import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/music_track.dart';

/// A direct media stream with the request headers required by its source.
class MediaStream {
  final String url;
  final String extension;
  final Map<String, String> headers;

  const MediaStream({
    required this.url,
    required this.extension,
    required this.headers,
  });

  factory MediaStream.fromMap(Map<Object?, Object?> map) {
    final rawHeaders = map['headers'];
    final headers = rawHeaders is Map
        ? rawHeaders.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          )
        : <String, String>{};
    return MediaStream(
      url: map['url'] as String,
      extension: (map['extension'] as String?) ?? 'mp4',
      headers: headers,
    );
  }
}

/// The streams and metadata selected by the embedded yt-dlp extractor.
class ExtractedMedia {
  final String title;
  final String filename;
  final String? track;
  final String? artist;
  final String? album;
  final String? thumbnail;
  final int duration;
  final MediaStream video;
  final MediaStream? audio;
  final String? error;

  const ExtractedMedia({
    required this.title,
    required this.filename,
    this.track,
    this.artist,
    this.album,
    this.thumbnail,
    this.duration = 0,
    required this.video,
    this.audio,
    this.error,
  });

  bool get isSuccess => error == null;
  bool get needsMuxing => audio != null;

  factory ExtractedMedia.fromMap(Map<Object?, Object?> map) {
    final error = map['error'] as String?;
    if (error != null) {
      return ExtractedMedia(
        title: '',
        filename: '',
        video: const MediaStream(url: '', extension: 'mp4', headers: {}),
        error: error,
      );
    }
    final video = map['video'];
    if (video is! Map) {
      return ExtractedMedia(
        title: '',
        filename: '',
        video: const MediaStream(url: '', extension: 'mp4', headers: {}),
        error: 'The extractor did not return a media stream.',
      );
    }
    final audio = map['audio'];
    return ExtractedMedia(
      title: (map['title'] as String?) ?? 'Saved media',
      filename: (map['filename'] as String?) ?? 'saveduk-video.mp4',
      track: map['track'] as String?,
      artist: map['artist'] as String?,
      album: map['album'] as String?,
      thumbnail: map['thumbnail'] as String?,
      duration: (map['duration'] as num?)?.toInt() ?? 0,
      video: MediaStream.fromMap(Map<Object?, Object?>.from(video)),
      audio: audio is Map
          ? MediaStream.fromMap(Map<Object?, Object?>.from(audio))
          : null,
    );
  }
}

/// Search result track model
class SearchTrackResult {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final String? thumbnail;
  final int duration;
  final String url;

  const SearchTrackResult({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.thumbnail,
    this.duration = 0,
    required this.url,
  });

  factory SearchTrackResult.fromMap(Map<Object?, Object?> map) {
    return SearchTrackResult(
      id: (map['id'] as String?) ?? '',
      title: (map['title'] as String?) ?? 'Unknown Track',
      artist: (map['artist'] as String?) ?? 'Unknown Artist',
      album: map['album'] as String?,
      thumbnail: map['thumbnail'] as String?,
      duration: (map['duration'] as num?)?.toInt() ?? 0,
      url: (map['url'] as String?) ?? '',
    );
  }

  /// Converts a search result into a playable MusicTrack
  MusicTrack toMusicTrack() {
    return MusicTrack(
      id: id.isNotEmpty ? id : DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      artist: artist,
      album: album,
      artworkUrl: thumbnail,
      originalMediaUrl: url,
      durationSeconds: duration,
      createdAt: DateTime.now(),
    );
  }
}

/// Bridges Flutter to the Android-only, embedded yt-dlp extractor.
class OnDeviceExtractorService {
  static const MethodChannel _channel = MethodChannel('saveduk/extractor');

  /// Search online music tracks via embedded yt-dlp engine.
  Future<List<SearchTrackResult>> searchTracks(String query, {int limit = 10}) async {
    if (!Platform.isAndroid || query.trim().isEmpty) return [];
    try {
      final response = await _channel.invokeMethod<Object?>('searchTracks', {
        'query': query,
        'limit': limit,
      });
      if (response is! Map) return [];
      final rawTracks = response['tracks'];
      if (rawTracks is! List) return [];
      return rawTracks
          .whereType<Map>()
          .map((m) => SearchTrackResult.fromMap(Map<Object?, Object?>.from(m)))
          .toList();
    } catch (e) {
      debugPrint('[SaveDukExtractor] searchTracks error: $e');
      return [];
    }
  }

  Future<ExtractedMedia> extract(String url) async {
    if (!Platform.isAndroid) {
      return ExtractedMedia(
        title: '',
        filename: '',
        video: const MediaStream(url: '', extension: 'mp4', headers: {}),
        error: 'On-device extraction is available on Android only.',
      );
    }
    try {
      debugPrint('[SaveDukExtractor] requesting native extraction');
      final response = await _channel.invokeMethod<Object?>('extract', {
        'url': url,
      });
      if (response is! Map) {
        throw const FormatException('Invalid extractor response');
      }
      final media = ExtractedMedia.fromMap(
        Map<Object?, Object?>.from(response),
      );
      debugPrint(
        '[SaveDukExtractor] response=${media.isSuccess ? 'success' : 'source_error'} '
        'mux=${media.needsMuxing}',
      );
      return media;
    } on PlatformException catch (error) {
      debugPrint(
        '[SaveDukExtractor] native_failure code=${error.code} '
        'details=${error.details}',
      );
      return ExtractedMedia(
        title: '',
        filename: '',
        video: const MediaStream(url: '', extension: 'mp4', headers: {}),
        error: error.message ?? 'The on-device extractor is unavailable.',
      );
    } on FormatException {
      return ExtractedMedia(
        title: '',
        filename: '',
        video: const MediaStream(url: '', extension: 'mp4', headers: {}),
        error: 'The on-device extractor returned an invalid response.',
      );
    }
  }

  /// Save raw cookie text (Netscape format or key=value header format) for authenticated platforms.
  Future<bool> setCookies(String cookies) async {
    if (!Platform.isAndroid) return false;
    try {
      await _channel.invokeMethod('setCookies', {'cookies': cookies});
      return true;
    } catch (e) {
      debugPrint('[SaveDukExtractor] failed to save cookies: $e');
      return false;
    }
  }

  /// Check whether cookies are currently stored.
  Future<bool> hasCookies() async {
    if (!Platform.isAndroid) return false;
    try {
      final path = await _channel.invokeMethod<String>('getCookiePath');
      return path != null && path.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Clear stored cookies.
  Future<void> clearCookies() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('clearCookies');
    } catch (_) {}
  }
}
