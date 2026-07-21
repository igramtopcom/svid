/// Computes per-download speed allocations from a global bandwidth cap.
///
/// The global limit is stored in KB/s; it is converted to bytes/s and divided
/// evenly among all active downloads.  A value of 0 means "unlimited".
class BandwidthRateLimiter {
  BandwidthRateLimiter._();

  /// Priority weights: high=2×, normal=1×, low=0.5×.
  static const double kHighWeight = 2.0;
  static const double kNormalWeight = 1.0;
  static const double kLowWeight = 0.5;

  /// Returns the per-download speed limit in **bytes/s** (equal split).
  ///
  /// - Returns `0` (unlimited) when [globalLimitKbps] is 0 (disabled).
  /// - Returns `0` (unlimited) when [activeCount] is ≤ 0.
  /// - Otherwise returns `floor((globalLimitKbps * 1024) / activeCount)`.
  static int computePerDownloadLimit({
    required int globalLimitKbps,
    required int activeCount,
  }) {
    if (globalLimitKbps <= 0 || activeCount <= 0) return 0;
    final totalBytesPerSec = globalLimitKbps * 1024;
    return totalBytesPerSec ~/ activeCount;
  }

  /// Returns the per-download limit for a specific [downloadPriority] using
  /// priority-weighted allocation across [activeWeightSum] total weight units.
  ///
  /// Priority levels: 1=high (2×), 0=normal (1×), -1=low (0.5×).
  ///
  /// - Returns `0` (unlimited) when [globalLimitKbps] is 0 or [activeWeightSum] ≤ 0.
  static int computeWeightedLimit({
    required int globalLimitKbps,
    required int downloadPriority,
    required double activeWeightSum,
  }) {
    if (globalLimitKbps <= 0 || activeWeightSum <= 0) return 0;
    final weight = weightFor(downloadPriority);
    final totalBytesPerSec = globalLimitKbps * 1024;
    return (totalBytesPerSec * weight / activeWeightSum).floor();
  }

  /// Computes the total weight sum for a list of download priorities.
  static double totalWeightSum(List<int> priorities) {
    if (priorities.isEmpty) return 0;
    return priorities.fold(0.0, (sum, p) => sum + weightFor(p));
  }

  /// Returns the bandwidth weight for a given priority value.
  static double weightFor(int priority) {
    if (priority > 0) return kHighWeight;
    if (priority < 0) return kLowWeight;
    return kNormalWeight;
  }
}
