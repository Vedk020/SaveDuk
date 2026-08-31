import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/constants.dart';
import '../models/download_item.dart';
import '../services/database_service.dart';
import '../services/download_service.dart';
import '../services/gallery_service.dart';
import '../services/media_muxer_service.dart';
import '../services/on_device_extractor_service.dart';
import '../services/url_parser_service.dart';
import '../widgets/download_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/progress_indicator.dart' as custom;
import 'package:uuid/uuid.dart';
import '../services/share_handler_service.dart';
import '../services/background_download_service.dart';
import 'dart:async';

/// Home screen — main interface with URL paste + download list
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final TextEditingController _urlController = TextEditingController();
  final OnDeviceExtractorService _extractorService = OnDeviceExtractorService();
  final DownloadService _downloadService = DownloadService();
  final MediaMuxerService _mediaMuxer = MediaMuxerService();
  List<DownloadItem> _downloads = [];
  bool _isLoading = true;

  StreamSubscription<String>? _shareSubscription;

  @override
  void initState() {
    super.initState();
    _loadDownloads();
    _checkCookies();
    // Listen for shared URLs from the ShareHandlerService
    _shareSubscription = ShareHandlerService.instance.sharedUrlStream.listen((
      url,
    ) {
      _processUrl(url);
    });
    // Check for any pending URL from cold start
    final pending = ShareHandlerService.instance.consumePending();
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _processUrl(pending);
      });
    }
  }

  Future<void> _loadDownloads() async {
    setState(() => _isLoading = true);
    try {
      final downloads = await DatabaseService.getAll();
      setState(() {
        _downloads = downloads;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _processUrl(String text) async {
    final extractedUrl = UrlParserService.extractUrl(text);
    if (extractedUrl == null) {
      _showSnackbar('No valid URL found', isError: true);
      return;
    }

    final cleanUrl = UrlParserService.cleanUrl(extractedUrl);
    final platform = UrlParserService.detectPlatform(cleanUrl);

    if (platform == null) {
      _showSnackbar(
        'Unsupported platform. Supported: YouTube, Instagram, Twitter, Facebook, Pinterest',
        isError: true,
      );
      return;
    }

    // Create download item
    final item = DownloadItem(
      id: const Uuid().v4(),
      originalUrl: cleanUrl,
      platform: platform.id,
      createdAt: DateTime.now(),
      status: DownloadStatus.fetching,
    );

    // Add to list and DB
    setState(() {
      _downloads.insert(0, item);
    });
    await DatabaseService.insert(item);

    // Clear input
    _urlController.clear();

    // Start download pipeline
    _startDownload(item);
  }

  Future<void> _startDownload(DownloadItem item) async {
    var current = item;
    try {
      // Step 1: Select direct streams with the embedded Android extractor.
      current = current.copyWith(status: DownloadStatus.fetching);
      _updateItem(current);

      final result = await _extractorService.extract(item.originalUrl);

      if (!result.isSuccess) {
        final errorMsg = result.error ?? 'Failed to get download link';
        _updateItem(
          current.copyWith(
            status: DownloadStatus.failed,
            errorMessage: errorMsg,
          ),
        );
        final isAuthError =
            errorMsg.toLowerCase().contains('cookie') ||
            errorMsg.toLowerCase().contains('authentication') ||
            errorMsg.toLowerCase().contains('login');
        if (isAuthError) {
          _showSnackbar(
            errorMsg,
            isError: true,
            onAction: _showCookieModal,
            actionLabel: 'COOKIES',
          );
        }
        return;
      }

      // Step 2: Download the direct stream(s) before their short-lived URLs
      // expire. Separate streams are merged locally after both finish.
      current = current.copyWith(
        status: DownloadStatus.downloading,
        filename: result.filename,
        title: result.title,
      );
      _updateItem(current);

      // Start foreground service to keep downloads alive in background
      await BackgroundDownloadService.notifyDownloadStarted(
        title: result.title,
      );

      final videoPath = await _downloadService.downloadFile(
        url: result.video.url,
        downloadId: '${item.id}-video',
        filename: _streamFilename(
          result.filename,
          result.video.extension,
          'video',
        ),
        headers: result.video.headers,
        onProgress: (progress) {
          final scaledProgress = result.needsMuxing ? progress * 0.8 : progress;
          current = current.copyWith(
            status: DownloadStatus.downloading,
            progress: scaledProgress,
          );
          _updateItem(current);
          BackgroundDownloadService.updateProgress(
            title: result.title,
            progress: (scaledProgress * 100).toInt(),
          );
        },
        onFileSize: (bytes) {
          current = current.copyWith(fileSize: bytes);
          _updateItem(current);
        },
      );

      String localPath = videoPath;
      if (result.audio != null) {
        final audio = result.audio!;
        final audioPath = await _downloadService.downloadFile(
          url: audio.url,
          downloadId: '${item.id}-audio',
          filename: _streamFilename(result.filename, audio.extension, 'audio'),
          headers: audio.headers,
          onProgress: (progress) {
            current = current.copyWith(
              status: DownloadStatus.downloading,
              progress: 0.8 + (progress * 0.15),
            );
            _updateItem(current);
          },
          onFileSize: (_) {},
        );
        current = current.copyWith(
          status: DownloadStatus.saving,
          progress: 0.95,
        );
        _updateItem(current);
        localPath = await _mediaMuxer.merge(
          videoPath: videoPath,
          audioPath: audioPath,
          downloadId: item.id,
          filename: result.filename,
        );
      }

      // Step 3: Save the completed local file to the gallery.
      current = current.copyWith(status: DownloadStatus.saving);
      _updateItem(current);

      await GalleryService.saveToGallery(localPath);

      // Step 4: Mark complete
      current = current.copyWith(
        status: DownloadStatus.completed,
        progress: 1.0,
        localPath: localPath,
      );
      _updateItem(current);

      _showSnackbar('Saved to gallery ✓');
      await BackgroundDownloadService.notifyDownloadFinished();
    } catch (e) {
      _updateItem(
        current.copyWith(
          status: DownloadStatus.failed,
          errorMessage: e.toString(),
        ),
      );
      await BackgroundDownloadService.notifyDownloadFinished();
      _showSnackbar('Download failed', isError: true);
    }
  }

  void _updateItem(DownloadItem updated) {
    setState(() {
      final index = _downloads.indexWhere((d) => d.id == updated.id);
      if (index >= 0) {
        _downloads[index] = updated;
      }
    });
    DatabaseService.update(updated);
  }

  void _retryDownload(DownloadItem item) {
    final retried = item.copyWith(
      status: DownloadStatus.fetching,
      progress: 0.0,
      clearError: true,
    );
    _updateItem(retried);
    _startDownload(retried);
  }

  void _cancelDownload(DownloadItem item) {
    _downloadService.cancelDownload(item.id);
    _downloadService.cancelDownload('${item.id}-video');
    _downloadService.cancelDownload('${item.id}-audio');
    _mediaMuxer.cancel();
    _updateItem(
      item.copyWith(status: DownloadStatus.failed, errorMessage: 'Cancelled'),
    );
  }

  Future<void> _deleteDownload(DownloadItem item) async {
    if (item.localPath != null) {
      await GalleryService.deleteLocalFile(item.localPath!);
    }
    await DatabaseService.delete(item.id);
    setState(() {
      _downloads.removeWhere((d) => d.id == item.id);
    });
    _showSnackbar('Removed');
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      _urlController.text = data.text!;
      _processUrl(data.text!);
    } else {
      _showSnackbar('Clipboard is empty', isError: true);
    }
  }

  bool _hasCookies = false;

  Future<void> _checkCookies() async {
    final hasCookies = await _extractorService.hasCookies();
    if (mounted) {
      setState(() => _hasCookies = hasCookies);
    }
  }

  void _showCookieModal() {
    final cookieInputController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(modalContext).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.vpn_key_outlined,
                        size: 20,
                        color: AppColors.textPrimary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'SESSION COOKIES',
                        style: Theme.of(
                          modalContext,
                        ).textTheme.titleLarge?.copyWith(fontSize: 16),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _hasCookies
                              ? AppColors.surfaceLight
                              : AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _hasCookies
                                    ? Colors.greenAccent
                                    : AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _hasCookies ? 'ACTIVE' : 'NOT SET',
                              style: Theme.of(modalContext).textTheme.bodySmall
                                  ?.copyWith(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Instagram & Facebook require authentication for many posts. Paste your session cookie string (e.g. sessionid=... or Netscape format) from your browser.',
                    style: Theme.of(
                      modalContext,
                    ).textTheme.bodySmall?.copyWith(height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: cookieInputController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Paste sessionid=... or cookie export here',
                      hintStyle: Theme.of(modalContext).textTheme.bodySmall,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.content_paste, size: 18),
                        tooltip: 'Paste from clipboard',
                        onPressed: () async {
                          final data = await Clipboard.getData(
                            Clipboard.kTextPlain,
                          );
                          if (data?.text != null) {
                            cookieInputController.text = data!.text!;
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (_hasCookies) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              await _extractorService.clearCookies();
                              await _checkCookies();
                              setModalState(() {});
                              if (modalContext.mounted) {
                                Navigator.pop(modalContext);
                              }
                              _showSnackbar('Cookies cleared');
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              side: const BorderSide(color: AppColors.line),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Clear'),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () async {
                            final text = cookieInputController.text.trim();
                            if (text.isEmpty) {
                              _showSnackbar(
                                'Please paste a cookie string',
                                isError: true,
                              );
                              return;
                            }
                            final success = await _extractorService.setCookies(
                              text,
                            );
                            if (success) {
                              await _checkCookies();
                              if (modalContext.mounted) {
                                Navigator.pop(modalContext);
                              }
                              _showSnackbar('Cookies saved ✓');
                            } else {
                              _showSnackbar(
                                'Failed to save cookies',
                                isError: true,
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.textPrimary,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            'Save Cookies',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showSnackbar(
    String message, {
    bool isError = false,
    VoidCallback? onAction,
    String? actionLabel,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.surface,
        duration: Duration(seconds: isError ? 4 : 2),
        action: actionLabel != null && onAction != null
            ? SnackBarAction(
                label: actionLabel,
                textColor: Colors.black,
                backgroundColor: AppColors.textPrimary,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }

  String _streamFilename(String finalFilename, String extension, String kind) {
    final basename = finalFilename.replaceFirst(RegExp(r'\.mp4$'), '');
    final safeExtension = extension.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    return '${[basename, kind].join('_')}.${safeExtension.isEmpty ? 'mp4' : safeExtension}';
  }

  @override
  void dispose() {
    _shareSubscription?.cancel();
    _urlController.dispose();
    _downloadService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeDownloads = _downloads
        .where(
          (d) =>
              d.status == DownloadStatus.fetching ||
              d.status == DownloadStatus.downloading ||
              d.status == DownloadStatus.saving,
        )
        .toList();
    final recentDownloads = _downloads
        .where(
          (d) =>
              d.status == DownloadStatus.completed ||
              d.status == DownloadStatus.failed,
        )
        .toList();

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // App Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.line, width: 1),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(7),
                            child: Image.asset(
                              'assets/images/logo.png',
                              width: 38,
                              height: 38,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'SAVE//DUK',
                          style: Theme.of(context).textTheme.displayMedium
                              ?.copyWith(letterSpacing: -1.5),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: _showCookieModal,
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceLight,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.line),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.vpn_key_outlined,
                                  size: 13,
                                  color: _hasCookies
                                      ? Colors.greenAccent
                                      : AppColors.textMuted,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _hasCookies ? 'COOKIES ✓' : 'COOKIES',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        fontSize: 10,
                                        color: _hasCookies
                                            ? Colors.greenAccent
                                            : AppColors.textMuted,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '01',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'PASTE A LINK. KEEP THE FILE.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),

                    // URL Input
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _urlController,
                            decoration: const InputDecoration(
                              hintText: 'Paste video link here…',
                              prefixIcon: Icon(
                                Icons.link_rounded,
                                color: AppColors.textMuted,
                              ),
                            ),
                            onSubmitted: (text) {
                              if (text.isNotEmpty) _processUrl(text);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Paste button
                        _MonoButton(
                          icon: Icons.content_paste_rounded,
                          onTap: _pasteFromClipboard,
                          tooltip: 'Paste',
                          primary: false,
                        ),
                        const SizedBox(width: 8),
                        // Download button
                        _MonoButton(
                          icon: Icons.arrow_downward_rounded,
                          onTap: () {
                            final text = _urlController.text.trim();
                            if (text.isNotEmpty) _processUrl(text);
                          },
                          tooltip: 'Download',
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // Supported platforms row
                    _SupportedPlatformsRow(),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // Active Downloads Section
            if (activeDownloads.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const custom.GradientProgressIndicator(
                        progress: -1,
                        size: 18,
                        strokeWidth: 2,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'IN PROGRESS',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final item = activeDownloads[index];
                  return DownloadCard(
                    item: item,
                    onCancel: () => _cancelDownload(item),
                  );
                }, childCount: activeDownloads.length),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],

            // Recent Downloads Section
            if (recentDownloads.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'RECENT FILES',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final item = recentDownloads[index];
                  return Dismissible(
                    key: Key(item.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.delete_outline,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    onDismissed: (_) => _deleteDownload(item),
                    child: DownloadCard(
                      item: item,
                      onRetry: () => _retryDownload(item),
                      onDelete: () => _deleteDownload(item),
                    ),
                  );
                }, childCount: recentDownloads.length),
              ),
            ],

            // Empty State
            if (_downloads.isEmpty && !_isLoading)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.download_rounded,
                  title: 'No downloads yet',
                  subtitle:
                      'Share a video link from YouTube, Instagram,\nTwitter, Facebook, or Pinterest',
                  action: OutlinedButton.icon(
                    onPressed: _pasteFromClipboard,
                    icon: const Icon(Icons.content_paste_rounded),
                    label: const Text('Paste from clipboard'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.textPrimary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
              ),

            // Loading
            if (_isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: custom.GradientProgressIndicator(
                    progress: -1,
                    size: 48,
                    strokeWidth: 3,
                  ),
                ),
              ),

            // Bottom padding
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
    );
  }
}

class _MonoButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool primary;

  const _MonoButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.primary = true,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: primary ? AppColors.textPrimary : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.line),
          ),
          child: Icon(
            icon,
            color: primary ? Colors.black : AppColors.textPrimary,
            size: 21,
          ),
        ),
      ),
    );
  }
}

/// Row of supported platform icons
class _SupportedPlatformsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('SUPPORTED — ', style: Theme.of(context).textTheme.bodySmall),
        ...AppPlatforms.all.map(
          (p) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Tooltip(
              message: p.name,
              child: Icon(p.icon, color: AppColors.textSecondary, size: 16),
            ),
          ),
        ),
      ],
    );
  }
}
