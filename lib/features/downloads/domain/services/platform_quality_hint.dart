import '../../../../core/utils/platform_detector.dart';
import '../entities/video_info.dart';

/// Pure decision logic for "this platform's HQ formats are auth-gated"
/// hints. The goal isn't to surface a UI string (deferred to v2.1 once
/// product picks the per-platform messaging strategy and i18n rounds the
/// keys across 15 locales) — it's to expose the predicate as a
/// testable, side-effect-free helper so extraction callers can emit
/// telemetry breadcrumbs at the right moment WITHOUT each call site
/// re-implementing the heuristic.
///
/// Production context: PHP feedback flags Bilibili users getting only
/// SD formats after the 1.7.0 ship — but the underlying yt-dlp call
/// succeeds, so the app sees no error. Bilibili gates 1080p/4K behind
/// signed-in Premium accounts. Without cookies, the extractor only
/// surfaces the unauthenticated quality tier. The same shape exists
/// for other Chinese-platform extractors (Douyin notably) but the
/// production telemetry only mentions Bilibili so far.
class PlatformQualityHint {
  PlatformQualityHint._();

  /// Highest video height (in pixels) below which we consider the
  /// extraction to have been "quality-clamped" by missing auth. 720 is
  /// the lower bound of mainstream HD; anything strictly below this on
  /// a platform we KNOW gates HQ behind login is a strong signal that
  /// cookies would have unlocked a better stream.
  static const int loginGatedHqHeightThreshold = 720;

  /// Platforms whose HQ (1080p+) formats are reliably gated behind a
  /// signed-in account. Used as a positive list so a future yt-dlp
  /// regression on a non-Chinese site doesn't accidentally trigger the
  /// hint for the wrong platform.
  static const Set<VideoPlatform> loginGatedHqPlatforms = {
    VideoPlatform.bilibili,
  };

  /// Whether the extracted [videoInfo] for [platform] should emit a
  /// "sign in for HQ" telemetry signal. Triggers when ALL of:
  ///   * platform is in [loginGatedHqPlatforms]
  ///   * the highest available video height is strictly below
  ///     [loginGatedHqHeightThreshold]
  ///   * no cookies were passed to the extractor for this attempt
  ///
  /// Returns false on missing data (best-effort, never throws). Callers
  /// can emit a Sentry breadcrumb without UI side effects so we can
  /// measure how often the situation occurs before investing in
  /// localised UI.
  static bool shouldHintLoginForHq({
    required VideoPlatform platform,
    required VideoInfo videoInfo,
    required bool hasCookiesForPlatform,
  }) {
    if (!loginGatedHqPlatforms.contains(platform)) return false;
    if (hasCookiesForPlatform) return false;

    final maxHeight = _maxVideoHeight(videoInfo);
    if (maxHeight == null) return false; // best-effort — no signal
    return maxHeight < loginGatedHqHeightThreshold;
  }

  /// Extract the largest video height present in
  /// [videoInfo.availableQualities]. Returns null when no quality
  /// carries a parseable resolution (audio-only payloads,
  /// subtitle-only, etc.).
  static int? _maxVideoHeight(VideoInfo videoInfo) {
    int? best;
    for (final q in videoInfo.availableQualities) {
      if (q.isAudioOnly) continue;
      final h = _parseHeight(q.qualityText);
      if (h == null) continue;
      if (best == null || h > best) best = h;
    }
    return best;
  }

  /// Pull the height (in pixels) out of a yt-dlp quality label.
  /// Recognises canonical shapes:
  ///   * `MP4 720p [1280x720]` → 720
  ///   * `Best (1080p)`        → 1080
  ///   * `2160p` / `4K`        → 2160 (4K alias)
  ///   * `480x854`             → 480 (height = first int when matrix
  ///     is `WxH`, but yt-dlp labels are HxW for portrait — accept
  ///     min(W, H) as a conservative height proxy)
  /// Returns null when no resolution can be confidently extracted.
  static int? _parseHeight(String label) {
    final lower = label.toLowerCase();
    // 4K alias common in user-facing labels
    if (lower.contains('4k')) return 2160;
    // `<n>p` shape, e.g. 720p, 1080p, 2160p
    final pMatch = RegExp(r'(\d{3,4})p').firstMatch(lower);
    if (pMatch != null) {
      return int.tryParse(pMatch.group(1)!);
    }
    // `WxH` resolution matrix — use min as a height proxy so a
    // portrait `1080x1920` and a landscape `1920x1080` both report
    // 1080 instead of 1920 (landscape height vs portrait width).
    final matMatch = RegExp(r'(\d{3,5})x(\d{3,5})').firstMatch(lower);
    if (matMatch != null) {
      final a = int.tryParse(matMatch.group(1)!);
      final b = int.tryParse(matMatch.group(2)!);
      if (a != null && b != null) return a < b ? a : b;
    }
    return null;
  }
}
