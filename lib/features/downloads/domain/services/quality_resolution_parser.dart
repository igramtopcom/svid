import 'dart:math' as math;

import '../../../premium/domain/entities/premium_limits.dart';
import '../entities/video_info.dart';

/// Shared resolution parser for user-facing quality labels.
///
/// Extractors can label the same high-resolution option as `2160p`,
/// `Best (4K)`, or `[3840x2160]`. Premium gates must use one parser so
/// UI locks, presentation checks, and domain guards cannot drift apart.
class QualityResolutionParser {
  const QualityResolutionParser._();

  static int? heightForQuality(Quality quality) {
    if (quality.mediaType != MediaType.video) return null;
    return parseHeight(quality.qualityText);
  }

  static bool isAboveFreeLimit(Quality quality) {
    final height = heightForQuality(quality);
    return height != null && height > PremiumLimits.freeMaxResolutionP;
  }

  static int? parseHeight(String qualityText) {
    final text = qualityText.trim();
    if (text.isEmpty) return null;

    final pMatch = RegExp(
      r'(\d{3,4})\s*p(?:\d{2,3})?\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (pMatch != null) return int.tryParse(pMatch.group(1)!);

    final dimensionMatch = RegExp(
      r'(\d{3,5})\s*[x×]\s*(\d{3,5})',
      caseSensitive: false,
    ).firstMatch(text);
    if (dimensionMatch != null) {
      final width = int.tryParse(dimensionMatch.group(1)!);
      final height = int.tryParse(dimensionMatch.group(2)!);
      if (width != null && height != null) {
        // Use the shorter side so vertical 1080x1920 is treated as 1080p,
        // while vertical 2160x3840 still counts as 4K-class.
        return math.min(width, height);
      }
    }

    final normalized = text.toLowerCase();
    if (_hasResolutionToken(normalized, '8k')) return 4320;
    if (_hasResolutionToken(normalized, '4k')) return 2160;
    if (_hasResolutionToken(normalized, '2k')) return 1440;
    if (_hasResolutionToken(normalized, 'uhd')) return 2160;
    if (_hasResolutionToken(normalized, 'qhd')) return 1440;

    return null;
  }

  static bool _hasResolutionToken(String text, String token) {
    final escaped = RegExp.escape(token);
    return RegExp(
      '(^|[^a-z0-9])$escaped(?:\\d{2,3})?([^a-z0-9]|\$)',
    ).hasMatch(text);
  }
}
