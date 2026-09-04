import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/constants.dart';

enum UpdateStatus {
  noUpdate,
  optionalUpdate,
  forceUpdate,
  checkFailed,
}

class UpdateCheckResult {
  final UpdateStatus status;
  final String currentVersion;
  final String latestVersion;
  final String? releaseNotes;
  final String downloadUrl;
  final bool isForceUpdate;
  final String? title;

  const UpdateCheckResult({
    required this.status,
    required this.currentVersion,
    required this.latestVersion,
    this.releaseNotes,
    required this.downloadUrl,
    required this.isForceUpdate,
    this.title,
  });

  bool get hasUpdate =>
      status == UpdateStatus.optionalUpdate || status == UpdateStatus.forceUpdate;
}

/// Service to check for application updates and prompt or force the user to update.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  /// Current app version (keep synced with pubspec.yaml version)
  static const String currentVersion = '1.0.0';
  static const int currentBuildNumber = 1;

  /// Default remote URL that hosts the version configuration JSON
  /// Users/Developers can host this file on GitHub Raw, Firebase, or their own domain.
  static const String remoteVersionUrl =
      'https://raw.githubusercontent.com/Vedk020/SaveDuk/main/version.json';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 6),
      headers: {
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
      },
    ),
  );

  /// Check remote version endpoint for updates
  Future<UpdateCheckResult> checkForUpdates({String? customUrl}) async {
    final url = customUrl ?? remoteVersionUrl;
    try {
      final response = await _dio.get<String>(
        url,
        queryParameters: {'t': DateTime.now().millisecondsSinceEpoch.toString()},
      );

      if (response.statusCode == 200 && response.data != null) {
        final Map<String, dynamic> data =
            response.data is Map ? (response.data as Map).cast<String, dynamic>() : jsonDecode(response.data!);

        final latestVersion = data['latest_version']?.toString() ?? currentVersion;
        final latestBuild = (data['latest_build'] as num?)?.toInt() ?? currentBuildNumber;
        final minRequiredBuild = (data['min_required_build'] as num?)?.toInt() ?? 0;
        final forceFlag = data['force_update'] == true;
        final downloadUrl = data['download_url']?.toString() ??
            'https://github.com/Vedk020/SaveDuk/releases/latest';
        final notes = data['release_notes']?.toString();
        final title = data['title']?.toString();

        // Determine if update is needed
        final isOutdated = _compareVersions(latestVersion, currentVersion) > 0 ||
            latestBuild > currentBuildNumber;

        if (!isOutdated) {
          return UpdateCheckResult(
            status: UpdateStatus.noUpdate,
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            downloadUrl: downloadUrl,
            isForceUpdate: false,
          );
        }

        // Check if forced
        final isForced = forceFlag || currentBuildNumber < minRequiredBuild;

        return UpdateCheckResult(
          status: isForced ? UpdateStatus.forceUpdate : UpdateStatus.optionalUpdate,
          currentVersion: currentVersion,
          latestVersion: latestVersion,
          releaseNotes: notes,
          downloadUrl: downloadUrl,
          isForceUpdate: isForced,
          title: title,
        );
      }
    } catch (e) {
      debugPrint('[UpdateService] Update check failed: $e');
    }

    return const UpdateCheckResult(
      status: UpdateStatus.checkFailed,
      currentVersion: currentVersion,
      latestVersion: currentVersion,
      downloadUrl: 'https://github.com/Vedk020/SaveDuk/releases/latest',
      isForceUpdate: false,
    );
  }

  /// Show the update dialog (blocking if forceUpdate is true)
  Future<void> showUpdateDialog(BuildContext context, UpdateCheckResult result) {
    return showDialog<void>(
      context: context,
      barrierDismissible: !result.isForceUpdate,
      builder: (dialogCtx) {
        return PopScope(
          canPop: !result.isForceUpdate,
          child: AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: result.isForceUpdate ? Colors.redAccent.withValues(alpha: 0.5) : AppColors.line,
                width: 1.2,
              ),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: result.isForceUpdate
                        ? Colors.redAccent.withValues(alpha: 0.15)
                        : Colors.greenAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    result.isForceUpdate ? Icons.system_update_rounded : Icons.rocket_launch_rounded,
                    color: result.isForceUpdate ? Colors.redAccent : Colors.greenAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.isForceUpdate ? 'UPDATE REQUIRED' : 'UPDATE AVAILABLE',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'v${result.currentVersion} → v${result.latestVersion}',
                        style: TextStyle(
                          fontSize: 12,
                          color: result.isForceUpdate ? Colors.redAccent : Colors.greenAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.title != null) ...[
                  Text(
                    result.title!,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  result.isForceUpdate
                      ? 'A critical update has been published. To continue using SaveDuk with active extractor engines and fixes, please update to the latest release.'
                      : 'A new version of SaveDuk is available with new features and performance improvements.',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                ),
                if (result.releaseNotes != null && result.releaseNotes!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "WHAT'S NEW:",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          result.releaseNotes!,
                          style: const TextStyle(fontSize: 11, color: AppColors.textPrimary, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              if (!result.isForceUpdate)
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('LATER', style: TextStyle(color: AppColors.textMuted)),
                ),
              ElevatedButton.icon(
                onPressed: () async {
                  HapticFeedback.mediumImpact();
                  final uri = Uri.parse(result.downloadUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.download_rounded, size: 18, color: Colors.black),
                label: const Text('UPDATE NOW', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: result.isForceUpdate ? Colors.redAccent : AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Simple semver compare (returns >0 if v1 > v2, <0 if v1 < v2, 0 if equal)
  int _compareVersions(String v1, String v2) {
    try {
      final parts1 = v1.split('.').map(int.parse).toList();
      final parts2 = v2.split('.').map(int.parse).toList();
      final len = parts1.length > parts2.length ? parts1.length : parts2.length;

      for (int i = 0; i < len; i++) {
        final p1 = i < parts1.length ? parts1[i] : 0;
        final p2 = i < parts2.length ? parts2[i] : 0;
        if (p1 != p2) return p1.compareTo(p2);
      }
      return 0;
    } catch (_) {
      return v1.compareTo(v2);
    }
  }
}
