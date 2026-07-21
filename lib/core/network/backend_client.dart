import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import '../config/brand_config.dart';
import '../constants/app_constants.dart';
import '../errors/app_exception.dart';
import '../logging/app_logger.dart';
import '../services/error_reporter_service.dart';
import '../services/hardware_fingerprint_service.dart';
import '../services/instrumentation.dart';
import '../services/network_monitor_service.dart';
import '../services/pii_scrubber.dart';
import '../services/secure_credential_store.dart';

/// Internal flag carried in `RequestOptions.extra` that suppresses Sentry
/// instrumentation for telemetry-forwarding requests.
///
/// **Use only for crash forwarding** (e.g. `BackendService.submitCrash`).
/// Without this, capturing a failed `submitCrash` POST would itself try to
/// submit a crash → loop. User-initiated `submitBug` does NOT set this —
/// bug submission failures are real ops issues that ops genuinely wants to
/// see. The flag is read by both [_SentryHttpInterceptor] and
/// [BackendClient._reportEnvelopeError].
const String backendInternalRequestFlag = '_sentryInternal';

/// Request extra flag for backend calls whose failures are already handled by
/// the caller and should not become crash-dashboard events.
///
/// The request still emits normal breadcrumbs and still throws back to the
/// caller; this only suppresses the high-signal Sentry event. Use for
/// background telemetry and expected product states such as restore-not-found.
const String suppressBackendErrorReportFlag = '_suppressBackendErrorReport';

/// Internal flag set by `_AuthInterceptor` before re-fetching after a 401.
/// Lets [_SentryHttpInterceptor] distinguish original-401-then-refresh flow
/// (warning-level breadcrumb only) from real failures (capture as event).
const String _retryRequestFlag = '_isRetry';

@visibleForTesting
bool isRecoverableApiKeyErrorCode(String? code) {
  return code == 'INVALID_API_KEY' ||
      code == 'MISSING_API_KEY' ||
      code == 'REVOKED_API_KEY' ||
      code == 'EXPIRED_API_KEY';
}

/// Dedicated Dio client for Svid backend API.
/// Separate from [DioClient] which uses browser-like UA for download APIs.
class BackendClient {
  final SecureCredentialStore _credentials;
  final ErrorReporterService? _errorReporter;
  late final Dio _dio;
  StreamSubscription<bool>? _onlineSub;

  /// Cached online state. `null` means "not yet known" (constructor's
  /// async seed hasn't resolved). Failure breadcrumbs report this as
  /// `'unknown'` rather than misreporting a default. Once the seed or any
  /// stream change resolves, this becomes a definite `true`/`false`.
  bool? _lastKnownOnline;

  BackendClient(
    this._credentials, {
    ErrorReporterService? errorReporter,
    NetworkMonitorService? networkMonitor,
  }) : _errorReporter = errorReporter {
    // Cache last-known online state from the stream so the failure-path
    // breadcrumb can read it synchronously (no extra round-trip on errors).
    //
    // The connectivity_plus stream is change-only — it does NOT emit the
    // current state on subscription. If the very first request fails before
    // any connectivity change has happened, the cached value would be the
    // default (`true`) regardless of actual state. Seed it once on construct.
    if (networkMonitor != null) {
      // ignore: discarded_futures — fire-and-forget seed; the onError-path
      // breadcrumb is best-effort and tolerates a brief stale value before
      // the seed completes (sub-millisecond on most platforms).
      networkMonitor
          .isOnline()
          .then((online) => _lastKnownOnline = online)
          .catchError((Object _) => false);
      _onlineSub = networkMonitor.onlineStream.listen((online) {
        _lastKnownOnline = online;
      });
    }

    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.backendBaseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(_AuthInterceptor(_credentials, _dio));
    // Sentry interceptor sits AFTER auth (so we never breadcrumb a request
    // auth rejected pre-flight) and BEFORE LogInterceptor (so dev logs
    // reflect what was actually instrumented).
    _dio.interceptors.add(
      _SentryHttpInterceptor(
        reporter: _errorReporter,
        onlineSnapshot: () => _onlineLabel(),
      ),
    );
    _dio.interceptors.add(
      LogInterceptor(
        request: false,
        requestHeader: false,
        requestBody: false,
        responseHeader: false,
        responseBody: false,
        error: true,
        logPrint: (object) => appLogger.debug('[Backend] $object'),
      ),
    );
  }

  /// Cancel the online-state subscription on disposal.
  void dispose() {
    _onlineSub?.cancel();
  }

  /// Test-only access to the underlying Dio's HttpClientAdapter so tests
  /// can swap in a stub adapter and exercise the REAL interceptor stack
  /// (auth + Sentry + log) end-to-end. Production code MUST NOT use this;
  /// the `@visibleForTesting` annotation is enforced at analysis time.
  @visibleForTesting
  set httpClientAdapterForTesting(HttpClientAdapter adapter) {
    _dio.httpClientAdapter = adapter;
  }

  /// Label for `network.online` telemetry: returns `'true'`, `'false'`, or
  /// `'unknown'` (when seeding hasn't completed). Honest reporting beats
  /// confidently-wrong reporting on cold-start failures.
  String _onlineLabel() {
    final v = _lastKnownOnline;
    if (v == null) return 'unknown';
    return v ? 'true' : 'false';
  }

  /// GET request - unwraps response envelope
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    required T Function(dynamic json) fromJson,
  }) async {
    try {
      final response = await _dio.get(
        path,
        queryParameters: queryParameters,
        options: options,
      );
      return _unwrap(response, fromJson);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// POST request - unwraps response envelope
  Future<T> post<T>(
    String path, {
    dynamic data,
    Options? options,
    required T Function(dynamic json) fromJson,
  }) async {
    try {
      final response = await _dio.post(path, data: data, options: options);
      return _unwrap(response, fromJson);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// POST request with no meaningful response data
  Future<void> postVoid(String path, {dynamic data, Options? options}) async {
    try {
      final response = await _dio.post(path, data: data, options: options);
      _unwrapVoid(response);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// DELETE request - unwraps response envelope
  Future<T> delete<T>(
    String path, {
    Options? options,
    required T Function(dynamic json) fromJson,
  }) async {
    try {
      final response = await _dio.delete(path, options: options);
      return _unwrap(response, fromJson);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// DELETE request with no meaningful response data
  Future<void> deleteVoid(String path, {Options? options}) async {
    try {
      final response = await _dio.delete(path, options: options);
      _unwrapVoid(response);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// PATCH request - unwraps response envelope
  Future<T> patch<T>(
    String path, {
    dynamic data,
    Options? options,
    required T Function(dynamic json) fromJson,
  }) async {
    try {
      final response = await _dio.patch(path, data: data, options: options);
      return _unwrap(response, fromJson);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// Raw POST without auth (for registration)
  Future<T> postNoAuth<T>(
    String path, {
    dynamic data,
    Options? options,
    required T Function(dynamic json) fromJson,
  }) async {
    try {
      final requestOptions = (options ?? Options()).copyWith(
        headers: {...?options?.headers, _AuthInterceptor._skipAuthHeader: true},
      );
      final response = await _dio.post(
        path,
        data: data,
        options: requestOptions,
      );
      return _unwrap(response, fromJson);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// Unwrap standard response envelope: { success, data, error }.
  ///
  /// On `success: false`, taps [_reportEnvelopeError] before throwing — this
  /// catches the "HTTP 200 but envelope-level failure" category that Dio's
  /// `onError` interceptor never sees.
  T _unwrap<T>(Response response, T Function(dynamic json) fromJson) {
    final body = response.data as Map<String, dynamic>;
    if (body['success'] == true) {
      return fromJson(body['data']);
    }
    final error = body['error'] as Map<String, dynamic>?;
    _reportEnvelopeError(response, error);
    throw AppException.network(
      message: error?['message'] ?? 'Unknown error',
      statusCode: response.statusCode,
      data: error?['code'],
    );
  }

  /// Void-variant envelope check. Bit-exact with the previous inline behavior
  /// of `postVoid` / `deleteVoid` — uses `'Request failed'` fallback (NOT
  /// `'Unknown error'`) and does NOT set `data`. The only addition is the
  /// `_reportEnvelopeError` tap, so callers see new Sentry events but no
  /// behavioral change in the thrown exception.
  void _unwrapVoid(Response response) {
    final body = response.data as Map<String, dynamic>;
    if (body['success'] == true) return;
    final error = body['error'] as Map<String, dynamic>?;
    _reportEnvelopeError(response, error);
    throw AppException.network(
      message: error?['message'] ?? 'Request failed',
      statusCode: response.statusCode,
    );
  }

  /// Report an envelope-level failure to Sentry. Self-protected via the
  /// `backendInternalRequestFlag` — telemetry-forwarding requests skip
  /// reporting to break the report-on-failure-of-report loop.
  void _reportEnvelopeError(Response response, Map<String, dynamic>? error) {
    if (response.requestOptions.extra[backendInternalRequestFlag] == true) {
      return;
    }
    final reporter = _errorReporter;
    if (reporter == null) return;

    final method = response.requestOptions.method;
    final url = scrubHttpUrl(response.requestOptions.uri);
    final code = error?['code'] as String?;
    final message = error?['message'] as String?;
    final attributes = <String, Object?>{
      'http.method': method,
      'http.url': url,
      'http.status_code': response.statusCode,
      'http.envelope_error_code': code,
      'http.envelope_error_message': message,
      'network.online': _onlineLabel(),
    };

    // Fire-and-forget — telemetry must never block request completion.
    // ignore: discarded_futures
    safeCaptureException(
      reporter,
      AppException.network(
        message: message ?? 'Envelope error',
        statusCode: response.statusCode,
        data: code,
      ),
      scopeConfig: (scope) {
        scope.setTag('op', 'http.envelope_error');
        for (final entry in attributes.entries) {
          final v = entry.value;
          if (v is String && v.length <= 150) {
            scope.setTag(entry.key, v);
          } else {
            // ignore: deprecated_member_use
            scope.setExtra(entry.key, v);
          }
        }
      },
      backendMetadata: {'op': 'http.envelope_error', ...attributes},
    );
  }

  /// Map Dio errors to AppException
  AppException _mapDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const AppException.network(message: 'Connection timed out');
      case DioExceptionType.connectionError:
        return const AppException.network(message: 'Cannot connect to server');
      case DioExceptionType.badResponse:
        final data = e.response?.data;
        if (data is Map<String, dynamic>) {
          // Standard error envelope: { error: { code, message } }.
          final error = data['error'];
          if (error is Map<String, dynamic>) {
            return AppException.network(
              message: error['message'] as String? ?? 'Server error',
              statusCode: e.response?.statusCode,
              data: error['code'],
            );
          }
          // Some endpoints return a non-2xx with a SUCCESS-shaped body, e.g.
          // device-limit: HTTP 403 + { success: true, data: { reason: ... } }.
          // Preserve data.reason so license-verdict classification can see it
          // (otherwise a real device_limit_exceeded would be dropped here and
          // wrongly fall through to offline grace = fail-open over-grant).
          final inner = data['data'];
          if (inner is Map<String, dynamic> && inner['reason'] is String) {
            return AppException.network(
              message: 'Server error (${e.response?.statusCode})',
              statusCode: e.response?.statusCode,
              data: inner['reason'],
            );
          }
        }
        return AppException.network(
          message: 'Server error (${e.response?.statusCode})',
          statusCode: e.response?.statusCode,
        );
      default:
        return AppException.network(message: e.message ?? 'Network error');
    }
  }

  /// Test-only access to [_mapDioError] so the error-envelope mapping (incl. the
  /// success-shaped non-2xx device-limit body) can be unit-tested without a live
  /// server.
  @visibleForTesting
  AppException mapDioErrorForTest(DioException e) => _mapDioError(e);
}

/// Sentry instrumentation for every Dio request through [BackendClient].
///
/// Emits a `category: http` breadcrumb on every response (success and
/// failure). On transport-level failure (Dio `onError`), captures a Sentry
/// event with status code, scrubbed URL, body excerpt, and cached network
/// state. Skips reporting when [backendInternalRequestFlag] is set in
/// `RequestOptions.extra` — used by crash-forwarding requests to break
/// report-on-failure-of-report loops.
///
/// Distinguishes `_AuthInterceptor`'s 401-then-retry flow from real failures
/// via [_retryRequestFlag] in `RequestOptions.extra`. Original 401 → warning
/// breadcrumb, no event. Retry → labeled breadcrumb. Retry failure → event.
class _SentryHttpInterceptor extends Interceptor {
  final ErrorReporterService? reporter;

  /// Snapshot returns the cached `network.online` label
  /// (`'true'` / `'false'` / `'unknown'`) — `'unknown'` covers the brief
  /// cold-start window before the network monitor's seed resolves.
  final String Function() onlineSnapshot;

  _SentryHttpInterceptor({
    required this.reporter,
    required this.onlineSnapshot,
  });

  static const _startTimeKey = '_sentryStartMs';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startTimeKey] = DateTime.now().millisecondsSinceEpoch;
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (response.requestOptions.extra[backendInternalRequestFlag] == true) {
      handler.next(response);
      return;
    }
    final r = reporter;
    if (r == null) {
      handler.next(response);
      return;
    }
    final isRetry = response.requestOptions.extra[_retryRequestFlag] == true;
    final duration = _durationMs(response.requestOptions);
    safeBreadcrumb(
      r,
      isRetry ? 'http.retry_succeeded' : 'http',
      data: <String, dynamic>{
        'method': response.requestOptions.method,
        'url': scrubHttpUrl(response.requestOptions.uri),
        'status': response.statusCode,
        'duration_ms': duration,
        if (isRetry) 'retry': true,
      },
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.requestOptions.extra[backendInternalRequestFlag] == true) {
      handler.next(err);
      return;
    }
    final r = reporter;
    if (r == null) {
      handler.next(err);
      return;
    }
    final isRetry = err.requestOptions.extra[_retryRequestFlag] == true;
    final refreshAttempted =
        err.requestOptions.extra[_AuthInterceptor._authRefreshAttemptedFlag] ==
        true;
    final refreshFailed =
        err.requestOptions.extra[_AuthInterceptor._authRefreshFailedFlag] ==
        true;
    // Suppress capture only when the auth interceptor has explicitly
    // marked this 401 as recoverable AND hasn't yet given up. Non-
    // refreshable 401s (missing token, expired without INVALID_API_KEY
    // code, malformed response) never get the flag and so are captured
    // as normal failures. This is the fix for the "any 401 silently
    // suppressed" bug.
    final isOriginalAuth401 =
        err.response?.statusCode == 401 &&
        !isRetry &&
        refreshAttempted &&
        !refreshFailed;
    final duration = _durationMs(err.requestOptions);
    final scrubbedUrl = scrubHttpUrl(err.requestOptions.uri);

    // Always emit a breadcrumb so the trail is intact even when we don't
    // capture an event (original 401 case).
    final suppressEvent =
        err.requestOptions.extra[suppressBackendErrorReportFlag] == true;
    safeBreadcrumb(
      r,
      isOriginalAuth401
          ? 'http.auth_refresh'
          : (suppressEvent ? 'http.suppressed_error' : 'http.error'),
      data: <String, dynamic>{
        'method': err.requestOptions.method,
        'url': scrubbedUrl,
        'status': err.response?.statusCode,
        'duration_ms': duration,
        if (isRetry) 'retry': true,
        if (refreshFailed) 'auth_refresh_failed': true,
      },
    );

    // Skip event capture for the original 401 — `_AuthInterceptor` is about
    // to refresh credentials and retry. The retry's outcome is what we care
    // about. If THIS request happens to be a retry that itself failed, OR
    // the auth interceptor has signaled refresh failure via the flag, we
    // capture below.
    if (isOriginalAuth401) {
      handler.next(err);
      return;
    }

    if (suppressEvent) {
      handler.next(err);
      return;
    }

    final bodyExcerpt = _extractBodyExcerpt(err.response?.data);
    final attributes = <String, Object?>{
      'http.method': err.requestOptions.method,
      'http.url': scrubbedUrl,
      'http.status_code': err.response?.statusCode,
      'http.error_type': err.type.toString(),
      'http.duration_ms': duration,
      'http.retry': isRetry,
      'network.online': onlineSnapshot(),
      if (bodyExcerpt != null) 'http.response_body_excerpt': bodyExcerpt,
    };

    // ignore: discarded_futures — fire-and-forget telemetry
    safeCaptureException(
      r,
      err,
      stackTrace: err.stackTrace,
      scopeConfig: (scope) {
        scope.setTag('op', 'http.transport_error');
        for (final entry in attributes.entries) {
          final v = entry.value;
          if (v is String && v.length <= 150) {
            scope.setTag(entry.key, v);
          } else {
            // ignore: deprecated_member_use
            scope.setExtra(entry.key, v);
          }
        }
      },
      backendMetadata: {'op': 'http.transport_error', ...attributes},
    );

    handler.next(err);
  }

  int? _durationMs(RequestOptions options) {
    final start = options.extra[_startTimeKey];
    if (start is! int) return null;
    return DateTime.now().millisecondsSinceEpoch - start;
  }

  /// Truncate response body to first 512 bytes after PII scrubbing.
  /// Skipped on success — failure paths only.
  String? _extractBodyExcerpt(dynamic body) {
    if (body == null) return null;
    String raw;
    if (body is String) {
      raw = body;
    } else if (body is Map || body is List) {
      try {
        raw = jsonEncode(body);
      } catch (_) {
        raw = body.toString();
      }
    } else {
      raw = body.toString();
    }
    final scrubbed = scrubString(raw);
    return scrubbed.length > 512 ? scrubbed.substring(0, 512) : scrubbed;
  }
}

/// Auth interceptor that auto-attaches X-API-Key header
/// and auto-recovers from stale API keys (401 INVALID_API_KEY).
///
/// Uses QueuedInterceptor to serialize interceptor execution, and a Completer
/// to coalesce multiple concurrent 401 handlers into ONE re-registration call.
/// All pending requests wait on the same Future and retry with the new key.
class _AuthInterceptor extends QueuedInterceptor {
  static const _skipAuthHeader = 'X-Skip-Auth';
  final SecureCredentialStore _credentials;
  final Dio _dio;

  /// Coalescing: only ONE re-registration runs at a time.
  /// All concurrent 401 handlers await the same Completer's Future.
  Completer<String?>? _refreshCompleter;

  _AuthInterceptor(this._credentials, this._dio);

  /// Marker set when [_AuthInterceptor] is actively attempting a refresh
  /// for THIS request. Without this flag, [_SentryHttpInterceptor] treats
  /// every 401 as a real user-visible failure and captures it. With the
  /// flag (and no failure flag yet), Sentry suppresses the original 401
  /// because the auth interceptor's retry will report success or failure
  /// after the refresh resolves.
  ///
  /// Critical: only the INVALID_API_KEY 401s carry this flag. Other 401s
  /// (missing token, expired token without code, response not a Map) bail
  /// out of `_AuthInterceptor.onError` without marking — those are real
  /// failures and must be captured.
  static const _authRefreshAttemptedFlag = '_authRefreshAttempted';

  /// Marker set when a refresh attempt failed. Combined with
  /// `_authRefreshAttemptedFlag` it tells Sentry "auth tried and gave up"
  /// — capture the original 401 as a real failure.
  static const _authRefreshFailedFlag = '_authRefreshFailed';

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Skip auth if explicitly requested (e.g., registration)
    if (options.headers.containsKey(_skipAuthHeader)) {
      options.headers.remove(_skipAuthHeader);
      handler.next(options);
      return;
    }

    final apiKey = await _credentials.read(PrefKeys.backendApiKey);
    if (apiKey != null && apiKey.isNotEmpty) {
      options.headers['X-API-Key'] = apiKey;
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 401) {
      handler.next(err);
      return;
    }

    // Internal crash-forwarding requests (submitCrash) MUST NOT trigger
    // re-registration. The /devices/register call below would itself go
    // through the Sentry interceptor (no internal flag), creating a side
    // request whose failures could feed back into crash submission. Skip
    // refresh entirely — let the original 401 propagate. This sacrifices
    // automatic recovery for telemetry posts in exchange for guaranteed
    // loop prevention. Crashes that fail submission can be retried on next
    // launch via the rolling crash buffer.
    if (err.requestOptions.extra[backendInternalRequestFlag] == true) {
      handler.next(err);
      return;
    }

    // Check for API-key lifecycle errors. Missing/revoked/expired keys are
    // recoverable the same way as INVALID_API_KEY: re-register and retry once.
    // If the response is malformed or has an unrelated code, bail out WITHOUT
    // marking refresh-attempted so Sentry treats it as a real failure.
    final data = err.response?.data;
    if (data is! Map<String, dynamic>) {
      handler.next(err);
      return;
    }
    final error = data['error'] as Map<String, dynamic>?;
    if (!isRecoverableApiKeyErrorCode(error?['code'] as String?)) {
      handler.next(err);
      return;
    }

    // From here on, this 401 IS recoverable in principle. Mark the request
    // so the Sentry interceptor knows to suppress the original 401 (the
    // refresh's retry will report). If refresh later fails, we additionally
    // set _authRefreshFailedFlag below.
    err.requestOptions.extra[_authRefreshAttemptedFlag] = true;

    try {
      // Coalesce: if re-registration is already in progress, wait for it.
      // All concurrent 401 handlers share the same Future.
      final newApiKey = await _getOrCreateRefreshFuture();

      if (newApiKey == null || newApiKey.isEmpty) {
        appLogger.warning('Re-registration failed, returning original error');
        // Mark the failure so `_SentryHttpInterceptor` upgrades this from
        // "ignore — auth refresh in progress" to "real user-visible
        // failure" and captures an event. Without this flag, refresh
        // failures were silent in Sentry.
        err.requestOptions.extra[_authRefreshFailedFlag] = true;
        handler.next(err);
        return;
      }

      // Retry the original request with new key. Mark _isRetry so the
      // Sentry interceptor labels breadcrumbs and treats failures as
      // user-visible (rather than the original 401 which was a normal
      // auth-refresh trigger).
      final opts = err.requestOptions;
      opts.headers['X-API-Key'] = newApiKey;
      opts.extra[_retryRequestFlag] = true;
      final retryResponse = await _dio.fetch(opts);
      handler.resolve(retryResponse);
    } catch (e) {
      appLogger.warning('Error in auth refresh flow: $e');
      err.requestOptions.extra[_authRefreshFailedFlag] = true;
      handler.next(err);
    }
  }

  /// Get existing refresh Future or create new one.
  /// Multiple concurrent 401 handlers all await the SAME Future.
  Future<String?> _getOrCreateRefreshFuture() {
    if (_refreshCompleter != null && !_refreshCompleter!.isCompleted) {
      appLogger.debug('Re-registration already in progress, waiting...');
      return _refreshCompleter!.future;
    }

    appLogger.info('Stale API key detected, starting re-registration...');
    _refreshCompleter = Completer<String?>();

    _performReRegistration()
        .then((apiKey) {
          _refreshCompleter!.complete(apiKey);
        })
        .catchError((Object e) {
          appLogger.warning('Re-registration error: $e');
          _refreshCompleter!.complete(null);
        });

    return _refreshCompleter!.future;
  }

  /// Perform actual re-registration. Returns new API key or null on failure.
  /// Uses dual-send: new SHA-256 fingerprint + legacy hostname-based fingerprint
  /// so the backend can migrate existing device records.
  Future<String?> _performReRegistration() async {
    try {
      await _credentials.delete(PrefKeys.backendApiKey);
      await _credentials.delete(PrefKeys.deviceId);

      final legacyId = HardwareFingerprintService.generateLegacyFingerprint();
      final strongId = await HardwareFingerprintService.generateFingerprint();

      final data = <String, dynamic>{
        'hardware_id': strongId ?? legacyId,
        'os': _getPlatformOs(),
        'os_version': Platform.operatingSystemVersion,
        'app_version': AppConstants.appVersion,
        'device_name': Platform.localHostname,
        'brand': BrandConfig.current.brand.name,
      };

      if (strongId != null) {
        data['legacy_hardware_id'] = legacyId;
      }

      final regResponse = await _dio.post(
        '/devices/register',
        data: data,
        options: Options(headers: {_skipAuthHeader: true}),
      );

      final body = regResponse.data;
      if (body is! Map<String, dynamic> || body['success'] != true) {
        appLogger.warning(
          'Re-registration response not successful: ${body['error']?['message']}',
        );
        return null;
      }

      final regData = body['data'] as Map<String, dynamic>?;
      final newKey = regData?['api_key'] as String?;
      final newDeviceId = regData?['device_id'] as String?;
      if (newKey == null || newKey.isEmpty || newDeviceId == null) {
        appLogger.warning(
          'Re-registration response missing api_key or device_id',
        );
        return null;
      }

      await _credentials.write(PrefKeys.backendApiKey, newKey);
      await _credentials.write(PrefKeys.deviceId, newDeviceId);
      appLogger.info('Re-registered device successfully ($newDeviceId)');
      return newKey;
    } on DioException catch (e) {
      appLogger.warning(
        'Re-registration DioException: ${e.response?.statusCode} — ${e.message}',
      );
      return null;
    }
  }

  String _getPlatformOs() {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }
}
