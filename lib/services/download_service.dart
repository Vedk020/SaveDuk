import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Service for downloading files with progress tracking
class DownloadService {
  final Dio _dio;
  final Map<String, CancelToken> _cancelTokens = {};

  DownloadService()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 10),
          followRedirects: true,
          maxRedirects: 5,
        ),
      );

  /// Download a file from [url] and save to temp directory.
  /// Returns the local file path on success.
  ///
  /// [downloadId] is used for cancellation support.
  /// [onProgress] callback receives progress as 0.0 – 1.0.
  /// [onFileSize] callback receives file size in bytes when known.
  Future<String> downloadFile({
    required String url,
    required String downloadId,
    String? filename,
    Map<String, String> headers = const {},
    void Function(double progress)? onProgress,
    void Function(int bytes)? onFileSize,
  }) async {
    final cancelToken = CancelToken();
    _cancelTokens[downloadId] = cancelToken;

    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory(p.join(documentsDir.path, 'downloads'));
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
      final resolvedFilename = _safeFilename(filename ?? _filenameFromUrl(url));
      final savePath = p.join(
        downloadDir.path,
        '${downloadId}_$resolvedFilename',
      );

      await _dio.download(
        url,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onFileSize?.call(total);
            onProgress?.call(received / total);
          } else {
            // Unknown total — report received bytes as size, progress indeterminate
            onFileSize?.call(received);
          }
        },
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'User-Agent': 'SaveDuk/1.0', ...headers},
        ),
      );

      _cancelTokens.remove(downloadId);

      // Verify file exists and has content
      final file = File(savePath);
      if (!await file.exists() || await file.length() == 0) {
        throw Exception('Downloaded file is empty');
      }

      return savePath;
    } catch (e) {
      _cancelTokens.remove(downloadId);
      rethrow;
    }
  }

  /// Cancel an in-progress download
  void cancelDownload(String downloadId) {
    final token = _cancelTokens[downloadId];
    if (token != null && !token.isCancelled) {
      token.cancel('User cancelled');
    }
    _cancelTokens.remove(downloadId);
  }

  /// Extract a filename from URL, with fallback
  String _filenameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      if (pathSegments.isNotEmpty) {
        final last = pathSegments.last;
        if (last.contains('.')) {
          return last;
        }
      }
    } catch (_) {}
    return 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
  }

  String _safeFilename(String filename) {
    final safe = filename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    if (safe.isEmpty) {
      return 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
    }
    return safe.contains('.') ? safe : '$safe.mp4';
  }

  void dispose() {
    for (final token in _cancelTokens.values) {
      if (!token.isCancelled) token.cancel('Disposed');
    }
    _cancelTokens.clear();
    _dio.close();
  }
}
