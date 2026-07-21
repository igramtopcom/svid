import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show Scope;
import 'package:svid/core/services/error_reporter_service.dart';
import 'package:svid/core/services/instrumentation.dart';

import 'fake_error_reporter.dart';

void main() {
  late FakeErrorReporter reporter;
  setUp(() {
    reporter = FakeErrorReporter();
    // Reset the safeCaptureException fingerprint dedupe cache
    // between tests — many cases reuse identical exception
    // shapes and would otherwise be silently merged across test
    // boundaries by the dedupe gate added 2026-05-12 (log.md
    // §528–647 root-cause guard).
    resetCrashDedupeForTesting();
  });

  group('instrumentedAsync — happy path', () {
    test('1: block returns value → no Sentry event captured', () async {
      final result = await instrumentedAsync(
        'test.success',
        () async => 42,
        reporter: reporter,
      );
      expect(result, 42);
      expect(reporter.capturedScopedExceptions, isEmpty);
      expect(reporter.capturedExceptions, isEmpty);
    });
  });

  group('instrumentedAsync — failure paths', () {
    test(
      '2: block throws sync, rethrowAfterReport=true → captured + rethrown',
      () async {
        Object? caught;
        try {
          await instrumentedAsync<int>(
            'test.throws',
            () => throw StateError('boom'),
            reporter: reporter,
          );
        } catch (e) {
          caught = e;
        }
        expect(caught, isA<StateError>());
        expect(reporter.capturedScopedExceptions, hasLength(1));
        expect(
          reporter.capturedScopedExceptions.first.exception,
          isA<StateError>(),
        );
      },
    );

    test(
      '3: rejected Future → captured + rethrown with original stack',
      () async {
        StackTrace? caughtStack;
        Object? caught;
        try {
          await instrumentedAsync<int>(
            'test.async_throws',
            () => Future.error(ArgumentError('async-boom'), StackTrace.current),
            reporter: reporter,
          );
        } catch (e, s) {
          caught = e;
          caughtStack = s;
        }
        expect(caught, isA<ArgumentError>());
        expect(caughtStack, isNotNull);
        expect(reporter.capturedScopedExceptions, hasLength(1));
      },
    );

    test(
      '4: rethrowAfterReport=false + no onError → ArgumentError immediately',
      () async {
        expect(
          () => instrumentedAsync<int>(
            'test.bad_config',
            () async => 1,
            rethrowAfterReport: false,
            reporter: reporter,
          ),
          throwsA(isA<ArgumentError>()),
        );
        // Block was never invoked because we throw on misconfiguration first.
        // No Sentry event should have been captured.
        expect(reporter.capturedScopedExceptions, isEmpty);
      },
    );

    test(
      '5: onError provided → onError result returned, exception captured',
      () async {
        final result = await instrumentedAsync<int>(
          'test.fallback',
          () => throw StateError('boom'),
          rethrowAfterReport: false,
          onError: (_, __) => -1,
          reporter: reporter,
        );
        expect(result, -1);
        expect(reporter.capturedScopedExceptions, hasLength(1));
      },
    );

    test(
      '6: onError itself throws → original exception rethrown, secondary captured separately',
      () async {
        // Hold a reference to the *exact* exception instance so we can assert
        // identity on rethrow — not just type. `isA<StateError>` would pass
        // even if the wrapper accidentally swapped in a different StateError.
        final originalException = StateError('original');
        Object? caught;
        try {
          await instrumentedAsync<int>(
            'test.bad_fallback',
            () => throw originalException,
            rethrowAfterReport: false,
            onError: (_, __) => throw FormatException('fallback-blew-up'),
            reporter: reporter,
          );
        } catch (e) {
          caught = e;
        }
        // Original exception INSTANCE is what propagates — fallback failure
        // must NOT mask it nor wrap it in a different exception.
        expect(
          identical(caught, originalException),
          isTrue,
          reason: 'must rethrow the same StateError instance, not a new one',
        );
        // Two captures: one scoped (original), one plain (the secondary failure).
        expect(reporter.capturedScopedExceptions, hasLength(1));
        expect(reporter.capturedExceptions, hasLength(1));
        expect(
          reporter.capturedExceptions.first.exception,
          isA<FormatException>(),
        );
      },
    );

    test(
      '7: reporter throws on capture → wrapper still rethrows original block exception',
      () async {
        reporter.throwOnCapture = StateError('reporter-broken');
        Object? caught;
        try {
          await instrumentedAsync<int>(
            'test.broken_reporter',
            () => throw ArgumentError('block-failure'),
            reporter: reporter,
          );
        } catch (e) {
          caught = e;
        }
        // Block exception (ArgumentError) propagates; reporter failure is
        // swallowed by safeCaptureException.
        expect(caught, isA<ArgumentError>());
      },
    );
  });

  group('instrumentedAsync — scope and tagging', () {
    test('8: op tag set on captured event via per-capture scope', () async {
      try {
        await instrumentedAsync<int>(
          'test.op_tagged',
          () => throw StateError('boom'),
          reporter: reporter,
        );
      } catch (_) {
        /* expected */
      }
      final captured = reporter.capturedScopedExceptions.single;
      expect(captured.capturedTags['op'], 'test.op_tagged');
      expect(captured.backendMetadata['op'], 'test.op_tagged');
    });

    test(
      '9: two concurrent calls with different ops → each event has its own op tag (no global scope leak)',
      () async {
        // Use a leak-detecting reporter: it shares ONE scope across all
        // captureExceptionWithScope invocations (mimicking the buggy
        // global-Sentry-scope behavior we explicitly forbid). If
        // instrumentedAsync ever regressed to mutating a shared scope, both
        // captures would see whichever op tag won the race.
        final detector = _SharedScopeDetectingReporter();

        Future<void> failing(String op) async {
          try {
            await instrumentedAsync<int>(op, () async {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              throw StateError('boom-$op');
            }, reporter: detector);
          } catch (_) {
            /* expected */
          }
        }

        await Future.wait([failing('test.op_a'), failing('test.op_b')]);
        expect(detector.capturedOps, hasLength(2));
        // Each capture must have its OWN op tag, not the shared scope's
        // last-write-wins value.
        expect(
          detector.capturedOps.toSet(),
          equals({'test.op_a', 'test.op_b'}),
        );
        // The detector's shared "global" scope must NOT have been touched —
        // proves we used per-capture withScope, not configureScope.
        expect(
          detector.sharedScopeMutationCount,
          0,
          reason: 'instrumentedAsync must not mutate a global Sentry scope',
        );
      },
    );

    test(
      '10: PII in attribute (URL, license key) → scrubbed in captured event',
      () async {
        try {
          await instrumentedAsync<int>(
            'test.pii',
            () => throw StateError('boom'),
            attributes: {
              'url': 'https://api.ssvid.app/v1/x',
              'license': '985168ae6f117474b5f5c57609d69276',
            },
            reporter: reporter,
          );
        } catch (_) {
          /* expected */
        }
        final captured = reporter.capturedScopedExceptions.single;
        expect(captured.backendMetadata['url'], contains('[URL_REDACTED]'));
        expect(
          captured.backendMetadata['license'],
          contains('[LICENSE_REDACTED]'),
        );
      },
    );

    test('12: long attribute value → routed to setExtra, not setTag', () async {
      final longValue = 'x' * (kAttributeTagMaxChars + 50);
      try {
        await instrumentedAsync<int>(
          'test.long_attr',
          () => throw StateError('boom'),
          attributes: {'huge': longValue},
          reporter: reporter,
        );
      } catch (_) {
        /* expected */
      }
      final captured = reporter.capturedScopedExceptions.single;
      expect(
        captured.capturedTags.containsKey('huge'),
        isFalse,
        reason: 'long value must NOT be a tag',
      );
      expect(captured.capturedExtras['huge'], longValue);
    });

    test(
      '13: Error (not Exception) thrown inside block → still captured',
      () async {
        try {
          await instrumentedAsync<int>(
            'test.error_not_exception',
            () => throw AssertionError('boom-error'),
            reporter: reporter,
          );
        } catch (_) {
          /* expected */
        }
        expect(reporter.capturedScopedExceptions, hasLength(1));
        expect(
          reporter.capturedScopedExceptions.first.exception,
          isA<AssertionError>(),
        );
      },
    );
  });

  group('instrumentedAsync — entry breadcrumb', () {
    test(
      '11: reporter throws inside addBreadcrumb → wrapper still completes block',
      () async {
        // Wire a reporter whose addBreadcrumb throws. safeBreadcrumb wraps it,
        // so the wrapper should not propagate the failure.
        final r = _BreadcrumbThrowingReporter();
        final result = await instrumentedAsync<int>(
          'test.breadcrumb_safe',
          () async => 7,
          emitEntryBreadcrumb: true,
          reporter: r,
        );
        expect(result, 7);
        // Stronger assertion: the breadcrumb path actually ran. If a future
        // refactor stopped calling safeBreadcrumb, the value-equality check
        // above would still pass — this counter wouldn't.
        expect(
          r.attemptCount,
          1,
          reason: 'breadcrumb sink must have been invoked exactly once',
        );
      },
    );
  });

  group('safeCaptureException', () {
    test('14: null reporter → no-op, returns immediately', () async {
      // Should not throw even with no reporter / arbitrary scope config.
      await safeCaptureException(null, StateError('x'));
      await safeCaptureException(
        null,
        StateError('x'),
        scopeConfig: (_) {},
        backendMetadata: const {},
      );
    });

    test(
      '15: reporter rejects Future on captureException → swallowed silently',
      () async {
        reporter.throwOnCapture = StateError('reporter-broken');
        // Should NOT throw even though the underlying reporter does.
        await safeCaptureException(reporter, StateError('original'));
      },
    );

    test(
      '16: scopeConfig + backendMetadata → forwards to captureExceptionWithScope, callback invoked once',
      () async {
        var callCount = 0;
        await safeCaptureException(
          reporter,
          StateError('boom'),
          scopeConfig: (scope) {
            callCount++;
            scope.setTag('manual', 'value');
          },
          backendMetadata: const {'op': 'manual.op'},
        );
        expect(callCount, 1, reason: 'callback must run exactly once');
        expect(reporter.capturedScopedExceptions, hasLength(1));
        final captured = reporter.capturedScopedExceptions.single;
        expect(captured.backendMetadata['op'], 'manual.op');
        expect(captured.capturedTags['manual'], 'value');
      },
    );

    test(
      '17: scopeConfig + null backendMetadata → assert in debug, defensive empty fallback in release',
      () async {
        // In Dart test mode (debug), `assert` is enabled and should fire.
        // Even so, the helper's outer try/catch swallows the AssertionError.
        // Test the resilience: function returns without throwing.
        Object? unhandled;
        try {
          await safeCaptureException(
            reporter,
            StateError('boom'),
            scopeConfig: (_) {},
            backendMetadata: null,
          );
        } catch (e) {
          unhandled = e;
        }
        expect(
          unhandled,
          isNull,
          reason: 'safeCaptureException must never propagate exceptions',
        );
      },
    );
  });
}

/// Reporter whose `addBreadcrumb` throws — used to exercise breadcrumb
/// resilience without affecting other tests. Counts attempts so tests
/// can prove the breadcrumb path actually ran (vs. silently being skipped).
class _BreadcrumbThrowingReporter extends FakeErrorReporter {
  int attemptCount = 0;

  @override
  void addBreadcrumb(String message, {Map<String, dynamic>? data}) {
    attemptCount++;
    throw StateError('breadcrumb-broken');
  }
}

/// Detector that would expose a global-scope leak. It records which `op`
/// each capture emitted (per-capture, the correct way) AND counts how many
/// times anyone mutated its single shared "global" scope (the wrong way).
///
/// If `instrumentedAsync` ever regressed to using `configureScope` instead
/// of `captureExceptionWithScope`, the [sharedScopeMutationCount] would be
/// non-zero and the test would fail.
class _SharedScopeDetectingReporter implements ErrorReporterService {
  final List<String> capturedOps = [];
  int sharedScopeMutationCount = 0;

  // The "shared global scope" the detector watches. Real production code
  // must NEVER touch this — all interaction should go through the
  // per-capture scope passed to configureScope.
  final _sharedGlobalScope = _MutationCountingScope();

  _SharedScopeDetectingReporter() {
    _sharedGlobalScope.onMutation = () => sharedScopeMutationCount++;
  }

  @override
  Future<void> captureExceptionWithScope(
    Object exception,
    ReporterScopeCallback configureScope,
    Map<String, Object?> backendMetadata, {
    StackTrace? stackTrace,
  }) async {
    // Per-capture: brand new scope each time. If the production helper
    // somehow shared scope state, this would be defeated.
    final perCaptureScope = _MutationCountingScope();
    configureScope(perCaptureScope);
    final op = perCaptureScope.tags['op'];
    if (op != null) capturedOps.add(op);
  }

  @override
  Future<void> init() async {}
  @override
  Future<void> captureException(
    dynamic exception, {
    StackTrace? stackTrace,
    String? context,
  }) async {}
  @override
  Future<void> captureMessage(String message) async {}
  @override
  void addBreadcrumb(String message, {Map<String, dynamic>? data}) {}
  @override
  void setTag(String key, String value) {
    // If anyone calls the GLOBAL ErrorReporterService.setTag (which is what
    // a configureScope-based leak would do), route through the recording
    // scope so the mutation hook fires and the counter increments.
    // ignore: discarded_futures — fire-and-forget is fine here, this is a
    // test double that just records calls.
    _sharedGlobalScope.setTag(key, value);
  }

  @override
  void setUserIdentifier(String? id, {String? username, String? email}) {}
  @override
  void clearUserIdentifier() {}
  @override
  get navigationObserver => null;
  @override
  void setEnabled(bool value) {}
  @override
  void setBackendService(dynamic backendService) {}
}

class _MutationCountingScope implements Scope {
  @override
  final Map<String, String> tags = {};
  void Function()? onMutation;

  @override
  Future<void> setTag(String key, String value) async {
    tags[key] = value;
    onMutation?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
