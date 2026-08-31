import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../config/constants.dart';
import '../models/music_track.dart';
import '../services/music_player_service.dart';
import '../services/streaming_links_service.dart';

/// Floating mini player bar displayed across screens when audio is active
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final playerService = MusicPlayerService.instance;

    return ValueListenableBuilder<MusicTrack?>(
      valueListenable: playerService.currentTrackNotifier,
      builder: (context, track, child) {
        if (track == null) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () => _showFullPlayer(context, track),
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.line),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Live progress line
                StreamBuilder<Duration>(
                  stream: playerService.positionStream,
                  builder: (context, snapshot) {
                    final position = snapshot.data ?? Duration.zero;
                    final total = playerService.player.duration ?? Duration.zero;
                    final progress = total.inMilliseconds > 0
                        ? (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
                        : 0.0;

                    return ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 2,
                        backgroundColor: Colors.transparent,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                      ),
                    );
                  },
                ),

                // Controls row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      // Artwork thumbnail
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: track.artworkUrl != null && track.artworkUrl!.isNotEmpty
                            ? Image.network(
                                track.artworkUrl!,
                                width: 42,
                                height: 42,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => _fallbackThumb(),
                              )
                            : _fallbackThumb(),
                      ),
                      const SizedBox(width: 10),

                      // Title & Artist
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              track.title,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              track.artist,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      // Buffering / Play / Pause button
                      ValueListenableBuilder<bool>(
                        valueListenable: playerService.isBufferingNotifier,
                        builder: (context, isBuffering, _) {
                          if (isBuffering) {
                            return const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            );
                          }

                          return StreamBuilder<PlayerState>(
                            stream: playerService.playerStateStream,
                            builder: (context, snapshot) {
                              final isPlaying = snapshot.data?.playing ?? false;
                              return IconButton(
                                icon: Icon(
                                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  color: AppColors.textPrimary,
                                  size: 26,
                                ),
                                onPressed: playerService.togglePlayPause,
                              );
                            },
                          );
                        },
                      ),

                      // Stop / Close button
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                        onPressed: playerService.stop,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _fallbackThumb() {
    return Container(
      width: 42,
      height: 42,
      color: AppColors.surfaceLight,
      child: const Icon(Icons.music_note_rounded, size: 20, color: AppColors.textMuted),
    );
  }

  void _showFullPlayer(BuildContext context, MusicTrack track) {
    final playerService = MusicPlayerService.instance;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top handle
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),

                // Large Artwork
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: track.artworkUrl != null && track.artworkUrl!.isNotEmpty
                      ? Image.network(
                          track.artworkUrl!,
                          width: 220,
                          height: 220,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            width: 220,
                            height: 220,
                            color: AppColors.surfaceLight,
                            child: const Icon(Icons.music_note_rounded, size: 80, color: AppColors.textMuted),
                          ),
                        )
                      : Container(
                          width: 220,
                          height: 220,
                          color: AppColors.surfaceLight,
                          child: const Icon(Icons.music_note_rounded, size: 80, color: AppColors.textMuted),
                        ),
                ),
                const SizedBox(height: 24),

                // Title & Artist
                Text(
                  track.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  track.artist,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.textMuted),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 20),

                // Seeker Bar
                StreamBuilder<Duration>(
                  stream: playerService.positionStream,
                  builder: (context, snapshot) {
                    final position = snapshot.data ?? Duration.zero;
                    final total = playerService.player.duration ?? Duration.zero;

                    return Column(
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            activeTrackColor: AppColors.textPrimary,
                            inactiveTrackColor: AppColors.line,
                            thumbColor: AppColors.textPrimary,
                          ),
                          child: Slider(
                            value: total.inMilliseconds > 0
                                ? position.inMilliseconds.clamp(0, total.inMilliseconds).toDouble()
                                : 0.0,
                            max: total.inMilliseconds > 0 ? total.inMilliseconds.toDouble() : 1.0,
                            onChanged: (val) {
                              playerService.seek(Duration(milliseconds: val.toInt()));
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_formatDuration(position), style: Theme.of(context).textTheme.bodySmall),
                              Text(_formatDuration(total), style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Playback Control Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.replay_10_rounded, size: 28, color: AppColors.textSecondary),
                      onPressed: () {
                        final current = playerService.player.position;
                        playerService.seek(current - const Duration(seconds: 10));
                      },
                    ),
                    const SizedBox(width: 20),
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.textPrimary,
                      ),
                      child: StreamBuilder<PlayerState>(
                        stream: playerService.playerStateStream,
                        builder: (context, snapshot) {
                          final isPlaying = snapshot.data?.playing ?? false;
                          return IconButton(
                            icon: Icon(
                              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.black,
                              size: 34,
                            ),
                            onPressed: playerService.togglePlayPause,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 20),
                    IconButton(
                      icon: const Icon(Icons.forward_10_rounded, size: 28, color: AppColors.textSecondary),
                      onPressed: () {
                        final current = playerService.player.position;
                        playerService.seek(current + const Duration(seconds: 10));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Quick Streaming Apps
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _IconStreamButton(
                      label: 'Spotify',
                      icon: Icons.graphic_eq_rounded,
                      color: const Color(0xFF1DB954),
                      onTap: () => StreamingLinksService.openSpotify(title: track.title, artist: track.artist),
                    ),
                    _IconStreamButton(
                      label: 'YT Music',
                      icon: Icons.play_circle_filled_rounded,
                      color: const Color(0xFFFF0000),
                      onTap: () => StreamingLinksService.openYouTubeMusic(title: track.title, artist: track.artist),
                    ),
                    _IconStreamButton(
                      label: 'Apple',
                      icon: Icons.music_note_rounded,
                      color: const Color(0xFFFA243C),
                      onTap: () => StreamingLinksService.openAppleMusic(title: track.title, artist: track.artist),
                    ),
                    _IconStreamButton(
                      label: 'Amazon',
                      icon: Icons.all_inclusive_rounded,
                      color: const Color(0xFF00A8E1),
                      onTap: () => StreamingLinksService.openAmazonMusic(title: track.title, artist: track.artist),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _IconStreamButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _IconStreamButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}
