import 'dart:async';
import 'dart:convert';
import '../errors/result.dart';
import '../logging/app_logger.dart';
import 'backend_service.dart';

/// Batches and sends analytics events to the backend.
///
/// Events are queued in memory and flushed:
/// - Every 60 seconds (periodic timer)
/// - When [flush] is called explicitly
/// - Non-blocking, fire-and-forget
class AnalyticsService {
  final BackendService _backendService;
  final List<Map<String, dynamic>> _eventQueue = [];
  Timer? _flushTimer;

  static const _flushInterval = Duration(seconds: 60);
  static const _maxBatchSize = 50;

  AnalyticsService(this._backendService);

  /// Start periodic flush timer.
  void start() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(_flushInterval, (_) => flush());
    track('app_open');
  }

  /// Track an event with optional properties.
  void track(String eventName, [Map<String, dynamic>? properties]) {
    _eventQueue.add({
      'event_type': eventName,
      if (properties != null && properties.isNotEmpty)
        'event_data': jsonEncode(properties),
    });

    // Auto-flush if queue gets large
    if (_eventQueue.length >= _maxBatchSize) {
      flush();
    }
  }

  /// Flush all queued events to the backend.
  Future<bool> flush() async {
    if (_eventQueue.isEmpty) return true;

    final batch = List<Map<String, dynamic>>.from(_eventQueue);
    _eventQueue.clear();

    try {
      final result = await _backendService.trackEvents(batch);
      if (result.isFailure) {
        _requeueBatch(batch);
        appLogger.debug('Analytics flush failed: ${result.exceptionOrNull}');
        return false;
      }
      appLogger.debug('Analytics: flushed ${batch.length} events');
      return true;
    } catch (e) {
      _requeueBatch(batch);
      appLogger.debug('Analytics flush failed: $e');
      return false;
    }
  }

  void _requeueBatch(List<Map<String, dynamic>> batch) {
    // Re-queue on failure (drop if queue gets too large to prevent memory leak)
    if (_eventQueue.length < _maxBatchSize * 3) {
      _eventQueue.addAll(batch);
    }
  }

  /// Stop the service and flush remaining events.
  Future<void> dispose() async {
    track('app_close');
    _flushTimer?.cancel();
    _flushTimer = null;
    await flush();
  }

  // app_version and platform are derived from the auth context on the backend
  // (device registration includes OS + version), so no need to duplicate here.
}
