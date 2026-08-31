import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Manages a lightweight Android foreground service notification
/// so that in-progress downloads survive backgrounding and screen-off.
///
/// On non-Android platforms this is a no-op.
class BackgroundDownloadService {
  static const MethodChannel _channel = MethodChannel('saveduk/foreground');

  /// Whether the foreground service is currently active.
  static bool _isRunning = false;
  static int _activeDownloads = 0;

  /// Call when a download starts.  Starts the foreground service
  /// notification if it is not already running.
  static Future<void> notifyDownloadStarted({
    required String title,
  }) async {
    _activeDownloads++;
    if (!Platform.isAndroid) return;
    if (_isRunning) {
      // Just update the notification text.
      await _updateNotification(title: title, progress: 0);
      return;
    }
    try {
      await _channel.invokeMethod('start', {
        'title': title,
      });
      _isRunning = true;
    } on MissingPluginException {
      // Native side not implemented yet — degrade gracefully.
      debugPrint('[BackgroundDownloadService] foreground channel unavailable');
    } catch (e) {
      debugPrint('[BackgroundDownloadService] start failed: $e');
    }
  }

  /// Update the ongoing notification with current progress.
  static Future<void> updateProgress({
    required String title,
    required int progress,
  }) async {
    if (!Platform.isAndroid || !_isRunning) return;
    await _updateNotification(title: title, progress: progress);
  }

  /// Call when a download finishes (success or failure).
  /// Stops the foreground service when the last active download completes.
  static Future<void> notifyDownloadFinished() async {
    _activeDownloads = (_activeDownloads - 1).clamp(0, 999);
    if (_activeDownloads > 0) return;
    if (!Platform.isAndroid || !_isRunning) return;
    try {
      await _channel.invokeMethod('stop');
      _isRunning = false;
    } on MissingPluginException {
      // Graceful fallback.
    } catch (e) {
      debugPrint('[BackgroundDownloadService] stop failed: $e');
    }
  }

  static Future<void> _updateNotification({
    required String title,
    required int progress,
  }) async {
    try {
      await _channel.invokeMethod('update', {
        'title': title,
        'progress': progress,
      });
    } on MissingPluginException {
      // Graceful fallback.
    } catch (_) {}
  }
}
