import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../../config/brand_config.dart';
import '../../constants/app_constants.dart';
import '../../logging/app_logger.dart';
import '../../network/backend_dtos.dart';
import '../error_reporter_service.dart';
import '../hardware_fingerprint_service.dart';
import '../instrumentation.dart';
import '../pii_scrubber.dart';
import '../../../features/premium/data/services/license_verification_service.dart';

/// VidCombo PHP backend adapter.
///
/// Translates VidCombo's PHP API protocol (checkkey.php, version.php)
/// into the same DTOs used by the Svid Go backend, enabling the rest
/// of the app to work identically regardless of backend type.
class VidComboBackendAdapter {
  final String _baseUrl;
  final http.Client _httpClient;
  final ErrorReporterService? _errorReporter;
  String? _deviceId;
  String? _licenseKey;

  /// 32-char legacy PHP validation — INTENTIONALLY permissive (any case), matching
  /// BrandConfig.licenseKeyPattern for VidCombo. checkkey.php is the authoritative
  /// gate; a narrower client regex could lock out a real PHP key (AP-1).
  static final _licenseKeyRegex = RegExp(r'^[0-9A-Za-z]{32}$');

  VidComboBackendAdapter({
    http.Client? httpClient,
    String? deviceId,
    String? baseUrl,
    ErrorReporterService? errorReporter,
  }) : _baseUrl = baseUrl ?? BrandConfig.current.backendBaseUrl,
       _httpClient = httpClient ?? http.Client(),
       _errorReporter = errorReporter,
       _deviceId = deviceId;

  /// Wrap an `http.Client` GET with the same Sentry instrumentation shape as
  /// `_SentryHttpInterceptor` for the Dio backend.
  ///
  /// CRITICAL: VidCombo's URLs carry `device_id` and `license_key` in the
  /// query string (see [checkKey] params at construction). [scrubHttpUrl]
  /// runs BEFORE breadcrumb emission so query parameters never leak into
  /// any captured payload.
  Future<http.Response> _instrumentedGet(
    Uri uri, {
    required Duration timeout,
    required String op,
  }) async {
    final start = DateTime.now().millisecondsSinceEpoch;
    final scrubbedUrl = scrubHttpUrl(uri);
    try {
      final response = await _httpClient.get(uri).timeout(timeout);
      final duration = DateTime.now().millisecondsSinceEpoch - start;
      // Unlike Dio, package:http does NOT throw on non-2xx — it returns
      // the Response with whatever status code. We classify here so a
      // 5xx PHP failure surfaces as `http.error`, not `http`.
      final isError = response.statusCode < 200 || response.statusCode >= 300;
      safeBreadcrumb(
        _errorReporter,
        isError ? 'http.error' : 'http',
        data: <String, dynamic>{
          'method': 'GET',
          'url': scrubbedUrl,
          'status': response.statusCode,
          'duration_ms': duration,
          'op': op,
        },
      );
      return response;
    } catch (e, stack) {
      final duration = DateTime.now().millisecondsSinceEpoch - start;
      safeBreadcrumb(
        _errorReporter,
        'http.error',
        data: <String, dynamic>{
          'method': 'GET',
          'url': scrubbedUrl,
          'duration_ms': duration,
          'op': op,
          'error_type': e.runtimeType.toString(),
        },
      );
      // Transient network conditions are caught + silently retried by the
      // caller (see [checkKey] which classifies TimeoutException /
      // SocketException as 'will retry next launch'). Full Sentry capture
      // for these would flood the project with 6+ events/24h of noise
      // that have a documented recovery path — emit breadcrumb only so
      // the timeline is intact while suppressing the duplicate event.
      // Genuine errors (FormatException from a corrupted PHP response,
      // unexpected exception types, etc.) still capture below.
      final isTransientNetwork = e is TimeoutException || e is SocketException;
      if (!isTransientNetwork) {
        // ignore: discarded_futures — fire-and-forget telemetry
        safeCaptureException(
          _errorReporter,
          e,
          stackTrace: stack,
          scopeConfig: (scope) {
            scope.setTag('op', op);
            scope.setTag('http.method', 'GET');
            scope.setTag('http.url', scrubbedUrl);
            // ignore: deprecated_member_use
            scope.setExtra('http.duration_ms', duration);
          },
          backendMetadata: {
            'op': op,
            'http.method': 'GET',
            'http.url': scrubbedUrl,
            'http.duration_ms': duration,
          },
        );
      }
      rethrow;
    }
  }

  /// Initialize device with VidCombo backend via checkkey.php.
  ///
  /// This single endpoint handles both device registration AND license check.
  /// On first contact, the PHP backend auto-creates a device record + trial license.
  /// On subsequent calls, it returns the existing device's license status.
  ///
  /// Returns the license check response with status, free download count, etc.
  Future<VidComboCheckKeyResponse> checkKey({String? licenseKey}) async {
    // Get raw platform UUID as device_id (matches old VidCombo app format)
    _deviceId ??= await HardwareFingerprintService.getRawPlatformUuid();
    if (_deviceId == null || _deviceId!.isEmpty) {
      throw StateError('Failed to obtain device ID for VidCombo registration');
    }

    final params = <String, String>{
      'device_id': _deviceId!,
      'app_name': BrandConfig.current.backendAppName,
      'os_name': _getOsName(),
      'os_version': Platform.operatingSystemVersion,
      'cpu_arch': _getCpuArch(),
    };

    if (licenseKey != null && licenseKey.isNotEmpty) {
      params['license_key'] = licenseKey;
    } else if (_licenseKey != null) {
      params['license_key'] = _licenseKey!;
    }

    final uri = Uri.parse(
      '$_baseUrl/checkkey.php',
    ).replace(queryParameters: params);

    late final http.Response response;
    try {
      response = await _instrumentedGet(
        uri,
        timeout: const Duration(seconds: 15),
        op: 'vidcombo.checkkey',
      );
    } on TimeoutException {
      appLogger.warning('VidCombo checkkey.php timed out after 15s');
      rethrow;
    } on SocketException catch (e) {
      appLogger.warning('VidCombo checkkey.php network error: $e');
      rethrow;
    }

    if (response.statusCode != 200) {
      final error = 'checkkey.php returned HTTP ${response.statusCode}';
      appLogger.warning('VidCombo $error');
      throw Exception(error);
    }

    late final Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException catch (e) {
      appLogger.warning(
        'VidCombo checkkey.php returned invalid JSON: $e '
        '(body: ${response.body.length > 200 ? response.body.substring(0, 200) : response.body})',
      );
      throw FormatException('checkkey.php returned non-JSON response');
    }

    final result = VidComboCheckKeyResponse.fromJson(json);

    // Cache the license key for subsequent calls (validate hex format)
    if (result.licenseKey != null &&
        _licenseKeyRegex.hasMatch(result.licenseKey!)) {
      _licenseKey = result.licenseKey;
    }

    return result;
  }

  /// Convert checkkey.php response to Svid's LicenseVerificationResponse format.
  LicenseVerificationResponse toLicenseVerification(
    VidComboCheckKeyResponse ck,
  ) {
    final isActive = ck.status == 'active';
    DateTime? expiresAt;
    if (ck.endDate != null && ck.endDate!.isNotEmpty) {
      expiresAt = DateTime.tryParse(ck.endDate!);
    }

    // Plan code mapping — verified against PHP backend `plan_alias` values:
    //   plan1   = $6.99/mo            → monthly      (5-device limit)
    //   plan2   = $29.34 = 6×$4.89    → semiannual   (7-device limit)
    //   plan3   = $41.88 = 12×$3.49   → yearly       (10-device limit, fixed-term)
    //   lifetime = $9.90              → lifetime     (separate branch in PHP)
    //
    // The earlier mapping had plan2→yearly and plan3→lifetime, which silently
    // mislabeled every paid VidCombo user. Yearly users (plan3) saw themselves
    // as "lifetime" in the UI and got no renewal warning — when their PHP-side
    // license expired, verification failed and they lost premium with no
    // explanation. This is the data-loss-equivalent for paying customers.
    String? billingCycle;
    switch (ck.plan) {
      case 'plan1':
        billingCycle = 'monthly';
      case 'plan2':
        billingCycle = 'semiannual';
      case 'plan3':
        billingCycle = 'yearly';
      case 'lifetime':
        billingCycle = 'lifetime';
    }

    return LicenseVerificationResponse(
      isValid: isActive,
      tier: isActive ? 'premium' : null,
      verifiedAt: DateTime.now(),
      reason: isActive ? null : ck.message,
      billingCycle: billingCycle,
      expiresAt: expiresAt,
      isAutoRenew: isActive && ck.plan != 'lifetime' && ck.plan != 'plan3',
    );
  }

  /// Check for updates via version.php.
  ///
  /// VidCombo's version.php returns a download URL (to homepage, not direct file).
  /// Returns no-update on any failure — update checks are non-critical.
  Future<UpdateCheckResponse> checkUpdate() async {
    final noUpdate = UpdateCheckResponse(
      updateAvailable: false,
      currentVersion: AppConstants.appVersion,
      isMandatory: false,
    );

    try {
      final params = <String, String>{
        'current_version': AppConstants.appVersion,
        'ytdlp_version': '0', // Placeholder — version.php requires these
        'ffmpeg_version': '0',
        'os': _getVersionPhpOs(),
        'app_name': BrandConfig.current.backendAppName,
      };

      final uri = Uri.parse(
        '$_baseUrl/version.php',
      ).replace(queryParameters: params);

      final response = await _instrumentedGet(
        uri,
        timeout: const Duration(seconds: 10),
        op: 'vidcombo.version_check',
      );

      if (response.statusCode != 200) {
        appLogger.debug(
          'VidCombo version.php returned HTTP ${response.statusCode}',
        );
        return noUpdate;
      }

      late final Map<String, dynamic> json;
      try {
        json = jsonDecode(response.body) as Map<String, dynamic>;
      } on FormatException {
        appLogger.warning('VidCombo version.php returned invalid JSON');
        return noUpdate;
      }

      final latestVersion = json['latest_version'] as String?;
      if (latestVersion == null || latestVersion.isEmpty) {
        return noUpdate;
      }

      final hasUpdate = _isNewerVersion(latestVersion, AppConstants.appVersion);

      return UpdateCheckResponse(
        updateAvailable: hasUpdate,
        latestVersion: latestVersion,
        currentVersion: AppConstants.appVersion,
        isMandatory: false,
        downloadUrl: json['download_url'] as String?,
        releaseNotes: json['message'] as String?,
      );
    } on TimeoutException {
      appLogger.debug('VidCombo version.php timed out');
      return noUpdate;
    } on SocketException catch (e) {
      appLogger.debug('VidCombo version.php network error: $e');
      return noUpdate;
    } catch (e) {
      appLogger.debug('VidCombo version.php check failed: $e');
      return noUpdate;
    }
  }

  /// Get the cached device_id (raw platform UUID).
  String? get deviceId => _deviceId;

  /// Get the cached license_key from backend.
  String? get licenseKey => _licenseKey;

  // ==================== HELPERS ====================

  static String _getOsName() {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  static String _getCpuArch() {
    // Dart doesn't expose CPU arch directly, use a heuristic
    if (Platform.isMacOS) {
      // Check if running under Rosetta or native ARM
      return Platform.version.contains('arm64') ? 'arm64' : 'x86_64';
    }
    return 'x86_64';
  }

  static String _getVersionPhpOs() {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows64';
    return 'linux';
  }

  static bool _isNewerVersion(String latest, String current) {
    final latestParts =
        latest.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final currentParts =
        current.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final l = i < latestParts.length ? latestParts[i] : 0;
      final c = i < currentParts.length ? currentParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }
}

/// Response from VidCombo's checkkey.php endpoint.
class VidComboCheckKeyResponse {
  final String? licenseKey;
  final String? message;
  final String status; // 'active', 'inactive', 'invalid'
  final String? endDate;
  final int countFree; // Remaining free downloads today
  final String? plan; // 'plan1', 'plan2', 'plan3', 'lifetime'

  VidComboCheckKeyResponse({
    this.licenseKey,
    this.message,
    required this.status,
    this.endDate,
    required this.countFree,
    this.plan,
  });

  factory VidComboCheckKeyResponse.fromJson(Map<String, dynamic> json) {
    // PHP backend uses 'mess' for message and 'lever' for plan
    final rawCountFree = json['count_free'];
    final countFree = (rawCountFree is int ? rawCountFree : 0).clamp(0, 9999);

    return VidComboCheckKeyResponse(
      licenseKey: json['license_key'] as String?,
      message: json['mess'] as String?,
      status: json['status'] as String? ?? 'invalid',
      endDate: json['end_date'] as String?,
      countFree: countFree,
      plan: json['lever'] as String?,
    );
  }

  bool get isPremium => status == 'active';
  bool get isTrial => status == 'invalid' && licenseKey == null;
}
