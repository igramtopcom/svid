import '../../../premium/domain/entities/premium_tier.dart';

/// Centralized Free vs Premium tier limits.
///
/// All enforcement points reference these constants — single source of truth.
/// Change limits here, enforcement updates everywhere.
class PremiumLimits {
  const PremiumLimits._();

  // ── Download Limits ──────────────────────────────────────────────

  /// Free tier weekly downloads — universal across all brands.
  ///
  /// The quota is enforced locally on an ISO-week UTC period. Old VidCombo PHP
  /// backend values are ignored for quota enforcement.
  static const int freeWeeklyDownloads = 15;

  /// Free tier: max 1080p resolution.
  static const int freeMaxResolutionP = 1080;

  /// Free tier: max 3 concurrent downloads.
  static const int freeMaxConcurrent = 3;

  /// Premium tier: max 10 concurrent downloads.
  static const int premiumMaxConcurrent = 10;

  // ── Helpers ──────────────────────────────────────────────────────

  /// Weekly download limit. Returns -1 for unlimited (premium).
  static int weeklyDownloadLimit(bool isPremium) =>
      isPremium ? -1 : freeWeeklyDownloads;

  /// Max video resolution in pixels (height). 4320 = 8K.
  static int maxResolution(bool isPremium) =>
      isPremium ? 4320 : freeMaxResolutionP;

  /// Max concurrent download slots.
  static int maxConcurrentDownloads(bool isPremium) =>
      isPremium ? premiumMaxConcurrent : freeMaxConcurrent;

  /// Whether batch playlist/channel downloads are allowed.
  static bool canBatchDownload(bool isPremium) => isPremium;

  /// Whether bulk URL import is allowed.
  static bool canBatchImport(bool isPremium) => isPremium;

  /// Format a resolution limit for display: "1080p" or "Unlimited".
  static String resolutionLabel(bool isPremium) =>
      isPremium ? '8K' : '${freeMaxResolutionP}p';

  /// Check if a given resolution (height px) is within the tier's limit.
  static bool isResolutionAllowed(int heightPx, bool isPremium) =>
      isPremium || heightPx <= freeMaxResolutionP;

  /// Tier-aware limits summary (for UI display).
  static ({
    int weeklyDownloads,
    int maxResolution,
    int maxConcurrent,
    bool batchDownload,
    bool batchImport,
  })
  forTier(PremiumTier tier) {
    final premium = tier == PremiumTier.premium;
    return (
      weeklyDownloads: weeklyDownloadLimit(premium),
      maxResolution: maxResolution(premium),
      maxConcurrent: maxConcurrentDownloads(premium),
      batchDownload: canBatchDownload(premium),
      batchImport: canBatchImport(premium),
    );
  }
}
