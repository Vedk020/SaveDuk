import 'package:flutter_test/flutter_test.dart';
import 'package:saveduk/services/on_device_extractor_service.dart';

void main() {
  group('ExtractedMedia', () {
    test('parses separate direct video and audio streams', () {
      final media = ExtractedMedia.fromMap({
        'title': 'Example video',
        'filename': 'example-video.mp4',
        'video': {
          'url': 'https://media.example/video.mp4',
          'extension': 'mp4',
          'headers': {'Referer': 'https://example.com/'},
        },
        'audio': {
          'url': 'https://media.example/audio.m4a',
          'extension': 'm4a',
          'headers': {},
        },
      });

      expect(media.isSuccess, isTrue);
      expect(media.needsMuxing, isTrue);
      expect(media.video.headers['Referer'], 'https://example.com/');
      expect(media.audio?.extension, 'm4a');
    });

    test(
      'preserves a native extractor error without making a download request',
      () {
        final media = ExtractedMedia.fromMap({
          'error': 'This site is not supported.',
        });

        expect(media.isSuccess, isFalse);
        expect(media.error, 'This site is not supported.');
      },
    );
  });
}
