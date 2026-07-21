import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Helper class for platform-specific styling (colors, icons, names)
/// Centralizes platform branding to avoid duplication
///
/// 8 SVG brand icons: YouTube, Facebook, Instagram, TikTok, X, Reddit, Pinterest, Other
/// Fallback: Material icon for rare platforms (Vimeo, Dailymotion, SoundCloud, Bilibili, LinkedIn)
class PlatformStyleHelper {
  PlatformStyleHelper._(); // Private constructor to prevent instantiation

  // ==================== SVG PLATFORM ICONS ====================

  /// SVG asset path for a platform (null = no SVG, use Material icon fallback)
  static String? getSvgPathForPlatform(String platform) {
    switch (platform.toLowerCase()) {
      case 'youtube':
        return 'assets/icons/platforms/youtube.svg';
      case 'facebook':
        return 'assets/icons/platforms/facebook.svg';
      case 'instagram':
        return 'assets/icons/platforms/instagram.svg';
      case 'tiktok':
        return 'assets/icons/platforms/tiktok.svg';
      case 'x':
      case 'twitter':
        return 'assets/icons/platforms/x.svg';
      case 'reddit':
        return 'assets/icons/platforms/reddit.svg';
      case 'pinterest':
        return 'assets/icons/platforms/pinterest.svg';
      default:
        return null; // No SVG — fallback to Material icon
    }
  }

  /// Whether a platform has a brand SVG icon
  static bool hasSvgIcon(String platform) {
    return getSvgPathForPlatform(platform) != null;
  }

  // ==================== PLATFORM COLORS ====================

  /// Get brand color for a given platform
  static Color getColorForPlatform(String platform) {
    switch (platform.toLowerCase()) {
      case 'youtube':
        return const Color(0xFFFF0000); // YouTube Red
      case 'facebook':
        return const Color(0xFF1877F2); // Facebook Blue
      case 'instagram':
        return const Color(0xFFE4405F); // Instagram Pink/Red
      case 'tiktok':
      case 'x':
      case 'twitter':
        return const Color(0xFF000000); // TikTok/X Black
      case 'reddit':
        return const Color(0xFFFF4500); // Reddit Orange
      case 'pinterest':
        return const Color(0xFFE60023); // Pinterest Red
      case 'vimeo':
        return const Color(0xFF1AB7EA); // Vimeo Blue
      case 'dailymotion':
        return const Color(0xFF0066DC); // Dailymotion Blue
      case 'soundcloud':
        return const Color(0xFFFF5500); // SoundCloud Orange
      case 'bilibili':
        return const Color(0xFF00A1D6); // Bilibili Blue
      case 'linkedin':
        return const Color(0xFF0077B5); // LinkedIn Blue
      default:
        return const Color(0xFF757575); // Neutral Gray
    }
  }

  // ==================== PLATFORM ICONS ====================

  /// Get icon for a given platform
  static IconData getIconForPlatform(String platform) {
    switch (platform.toLowerCase()) {
      case 'youtube':
        return Icons.play_circle_filled;
      case 'facebook':
        return Icons.facebook;
      case 'instagram':
        return Icons.camera_alt;
      case 'tiktok':
        return Icons.music_note;
      case 'x':
      case 'twitter':
        return Icons.comment;
      case 'reddit':
        return Icons.forum;
      case 'pinterest':
        return Icons.push_pin;
      case 'vimeo':
        return Icons.videocam;
      case 'dailymotion':
        return Icons.movie;
      case 'soundcloud':
        return Icons.audiotrack;
      case 'bilibili':
        return Icons.tv;
      case 'linkedin':
        return Icons.work;
      default:
        return Icons.public;
    }
  }

  // ==================== PLATFORM NAMES ====================

  /// Get display name for a given platform
  static String getNameForPlatform(String platform) {
    switch (platform.toLowerCase()) {
      case 'youtube':
        return 'YouTube';
      case 'facebook':
        return 'Facebook';
      case 'instagram':
        return 'Instagram';
      case 'tiktok':
        return 'TikTok';
      case 'x':
        return 'X';
      case 'twitter':
        return 'Twitter';
      case 'reddit':
        return 'Reddit';
      case 'pinterest':
        return 'Pinterest';
      case 'vimeo':
        return 'Vimeo';
      case 'dailymotion':
        return 'Dailymotion';
      case 'soundcloud':
        return 'SoundCloud';
      case 'bilibili':
        return 'Bilibili';
      case 'linkedin':
        return 'LinkedIn';
      default:
        return platform;
    }
  }

  // ==================== PLATFORM STYLE ====================

  /// Get complete platform style (color + icon + svgPath + name)
  static PlatformStyle getStyleForPlatform(String platform) {
    return PlatformStyle(
      color: getColorForPlatform(platform),
      icon: getIconForPlatform(platform),
      svgPath: getSvgPathForPlatform(platform),
      name: getNameForPlatform(platform),
    );
  }
}

/// Platform style data class
class PlatformStyle {
  final Color color;
  final IconData icon;
  final String? svgPath;
  final String name;

  const PlatformStyle({
    required this.color,
    required this.icon,
    this.svgPath,
    required this.name,
  });

  bool get hasSvg => svgPath != null;
}

/// Reusable widget for rendering platform icons consistently
/// Uses SVG brand logo for 7 popular platforms, Material icon fallback for others
class PlatformIcon extends StatelessWidget {
  final String platform;
  final double size;
  final Color? color;

  const PlatformIcon({
    super.key,
    required this.platform,
    this.size = 16,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final svgPath = PlatformStyleHelper.getSvgPathForPlatform(platform);

    if (svgPath != null) {
      // Dark SVGs (TikTok, X) need white tint in dark mode to stay visible
      final brandColor = PlatformStyleHelper.getColorForPlatform(platform);
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final needsLightTint = isDark && brandColor.computeLuminance() < 0.15;

      return SvgPicture.asset(
        svgPath,
        width: size,
        height: size,
        colorFilter:
            needsLightTint
                ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
                : null,
        errorBuilder:
            (_, __, ___) => Icon(
              PlatformStyleHelper.getIconForPlatform(platform),
              size: size,
              color: color ?? PlatformStyleHelper.getColorForPlatform(platform),
            ),
      );
    }

    // Fallback: Material icon for rare platforms
    return Icon(
      PlatformStyleHelper.getIconForPlatform(platform),
      size: size,
      color: color ?? PlatformStyleHelper.getColorForPlatform(platform),
    );
  }
}
