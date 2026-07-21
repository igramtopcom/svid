import 'dart:async';
import 'dart:math';

import '../../../../core/logging/app_logger.dart';

/// Pure Dart service for scheduling automatic retry of failed downloads.
///
/// Implements exponential backoff: `baseDuration * 2^attempt`.
/// Default base: 30 seconds. Max 4 retries.
class RetrySchedulerService {
  RetrySchedulerService({
    this.maxRetries = 4,
    Duration baseDuration = const Duration(seconds: 30),
    Future<void> Function(Duration)? delayFn,
  })  : _baseDuration = baseDuration,
        _delayFn = delayFn;

  final int maxRetries;
  final Duration _baseDuration;
  final Future<void> Function(Duration)? _delayFn;

  final Map<int, Timer> _pendingRetries = {};

  /// Whether a download should be retried based on its current retry count.
  bool shouldRetry(int retryCount) => retryCount < maxRetries;

  /// Compute the backoff duration for the given [retryCount].
  ///
  /// Formula: `baseDuration * 2^retryCount`
  /// - retry 0 → 30s
  /// - retry 1 → 60s
  /// - retry 2 → 120s
  /// - retry 3 → 240s
  Duration getBackoffDuration(int retryCount) {
    final multiplier = pow(2, retryCount).toInt();
    return Duration(milliseconds: _baseDuration.inMilliseconds * multiplier);
  }

  /// Schedule a retry for [downloadId] after the appropriate backoff.
  ///
  /// Calls [onRetry] after the backoff period. Cancels any existing pending
  /// retry for the same [downloadId] before scheduling the new one.
  void scheduleRetry({
    required int downloadId,
    required int currentRetryCount,
    required void Function(int id) onRetry,
  }) {
    if (!shouldRetry(currentRetryCount)) {
      appLogger.warning(
        '⚠️ [Retry] Download $downloadId exceeded max retries ($maxRetries)',
      );
      return;
    }

    // Cancel any pending retry for this download
    cancelRetry(downloadId);

    final delay = getBackoffDuration(currentRetryCount);
    appLogger.info(
      '⏳ [Retry] Scheduling download $downloadId retry '
      '${currentRetryCount + 1}/$maxRetries in ${delay.inSeconds}s',
    );

    if (_delayFn != null) {
      // Test-injectable: use async delay
      _delayFn(delay).then((_) {
        _pendingRetries.remove(downloadId);
        onRetry(downloadId);
      });
    } else {
      _pendingRetries[downloadId] = Timer(delay, () {
        _pendingRetries.remove(downloadId);
        onRetry(downloadId);
      });
    }
  }

  /// Cancel a pending retry for [downloadId] (e.g., user manually cancelled).
  void cancelRetry(int downloadId) {
    final timer = _pendingRetries.remove(downloadId);
    timer?.cancel();
  }

  /// Cancel all pending retries.
  void cancelAll() {
    for (final timer in _pendingRetries.values) {
      timer.cancel();
    }
    _pendingRetries.clear();
  }

  /// Number of downloads currently waiting to be retried.
  int get pendingRetryCount => _pendingRetries.length;

  /// Whether [downloadId] has a pending retry scheduled.
  bool hasPendingRetry(int downloadId) => _pendingRetries.containsKey(downloadId);

  /// Dispose: cancel all timers.
  void dispose() => cancelAll();
}
