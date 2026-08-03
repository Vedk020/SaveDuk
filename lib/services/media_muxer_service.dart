import 'dart:io';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Joins a separately downloaded MP4 video stream and M4A audio stream.
///
/// No media is re-encoded; FFmpeg only remuxes the compatible streams into an
/// MP4 container. The minimal maintained FFmpegKit fork is pinned in pubspec.
class MediaMuxerService {
  Future<String> merge({
    required String videoPath,
    required String audioPath,
    required String downloadId,
    required String filename,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final downloads = Directory(p.join(directory.path, 'downloads'));
    if (!await downloads.exists()) {
      await downloads.create(recursive: true);
    }
    final safeFilename = _safeFilename(filename);
    final outputPath = p.join(downloads.path, '${downloadId}_$safeFilename');
    await _deleteIfPresent(File(outputPath));

    final command = [
      '-y',
      '-i',
      _quote(videoPath),
      '-i',
      _quote(audioPath),
      '-map',
      '0:v:0',
      '-map',
      '1:a:0',
      '-c',
      'copy',
      '-movflags',
      '+faststart',
      _quote(outputPath),
    ].join(' ');
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    final output = File(outputPath);
    if (!ReturnCode.isSuccess(returnCode) ||
        !await output.exists() ||
        await output.length() == 0) {
      await _deleteIfPresent(output);
      throw StateError('Could not merge the downloaded audio and video.');
    }

    await _deleteIfPresent(File(videoPath));
    await _deleteIfPresent(File(audioPath));
    return outputPath;
  }

  void cancel() => FFmpegKit.cancel();

  String _safeFilename(String value) {
    final base = value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    if (base.isEmpty) return 'saveduk-video.mp4';
    return base.endsWith('.mp4') ? base : '$base.mp4';
  }

  String _quote(String value) => "'${value.replaceAll("'", r"'\\''")}'";

  Future<void> _deleteIfPresent(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // A failed temporary-file cleanup must not hide a successful download.
    }
  }
}
