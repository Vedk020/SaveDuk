/// Model representing a music track (recognized, streamed, or saved)
class MusicTrack {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final String? artworkUrl;
  final String? streamUrl;
  final String? localPath;
  final String? originalMediaUrl;
  final int durationSeconds;
  final DateTime createdAt;
  final bool isFavorite;

  const MusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.artworkUrl,
    this.streamUrl,
    this.localPath,
    this.originalMediaUrl,
    this.durationSeconds = 0,
    required this.createdAt,
    this.isFavorite = false,
  });

  bool get isLocal => localPath != null && localPath!.isNotEmpty;

  String get durationText {
    if (durationSeconds <= 0) return '--:--';
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  MusicTrack copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? artworkUrl,
    String? streamUrl,
    String? localPath,
    String? originalMediaUrl,
    int? durationSeconds,
    DateTime? createdAt,
    bool? isFavorite,
  }) {
    return MusicTrack(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      streamUrl: streamUrl ?? this.streamUrl,
      localPath: localPath ?? this.localPath,
      originalMediaUrl: originalMediaUrl ?? this.originalMediaUrl,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      createdAt: createdAt ?? this.createdAt,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'artworkUrl': artworkUrl,
      'streamUrl': streamUrl,
      'localPath': localPath,
      'originalMediaUrl': originalMediaUrl,
      'durationSeconds': durationSeconds,
      'createdAt': createdAt.toIso8601String(),
      'isFavorite': isFavorite ? 1 : 0,
    };
  }

  factory MusicTrack.fromMap(Map<String, dynamic> map) {
    return MusicTrack(
      id: map['id'] as String,
      title: map['title'] as String,
      artist: (map['artist'] as String?) ?? 'Unknown Artist',
      album: map['album'] as String?,
      artworkUrl: map['artworkUrl'] as String?,
      streamUrl: map['streamUrl'] as String?,
      localPath: map['localPath'] as String?,
      originalMediaUrl: map['originalMediaUrl'] as String?,
      durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
      isFavorite: (map['isFavorite'] as int? ?? 0) == 1,
    );
  }
}
