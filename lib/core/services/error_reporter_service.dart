import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show Scope;

/// Callback that configures a Sentry [Scope] for a single exception capture.
///
/// Used by [ErrorReporterService.captureExceptionWithScope] to attach per-event
/// tags/extras without mutating global scope state.
///
/// Implementations of [ErrorReporterService] MUST invoke this callback at most
/// once per call. Callers should not rely on idempotent re-invocation —
/// the contract is one capture, one scope build.
///
/// Named `ReporterScopeCallback` (not `ScopeCallback`) to avoid collision
/// with the Sentry SDK's own `ScopeCallback` typedef, which has a slightly
/// different shape (`FutureOr<void> Function(Scope)`). Files importing both
/// `sentry_flutter` and this contract would otherwise hit an ambiguous-import
/// error at the call sites.
typedef ReporterScopeCallback = void Function(Scope scope);

/// Abstract interface for error reporting and crash tracking.
///
/// Implementations:
/// - [SentryErrorReporter] — real Sentry integration (when DSN configured)
/// - [NoOpErrorReporter] — no-op fallback (dev mode / DSN not configured)
abstract class ErrorReporterService {
  /// Initialize the error reporting service.
  Future<void> init();

  /// Capture an exception with optional stack trace and context.
  Future<void> captureException(
    dynamic exception, {
    StackTrace? stackTrace,
    String? context,
  });

  /// Capture an exception with per-event scope configuration AND structured
  /// metadata for the SSvid backend.
  ///
  /// Use this when you need to attach searchable tags/extras (e.g. `op`,
  /// operation attributes) to a single Sentry event without leaking them to
  /// concurrent captures via the global scope.
  ///
  /// **Contract — both arguments must be derived from the same source data:**
  /// - [configureScope] is invoked exactly once with a fresh [Scope]; the
  ///   Sentry-side implementation passes it as `withScope:` to
  ///   `Sentry.captureException`.
  /// - [backendMetadata] is forwarded as-is to the SSvid backend's crash
  ///   submission. Implementations MUST NOT replay [configureScope] to harvest
  ///   metadata for the backend — callbacks are not guaranteed pure.
  ///
  /// The pair stays consistent only because the caller built both from the
  /// same scrubbed source. The wrapper [instrumentedAsync] enforces this; if
  /// you call this method directly, you carry the same responsibility.
  Future<void> captureExceptionWithScope(
    Object exception,
    ReporterScopeCallback configureScope,
    Map<String, Object?> backendMetadata, {
    StackTrace? stackTrace,
  });

  /// Capture a plain text message.
  Future<void> captureMessage(String message);

  /// Add a breadcrumb for context in future error reports.
  void addBreadcrumb(String message, {Map<String, dynamic>? data});

  /// Set a tag on future error reports.
  void setTag(String key, String value);

  /// Set user identifier for error reports.
  void setUserIdentifier(String? id, {String? username, String? email});

  /// Clear user identifier.
  void clearUserIdentifier();

  /// Get a navigator observer for route tracking breadcrumbs.
  NavigatorObserver? get navigationObserver;

  /// Enable or disable error reporting (respects user preference).
  void setEnabled(bool value);

  /// Set backend service for dual crash reporting (Sentry + backend).
  /// Called after ProviderContainer is available.
  void setBackendService(dynamic backendService) {}
}

/// Provider for the error reporter service.
/// Defaults to a no-op so tests work without explicit overrides.
/// Overridden in main.dart with [SentryErrorReporter] when DSN is configured.
final errorReporterServiceProvider = Provider<ErrorReporterService>(
  (ref) => _NoOpErrorReporter(),
);

/// Fail-safe breadcrumb helper. Wraps the underlying call in try/catch so a
/// broken Sentry SDK, an in-flight container disposal, or a null reporter
/// can never crash the caller. Use this at any startup-critical or hot-path
/// call site instead of invoking [ErrorReporterService.addBreadcrumb] directly.
///
/// Telemetry must never crash the app — this is the contract.
void safeBreadcrumb(
  ErrorReporterService? reporter,
  String message, {
  Map<String, dynamic>? data,
}) {
  if (reporter == null) return;
  try {
    reporter.addBreadcrumb(message, data: data);
  } catch (_) {
    // Silent. We do not even log — logging here could itself loop into
    // Sentry breadcrumbs and amplify the failure.
  }
}

/// Silent no-op fallback — used as the default for [errorReporterServiceProvider].
/// Prevents [UnimplementedError] in tests that don't override the provider.
///
/// This is the test default. The runtime fallback when Sentry DSN is not
/// configured is the public [NoOpErrorReporter] in `noop_error_reporter.dart`,
/// which forwards crashes to the SSvid backend even without Sentry.
class _NoOpErrorReporter implements ErrorReporterService {
  @override
  Future<void> init() async {}
  @override
  Future<void> captureException(dynamic exception,
      {StackTrace? stackTrace, String? context}) async {}
  @override
  Future<void> captureExceptionWithScope(
    Object exception,
    ReporterScopeCallback configureScope,
    Map<String, Object?> backendMetadata, {
    StackTrace? stackTrace,
  }) async {}
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
  @override
  void setBackendService(dynamic backendService) {}
}
