import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

enum EqPreset {
  flat,
  bassBoost,
  rock,
  pop,
  vocal,
  electronic,
}

class EqualizerState {
  final bool isEnabled;
  final EqPreset currentPreset;
  final double bassBoost; // 0.0 to 1.0
  final List<double> bandGains; // 5 bands: 60Hz, 230Hz, 910Hz, 3.6kHz, 14kHz (-10dB to +10dB)

  const EqualizerState({
    this.isEnabled = true,
    this.currentPreset = EqPreset.flat,
    this.bassBoost = 0.0,
    this.bandGains = const [0.0, 0.0, 0.0, 0.0, 0.0],
  });

  EqualizerState copyWith({
    bool? isEnabled,
    EqPreset? currentPreset,
    double? bassBoost,
    List<double>? bandGains,
  }) {
    return EqualizerState(
      isEnabled: isEnabled ?? this.isEnabled,
      currentPreset: currentPreset ?? this.currentPreset,
      bassBoost: bassBoost ?? this.bassBoost,
      bandGains: bandGains ?? this.bandGains,
    );
  }
}

/// Service managing audio equalizer profiles and bass boost
class AudioEqualizerService {
  AudioEqualizerService._() {
    _init();
  }
  static final AudioEqualizerService instance = AudioEqualizerService._();

  final ValueNotifier<EqualizerState> stateNotifier =
      ValueNotifier<EqualizerState>(const EqualizerState());

  EqualizerState get state => stateNotifier.value;

  AndroidEqualizer? _androidEqualizer;

  static const List<String> bandLabels = ['60Hz', '230Hz', '910Hz', '3.6kHz', '14kHz'];

  static const Map<EqPreset, List<double>> presetGains = {
    EqPreset.flat: [0.0, 0.0, 0.0, 0.0, 0.0],
    EqPreset.bassBoost: [6.0, 4.5, 1.0, 0.0, -1.0],
    EqPreset.rock: [4.5, 2.5, -1.0, 2.0, 4.5],
    EqPreset.pop: [-1.0, 2.0, 4.5, 2.5, -1.0],
    EqPreset.vocal: [-2.0, 1.0, 5.0, 3.5, 1.0],
    EqPreset.electronic: [5.0, 3.5, 0.5, 2.0, 4.0],
  };

  void _init() {
    try {
      _androidEqualizer = AndroidEqualizer();
      _androidEqualizer?.setEnabled(true);
    } catch (e) {
      debugPrint('[AudioEqualizer] Native equalizer initialization: $e');
    }
  }

  void toggleEnabled(bool enabled) {
    stateNotifier.value = state.copyWith(isEnabled: enabled);
    _applyToHardware();
  }

  void setPreset(EqPreset preset) {
    final gains = presetGains[preset] ?? presetGains[EqPreset.flat]!;
    final boost = preset == EqPreset.bassBoost ? 0.7 : 0.0;
    stateNotifier.value = state.copyWith(
      currentPreset: preset,
      bandGains: List<double>.from(gains),
      bassBoost: boost,
    );
    _applyToHardware();
  }

  void setBandGain(int bandIndex, double gain) {
    if (bandIndex < 0 || bandIndex >= state.bandGains.length) return;
    final updated = List<double>.from(state.bandGains);
    updated[bandIndex] = gain.clamp(-10.0, 10.0);
    stateNotifier.value = state.copyWith(
      bandGains: updated,
      currentPreset: EqPreset.flat, // custom
    );
    _applyToHardware();
  }

  void setBassBoost(double value) {
    stateNotifier.value = state.copyWith(bassBoost: value.clamp(0.0, 1.0));
    _applyToHardware();
  }

  void _applyToHardware() {
    try {
      if (_androidEqualizer != null && state.isEnabled) {
        _androidEqualizer!.setEnabled(true);
      }
    } catch (_) {}
  }
}
