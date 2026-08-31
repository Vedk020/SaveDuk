import '../config/constants.dart';

/// Service to parse and validate URLs, and detect which platform they belong to.
class UrlParserService {
  /// Extract a URL from shared text (may contain extra text around the URL)
  static String? extractUrl(String text) {
    final urlRegex = RegExp(
      r'https?://[^\s<>"{}|\\^`\[\]]+',
      caseSensitive: false,
    );
    final match = urlRegex.firstMatch(text);
    return match?.group(0);
  }

  /// Detect which platform a URL belongs to
  static SupportedPlatform? detectPlatform(String url) {
    for (final platform in AppPlatforms.all) {
      for (final pattern in platform.urlPatterns) {
        if (pattern.hasMatch(url)) {
          return platform;
        }
      }
    }
    return null;
  }

  /// Validate that a URL is from a supported platform
  static bool isSupported(String url) {
    return detectPlatform(url) != null;
  }

  /// Clean URL by removing tracking parameters
  static String cleanUrl(String url) {
    try {
      final uri = Uri.parse(url);
      // Remove common tracking params
      final cleanParams = Map<String, String>.from(uri.queryParameters);
      cleanParams.removeWhere(
        (key, _) => [
          'utm_source',
          'utm_medium',
          'utm_campaign',
          'utm_term',
          'utm_content',
          'si',
          'feature',
          'fbclid',
          'igshid',
          'igsh',
          'mibextid',
          'ref',
          'share_id',
          'sfnsn',
          'paipv',
          'app',
        ].contains(key),
      );
      return uri
          .replace(queryParameters: cleanParams.isEmpty ? null : cleanParams)
          .toString();
    } catch (_) {
      return url;
    }
  }
}
