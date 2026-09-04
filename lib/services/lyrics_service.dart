import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class LyricLine {
  final Duration timestamp;
  final String text;

  const LyricLine({
    required this.timestamp,
    required this.text,
  });

  @override
  String toString() => '[${timestamp.inSeconds}s]: $text';
}

class TrackLyrics {
  final String? plainLyrics;
  final List<LyricLine> syncedLyrics;
  final bool isSynced;

  const TrackLyrics({
    this.plainLyrics,
    this.syncedLyrics = const [],
    this.isSynced = false,
  });

  bool get hasLyrics => (isSynced && syncedLyrics.isNotEmpty) || (plainLyrics != null && plainLyrics!.isNotEmpty);
}

/// Service to fetch and parse synchronized LRC lyrics from community databases (LRCLIB)
class LyricsService {
  LyricsService._();
  static final LyricsService instance = LyricsService._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      headers: {
        'User-Agent': 'SaveDuk/1.0 (https://github.com/Vedk020/SaveDuk)',
      },
    ),
  );

  // In-memory cache
  final Map<String, TrackLyrics> _cache = {};

  /// Clean query strings (remove featured artists, tags, etc.)
  String _cleanTrackTitle(String title) {
    var clean = title.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '').trim();
    clean = clean.replaceAll(RegExp(r'\b(feat\.|ft\.|official|audio|video|lyrics)\b.*', caseSensitive: false), '').trim();
    return clean.isEmpty ? title : clean;
  }

  /// Fetch synchronized lyrics for a song
  Future<TrackLyrics?> getLyrics({
    required String title,
    required String artist,
    int? durationSeconds,
  }) async {
    final cleanTitle = _cleanTrackTitle(title);
    final cacheKey = '${cleanTitle.toLowerCase()}::${artist.toLowerCase()}';

    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    try {
      debugPrint('[LyricsService] Fetching lyrics for "$cleanTitle" by $artist');
      final queryParams = <String, dynamic>{
        'track_name': cleanTitle,
        'artist_name': artist,
      };
      if (durationSeconds != null && durationSeconds > 0) {
        queryParams['duration'] = durationSeconds;
      }

      final response = await _dio.get<Map<String, dynamic>>(
        'https://lrclib.net/api/get',
        queryParameters: queryParams,
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data!;
        final rawSynced = data['syncedLyrics'] as String?;
        final rawPlain = data['plainLyrics'] as String?;

        if (rawSynced != null && rawSynced.trim().isNotEmpty) {
          final parsed = parseLrc(rawSynced);
          final result = TrackLyrics(
            plainLyrics: rawPlain,
            syncedLyrics: parsed,
            isSynced: parsed.isNotEmpty,
          );
          _cache[cacheKey] = result;
          return result;
        }

        if (rawPlain != null && rawPlain.trim().isNotEmpty) {
          final result = TrackLyrics(
            plainLyrics: rawPlain,
            syncedLyrics: const [],
            isSynced: false,
          );
          _cache[cacheKey] = result;
          return result;
        }
      }
    } catch (e) {
      debugPrint('[LyricsService] Failed to fetch lyrics: $e');
    }

    // Try fallback search API if exact match failed
    try {
      final searchRes = await _dio.get<List<dynamic>>(
        'https://lrclib.net/api/search',
        queryParameters: {'q': '$cleanTitle $artist'},
      );

      if (searchRes.statusCode == 200 && searchRes.data != null && searchRes.data!.isNotEmpty) {
        final first = searchRes.data!.first as Map<String, dynamic>;
        final rawSynced = first['syncedLyrics'] as String?;
        final rawPlain = first['plainLyrics'] as String?;

        if (rawSynced != null && rawSynced.trim().isNotEmpty) {
          final parsed = parseLrc(rawSynced);
          final result = TrackLyrics(
            plainLyrics: rawPlain,
            syncedLyrics: parsed,
            isSynced: parsed.isNotEmpty,
          );
          _cache[cacheKey] = result;
          return result;
        }
      }
    } catch (_) {}

    return null;
  }

  /// Parse standard LRC timestamped text `[mm:ss.xx] lyric text`
  List<LyricLine> parseLrc(String lrcContent) {
    final lines = lrcContent.split('\n');
    final result = <LyricLine>[];
    final regex = RegExp(r'\[(\d{2}):(\d{2})(?:\.(\d{2,3}))?\](.*)');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final match = regex.firstMatch(trimmed);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final msString = match.group(3);
        var ms = 0;
        if (msString != null) {
          ms = int.parse(msString.padRight(3, '0').substring(0, 3));
        }

        final duration = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: ms,
        );
        final text = match.group(4)?.trim() ?? '';
        if (text.isNotEmpty) {
          result.add(LyricLine(timestamp: duration, text: text));
        }
      }
    }

    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }
}
