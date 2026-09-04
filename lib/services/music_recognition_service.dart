import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/music_track.dart';
import 'acr_cloud_service.dart';
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

/// Robust multi-tier service to identify music from video links or direct audio streams
class MusicRecognitionService {
  final OnDeviceExtractorService _extractor = OnDeviceExtractorService();
  final AcrCloudService _acrCloud = AcrCloudService();
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    ),
  );

  /// Identify music from any shared video or audio URL
  Future<RecognizedTrack?> identifyFromUrl(String url) async {
    try {
      debugPrint('[MusicRecognition] identifying track for: $url');

      // Stage 1: Check for direct music streaming links (Spotify, Apple Music, Soundcloud)
      final directMatch = await _identifyFromDirectStreamingLink(url);
      if (directMatch != null) return directMatch;

      // Stage 2: Attempt on-device yt-dlp extraction with Content-ID description parsing
      try {
        final media = await _extractor.extract(url);
        if (media.isSuccess) {
          final audioUrl = media.audio?.url ?? media.video.url;
          final audioHeaders = media.audio?.headers ?? media.video.headers;

          // Priority 2A: True Acoustic Fingerprinting via ACRCloud
          if (audioUrl.isNotEmpty) {
            try {
              debugPrint('[MusicRecognition] Attempting acoustic recognition with ACRCloud...');
              final acrResult = await _acrCloud.identifyFromStreamUrl(audioUrl, headers: audioHeaders);
              if (acrResult != null) {
                debugPrint('[MusicRecognition] ✅ ACRCloud matched: "${acrResult.title}" by ${acrResult.artist}');
                
                // Fetch high quality artwork and duration via YouTube Music search
                String? artwork = media.thumbnail;
                int duration = acrResult.durationSeconds > 0 ? acrResult.durationSeconds : media.duration;
                
                final searchResults = await _extractor.searchTracks(
                  '"${acrResult.title}" ${acrResult.artist}',
                  limit: 2,
                );
                if (searchResults.isNotEmpty) {
                  artwork = searchResults.first.thumbnail ?? artwork;
                  if (duration == 0) duration = searchResults.first.duration;
                }

                return RecognizedTrack(
                  track: MusicTrack(
                    id: const Uuid().v4(),
                    title: acrResult.title,
                    artist: acrResult.artist,
                    album: acrResult.album ?? media.album,
                    artworkUrl: artwork,
                    streamUrl: audioUrl,
                    originalMediaUrl: url,
                    durationSeconds: duration,
                    createdAt: DateTime.now(),
                  ),
                  audioStreamUrl: audioUrl,
                  headers: audioHeaders,
                  identifiedAcoustically: true,
                );
              }
            } catch (e) {
              debugPrint('[MusicRecognition] ACRCloud acoustic fingerprint error: $e');
            }
          }

          // Priority 2B: Content-ID or metadata tags from extractor
          // yt-dlp populates track/artist from YouTube Music's Content-ID system
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

          // Priority 2C: "Artist - Title" pattern parsing from video title
          final parsedTitle = _parseArtistAndTitle(media.title);
          if (parsedTitle != null) {
            // Verify with a YouTube Music search to get clean metadata
            final searchResults = await _extractor.searchTracks(
              '${parsedTitle.$1} ${parsedTitle.$2}',
              limit: 3,
            );

            String? artwork = media.thumbnail;
            int duration = media.duration;
            String finalTitle = parsedTitle.$2;
            String finalArtist = parsedTitle.$1;

            if (searchResults.isNotEmpty) {
              final best = searchResults.first;
              artwork = best.thumbnail ?? artwork;
              if (duration == 0) duration = best.duration;
              // Use search result's cleaner title if it matches well
              if (_isSimilar(best.title, parsedTitle.$2)) {
                finalTitle = best.title;
                finalArtist = best.artist;
              }
            }

            return RecognizedTrack(
              track: MusicTrack(
                id: const Uuid().v4(),
                title: finalTitle,
                artist: finalArtist,
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

          // Priority 2D: Smart song extraction from noisy video title
          final songQuery = _extractSongFromNoisyTitle(
            media.title,
            uploaderHint: media.artist,
          );
          final searchResults = await _extractor.searchTracks(songQuery, limit: 5);

          if (searchResults.isNotEmpty) {
            // Pick the best match — prefer results that look like actual songs
            final match = _pickBestSongMatch(searchResults, songQuery);
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
        }
      } catch (e) {
        debugPrint('[MusicRecognition] yt-dlp extraction skipped/failed: $e');
      }

      // Stage 3: Social oEmbed and Embed Scraping (for Instagram Reels, TikTok, Facebook)
      final socialMatch = await _identifyFromSocialOembed(url);
      if (socialMatch != null) return socialMatch;

      // Stage 4: Resilient Fallback — Extract whatever query we can and search
      final fallbackQuery = _extractFallbackQueryFromUrl(url);
      if (fallbackQuery.isNotEmpty) {
        final fallbackResults = await _extractor.searchTracks(fallbackQuery, limit: 3);
        if (fallbackResults.isNotEmpty) {
          final topMatch = fallbackResults.first;
          return RecognizedTrack(
            track: MusicTrack(
              id: const Uuid().v4(),
              title: topMatch.title,
              artist: topMatch.artist,
              artworkUrl: topMatch.thumbnail,
              streamUrl: null,
              originalMediaUrl: url,
              durationSeconds: topMatch.duration,
              createdAt: DateTime.now(),
            ),
            audioStreamUrl: null,
            headers: const {},
            identifiedAcoustically: true,
          );
        }
      }

      return null;
    } catch (e) {
      debugPrint('[MusicRecognition] identification error: $e');
      return null;
    }
  }

  /// Recognize direct Spotify, YouTube Music, or TikTok links
  Future<RecognizedTrack?> _identifyFromDirectStreamingLink(String url) async {
    final lower = url.toLowerCase();

    // Spotify track
    if (lower.contains('spotify.com/track/')) {
      try {
        final res = await _dio.get('https://open.spotify.com/oembed', queryParameters: {'url': url});
        if (res.statusCode == 200 && res.data is Map) {
          final data = res.data as Map;
          final title = data['title']?.toString() ?? '';
          final artwork = data['thumbnail_url']?.toString();

          // Spotify title format: "Song Name" or "Artist - Song Name"
          final parts = _parseArtistAndTitle(title);
          final songName = parts?.$2 ?? title;
          final artistName = parts?.$1 ?? 'Spotify Track';

          // Resolve playable YouTube audio stream
          final searchResults = await _extractor.searchTracks('$songName $artistName', limit: 2);
          final streamTrack = searchResults.isNotEmpty ? searchResults.first : null;

          return RecognizedTrack(
            track: MusicTrack(
              id: const Uuid().v4(),
              title: songName,
              artist: artistName,
              artworkUrl: artwork ?? streamTrack?.thumbnail,
              streamUrl: null,
              originalMediaUrl: url,
              durationSeconds: streamTrack?.duration ?? 0,
              createdAt: DateTime.now(),
            ),
            identifiedAcoustically: false,
          );
        }
      } catch (_) {}
    }

    // TikTok video
    if (lower.contains('tiktok.com')) {
      try {
        final res = await _dio.get('https://www.tiktok.com/oembed', queryParameters: {'url': url});
        if (res.statusCode == 200 && res.data is Map) {
          final data = res.data as Map;
          final title = data['title']?.toString() ?? '';
          final author = data['author_name']?.toString() ?? '';
          final artwork = data['thumbnail_url']?.toString();

          final cleanQuery = _extractSongFromNoisyTitle(title, uploaderHint: author);
          final searchResults = await _extractor.searchTracks(cleanQuery, limit: 3);

          if (searchResults.isNotEmpty) {
            final match = searchResults.first;
            return RecognizedTrack(
              track: MusicTrack(
                id: const Uuid().v4(),
                title: match.title,
                artist: match.artist,
                artworkUrl: match.thumbnail ?? artwork,
                streamUrl: null,
                originalMediaUrl: url,
                durationSeconds: match.duration,
                createdAt: DateTime.now(),
              ),
              identifiedAcoustically: true,
            );
          }

          return RecognizedTrack(
            track: MusicTrack(
              id: const Uuid().v4(),
              title: cleanQuery.isNotEmpty ? cleanQuery : 'TikTok Audio',
              artist: author.isNotEmpty ? author : 'TikTok Sound',
              artworkUrl: artwork,
              streamUrl: null,
              originalMediaUrl: url,
              durationSeconds: 0,
              createdAt: DateTime.now(),
            ),
            identifiedAcoustically: true,
          );
        }
      } catch (_) {}
    }

    return null;
  }

  /// Scrape public Instagram or Facebook embed pages for audio title badges
  Future<RecognizedTrack?> _identifyFromSocialOembed(String url) async {
    final lower = url.toLowerCase();
    if (!lower.contains('instagram.com') && !lower.contains('facebook.com')) {
      return null;
    }

    try {
      // 1. Try Instagram oEmbed
      if (lower.contains('instagram.com')) {
        final codeMatch = RegExp(r'instagram\.com/(?:reel|reels|p)/([A-Za-z0-9_-]+)').firstMatch(url);
        if (codeMatch != null) {
          final code = codeMatch.group(1);
          final embedUrl = 'https://www.instagram.com/p/$code/embed/captioned/';
          final res = await _dio.get(embedUrl);
          if (res.statusCode == 200 && res.data is String) {
            final html = res.data as String;

            // Check for AudioBadge or audio title in embed HTML
            final audioMatch = RegExp(r'class="AudioBadge"[^>]*>.*?<span>(.*?)</span>', dotAll: true).firstMatch(html) ??
                RegExp(r'class="CaptionComments"[^>]*>(.*?)</div>', dotAll: true).firstMatch(html);

            if (audioMatch != null) {
              final rawAudio = audioMatch.group(1)!.replaceAll(RegExp(r'<[^>]*>'), '').trim();
              if (rawAudio.isNotEmpty) {
                final searchResults = await _extractor.searchTracks(rawAudio, limit: 3);
                if (searchResults.isNotEmpty) {
                  final match = searchResults.first;
                  return RecognizedTrack(
                    track: MusicTrack(
                      id: const Uuid().v4(),
                      title: match.title,
                      artist: match.artist,
                      artworkUrl: match.thumbnail,
                      streamUrl: null,
                      originalMediaUrl: url,
                      durationSeconds: match.duration,
                      createdAt: DateTime.now(),
                    ),
                    identifiedAcoustically: true,
                  );
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[MusicRecognition] social embed parsing error: $e');
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Title Parsing & Cleaning
  // ---------------------------------------------------------------------------

  /// Extract the actual song name from a noisy video title.
  ///
  /// Handles patterns like:
  ///   "YESHA NAGULA 🔥👑 Jonita Gandhi | Anirudh XV Concert | #jonitgandhi #anirudh"
  ///   → "Yesha Nagula Jonita Gandhi"
  ///
  ///   "Peaches ft. Daniel Caesar & Giveon - Justin Bieber (Official Video)"
  ///   → "Peaches ft. Daniel Caesar Giveon Justin Bieber"
  String _extractSongFromNoisyTitle(String raw, {String? uploaderHint}) {
    var title = raw;

    // 1. Strip all emoji and special Unicode symbols
    title = title.replaceAll(RegExp(
      r'[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}'
      r'\u{1F1E0}-\u{1F1FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}'
      r'\u{FE00}-\u{FE0F}\u{1F900}-\u{1F9FF}\u{1FA00}-\u{1FA6F}'
      r'\u{1FA70}-\u{1FAFF}\u{200D}\u{20E3}\u{E0020}-\u{E007F}]',
      unicode: true,
    ), ' ');

    // 2. Strip hashtags and @mentions
    title = title.replaceAll(RegExp(r'#\w+'), '');
    title = title.replaceAll(RegExp(r'@[A-Za-z0-9._]+'), '');

    // 3. Strip bracketed and parenthesized noise
    title = title.replaceAll(RegExp(r'\[.*?\]'), '');
    title = title.replaceAll(
      RegExp(
        r'\((Official\s*(Music)?\s*Video|Official\s*Audio|Audio|Lyric\s*Video|'
        r'Lyrics|Visualizer|4K|HD|Full\s*Video|Full\s*Song|Live|'
        r'Live\s*Performance|Concert|Award\s*Show|Unplugged)\)',
        caseSensitive: false,
      ),
      '',
    );

    // 4. Split on pipes `|` — the first segment usually contains the song name
    if (title.contains('|')) {
      final segments = title.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        // Take the first segment (usually song + artist), ignore event/concert segments
        title = segments.first;
      }
    }

    // 5. Strip remaining noise words
    title = title.replaceAll(
      RegExp(
        r'\b(Official\s*Video|Official\s*Audio|Full\s*Song|HD|4K|MV|Shorts|Reels|'
        r'Music\s*Video|Video\s*Song|Song\s*Video|New\s*Song\s*\d{4}|'
        r'XV\s*Concert|Live\s*Concert|Live\s*Performance|Award\s*Show|'
        r'Concert\s*Version|Stage\s*Performance)\b',
        caseSensitive: false,
      ),
      '',
    );

    // 6. Clean up separators
    title = title.replaceAll(RegExp(r'[|/\\#~]'), ' ');
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();

    // 7. If the uploader/channel name is embedded in what remains and is long,
    //    don't strip it — it might be the artist name. But if the title starts
    //    or ends with common non-song uploader patterns, remove them.
    if (uploaderHint != null && uploaderHint.isNotEmpty) {
      // Only strip uploader if it looks like a channel name (not an artist)
      final lowerHint = uploaderHint.toLowerCase();
      final channelPatterns = ['music', 'official', 'records', 'entertainment', 'channel', 'vevo', 'studios'];
      final isChannelName = channelPatterns.any((p) => lowerHint.contains(p));
      if (isChannelName) {
        title = title.replaceAll(RegExp(RegExp.escape(uploaderHint), caseSensitive: false), '').trim();
      }
    }

    // 8. Final cleanup
    title = title.replaceAll(RegExp(r'[\-–—]+$'), '').trim(); // trailing dashes
    title = title.replaceAll(RegExp(r'^[\-–—]+'), '').trim(); // leading dashes
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();

    return title.isEmpty ? raw : title;
  }

  /// Pick the best song match from search results — prefer actual songs over compilations/playlists
  SearchTrackResult _pickBestSongMatch(List<SearchTrackResult> results, String query) {
    if (results.length <= 1) return results.first;

    // Prefer results with duration between 1:30 and 8:00 (typical song length)
    final songLengthResults = results.where((r) => r.duration >= 90 && r.duration <= 480).toList();
    if (songLengthResults.isNotEmpty) {
      return songLengthResults.first;
    }

    // Prefer results with duration < 15 min (avoid hour-long compilations)
    final shortResults = results.where((r) => r.duration > 0 && r.duration < 900).toList();
    if (shortResults.isNotEmpty) {
      return shortResults.first;
    }

    return results.first;
  }

  /// Check if two titles are similar enough to be the same song
  bool _isSimilar(String a, String b) {
    final cleanA = a.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), '').trim();
    final cleanB = b.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), '').trim();
    if (cleanA == cleanB) return true;
    // Check if one contains the other
    if (cleanA.contains(cleanB) || cleanB.contains(cleanA)) return true;
    // Check word overlap
    final wordsA = cleanA.split(' ').toSet();
    final wordsB = cleanB.split(' ').toSet();
    final overlap = wordsA.intersection(wordsB).length;
    final maxLen = wordsA.length > wordsB.length ? wordsA.length : wordsB.length;
    return maxLen > 0 && overlap / maxLen >= 0.5;
  }

  /// Extract fallback search query from URL path or parameters
  String _extractFallbackQueryFromUrl(String rawUrl) {
    try {
      final uri = Uri.parse(rawUrl);
      final segments = uri.pathSegments.where((s) => s.isNotEmpty && s != 'reel' && s != 'reels' && s != 'p').toList();
      if (segments.isNotEmpty) {
        return segments.last.replaceAll(RegExp(r'[-_]'), ' ').trim();
      }
    } catch (_) {}
    return '';
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
    // Strip emoji
    title = title.replaceAll(RegExp(
      r'[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}'
      r'\u{1F1E0}-\u{1F1FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}'
      r'\u{FE00}-\u{FE0F}\u{1F900}-\u{1F9FF}\u{1FA00}-\u{1FA6F}'
      r'\u{1FA70}-\u{1FAFF}\u{200D}\u{20E3}\u{E0020}-\u{E007F}]',
      unicode: true,
    ), ' ');
    title = title.replaceAll(RegExp(r'\[.*?\]'), '');
    title = title.replaceAll(
      RegExp(r'\((Official\s*(Music)?\s*Video|Official\s*Audio|Audio|Lyric\s*Video|Lyrics|Visualizer|4K|HD|Full\s*Video)\)', caseSensitive: false),
      '',
    );
    title = title.replaceAll(RegExp(r'\b(Official\s*Video|Official\s*Audio|Full\s*Song|HD|4K|MV|Shorts|Reels)\b', caseSensitive: false), '');
    title = title.replaceAll(RegExp(r'#\w+'), '');
    title = title.replaceAll(RegExp(r'@[A-Za-z0-9._]+'), '');
    title = title.replaceAll(RegExp(r'[|/\\#]'), ' ');
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    return title.isEmpty ? raw : title;
  }
}
