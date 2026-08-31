import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/music_track.dart';
import 'database_service.dart';

/// Database and local file storage for music tracks
class MusicStorageService {
  static const String _tableName = 'music_tracks';
  static final Dio _dio = Dio();

  /// Initialize table in SQLite
  static Future<void> ensureTableExists() async {
    final db = await DatabaseService.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        album TEXT,
        artworkUrl TEXT,
        streamUrl TEXT,
        localPath TEXT,
        originalMediaUrl TEXT,
        durationSeconds INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        isFavorite INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// Insert or update a track
  static Future<void> saveTrack(MusicTrack track) async {
    await ensureTableExists();
    final db = await DatabaseService.database;
    await db.insert(
      _tableName,
      track.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Download audio stream and save track locally
  static Future<MusicTrack> downloadAndSaveTrack(
    MusicTrack track, {
    String? audioUrl,
    void Function(double progress)? onProgress,
  }) async {
    await ensureTableExists();
    final urlToDownload = audioUrl ?? track.streamUrl;
    if (urlToDownload == null || urlToDownload.isEmpty) {
      throw Exception('No audio stream URL available for download');
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final musicDir = Directory(p.join(docsDir.path, 'music'));
    if (!await musicDir.exists()) {
      await musicDir.create(recursive: true);
    }

    final safeTitle = track.title.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final filePath = p.join(musicDir.path, '${track.id}_$safeTitle.m4a');

    await _dio.download(
      urlToDownload,
      filePath,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          onProgress?.call(received / total);
        }
      },
    );

    final updatedTrack = track.copyWith(
      localPath: filePath,
      streamUrl: urlToDownload,
    );

    await saveTrack(updatedTrack);
    return updatedTrack;
  }

  /// Get all saved tracks
  static Future<List<MusicTrack>> getAllTracks() async {
    await ensureTableExists();
    final db = await DatabaseService.database;
    final maps = await db.query(_tableName, orderBy: 'createdAt DESC');
    return maps.map((m) => MusicTrack.fromMap(m)).toList();
  }

  /// Get favorite tracks
  static Future<List<MusicTrack>> getFavoriteTracks() async {
    await ensureTableExists();
    final db = await DatabaseService.database;
    final maps = await db.query(
      _tableName,
      where: 'isFavorite = 1',
      orderBy: 'createdAt DESC',
    );
    return maps.map((m) => MusicTrack.fromMap(m)).toList();
  }

  /// Toggle favorite status
  static Future<void> toggleFavorite(String id, bool isFavorite) async {
    await ensureTableExists();
    final db = await DatabaseService.database;
    await db.update(
      _tableName,
      {'isFavorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete a track and its local file
  static Future<void> deleteTrack(MusicTrack track) async {
    await ensureTableExists();
    final db = await DatabaseService.database;
    await db.delete(_tableName, where: 'id = ?', whereArgs: [track.id]);

    if (track.localPath != null) {
      final file = File(track.localPath!);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
  }
}
