import 'dart:async';

import '../../../../core/logging/app_logger.dart';
import '../../domain/services/capture_service.dart';
import 'capture_side_effect_router.dart';

/// Owns the runtime wiring between [CaptureService] and
/// [CaptureSideEffectRouter] for the lifetime of the host app.
///
/// Construct once in main.dart, call [start] after the main
/// ProviderContainer is ready, call [dispose] on app shutdown.
///
/// Responsibilities:
/// 1. Start the underlying CaptureService (clipboard listening, snooze
///    state load, popup event subscription).
/// 2. Subscribe to [CaptureService.sideEffects] and dispatch each effect
///    through the injected router.
/// 3. Tear everything down cleanly on shutdown so the host process exits
///    promptly (subscriptions cancelled before the service disposes).
class CaptureLifecycleController {
  final CaptureService _service;
  final CaptureSideEffectRouter _router;

  StreamSubscription<CaptureSideEffect>? _sub;
  bool _started = false;
  bool _disposed = false;

  CaptureLifecycleController({
    required CaptureService service,
    required CaptureSideEffectRouter router,
  })  : _service = service,
        _router = router;

  /// Whether [start] has succeeded (and [dispose] not yet called).
  bool get isRunning => _started && !_disposed;

  /// Start the capture pipeline. Idempotent — second call no-op while
  /// running. Failures inside [CaptureService.start] are logged but do
  /// NOT throw to the caller — the app must keep booting even if capture
  /// can't start (e.g., on Linux where native hooks aren't yet wired).
  Future<void> start() async {
    if (_disposed) {
      throw StateError(
        'CaptureLifecycleController.start() called after dispose()',
      );
    }
    if (_started) return;
    _started = true;

    try {
      await _service.start();
    } catch (e, s) {
      // Capture failure shouldn't crash the host app. Log + continue;
      // the user gets a non-functional clipboard monitor but the rest
      // of the app works.
      appLogger.error('[CaptureLifecycle] service start failed', e, s);
    }

    _sub = _service.sideEffects.listen(
      _router.handle,
      onError: (Object e, StackTrace s) {
        appLogger.error('[CaptureLifecycle] sideEffects stream error', e, s);
      },
    );
    appLogger.info('[CaptureLifecycle] started');
  }

  /// Pause the running pipeline without tearing it down. Distinct from
  /// [dispose]: pause keeps the underlying CaptureService instance alive
  /// (and reusable by [resume]) so toggling the Settings switch off and
  /// on within a single session is cheap.
  ///
  /// Cancels the sideEffects subscription first so any final emission
  /// from the service's internal teardown doesn't fire the router on a
  /// half-paused state.
  ///
  /// Idempotent — calling on a controller that isn't running is a no-op.
  Future<void> pause() async {
    if (_disposed) {
      throw StateError(
        'CaptureLifecycleController.pause() called after dispose()',
      );
    }
    if (!_started) return;
    _started = false;

    await _sub?.cancel();
    _sub = null;

    try {
      await _service.stop();
    } catch (e, s) {
      appLogger.error('[CaptureLifecycle] service stop failed', e, s);
    }
    appLogger.info('[CaptureLifecycle] paused');
  }

  /// Resume the pipeline after a [pause]. Semantic alias for [start] —
  /// uses the same idempotent code path. Provided for call-site clarity
  /// (`lifecycle.start()` reads as boot wiring, `lifecycle.resume()` as
  /// reaction to a Settings toggle).
  Future<void> resume() => start();

  /// Tear down. Idempotent. Cancels the subscription BEFORE disposing the
  /// service so any final emissions are silently dropped instead of
  /// firing the router on a half-torn-down app.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    await _sub?.cancel();
    _sub = null;

    try {
      await _service.dispose();
    } catch (e, s) {
      appLogger.error('[CaptureLifecycle] service dispose failed', e, s);
    }
    appLogger.info('[CaptureLifecycle] disposed');
  }
}
