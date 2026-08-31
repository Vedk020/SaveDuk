import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Service to generate deep-links and launch external streaming platforms
/// (Spotify, YouTube Music, Amazon Music, Apple Music).
class StreamingLinksService {
  /// Open track in Spotify (deep-link native app, fallback to web)
  static Future<bool> openSpotify({required String title, required String artist}) async {
    final query = Uri.encodeComponent('$title $artist'.trim());
    final deepLink = Uri.parse('spotify:search:$query');
    final webUrl = Uri.parse('https://open.spotify.com/search/$query');

    return await _launchWithFallback(deepLink, webUrl);
  }

  /// Open track in YouTube Music
  static Future<bool> openYouTubeMusic({required String title, required String artist}) async {
    final query = Uri.encodeComponent('$title $artist'.trim());
    final deepLink = Uri.parse('vnd.youtube.music://search?q=$query');
    final webUrl = Uri.parse('https://music.youtube.com/search?q=$query');

    return await _launchWithFallback(deepLink, webUrl);
  }

  /// Open track in Amazon Music
  static Future<bool> openAmazonMusic({required String title, required String artist}) async {
    final query = Uri.encodeComponent('$title $artist'.trim());
    final deepLink = Uri.parse('amznmp3://search?query=$query');
    final webUrl = Uri.parse('https://music.amazon.com/search/$query');

    return await _launchWithFallback(deepLink, webUrl);
  }

  /// Open track in Apple Music
  static Future<bool> openAppleMusic({required String title, required String artist}) async {
    final query = Uri.encodeComponent('$title $artist'.trim());
    final deepLink = Uri.parse('music://search?term=$query');
    final webUrl = Uri.parse('https://music.apple.com/search?term=$query');

    return await _launchWithFallback(deepLink, webUrl);
  }

  static Future<bool> _launchWithFallback(Uri deepLink, Uri webUrl) async {
    try {
      // Attempt native app deep-link first
      if (await canLaunchUrl(deepLink)) {
        final launched = await launchUrl(
          deepLink,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return true;
      }
    } catch (e) {
      debugPrint('[StreamingLinks] native launch error: $e');
    }

    try {
      // Fall back to web browser
      return await launchUrl(
        webUrl,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('[StreamingLinks] web launch error: $e');
      return false;
    }
  }
}
