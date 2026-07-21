import 'dart:convert';
import 'package:flutter/widgets.dart';

import '../logging/app_logger.dart';
import 'backend_service.dart';
import 'error_reporter_service.dart';
import 'crash_severity_classifier.dart';

/// Error reporter without Sentry but WITH backend crash submission.
///
/// Used when Sentry DSN is not configured. Sentry-specific features (breadcrumbs,
/// tags, navigator observer) are no-ops, but crashes are ALWAYS submitted to the
/// Go backend for production health monitoring.
///
/// This ensures crash visibility even when Sentry is not configured —
/// the Go backend admin dashboard is the production health lifeline.
class NoOpErrorReporter implements ErrorReporterService {
  BackendService? _backendService;
  bool _enabled = true;

  /// Rolling breadcrumb buffer for crash context.
  final List<Map<String, dynamic>> _breadcrumbs = [];
  static const _maxBreadcrumbs = 30;

  /// Tags for crash metadata context.
  final Map<String, String> _tags = {};

  @override
  Future<void> init() async {}

  @override
  Future<void> captureException(
    dynamic exception, {
    StackTrace? stackTrace,
    String? context,
  }) async {
    if (!_enabled) return;
    // No Sentry, but still submit to Go backend for production monitoring
    _submitCrashToBackend(exception, stackTrace, context);
  }

  @override
  Future<void> captureExceptionWithScope(
    Object exception,
    ReporterScopeCallback configureScope,
    Map<String, Object?> backendMetadata, {
    StackTrace? stackTrace,
  }) async {
    if (!_enabled) return;
    // No Sentry — the configureScope callback is silently ignored; this
    // implementation does not have a Sentry hub to apply it to.
    //
    // Backend gets the caller-provided metadata. Per the contract, we do NOT
    // replay configureScope to harvest scope state — callbacks are not
    // guaranteed pure. The caller built backendMetadata from the same source
    // as configureScope; we forward it as-is.
    _submitCrashToBackend(
      exception,
      stackTrace,
      null, // context goes through scope on Sentry; n/a here
      scopeMetadata: backendMetadata,
    );
  }

  @override
  Future<void> captureMessage(String message) async {}

  @override
  void addBreadcrumb(String message, {Map<String, dynamic>? data}) {
    _breadcrumbs.add({
      'message': message,
      'timestamp': DateTime.now().toIso8601String(),
      if (data != null) 'data': data,
    });
    if (_breadcrumbs.length > _maxBreadcrumbs) {
      _breadcrumbs.removeAt(0);
    }
  }

  @override
  void setTag(String key, String value) {
    _tags[key] = value;
  }

  @override
  void setUserIdentifier(String? id, {String? username, String? email}) {}

  @override
  void clearUserIdentifier() {}

  @override
  NavigatorObserver? get navigationObserver => null;

  @override
  void setEnabled(bool value) {
    _enabled = value;
  }

  @override
  void setBackendService(dynamic backendService) {
    if (backendService is BackendService) {
      _backendService = backendService;
    }
  }

  /// Submit crash to Go backend with metadata and diagnostic logs.
  /// Works independently of Sentry — this is the production health lifeline.
  ///
  /// [scopeMetadata] is per-capture metadata supplied by the caller (used by
  /// [captureExceptionWithScope]). It's merged with the rolling breadcrumb
  /// buffer and global tags; per-capture keys win on collision.
  void _submitCrashToBackend(
    dynamic exception,
    StackTrace? stackTrace,
    String? context, {
    Map<String, Object?> scopeMetadata = const {},
  }) {
    final backend = _backendService;
    if (backend == null) return;

    try {
      // Build metadata with breadcrumbs, tags, context, and per-capture scope.
      final metadata = <String, dynamic>{};
      if (_breadcrumbs.isNotEmpty) {
        metadata['breadcrumbs'] = List<Map<String, dynamic>>.from(_breadcrumbs);
      }
      if (_tags.isNotEmpty) {
        metadata['tags'] = Map<String, String>.from(_tags);
      }
      if (context != null) {
        metadata['context'] = context;
      }
      if (scopeMetadata.isNotEmpty) {
        // Per-capture metadata is namespaced under 'scope' so callers see it
        // distinct from the rolling-buffer 'tags'/'breadcrumbs'.
        metadata['scope'] = Map<String, Object?>.from(scopeMetadata);
      }

      final metadataJson =
          metadata.isNotEmpty ? jsonEncode(metadata) : null;

      // Pre-compute the heuristic severity so both submit paths agree
      // (see classifyCrashSeverity in sentry_error_reporter.dart).
      final errorMessage = exception.toString();
      final severity = classifyCrashSeverity(errorMessage, stackTrace?.toString());

      // Collect diagnostic log asynchronously, then submit
      appLogger.getRecentLogs(maxLines: 100).then((diagnosticLog) {
        backend.submitCrash(
          stackTrace: stackTrace?.toString() ?? 'No stack trace',
          errorMessage: errorMessage,
          severity: severity,
          metadata: metadataJson,
          diagnosticLog: diagnosticLog.isNotEmpty ? diagnosticLog : null,
        );
      }).catchError((_) {
        // Fallback: submit without diagnostic log
        backend.submitCrash(
          stackTrace: stackTrace?.toString() ?? 'No stack trace',
          errorMessage: errorMessage,
          severity: severity,
          metadata: metadataJson,
        );
      });
    } catch (_) {
      // Never let crash reporting break the app
    }
  }
}
