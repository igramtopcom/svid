import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:ssvid/core/services/error_reporter_service.dart';

/// Test double for [ErrorReporterService] that records all calls.
class FakeErrorReporter implements ErrorReporterService {
  bool initCalled = false;
  bool enabled = true;
  final List<CapturedError> capturedExceptions = [];
  final List<CapturedScopedError> capturedScopedExceptions = [];
  final List<String> capturedMessages = [];
  final List<String> breadcrumbs = [];
  final Map<String, String> tags = {};
  String? userId;
  String? userUsername;
  String? userEmail;

  /// Optional injected behavior. If set, [captureException] and
  /// [captureExceptionWithScope] will throw this on call — used to test
  /// that wrappers swallow reporter failures.
  Object? throwOnCapture;

  @override
  Future<void> init() async {
    initCalled = true;
  }

  @override
  Future<void> captureException(
    dynamic exception, {
    StackTrace? stackTrace,
    String? context,
  }) async {
    if (throwOnCapture != null) {
      throw throwOnCapture!;
    }
    capturedExceptions.add(
      CapturedError(
        exception: exception,
        stackTrace: stackTrace,
        context: context,
      ),
    );
  }

  @override
  Future<void> captureExceptionWithScope(
    Object exception,
    ReporterScopeCallback configureScope,
    Map<String, Object?> backendMetadata, {
    StackTrace? stackTrace,
  }) async {
    if (throwOnCapture != null) {
      throw throwOnCapture!;
    }
    // Apply the callback against a recording scope so tests can assert on
    // the tags/extras that WOULD have been set on the real Sentry scope.
    // Production implementations MUST NOT replay configureScope to harvest
    // metadata (callbacks aren't guaranteed pure) — but the fake does so
    // strictly for test introspection. Tests asserting that callbacks
    // throw are responsible for handling the propagation themselves; this
    // fake intentionally does NOT swallow callback exceptions so tests
    // expecting failure modes see them.
    final recordingScope = _RecordingScope();
    configureScope(recordingScope);
    capturedScopedExceptions.add(
      CapturedScopedError(
        exception: exception,
        stackTrace: stackTrace,
        backendMetadata: Map<String, Object?>.from(backendMetadata),
        capturedTags: Map<String, String>.from(recordingScope.tags),
        capturedExtras: Map<String, Object?>.from(recordingScope.extras),
      ),
    );
  }

  @override
  Future<void> captureMessage(String message) async {
    capturedMessages.add(message);
  }

  @override
  void addBreadcrumb(String message, {Map<String, dynamic>? data}) {
    breadcrumbs.add(message);
  }

  @override
  void setTag(String key, String value) {
    tags[key] = value;
  }

  @override
  void setUserIdentifier(String? id, {String? username, String? email}) {
    userId = id;
    userUsername = username;
    userEmail = email;
  }

  @override
  void clearUserIdentifier() {
    userId = null;
    userUsername = null;
    userEmail = null;
  }

  @override
  NavigatorObserver? get navigationObserver => null;

  @override
  void setEnabled(bool value) {
    enabled = value;
  }

  @override
  void setBackendService(dynamic backendService) {}

  void reset() {
    initCalled = false;
    enabled = true;
    capturedExceptions.clear();
    capturedScopedExceptions.clear();
    capturedMessages.clear();
    breadcrumbs.clear();
    tags.clear();
    userId = null;
    userUsername = null;
    userEmail = null;
    throwOnCapture = null;
  }
}

class CapturedError {
  final dynamic exception;
  final StackTrace? stackTrace;
  final String? context;

  CapturedError({required this.exception, this.stackTrace, this.context});
}

class CapturedScopedError {
  final Object exception;
  final StackTrace? stackTrace;
  final Map<String, Object?> backendMetadata;
  final Map<String, String> capturedTags;
  final Map<String, Object?> capturedExtras;

  CapturedScopedError({
    required this.exception,
    required this.stackTrace,
    required this.backendMetadata,
    required this.capturedTags,
    required this.capturedExtras,
  });
}

/// Minimal recording stand-in for `Scope`. Captures `setTag`/`setExtra` calls
/// for test assertions. Anything else delegates to default no-ops; tests that
/// need richer Scope behavior should construct a real Sentry hub.
class _RecordingScope implements Scope {
  @override
  final Map<String, String> tags = {};
  final Map<String, Object?> extras = {};

  @override
  Future<void> setTag(String key, String value) async {
    tags[key] = value;
  }

  @override
  Future<void> setExtra(String key, dynamic value) async {
    extras[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
