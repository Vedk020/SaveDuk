import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/download_item.dart';

/// SQLite database service for download history
class DatabaseService {
  static Database? _database;
  static const String _tableName = 'downloads';

  /// Get database instance (singleton)
  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'saveduk.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id TEXT PRIMARY KEY,
            originalUrl TEXT NOT NULL,
            platform TEXT NOT NULL,
            title TEXT,
            thumbnailUrl TEXT,
            localPath TEXT,
            filename TEXT,
            status INTEGER NOT NULL DEFAULT 0,
            progress REAL NOT NULL DEFAULT 0.0,
            createdAt TEXT NOT NULL,
            fileSize INTEGER,
            errorMessage TEXT
          )
        ''');
      },
    );
  }

  /// Insert a new download
  static Future<void> insert(DownloadItem item) async {
    final db = await database;
    await db.insert(
      _tableName,
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Update an existing download
  static Future<void> update(DownloadItem item) async {
    final db = await database;
    await db.update(
      _tableName,
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  /// Delete a download by ID
  static Future<void> delete(String id) async {
    final db = await database;
    await db.delete(_tableName, where: 'id = ?', whereArgs: [id]);
  }

  /// Get all downloads, most recent first
  static Future<List<DownloadItem>> getAll() async {
    final db = await database;
    final maps = await db.query(_tableName, orderBy: 'createdAt DESC');
    return maps.map((m) => DownloadItem.fromMap(m)).toList();
  }

  /// Get downloads filtered by platform
  static Future<List<DownloadItem>> getByPlatform(String platform) async {
    final db = await database;
    final maps = await db.query(
      _tableName,
      where: 'platform = ?',
      whereArgs: [platform],
      orderBy: 'createdAt DESC',
    );
    return maps.map((m) => DownloadItem.fromMap(m)).toList();
  }

  /// Get only completed downloads
  static Future<List<DownloadItem>> getCompleted() async {
    final db = await database;
    final maps = await db.query(
      _tableName,
      where: 'status = ?',
      whereArgs: [DownloadStatus.completed.index],
      orderBy: 'createdAt DESC',
    );
    return maps.map((m) => DownloadItem.fromMap(m)).toList();
  }

  /// Get a single download by ID
  static Future<DownloadItem?> getById(String id) async {
    final db = await database;
    final maps = await db.query(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return DownloadItem.fromMap(maps.first);
  }

  /// Get count of downloads
  static Future<int> getCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_tableName',
    );
    return result.first['count'] as int;
  }

  /// Clear all download history
  static Future<void> clearAll() async {
    final db = await database;
    await db.delete(_tableName);
  }
}
