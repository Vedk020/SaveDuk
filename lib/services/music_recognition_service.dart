import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/music_track.dart';
import 'on_device_extractor_service.dart';

/// Result of music identification
class RecognizedTrack {
  final MusicTrack track;
  final String? audioStreamUrl;
  final Map<String, String> headers;
  final bool identifiedAcoustically;

  const RecognizedTrack({
    required this.track,
    this.audioStreamUrl,
    this.headers = const {},
    this.identifiedAcoustically = false,
  });
}

/// Service to identify music from video links or audio streams
class MusicRecognitionService {
  final OnDeviceExtractorService _extractor = OnDeviceExtractorService();

  /// Identify music from a shared video URL
  Future<RecognizedTrack?> identifyFromUrl(String url) async {
    try {
      debugPrint('[MusicRecognition] extracting stream & metadata for: $url');
      final media = await _extractor.extract(url);

      if (!media.isSuccess) {
        throw Exception(media.error ?? 'Failed to extract media for music recognition');
      }

      final audioUrl = media.audio?.url ?? media.video.url;
      final audioHeaders = media.audio?.headers ?? media.video.headers;

      // Tier 1: Check for explicit track / artist metadata from extractor
      if (media.track != null && media.track!.trim().isNotEmpty) {
        final trackName = media.track!.trim();
        final artistName = (media.artist?.trim().isNotEmpty == true)
            ? media.artist!.trim()
            : 'Unknown Artist';

        return RecognizedTrack(
          track: MusicTrack(
            id: const Uuid().v4(),
            title: trackName,
            artist: artistName,
            album: media.album,
            artworkUrl: media.thumbnail,
            streamUrl: audioUrl,
            originalMediaUrl: url,
            durationSeconds: media.duration,
            createdAt: DateTime.now(),
          ),
          audioStreamUrl: audioUrl,
          headers: audioHeaders,
          identifiedAcoustically: false,
        );
      }

      // Tier 2: Parse common video title patterns e.g. "Artist - Song (Official Video)"
      final parsedTitle = _parseArtistAndTitle(media.title);
      if (parsedTitle != null) {
        // Try searching for cleaner metadata using searchTracks
        final searchResults = await _extractor.searchTracks(
          '${parsedTitle.$1} ${parsedTitle.$2}',
          limit: 3,
        );

        String? artwork = media.thumbnail;
        int duration = media.duration;
        if (searchResults.isNotEmpty) {
          artwork = searchResults.first.thumbnail ?? artwork;
          if (duration == 0) duration = searchResults.first.duration;
        }

        return RecognizedTrack(
          track: MusicTrack(
            id: const Uuid().v4(),
            title: parsedTitle.$2,
            artist: parsedTitle.$1,
            album: media.album,
            artworkUrl: artwork,
            streamUrl: audioUrl,
            originalMediaUrl: url,
            durationSeconds: duration,
            createdAt: DateTime.now(),
          ),
          audioStreamUrl: audioUrl,
          headers: audioHeaders,
          identifiedAcoustically: false,
        );
      }

      // Tier 3: Attempt online search match with clean title
      final cleanTitle = _cleanVideoTitle(media.title);
      final searchResults = await _extractor.searchTracks(cleanTitle, limit: 3);

      if (searchResults.isNotEmpty) {
        final match = searchResults.first;
        return RecognizedTrack(
          track: MusicTrack(
            id: const Uuid().v4(),
            title: match.title,
            artist: match.artist,
            album: match.album,
            artworkUrl: match.thumbnail ?? media.thumbnail,
            streamUrl: audioUrl,
            originalMediaUrl: url,
            durationSeconds: match.duration > 0 ? match.duration : media.duration,
            createdAt: DateTime.now(),
          ),
          audioStreamUrl: audioUrl,
          headers: audioHeaders,
          identifiedAcoustically: true,
        );
      }

      // Fallback: Use raw extracted title
      return RecognizedTrack(
        track: MusicTrack(
          id: const Uuid().v4(),
          title: cleanTitle,
          artist: media.artist?.isNotEmpty == true ? media.artist! : 'Unknown Artist',
          album: media.album,
          artworkUrl: media.thumbnail,
          streamUrl: audioUrl,
          originalMediaUrl: url,
          durationSeconds: media.duration,
          createdAt: DateTime.now(),
        ),
        audioStreamUrl: audioUrl,
        headers: audioHeaders,
        identifiedAcoustically: false,
      );
    } catch (e) {
      debugPrint('[MusicRecognition] identification error: $e');
      return null;
    }
  }

  /// Parses "Artist - Title" patterns
  (String, String)? _parseArtistAndTitle(String rawTitle) {
    final cleaned = _cleanVideoTitle(rawTitle);
    if (cleaned.contains(' - ')) {
      final parts = cleaned.split(' - ');
      if (parts.length >= 2) {
        final artist = parts[0].trim();
        final title = parts.sublist(1).join(' - ').trim();
        if (artist.isNotEmpty && title.isNotEmpty) {
          return (artist, title);
        }
      }
    }
    return null;
  }

  /// Remove tags like [Official Music Video], (Audio), 4K, HD, etc.
  String _cleanVideoTitle(String raw) {
    var title = raw;
    title = title.replaceAll(RegExp(r'\[.*?\]'), '');
    title = title.replaceAll(
      RegExp(r'\((Official\s*(Music)?\s*Video|Official\s*Audio|Audio|Lyric\s*Video|Lyrics|Visualizer|4K|HD)\)', caseSensitive: false),
      '',
    );
    title = title.replaceAll(RegExp(r'\b(Official\s*Video|Official\s*Audio|Full\s*Song|HD|4K|MV)\b', caseSensitive: false), '');
    title = title.replaceAll(RegExp(r'[|/\\#]'), '');
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    return title.isEmpty ? raw : title;
  }
}
