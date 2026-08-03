import 'dart:io';
import 'package:flutter/material.dart';
import '../config/constants.dart';

/// Video thumbnail with play overlay icon
class VideoThumbnailWidget extends StatelessWidget {
  final String? thumbnailPath;
  final String? networkThumbnail;
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const VideoThumbnailWidget({
    super.key,
    this.thumbnailPath,
    this.networkThumbnail,
    this.width = double.infinity,
    this.height = 180,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail image
            _buildImage(),
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.22),
              ),
            ),
            // Play button
            Center(
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (thumbnailPath != null) {
      final file = File(thumbnailPath!);
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _placeholder(),
      );
    }
    if (networkThumbnail != null) {
      return Image.network(
        networkThumbnail!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _placeholder(),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _placeholder();
        },
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.surface,
      child: const Center(
        child: Icon(
          Icons.videocam_rounded,
          color: AppColors.textMuted,
          size: 36,
        ),
      ),
    );
  }
}
