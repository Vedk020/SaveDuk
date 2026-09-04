import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/music_track.dart';
import 'database_service.dart';

/// Representation of a user or system music playlist
class MusicPlaylist {
  final String id;
  final String name;
  final DateTime createdAt;
  final String? coverUrl;
  final int trackCount;

  const MusicPlaylist({
    required this.id,
    required this.name,
    required this.createdAt,
    this.coverUrl,
    this.trackCount = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'coverUrl': coverUrl,
      };

  factory MusicPlaylist.fromMap(Map<String, dynamic> map, {int trackCount = 0}) =>
      MusicPlaylist(
        id: map['id'] as String,
        name: map['name'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
        coverUrl: map['coverUrl'] as String?,
        trackCount: trackCount,
      );
}

/// Database and local file storage for music tracks, playlists, and offline saves
class MusicStorageService {
  static const String _tableName = 'music_tracks';
  static const String _playlistsTable = 'music_playlists';
  static const String _playlistTracksTable = 'music_playlist_tracks';
  static final Dio _dio = Dio();

  /// Initialize tables in SQLite
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

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_playlistsTable (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        coverUrl TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_playlistTracksTable (
        playlistId TEXT NOT NULL,
        trackId TEXT NOT NULL,
        addedAt TEXT NOT NULL,
        PRIMARY KEY (playlistId, trackId)
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

  /// Get strictly offline tracks (saved to local disk and file exists)
  static Future<List<MusicTrack>> getOfflineTracks() async {
    await ensureTableExists();
    final all = await getAllTracks();
    final offline = <MusicTrack>[];
    for (final track in all) {
      if (track.localPath != null && File(track.localPath!).existsSync()) {
        offline.add(track);
      }
    }
    return offline;
  }

  /// Total size of all offline saved tracks in bytes
  static Future<int> getOfflineStorageSizeBytes() async {
    final offline = await getOfflineTracks();
    int total = 0;
    for (final track in offline) {
      if (track.localPath != null) {
        try {
          total += File(track.localPath!).lengthSync();
        } catch (_) {}
      }
    }
    return total;
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

  // ---------------------------------------------------------------------------
  // Playlist Management
  // ---------------------------------------------------------------------------

  /// Create a new playlist
  static Future<MusicPlaylist> createPlaylist(String name, {String? coverUrl}) async {
    await ensureTableExists();
    final playlist = MusicPlaylist(
      id: const Uuid().v4(),
      name: name.trim(),
      createdAt: DateTime.now(),
      coverUrl: coverUrl,
      trackCount: 0,
    );

    final db = await DatabaseService.database;
    await db.insert(_playlistsTable, playlist.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    return playlist;
  }

  /// Get all user playlists with track counts
  static Future<List<MusicPlaylist>> getAllPlaylists() async {
    await ensureTableExists();
    final db = await DatabaseService.database;
    final playlistRows = await db.query(_playlistsTable, orderBy: 'createdAt DESC');

    final playlists = <MusicPlaylist>[];
    for (final row in playlistRows) {
      final id = row['id'] as String;
      final countResult = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM $_playlistTracksTable WHERE playlistId = ?',
        [id],
      )) ?? 0;

      playlists.add(MusicPlaylist.fromMap(row, trackCount: countResult));
    }
    return playlists;
  }

  /// Add track to playlist
  static Future<void> addTrackToPlaylist(String playlistId, MusicTrack track) async {
    await ensureTableExists();
    await saveTrack(track); // ensure track exists in db

    final db = await DatabaseService.database;
    await db.insert(
      _playlistTracksTable,
      {
        'playlistId': playlistId,
        'trackId': track.id,
        'addedAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Get all tracks for a specific playlist
  static Future<List<MusicTrack>> getTracksForPlaylist(String playlistId) async {
    await ensureTableExists();
    final db = await DatabaseService.database;
    final results = await db.rawQuery('''
      SELECT t.* FROM $_tableName t
      INNER JOIN $_playlistTracksTable pt ON t.id = pt.trackId
      WHERE pt.playlistId = ?
      ORDER BY pt.addedAt DESC
    ''', [playlistId]);

    return results.map((m) => MusicTrack.fromMap(m)).toList();
  }

  /// Delete playlist
  static Future<void> deletePlaylist(String playlistId) async {
    await ensureTableExists();
    final db = await DatabaseService.database;
    await db.delete(_playlistTracksTable, where: 'playlistId = ?', whereArgs: [playlistId]);
    await db.delete(_playlistsTable, where: 'id = ?', whereArgs: [playlistId]);
  }
}
