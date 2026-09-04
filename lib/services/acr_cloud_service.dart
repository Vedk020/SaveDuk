import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/constants.dart';

/// Structured result parsed from ACRCloud acoustic fingerprint response
class AcrTrackResult {
  final String title;
  final String artist;
  final String? album;
  final int durationSeconds;
  final String? spotifyTrackId;
  final String? youtubeVideoId;
  final int score;

  const AcrTrackResult({
    required this.title,
    required this.artist,
    this.album,
    this.durationSeconds = 0,
    this.spotifyTrackId,
    this.youtubeVideoId,
    this.score = 100,
  });

  @override
  String toString() => 'AcrTrackResult("$title" by $artist, score: $score)';
}

/// Official ACRCloud Acoustic Recognition Client
class AcrCloudService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  /// Identifies audio from raw byte sample (WAV, MP3, AAC, M4A, etc.)
  Future<AcrTrackResult?> identifyAudioBytes(Uint8List sample) async {
    try {
      final host = AcrCloudConfig.host;
      final accessKey = AcrCloudConfig.accessKey;
      final secretKey = AcrCloudConfig.accessSecret;

      final httpMethod = 'POST';
      final httpUri = '/v1/identify';
      final dataType = 'audio';
      final signatureVersion = '1';
      final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

      // String to sign: METHOD + "\n" + URI + "\n" + ACCESS_KEY + "\n" + DATA_TYPE + "\n" + SIGNATURE_VERSION + "\n" + TIMESTAMP
      final stringToSign = '$httpMethod\n$httpUri\n$accessKey\n$dataType\n$signatureVersion\n$timestamp';
      final hmac = Hmac(sha1, utf8.encode(secretKey));
      final signature = base64.encode(hmac.convert(utf8.encode(stringToSign)).bytes);

      final formData = FormData.fromMap({
        'sample': MultipartFile.fromBytes(
          sample,
          filename: 'sample.mp4',
        ),
        'access_key': accessKey,
        'data_type': dataType,
        'signature_version': signatureVersion,
        'signature': signature,
        'sample_bytes': sample.length.toString(),
        'timestamp': timestamp,
      });

      debugPrint('[ACRCloud] Sending acoustic fingerprint sample (${sample.length} bytes) to https://$host$httpUri...');
      final response = await _dio.post(
        'https://$host$httpUri',
        data: formData,
        options: Options(
          headers: {
            'Accept': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is Map ? response.data as Map : jsonDecode(response.data.toString()) as Map;
        return _parseAcrResponse(data);
      }
    } catch (e) {
      debugPrint('[ACRCloud] Error identifying acoustic sample: $e');
    }
    return null;
  }

  /// Downloads a ~600KB audio/video header chunk from a media stream URL and acoustically identifies it
  Future<AcrTrackResult?> identifyFromStreamUrl(
    String streamUrl, {
    Map<String, String>? headers,
  }) async {
    try {
      debugPrint('[ACRCloud] Sampling audio chunk from stream URL...');
      final reqHeaders = <String, dynamic>{
        ...?headers,
        'Range': 'bytes=0-655360', // First ~640 KB gives 8-15 seconds of audio
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      };

      final chunkResponse = await _dio.get<List<int>>(
        streamUrl,
        options: Options(
          headers: reqHeaders,
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (status) => status != null && (status >= 200 && status < 300 || status == 206),
        ),
      );

      if (chunkResponse.data != null && chunkResponse.data!.isNotEmpty) {
        final sampleBytes = Uint8List.fromList(chunkResponse.data!);
        debugPrint('[ACRCloud] Downloaded sample chunk: ${sampleBytes.length} bytes');
        return await identifyAudioBytes(sampleBytes);
      }
    } catch (e) {
      debugPrint('[ACRCloud] Failed downloading stream chunk: $e');
    }
    return null;
  }

  AcrTrackResult? _parseAcrResponse(Map data) {
    try {
      final status = data['status'] as Map?;
      if (status == null || status['code'] != 0) {
        debugPrint('[ACRCloud] Recognition failed: ${status?['msg']} (code: ${status?['code']})');
        return null;
      }

      final metadata = data['metadata'] as Map?;
      if (metadata == null) return null;

      final musicList = metadata['music'] as List?;
      if (musicList == null || musicList.isEmpty) {
        debugPrint('[ACRCloud] No music matches found');
        return null;
      }

      final music = musicList.first as Map;
      final title = music['title']?.toString() ?? '';
      
      // Parse artist names
      final artistsList = music['artists'] as List?;
      final artist = (artistsList != null && artistsList.isNotEmpty)
          ? artistsList.map((a) => (a as Map)['name']?.toString() ?? '').where((s) => s.isNotEmpty).join(', ')
          : 'Unknown Artist';

      // Parse album
      final albumMap = music['album'] as Map?;
      final album = albumMap?['name']?.toString();

      // Duration
      final durationMs = (music['duration_ms'] as num?)?.toInt() ?? 0;
      final durationSeconds = durationMs ~/ 1000;

      // Score (confidence: 0 - 100)
      final score = (music['score'] as num?)?.toInt() ?? 100;

      // External IDs (Spotify / YouTube)
      String? spotifyId;
      String? youtubeVid;
      final externalMetadata = music['external_metadata'] as Map?;
      if (externalMetadata != null) {
        final spotify = externalMetadata['spotify'] as Map?;
        spotifyId = (spotify?['track'] as Map?)?['id']?.toString();

        final youtube = externalMetadata['youtube'] as Map?;
        youtubeVid = youtube?['vid']?.toString();
      }

      final result = AcrTrackResult(
        title: title,
        artist: artist,
        album: album,
        durationSeconds: durationSeconds,
        spotifyTrackId: spotifyId,
        youtubeVideoId: youtubeVid,
        score: score,
      );

      debugPrint('[ACRCloud] ✅ ACOUSTIC MATCH FOUND: $result');
      return result;
    } catch (e) {
      debugPrint('[ACRCloud] Error parsing metadata: $e');
      return null;
    }
  }
}
