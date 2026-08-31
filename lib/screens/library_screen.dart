import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import '../config/constants.dart';
import '../models/download_item.dart';
import '../services/database_service.dart';
import '../services/gallery_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/platform_badge.dart';
import 'about_screen.dart';
import 'settings_screen.dart';

/// Library screen — grid view of all downloaded media
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<DownloadItem> _downloads = [];
  String _selectedPlatform = 'all';
  bool _isLoading = true;

  final List<Map<String, dynamic>> _filters = [
    {'id': 'all', 'label': 'All', 'icon': Icons.grid_view_rounded},
    ...AppPlatforms.all.map(
      (p) => {'id': p.id, 'label': p.name, 'icon': p.icon, 'color': p.color},
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadDownloads();
  }

  Future<void> _loadDownloads() async {
    setState(() => _isLoading = true);
    try {
      List<DownloadItem> downloads;
      if (_selectedPlatform == 'all') {
        downloads = await DatabaseService.getCompleted();
      } else {
        final all = await DatabaseService.getByPlatform(_selectedPlatform);
        downloads = all
            .where((d) => d.status == DownloadStatus.completed)
            .toList();
      }
      setState(() {
        _downloads = downloads;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _openVideo(DownloadItem item) {
    if (item.localPath != null) {
      OpenFile.open(item.localPath!);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Video file not found — it\'s saved in your gallery'),
          backgroundColor: AppColors.surface,
        ),
      );
    }
  }

  void _shareVideo(DownloadItem item) {
    Share.share(
      item.originalUrl,
      subject: item.title ?? 'Check out this video',
    );
  }

  Future<void> _deleteDownload(DownloadItem item) async {
    if (item.localPath != null) {
      await GalleryService.deleteLocalFile(item.localPath!);
    }
    await DatabaseService.delete(item.id);
    _loadDownloads();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Removed from library'),
          backgroundColor: AppColors.surface,
        ),
      );
    }
  }

  void _showItemOptions(DownloadItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.textMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Item info
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    PlatformBadge(platformId: item.platform, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title ?? 'Video',
                            style: Theme.of(context).textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${item.fileSizeText} • ${DateFormat.yMMMd().format(item.createdAt)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(color: AppColors.cardBackground, height: 1),
              ListTile(
                leading: const Icon(
                  Icons.play_circle_outline,
                  color: AppColors.textPrimary,
                ),
                title: const Text('Open in Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _openVideo(item);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.share_rounded,
                  color: AppColors.textPrimary,
                ),
                title: const Text('Share Link'),
                onTap: () {
                  Navigator.pop(context);
                  _shareVideo(item);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: AppColors.error,
                ),
                title: const Text('Remove from Library'),
                onTap: () {
                  Navigator.pop(context);
                  _deleteDownload(item);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onLongPress: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AboutScreen()),
                      );
                    },
                    child: Text(
                      'SAVED//GALLERY',
                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                            fontSize: 22,
                            letterSpacing: -1.0,
                          ),
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      );
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: const Icon(
                        Icons.tune_rounded,
                        size: 16,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '${_downloads.length} video${_downloads.length != 1 ? 's' : ''} saved to gallery',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 16),

            // Filter chips
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _filters.length,
                itemBuilder: (context, index) {
                  final filter = _filters[index];
                  final isSelected = _selectedPlatform == filter['id'];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: isSelected,
                      label: Text(
                        filter['label'] as String,
                        style: TextStyle(
                          color: isSelected
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      avatar: isSelected
                          ? null
                          : Icon(
                              filter['icon'] as IconData,
                              size: 16,
                              color:
                                  filter['color'] as Color? ??
                                  AppColors.textMuted,
                            ),
                      onSelected: (_) {
                        setState(() {
                          _selectedPlatform = filter['id'] as String;
                        });
                        _loadDownloads();
                      },
                      selectedColor: AppColors.textPrimary.withValues(
                        alpha: 0.15,
                      ),
                      checkmarkColor: AppColors.textPrimary,
                      side: BorderSide(
                        color: isSelected
                            ? AppColors.textPrimary.withValues(alpha: 0.5)
                            : AppColors.line,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),

            // Grid
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.textPrimary,
                      ),
                    )
                  : _downloads.isEmpty
                  ? EmptyState(
                      icon: Icons.video_library_rounded,
                      title: _selectedPlatform == 'all'
                          ? 'No downloads yet'
                          : 'No ${_filters.firstWhere((f) => f['id'] == _selectedPlatform)['label']} downloads',
                      subtitle: 'Your saved videos will appear here',
                    )
                  : RefreshIndicator(
                      onRefresh: _loadDownloads,
                      color: AppColors.textPrimary,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _downloads.length,
                        itemBuilder: (context, index) {
                          final item = _downloads[index];
                          return _LibraryCard(
                            item: item,
                            onTap: () => _openVideo(item),
                            onLongPress: () => _showItemOptions(item),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Library list card
class _LibraryCard extends StatelessWidget {
  final DownloadItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _LibraryCard({
    required this.item,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                // Thumbnail placeholder
                Container(
                  width: 72,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.videocam_rounded,
                        color: _platformColor.withValues(alpha: 0.5),
                        size: 24,
                      ),
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Icon(
                            _platformIcon,
                            color: _platformColor,
                            size: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title ?? item.filename ?? _platformName,
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(_platformIcon, color: _platformColor, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            _platformName,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: _platformColor),
                          ),
                          if (item.fileSize != null) ...[
                            const Text(
                              ' • ',
                              style: TextStyle(color: AppColors.textMuted),
                            ),
                            Text(
                              item.fileSizeText,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                          const Spacer(),
                          Text(
                            DateFormat.MMMd().format(item.createdAt),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted.withValues(alpha: 0.5),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color get _platformColor {
    final platform = AppPlatforms.all.where((p) => p.id == item.platform);
    return platform.isNotEmpty ? platform.first.color : AppColors.textMuted;
  }

  IconData get _platformIcon {
    final platform = AppPlatforms.all.where((p) => p.id == item.platform);
    return platform.isNotEmpty ? platform.first.icon : Icons.link;
  }

  String get _platformName {
    final platform = AppPlatforms.all.where((p) => p.id == item.platform);
    return platform.isNotEmpty ? platform.first.name : 'Unknown';
  }
}
