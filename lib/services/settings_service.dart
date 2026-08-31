import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'database_service.dart';

/// Global user settings and preferences service
class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  static const String _tableName = 'app_settings';

  // Observable properties
  final ValueNotifier<String> activeLogoNotifier =
      ValueNotifier<String>('assets/images/logo.png');
  final ValueNotifier<bool> autoSaveToGalleryNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<String> preferredStreamingNotifier =
      ValueNotifier<String>('spotify');

  String get activeLogo => activeLogoNotifier.value;
  bool get autoSaveToGallery => autoSaveToGalleryNotifier.value;
  String get preferredStreaming => preferredStreamingNotifier.value;

  /// Initialize and load saved settings from SQLite
  Future<void> init() async {
    try {
      final db = await DatabaseService.database;
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_tableName (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');

      final rows = await db.query(_tableName);
      for (final row in rows) {
        final key = row['key'] as String;
        final value = row['value'] as String;
        if (key == 'active_logo') {
          activeLogoNotifier.value = value;
        } else if (key == 'auto_save_gallery') {
          autoSaveToGalleryNotifier.value = value == '1';
        } else if (key == 'preferred_streaming') {
          preferredStreamingNotifier.value = value;
        }
      }
    } catch (e) {
      debugPrint('[SettingsService] init error: $e');
    }
  }

  /// Switch the active logo between Psyduck and Music logo
  Future<void> setActiveLogo(String logoPath) async {
    activeLogoNotifier.value = logoPath;
    await _setValue('active_logo', logoPath);
  }

  Future<void> setAutoSaveToGallery(bool value) async {
    autoSaveToGalleryNotifier.value = value;
    await _setValue('auto_save_gallery', value ? '1' : '0');
  }

  Future<void> setPreferredStreaming(String service) async {
    preferredStreamingNotifier.value = service;
    await _setValue('preferred_streaming', service);
  }

  Future<void> _setValue(String key, String value) async {
    try {
      final db = await DatabaseService.database;
      await db.insert(
        _tableName,
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('[SettingsService] save error: $e');
    }
  }
}
