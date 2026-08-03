import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

/// The streams selected by the embedded yt-dlp extractor.
class ExtractedMedia {
  final String title;
  final String filename;
  final MediaStream video;
  final MediaStream? audio;
  final String? error;

  const ExtractedMedia({
    required this.title,
    required this.filename,
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
      video: MediaStream.fromMap(Map<Object?, Object?>.from(video)),
      audio: audio is Map
          ? MediaStream.fromMap(Map<Object?, Object?>.from(audio))
          : null,
    );
  }
}

/// Bridges Flutter to the Android-only, embedded yt-dlp extractor.
class OnDeviceExtractorService {
  static const MethodChannel _channel = MethodChannel('saveduk/extractor');

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
}
