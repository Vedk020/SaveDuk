import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import '../models/music_track.dart';
import 'jam_sync_service.dart';
import 'on_device_extractor_service.dart';
import 'sleep_timer_service.dart';

enum AudioRepeatMode { off, all, one }

/// Global audio player service for streaming and local track playback with full queue & auto-play
class MusicPlayerService {
  MusicPlayerService._() {
    _init();
  }
  static final MusicPlayerService instance = MusicPlayerService._();

  static const MethodChannel _mediaChannel = MethodChannel('saveduk/media_notification');

  final AudioPlayer _player = AudioPlayer();
  final OnDeviceExtractorService _extractor = OnDeviceExtractorService();

  final ValueNotifier<MusicTrack?> currentTrackNotifier = ValueNotifier<MusicTrack?>(null);
  final ValueNotifier<bool> isBufferingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<List<MusicTrack>> queueNotifier = ValueNotifier<List<MusicTrack>>([]);
  final ValueNotifier<int> currentIndexNotifier = ValueNotifier<int>(-1);
  final ValueNotifier<bool> isAutoPlayNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<bool> isShuffleNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<AudioRepeatMode> repeatModeNotifier = ValueNotifier<AudioRepeatMode>(AudioRepeatMode.off);

  bool _isAutoFetchingRelated = false;

  AudioPlayer get player => _player;
  MusicTrack? get currentTrack => currentTrackNotifier.value;
  List<MusicTrack> get queue => queueNotifier.value;
  int get currentIndex => currentIndexNotifier.value;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  bool get isPlaying => _player.playing;

  bool get hasNext {
    if (repeatModeNotifier.value == AudioRepeatMode.all || repeatModeNotifier.value == AudioRepeatMode.one) return true;
    if (currentIndexNotifier.value >= 0 && currentIndexNotifier.value < queueNotifier.value.length - 1) return true;
    return isAutoPlayNotifier.value;
  }

  bool get hasPrevious {
    if (_player.position.inSeconds > 3) return true;
    return currentIndexNotifier.value > 0;
  }

  void _init() {
    _mediaChannel.setMethodCallHandler((call) async {
      if (call.method == 'onAction') {
        final action = call.arguments as String?;
        if (action == 'play_pause') {
          togglePlayPause();
        } else if (action == 'previous') {
          skipToPrevious();
        } else if (action == 'next') {
          skipToNext();
        } else if (action == 'rewind') {
          seek(_player.position - const Duration(seconds: 10));
        } else if (action == 'forward') {
          seek(_player.position + const Duration(seconds: 10));
        } else if (action == 'stop') {
          stop();
        }
      }
    });

    _player.playerStateStream.listen((state) {
      isBufferingNotifier.value =
          state.processingState == ProcessingState.buffering ||
          state.processingState == ProcessingState.loading;

      if (currentTrack != null) {
        _syncMediaNotification(currentTrack!, state.playing);
      }

      // Auto-Play: When current track finishes playing
      if (state.processingState == ProcessingState.completed) {
        _handleTrackCompleted();
      }
    });
  }

  void _handleTrackCompleted() {
    if (SleepTimerService.instance.stopAtEndOfTrackNotifier.value) {
      return;
    }

    if (repeatModeNotifier.value == AudioRepeatMode.one) {
      seek(Duration.zero);
      resume();
      return;
    }

    if (isAutoPlayNotifier.value || repeatModeNotifier.value != AudioRepeatMode.off || hasNext) {
      skipToNext();
    }
  }

  void _syncMediaNotification(MusicTrack track, bool isPlaying) {
    if (!Platform.isAndroid) return;
    try {
      _mediaChannel.invokeMethod('show', {
        'title': track.title,
        'artist': track.artist,
        'isPlaying': isPlaying,
      });
    } catch (_) {}
  }

  void _hideMediaNotification() {
    if (!Platform.isAndroid) return;
    try {
      _mediaChannel.invokeMethod('hide');
    } catch (_) {}
  }

  /// Sets or updates the active playback queue
  void setQueue(List<MusicTrack> newQueue, {int initialIndex = 0}) {
    queueNotifier.value = List.unmodifiable(newQueue);
    currentIndexNotifier.value = initialIndex.clamp(0, newQueue.isEmpty ? 0 : newQueue.length - 1);
  }

  /// Toggle Auto-Play mode
  void toggleAutoPlay() {
    isAutoPlayNotifier.value = !isAutoPlayNotifier.value;
  }

  /// Toggle Shuffle mode
  void toggleShuffle() {
    isShuffleNotifier.value = !isShuffleNotifier.value;
  }

  /// Cycle Repeat Mode: Off -> All -> One -> Off
  void cycleRepeatMode() {
    switch (repeatModeNotifier.value) {
      case AudioRepeatMode.off:
        repeatModeNotifier.value = AudioRepeatMode.all;
        break;
      case AudioRepeatMode.all:
        repeatModeNotifier.value = AudioRepeatMode.one;
        break;
      case AudioRepeatMode.one:
        repeatModeNotifier.value = AudioRepeatMode.off;
        break;
    }
  }

  /// Play a music track, optionally initializing or joining an active queue
  Future<void> playTrack(
    MusicTrack track, {
    List<MusicTrack>? queue,
    int? index,
    String? directAudioUrl,
    Map<String, String>? headers,
  }) async {
    if (queue != null && queue.isNotEmpty) {
      queueNotifier.value = List.unmodifiable(queue);
      currentIndexNotifier.value = index ?? queue.indexWhere((t) => t.id == track.id || t.title == track.title).clamp(0, queue.length - 1);
    } else {
      // Check if track is already in current queue
      final existingIndex = queueNotifier.value.indexWhere((t) => t.id == track.id || t.title == track.title);
      if (existingIndex >= 0) {
        currentIndexNotifier.value = existingIndex;
      } else {
        final newQueue = List<MusicTrack>.from(queueNotifier.value)..add(track);
        queueNotifier.value = List.unmodifiable(newQueue);
        currentIndexNotifier.value = newQueue.length - 1;
      }
    }

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
        String targetUrl;
        if (track.originalMediaUrl != null && track.originalMediaUrl!.isNotEmpty) {
          targetUrl = track.originalMediaUrl!;
        } else {
          // No URL stored (e.g. legacy imported track) — search by title + artist
          debugPrint('[MusicPlayerService] No URL for "${track.title}", searching YouTube…');
          final searchResults = await _extractor.searchTracks(
            '"${track.title}" ${track.artist}',
            limit: 1,
          );
          if (searchResults.isNotEmpty) {
            targetUrl = searchResults.first.url;
          } else {
            throw Exception('Could not find a playable source for "${track.title}"');
          }
        }
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
      JamSyncService.instance.notifyTrackChanged(track);
    } catch (e) {
      debugPrint('[MusicPlayerService] playTrack error: $e');
      isBufferingNotifier.value = false;
      rethrow;
    }
  }

  /// Skip to next track in queue or auto-play next recommendation
  Future<void> skipToNext() async {
    final currentQ = queueNotifier.value;
    final idx = currentIndexNotifier.value;

    if (repeatModeNotifier.value == AudioRepeatMode.one) {
      await seek(Duration.zero);
      await resume();
      return;
    }

    if (isShuffleNotifier.value && currentQ.length > 1) {
      final random = Random();
      int nextIdx = random.nextInt(currentQ.length);
      if (nextIdx == idx) {
        nextIdx = (nextIdx + 1) % currentQ.length;
      }
      currentIndexNotifier.value = nextIdx;
      await playTrack(currentQ[nextIdx]);
      return;
    }

    if (idx >= 0 && idx < currentQ.length - 1) {
      currentIndexNotifier.value = idx + 1;
      await playTrack(currentQ[idx + 1]);
      return;
    }

    // At end of queue
    if (repeatModeNotifier.value == AudioRepeatMode.all && currentQ.isNotEmpty) {
      currentIndexNotifier.value = 0;
      await playTrack(currentQ[0]);
      return;
    }

    // Auto-Play: Fetch more related songs if enabled
    if (isAutoPlayNotifier.value && currentTrack != null && !_isAutoFetchingRelated) {
      _isAutoFetchingRelated = true;
      try {
        debugPrint('[MusicPlayerService] Auto-play fetching related tracks for ${currentTrack!.title}…');
        final query = '${currentTrack!.artist} music songs';
        final results = await _extractor.searchTracks(query, limit: 6);
        final newTracks = results
            .map((r) => r.toMusicTrack())
            .where((t) => !currentQ.any((q) => q.title.toLowerCase() == t.title.toLowerCase()))
            .toList();

        if (newTracks.isNotEmpty) {
          final updatedQ = List<MusicTrack>.from(currentQ)..addAll(newTracks);
          queueNotifier.value = List.unmodifiable(updatedQ);
          final nextIdx = idx + 1 < updatedQ.length ? idx + 1 : updatedQ.length - 1;
          currentIndexNotifier.value = nextIdx;
          await playTrack(updatedQ[nextIdx]);
          return;
        }
      } catch (e) {
        debugPrint('[MusicPlayerService] Auto-play fetch error: $e');
      } finally {
        _isAutoFetchingRelated = false;
      }
    }

    // If reached here and no further track, pause
    await pause();
  }

  /// Skip to previous track or restart current track
  Future<void> skipToPrevious() async {
    if (_player.position.inSeconds > 3) {
      await seek(Duration.zero);
      await resume();
      return;
    }

    final currentQ = queueNotifier.value;
    final idx = currentIndexNotifier.value;

    if (idx > 0 && idx < currentQ.length) {
      currentIndexNotifier.value = idx - 1;
      await playTrack(currentQ[idx - 1]);
    } else {
      await seek(Duration.zero);
      await resume();
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
    _hideMediaNotification();
    await _player.stop();
    currentTrackNotifier.value = null;
    currentIndexNotifier.value = -1;
  }

  void dispose() {
    _hideMediaNotification();
    _player.dispose();
  }
}
