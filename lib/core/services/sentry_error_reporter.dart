import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../config/brand_config.dart';
import '../config/env_config.dart';
import '../constants/app_constants.dart';
import '../logging/app_logger.dart';
import 'backend_service.dart';
import 'crash_severity_classifier.dart';
import 'error_reporter_service.dart';
import 'pii_scrubber.dart';
import 'sentry_noise_filters.dart';

/// Real Sentry error reporter implementation.
///
/// Uses `SentryFlutter.init()` with manual error handler wiring
/// (not wrapping runApp) for better control in an existing architecture.
class SentryErrorReporter implements ErrorReporterService {
  SentryNavigatorObserver? _navigatorObserver;

  /// True when the Sentry SDK initialized successfully. False after a fatal
  /// init failure (network, malformed DSN, etc.). Independent of user
  /// preference: a user who hasn't opted out should still get backend crash
  /// submission even when Sentry itself is broken.
  bool _sentryEnabled = true;

  /// True when reporting is enabled per user preference. [setEnabled] toggles
  /// this. Disabling stops both Sentry AND backend submission — opt-out is
  /// total privacy, not "Sentry off but backend on."
  bool _userEnabled = true;

  BackendService? _backendService;

  @override
  Future<void> init() async {
    // CRITICAL: this runs at line 49 of main(), BEFORE FlutterError.onError and
    // PlatformDispatcher.onError are wired. If `SentryFlutter.init()` throws
    // (network down on cold start, malformed DSN, Sentry's Hive offline cache
    // corrupted, disk full, native plugin init failed), the unhandled
    // exception aborts main() and the user sees a black window with no error
    // visible — same failure mode as the v15→v16 migration bug.
    //
    // Fix: catch every failure mode and disable Sentry locally. The app
    // proceeds without crash reporting, but it BOOTS — which is the bar.
    // Subsequent capture* calls become no-ops because `_enabled = false`.
    try {
      await SentryFlutter.init(
        (options) {
          options.dsn = EnvConfig.sentryDsn;
          options.environment = kDebugMode ? 'development' : 'production';
          options.release = '${BrandConfig.current.brand.name}@${AppConstants.appVersion}';
          options.tracesSampleRate = kDebugMode ? 1.0 : 0.1;
          options.debug = kDebugMode;
          options.beforeSend = _beforeSend;
          options.attachStacktrace = true;

          // Release health: tracks crash-free session rate in Sentry dashboard
          options.autoSessionTrackingInterval = const Duration(seconds: 30);
          options.enableAutoSessionTracking = true;

          // Native crash handling for Windows (sentry-native/Crashpad) and
          // macOS (sentry-cocoa). Without this we are blind to WebView2/CEF
          // process crashes — the renderer dies, the Dart isolate is unaware,
          // and no log is ever uploaded.
          options.enableNativeCrashHandling = true;
          options.enableAutoNativeBreadcrumbs = true;
          options.attachThreads = true;

          // App hang detection (macOS surfaces the "Meta logo, then nothing"
          // Facebook freeze as an app hang event rather than a crash).
          options.enableAppHangTracking = true;
        },
      );

      _navigatorObserver = SentryNavigatorObserver();
    } catch (e, stack) {
      // Local-only logging — Sentry itself is what failed, can't report there.
      _sentryEnabled = false;
      // appLogger may not exist yet at this point in main(); use debugPrint as
      // a last-ditch channel that goes to console + system log on all platforms.
      debugPrint('Sentry init failed: $e\n$stack');
      debugPrint(
          'Sentry crash reporting disabled, backend submission still active.');
    }
  }

  /// PII scrubbing + narrow noise filters before sending events to Sentry.
  ///
  /// Filter order matters: drop noise FIRST, then scrub PII on what remains.
  /// Scrubbing a soon-to-be-dropped event wastes work; dropping a noise
  /// event before scrubbing keeps the pipeline lean. The noise filter
  /// surface is locked by unit tests so it can never widen accidentally.
  FutureOr<SentryEvent?> _beforeSend(SentryEvent event, Hint hint) {
    if (!_sentryEnabled || !_userEnabled) return null;
    if (SentryNoiseFilters.shouldDrop(event)) return null;
    return piiScrubber(event);
  }

  @override
  Future<void> captureException(
    dynamic exception, {
    StackTrace? stackTrace,
    String? context,
  }) async {
    // User opt-out kills both paths. Sentry init failure only kills Sentry —
    // the backend submission below still runs as the production health
    // lifeline.
    if (!_userEnabled) return;

    if (_sentryEnabled) {
      await Sentry.captureException(
        exception,
        stackTrace: stackTrace,
        withScope: context != null
            ? (scope) => scope.setTag('context', context)
            : null,
      );
    }

    // Also submit to backend (fire-and-forget, non-blocking).
    // Empty scopeMetadata preserves existing behavior — captureException
    // does not currently attach structured metadata to backend reports.
    _dispatchCrashToBackend(exception, stackTrace);
  }

  @override
  Future<void> captureExceptionWithScope(
    Object exception,
    ReporterScopeCallback configureScope,
    Map<String, Object?> backendMetadata, {
    StackTrace? stackTrace,
  }) async {
    if (!_userEnabled) return;

    if (_sentryEnabled) {
      // Sentry side: invoke configureScope exactly once, scoped to this capture.
      // The Scope passed to withScope is per-capture, NOT global — concurrent
      // captures cannot trample each other's tags. See plan D7.
      await Sentry.captureException(
        exception,
        stackTrace: stackTrace,
        withScope: configureScope,
      );
    }

    // Backend side: forward the caller-provided metadata as-is. Runs even
    // when Sentry init failed — backend is the production health lifeline.
    // We deliberately do NOT replay configureScope to harvest scope state —
    // callbacks are not guaranteed pure (timestamps, counters, throws). The
    // caller is responsible for keeping configureScope and backendMetadata
    // consistent; instrumentedAsync builds both from the same source.
    _dispatchCrashToBackend(
      exception,
      stackTrace,
      scopeMetadata: backendMetadata,
    );
  }

  @override
  Future<void> captureMessage(String message) async {
    if (!_userEnabled || !_sentryEnabled) return;
    await Sentry.captureMessage(message);
  }

  @override
  void addBreadcrumb(String message, {Map<String, dynamic>? data}) {
    if (!_userEnabled || !_sentryEnabled) return;
    Sentry.addBreadcrumb(Breadcrumb(
      message: message,
      data: data,
      timestamp: DateTime.now(),
    ));
  }

  @override
  void setTag(String key, String value) {
    Sentry.configureScope((scope) => scope.setTag(key, value));
  }

  @override
  void setUserIdentifier(String? id, {String? username, String? email}) {
    Sentry.configureScope((scope) {
      scope.setUser(id != null
          ? SentryUser(id: id, username: username, email: email)
          : null);
    });
  }

  @override
  void clearUserIdentifier() {
    Sentry.configureScope((scope) => scope.setUser(null));
  }

  @override
  NavigatorObserver? get navigationObserver => _navigatorObserver;

  @override
  void setEnabled(bool value) {
    // Toggles user opt-in/out. Total privacy switch — affects both Sentry
    // and backend submission. Does NOT re-enable Sentry SDK if init failed.
    _userEnabled = value;
  }

  @override
  void setBackendService(dynamic backendService) {
    if (backendService is BackendService) {
      _backendService = backendService;
    }
  }

  /// Submit crash to backend alongside Sentry (fire-and-forget).
  ///
  /// Shared between [captureException] (empty [scopeMetadata]) and
  /// [captureExceptionWithScope] (caller-provided metadata) so backend
  /// crash coverage stays uniform across both code paths.
  void _dispatchCrashToBackend(
    dynamic exception,
    StackTrace? stackTrace, {
    Map<String, Object?> scopeMetadata = const {},
  }) {
    final backend = _backendService;
    if (backend == null) return;

    try {
      final errorMessage = exception.toString();
      String? metadataJson;
      if (scopeMetadata.isNotEmpty) {
        // Schema parity with NoOpErrorReporter: per-capture metadata is
        // nested under the `scope` key. Backend consumers looking for `op`
        // can use the same path (`metadata.scope.op`) regardless of which
        // reporter produced the event. NoOp may also include sibling
        // `breadcrumbs` / `tags` from its rolling buffer; Sentry doesn't
        // (Sentry handles its own breadcrumbs/tags through its SDK).
        //
        // jsonEncode may throw on non-serializable values; the outer try/catch
        // covers that — backend submission is best-effort by contract.
        metadataJson = jsonEncode({'scope': scopeMetadata});
      }
      final stack = stackTrace?.toString() ?? 'No stack trace';
      final severity = classifyCrashSeverity(
        errorMessage,
        stackTrace?.toString(),
      );

      appLogger
          .getRecentLogs(maxLines: 100)
          .then((diagnosticLog) {
            backend.submitCrash(
              stackTrace: stack,
              errorMessage: errorMessage,
              severity: severity,
              metadata: metadataJson,
              diagnosticLog: diagnosticLog.isNotEmpty ? diagnosticLog : null,
            );
          })
          .catchError((_) {
            backend.submitCrash(
              stackTrace: stack,
              errorMessage: errorMessage,
              severity: severity,
              metadata: metadataJson,
            );
          });
    } catch (_) {
      // Never let backend crash reporting break the app.
    }
  }
}
