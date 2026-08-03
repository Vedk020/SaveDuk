import 'package:flutter_test/flutter_test.dart';
import 'package:saveduk/services/url_parser_service.dart';

void main() {
  group('UrlParserService', () {
    test('extracts a URL from shared text', () {
      expect(
        UrlParserService.extractUrl(
          'Watch this https://youtu.be/dQw4w9WgXcQ now',
        ),
        'https://youtu.be/dQw4w9WgXcQ',
      );
    });

    test('detects supported platforms', () {
      expect(
        UrlParserService.detectPlatform(
          'https://www.instagram.com/reel/example/',
        )?.id,
        'instagram',
      );
      expect(
        UrlParserService.detectPlatform('https://x.com/example/status/123')?.id,
        'twitter',
      );
    });

    test('removes tracking parameters without changing video identifiers', () {
      expect(
        UrlParserService.cleanUrl(
          'https://www.youtube.com/watch?v=abc123&utm_source=share',
        ),
        'https://www.youtube.com/watch?v=abc123',
      );
    });
  });
}
