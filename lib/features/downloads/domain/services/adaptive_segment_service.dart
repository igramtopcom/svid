/// Adaptive per-download segment count service.
///
/// Maps observed network bandwidth to an optimal [numSegments] value for the
/// Rust multi-segment download engine.  The thresholds mirror the Rust-side
/// `adaptive_compute_segments()` function in `segmented_engine.rs`.
///
/// Tier table (bytes/sec → segments):
/// | Bandwidth    | Segments |
/// |-------------|----------|
/// | < 5 Mbps    |  2       |
/// | 5 – 20 Mbps |  4       |
/// | 20 – 50 Mbps|  8       |
/// | > 50 Mbps   | 16       |
class AdaptiveSegmentService {
  // Thresholds in bytes/sec
  static const int _k5Mbps = 5 * 1024 * 1024;
  static const int _k20Mbps = 20 * 1024 * 1024;
  static const int _k50Mbps = 50 * 1024 * 1024;

  /// Significant change threshold: >50 % deviation from initial probe.
  static const double _kChangeThreshold = 0.5;

  /// Map [bandwidthBps] (bytes/sec) to the optimal segment count.
  static int computeOptimalSegments(int bandwidthBps) {
    if (bandwidthBps < _k5Mbps) return 2;
    if (bandwidthBps < _k20Mbps) return 4;
    if (bandwidthBps < _k50Mbps) return 8;
    return 16;
  }

  /// Human-readable log message for the chosen segment count.
  /// Example: "Adaptive segments: 8 (bandwidth: 35 Mbps)"
  static String logMessage(int segments, int bandwidthBps) {
    final mbps = (bandwidthBps / (1024 * 1024)).round();
    return 'Adaptive segments: $segments (bandwidth: $mbps Mbps)';
  }

  /// Returns true when [currentBps] deviates by more than 50 % from
  /// [initialBps] — a signal that the segment count should be re-evaluated.
  static bool hasBandwidthChangedSignificantly(int initialBps, int currentBps) {
    if (initialBps == 0) return false;
    final ratio = (currentBps - initialBps).abs() / initialBps;
    return ratio > _kChangeThreshold;
  }

  /// Returns true when the bandwidth change is large enough to warrant
  /// selecting a *different* segment tier (not just a raw bps fluctuation).
  static bool shouldAdjustSegments(int initialBps, int currentBps) {
    if (!hasBandwidthChangedSignificantly(initialBps, currentBps)) return false;
    return computeOptimalSegments(currentBps) != computeOptimalSegments(initialBps);
  }
}
