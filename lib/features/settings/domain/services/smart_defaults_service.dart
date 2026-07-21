import 'dart:io';

import 'package:flutter/widgets.dart';

import '../enums/video_codec_preference.dart';

/// Advisory-only utility for suggesting optimal defaults based on device.
/// Never auto-changes settings — only provides hints for the UI.
class SmartDefaultsService {
  /// Screen physical height → suggested max resolution
  static int suggestMaxResolution(BuildContext context) {
    final mq = MediaQuery.of(context);
    final physicalHeight = mq.size.height * mq.devicePixelRatio;
    if (physicalHeight >= 2160) return 2160;
    if (physicalHeight >= 1440) return 1440;
    if (physicalHeight >= 1080) return 1080;
    return 720;
  }

  /// Check if current maxResolution is lower than screen capability.
  /// Returns suggested resolution if hint needed, null otherwise.
  static int? getResolutionHint(int currentMax, int suggestedMax) {
    // 0 = unlimited, no hint needed
    if (currentMax == 0) return null;
    if (currentMax >= suggestedMax) return null;
    return suggestedMax;
  }

  /// Check if macOS user should consider H.265/AV1.
  /// Returns true if hint should be shown.
  static bool shouldShowCodecHint(VideoCodecPreference current) {
    if (!Platform.isMacOS) return false;
    if (current != VideoCodecPreference.h264) return false;
    return true;
  }
}
