import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import '../config/constants.dart';
import '../models/music_track.dart';
import '../services/lyrics_service.dart';
import '../services/music_player_service.dart';
import '../services/sleep_timer_service.dart';
import '../services/streaming_links_service.dart';
import 'equalizer_sheet.dart';

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
          onTap: () {
            HapticFeedback.lightImpact();
            _showFullPlayer(context, track);
          },
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
                // Isolated live progress line with RepaintBoundary
                const RepaintBoundary(child: _MiniProgressBar()),

                // Controls row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      // Artwork thumbnail with downscaled memory cache
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: track.artworkUrl != null && track.artworkUrl!.isNotEmpty
                            ? Image.network(
                                track.artworkUrl!,
                                width: 42,
                                height: 42,
                                cacheWidth: 126,
                                cacheHeight: 126,
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
                                  isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: AppColors.textPrimary,
                                  size: 28,
                                ),
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  playerService.togglePlayPause();
                                },
                              );
                            },
                          );
                        },
                      ),

                      // Close / Stop button
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.textMuted,
                          size: 20,
                        ),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          playerService.stop();
                        },
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

  void _showFullPlayer(BuildContext context, MusicTrack initialTrack) {
    final playerService = MusicPlayerService.instance;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalContext) {
        bool showLyrics = false;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return ValueListenableBuilder<MusicTrack?>(
              valueListenable: playerService.currentTrackNotifier,
              builder: (context, track, _) {
                final current = track ?? initialTrack;

                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
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
                        const SizedBox(height: 14),

                        // Top Bar with Pro Tools (Lyrics, EQ, Sleep Timer, Down)
                        Row(
                          children: [
                            const Text(
                              'NOW PLAYING',
                              style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textMuted,
                              ),
                            ),
                            const Spacer(),

                            // Sleep Timer Button with Countdown
                            ValueListenableBuilder<Duration?>(
                              valueListenable: SleepTimerService.instance.remainingNotifier,
                              builder: (context, remaining, _) {
                                final isActive = remaining != null || SleepTimerService.instance.stopAtEndOfTrackNotifier.value;
                                return IconButton(
                                  icon: Icon(
                                    isActive ? Icons.bedtime_rounded : Icons.bedtime_outlined,
                                    size: 20,
                                    color: isActive ? Colors.amberAccent : AppColors.textSecondary,
                                  ),
                                  tooltip: 'Sleep Timer',
                                  onPressed: () => _showSleepTimerModal(context),
                                );
                              },
                            ),

                            // Equalizer Button
                            IconButton(
                              icon: const Icon(Icons.tune_rounded, size: 20, color: AppColors.textSecondary),
                              tooltip: 'Equalizer & Bass Boost',
                              onPressed: () => EqualizerSheet.show(context),
                            ),

                            // Lyrics Toggle Button
                            IconButton(
                              icon: Icon(
                                showLyrics ? Icons.image_rounded : Icons.lyrics_rounded,
                                size: 20,
                                color: showLyrics ? Colors.greenAccent : AppColors.textSecondary,
                              ),
                              tooltip: showLyrics ? 'Show Artwork' : 'Show Synced Lyrics',
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                setModalState(() => showLyrics = !showLyrics);
                              },
                            ),

                            IconButton(
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
                              onPressed: () => Navigator.pop(modalContext),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Center Display: Either 220px Artwork OR Live Lyrics
                        if (!showLyrics)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: current.artworkUrl != null && current.artworkUrl!.isNotEmpty
                                ? Image.network(
                                    current.artworkUrl!,
                                    width: 220,
                                    height: 220,
                                    cacheWidth: 440,
                                    cacheHeight: 440,
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
                          )
                        else
                          _FullPlayerLyricsView(track: current),

                        const SizedBox(height: 20),

                    // Title & Artist
                    Text(
                      current.title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      current.artist,
                      style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),

                    // RepaintBoundary isolated Seeker Bar
                    const RepaintBoundary(child: _FullPlayerSeekBar()),
                    const SizedBox(height: 16),

                    // Playback Control Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.replay_10_rounded, size: 28, color: AppColors.textSecondary),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            final pos = playerService.player.position;
                            playerService.seek(pos - const Duration(seconds: 10));
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
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  playerService.togglePlayPause();
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 20),
                        IconButton(
                          icon: const Icon(Icons.forward_10_rounded, size: 28, color: AppColors.textSecondary),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            final pos = playerService.player.position;
                            playerService.seek(pos + const Duration(seconds: 10));
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Open in External Streaming Apps
                    const Text(
                      'OPEN IN APPS',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.0,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _externalAppChip('Spotify', const Color(0xFF1DB954), () {
                          HapticFeedback.lightImpact();
                          StreamingLinksService.openSpotify(title: current.title, artist: current.artist);
                        }),
                        const SizedBox(width: 8),
                        _externalAppChip('YT Music', const Color(0xFFFF0000), () {
                          HapticFeedback.lightImpact();
                          StreamingLinksService.openYouTubeMusic(title: current.title, artist: current.artist);
                        }),
                        const SizedBox(width: 8),
                        _externalAppChip('Apple', const Color(0xFFFA243C), () {
                          HapticFeedback.lightImpact();
                          StreamingLinksService.openAppleMusic(title: current.title, artist: current.artist);
                        }),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  },
);
}

  static Widget _fallbackThumb() {
    return Container(
      width: 42,
      height: 42,
      color: AppColors.surfaceLight,
      child: const Icon(Icons.music_note_rounded, size: 20, color: AppColors.textMuted),
    );
  }

  static Widget _externalAppChip(String name, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
            const SizedBox(width: 6),
            Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// Dedicated Progress Bar widget isolated from parent rebuilds
class _MiniProgressBar extends StatelessWidget {
  const _MiniProgressBar();

  @override
  Widget build(BuildContext context) {
    final playerService = MusicPlayerService.instance;

    return StreamBuilder<Duration>(
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
    );
  }
}

/// Dedicated Slider widget for the full player sheet
class _FullPlayerSeekBar extends StatelessWidget {
  const _FullPlayerSeekBar();

  @override
  Widget build(BuildContext context) {
    final playerService = MusicPlayerService.instance;

    return StreamBuilder<Duration>(
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
    );
  }

  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Dedicated live synchronized karaoke lyrics display for the full player
class _FullPlayerLyricsView extends StatefulWidget {
  final MusicTrack track;

  const _FullPlayerLyricsView({required this.track});

  @override
  State<_FullPlayerLyricsView> createState() => _FullPlayerLyricsViewState();
}

class _FullPlayerLyricsViewState extends State<_FullPlayerLyricsView> {
  final ScrollController _scrollController = ScrollController();
  TrackLyrics? _lyrics;
  bool _isLoading = true;
  int _lastActiveIndex = -1;

  @override
  void initState() {
    super.initState();
    _fetchLyrics();
  }

  @override
  void didUpdateWidget(covariant _FullPlayerLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      _fetchLyrics();
    }
  }

  Future<void> _fetchLyrics() async {
    setState(() => _isLoading = true);
    final res = await LyricsService.instance.getLyrics(
      title: widget.track.title,
      artist: widget.track.artist,
      durationSeconds: widget.track.durationSeconds,
    );
    if (mounted) {
      setState(() {
        _lyrics = res;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients || index == _lastActiveIndex) return;
    _lastActiveIndex = index;
    final targetOffset = (index * 44.0).clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final playerService = MusicPlayerService.instance;

    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.greenAccent),
                  ),
                  SizedBox(height: 12),
                  Text('SEARCHING SYNCED LYRICS…',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: AppColors.textMuted)),
                ],
              ),
            )
          : (_lyrics == null || !_lyrics!.hasLyrics)
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'No synchronized lyrics found for this song.\nTap the lyrics button again to view album artwork.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4),
                    ),
                  ),
                )
              : _lyrics!.isSynced
                  ? StreamBuilder<Duration>(
                      stream: playerService.positionStream,
                      builder: (context, snapshot) {
                        final pos = snapshot.data ?? Duration.zero;
                        final lines = _lyrics!.syncedLyrics;

                        // Find current active lyric line
                        int activeIndex = 0;
                        for (int i = 0; i < lines.length; i++) {
                          if (lines[i].timestamp <= pos) {
                            activeIndex = i;
                          } else {
                            break;
                          }
                        }

                        // Auto-scroll to active index
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _scrollToIndex(activeIndex);
                        });

                        return ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 88, horizontal: 16),
                          itemCount: lines.length,
                          itemBuilder: (context, idx) {
                            final line = lines[idx];
                            final isActive = idx == activeIndex;

                            return GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                playerService.seek(line.timestamp);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  line.text,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: isActive ? 16 : 13,
                                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                    color: isActive ? Colors.greenAccent : AppColors.textMuted,
                                    shadows: isActive
                                        ? [
                                            BoxShadow(
                                              color: Colors.greenAccent.withValues(alpha: 0.5),
                                              blurRadius: 10,
                                            ),
                                          ]
                                        : null,
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _lyrics!.plainLyrics ?? '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
                      ),
                    ),
    );
  }
}

/// Quick-picker modal for Sleep Timer
void _showSleepTimerModal(BuildContext context) {
  final sleepService = SleepTimerService.instance;

  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (modalCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const Row(
              children: [
                Icon(Icons.bedtime_rounded, color: Colors.amberAccent, size: 22),
                SizedBox(width: 10),
                Text('SLEEP TIMER',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1.0)),
              ],
            ),
            const SizedBox(height: 14),

            _buildSleepOption(modalCtx, '15 Minutes', const Duration(minutes: 15)),
            _buildSleepOption(modalCtx, '30 Minutes', const Duration(minutes: 30)),
            _buildSleepOption(modalCtx, '45 Minutes', const Duration(minutes: 45)),
            _buildSleepOption(modalCtx, '1 Hour', const Duration(hours: 1)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.music_note_rounded, color: Colors.greenAccent, size: 20),
              title: const Text('End of current song', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              onTap: () {
                HapticFeedback.lightImpact();
                sleepService.setStopAtEndOfTrack(true);
                Navigator.pop(modalCtx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Audio will stop when this song finishes ✓'),
                    backgroundColor: AppColors.surfaceLight,
                  ),
                );
              },
            ),
            if (sleepService.isActive) ...[
              const Divider(color: AppColors.line),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.timer_off_rounded, color: Colors.redAccent, size: 20),
                title: const Text('Turn Off Sleep Timer',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                onTap: () {
                  HapticFeedback.lightImpact();
                  sleepService.cancel();
                  Navigator.pop(modalCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sleep timer turned off'), backgroundColor: AppColors.surfaceLight),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

Widget _buildSleepOption(BuildContext context, String title, Duration duration) {
  return ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.timer_outlined, color: AppColors.textMuted, size: 20),
    title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    onTap: () {
      HapticFeedback.lightImpact();
      SleepTimerService.instance.startTimer(duration);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sleep timer set for $title (with smooth fade-out) ✓'),
          backgroundColor: AppColors.surfaceLight,
        ),
      );
    },
  );
}

