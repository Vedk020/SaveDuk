import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../config/constants.dart';
import '../models/music_track.dart';
import '../services/music_player_service.dart';
import '../services/music_storage_service.dart';
import '../services/on_device_extractor_service.dart';
import '../services/settings_service.dart';
import '../services/streaming_links_service.dart';
import 'about_screen.dart';
import 'settings_screen.dart';

/// Music Screen — Free ad-free music streamer, search engine, and library
class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key});

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final OnDeviceExtractorService _extractor = OnDeviceExtractorService();
  late TabController _tabController;

  List<SearchTrackResult> _searchResults = [];
  List<MusicTrack> _savedTracks = [];
  bool _isSearching = false;
  bool _isLoadingLibrary = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadLibrary();
    _loadInitialTrending();
  }

  Future<void> _loadLibrary() async {
    setState(() => _isLoadingLibrary = true);
    try {
      final tracks = await MusicStorageService.getAllTracks();
      if (mounted) {
        setState(() {
          _savedTracks = tracks;
          _isLoadingLibrary = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingLibrary = false);
    }
  }

  Future<void> _loadInitialTrending() async {
    final trending = await _extractor.searchTracks('trending songs', limit: 8);
    if (mounted && _searchResults.isEmpty) {
      setState(() => _searchResults = trending);
    }
  }

  Future<void> _performSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;

    setState(() => _isSearching = true);
    final results = await _extractor.searchTracks(q, limit: 15);
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  Future<void> _playSearchResult(SearchTrackResult searchTrack) async {
    final track = MusicTrack(
      id: searchTrack.id,
      title: searchTrack.title,
      artist: searchTrack.artist,
      album: searchTrack.album,
      artworkUrl: searchTrack.thumbnail,
      originalMediaUrl: searchTrack.url,
      durationSeconds: searchTrack.duration,
      createdAt: DateTime.now(),
    );

    try {
      await MusicPlayerService.instance.playTrack(track);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Playback failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _playSavedTrack(MusicTrack track) async {
    try {
      await MusicPlayerService.instance.playTrack(track);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Playback failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _saveTrackToLibrary(SearchTrackResult searchTrack) async {
    final track = MusicTrack(
      id: searchTrack.id.isNotEmpty ? searchTrack.id : const Uuid().v4(),
      title: searchTrack.title,
      artist: searchTrack.artist,
      artworkUrl: searchTrack.thumbnail,
      originalMediaUrl: searchTrack.url,
      durationSeconds: searchTrack.duration,
      createdAt: DateTime.now(),
    );

    try {
      await MusicStorageService.saveTrack(track);
      await _loadLibrary();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Added to Library ✓'),
            backgroundColor: AppColors.surfaceLight,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          ValueListenableBuilder<String>(
                            valueListenable: SettingsService.instance.activeLogoNotifier,
                            builder: (context, activeLogo, _) {
                              return Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.line),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(7),
                                  child: Image.asset(
                                    activeLogo,
                                    width: 38,
                                    height: 38,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onLongPress: () {
                              HapticFeedback.heavyImpact();
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const AboutScreen()),
                              );
                            },
                            child: Text(
                              'SAVEDUK//MUSIC',
                              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                                    fontSize: 22,
                                    letterSpacing: -1.0,
                                  ),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceLight,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.line),
                            ),
                            child: const Text(
                              'FREE & NO ADS',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.greenAccent,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const SettingsScreen()),
                              );
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceLight,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.line),
                              ),
                              child: const Icon(
                                Icons.tune_rounded,
                                size: 16,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'STREAM ANY TRACK. FREE FOR PUBLIC.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),

                      // Search Box
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: 'Search songs, artists, albums…',
                                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 18, color: AppColors.textMuted),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() {});
                                        },
                                      )
                                    : null,
                              ),
                              onSubmitted: _performSearch,
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => _performSearch(_searchController.text),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: AppColors.textPrimary,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.line),
                              ),
                              child: const Icon(Icons.arrow_forward_rounded, color: Colors.black, size: 22),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Tabs
                      TabBar(
                        controller: _tabController,
                        indicatorColor: AppColors.textPrimary,
                        labelColor: AppColors.textPrimary,
                        unselectedLabelColor: AppColors.textMuted,
                        tabs: const [
                          Tab(text: 'EXPLORE'),
                          Tab(text: 'MY LIBRARY'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ];
          },
          body: TabBarView(
            controller: _tabController,
            children: [
              // Tab 1: Search & Explore
              _buildExploreTab(),

              // Tab 2: Library
              _buildLibraryTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExploreTab() {
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.textPrimary),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          'Search any song or artist to stream for free',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final track = _searchResults[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.line),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: track.thumbnail != null && track.thumbnail!.isNotEmpty
                  ? Image.network(
                      track.thumbnail!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => _fallbackThumb(),
                    )
                  : _fallbackThumb(),
            ),
            title: Text(
              track.title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              track.artist,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.bookmark_add_outlined, size: 20, color: AppColors.textSecondary),
                  tooltip: 'Save to Library',
                  onPressed: () => _saveTrackToLibrary(track),
                ),
                IconButton(
                  icon: const Icon(Icons.play_circle_filled_rounded, size: 30, color: AppColors.textPrimary),
                  tooltip: 'Play',
                  onPressed: () => _playSearchResult(track),
                ),
              ],
            ),
            onTap: () => _playSearchResult(track),
          ),
        );
      },
    );
  }

  Widget _buildLibraryTab() {
    if (_isLoadingLibrary) {
      return const Center(child: CircularProgressIndicator(color: AppColors.textPrimary));
    }

    return RefreshIndicator(
      onRefresh: _loadLibrary,
      color: AppColors.textPrimary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        children: [
          // Playlist Import Banner (Roadmap feature)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                const Icon(Icons.playlist_add_rounded, color: Colors.greenAccent, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'IMPORT PLAYLISTS',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Paste any public Spotify or YT Music playlist link to import all tracks for free.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (_savedTracks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.music_note_outlined, size: 48, color: AppColors.textMuted),
                    const SizedBox(height: 12),
                    Text('No saved tracks yet', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Search for music or share videos to SaveDuk Music',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Text(
              'SAVED TRACKS (${_savedTracks.length})',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._savedTracks.map((track) => _buildSavedTrackTile(track)),
          ],
        ],
      ),
    );
  }

  Widget _buildSavedTrackTile(MusicTrack track) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: track.artworkUrl != null && track.artworkUrl!.isNotEmpty
              ? Image.network(
                  track.artworkUrl!,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => _fallbackThumb(),
                )
              : _fallbackThumb(),
        ),
        title: Text(
          track.title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${track.artist} ${track.durationText != '--:--' ? '• ${track.durationText}' : ''}',
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded, size: 18, color: AppColors.textMuted),
              tooltip: 'Open in Spotify',
              onPressed: () => StreamingLinksService.openSpotify(title: track.title, artist: track.artist),
            ),
            IconButton(
              icon: const Icon(Icons.play_circle_filled_rounded, size: 28, color: AppColors.textPrimary),
              onPressed: () => _playSavedTrack(track),
            ),
          ],
        ),
        onTap: () => _playSavedTrack(track),
      ),
    );
  }

  Widget _fallbackThumb() {
    return Container(
      width: 48,
      height: 48,
      color: AppColors.surfaceLight,
      child: const Icon(Icons.music_note_rounded, size: 24, color: AppColors.textMuted),
    );
  }
}
