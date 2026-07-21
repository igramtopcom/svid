import 'package:flutter/foundation.dart';

import '../../../../core/config/brand_config.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/backend_client.dart';
import '../../domain/entities/premium_license.dart';
import '../../domain/entities/premium_tier.dart';
import '../../domain/services/premium_license_service.dart';

/// Response from the backend license verification endpoint.
class LicenseVerificationResponse {
  final bool isValid;
  final String? tier;
  final DateTime verifiedAt;
  final String? reason; // e.g., 'revoked', 'expired', 'device_limit_exceeded'
  final int? deviceCount;
  final int? maxDevices;
  final String? billingCycle; // 'monthly' | 'yearly'
  final DateTime? expiresAt;
  final bool? isAutoRenew;

  LicenseVerificationResponse({
    required this.isValid,
    this.tier,
    required this.verifiedAt,
    this.reason,
    this.deviceCount,
    this.maxDevices,
    this.billingCycle,
    this.expiresAt,
    this.isAutoRenew,
  });

  factory LicenseVerificationResponse.fromJson(Map<String, dynamic> json) {
    return LicenseVerificationResponse(
      isValid: json['is_valid'] as bool? ?? false,
      tier: json['tier'] as String?,
      verifiedAt:
          json['verified_at'] != null
              ? DateTime.parse(json['verified_at'] as String)
              : DateTime.now(),
      reason: json['reason'] as String?,
      deviceCount: json['device_count'] as int?,
      maxDevices: json['max_devices'] as int?,
      billingCycle: json['billing_cycle'] as String?,
      expiresAt:
          json['expires_at'] != null
              ? DateTime.tryParse(json['expires_at'] as String)
              : null,
      isAutoRenew: json['is_auto_renew'] as bool?,
    );
  }
}

/// Result of a license verification attempt.
class VerificationResult {
  final bool verified;
  final bool shouldDeactivate;
  final String? reason;
  final int? deviceCount;
  final int? maxDevices;

  /// Whether [shouldDeactivate] is backed by a DEFINITIVE server revoke.
  ///
  /// `true` only for a server-confirmed revoke (reason=='revoked' or tier
  /// resolved to free) — the only signals that justify a full key-wipe.
  /// `false` for every uncertain signal (expired / network / grace /
  /// format-corrupt / unknown): the demote should preserve the stored key so
  /// the user auto-recovers when the backend re-confirms. See INVARIANT #1.
  final bool definitive;

  const VerificationResult({
    required this.verified,
    this.shouldDeactivate = false,
    this.reason,
    this.deviceCount,
    this.maxDevices,
    this.definitive = false,
  });

  static const success = VerificationResult(verified: true);

  static const offlineGrace = VerificationResult(
    verified: true,
    reason: 'offline_grace',
  );

  // Offline grace expired (offline > 30d): uncertain, NOT a server revoke —
  // keep the key so re-connecting auto-recovers premium.
  static const offlineExpired = VerificationResult(
    verified: false,
    shouldDeactivate: true,
    reason: 'grace_period_expired',
    definitive: false,
  );

  /// True when the backend gave a DEFINITIVE revoke for an is_valid=false
  /// response: explicit revoke reason, OR tier resolved to free.
  ///
  /// The 0-grace post-expiry backend bug sends is_valid=false with NO reason
  /// and tier=='premium' → NOT definitive → key preserved.
  static bool isDefinitiveServerRevoke(LicenseVerificationResponse response) {
    if (response.reason == 'revoked') return true;
    final tier = response.tier;
    if (tier != null && tier == PremiumTier.free.name) return true;
    return false;
  }
}

/// Service that handles periodic license verification with the backend.
///
/// Checks every 7 days. If the server is unreachable, a 30-day grace
/// period allows continued premium use. After grace expires, license
/// reverts to free tier.
class LicenseVerificationService {
  final BackendClient _client;
  final PremiumLicenseService _licenseService;

  /// Grace period: 30 days of offline use after last successful verification.
  static const gracePeriodDays = 30;

  /// Verification interval: check every 7 days.
  static const verificationIntervalDays = 7;

  LicenseVerificationService(this._client, this._licenseService);

  /// Verify the current license with the backend.
  ///
  /// Returns a [VerificationResult] indicating whether the license is valid.
  /// Handles network failures gracefully with offline grace period.
  Future<VerificationResult> verify({DateTime? now}) async {
    final license = await _licenseService.getLicense();

    // Free users don't need verification
    if (license.isFree || license.licenseKey == null) {
      return VerificationResult.success;
    }

    // Key format guard: if stored key doesn't match the expected brand format
    // (SSVID-XXXX for SSvid, 32-char-alphanumeric/VIDCOMBO-XXXX for VidCombo), it's corrupted
    // — clear immediately instead of entering grace period.
    if (!PremiumLicenseService.isValidLicenseKey(license.licenseKey!)) {
      appLogger.warning(
        'Stored license key has invalid format — clearing immediately',
      );
      return const VerificationResult(
        verified: false,
        shouldDeactivate: true,
        reason: 'invalid_key_format',
      );
    }

    // Local expiry is a trigger-to-check, NOT a demote-decision. The backend
    // is the renewal authority: it returns the renewed expiresAt + is_valid.
    // Never pre-server demote on local expiry — that strands a paid user whose
    // subscription was renewed server-side but whose local metadata still shows
    // the old expiresAt. An OFFLINE locally-expired user must still reach the
    // 30-day offline grace (the server POST below throws → catch → grace),
    // which the old pre-server demote blocked. Only a SERVER-confirmed
    // expired/revoke (else-branch below) or offline-grace-expired demotes.
    final expiredLocally = license.isExpired;
    if (expiredLocally) {
      appLogger.info(
        'Subscription expired locally — asking server before any demote',
      );
    }

    // Check if verification is needed (7-day interval). A locally-expired
    // license MUST reach the server regardless of the interval, otherwise a
    // just-renewed paid user stays stuck on stale expiry until the next 7-day
    // window.
    if (!expiredLocally && !license.needsVerification(now: now)) {
      appLogger.debug('License verification not needed yet');
      return VerificationResult.success;
    }

    // PHP backends (VidCombo) with PHP-created licenses don't have
    // /premium/licenses/verify — verification happens via checkkey.php
    // at startup instead. But Go-created licenses (from in-app Stripe)
    // use VIDCOMBO-XXXX or legacy SSVID-XXXX format and MUST be verified
    // via Go backend.
    if (BrandConfig.current.backendType == BackendType.php) {
      final key = license.licenseKey;
      final isGoLicense =
          key != null && PremiumLicenseService.isGoBackendLicenseKey(key);
      if (!isGoLicense) {
        appLogger.debug(
          'Skipping periodic license verification (PHP-created key)',
        );
        await _licenseService.updateLicenseMetadata(now: now);
        return VerificationResult.success;
      }
      // Go-created VidCombo license — fall through to verify with Go backend.
      appLogger.debug(
        'Go-created VidCombo license — verifying with Go backend',
      );
    }

    // Try to verify with backend
    try {
      appLogger.debug(
        'Verifying license ${_maskKeyForLog(license.licenseKey!)}',
      );
      final response = await _client.post<LicenseVerificationResponse>(
        '/premium/licenses/verify',
        data: {'key': license.licenseKey!},
        fromJson:
            (json) => LicenseVerificationResponse.fromJson(
              json as Map<String, dynamic>,
            ),
      );

      if (response.isValid) {
        // Server confirms license is valid — sync metadata + update lastVerified
        final billingCycle =
            response.billingCycle != null
                ? BillingCycle.fromString(response.billingCycle!)
                : null;
        await _licenseService.updateLicenseMetadata(
          billingCycle: billingCycle,
          expiresAt: response.expiresAt,
          isAutoRenew: response.isAutoRenew,
          now: now,
        );
        appLogger.info(
          'License verified successfully '
          '(cycle: ${billingCycle?.name ?? "unknown"}, '
          'expires: ${response.expiresAt?.toIso8601String() ?? "none"})',
        );
        return VerificationResult.success;
      } else {
        // Server says license is invalid — demote. Only a DEFINITIVE revoke
        // (reason=='revoked' or tier resolved free) justifies a full key-wipe;
        // an is_valid=false with no reason (e.g. backend 0-grace post-expiry
        // contradiction) is uncertain → keep the key so renewal auto-recovers.
        final definitive = VerificationResult.isDefinitiveServerRevoke(
          response,
        );
        appLogger.warning(
          'License invalidated by server: ${response.reason} '
          '(definitive: $definitive)',
        );
        return VerificationResult(
          verified: false,
          shouldDeactivate: true,
          reason: response.reason ?? 'invalid',
          deviceCount: response.deviceCount,
          maxDevices: response.maxDevices,
          definitive: definitive,
        );
      }
    } catch (e) {
      // Dio throws on every non-2xx. A 4xx is a SERVER VERDICT (404 invalid
      // key / 403 device_limit), NOT a connectivity failure — routing it into
      // offline grace would fail-OPEN (keep premium on a server rejection).
      // Only a transport failure with NO statusCode (connectionError /
      // timeout) is genuinely offline and earns the 30-day grace.
      final serverVerdict = serverVerdictFor4xx(e);
      if (serverVerdict != null) {
        appLogger.warning(
          'License rejected by server (4xx): reason=${serverVerdict.reason} '
          '(definitive: ${serverVerdict.definitive})',
        );
        return serverVerdict;
      }

      // No statusCode → genuine connectivity failure — check grace period.
      appLogger.debug('License verification failed (network): $e');
      return _handleOfflineVerification(license, now: now);
    }
  }

  /// License-verdict error codes (the only 4xx codes that justify an
  /// entitlement demote). Matched case-insensitively against the server's
  /// `error.code`. Auth-lifecycle (UNAUTHORIZED / *_API_KEY), device-auth
  /// (DEVICE_INACTIVE), validation (INVALID_DEVICE_ID) and rate-limit codes are
  /// deliberately ABSENT — those are not entitlement verdicts and must never
  /// demote a paying user. `revoked`/`license_revoked` are the only definitive
  /// (full key-wipe) verdicts; the rest are soft (key preserved).
  static const _licenseVerdictCodes = {
    'revoked',
    'license_revoked',
    'expired',
    'license_expired',
    'device_limit_exceeded',
    'invalid_license_key',
  };

  /// Classify a verify() failure: a 4xx [AppException.network] is a SERVER
  /// verdict ONLY when its error code is a known license-status code (see
  /// [_licenseVerdictCodes]). Auth/validation/rate-limit 4xx and any
  /// unrecognized code return `null` (default-deny demote) so they fall through
  /// to the offline grace path — favoring a paying user over a spurious demote.
  /// A true revoke also arrives as a 200 is_valid=false reason=='revoked',
  /// handled by the main verify flow.
  ///
  /// Returns `null` for connectionError/timeout (no statusCode) too.
  @visibleForTesting
  VerificationResult? serverVerdictFor4xx(Object e) {
    if (e is! AppException) return null;
    final status = e.maybeWhen(
      network: (message, statusCode, data) => statusCode,
      orElse: () => null,
    );
    if (status == null || status < 400 || status >= 500) return null;

    // The server's error code rides in AppException.network.data (set by
    // BackendClient._mapDioError from the response envelope's error.code).
    final reason = e.maybeWhen(
      network: (message, statusCode, data) => data is String ? data : null,
      orElse: () => null,
    );
    final code = reason?.toLowerCase();
    if (code == null || !_licenseVerdictCodes.contains(code)) return null;

    // Demote-safety: full key-wipe only on a definitive revoke. Every other
    // recognized verdict (device_limit, invalid, expired) is a SOFT demote that
    // keeps the stored key so the user auto-recovers when the backend re-confirms.
    final definitive = code == 'revoked' || code == 'license_revoked';
    return VerificationResult(
      verified: false,
      shouldDeactivate: true,
      reason: reason,
      definitive: definitive,
    );
  }

  /// Verify a license key with the backend (for activation from deep link).
  ///
  /// Unlike [verify], this always calls the server (no caching/interval).
  Future<LicenseVerificationResponse> verifyKey(String licenseKey) async {
    final isGoLicense = PremiumLicenseService.isGoBackendLicenseKey(licenseKey);
    if (BrandConfig.current.backendType != BackendType.go && !isGoLicense) {
      throw UnsupportedError(
        'License key verification requires Go backend '
        '(current: ${BrandConfig.current.backendType.name})',
      );
    }
    return _client.post<LicenseVerificationResponse>(
      '/premium/licenses/verify',
      data: {'key': licenseKey},
      fromJson:
          (json) => LicenseVerificationResponse.fromJson(
            json as Map<String, dynamic>,
          ),
    );
  }

  /// Handle verification when the server is unreachable.
  VerificationResult _handleOfflineVerification(
    PremiumLicense license, {
    DateTime? now,
  }) {
    if (license.isWithinGracePeriod(now: now)) {
      final current = now ?? DateTime.now();
      final daysRemaining =
          gracePeriodDays - current.difference(license.lastVerified!).inDays;
      appLogger.info(
        'Offline grace period active: $daysRemaining days remaining',
      );
      return VerificationResult.offlineGrace;
    } else {
      appLogger.warning(
        'Offline grace period expired — reverting to free tier',
      );
      return VerificationResult.offlineExpired;
    }
  }

  /// Mask license key for logging (show first and last 4 chars).
  String _maskKeyForLog(String key) {
    if (key.length <= 8) return '***';
    return '${key.substring(0, 5)}...${key.substring(key.length - 4)}';
  }
}
