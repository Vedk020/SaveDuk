import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../models/download_item.dart';
import 'platform_badge.dart';

/// Card widget for displaying a download item in the list
class DownloadCard extends StatelessWidget {
  final DownloadItem item;
  final VoidCallback? onTap;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;

  const DownloadCard({
    super.key,
    required this.item,
    this.onTap,
    this.onCancel,
    this.onRetry,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _borderColor, width: 1),
            ),
            child: Row(
              children: [
                PlatformBadge(platformId: item.platform, size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title ?? _truncateUrl(item.originalUrl),
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _StatusDot(status: item.status),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              item.statusText,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: _statusColor),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (item.fileSize != null && item.fileSize! > 0)
                            Text(
                              item.fileSizeText,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                      if (item.status == DownloadStatus.downloading) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: item.progress,
                            backgroundColor: AppColors.surface,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.textPrimary,
                            ),
                            minHeight: 3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildTrailingAction(context),
              ],
            ),
          ),
        ),
      ),
    ));
  }

  Widget _buildTrailingAction(BuildContext context) {
    switch (item.status) {
      case DownloadStatus.downloading:
      case DownloadStatus.fetching:
        return IconButton(
          icon: const Icon(Icons.close, color: AppColors.textMuted, size: 20),
          onPressed: onCancel,
          tooltip: 'Cancel',
        );
      case DownloadStatus.failed:
        return IconButton(
          icon: const Icon(Icons.refresh, color: AppColors.warning, size: 20),
          onPressed: onRetry,
          tooltip: 'Retry',
        );
      case DownloadStatus.completed:
        return IconButton(
          icon: const Icon(
            Icons.check_circle,
            color: AppColors.success,
            size: 22,
          ),
          onPressed: onTap,
          tooltip: 'Open',
        );
      default:
        return const SizedBox(width: 48);
    }
  }

  Color get _borderColor {
    switch (item.status) {
      case DownloadStatus.downloading:
      case DownloadStatus.fetching:
        return AppColors.textPrimary.withValues(alpha: 0.4);
      case DownloadStatus.completed:
        return AppColors.success.withValues(alpha: 0.2);
      case DownloadStatus.failed:
        return AppColors.error.withValues(alpha: 0.2);
      default:
        return Colors.white.withValues(alpha: 0.05);
    }
  }

  Color get _statusColor {
    switch (item.status) {
      case DownloadStatus.downloading:
      case DownloadStatus.fetching:
      case DownloadStatus.saving:
        return AppColors.textPrimary;
      case DownloadStatus.completed:
        return AppColors.success;
      case DownloadStatus.failed:
        return AppColors.error;
      default:
        return AppColors.textMuted;
    }
  }

  String _truncateUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final host = uri.host.replaceFirst('www.', '');
    final path = uri.path.length > 30
        ? '${uri.path.substring(0, 30)}…'
        : uri.path;
    return '$host$path';
  }
}

class _StatusDot extends StatefulWidget {
  final DownloadStatus status;

  const _StatusDot({required this.status});

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (_isActive) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isActive && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!_isActive && _controller.isAnimating) {
      _controller.stop();
    }
  }

  bool get _isActive =>
      widget.status == DownloadStatus.downloading ||
      widget.status == DownloadStatus.fetching ||
      widget.status == DownloadStatus.saving;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _dotColor;
    if (_isActive) {
      return AnimatedBuilder(
        animation: _controller,
        builder: (_, child) => Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.4 + _controller.value * 0.6),
            shape: BoxShape.circle,
          ),
        ),
      );
    }
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Color get _dotColor {
    switch (widget.status) {
      case DownloadStatus.downloading:
      case DownloadStatus.fetching:
      case DownloadStatus.saving:
        return AppColors.textPrimary;
      case DownloadStatus.completed:
        return AppColors.success;
      case DownloadStatus.failed:
        return AppColors.error;
      default:
        return AppColors.textMuted;
    }
  }
}
