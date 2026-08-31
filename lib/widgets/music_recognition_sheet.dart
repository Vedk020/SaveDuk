import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../models/music_track.dart';
import '../services/music_player_service.dart';
import '../services/music_recognition_service.dart';
import '../services/music_storage_service.dart';
import '../services/on_device_extractor_service.dart';
import '../services/streaming_links_service.dart';

/// Modal sheet displaying live animated music recognition, track metadata,
/// external streaming links (Spotify, YT Music, Apple, Amazon), and in-app streaming.
class MusicRecognitionSheet extends StatefulWidget {
  final String? urlToRecognize;
  final RecognizedTrack? initialRecognized;

  const MusicRecognitionSheet({
    super.key,
    this.urlToRecognize,
    this.initialRecognized,
  });

  /// Launch the live animated recognition modal immediately when a video link is shared
  static Future<void> startRecognition(BuildContext context, String url) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => MusicRecognitionSheet(urlToRecognize: url),
    );
  }

  /// Show recognized track details directly
  static Future<void> show(BuildContext context, RecognizedTrack recognized) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => MusicRecognitionSheet(initialRecognized: recognized),
    );
  }

  @override
  State<MusicRecognitionSheet> createState() => _MusicRecognitionSheetState();
}

class _MusicRecognitionSheetState extends State<MusicRecognitionSheet>
    with TickerProviderStateMixin {
  final MusicRecognitionService _musicService = MusicRecognitionService();
  final OnDeviceExtractorService _extractor = OnDeviceExtractorService();
  final TextEditingController _manualSearchController = TextEditingController();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  RecognizedTrack? _recognized;
  bool _isRecognizing = false;
  String _statusMessage = 'EXTRACTING AUDIO…';
  int _currentStep = 1;
  String? _errorMessage;

  bool _isSaved = false;
  bool _isSaving = false;
  double _saveProgress = 0.0;

  List<SearchTrackResult> _manualSearchResults = [];
  bool _isManualSearching = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.initialRecognized != null) {
      _recognized = widget.initialRecognized;
      _checkIfSaved();
    } else if (widget.urlToRecognize != null) {
      _runLiveRecognition(widget.urlToRecognize!);
    }
  }

  Future<void> _runLiveRecognition(String url) async {
    setState(() {
      _isRecognizing = true;
      _statusMessage = 'EXTRACTING AUDIO STREAM…';
      _currentStep = 1;
      _errorMessage = null;
    });

    try {
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) {
        setState(() {
          _statusMessage = 'IDENTIFYING ACOUSTIC FINGERPRINT…';
          _currentStep = 2;
        });
      }

      final result = await _musicService.identifyFromUrl(url);

      if (mounted) {
        if (result != null) {
          setState(() {
            _statusMessage = 'MATCHING STREAMING SERVICES…';
            _currentStep = 3;
          });
          await Future.delayed(const Duration(milliseconds: 300));
          if (mounted) {
            setState(() {
              _recognized = result;
              _isRecognizing = false;
            });
            _checkIfSaved();
          }
        } else {
          setState(() {
            _isRecognizing = false;
            _errorMessage = 'Could not automatically identify music from this video.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRecognizing = false;
          _errorMessage = 'Recognition error: $e';
        });
      }
    }
  }

  Future<void> _performManualSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    setState(() => _isManualSearching = true);
    final results = await _extractor.searchTracks(q, limit: 5);
    if (mounted) {
      setState(() {
        _manualSearchResults = results;
        _isManualSearching = false;
      });
    }
  }

  Future<void> _selectManualTrack(SearchTrackResult searchTrack) async {
    final track = MusicTrack(
      id: searchTrack.id,
      title: searchTrack.title,
      artist: searchTrack.artist,
      artworkUrl: searchTrack.thumbnail,
      originalMediaUrl: searchTrack.url,
      durationSeconds: searchTrack.duration,
      createdAt: DateTime.now(),
    );

    setState(() {
      _recognized = RecognizedTrack(
        track: track,
        audioStreamUrl: null,
        identifiedAcoustically: true,
      );
      _errorMessage = null;
    });
    _checkIfSaved();
  }

  Future<void> _checkIfSaved() async {
    if (_recognized == null) return;
    final tracks = await MusicStorageService.getAllTracks();
    final exists = tracks.any((t) =>
        t.title == _recognized!.track.title && t.artist == _recognized!.track.artist);
    if (mounted) {
      setState(() => _isSaved = exists);
    }
  }

  Future<void> _handleSave() async {
    if (_recognized == null || _isSaved || _isSaving) return;
    setState(() {
      _isSaving = true;
      _saveProgress = 0.0;
    });

    try {
      await MusicStorageService.downloadAndSaveTrack(
        _recognized!.track,
        audioUrl: _recognized!.audioStreamUrl,
        onProgress: (progress) {
          if (mounted) setState(() => _saveProgress = progress);
        },
      );
      if (mounted) {
        setState(() {
          _isSaved = true;
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved to Music Library ✓'),
            backgroundColor: AppColors.surfaceLight,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handlePlay() async {
    if (_recognized == null) return;
    try {
      await MusicPlayerService.instance.playTrack(
        _recognized!.track,
        directAudioUrl: _recognized!.audioStreamUrl,
        headers: _recognized!.headers,
      );
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Playback error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _manualSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
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

            // State 1: Live Recognizing Animation
            if (_isRecognizing) _buildRecognizingState(),

            // State 2: Recognition Error & Manual Search Fallback
            if (!_isRecognizing && _errorMessage != null) _buildErrorState(),

            // State 3: Recognized Track Details & Actions
            if (!_isRecognizing && _recognized != null) _buildRecognizedState(),
          ],
        ),
      ),
    );
  }

  Widget _buildRecognizingState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          // Glowing Pulsing Radar with Music Logo
          Center(
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer ripple
                    Container(
                      width: 140 * _pulseAnimation.value,
                      height: 140 * _pulseAnimation.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.greenAccent.withValues(
                          alpha: (0.15 * (1.2 - _pulseAnimation.value + 0.8)).clamp(0.0, 0.25),
                        ),
                      ),
                    ),
                    // Inner glow ring
                    Container(
                      width: 108 * _pulseAnimation.value,
                      height: 108 * _pulseAnimation.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.greenAccent.withValues(alpha: 0.6),
                          width: 2,
                        ),
                      ),
                    ),
                    // Central Music Logo
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.cardBackground,
                        border: Border.all(color: AppColors.line, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.greenAccent.withValues(alpha: 0.3),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/images/logo_music.png',
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 28),

          // Title & Live Status
          Text(
            'IDENTIFYING MUSIC…',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: AppColors.textPrimary,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            _statusMessage,
            style: const TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),

          // Step Progress Dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildStepIndicator(1, 'Audio'),
              const SizedBox(width: 8),
              _buildStepIndicator(2, 'Fingerprint'),
              const SizedBox(width: 8),
              _buildStepIndicator(3, 'Match'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(int step, String label) {
    final isActive = _currentStep >= step;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? Colors.greenAccent.withValues(alpha: 0.15) : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isActive ? Colors.greenAccent : AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isActive ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 11,
            color: isActive ? Colors.greenAccent : AppColors.textMuted,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isActive ? Colors.greenAccent : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.amberAccent, size: 20),
            const SizedBox(width: 8),
            Text('MUSIC NOT FOUND', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _errorMessage ?? 'Could not automatically identify the background audio.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),

        // Search manually
        TextField(
          controller: _manualSearchController,
          decoration: InputDecoration(
            hintText: 'Search song or artist manually…',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_forward_rounded),
              onPressed: () => _performManualSearch(_manualSearchController.text),
            ),
          ),
          onSubmitted: _performManualSearch,
        ),
        const SizedBox(height: 12),

        if (_isManualSearching)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator(color: AppColors.textPrimary)),
          ),

        if (_manualSearchResults.isNotEmpty) ...[
          Text('SELECT MATCHING TRACK:', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ..._manualSearchResults.map(
            (t) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: t.thumbnail != null && t.thumbnail!.isNotEmpty
                    ? Image.network(
                        t.thumbnail!,
                        width: 42,
                        height: 42,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => _fallbackArtwork(),
                      )
                    : _fallbackArtwork(),
              ),
              title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.check_rounded, color: Colors.greenAccent),
              onTap: () => _selectManualTrack(t),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRecognizedState() {
    final track = _recognized!.track;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Tag
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.music_note_rounded, size: 12, color: Colors.greenAccent),
                  const SizedBox(width: 4),
                  Text(
                    _recognized!.identifiedAcoustically ? 'IDENTIFIED TRACK' : 'RECOGNIZED TRACK',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.greenAccent,
                        ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 20, color: AppColors.textMuted),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Track Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: track.artworkUrl != null && track.artworkUrl!.isNotEmpty
                    ? Image.network(
                        track.artworkUrl!,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => _fallbackArtwork(),
                      )
                    : _fallbackArtwork(),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.artist,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Stream & Save buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _handlePlay,
                icon: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 22),
                label: const Text('Stream Free', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isSaving ? null : _handleSave,
                icon: _isSaving
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: _saveProgress > 0 ? _saveProgress : null,
                          color: AppColors.textPrimary,
                        ),
                      )
                    : Icon(
                        _isSaved ? Icons.check_circle_rounded : Icons.bookmark_add_outlined,
                        size: 18,
                        color: _isSaved ? Colors.greenAccent : AppColors.textPrimary,
                      ),
                label: Text(
                  _isSaving
                      ? '${(_saveProgress * 100).toInt()}%'
                      : _isSaved
                          ? 'Saved'
                          : 'Save Track',
                  style: TextStyle(
                    color: _isSaved ? Colors.greenAccent : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _isSaved ? Colors.greenAccent.withValues(alpha: 0.5) : AppColors.line),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),

        // Open in Streaming Apps Section
        Text(
          'OPEN IN STREAMING APPS',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11,
                letterSpacing: 1.0,
                fontWeight: FontWeight.bold,
                color: AppColors.textMuted,
              ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _StreamingButton(
              name: 'Spotify',
              icon: Icons.graphic_eq_rounded,
              color: const Color(0xFF1DB954),
              onTap: () => StreamingLinksService.openSpotify(title: track.title, artist: track.artist),
            ),
            const SizedBox(width: 8),
            _StreamingButton(
              name: 'YT Music',
              icon: Icons.play_circle_filled_rounded,
              color: const Color(0xFFFF0000),
              onTap: () => StreamingLinksService.openYouTubeMusic(title: track.title, artist: track.artist),
            ),
            const SizedBox(width: 8),
            _StreamingButton(
              name: 'Apple',
              icon: Icons.music_note_rounded,
              color: const Color(0xFFFA243C),
              onTap: () => StreamingLinksService.openAppleMusic(title: track.title, artist: track.artist),
            ),
            const SizedBox(width: 8),
            _StreamingButton(
              name: 'Amazon',
              icon: Icons.all_inclusive_rounded,
              color: const Color(0xFF00A8E1),
              onTap: () => StreamingLinksService.openAmazonMusic(title: track.title, artist: track.artist),
            ),
          ],
        ),
      ],
    );
  }

  Widget _fallbackArtwork() {
    return Container(
      width: 64,
      height: 64,
      color: AppColors.surfaceLight,
      child: const Icon(Icons.music_note_rounded, size: 30, color: AppColors.textMuted),
    );
  }
}

class _StreamingButton extends StatelessWidget {
  final String name;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _StreamingButton({
    required this.name,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 4),
              Text(
                name,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
