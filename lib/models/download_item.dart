/// Download status enum
enum DownloadStatus {
  pending,
  fetching, // Selecting direct streams on device
  downloading, // Downloading the file
  saving, // Saving to gallery
  completed,
  failed,
}

/// Represents a single download item
class DownloadItem {
  final String id;
  final String originalUrl;
  final String platform; // youtube, instagram, twitter, facebook, pinterest
  final String? title;
  final String? thumbnailUrl;
  final String? localPath;
  final String? filename;
  final DownloadStatus status;
  final double progress; // 0.0 - 1.0
  final DateTime createdAt;
  final int? fileSize;
  final String? errorMessage;

  const DownloadItem({
    required this.id,
    required this.originalUrl,
    required this.platform,
    this.title,
    this.thumbnailUrl,
    this.localPath,
    this.filename,
    this.status = DownloadStatus.pending,
    this.progress = 0.0,
    required this.createdAt,
    this.fileSize,
    this.errorMessage,
  });

  DownloadItem copyWith({
    String? id,
    String? originalUrl,
    String? platform,
    String? title,
    String? thumbnailUrl,
    String? localPath,
    String? filename,
    DownloadStatus? status,
    double? progress,
    DateTime? createdAt,
    int? fileSize,
    String? errorMessage,
    bool clearError = false,
  }) {
    return DownloadItem(
      id: id ?? this.id,
      originalUrl: originalUrl ?? this.originalUrl,
      platform: platform ?? this.platform,
      title: title ?? this.title,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      localPath: localPath ?? this.localPath,
      filename: filename ?? this.filename,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      createdAt: createdAt ?? this.createdAt,
      fileSize: fileSize ?? this.fileSize,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }

  /// Convert to Map for SQLite storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'originalUrl': originalUrl,
      'platform': platform,
      'title': title,
      'thumbnailUrl': thumbnailUrl,
      'localPath': localPath,
      'filename': filename,
      'status': status.index,
      'progress': progress,
      'createdAt': createdAt.toIso8601String(),
      'fileSize': fileSize,
      'errorMessage': errorMessage,
    };
  }

  /// Create from SQLite Map
  factory DownloadItem.fromMap(Map<String, dynamic> map) {
    return DownloadItem(
      id: map['id'] as String,
      originalUrl: map['originalUrl'] as String,
      platform: map['platform'] as String,
      title: map['title'] as String?,
      thumbnailUrl: map['thumbnailUrl'] as String?,
      localPath: map['localPath'] as String?,
      filename: map['filename'] as String?,
      status: DownloadStatus.values[map['status'] as int],
      progress: (map['progress'] as num).toDouble(),
      createdAt: DateTime.parse(map['createdAt'] as String),
      fileSize: map['fileSize'] as int?,
      errorMessage: map['errorMessage'] as String?,
    );
  }

  /// Human-readable status text
  String get statusText {
    switch (status) {
      case DownloadStatus.pending:
        return 'Pending…';
      case DownloadStatus.fetching:
        return 'Fetching link…';
      case DownloadStatus.downloading:
        return 'Downloading… ${(progress * 100).toInt()}%';
      case DownloadStatus.saving:
        return 'Saving to gallery…';
      case DownloadStatus.completed:
        return 'Saved ✓';
      case DownloadStatus.failed:
        return errorMessage ?? 'Failed';
    }
  }

  /// Human-readable file size
  String get fileSizeText {
    if (fileSize == null) return '';
    final kb = fileSize! / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }
}
