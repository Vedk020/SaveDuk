import 'package:flutter/material.dart';
import '../config/constants.dart';

/// Badge showing the platform icon with its brand color
class PlatformBadge extends StatelessWidget {
  final String platformId;
  final double size;

  const PlatformBadge({super.key, required this.platformId, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final platform = _getPlatform(platformId);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(size * 0.18),
        border: Border.all(color: AppColors.line),
      ),
      child: Icon(
        platform.icon,
        color: AppColors.textPrimary,
        size: size * 0.55,
      ),
    );
  }

  SupportedPlatform _getPlatform(String id) {
    return AppPlatforms.all.firstWhere(
      (p) => p.id == id,
      orElse: () => SupportedPlatform(
        id: 'unknown',
        name: 'Unknown',
        icon: Icons.link,
        color: AppColors.textMuted,
        urlPatterns: [],
      ),
    );
  }
}
