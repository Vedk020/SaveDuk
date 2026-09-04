import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'music_player_service.dart';

enum SleepTimerMode {
  timed,
  endOfTrack,
}

/// Service managing the audio playback sleep timer with smooth volume fade-out
class SleepTimerService {
  SleepTimerService._();
  static final SleepTimerService instance = SleepTimerService._();

  Timer? _timer;
  final ValueNotifier<Duration?> remainingNotifier = ValueNotifier<Duration?>(null);
  final ValueNotifier<bool> stopAtEndOfTrackNotifier = ValueNotifier<bool>(false);

  bool get isActive => remainingNotifier.value != null || stopAtEndOfTrackNotifier.value;

  /// Start a timed sleep countdown (e.g. 15m, 30m, 60m)
  void startTimer(Duration duration) {
    cancel();
    stopAtEndOfTrackNotifier.value = false;
    remainingNotifier.value = duration;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final current = remainingNotifier.value;
      if (current == null || current.inSeconds <= 1) {
        timer.cancel();
        remainingNotifier.value = null;
        await _executeFadeOutAndPause();
      } else {
        remainingNotifier.value = current - const Duration(seconds: 1);
      }
    });
  }

  /// Stop at the end of the current playing track
  void setStopAtEndOfTrack(bool enabled) {
    cancel();
    stopAtEndOfTrackNotifier.value = enabled;

    if (enabled) {
      // Listen to player completion
      final player = MusicPlayerService.instance.player;
      StreamSubscription? sub;
      sub = player.playerStateStream.listen((state) async {
        if (state.processingState == ProcessingState.completed) {
          sub?.cancel();
          stopAtEndOfTrackNotifier.value = false;
          await _executeFadeOutAndPause();
        }
      });
    }
  }

  /// Cancel any active sleep timer
  void cancel() {
    _timer?.cancel();
    _timer = null;
    remainingNotifier.value = null;
    stopAtEndOfTrackNotifier.value = false;
  }

  /// Smoothly fade out volume over 3 seconds and pause playback
  Future<void> _executeFadeOutAndPause() async {
    final player = MusicPlayerService.instance.player;
    try {
      final initialVol = player.volume;
      const steps = 6;
      for (int i = steps - 1; i >= 0; i--) {
        await player.setVolume(initialVol * (i / steps));
        await Future.delayed(const Duration(milliseconds: 500));
      }
      await MusicPlayerService.instance.pause();
      await player.setVolume(initialVol); // restore volume for future play
    } catch (e) {
      debugPrint('[SleepTimer] Error during fade-out: $e');
      await MusicPlayerService.instance.pause();
    }
  }

  String get formattedRemaining {
    final d = remainingNotifier.value;
    if (d == null) return '';
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
