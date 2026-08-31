import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../config/constants.dart';
import '../services/on_device_extractor_service.dart';
import '../services/settings_service.dart';
import 'about_screen.dart';

/// Settings screen for configuring app logo, cookies, default streaming, and storage
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final OnDeviceExtractorService _extractor = OnDeviceExtractorService();
  final SettingsService _settings = SettingsService.instance;

  bool _hasCookies = false;
  String _cacheSizeText = 'Calculating…';

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final hasCookies = await _extractor.hasCookies();
    if (mounted) setState(() => _hasCookies = hasCookies);
    _calculateCacheSize();
  }

  Future<void> _calculateCacheSize() async {
    try {
      final tempDir = await getTemporaryDirectory();
      int totalBytes = 0;
      if (await tempDir.exists()) {
        final files = tempDir.listSync(recursive: true, followLinks: false);
        for (final file in files) {
          if (file is File) {
            totalBytes += await file.length();
          }
        }
      }
      final mb = totalBytes / (1024 * 1024);
      if (mounted) {
        setState(() => _cacheSizeText = '${mb.toStringAsFixed(1)} MB');
      }
    } catch (_) {
      if (mounted) setState(() => _cacheSizeText = '0.0 MB');
    }
  }

  Future<void> _clearCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        final files = tempDir.listSync(recursive: true, followLinks: false);
        for (final file in files) {
          if (file is File) {
            try {
              await file.delete();
            } catch (_) {}
          }
        }
      }
      await _calculateCacheSize();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cache cleared ✓'),
            backgroundColor: AppColors.surfaceLight,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clearing cache: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showCookieModal() {
    final cookieInputController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
                      const Icon(Icons.vpn_key_outlined, size: 20, color: AppColors.textPrimary),
                      const SizedBox(width: 8),
                      Text(
                        'SESSION COOKIES',
                        style: Theme.of(modalContext).textTheme.titleLarge?.copyWith(fontSize: 16),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _hasCookies ? AppColors.surfaceLight : AppColors.cardBackground,
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
                                color: _hasCookies ? Colors.greenAccent : AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _hasCookies ? 'ACTIVE' : 'NOT SET',
                              style: Theme.of(modalContext).textTheme.bodySmall?.copyWith(
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
                    'Paste your session cookie string (e.g. sessionid=... or Netscape format) to enable authenticated downloads from Instagram & Facebook.',
                    style: Theme.of(modalContext).textTheme.bodySmall?.copyWith(height: 1.4),
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
                          final data = await Clipboard.getData(Clipboard.kTextPlain);
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
                              await _extractor.clearCookies();
                              await _loadState();
                              setModalState(() {});
                              if (modalContext.mounted) {
                                Navigator.pop(modalContext);
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              side: const BorderSide(color: AppColors.line),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                            if (text.isEmpty) return;
                            final success = await _extractor.setCookies(text);
                            if (success) {
                              await _loadState();
                              if (modalContext.mounted) {
                                Navigator.pop(modalContext);
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.textPrimary,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Save Cookies', style: TextStyle(fontWeight: FontWeight.bold)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'SETTINGS',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            // Section 1: App Logo Selector
            _buildSectionHeader('APP LOGO THEME'),
            const SizedBox(height: 10),
            ValueListenableBuilder<String>(
              valueListenable: _settings.activeLogoNotifier,
              builder: (context, activeLogo, _) {
                return Row(
                  children: [
                    Expanded(
                      child: _buildLogoCard(
                        title: 'SaveDuk Classic',
                        subtitle: 'Psyduck Icon',
                        assetPath: 'assets/images/logo.png',
                        isSelected: activeLogo == 'assets/images/logo.png',
                        onTap: () {
                          HapticFeedback.selectionClick();
                          _settings.setActiveLogo('assets/images/logo.png');
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildLogoCard(
                        title: 'SaveDuk Music',
                        subtitle: 'Neon Wave Icon',
                        assetPath: 'assets/images/logo_music.png',
                        isSelected: activeLogo == 'assets/images/logo_music.png',
                        onTap: () {
                          HapticFeedback.selectionClick();
                          _settings.setActiveLogo('assets/images/logo_music.png');
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),

            // Section 2: Authentication
            _buildSectionHeader('AUTHENTICATION & SESSIONS'),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.line),
              ),
              child: ListTile(
                leading: const Icon(Icons.vpn_key_outlined, color: AppColors.textPrimary),
                title: const Text('Instagram / Facebook Cookies', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  _hasCookies ? 'Session cookies active' : 'Not configured (login required for reels)',
                  style: TextStyle(
                    fontSize: 12,
                    color: _hasCookies ? Colors.greenAccent : AppColors.textMuted,
                  ),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Text(
                    _hasCookies ? 'EDIT' : 'ADD',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                ),
                onTap: _showCookieModal,
              ),
            ),
            const SizedBox(height: 24),

            // Section 3: Downloads & Gallery
            _buildSectionHeader('DOWNLOAD PREFERENCES'),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: _settings.autoSaveToGalleryNotifier,
                    builder: (context, autoSave, _) {
                      return SwitchListTile(
                        activeThumbColor: AppColors.textPrimary,
                        activeTrackColor: Colors.greenAccent.withValues(alpha: 0.5),
                        title: const Text('Auto-Save to Gallery', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text(
                          'Save completed videos straight to device media gallery',
                          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                        value: autoSave,
                        onChanged: (val) {
                          HapticFeedback.lightImpact();
                          _settings.setAutoSaveToGallery(val);
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Section 4: Cache & Storage
            _buildSectionHeader('STORAGE & CACHE'),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.line),
              ),
              child: ListTile(
                leading: const Icon(Icons.cleaning_services_outlined, color: AppColors.textPrimary),
                title: const Text('Temporary Media Cache', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('Temporary audio/video chunks: $_cacheSizeText', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                trailing: TextButton(
                  onPressed: _clearCache,
                  child: const Text('CLEAR', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Section 5: About & Info
            _buildSectionHeader('SYSTEM & ABOUT'),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.line),
              ),
              child: ListTile(
                leading: const Icon(Icons.info_outline_rounded, color: AppColors.textPrimary),
                title: const Text('About SaveDuk', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('On-device engine, architecture, developer info', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen()));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 1.2,
        fontWeight: FontWeight.bold,
        color: AppColors.textMuted,
      ),
    );
  }

  Widget _buildLogoCard({
    required String title,
    required String subtitle,
    required String assetPath,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.surfaceLight : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.greenAccent : AppColors.line,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(assetPath, width: 44, height: 44, fit: BoxFit.cover),
                ),
                const Spacer(),
                Icon(
                  isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: isSelected ? Colors.greenAccent : AppColors.textMuted,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}
