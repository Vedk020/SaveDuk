import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/music_track.dart';
import 'on_device_extractor_service.dart';

/// Global audio player service for streaming and local track playback
class MusicPlayerService {
  MusicPlayerService._() {
    _init();
  }
  static final MusicPlayerService instance = MusicPlayerService._();

  final AudioPlayer _player = AudioPlayer();
  final OnDeviceExtractorService _extractor = OnDeviceExtractorService();

  final ValueNotifier<MusicTrack?> currentTrackNotifier = ValueNotifier<MusicTrack?>(null);
  final ValueNotifier<bool> isBufferingNotifier = ValueNotifier<bool>(false);

  AudioPlayer get player => _player;
  MusicTrack? get currentTrack => currentTrackNotifier.value;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  bool get isPlaying => _player.playing;

  void _init() {
    _player.playerStateStream.listen((state) {
      isBufferingNotifier.value =
          state.processingState == ProcessingState.buffering ||
          state.processingState == ProcessingState.loading;
    });
  }

  /// Play a music track (streams online if not local)
  Future<void> playTrack(MusicTrack track, {String? directAudioUrl, Map<String, String>? headers}) async {
    try {
      currentTrackNotifier.value = track;
      isBufferingNotifier.value = true;

      // Case 1: Local saved file
      if (track.localPath != null && await File(track.localPath!).exists()) {
        await _player.setAudioSource(AudioSource.file(track.localPath!));
        await _player.play();
        return;
      }

      // Case 2: Direct audio stream URL provided
      String? streamUrl = directAudioUrl ?? track.streamUrl;
      Map<String, String> requestHeaders = headers ?? const {};

      // Case 3: Need to resolve audio stream URL
      if (streamUrl == null || streamUrl.isEmpty) {
        final targetUrl = track.originalMediaUrl ?? 'https://www.youtube.com/watch?v=${track.id}';
        final media = await _extractor.extract(targetUrl);
        if (!media.isSuccess) {
          throw Exception(media.error ?? 'Failed to resolve audio stream');
        }
        streamUrl = media.audio?.url ?? media.video.url;
        requestHeaders = media.audio?.headers ?? media.video.headers;
      }

      final uri = Uri.parse(streamUrl);
      await _player.setAudioSource(
        AudioSource.uri(
          uri,
          headers: requestHeaders.isNotEmpty ? requestHeaders : null,
        ),
      );
      await _player.play();
    } catch (e) {
      debugPrint('[MusicPlayerService] playTrack error: $e');
      isBufferingNotifier.value = false;
      rethrow;
    }
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> resume() async {
    await _player.play();
  }

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> stop() async {
    await _player.stop();
    currentTrackNotifier.value = null;
  }

  void dispose() {
    _player.dispose();
  }
}
