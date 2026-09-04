import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../config/constants.dart';
import '../models/music_track.dart';
import '../services/music_player_service.dart';
import '../services/music_storage_service.dart';
import '../services/on_device_extractor_service.dart';
import '../services/jam_sync_service.dart';
import '../services/settings_service.dart';
import 'about_screen.dart';
import 'playlist_import_screen.dart';
import 'settings_screen.dart';

/// SaveDuk Music Screen — Ad-free music streaming, playlists, and offline library
class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key});

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final OnDeviceExtractorService _extractor = OnDeviceExtractorService();
  late TabController _tabController;

  List<SearchTrackResult> _trendingTracks = [];
  List<SearchTrackResult> _searchResults = [];
  List<MusicTrack> _savedTracks = [];
  List<MusicPlaylist> _playlists = [];
  List<MusicTrack> _offlineTracks = [];
  int _offlineStorageBytes = 0;

  bool _isSearching = false;
  bool _isLoadingTrending = true;
  bool _isLoadingLibrary = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    // 1. Load local offline library instantly
    await _loadLibrary();

    // 2. Defer heavy Python runtime search until after initial UI frames complete
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) _loadTrending();
    });
  }

  Future<void> _loadTrending() async {
    try {
      final trending = await _extractor.searchTracks('top hits 2026 trending songs', limit: 12);
      if (mounted) {
        setState(() {
          _trendingTracks = trending;
          _isLoadingTrending = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingTrending = false);
    }
  }

  Future<void> _loadLibrary() async {
    setState(() => _isLoadingLibrary = true);
    try {
      final tracks = await MusicStorageService.getAllTracks();
      final playlists = await MusicStorageService.getAllPlaylists();
      final offline = await MusicStorageService.getOfflineTracks();
      final storageBytes = await MusicStorageService.getOfflineStorageSizeBytes();

      if (mounted) {
        setState(() {
          _savedTracks = tracks;
          _playlists = playlists;
          _offlineTracks = offline;
          _offlineStorageBytes = storageBytes;
          _isLoadingLibrary = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingLibrary = false);
    }
  }

  Future<void> _performSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    HapticFeedback.lightImpact();
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
    HapticFeedback.lightImpact();
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
          SnackBar(content: Text('Playback failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _playSavedTrack(MusicTrack track) async {
    HapticFeedback.lightImpact();
    try {
      await MusicPlayerService.instance.playTrack(track);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playback failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _saveTrackToLibrary(SearchTrackResult searchTrack) async {
    HapticFeedback.lightImpact();
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
          SnackBar(content: Text('Failed to save: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _showCreatePlaylistDialog() {
    HapticFeedback.lightImpact();
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.line),
        ),
        title: const Text('CREATE PLAYLIST', style: TextStyle(fontSize: 14, letterSpacing: 1.0, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Playlist name (e.g. Chill Beats, Gym)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('CANCEL', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.textPrimary,
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                HapticFeedback.mediumImpact();
                await MusicStorageService.createPlaylist(name);
                if (mounted) {
                  Navigator.pop(dialogCtx);
                  await _loadLibrary();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Playlist "$name" created ✓'),
                      backgroundColor: AppColors.surfaceLight,
                    ),
                  );
                }
              }
            },
            child: const Text('CREATE', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _showImportPlaylistDialog() async {
    HapticFeedback.lightImpact();
    final imported = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PlaylistImportScreen()),
    );
    if (imported == true) {
      await _loadLibrary();
    }
  }

  void _showOfflineSavesSheet() {
    HapticFeedback.lightImpact();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.folder_rounded, color: Colors.amberAccent, size: 24),
                  const SizedBox(width: 10),
                  const Text('OFFLINE SAVES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(sheetCtx),
                  ),
                ],
              ),
              Text(
                '${_offlineTracks.length} tracks downloaded locally • ${_formatStorageSize(_offlineStorageBytes)}',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              if (_offlineTracks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Center(
                    child: Text('No offline downloads yet. Tap download on any track to listen without internet.',
                        textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _offlineTracks.length,
                    itemBuilder: (context, idx) {
                      final track = _offlineTracks[idx];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                          leading: const Icon(Icons.music_note_rounded, color: Colors.greenAccent),
                          title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          trailing: IconButton(
                            icon: const Icon(Icons.play_arrow_rounded, color: AppColors.textPrimary, size: 28),
                            onPressed: () {
                              Navigator.pop(sheetCtx);
                              _playSavedTrack(track);
                            },
                          ),
                          onTap: () {
                            Navigator.pop(sheetCtx);
                            _playSavedTrack(track);
                          },
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeletePlaylist(MusicPlaylist pl, [BuildContext? parentSheetCtx]) {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.line),
        ),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
            SizedBox(width: 8),
            Text('DELETE PLAYLIST', style: TextStyle(fontSize: 14, letterSpacing: 1.0, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${pl.name}"? The playlist will be removed, but songs in your Library will not be deleted.',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('CANCEL', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              HapticFeedback.heavyImpact();
              Navigator.pop(dialogCtx);
              if (parentSheetCtx != null && Navigator.canPop(parentSheetCtx)) {
                Navigator.pop(parentSheetCtx);
              }
              await MusicStorageService.deletePlaylist(pl.id);
              await _loadLibrary();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Playlist "${pl.name}" deleted ✓'),
                    backgroundColor: AppColors.surfaceLight,
                  ),
                );
              }
            },
            child: const Text('DELETE', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _showPlaylistDetailSheet(MusicPlaylist pl) async {
    HapticFeedback.lightImpact();
    final tracks = await MusicStorageService.getTracksForPlaylist(pl.id);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.queue_music_rounded, color: Colors.greenAccent, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pl.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('${tracks.length} tracks', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
                    tooltip: 'Delete Playlist',
                    onPressed: () => _confirmDeletePlaylist(pl, sheetCtx),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(sheetCtx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (tracks.isNotEmpty) ...[
                ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    _playSavedTrack(tracks.first);
                    Navigator.pop(sheetCtx);
                  },
                  icon: const Icon(Icons.play_arrow_rounded, color: Colors.black),
                  label: const Text('PLAY ALL', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.textPrimary,
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (tracks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Center(
                    child: Text('This playlist has no tracks yet.', style: TextStyle(color: AppColors.textMuted)),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: tracks.length,
                    itemBuilder: (context, idx) {
                      final track = tracks[idx];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: track.artworkUrl != null && track.artworkUrl!.isNotEmpty
                                ? Image.network(
                                    track.artworkUrl!,
                                    width: 40,
                                    height: 40,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _fallbackThumb(),
                                  )
                                : _fallbackThumb(),
                          ),
                          title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          trailing: IconButton(
                            icon: const Icon(Icons.play_circle_filled_rounded, size: 26, color: AppColors.textPrimary),
                            onPressed: () {
                              _playSavedTrack(track);
                              Navigator.pop(sheetCtx);
                            },
                          ),
                          onTap: () {
                            _playSavedTrack(track);
                            Navigator.pop(sheetCtx);
                          },
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _triggerSync() {
    HapticFeedback.lightImpact();
    _showJamSheet();
  }

  void _showJamSheet() {
    final jamService = JamSyncService.instance;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalCtx) {
        final ipController = TextEditingController();
        final pinController = TextEditingController();

        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 16,
                  bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 20,
                ),
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

                    Row(
                      children: [
                        const Icon(Icons.speaker_group_rounded, color: Colors.cyanAccent, size: 24),
                        const SizedBox(width: 10),
                        const Text('SAVEDUK JAM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.0)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.cyanAccent, borderRadius: BorderRadius.circular(4)),
                          child: const Text('BETA', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black)),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(modalCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Play music in sync across multiple phones over local Wi-Fi or Mobile Hotspot without internet.',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4),
                    ),
                    const SizedBox(height: 20),

                    if (jamService.role == JamRole.host) ...[
                      // Host Active View
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          children: [
                            const Text('YOU ARE THE DJ (HOST)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
                            const SizedBox(height: 10),
                            Text(
                              jamService.sessionPin ?? '------',
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 8.0,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text('Share this 6-digit PIN with friends nearby', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                            const SizedBox(height: 10),
                            Text('Host IP: ${jamService.localIp ?? "Loading…"}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontFamily: 'monospace')),
                            const SizedBox(height: 12),
                            ValueListenableBuilder<int>(
                              valueListenable: jamService.connectedGuestsNotifier,
                              builder: (context, count, _) {
                                return Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.greenAccent)),
                                    const SizedBox(width: 8),
                                    Text('$count speakers connected', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.greenAccent)),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () async {
                          HapticFeedback.lightImpact();
                          await jamService.stopSession();
                          setModalState(() {});
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                          foregroundColor: Colors.redAccent,
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('STOP HOSTING JAM', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ] else if (jamService.role == JamRole.guest) ...[
                      // Guest Active View
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          children: [
                            const Text('CONNECTED AS SPEAKER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                            const SizedBox(height: 8),
                            Text(jamService.statusMessageNotifier.value ?? 'Synced', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            const Text('Music on this phone will follow the DJ in real-time.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () async {
                          HapticFeedback.lightImpact();
                          await jamService.stopSession();
                          setModalState(() {});
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                          foregroundColor: Colors.redAccent,
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('LEAVE JAM SESSION', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ] else ...[
                      // Choose Mode
                      ElevatedButton.icon(
                        onPressed: () async {
                          HapticFeedback.mediumImpact();
                          await jamService.startHosting();
                          setModalState(() {});
                        },
                        icon: const Icon(Icons.radio_rounded, color: Colors.black),
                        label: const Text('HOST A JAM (BE THE DJ)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 14),

                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('JOIN A FRIEND\'S JAM', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                            TextField(
                              controller: ipController,
                              style: const TextStyle(fontSize: 12),
                              decoration: const InputDecoration(
                                hintText: 'Host IP (e.g. 192.168.1.15)',
                                prefixIcon: Icon(Icons.wifi_rounded, size: 18),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: pinController,
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              style: const TextStyle(fontSize: 16, letterSpacing: 4, fontWeight: FontWeight.bold),
                              decoration: const InputDecoration(
                                hintText: '6-digit PIN',
                                counterText: '',
                                prefixIcon: Icon(Icons.pin_rounded, size: 18),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: () async {
                                final ip = ipController.text.trim();
                                final pin = pinController.text.trim();
                                if (ip.isEmpty || pin.length != 6) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Please enter valid Host IP and 6-digit PIN'), backgroundColor: AppColors.error),
                                  );
                                  return;
                                }
                                HapticFeedback.mediumImpact();
                                final success = await jamService.joinJam(hostIp: ip, pin: pin);
                                if (success) {
                                  setModalState(() {});
                                } else {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Failed to connect to Jam session. Check IP & PIN.'), backgroundColor: AppColors.error),
                                    );
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.textPrimary,
                                foregroundColor: Colors.black,
                                minimumSize: const Size.fromHeight(40),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('CONNECT AS SPEAKER', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
        child: Column(
          children: [
            // Top App Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ValueListenableBuilder<String>(
                        valueListenable: SettingsService.instance.activeLogoNotifier,
                        builder: (context, activeLogo, _) {
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              final nextLogo = activeLogo == 'assets/images/logo.png'
                                  ? 'assets/images/logo_music.png'
                                  : 'assets/images/logo.png';
                              SettingsService.instance.setActiveLogo(nextLogo);
                            },
                            onLongPress: () {
                              HapticFeedback.heavyImpact();
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const SettingsScreen()),
                              );
                            },
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.line),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(7),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 250),
                                  transitionBuilder: (child, animation) =>
                                      FadeTransition(opacity: animation, child: ScaleTransition(scale: animation, child: child)),
                                  child: Image.asset(
                                    activeLogo,
                                    key: ValueKey<String>(activeLogo),
                                    width: 36,
                                    height: 36,
                                    fit: BoxFit.cover,
                                  ),
                                ),
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
                                fontSize: 20,
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
                          padding: const EdgeInsets.all(6),
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
                  const SizedBox(height: 12),

                  // Search Bar + [ + Create Playlist ] Row
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: TextField(
                            controller: _searchController,
                            style: const TextStyle(fontSize: 13),
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(vertical: 10),
                              hintText: 'Search songs, artists, albums…',
                              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 20),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 16, color: AppColors.textMuted),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _searchResults = []);
                                      },
                                    )
                                  : null,
                            ),
                            onSubmitted: _performSearch,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // + Create Playlist Button
                      InkWell(
                        onTap: _showCreatePlaylistDialog,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.line),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.add_rounded, size: 20, color: AppColors.textPrimary),
                              SizedBox(width: 4),
                              Text('PLAYLIST', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Tabs Header
                  TabBar(
                    controller: _tabController,
                    indicatorColor: AppColors.textPrimary,
                    labelColor: AppColors.textPrimary,
                    unselectedLabelColor: AppColors.textMuted,
                    onTap: (_) => HapticFeedback.selectionClick(),
                    tabs: const [
                      Tab(text: 'EXPLORE'),
                      Tab(text: 'MY LIBRARY'),
                    ],
                  ),
                ],
              ),
            ),

            // Tab Views with locked horizontal physics so vertical scrolling never lags
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildExploreTab(),
                  _buildLibraryTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: EXPLORE
  // ---------------------------------------------------------------------------
  Widget _buildExploreTab() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator(color: AppColors.textPrimary));
    }

    // Active Search Results
    if (_searchResults.isNotEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        physics: const BouncingScrollPhysics(),
        itemCount: _searchResults.length,
        itemBuilder: (context, index) {
          final track = _searchResults[index];
          return _buildTrackListTile(track);
        },
      );
    }

    // Default Explore View: 6 Recent Square Cards + Bottom 40% Trending List
    final recentItems = _savedTracks.isNotEmpty
        ? _savedTracks.take(6).toList()
        : _trendingTracks.take(6).map((s) => MusicTrack(
            id: s.id,
            title: s.title,
            artist: s.artist,
            artworkUrl: s.thumbnail,
            originalMediaUrl: s.url,
            durationSeconds: s.duration,
            createdAt: DateTime.now(),
          )).toList();

    return RefreshIndicator(
      onRefresh: _loadInitialData,
      color: AppColors.textPrimary,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Section 1 Header: 6 Recent Cards
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.history_rounded, size: 18, color: AppColors.textPrimary),
                  const SizedBox(width: 8),
                  Text(
                    'RECENT DISCOVERIES',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ),
          ),

          // 6 Square Cards in a 2x3 Grid
          if (recentItems.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.82,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final track = recentItems[index];
                    return _buildRecentSquareCard(track);
                  },
                  childCount: recentItems.length,
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 20)),

          // Section 2 Header: Trending List (Bottom 40%)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.trending_up_rounded, size: 18, color: Colors.greenAccent),
                  const SizedBox(width: 8),
                  Text(
                    'TRENDING CHARTS',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  const Text('TOP 40', style: TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),

          // Trending List Items
          if (_isLoadingTrending)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator(color: AppColors.textPrimary)),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final track = _trendingTracks[index];
                    return _buildTrendingRankedTile(track, index + 1);
                  },
                  childCount: _trendingTracks.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecentSquareCard(MusicTrack track) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: () => _playSavedTrack(track),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Square Thumbnail
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      track.artworkUrl != null && track.artworkUrl!.isNotEmpty
                          ? Image.network(
                              track.artworkUrl!,
                              fit: BoxFit.cover,
                              cacheWidth: 160,
                              cacheHeight: 160,
                              errorBuilder: (_, __, ___) => _cardFallbackArt(),
                            )
                          : _cardFallbackArt(),
                      // Play button badge
                      Positioned(
                        bottom: 6,
                        right: 6,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                            color: Color(0xB3000000),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Title & Artist
              Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 9, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrendingRankedTile(SearchTrackResult track, int rank) {
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.line),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  rank.toString().padLeft(2, '0'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: track.thumbnail != null && track.thumbnail!.isNotEmpty
                    ? Image.network(
                        track.thumbnail!,
                        width: 44,
                        height: 44,
                        cacheWidth: 88,
                        cacheHeight: 88,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _fallbackThumb(),
                      )
                    : _fallbackThumb(),
              ),
            ],
          ),
          title: Text(
            track.title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            track.artist,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
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
                icon: const Icon(Icons.play_circle_filled_rounded, size: 28, color: AppColors.textPrimary),
                tooltip: 'Play',
                onPressed: () => _playSearchResult(track),
              ),
            ],
          ),
          onTap: () => _playSearchResult(track),
        ),
      ),
    );
  }

  Widget _buildTrackListTile(SearchTrackResult track) {
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.line),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: track.thumbnail != null && track.thumbnail!.isNotEmpty
                ? Image.network(
                    track.thumbnail!,
                    width: 44,
                    height: 44,
                    cacheWidth: 88,
                    cacheHeight: 88,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _fallbackThumb(),
                  )
                : _fallbackThumb(),
          ),
          title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.bookmark_add_outlined, size: 20, color: AppColors.textSecondary),
                onPressed: () => _saveTrackToLibrary(track),
              ),
              IconButton(
                icon: const Icon(Icons.play_circle_filled_rounded, size: 28, color: AppColors.textPrimary),
                onPressed: () => _playSearchResult(track),
              ),
            ],
          ),
          onTap: () => _playSearchResult(track),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 2: MY LIBRARY (Import + Playlists + Offline Saves + Big Sync Button)
  // ---------------------------------------------------------------------------
  Widget _buildLibraryTab() {
    if (_isLoadingLibrary) {
      return const Center(child: CircularProgressIndicator(color: AppColors.textPrimary));
    }

    return RefreshIndicator(
      onRefresh: _loadLibrary,
      color: AppColors.textPrimary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
        physics: const BouncingScrollPhysics(),
        children: [
          // 1. [ 📥 IMPORT PLAYLIST ] Button
          InkWell(
            onTap: _showImportPlaylistDialog,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.line),
              ),
              child: const Row(
                children: [
                  Icon(Icons.playlist_add_rounded, color: Colors.greenAccent, size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('IMPORT PLAYLIST', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        SizedBox(height: 2),
                        Text('Import Spotify or YouTube Music playlist link', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 2. Playlists Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'YOUR PLAYLISTS (${_playlists.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.8),
              ),
              InkWell(
                onTap: _showCreatePlaylistDialog,
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text('+ NEW', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_playlists.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.line),
              ),
              child: const Row(
                children: [
                  Icon(Icons.queue_music_rounded, color: AppColors.textMuted, size: 20),
                  SizedBox(width: 12),
                  Text('No custom playlists yet. Tap + NEW to create one.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ],
              ),
            )
          else
            ..._playlists.map((pl) => _buildPlaylistCard(pl)),

          const SizedBox(height: 16),

          // 3. Folder of Offline Saves
          InkWell(
            onTap: _showOfflineSavesSheet,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.amberAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.folder_special_rounded, color: Colors.amberAccent, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('OFFLINE SAVES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 2),
                        Text(
                          '${_offlineTracks.length} tracks • ${_formatStorageSize(_offlineStorageBytes)}',
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('OFFLINE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 4. Saved Tracks List
          if (_savedTracks.isNotEmpty) ...[
            Text('ALL SAVED TRACKS (${_savedTracks.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            ..._savedTracks.take(20).map((t) => _buildSavedTrackTile(t)),
            const SizedBox(height: 16),
          ],

          // 5. Big Sync Button (Bottom)
          InkWell(
            onTap: _triggerSync,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.cyanAccent.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.speaker_group_rounded, color: Colors.cyanAccent, size: 24),
                  SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('SAVEDUK JAM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.8, color: AppColors.textPrimary)),
                          SizedBox(width: 6),
                          DecoratedBox(
                            decoration: BoxDecoration(color: Colors.cyanAccent, borderRadius: BorderRadius.all(Radius.circular(3))),
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              child: Text('BETA', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.black)),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 2),
                      Text('Sync & play music together via 6-digit PIN', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistCard(MusicPlaylist pl) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(Icons.queue_music_rounded, color: AppColors.textPrimary, size: 20),
        ),
        title: Text(pl.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: Text('${pl.trackCount} tracks', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.textMuted, size: 20),
              tooltip: 'Delete playlist',
              onPressed: () => _confirmDeletePlaylist(pl),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
        onTap: () => _showPlaylistDetailSheet(pl),
      ),
    );
  }

  Widget _buildSavedTrackTile(MusicTrack track) {
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.line),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: track.artworkUrl != null && track.artworkUrl!.isNotEmpty
                ? Image.network(
                    track.artworkUrl!,
                    width: 44,
                    height: 44,
                    cacheWidth: 88,
                    cacheHeight: 88,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _fallbackThumb(),
                  )
                : _fallbackThumb(),
          ),
          title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.play_circle_filled_rounded, size: 28, color: AppColors.textPrimary),
                onPressed: () => _playSavedTrack(track),
              ),
            ],
          ),
          onTap: () => _playSavedTrack(track),
        ),
      ),
    );
  }

  Widget _cardFallbackArt() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.surfaceLight,
            AppColors.surface.withValues(alpha: 0.8),
            const Color(0xFF1A1A2E),
          ],
        ),
      ),
      child: const Center(
        child: Icon(Icons.music_note_rounded, color: AppColors.textMuted, size: 34),
      ),
    );
  }

  Widget _fallbackThumb() {
    return Container(
      width: 44,
      height: 44,
      color: AppColors.surfaceLight,
      child: const Icon(Icons.music_note_rounded, size: 20, color: AppColors.textMuted),
    );
  }

  static String _formatStorageSize(int bytes) {
    if (bytes <= 0) return '0 KB';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
