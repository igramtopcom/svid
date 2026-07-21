import '../../../../core/config/brand_config.dart';
import '../../../../core/errors/app_exception.dart';
import '../../data/datasources/premium_local_datasource.dart';
import '../entities/premium_feature.dart';
import '../entities/premium_license.dart';
import '../entities/premium_tier.dart';

/// Service for managing premium license state.
///
/// Handles activation, deactivation, feature checks, and persistence.
/// License key stored in Keychain via [PremiumLocalDatasource].
class PremiumLicenseService {
  final PremiumLocalDatasource _datasource;

  PremiumLicenseService(this._datasource);

  /// Load current license from storage
  Future<PremiumLicense> getLicense() async {
    final metadata = _datasource.getMetadata();
    if (metadata == null) return PremiumLicense.free;

    final licenseKey = await _datasource.getLicenseKey();
    return PremiumLicense.fromJson(metadata).copyWith(licenseKey: licenseKey);
  }

  /// Activate a new subscription license
  Future<PremiumLicense> activateLicense(
    String key, {
    String? paymentMethod,
    String? transactionId,
    BillingCycle? billingCycle,
    DateTime? expiresAt,
    bool isAutoRenew = true,
    DateTime? now,
  }) async {
    if (!isValidLicenseKey(key)) {
      throw const FormatException('Invalid license key format');
    }

    final current = now ?? DateTime.now();
    final license = PremiumLicense(
      tier: PremiumTier.premium,
      licenseKey: key,
      purchaseDate: current,
      lastVerified: current,
      paymentMethod: paymentMethod,
      transactionId: transactionId,
      billingCycle: billingCycle,
      expiresAt: expiresAt,
      isAutoRenew: isAutoRenew,
    );

    try {
      await _datasource.saveLicenseKey(key);
    } catch (e) {
      throw AppException.storage(
        message: 'Failed to save license key to Keychain: ${e.toString()}',
      );
    }

    try {
      await _datasource.saveMetadata(license.toJson());
    } catch (e) {
      throw AppException.storage(
        message: 'Failed to save license metadata: ${e.toString()}',
      );
    }

    return license;
  }

  /// Activate premium from a backend response that already verified access.
  ///
  /// Some legacy VidCombo PHP `checkkey.php` responses are device-bound and
  /// can report `status=active` without returning a license key. In that case
  /// we still need to persist premium metadata so local gates do not treat a
  /// verified paying user as free.
  Future<PremiumLicense> activateVerifiedPremium({
    String? key,
    String? paymentMethod,
    String? transactionId,
    BillingCycle? billingCycle,
    DateTime? expiresAt,
    bool isAutoRenew = true,
    DateTime? now,
  }) async {
    if (key != null && key.isNotEmpty && !isValidLicenseKey(key)) {
      throw const FormatException('Invalid license key format');
    }

    final current = now ?? DateTime.now();
    final license = PremiumLicense(
      tier: PremiumTier.premium,
      licenseKey: key,
      purchaseDate: current,
      lastVerified: current,
      paymentMethod: paymentMethod,
      transactionId: transactionId,
      billingCycle: billingCycle,
      expiresAt: expiresAt,
      isAutoRenew: isAutoRenew,
    );

    if (key != null && key.isNotEmpty) {
      try {
        await _datasource.saveLicenseKey(key);
      } catch (e) {
        throw AppException.storage(
          message: 'Failed to save license key to Keychain: ${e.toString()}',
        );
      }
    }

    try {
      await _datasource.saveMetadata(license.toJson());
    } catch (e) {
      throw AppException.storage(
        message: 'Failed to save license metadata: ${e.toString()}',
      );
    }

    return license;
  }

  /// Cancel subscription (marks as cancelled, still active until expiry)
  Future<PremiumLicense> cancelSubscription({DateTime? now}) async {
    final license = await getLicense();
    if (license.isFree) return license;

    final updated = license.copyWith(
      cancelledAt: now ?? DateTime.now(),
      isAutoRenew: false,
    );
    await _datasource.saveMetadata(updated.toJson());
    return updated;
  }

  /// Deactivate current license (revert to free)
  ///
  /// Full wipe: removes metadata AND the secure-storage key. Reserved for
  /// explicit user Deactivate or a DEFINITIVE server revoke. For uncertain
  /// signals use [softDeactivateLicense] instead.
  Future<PremiumLicense> deactivateLicense() async {
    await _datasource.clearAll();
    return PremiumLicense.free;
  }

  /// Soft-deactivate current license (revert to free, KEEP the stored key).
  ///
  /// For non-definitive demote signals (expired / network / grace /
  /// format-corrupt / unknown): clears premium metadata so local gates treat
  /// the user as free, but preserves the secure-storage license key so the
  /// user auto-recovers premium when the backend re-confirms.
  Future<PremiumLicense> softDeactivateLicense() async {
    await _datasource.clearMetadataKeepKey();
    return PremiumLicense.free;
  }

  /// Whether a license key is still present in secure storage, independent of
  /// premium metadata. A soft demote ([softDeactivateLicense] ->
  /// clearMetadataKeepKey) leaves the key; a full wipe ([deactivateLicense] ->
  /// clearAll, i.e. explicit user Deactivate or a definitive revoke) deletes it.
  /// Startup self-heal uses this to recover ONLY an involuntary soft demote and
  /// never re-promote after a deliberate teardown.
  Future<bool> hasStoredKey() async {
    final key = await _datasource.getLicenseKey();
    return key != null && key.isNotEmpty;
  }

  /// Update last verification timestamp
  Future<PremiumLicense> updateVerification({DateTime? now}) async {
    final license = await getLicense();
    if (license.isFree) return license;

    final updated = license.copyWith(lastVerified: now ?? DateTime.now());
    await _datasource.saveMetadata(updated.toJson());
    return updated;
  }

  /// Update license metadata from backend verification response.
  ///
  /// Called after successful verify() to sync billingCycle, expiresAt,
  /// isAutoRenew from the backend — these are not available at activation
  /// time (only the key is known).
  Future<PremiumLicense> updateLicenseMetadata({
    BillingCycle? billingCycle,
    DateTime? expiresAt,
    bool? isAutoRenew,
    DateTime? now,
  }) async {
    final license = await getLicense();
    if (license.isFree) return license;

    final updated = license.copyWith(
      billingCycle: billingCycle ?? license.billingCycle,
      expiresAt: expiresAt ?? license.expiresAt,
      isAutoRenew: isAutoRenew ?? license.isAutoRenew,
      lastVerified: now ?? DateTime.now(),
    );
    await _datasource.saveMetadata(updated.toJson());
    return updated;
  }

  /// Check if a specific premium feature is available.
  ///
  /// Returns true if the subscription is active, or if an auto-renewing
  /// subscription expired within the last [gracePeriodAfterExpiryDays] days
  /// (payment retry window).
  ///
  /// [now] is injectable for testing; defaults to [DateTime.now()].
  bool isFeatureAvailable(
    PremiumFeature feature,
    PremiumLicense license, {
    DateTime? now,
  }) {
    if (license.isFree) return false;
    if (!license.isPremium) return false;

    final current = now ?? DateTime.now();

    if (license.expiresAt == null) {
      if (license.billingCycle?.isLifetime ?? false) return true;
      if (BrandConfig.current.brand == Brand.vidcombo) {
        final trustedSince = license.lastVerified ?? license.purchaseDate;
        if (trustedSince == null) return false;
        return current.difference(trustedSince).inDays <
            vidComboNullExpiryTrustDays;
      }
      return true;
    }

    // Active: has not expired yet.
    if (!current.isAfter(license.expiresAt!)) {
      return true;
    }

    // Fixed-term and one-time rails have no payment-retry grace. Their server
    // expiry is the entitlement boundary.
    if (!license.isAutoRenew) return false;

    // Expired auto-renewal — allow the payment failure retry window.
    final daysSinceExpiry = current.difference(license.expiresAt!).inDays;
    return daysSinceExpiry <= gracePeriodAfterExpiryDays;
  }

  /// Days of access granted after subscription expiry (payment retry window).
  static const gracePeriodAfterExpiryDays = 7;

  /// Max local trust for VidCombo premium records that arrive without an
  /// explicit expiry. They must be refreshed by backend confirmation instead
  /// of granting perpetual offline access.
  static const vidComboNullExpiryTrustDays = 30;

  /// Validate license key format (brand-specific pattern)
  static bool isValidLicenseKey(String key) {
    return BrandConfig.current.isValidLicenseKey(key);
  }

  /// Go-backend license key formats, independent of the current brand backend.
  static bool isGoBackendLicenseKey(String key) {
    if (key.startsWith('SSVID-') && key.length == 45) return true;
    if (key.startsWith('VIDCOMBO-') && key.length == 48) return true;
    return false;
  }
}
