import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/floating_capture/data/services/capture_lifecycle_controller.dart';
import 'package:ssvid/features/floating_capture/data/services/capture_side_effect_router.dart';
import 'package:ssvid/features/floating_capture/domain/entities/snooze_duration.dart';
import 'package:ssvid/features/floating_capture/domain/entities/snooze_state.dart';
import 'package:ssvid/features/floating_capture/domain/services/capture_service.dart';

/// Minimal fake [CaptureService] — gives tests direct control over the
/// sideEffects stream and counters for start/stop/dispose.
class _FakeCaptureService implements CaptureService {
  final _effects = StreamController<CaptureSideEffect>.broadcast();
  bool _active = false;
  bool _disposed = false;
  int startCount = 0;
  int disposeCount = 0;
  Object? failOnStart;

  @override
  Stream<CaptureSideEffect> get sideEffects => _effects.stream;

  final _snoozeChanges = StreamController<SnoozeState>.broadcast();

  @override
  Stream<SnoozeState> get snoozeChanges => _snoozeChanges.stream;

  @override
  bool get isActive => _active;

  @override
  SnoozeState get currentSnooze => SnoozeState.inactive;

  @override
  Future<void> start() async {
    startCount++;
    if (failOnStart != null) {
      final f = failOnStart!;
      failOnStart = null;
      throw f;
    }
    _active = true;
  }

  @override
  Future<void> stop() async {
    _active = false;
  }

  @override
  Future<void> snoozeFor(SnoozeDuration duration) async {}

  @override
  Future<void> resumeFromSnooze() async {}

  int resetCooldownsCount = 0;
  @override
  void resetCooldowns() {
    resetCooldownsCount++;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    disposeCount++;
    _disposed = true;
    _active = false;
    await _effects.close();
    await _snoozeChanges.close();
  }

  /// Test helper: emit a side effect.
  void emit(CaptureSideEffect e) => _effects.add(e);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('lifecycle', () {
    test('initial isRunning=false', () {
      final ctl = CaptureLifecycleController(
        service: _FakeCaptureService(),
        router: const CaptureSideEffectRouter(),
      );
      expect(ctl.isRunning, isFalse);
    });

    test('start flips isRunning + invokes service.start', () async {
      final svc = _FakeCaptureService();
      final ctl = CaptureLifecycleController(
        service: svc,
        router: const CaptureSideEffectRouter(),
      );
      await ctl.start();
      expect(ctl.isRunning, isTrue);
      expect(svc.startCount, 1);
    });

    test('idempotent start — second call no-op', () async {
      final svc = _FakeCaptureService();
      final ctl = CaptureLifecycleController(
        service: svc,
        router: const CaptureSideEffectRouter(),
      );
      await ctl.start();
      await ctl.start();
      expect(svc.startCount, 1);
    });

    test('start swallows service.start exception', () async {
      final svc = _FakeCaptureService()..failOnStart = Exception('boom');
      final ctl = CaptureLifecycleController(
        service: svc,
        router: const CaptureSideEffectRouter(),
      );
      // Must not throw — host app must keep booting.
      await expectLater(ctl.start(), completes);
      // Still subscribed even though service failed (handler registered
      // for late-arriving events).
      expect(ctl.isRunning, isTrue);
    });

    test('start after dispose throws StateError', () async {
      final ctl = CaptureLifecycleController(
        service: _FakeCaptureService(),
        router: const CaptureSideEffectRouter(),
      );
      await ctl.dispose();
      expect(() => ctl.start(), throwsStateError);
    });
  });

  group('side effect routing', () {
    test('emitted effects flow through router callback', () async {
      final svc = _FakeCaptureService();
      String? capturedUrl;
      final router = CaptureSideEffectRouter(
        onOpenExternal: (u) async => capturedUrl = u,
      );
      final ctl = CaptureLifecycleController(service: svc, router: router);
      await ctl.start();

      svc.emit(const OpenExternalUrl('https://www.youtube.com/watch?v=abc'));
      // Allow the broadcast stream to deliver.
      await Future<void>.delayed(Duration.zero);

      expect(capturedUrl, 'https://www.youtube.com/watch?v=abc');
    });

    test('router exception does not poison the subscription', () async {
      final svc = _FakeCaptureService();
      var calls = 0;
      final router = CaptureSideEffectRouter(
        // First emission's handler throws; second's increments.
        onOpenExternal: (_) async {
          calls++;
          if (calls == 1) throw StateError('first fails');
        },
      );
      final ctl = CaptureLifecycleController(service: svc, router: router);
      await ctl.start();

      svc.emit(const OpenExternalUrl('https://www.youtube.com/watch?v=aaaaa'));
      await Future<void>.delayed(Duration.zero);
      svc.emit(const OpenExternalUrl('https://www.youtube.com/watch?v=bbbbb'));
      await Future<void>.delayed(Duration.zero);

      expect(calls, 2,
          reason: 'second emit must dispatch despite first throwing');
    });
  });

  group('pause / resume (Phase 1A.8)', () {
    test('pause stops service + cancels sub', () async {
      final svc = _FakeCaptureService();
      var calls = 0;
      final router = CaptureSideEffectRouter(
        onOpenExternal: (_) async => calls++,
      );
      final ctl = CaptureLifecycleController(service: svc, router: router);
      await ctl.start();
      expect(ctl.isRunning, isTrue);

      await ctl.pause();
      expect(ctl.isRunning, isFalse);
      expect(svc.isActive, isFalse);

      // Late emit after pause — sub is cancelled, router shouldn't fire.
      svc.emit(const OpenExternalUrl('https://post-pause'));
      await Future<void>.delayed(Duration.zero);
      expect(calls, 0);
    });

    test('pause when not running is a no-op', () async {
      final svc = _FakeCaptureService();
      final ctl = CaptureLifecycleController(
        service: svc,
        router: const CaptureSideEffectRouter(),
      );
      await ctl.pause(); // never started
      expect(svc.isActive, isFalse);
      expect(ctl.isRunning, isFalse);
    });

    test('resume after pause re-subscribes + restarts service', () async {
      final svc = _FakeCaptureService();
      var calls = 0;
      final router = CaptureSideEffectRouter(
        onOpenExternal: (_) async => calls++,
      );
      final ctl = CaptureLifecycleController(service: svc, router: router);
      await ctl.start();
      await ctl.pause();
      await ctl.resume();
      expect(ctl.isRunning, isTrue);
      expect(svc.startCount, 2,
          reason: 'service.start called once for boot, once for resume');

      svc.emit(const OpenExternalUrl('https://www.youtube.com/watch?v=postresume'));
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1, reason: 'router fires again after resume');
    });

    test('pause after dispose throws', () async {
      final ctl = CaptureLifecycleController(
        service: _FakeCaptureService(),
        router: const CaptureSideEffectRouter(),
      );
      await ctl.dispose();
      expect(() => ctl.pause(), throwsStateError);
    });

    test('idempotent pause — second call no-op', () async {
      final svc = _FakeCaptureService();
      final ctl = CaptureLifecycleController(
        service: svc,
        router: const CaptureSideEffectRouter(),
      );
      await ctl.start();
      await ctl.pause();
      await ctl.pause();
      // No assert needed — just shouldn't throw.
      expect(ctl.isRunning, isFalse);
    });
  });

  group('disposal', () {
    test('dispose cancels subscription before disposing service',
        () async {
      final svc = _FakeCaptureService();
      var calls = 0;
      final router = CaptureSideEffectRouter(
        onOpenExternal: (_) async => calls++,
      );
      final ctl = CaptureLifecycleController(service: svc, router: router);
      await ctl.start();
      await ctl.dispose();

      // Even if the service somehow emitted post-dispose, the cancelled
      // sub would drop it. Service is closed too, so emit throws — try
      // anyway and assert we don't see a callback.
      try {
        svc.emit(const OpenExternalUrl('https://post-dispose'));
      } catch (_) {
        // Expected — service closed.
      }
      await Future<void>.delayed(Duration.zero);

      expect(calls, 0);
      expect(svc.disposeCount, 1);
      expect(ctl.isRunning, isFalse);
    });

    test('dispose is idempotent', () async {
      final svc = _FakeCaptureService();
      final ctl = CaptureLifecycleController(
        service: svc,
        router: const CaptureSideEffectRouter(),
      );
      await ctl.start();
      await ctl.dispose();
      await ctl.dispose();
      expect(svc.disposeCount, 1);
    });

    test('dispose without start safe (no service.start was called)',
        () async {
      final svc = _FakeCaptureService();
      final ctl = CaptureLifecycleController(
        service: svc,
        router: const CaptureSideEffectRouter(),
      );
      await ctl.dispose();
      expect(svc.startCount, 0);
      expect(svc.disposeCount, 1);
    });
  });
}
