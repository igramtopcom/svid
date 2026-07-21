import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/services/secure_credential_store.dart';

/// Local datasource for premium license storage.
///
/// License key stored in secure storage (Keychain/DPAPI).
/// Metadata (non-secret) stays in SharedPreferences.
class PremiumLocalDatasource {
  final SharedPreferences _prefs;
  final SecureCredentialStore _credentials;

  static const _metadataKey = 'premium_license_metadata';
  static const _licenseKeyKey = 'premium_license_key';

  PremiumLocalDatasource(this._prefs, this._credentials);

  /// Read license metadata from SharedPreferences
  Map<String, dynamic>? getMetadata() {
    final raw = _prefs.getString(_metadataKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return json.decode(raw) as Map<String, dynamic>;
    } catch (e) {
      appLogger.warning('Failed to read premium metadata: $e');
      return null;
    }
  }

  /// Save license metadata to SharedPreferences
  Future<void> saveMetadata(Map<String, dynamic> metadata) async {
    await _prefs.setString(_metadataKey, json.encode(metadata));
  }

  /// Read license key from secure storage
  Future<String?> getLicenseKey() async {
    return await _credentials.read(_licenseKeyKey);
  }

  /// Save license key to secure storage
  Future<void> saveLicenseKey(String key) async {
    await _credentials.write(_licenseKeyKey, key);
  }

  /// Delete license key from both stores
  Future<void> deleteLicenseKey() async {
    await _credentials.delete(_licenseKeyKey);
  }

  /// Clear all premium data
  Future<void> clearAll() async {
    await _prefs.remove(_metadataKey);
    await deleteLicenseKey();
  }

  /// Soft-clear premium state: remove metadata only, KEEP the secure-storage
  /// license key.
  ///
  /// Used for non-definitive demote signals (expired / network / grace /
  /// format-corrupt / unknown). Preserving the key lets the user auto-recover
  /// premium when the backend re-confirms the license, instead of permanently
  /// losing it. Full key-wipe ([clearAll]) is reserved for explicit user
  /// Deactivate or a definitive server revoke.
  Future<void> clearMetadataKeepKey() async {
    await _prefs.remove(_metadataKey);
  }
}
