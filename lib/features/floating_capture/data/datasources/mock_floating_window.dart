import 'dart:async';

import '../../../downloads/domain/entities/video_preview.dart';
import '../../domain/entities/floating_window_event.dart';
import '../../domain/entities/popup_action_result.dart';
import '../../domain/services/floating_window.dart';

/// In-memory [FloatingWindow] implementation for tests.
///
/// - Outbound calls (showPreview / pushQueue / setQuotaState / etc.) record
///   into call counters + payload buffers so tests can assert what the
///   coordinator forwarded to the popup.
/// - Inbound events (DownloadClicked / SnoozeSelected / ...) are pushed via
///   [emit] — tests use it to simulate the user clicking the popup.
///
/// State flags ([isSpawned], [isVisible]) mirror the real plugin's lifecycle
/// so consumer code that gates on those flags exercises the same branches
/// in production and test runs.
class MockFloatingWindow implements FloatingWindow {
  final StreamController<FloatingWindowEvent> _events =
      StreamController<FloatingWindowEvent>.broadcast();

  bool _spawned = false;
  bool _visible = false;
  bool _disposed = false;

  // Recorded calls — public so tests can read counters + payload buffers.
  int spawnCallCount = 0;
  int showCallCount = 0;
  int hideCallCount = 0;
  int clearQueueCallCount = 0;
  int disposeCallCount = 0;

  /// All previews ever sent via [showPreview]. Last-element = current.
  final List<VideoPreview> previewsShown = [];

  /// All previews appended via [pushQueue], in order.
  final List<VideoPreview> queuePushes = [];

  /// All quota updates received, in order.
  final List<int> quotaUpdates = [];

  /// All action results received via [setActionResult], in order. v2.2 Phase 2C.
  final List<PopupActionResult> actionResults = [];

  /// If non-null, the next outbound call throws this. Auto-resets after
  /// one throw so tests can simulate transient platform failures.
  Object? failNextCall;

  @override
  Stream<FloatingWindowEvent> get events => _events.stream;

  @override
  bool get isSpawned => _spawned;

  @override
  bool get isVisible => _visible;

  @override
  Future<void> spawn({required VideoPreview initialPreview}) async {
    _ensureNotDisposed('spawn');
    spawnCallCount++;
    _consumeFailIfSet();
    if (_spawned) return;
    _spawned = true;
    _visible = true;
    previewsShown.add(initialPreview);
  }

  @override
  Future<void> show() async {
    _ensureNotDisposed('show');
    _ensureSpawned('show');
    showCallCount++;
    _consumeFailIfSet();
    _visible = true;
  }

  @override
  Future<void> hide() async {
    _ensureNotDisposed('hide');
    hideCallCount++;
    _consumeFailIfSet();
    if (!_spawned) return;
    _visible = false;
  }

  @override
  Future<void> pushQueue(VideoPreview preview) async {
    _ensureNotDisposed('pushQueue');
    _ensureSpawned('pushQueue');
    _consumeFailIfSet();
    queuePushes.add(preview);
  }

  @override
  Future<void> showPreview(VideoPreview preview) async {
    _ensureNotDisposed('showPreview');
    _ensureSpawned('showPreview');
    _consumeFailIfSet();
    previewsShown.add(preview);
    _visible = true;
  }

  @override
  Future<void> clearQueue() async {
    _ensureNotDisposed('clearQueue');
    clearQueueCallCount++;
    _consumeFailIfSet();
    queuePushes.clear();
    _visible = false;
  }

  @override
  Future<void> setQuotaState({required int remaining}) async {
    _ensureNotDisposed('setQuotaState');
    _ensureSpawned('setQuotaState');
    _consumeFailIfSet();
    quotaUpdates.add(remaining);
  }

  @override
  Future<void> setActionResult(PopupActionResult result) async {
    _ensureNotDisposed('setActionResult');
    _ensureSpawned('setActionResult');
    _consumeFailIfSet();
    actionResults.add(result);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    disposeCallCount++;
    _disposed = true;
    _spawned = false;
    _visible = false;
    await _events.close();
  }

  /// Test helper: simulate the popup emitting an event back to the main app.
  /// Throws [StateError] if called after [dispose] (mirrors what would
  /// happen in production — events stop after the engine tears down).
  void emit(FloatingWindowEvent event) {
    if (_disposed) {
      throw StateError('MockFloatingWindow.emit called after dispose');
    }
    _events.add(event);
  }

  void _ensureSpawned(String method) {
    if (!_spawned) {
      throw StateError(
        'MockFloatingWindow.$method() called before spawn()',
      );
    }
  }

  void _ensureNotDisposed(String method) {
    if (_disposed) {
      throw StateError(
        'MockFloatingWindow.$method() called after dispose()',
      );
    }
  }

  void _consumeFailIfSet() {
    final fail = failNextCall;
    if (fail != null) {
      failNextCall = null;
      throw fail;
    }
  }
}
