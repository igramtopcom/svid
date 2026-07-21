/// Features gated behind Premium tier.
///
/// Every value maps to a REAL feature that exists in the codebase.
/// No vaporware — each feature is enforced and delivers tangible value.
enum PremiumFeature {
  // ── Download Power ──────────────────────────────────────────────
  /// Removes the 15 downloads/week limit.
  unlimitedDownloads,

  /// Enables 1440p / 4K / 8K resolution downloads (free: 1080p max).
  highQuality4K,

  /// Up to 10 concurrent downloads (free: 2 max).
  extendedConcurrent,

  /// Playlist and channel batch downloads.
  batchDownload,

  // ── Advanced Tools ──────────────────────────────────────────────
  /// PiP, video trim, cinema mode, A-B repeat.
  advancedPlayer,

  /// Ad blocking, fingerprint protection, enhanced media interception.
  browserShield,

  /// Schedule downloads for later execution.
  scheduledDownloads,

  /// Advanced bandwidth management and scheduling.
  bandwidthControl,

  // ── Organization & Insights ─────────────────────────────────────
  /// Smart download collections with auto-tagging.
  smartCollections,

  /// Full analytics dashboard, heatmaps, platform insights.
  advancedAnalytics,

  /// Bulk URL import from clipboard or file.
  batchImport,

  /// Priority support with faster response times.
  prioritySupport,

  /// Advanced media conversion: all presets, batch, HW accel, custom config.
  mediaConverter,
}
