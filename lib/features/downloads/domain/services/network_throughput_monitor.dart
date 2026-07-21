import '../entities/download_entity.dart';
import '../entities/download_status.dart';

/// A 5-sample ring buffer that computes a rolling average of aggregate
/// download speed in bytes/s.  Used to smooth out short speed spikes that
/// would otherwise cause rapid concurrency limit changes.
class SpeedRollingAverage {
  static const int _kWindowSize = 5;
  final List<int> _samples = List.filled(_kWindowSize, 0);
  int _head = 0;
  bool _hasData = false;

  /// Add a new [sample] (bytes/s) to the ring buffer.
  void add(int sample) {
    _samples[_head] = sample;
    _head = (_head + 1) % _kWindowSize;
    _hasData = true;
  }

  /// Returns the average of all buffered samples, or 0 if no samples yet.
  int get average {
    if (!_hasData) return 0;
    return _samples.fold(0, (sum, s) => sum + s) ~/ _kWindowSize;
  }

  /// Reset all samples to zero.
  void reset() {
    _samples.fillRange(0, _kWindowSize, 0);
    _head = 0;
    _hasData = false;
  }
}

/// Pure-Dart service that aggregates real-time download throughput from active
/// [DownloadEntity] instances and maps it to a safe concurrency limit.
///
/// Concurrency tiers (auto-mode only; never exceeds [userConfiguredMax]):
/// - aggregate speed == 0 (no active downloads yet) → use [userConfiguredMax]
/// - aggregate speed  < 1 MB/s                       → max 1 concurrent
/// - aggregate speed 1–5 MB/s                        → max 2 concurrent
/// - aggregate speed  > 5 MB/s                       → [userConfiguredMax]
class NetworkThroughputMonitor {
  static const int _kLowThresholdBps = 1 * 1024 * 1024;  // 1 MB/s
  static const int _kMidThresholdBps = 5 * 1024 * 1024;  // 5 MB/s

  /// Shared rolling-average instance — updated once per stream emission in
  /// [DownloadsNotifier._applyAutoThrottle].
  static final SpeedRollingAverage rollingAverage = SpeedRollingAverage();

  const NetworkThroughputMonitor();

  /// Sums [DownloadEntity.speed] (bytes/sec) of all actively downloading items.
  static int aggregateThroughput(List<DownloadEntity> downloads) {
    return downloads
        .where((d) => d.status == DownloadStatus.downloading)
        .fold(0, (sum, d) => sum + d.speed);
  }

  /// Like [aggregateThroughput] but feeds the result through [rollingAverage]
  /// and returns the smoothed value.  Call this instead of [aggregateThroughput]
  /// when making concurrency throttle decisions.
  static int aggregateThroughputSmoothed(List<DownloadEntity> downloads) {
    final raw = aggregateThroughput(downloads);
    rollingAverage.add(raw);
    return rollingAverage.average;
  }

  /// Returns the effective max-concurrent-downloads limit based on [aggregateSpeedBps].
  ///
  /// [userConfiguredMax] is the user's explicit setting and acts as the ceiling.
  static int computeEffectiveConcurrencyLimit({
    required int aggregateSpeedBps,
    required int userConfiguredMax,
  }) {
    // No active downloads yet — don't restrict queue startup
    if (aggregateSpeedBps == 0) return userConfiguredMax;

    if (aggregateSpeedBps < _kLowThresholdBps) return 1;
    if (aggregateSpeedBps < _kMidThresholdBps) return 2.clamp(1, userConfiguredMax);
    return userConfiguredMax;
  }
}
