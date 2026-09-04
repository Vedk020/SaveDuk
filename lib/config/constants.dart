import 'package:flutter/material.dart';

/// Supported platform definitions
class SupportedPlatform {
  final String id;
  final String name;
  final IconData icon;
  final Color color;
  final List<RegExp> urlPatterns;

  const SupportedPlatform({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.urlPatterns,
  });
}

class AppPlatforms {
  static final youtube = SupportedPlatform(
    id: 'youtube',
    name: 'YouTube',
    icon: Icons.play_circle_filled,
    color: AppColors.textPrimary,
    urlPatterns: [
      RegExp(r'(youtube\.com/watch\?v=|youtu\.be/|youtube\.com/shorts/)'),
    ],
  );

  static final instagram = SupportedPlatform(
    id: 'instagram',
    name: 'Instagram',
    icon: Icons.camera_alt,
    color: AppColors.textPrimary,
    urlPatterns: [
      RegExp(r'(instagram\.com/(reel|reels|p|tv|stories|share/reel|share/p)/|instagr\.am/(p|reel)/)'),
    ],
  );

  static final twitter = SupportedPlatform(
    id: 'twitter',
    name: 'Twitter/X',
    icon: Icons.alternate_email,
    color: AppColors.textPrimary,
    urlPatterns: [RegExp(r'(twitter\.com|x\.com)/.+/status/')],
  );

  static final facebook = SupportedPlatform(
    id: 'facebook',
    name: 'Facebook',
    icon: Icons.facebook,
    color: AppColors.textPrimary,
    urlPatterns: [
      RegExp(r'(facebook\.com/(.+/videos/|reel/|watch[/?]|share/r/|share/v/|story\.php)|fb\.watch/|fb\.gg/)'),
    ],
  );

  static final pinterest = SupportedPlatform(
    id: 'pinterest',
    name: 'Pinterest',
    icon: Icons.push_pin,
    color: AppColors.textPrimary,
    urlPatterns: [RegExp(r'pinterest\.(com|ca|co\.uk)/pin/')],
  );

  static List<SupportedPlatform> get all => [
    youtube,
    instagram,
    twitter,
    facebook,
    pinterest,
  ];
}

/// App color palette
class AppColors {
  static const Color background = Color(0xFF0B0B0B);
  static const Color surface = Color(0xFF151515);
  static const Color surfaceLight = Color(0xFF202020);
  static const Color cardBackground = Color(0xFF181818);
  static const Color textPrimary = Color(0xFFF5F5F5);
  static const Color textSecondary = Color(0xFFB8B8B8);
  static const Color textMuted = Color(0xFF737373);
  static const Color line = Color(0xFF303030);
  static const Color success = Color(0xFFF5F5F5);
  static const Color error = Color(0xFFF5F5F5);
  static const Color warning = Color(0xFFD0D0D0);
}

/// ACRCloud Acoustic Recognition Configuration
class AcrCloudConfig {
  static const String host = 'identify-ap-southeast-1.acrcloud.com';
  static const String accessKey = '3a6b9c411a1bbd17f4a3a114bda40e0e';
  static const String accessSecret = 'vfzV7xUBP1NOLJuFDMDcWroClA4z0J8YhZgqU6Lb';
}

