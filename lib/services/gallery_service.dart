import 'dart:io';
import 'package:gal/gal.dart';

/// Service for saving media files to the device gallery
class GalleryService {
  /// Request necessary permissions for gallery access
  static Future<bool> requestPermissions() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    if (await Gal.hasAccess(toAlbum: true)) return true;
    return Gal.requestAccess(toAlbum: true);
  }

  /// Save a video file to the device gallery
  /// Returns true on success
  static Future<bool> saveToGallery(String filePath) async {
    try {
      // Request permissions if needed
      final hasPermission = await requestPermissions();
      if (!hasPermission) {
        throw Exception('Gallery permission denied');
      }

      await Gal.putVideo(filePath, album: 'SaveDuk');
      return true;
    } catch (e) {
      throw Exception('Failed to save to gallery: $e');
    }
  }

  /// Delete the app's private copy when its history item is removed.
  static Future<void> deleteLocalFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignore cleanup errors
    }
  }
}
