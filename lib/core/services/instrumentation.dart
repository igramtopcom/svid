import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show Scope;

import 'error_reporter_service.dart';
import 'pii_scrubber.dart';

/// Operation name for [instrumentedAsync] / [instrumentedSync]. Convention:
/// `domain.action` in lower snake_case (e.g. `ytdlp.extract_info`,
/// `backend.submit_crash`, `license.activate`). Used as Sentry tag `op` and
/// as the breadcrumb category for failures.
typedef OperationName = String;

/// Fallback when an instrumented block throws and the caller wants to swallow.
typedef OnErrorCallback<T> = T Function(Object error, StackTrace stack);

/// Wrap an async block with Sentry instrumentation.
///
/// On failure, captures the exception with `op` tag set on the event via
/// per-capture scope (NOT global scope — see plan D7). The caller decides
/// whether to rethrow, swallow with [onError], or convert to [Result] by
/// wrapping with `runCatching` at the outside.
///
/// Failure handling rules:
/// - [rethrowAfterReport] = `true` (default): exception is captured then
///   rethrown with the original stack preserved.
/// - [rethrowAfterReport] = `false` AND [onError] supplied: exception is
///   captured, [onError] is invoked, its result returned.
/// - [rethrowAfterReport] = `false` AND [onError] = `null`: throws
///   [ArgumentError] immediately. This combo has no defined return; refusing
///   it loud beats producing an `instance of T` runtime cast failure.
///
/// [emitEntryBreadcrumb] is off by default — turning it on emits a breadcrumb
/// at block entry. Useful for high-value boundaries (license check, payment),
/// noisy for hot paths.
///
/// [reporter] can be supplied for tests; production code should leave it null
/// and let the caller pass in a reporter via the helper composition pattern.
/// When null, the function still runs the block but skips Sentry interaction
/// — equivalent to a no-op reporter.
Future<T> instrumentedAsync<T>(
  OperationName op,
  Future<T> Function() block, {
  Map<String, Object?>? attributes,
  Map<String, Object?>? entryBreadcrumbData,
  OnErrorCallback<T>? onError,
  bool rethrowAfterReport = true,
  bool emitEntryBreadcrumb = false,
  ErrorReporterService? reporter,
}) async {
  // Combination guard — see goal of "loud refusal of misconfiguration".
  if (!rethrowAfterReport && onError == null) {
    throw ArgumentError(
      'instrumentedAsync($op): must supply onError when rethrowAfterReport=false',
    );
  }

  if (emitEntryBreadcrumb && reporter != null) {
    // Entry breadcrumb data is separate from event attributes: callers may
    // want a coarse summary on the breadcrumb (cheap, indexed in Sentry's
    // breadcrumb buffer) and richer attributes on the captured event itself.
    // Falls back to scrubbed attributes if caller didn't customize.
    safeBreadcrumb(
      reporter,
      'op.start: $op',
      data: _scrubAttributesForBreadcrumb(entryBreadcrumbData ?? attributes),
    );
  }

  try {
    return await block();
  } catch (e, stack) {
    // Build the per-capture scope and the parallel backend metadata from
    // the same scrubbed source. Call this twice and you risk side effects;
    // build once, hand both to the reporter.
    final scrubbedAttrs = _scrubAttributes(attributes);
    final backendMetadata = <String, Object?>{
      'op': op,
      if (scrubbedAttrs != null) ...scrubbedAttrs,
    };
    void configureScope(Scope scope) {
      scope.setTag('op', op);
      if (scrubbedAttrs != null) {
        for (final entry in scrubbedAttrs.entries) {
          _attachToScope(scope, entry.key, entry.value);
        }
      }
    }

    await safeCaptureException(
      reporter,
      e,
      stackTrace: stack,
      scopeConfig: configureScope,
      backendMetadata: backendMetadata,
    );

    if (rethrowAfterReport) {
      // Preserve the original stack across the await boundary.
      Error.throwWithStackTrace(e, stack);
    }

    // onError is non-null here per the combination guard at the top.
    try {
      return onError!(e, stack);
    } catch (onErrorException, onErrorStack) {
      // onError itself blew up. Report the secondary failure for visibility,
      // then rethrow the ORIGINAL exception — the user's primary failure
      // must not be masked by a buggy fallback.
      await safeCaptureException(
        reporter,
        onErrorException,
        stackTrace: onErrorStack,
      );
      Error.throwWithStackTrace(e, stack);
    }
  }
}

/// Sync version of [instrumentedAsync]. Same contract, no `await`.
T instrumentedSync<T>(
  OperationName op,
  T Function() block, {
  Map<String, Object?>? attributes,
  Map<String, Object?>? entryBreadcrumbData,
  OnErrorCallback<T>? onError,
  bool rethrowAfterReport = true,
  bool emitEntryBreadcrumb = false,
  ErrorReporterService? reporter,
}) {
  if (!rethrowAfterReport && onError == null) {
    throw ArgumentError(
      'instrumentedSync($op): must supply onError when rethrowAfterReport=false',
    );
  }

  if (emitEntryBreadcrumb && reporter != null) {
    safeBreadcrumb(
      reporter,
      'op.start: $op',
      data: _scrubAttributesForBreadcrumb(entryBreadcrumbData ?? attributes),
    );
  }

  try {
    return block();
  } catch (e, stack) {
    final scrubbedAttrs = _scrubAttributes(attributes);
    final backendMetadata = <String, Object?>{
      'op': op,
      if (scrubbedAttrs != null) ...scrubbedAttrs,
    };
    void configureScope(Scope scope) {
      scope.setTag('op', op);
      if (scrubbedAttrs != null) {
        for (final entry in scrubbedAttrs.entries) {
          _attachToScope(scope, entry.key, entry.value);
        }
      }
    }

    // Fire-and-forget — sync callers don't await; the report happens on the
    // next microtask. Rethrow first so the caller's stack is preserved
    // synchronously.
    final reporterCopy = reporter;
    if (reporterCopy != null) {
      // ignore: discarded_futures
      safeCaptureException(
        reporterCopy,
        e,
        stackTrace: stack,
        scopeConfig: configureScope,
        backendMetadata: backendMetadata,
      );
    }

    if (rethrowAfterReport) {
      Error.throwWithStackTrace(e, stack);
    }

    try {
      return onError!(e, stack);
    } catch (onErrorException, onErrorStack) {
      if (reporterCopy != null) {
        // ignore: discarded_futures
        safeCaptureException(
          reporterCopy,
          onErrorException,
          stackTrace: onErrorStack,
        );
      }
      Error.throwWithStackTrace(e, stack);
    }
  }
}

/// Fail-safe [ErrorReporterService.captureException] / [captureExceptionWithScope]
/// wrapper. Mirrors [safeBreadcrumb]: a broken reporter, a null reporter, or
/// an in-flight container disposal cannot crash the caller.
///
/// Two modes:
/// - Without [scopeConfig]: forwards to plain `captureException`.
/// - With [scopeConfig]: forwards to `captureExceptionWithScope`. The caller
///   MUST also provide [backendMetadata] derived from the same source data
///   (see [ErrorReporterService.captureExceptionWithScope] contract). The
///   `assert` below catches missing metadata in DEBUG builds during local
///   development — but the surrounding fail-safe try/catch swallows the
///   AssertionError, so the wrapper still returns cleanly. In RELEASE the
///   assert is stripped entirely; we fall back to an empty metadata map.
///   Net effect either way: telemetry continues, never throws to caller.
///   (Discovery: only debug-mode console output flags the misconfiguration.)
///
/// Returns even if the reporter throws — telemetry must never break the app.
Future<void> safeCaptureException(
  ErrorReporterService? reporter,
  Object exception, {
  StackTrace? stackTrace,
  ReporterScopeCallback? scopeConfig,
  Map<String, Object?>? backendMetadata,
}) async {
  if (reporter == null) return;
  // Dedupe gate — guards against repeating-source exceptions
  // turning into a `POST /api/v1/crashes` flood. log.md 2026-05-12
  // §528–647 caught a single `_debugDuringDeviceUpdate` assertion
  // amplifying into 20+ crash POSTs in seconds (each Flutter
  // assertion → FlutterError.onError → this function), visibly
  // freezing the app. The dedupe fingerprints by exception type +
  // top stack frames so an unrelated NEW failure still reports.
  if (!_CrashDeduper.shouldReport(exception, stackTrace)) {
    return;
  }
  try {
    if (scopeConfig != null) {
      assert(
        backendMetadata != null,
        'safeCaptureException: scopeConfig requires backendMetadata',
      );
      await reporter.captureExceptionWithScope(
        exception,
        scopeConfig,
        backendMetadata ?? const <String, Object?>{},
        stackTrace: stackTrace,
      );
    } else {
      await reporter.captureException(exception, stackTrace: stackTrace);
    }
  } catch (_) {
    // Silent — same contract as safeBreadcrumb. We do not even log,
    // because logging here could itself loop into Sentry breadcrumbs
    // and amplify the failure.
  }
}

// --- Internals ---

/// Threshold (chars) above which an attribute value is routed to `setExtra`
/// instead of `setTag`. Sentry historically caps tag values at 200 chars; we
/// pick a tighter threshold so we never hit the limit at runtime.
@visibleForTesting
const int kAttributeTagMaxChars = 150;

Map<String, Object?>? _scrubAttributes(Map<String, Object?>? input) {
  if (input == null || input.isEmpty) return null;
  final result = <String, Object?>{};
  for (final entry in input.entries) {
    final v = entry.value;
    if (v is String) {
      result[entry.key] = scrubString(v);
    } else {
      result[entry.key] = v;
    }
  }
  return result;
}

Map<String, dynamic>? _scrubAttributesForBreadcrumb(
  Map<String, Object?>? input,
) {
  final scrubbed = _scrubAttributes(input);
  if (scrubbed == null) return null;
  return Map<String, dynamic>.from(scrubbed);
}

void _attachToScope(Scope scope, String key, Object? value) {
  // String values go to tags if short, extras if long. Non-strings go to
  // extras (tags only accept strings per Sentry semantics).
  if (value is String) {
    if (value.length <= kAttributeTagMaxChars) {
      scope.setTag(key, value);
    } else {
      // ignore: deprecated_member_use
      scope.setExtra(key, value);
    }
  } else {
    // ignore: deprecated_member_use
    scope.setExtra(key, value);
  }
}

/// In-memory dedupe for `safeCaptureException`.
///
/// Problem (log.md 2026-05-12 §528–647): a single repeating Flutter
/// framework assertion (`MouseTracker._debugDuringDeviceUpdate`)
/// fired ~20 times per second through `FlutterError.onError`, each
/// firing a `POST /api/v1/crashes` request. The naive
/// `safeCaptureException` had no gate, so the crash reporter
/// itself became the amplifier turning a recoverable hover stutter
/// into a network/CPU storm that visibly froze the app.
///
/// Dedupe strategy:
/// - Fingerprint = `runtimeType + first 3 lines of stack trace`.
///   Type alone collides too aggressively (every `StateError` is
///   the same); full stack churns under inlining. Top-3 frames hit
///   the sweet spot for "same logical site".
/// - TTL = 5 minutes. Long enough to suppress a hot loop (the
///   observed loop fires sub-second), short enough that a
///   genuinely-recurring problem still surfaces multiple events
///   per session for triage signal.
/// - Bounded map size 32. Sufficient distinct fingerprints in a
///   typical session, and the eviction is O(1) (drop the oldest
///   insertion-ordered entry — Dart's `Map` literal preserves
///   insertion order so `keys.first` is the LRU candidate).
///
/// Tested in `test/core/services/safe_capture_exception_dedupe_test.dart`.
class _CrashDeduper {
  static final Map<String, DateTime> _seen = <String, DateTime>{};
  static const Duration _ttl = Duration(minutes: 5);
  static const int _maxEntries = 32;

  static bool shouldReport(Object exception, StackTrace? stack) {
    final now = DateTime.now();
    // Sweep expired entries first so the bounded-size check below
    // reflects only live entries.
    _seen.removeWhere((_, when) => now.difference(when) > _ttl);

    final key = _fingerprint(exception, stack);
    if (_seen.containsKey(key)) {
      return false;
    }
    if (_seen.length >= _maxEntries) {
      _seen.remove(_seen.keys.first);
    }
    _seen[key] = now;
    return true;
  }

  static String _fingerprint(Object exception, StackTrace? stack) {
    final type = exception.runtimeType.toString();
    // Include the head of the exception message. Truly-repeating
    // assertions (Flutter framework storms, log.md root cause)
    // emit IDENTICAL message text, so this preserves the dedupe.
    // Logically-distinct failures that happen to share a type +
    // stack site (two ops both throwing `StateError` at the same
    // helper line, each with their own descriptive text) get
    // different message heads, so they surface independently —
    // fixes the "concurrent ops collapse to one capture"
    // regression in instrumentation_test.dart §9. 80 chars is
    // enough to differentiate typical descriptive messages
    // without bloating the cache key.
    final messageRaw = exception.toString();
    final messageHead =
        messageRaw.length > 80 ? messageRaw.substring(0, 80) : messageRaw;
    if (stack == null) return '$type::$messageHead';
    // Top 3 non-empty stack lines — they identify the throwing
    // site stably even across inlined helper frames.
    final frames = stack
        .toString()
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .take(3)
        .join('|');
    return '$type::$messageHead::$frames';
  }

  /// Reset for tests — never call from production code.
  @visibleForTesting
  static void resetForTesting() {
    _seen.clear();
  }
}

/// Test-only re-export so tests can reset the in-memory dedupe
/// state between cases without exposing the private class.
@visibleForTesting
void resetCrashDedupeForTesting() => _CrashDeduper.resetForTesting();
