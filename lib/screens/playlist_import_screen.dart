import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../config/constants.dart';
import '../models/music_track.dart';
import '../services/music_storage_service.dart';
import '../services/on_device_extractor_service.dart';

enum ImportSource { spotify, youtube, text }

class ParsedImportTrack {
  final String title;
  final String artist;
  bool selected;

  ParsedImportTrack({
    required this.title,
    required this.artist,
    this.selected = true,
  });
}

class PlaylistImportScreen extends StatefulWidget {
  const PlaylistImportScreen({super.key});

  @override
  State<PlaylistImportScreen> createState() => _PlaylistImportScreenState();
}

class _PlaylistImportScreenState extends State<PlaylistImportScreen> {
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final OnDeviceExtractorService _extractor = OnDeviceExtractorService();
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
      },
    ),
  );

  ImportSource _selectedSource = ImportSource.spotify;
  bool _isAnalyzing = false;
  bool _isImporting = false;
  double _importProgress = 0.0;
  String _statusMessage = '';

  List<ParsedImportTrack> _parsedTracks = [];

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _autoDetectSource(text);
  }

  void _autoDetectSource(String text) {
    if (text.contains('spotify.com') && _selectedSource != ImportSource.spotify) {
      setState(() => _selectedSource = ImportSource.spotify);
    } else if ((text.contains('youtube.com') || text.contains('youtu.be')) &&
        _selectedSource != ImportSource.youtube) {
      setState(() => _selectedSource = ImportSource.youtube);
    }
  }

  @override
  void dispose() {
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pasteClipboard() async {
    HapticFeedback.lightImpact();
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      final text = data.text!.trim();
      setState(() {
        _inputController.text = text;
      });
      _autoDetectSource(text);
    }
  }

  Future<void> _analyzeInput() async {
    final input = _inputController.text.trim();
    if (input.isEmpty) {
      _showToast('Please enter a playlist link or tracklist');
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _isAnalyzing = true;
      _statusMessage = 'Analyzing playlist data…';
      _parsedTracks = [];
    });

    try {
      // Smart routing: automatically route by URL type regardless of active tab
      if (input.contains('spotify.com')) {
        setState(() => _selectedSource = ImportSource.spotify);
        await _analyzeSpotify(input);
      } else if (input.contains('youtube.com') || input.contains('youtu.be')) {
        setState(() => _selectedSource = ImportSource.youtube);
        await _analyzeYouTube(input);
      } else if (_selectedSource == ImportSource.spotify) {
        await _analyzeSpotify(input);
      } else if (_selectedSource == ImportSource.youtube) {
        await _analyzeYouTube(input);
      } else {
        _analyzeText(input);
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Analysis error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
      }
    }
  }

  Future<void> _analyzeSpotify(String rawUrl) async {
    setState(() => _statusMessage = 'Fetching Spotify playlist metadata…');

    // Strip tracking parameters
    final cleanUrl = rawUrl.split('?').first.trim();
    final idMatch = RegExp(r'(?:playlist|album|track)/([a-zA-Z0-9]+)').firstMatch(cleanUrl);
    final id = idMatch?.group(1);
    final isTrack = rawUrl.contains('/track/');
    final isAlbum = rawUrl.contains('/album/');

    String playlistTitle = isTrack ? 'Spotify Track' : (isAlbum ? 'Spotify Album' : 'Spotify Playlist');
    final tracks = <ParsedImportTrack>[];

    // Stage 1: Fetch Spotify oEmbed to get the clean title
    try {
      final oEmbedUrl = 'https://open.spotify.com/oembed?url=https://open.spotify.com/${isTrack ? "track" : isAlbum ? "album" : "playlist"}/${id ?? ""}';
      final res = await _dio.get(oEmbedUrl);
      if (res.statusCode == 200 && res.data is Map) {
        final title = res.data['title']?.toString();
        if (title != null && title.isNotEmpty) {
          playlistTitle = title;
        }
      }
    } catch (_) {}

    _nameController.text = playlistTitle;

    // Stage 2: Fetch Spotify Embed HTML which contains the embedded JSON data
    if (id != null && id.isNotEmpty) {
      try {
        final embedUrl = 'https://open.spotify.com/embed/${isTrack ? "track" : isAlbum ? "album" : "playlist"}/$id';
        final pageRes = await _dio.get(embedUrl);
        if (pageRes.statusCode == 200 && pageRes.data != null) {
          final html = pageRes.data.toString();

          // A. Parse __NEXT_DATA__ JSON script tag
          final nextDataMatch = RegExp(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', dotAll: true).firstMatch(html);
          if (nextDataMatch != null) {
            final jsonStr = nextDataMatch.group(1);
            if (jsonStr != null) {
              final dynamic nextData = jsonDecode(jsonStr);
              _extractTracksFromNextData(nextData, tracks);
            }
          }

          // B. Regex fallback across HTML for track items
          if (tracks.isEmpty) {
            final trackRegex = RegExp(r'"title"\s*:\s*"([^"]+)"[^{}]*?"subtitle"\s*:\s*"([^"]+)"');
            for (final m in trackRegex.allMatches(html)) {
              final tTitle = m.group(1)?.trim();
              final tArtist = m.group(2)?.trim() ?? 'Unknown Artist';
              if (tTitle != null && tTitle.isNotEmpty && !tracks.any((t) => t.title == tTitle)) {
                tracks.add(ParsedImportTrack(title: tTitle, artist: tArtist, selected: true));
              }
            }
          }

          // C. Schema ld+json fallback
          if (tracks.isEmpty) {
            final ldMatch = RegExp(r'<script type="application/ld\+json"[^>]*>(.*?)</script>', dotAll: true).firstMatch(html);
            if (ldMatch != null) {
              final ldStr = ldMatch.group(1);
              if (ldStr != null) {
                final dynamic ldData = jsonDecode(ldStr);
                if (ldData is Map && ldData['track'] is List) {
                  for (final item in ldData['track']) {
                    final tName = item['name']?.toString() ?? '';
                    final tArtist = item['byArtist']?['name']?.toString() ?? 'Spotify Artist';
                    if (tName.isNotEmpty) {
                      tracks.add(ParsedImportTrack(title: tName, artist: tArtist, selected: true));
                    }
                  }
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[SpotifyEmbed] HTML parse error: $e');
      }
    }

    // Stage 3: If tracks still empty, search YouTube for the playlist name to guarantee real playable tracks
    if (tracks.isEmpty) {
      setState(() => _statusMessage = 'Resolving tracks for "$playlistTitle"…');
      final cleanQuery = playlistTitle
          .replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final searchResults = await _extractor.searchTracks(cleanQuery, limit: 12);
      for (final item in searchResults) {
        tracks.add(ParsedImportTrack(title: item.title, artist: item.artist, selected: true));
      }
    }

    setState(() {
      _parsedTracks = tracks;
      _statusMessage = tracks.isNotEmpty
          ? 'Found ${tracks.length} tracks in "$playlistTitle"'
          : 'Could not extract tracks. Please check the playlist link.';
    });
  }

  void _extractTracksFromNextData(dynamic node, List<ParsedImportTrack> tracks) {
    if (node is Map) {
      if (node.containsKey('name') && node['name'] is String && _nameController.text.isEmpty) {
        _nameController.text = node['name'] as String;
      }

      if (node.containsKey('trackList') && node['trackList'] is List) {
        for (final item in node['trackList']) {
          if (item is Map) {
            final title = (item['title'] ?? item['name'])?.toString().trim();
            final subtitle = (item['subtitle'] ?? item['artist'] ?? item['artists'])?.toString().trim();
            if (title != null && title.isNotEmpty) {
              tracks.add(ParsedImportTrack(
                title: title,
                artist: subtitle?.isNotEmpty == true ? subtitle! : 'Spotify Artist',
                selected: true,
              ));
            }
          }
        }
        return;
      }

      for (final val in node.values) {
        _extractTracksFromNextData(val, tracks);
        if (tracks.length >= 100) return;
      }
    } else if (node is List) {
      for (final val in node) {
        _extractTracksFromNextData(val, tracks);
        if (tracks.length >= 100) return;
      }
    }
  }

  Future<void> _analyzeYouTube(String url) async {
    setState(() => _statusMessage = 'Resolving YouTube playlist tracks…');
    _nameController.text = 'YouTube Music Mix';

    try {
      final searchResults = await _extractor.searchTracks(url, limit: 25);
      final tracks = searchResults
          .map((s) => ParsedImportTrack(title: s.title, artist: s.artist, selected: true))
          .toList();

      if (searchResults.isNotEmpty && searchResults.first.album?.isNotEmpty == true) {
        _nameController.text = searchResults.first.album!;
      }

      setState(() {
        _parsedTracks = tracks;
        _statusMessage = tracks.isNotEmpty
            ? 'Found ${tracks.length} tracks from YouTube'
            : 'No tracks found in this YouTube playlist.';
      });
    } catch (e) {
      _analyzeText(url);
    }
  }

  void _analyzeText(String text) {
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final tracks = <ParsedImportTrack>[];

    for (final line in lines) {
      if (line.startsWith('http://') || line.startsWith('https://')) {
        final segment = Uri.tryParse(line)?.pathSegments.lastOrNull ?? line;
        final decoded = Uri.decodeComponent(segment).replaceAll(RegExp(r'[_-]'), ' ').trim();
        if (decoded.isNotEmpty) {
          tracks.add(ParsedImportTrack(title: decoded, artist: 'Web Link', selected: true));
        }
        continue;
      }

      if (line.contains(' - ')) {
        final parts = line.split(' - ');
        tracks.add(ParsedImportTrack(title: parts.sublist(1).join(' - ').trim(), artist: parts[0].trim(), selected: true));
      } else {
        tracks.add(ParsedImportTrack(title: line, artist: 'Various Artists', selected: true));
      }
    }

    _nameController.text = 'My Custom Playlist';
    setState(() {
      _parsedTracks = tracks;
      _statusMessage = 'Found ${tracks.length} tracks';
    });
  }

  Future<void> _commitImport() async {
    final selected = _parsedTracks.where((t) => t.selected).toList();
    if (selected.isEmpty) {
      _showToast('No tracks selected to import');
      return;
    }

    final playlistName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'Imported Playlist';

    HapticFeedback.mediumImpact();
    setState(() {
      _isImporting = true;
      _importProgress = 0.0;
      _statusMessage = 'Creating playlist…';
    });

    try {
      final playlist = await MusicStorageService.createPlaylist(playlistName);
      int resolved = 0;

      for (int i = 0; i < selected.length; i++) {
        final item = selected[i];
        setState(() {
          _importProgress = (i + 1) / selected.length;
          _statusMessage = 'Resolving "${item.title}" (${i + 1}/${selected.length})…';
        });

        // Resolve each track against YouTube to get a playable URL + artwork
        String? originalMediaUrl;
        String? artworkUrl;
        int durationSeconds = 0;

        try {
          final searchResults = await _extractor.searchTracks(
            '"${item.title}" ${item.artist}',
            limit: 1,
          );
          if (searchResults.isNotEmpty) {
            final match = searchResults.first;
            originalMediaUrl = match.url;
            artworkUrl = match.thumbnail;
            durationSeconds = match.duration;
            resolved++;
          }
        } catch (e) {
          debugPrint('[PlaylistImport] resolve failed for "${item.title}": $e');
        }

        final track = MusicTrack(
          id: const Uuid().v4(),
          title: item.title,
          artist: item.artist,
          artworkUrl: artworkUrl,
          originalMediaUrl: originalMediaUrl,
          durationSeconds: durationSeconds,
          createdAt: DateTime.now(),
        );

        await MusicStorageService.addTrackToPlaylist(playlist.id, track);
        await Future.delayed(const Duration(milliseconds: 50));
      }

      HapticFeedback.heavyImpact();
      if (mounted) {
        _showToast('Imported ${selected.length} tracks ($resolved resolved) ✓');
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Import error: $e';
        _isImporting = false;
      });
    }
  }

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.surfaceLight),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'IMPORT PLAYLIST',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          physics: const BouncingScrollPhysics(),
          children: [
            const Text(
              'Import playlists from Spotify, YouTube Music, or text tracklists for 100% free streaming.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.4),
            ),
            const SizedBox(height: 18),

            // Source Selector Chips
            Row(
              children: [
                _buildSourceChip(ImportSource.spotify, 'Spotify', Icons.music_note_rounded, const Color(0xFF1DB954)),
                const SizedBox(width: 8),
                _buildSourceChip(ImportSource.youtube, 'YT Music', Icons.play_arrow_rounded, const Color(0xFFFF0000)),
                const SizedBox(width: 8),
                _buildSourceChip(ImportSource.text, 'Tracklist', Icons.format_list_bulleted_rounded, Colors.cyanAccent),
              ],
            ),
            const SizedBox(height: 16),

            // Input Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _selectedSource == ImportSource.text
                            ? 'PASTE TRACKLIST (ONE PER LINE)'
                            : _selectedSource == ImportSource.youtube
                                ? 'YOUTUBE PLAYLIST LINK'
                                : 'SPOTIFY PLAYLIST LINK',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textMuted),
                      ),
                      InkWell(
                        onTap: _pasteClipboard,
                        borderRadius: BorderRadius.circular(4),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Row(
                            children: [
                              Icon(Icons.content_paste_rounded, size: 14, color: AppColors.textPrimary),
                              SizedBox(width: 4),
                              Text('PASTE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _inputController,
                    maxLines: _selectedSource == ImportSource.text ? 4 : 1,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: _selectedSource == ImportSource.spotify
                          ? 'https://open.spotify.com/playlist/...'
                          : _selectedSource == ImportSource.youtube
                              ? 'https://music.youtube.com/playlist?list=...'
                              : 'Queen - Bohemian Rhapsody\nEminem - Lose Yourself\nDua Lipa - Levitating',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Analyze Button
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.textPrimary,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _isAnalyzing || _isImporting ? null : _analyzeInput,
                      child: _isAnalyzing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Text('ANALYZE & PREVIEW TRACKS', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Status message
            if (_statusMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _statusMessage,
                  style: TextStyle(
                    fontSize: 12,
                    color: _statusMessage.toLowerCase().contains('error') || _statusMessage.toLowerCase().contains('could not')
                        ? AppColors.error
                        : Colors.greenAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

            // Import Progress Bar
            if (_isImporting) ...[
              LinearProgressIndicator(
                value: _importProgress,
                backgroundColor: AppColors.line,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
              ),
              const SizedBox(height: 16),
            ],

            // Preview Section
            if (_parsedTracks.isNotEmpty && !_isImporting) ...[
              // Playlist Title & Select All Row
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('PLAYLIST NAME', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nameController,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'DETECTED SONGS (${_parsedTracks.length})',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                  ),
                  TextButton(
                    onPressed: () {
                      final allSelected = _parsedTracks.every((t) => t.selected);
                      setState(() {
                        for (final t in _parsedTracks) {
                          t.selected = !allSelected;
                        }
                      });
                    },
                    child: Text(
                      _parsedTracks.every((t) => t.selected) ? 'DESELECT ALL' : 'SELECT ALL',
                      style: const TextStyle(fontSize: 11, color: Colors.greenAccent, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Tracks List
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _parsedTracks.length,
                itemBuilder: (context, index) {
                  final track = _parsedTracks[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: CheckboxListTile(
                      activeColor: Colors.greenAccent,
                      checkColor: Colors.black,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      dense: true,
                      value: track.selected,
                      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      onChanged: (val) {
                        setState(() {
                          track.selected = val ?? false;
                        });
                      },
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),

              // Import Selected Tracks Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _commitImport,
                  child: Text(
                    'IMPORT ${_parsedTracks.where((t) => t.selected).length} TRACKS',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSourceChip(ImportSource source, String label, IconData icon, Color color) {
    final isSelected = _selectedSource == source;
    return Expanded(
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() {
            _selectedSource = source;
            _statusMessage = '';
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.15) : AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? color : AppColors.line, width: isSelected ? 1.5 : 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: isSelected ? color : AppColors.textMuted),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? AppColors.textPrimary : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
