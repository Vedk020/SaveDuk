import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/constants.dart';
import '../services/audio_equalizer_service.dart';

class EqualizerSheet extends StatelessWidget {
  const EqualizerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const EqualizerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eq = AudioEqualizerService.instance;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: ValueListenableBuilder<EqualizerState>(
          valueListenable: eq.stateNotifier,
          builder: (context, state, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle Bar
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Title row with switch
                Row(
                  children: [
                    const Icon(Icons.graphic_eq_rounded, color: Colors.greenAccent, size: 24),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('EQUALIZER & BASS BOOST',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1.0)),
                          Text('5-band hardware tuning & acoustic presets',
                              style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                    Switch(
                      value: state.isEnabled,
                      activeThumbColor: Colors.greenAccent,
                      activeTrackColor: Colors.greenAccent.withValues(alpha: 0.4),
                      onChanged: (val) {
                        HapticFeedback.lightImpact();
                        eq.toggleEnabled(val);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Presets horizontal list
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildPresetChip(context, 'FLAT', EqPreset.flat, state.currentPreset),
                      const SizedBox(width: 8),
                      _buildPresetChip(context, 'BASS BOOST 🔥', EqPreset.bassBoost, state.currentPreset),
                      const SizedBox(width: 8),
                      _buildPresetChip(context, 'ROCK 🎸', EqPreset.rock, state.currentPreset),
                      const SizedBox(width: 8),
                      _buildPresetChip(context, 'POP 🎵', EqPreset.pop, state.currentPreset),
                      const SizedBox(width: 8),
                      _buildPresetChip(context, 'VOCAL 🎙️', EqPreset.vocal, state.currentPreset),
                      const SizedBox(width: 8),
                      _buildPresetChip(context, 'ELECTRONIC ⚡', EqPreset.electronic, state.currentPreset),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Bass Boost Slider
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.speaker_rounded, color: Colors.amberAccent, size: 20),
                      const SizedBox(width: 10),
                      const Text('Bass Boost', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const Spacer(),
                      Text('${(state.bassBoost * 100).toInt()}%',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amberAccent, fontSize: 12)),
                      Expanded(
                        flex: 2,
                        child: Slider(
                          value: state.bassBoost,
                          min: 0.0,
                          max: 1.0,
                          activeColor: Colors.amberAccent,
                          inactiveColor: AppColors.line,
                          onChanged: state.isEnabled
                              ? (val) {
                                  HapticFeedback.selectionClick();
                                  eq.setBassBoost(val);
                                }
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 5-Band Vertical EQ Sliders
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(5, (index) {
                          final gain = state.bandGains[index];
                          final label = AudioEqualizerService.bandLabels[index];

                          return Column(
                            children: [
                              Text('${gain > 0 ? '+' : ''}${gain.toStringAsFixed(0)}dB',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: gain != 0 ? Colors.greenAccent : AppColors.textMuted,
                                  )),
                              SizedBox(
                                height: 120,
                                child: RotatedBox(
                                  quarterTurns: -1,
                                  child: Slider(
                                    value: gain,
                                    min: -10.0,
                                    max: 10.0,
                                    activeColor: Colors.greenAccent,
                                    inactiveColor: AppColors.line,
                                    onChanged: state.isEnabled
                                        ? (v) {
                                            eq.setBandGain(index, v);
                                          }
                                        : null,
                                  ),
                                ),
                              ),
                              Text(label,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  )),
                            ],
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPresetChip(BuildContext context, String title, EqPreset preset, EqPreset activePreset) {
    final isSelected = preset == activePreset;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        AudioEqualizerService.instance.setPreset(preset);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? Colors.greenAccent.withValues(alpha: 0.15) : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.greenAccent : AppColors.line,
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.greenAccent : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
