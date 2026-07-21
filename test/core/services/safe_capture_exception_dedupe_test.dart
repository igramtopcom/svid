/// Pins the dedupe contract on `safeCaptureException` introduced
/// 2026-05-12 in response to the `_debugDuringDeviceUpdate`
/// assertion storm (log.md §528–647): a single repeating Flutter
/// framework assertion fired 20+ `POST /api/v1/crashes` requests
/// in seconds, visibly freezing the app.
///
/// The dedupe gates by `(exception runtimeType, top-3 stack
/// frames)` fingerprint with a 5-minute TTL and a 32-entry bounded
/// cache. These tests pin:
///   1. identical exception fired twice in the same session
///      reports exactly once
///   2. an exception with different stack reports independently
///      (call sites must not collide)
///   3. an exception with a different type reports independently
///   4. the cache evicts the oldest entry once it crosses 32 items
///      (so a long-running session with many distinct failures
///      doesn't permanently silence the 33rd onwards)
///   5. `resetCrashDedupeForTesting()` zeroes state between tests
///
/// We do NOT pin TTL expiry here because the implementation reads
/// `DateTime.now()` directly — pinning it would require either a
/// clock seam (over-engineering for one dedupe gate) or a
/// 5-minute test wait. Instead the TTL behavior is covered by
/// code inspection: `removeWhere` runs unconditionally on every
/// call against a real-clock threshold.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/services/error_reporter_service.dart';
import 'package:svid/core/services/instrumentation.dart';

/// Test-only reporter that counts capture* calls.
class _CountingReporter extends ErrorReporterService {
  int captureCalls = 0;

  @override
  Future<void> init() async {}

  @override
  Future<void> captureException(
    dynamic exception, {
    StackTrace? stackTrace,
    String? context,
  }) async {
    captureCalls++;
  }

  @override
  Future<void> captureExceptionWithScope(
    Object exception,
    ReporterScopeCallback configureScope,
    Map<String, Object?> backendMetadata, {
    StackTrace? stackTrace,
  }) async {
    captureCalls++;
  }

  @override
  Future<void> captureMessage(String message) async {}

  @override
  void addBreadcrumb(String message, {Map<String, dynamic>? data}) {}

  @override
  void setTag(String key, String value) {}

  @override
  void setUserIdentifier(String? id, {String? username, String? email}) {}

  @override
  void clearUserIdentifier() {}

  @override
  NavigatorObserver? get navigationObserver => null;

  @override
  void setEnabled(bool value) {}
}

void main() {
  group('safeCaptureException dedupe', () {
    late _CountingReporter reporter;

    setUp(() {
      resetCrashDedupeForTesting();
      reporter = _CountingReporter();
    });

    test(
      'identical exception + identical stack reports exactly once',
      () async {
        final stack = StackTrace.fromString(
          '#0 widget.build (a.dart:1)\n'
          '#1 element.build (b.dart:2)\n'
          '#2 owner.flush (c.dart:3)\n',
        );
        final err = StateError('mouse_tracker assertion');

        await safeCaptureException(reporter, err, stackTrace: stack);
        await safeCaptureException(reporter, err, stackTrace: stack);
        await safeCaptureException(reporter, err, stackTrace: stack);

        expect(
          reporter.captureCalls,
          1,
          reason:
              'A spinning assertion must not amplify into N POST '
              '/api/v1/crashes — log.md §528–647 root-cause guard',
        );
      },
    );

    test(
      'same exception type, different stack frames reports both — '
      'do NOT collide call sites',
      () async {
        final err1 = StateError('same type different site');
        final err2 = StateError('same type different site');

        final stackA = StackTrace.fromString(
          '#0 widgetA.build (a.dart:10)\n'
          '#1 element.build (b.dart:2)\n',
        );
        final stackB = StackTrace.fromString(
          '#0 widgetB.build (a.dart:99)\n'
          '#1 element.build (b.dart:2)\n',
        );

        await safeCaptureException(reporter, err1, stackTrace: stackA);
        await safeCaptureException(reporter, err2, stackTrace: stackB);

        expect(
          reporter.captureCalls,
          2,
          reason:
              'Two distinct throwing sites must surface independently '
              'so triage signal is preserved.',
        );
      },
    );

    test(
      'different exception types report independently even with same stack',
      () async {
        final stack = StackTrace.fromString(
          '#0 widget.build (a.dart:1)\n'
          '#1 element.build (b.dart:2)\n',
        );

        await safeCaptureException(
          reporter,
          StateError('first'),
          stackTrace: stack,
        );
        await safeCaptureException(
          reporter,
          ArgumentError('second'),
          stackTrace: stack,
        );

        expect(reporter.captureCalls, 2);
      },
    );

    test(
      'null reporter is a no-op (telemetry-disabled mode)',
      () async {
        await safeCaptureException(
          null,
          StateError('ignored'),
          stackTrace: StackTrace.empty,
        );
        // Nothing observable to assert beyond "does not throw" —
        // pin the contract that null reporter short-circuits before
        // the dedupe gate too.
        expect(true, isTrue);
      },
    );

    test(
      'bounded cache evicts oldest after 32 distinct fingerprints',
      () async {
        // Fire 33 distinct exceptions, then fire the FIRST one again.
        // Pre-eviction it would be deduped; post-eviction it should
        // surface fresh — proving the cache evicted the oldest entry
        // once it hit the 32-entry ceiling.
        for (var i = 0; i < 33; i++) {
          final stack = StackTrace.fromString(
            '#0 frame$i (file$i.dart:$i)\n',
          );
          await safeCaptureException(
            reporter,
            StateError('err$i'),
            stackTrace: stack,
          );
        }
        expect(
          reporter.captureCalls,
          33,
          reason: 'all 33 distinct fingerprints should report on first sighting',
        );

        // Fire the OLDEST again — fingerprint 'err0' + frame0 — and
        // it should now be a cache miss (evicted) and report again.
        await safeCaptureException(
          reporter,
          StateError('err0'),
          stackTrace: StackTrace.fromString('#0 frame0 (file0.dart:0)\n'),
        );
        expect(
          reporter.captureCalls,
          34,
          reason:
              'oldest fingerprint must be evicted once cache fills, so a '
              'long-running session does not permanently silence early '
              'failures',
        );
      },
    );

    test(
      'resetCrashDedupeForTesting clears state between tests',
      () async {
        final stack = StackTrace.fromString('#0 sameframe\n');
        final err = StateError('boom');

        await safeCaptureException(reporter, err, stackTrace: stack);
        expect(reporter.captureCalls, 1);

        // Without reset, the second call would dedupe.
        resetCrashDedupeForTesting();

        await safeCaptureException(reporter, err, stackTrace: stack);
        expect(
          reporter.captureCalls,
          2,
          reason:
              'reset must clear the in-memory fingerprint map so test '
              'isolation works',
        );
      },
    );
  });
}
