import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show Options;
import 'package:uuid/uuid.dart';

import '../config/brand_config.dart';
import '../constants/app_constants.dart';
import '../errors/app_exception.dart';
import '../logging/app_logger.dart';
import '../network/backend_client.dart';
import '../network/backend_dtos.dart';
import 'hardware_fingerprint_service.dart';
import 'secure_credential_store.dart';

typedef StrongFingerprintProvider = Future<String?> Function();
typedef LegacyFingerprintProvider = String Function();
typedef PlatformOsProvider = String Function();
typedef StringValueProvider = String Function();

/// Handles device registration and API key management for the backend.
class DeviceAuthService {
  final BackendClient _client;
  final SecureCredentialStore _credentials;
  final StrongFingerprintProvider _generateFingerprint;
  final LegacyFingerprintProvider _generateLegacyFingerprint;
  final PlatformOsProvider _platformOsProvider;
  final StringValueProvider _osVersionProvider;
  final StringValueProvider _deviceNameProvider;
  final StringValueProvider _brandNameProvider;
  final StringValueProvider _installIdProvider;

  DeviceAuthService(
    this._client,
    this._credentials, {
    StrongFingerprintProvider? generateFingerprint,
    LegacyFingerprintProvider? generateLegacyFingerprint,
    PlatformOsProvider? platformOsProvider,
    StringValueProvider? osVersionProvider,
    StringValueProvider? deviceNameProvider,
    StringValueProvider? brandNameProvider,
    StringValueProvider? installIdProvider,
  }) : _generateFingerprint =
           generateFingerprint ??
           HardwareFingerprintService.generateFingerprint,
       _generateLegacyFingerprint =
           generateLegacyFingerprint ??
           HardwareFingerprintService.generateLegacyFingerprint,
       _platformOsProvider = platformOsProvider ?? _defaultPlatformOs,
       _osVersionProvider = osVersionProvider ?? _defaultOsVersion,
       _deviceNameProvider = deviceNameProvider ?? _defaultDeviceName,
       _brandNameProvider = brandNameProvider ?? _defaultBrandName,
       _installIdProvider = installIdProvider ?? _defaultInstallId;

  /// Whether this device has been registered with the backend.
  Future<bool> get isRegistered async =>
      await _credentials.containsKey(PrefKeys.backendApiKey);

  /// Get stored API key (null if not registered).
  Future<String?> get apiKey => _credentials.read(PrefKeys.backendApiKey);

  /// Get stored device ID (null if not registered).
  Future<String?> get deviceId => _credentials.read(PrefKeys.deviceId);

  /// Register this device with the backend.
  /// Stores the API key and device ID in secure storage.
  /// Returns true if registration was successful.
  ///
  /// Sends both new (SHA-256) and legacy (hostname-based) hardware IDs
  /// so the backend can migrate existing device records to the new fingerprint.
  Future<bool> register() async {
    try {
      final legacyId = _generateLegacyFingerprint();
      final strongId = await _generateFingerprint();
      final os = _platformOsProvider();
      final osVersion = _osVersionProvider();

      final data = <String, dynamic>{
        'hardware_id': strongId ?? legacyId,
        'os': os,
        'os_version': osVersion,
        'app_version': AppConstants.appVersion,
        'device_name': _deviceNameProvider(),
      };

      // Dual-send: include legacy ID so backend can migrate existing records
      if (strongId != null) {
        data['legacy_hardware_id'] = legacyId;
      }

      // Multi-brand: tell Go backend which brand this device belongs to
      data['brand'] = _brandNameProvider();

      unawaited(
        _trackBootstrapEvent(
          stage: 'register',
          status: 'started',
          metadata: {
            'has_strong_fingerprint': strongId != null,
            'has_legacy_fingerprint': legacyId.isNotEmpty,
          },
        ),
      );

      final response = await _client.postNoAuth<RegisterResponse>(
        '/devices/register',
        data: data,
        fromJson:
            (json) => RegisterResponse.fromJson(json as Map<String, dynamic>),
      );

      await _credentials.write(PrefKeys.backendApiKey, response.apiKey);
      await _credentials.write(PrefKeys.deviceId, response.deviceId);

      appLogger.info(
        'Device registered: ${response.isNew ? "new" : "existing"} (${response.deviceId})',
      );
      unawaited(
        _trackBootstrapEvent(
          stage: 'register',
          status: 'succeeded',
          metadata: {'is_new': response.isNew},
        ),
      );
      return true;
    } catch (e) {
      appLogger.warning('Device registration failed (non-critical): $e');
      unawaited(
        _trackBootstrapEvent(
          stage: 'register',
          status: 'failed',
          errorCode: _bootstrapErrorCode(e),
          errorMessage: AppExceptionX.readableMessage(e),
        ),
      );
      return false;
    }
  }

  /// Send heartbeat to the backend.
  /// Optionally syncs premium [tier] so Go admin dashboard reflects
  /// VidCombo premium status verified via PHP checkkey.php.
  Future<void> heartbeat({String? tier}) async {
    if (!await isRegistered) return;
    try {
      await _client.post<HeartbeatResponse>(
        '/devices/heartbeat',
        data: {
          'app_version': AppConstants.appVersion,
          'brand': _brandNameProvider(),
          if (tier != null) 'tier': tier,
        },
        options: Options(extra: {suppressBackendErrorReportFlag: true}),
        fromJson:
            (json) => HeartbeatResponse.fromJson(json as Map<String, dynamic>),
      );
      appLogger.debug('Heartbeat sent');
    } catch (e) {
      appLogger.debug('Heartbeat failed (non-critical): $e');
    }
  }

  /// Get platform OS name matching backend enum.
  static String _defaultPlatformOs() {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  static String _defaultOsVersion() => Platform.operatingSystemVersion;

  static String _defaultDeviceName() => Platform.localHostname;

  static String _defaultBrandName() => BrandConfig.current.brand.name;

  static String _defaultInstallId() => const Uuid().v4();

  Future<String> _getOrCreateBootstrapInstallId() async {
    final existing = await _credentials.read(PrefKeys.bootstrapInstallId);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _installIdProvider();
    await _credentials.write(PrefKeys.bootstrapInstallId, id);
    return id;
  }

  Future<void> _trackBootstrapEvent({
    required String stage,
    required String status,
    String? errorCode,
    String? errorMessage,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final installId = await _getOrCreateBootstrapInstallId();
      await _client.postNoAuth<void>(
        '/bootstrap/events',
        data: {
          'install_id': installId,
          'brand': _brandNameProvider(),
          'os': _platformOsProvider(),
          'os_version': _osVersionProvider(),
          'app_version': AppConstants.appVersion,
          'stage': stage,
          'status': status,
          if (errorCode != null && errorCode.isNotEmpty)
            'error_code': errorCode,
          if (errorMessage != null && errorMessage.isNotEmpty)
            'error_message': errorMessage,
          if (metadata != null && metadata.isNotEmpty)
            'metadata': jsonEncode(metadata),
        },
        options: Options(extra: const {suppressBackendErrorReportFlag: true}),
        fromJson: (_) {},
      );
    } catch (e) {
      appLogger.debug('Bootstrap telemetry failed (non-critical): $e');
    }
  }

  String _bootstrapErrorCode(Object error) {
    if (error is AppException && error.isNetworkError) return 'network';
    return 'exception';
  }
}
