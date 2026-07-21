import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../logging/app_logger.dart';
import 'error_reporter_service.dart';

/// Secure credential store with automatic migration from SharedPreferences.
///
/// Secrets (API key, device ID, license key) are stored in platform-secure
/// storage when available:
/// - macOS: Keychain (kSecClassGenericPassword)
/// - Windows: DPAPI-encrypted file in AppData
/// - Linux: libsecret
///
/// If the platform's secure storage is not available (unsigned / ad-hoc
/// debug builds on macOS return errSecMissingEntitlement (-34018), broken
/// DPAPI on Windows, missing libsecret on Linux) this class transparently
/// falls back to SharedPreferences so the app stays usable. Availability is
/// probed at most once per 24h; we never spam the log with per-key failures
/// when the infrastructure itself is absent.
class SecureCredentialStore {
  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;
  final ErrorReporterService? _errorReporter;

  static const _migrationDoneKey = 'secure_storage_migrated';
  static const _unavailableUntilKey = 'secure_storage_unavailable_until';
  static const _probeKey = '_ssvid_secure_probe';
  static const _probeValue = 'ok';

  /// How long to trust a failed probe before re-trying. Keeps debug /
  /// unsigned builds from probing every launch, but lets a signed build
  /// that follows an unsigned run recover within a day.
  static const Duration _unavailableTtl = Duration(hours: 24);

  // Keys that should be migrated to secure storage
  static const _secretKeys = [
    'backend_api_key',
    'device_id',
    'premium_license_key',
  ];

  /// Cached probe result for this process — avoid re-probing per call.
  bool? _secureAvailable;

  SecureCredentialStore(this._prefs, {ErrorReporterService? errorReporter})
      : _secure = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
          mOptions: MacOsOptions(
            accessibility: KeychainAccessibility.unlocked_this_device,
          ),
        ),
        _errorReporter = errorReporter;

  /// Run once on app startup. Migrates secrets from SharedPreferences
  /// to secure storage if available; otherwise silently defers.
  Future<void> migrateIfNeeded() async {
    if (_prefs.getBool(_migrationDoneKey) == true) return;

    if (!await _isSecureAvailable()) {
      // Infrastructure unavailable — SharedPreferences fallback is already
      // effective. Do not pollute the log with per-key WARNs.
      return;
    }

    appLogger.info('Migrating credentials to secure storage...');
    var allMigrated = true;

    for (final key in _secretKeys) {
      final value = _prefs.getString(key);
      if (value == null || value.isEmpty) continue;

      try {
        await _secure.write(key: key, value: value);
        await _prefs.remove(key);
        appLogger.debug('Migrated "$key" to secure storage');
      } catch (e) {
        // Probe said available but this specific write still failed —
        // genuinely transient. Keep the value in prefs, retry next launch.
        appLogger.warning('Failed to migrate "$key" to secure storage: $e');
        allMigrated = false;
      }
    }

    if (allMigrated) {
      await _prefs.setBool(_migrationDoneKey, true);
      appLogger.info('Credential migration complete');
    } else {
      appLogger.warning('Partial migration — will retry next launch');
    }
  }

  /// Probe secure storage to determine if it's usable in this environment.
  ///
  /// Caches the result for this process and persists a TTL so repeated
  /// launches on an unavailable environment don't re-probe every time, but
  /// still recover within 24h if the environment changes (e.g. switching
  /// from an unsigned debug build to a signed release build).
  Future<bool> _isSecureAvailable() async {
    if (_secureAvailable != null) return _secureAvailable!;

    // If we marked it unavailable recently, honour the TTL.
    final unavailableUntilMs = _prefs.getInt(_unavailableUntilKey);
    if (unavailableUntilMs != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now < unavailableUntilMs) {
        _secureAvailable = false;
        return false;
      }
      // TTL expired — clear and re-probe.
      await _prefs.remove(_unavailableUntilKey);
    }

    try {
      await _secure.write(key: _probeKey, value: _probeValue);
      final readBack = await _secure.read(key: _probeKey);
      await _secure.delete(key: _probeKey);
      _secureAvailable = readBack == _probeValue;
    } catch (e) {
      // Expected on ad-hoc-signed debug macOS (errSecMissingEntitlement
      // / -34018), broken DPAPI on Windows, missing libsecret on Linux.
      // Not a bug — log once at INFO and use the fallback.
      appLogger.info(
        'Secure storage unavailable — using SharedPreferences fallback. '
        'Reason: $e',
      );
      _secureAvailable = false;
    }

    if (_secureAvailable == false) {
      await _prefs.setInt(
        _unavailableUntilKey,
        DateTime.now().add(_unavailableTtl).millisecondsSinceEpoch,
      );
      safeBreadcrumb(
        _errorReporter,
        'secure_credential_fallback',
        data: {'ttl_hours': _unavailableTtl.inHours},
      );
    }

    return _secureAvailable!;
  }

  /// Read a secret. Prefers secure storage when available; transparently
  /// falls back to SharedPreferences.
  Future<String?> read(String key) async {
    if (await _isSecureAvailable()) {
      try {
        final secure = await _secure.read(key: key);
        if (secure != null && secure.isNotEmpty) return secure;
      } catch (e) {
        appLogger.debug('Secure storage read failed for "$key": $e');
      }
    }
    // Fallback: pre-migration, or secure storage unavailable.
    return _prefs.getString(key);
  }

  /// Write a secret. Prefers secure storage; silently falls back to
  /// SharedPreferences when unavailable.
  Future<void> write(String key, String value) async {
    if (await _isSecureAvailable()) {
      try {
        await _secure.write(key: key, value: value);
        if (_prefs.containsKey(key)) {
          await _prefs.remove(key);
        }
        return;
      } catch (e) {
        appLogger.warning('Secure storage write failed for "$key": $e');
      }
    }
    await _prefs.setString(key, value);
  }

  /// Delete a secret from both stores.
  Future<void> delete(String key) async {
    if (await _isSecureAvailable()) {
      try {
        await _secure.delete(key: key);
      } catch (e) {
        appLogger.debug('Secure storage delete failed for "$key": $e');
      }
    }
    await _prefs.remove(key);
  }

  /// Check if a key exists in either store.
  Future<bool> containsKey(String key) async {
    if (await _isSecureAvailable()) {
      try {
        final secure = await _secure.read(key: key);
        if (secure != null && secure.isNotEmpty) return true;
      } catch (_) {}
    }
    return _prefs.containsKey(key);
  }
}
