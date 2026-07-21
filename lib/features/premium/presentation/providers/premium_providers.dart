import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/providers/backend_providers.dart';
import '../../../../core/services/startup_service.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../data/datasources/premium_local_datasource.dart';
import '../../data/services/license_verification_service.dart';
import '../../domain/entities/premium_feature.dart';
import '../../domain/entities/premium_limits.dart';
import '../../domain/entities/premium_license.dart';
import '../../domain/services/download_quota_reserver.dart';
import '../../domain/services/download_quota_tracker.dart';
import '../../domain/services/premium_license_service.dart';

/// Premium local datasource provider
final premiumLocalDatasourceProvider = Provider<PremiumLocalDatasource>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final credentials = ref.watch(secureCredentialStoreProvider);
  return PremiumLocalDatasource(prefs, credentials);
});

/// Premium license service provider
final premiumLicenseServiceProvider = Provider<PremiumLicenseService>((ref) {
  final datasource = ref.watch(premiumLocalDatasourceProvider);
  return PremiumLicenseService(datasource);
});

/// Premium license state provider
final premiumLicenseProvider =
    StateNotifierProvider<PremiumNotifier, PremiumLicense>((ref) {
      final service = ref.watch(premiumLicenseServiceProvider);
      return PremiumNotifier(
        service,
        // Clear the VidCombo user-deactivate tombstone on any explicit
        // re-activation (manual paste, restore-by-email, payment, deep-link
        // — all paths converge here now). Brand-guarded inside the helper.
        onActivationSuccess: () async {
          final prefs = ref.read(sharedPreferencesProvider);
          await StartupService.clearVidComboDeactivateTombstone(prefs);
        },
      );
    });

/// Derived: does the user currently have premium feature access?
final isPremiumProvider = Provider<bool>((ref) {
  final license = ref.watch(premiumLicenseProvider);
  final service = ref.read(premiumLicenseServiceProvider);
  return service.isFeatureAvailable(PremiumFeature.unlimitedDownloads, license);
});

/// True after local premium state is safe to use for quota decisions.
///
/// Defaults to true for normal/test containers. The app sets this to false
/// only for VidCombo launches where no local premium metadata exists yet and
/// `checkkey.php` still needs to recover legacy device-bound premium state.
final premiumBootstrapReadyProvider = StateProvider<bool>((ref) => true);

/// Derived: is specific feature available?
final premiumFeatureProvider = Provider.family<bool, PremiumFeature>((
  ref,
  feature,
) {
  final license = ref.watch(premiumLicenseProvider);
  final service = ref.read(premiumLicenseServiceProvider);
  return service.isFeatureAvailable(feature, license);
});

/// Download quota tracker for weekly free-tier limits.
final downloadQuotaTrackerProvider = Provider<DownloadQuotaTracker>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return DownloadQuotaTracker(prefs);
});

/// Reactive quota state for UI + gated download entry points.
///
/// State is the number of free-tier downloads consumed this week. The underlying
/// tracker remains the persistence authority; this notifier emits after
/// mutations so quota UI is not dependent on unrelated widget rebuilds.
final downloadQuotaNotifierProvider =
    StateNotifierProvider<DownloadQuotaNotifier, int>((ref) {
      final tracker = ref.watch(downloadQuotaTrackerProvider);
      return DownloadQuotaNotifier(tracker);
    });

class DownloadQuotaNotifier extends StateNotifier<int>
    implements DownloadQuotaReserver {
  final DownloadQuotaTracker _tracker;

  DownloadQuotaNotifier(this._tracker) : super(_tracker.currentPeriodCount());

  @override
  int currentPeriodCount() {
    final count = _tracker.currentPeriodCount();
    state = count;
    return count;
  }

  @override
  int remainingThisWeek({required bool isPremium}) {
    if (isPremium) return -1;
    final count = currentPeriodCount();
    return (PremiumLimits.freeWeeklyDownloads - count)
        .clamp(0, PremiumLimits.freeWeeklyDownloads)
        .toInt();
  }

  @override
  bool tryConsume({required bool isPremium, int count = 1}) {
    final before = _tracker.currentPeriodCount();
    appLogger.info(
      '📊 [Quota] tryConsume entry: isPremium=$isPremium, '
      'count=$count, before=$before/${PremiumLimits.freeWeeklyDownloads}',
    );
    final consumed = _tracker.tryConsume(isPremium: isPremium, count: count);
    if (!isPremium) {
      state = _tracker.currentPeriodCount();
    }
    appLogger.info(
      '📊 [Quota] tryConsume exit: consumed=$consumed, '
      'after=${_tracker.currentPeriodCount()}/${PremiumLimits.freeWeeklyDownloads}',
    );
    return consumed;
  }

  void syncFromServer(int consumed) {
    _tracker.syncFromServer(consumed);
    state = _tracker.currentPeriodCount();
  }

  Future<void> reset() async {
    await _tracker.reset();
    state = _tracker.currentPeriodCount();
  }
}

/// Premium state notifier
class PremiumNotifier extends StateNotifier<PremiumLicense> {
  final PremiumLicenseService _service;

  /// Optional callback fired after every successful explicit re-activation.
  /// Used by the provider to clear the VidCombo user-deactivate tombstone
  /// (brand-guarded inside the callback). Null in test contexts that do
  /// not exercise the tombstone path.
  final Future<void> Function()? _onActivationSuccess;

  /// SharedPrefs key: ISO-8601 timestamp of last startup refresh.
  static const _lastRefreshKey = 'premium_last_verified';

  /// Exposed for testing only.
  @visibleForTesting
  static const lastRefreshKeyForTest = _lastRefreshKey;

  /// Skip backend call if last startup refresh was <24h ago.
  static const _refreshCooldownHours = 24;

  PremiumNotifier(this._service, {Future<void> Function()? onActivationSuccess})
    : _onActivationSuccess = onActivationSuccess,
      super(PremiumLicense.free) {
    _loadLicense();
  }

  Future<void> _loadLicense() async {
    final loaded = await _service.getLicense();
    state = loaded;
  }

  /// Refresh subscription status from the backend on app startup.
  ///
  /// [verificationService] and [prefs] are passed by the caller (app_scaffold)
  /// to avoid a circular import between premium_providers ↔ license_verification_providers.
  ///
  /// Skips if [prefs] has a cache entry < [_refreshCooldownHours] old.
  /// On [VerificationResult.shouldDeactivate]: reverts to free tier.
  /// Free users: always skipped (no network call on startup).
  Future<void> refreshLicense({
    required LicenseVerificationService verificationService,
    required SharedPreferences prefs,
    DownloadQuotaNotifier? quotaNotifier,
    DateTime? now,
    bool ignoreCooldown = false,
  }) async {
    // Skip for free users — no backend call needed
    if (state.isFree) return;

    final current = now ?? DateTime.now();

    // 24h caching: avoid hammering the backend on every launch
    if (!ignoreCooldown) {
      final lastRefreshStr = prefs.getString(_lastRefreshKey);
      if (lastRefreshStr != null) {
        final lastRefresh = DateTime.tryParse(lastRefreshStr);
        if (lastRefresh != null) {
          final hoursSince = current.difference(lastRefresh).inHours;
          if (hoursSince < _refreshCooldownHours) {
            appLogger.debug(
              'Premium refresh skipped: last refresh ${hoursSince}h ago',
            );
            return;
          }
        }
      }
    }

    appLogger.info('Running startup premium license refresh');
    try {
      final result = await verificationService.verify(now: now);
      if (result.shouldDeactivate) {
        if (result.definitive) {
          // DEFINITIVE server revoke (reason=='revoked' / tier free) → full
          // wipe including the key.
          appLogger.warning(
            'Startup refresh: license revoked by server (${result.reason})',
          );
          await deactivateLicense(quotaNotifier: quotaNotifier);
        } else {
          // UNCERTAIN demote (expired / network / grace / format / unknown) →
          // soft demote: drop premium but KEEP the key so the user
          // auto-recovers when the backend re-confirms. INVARIANT #1.
          appLogger.warning(
            'Startup refresh: license demoted, key preserved (${result.reason})',
          );
          await softDeactivateLicense(quotaNotifier: quotaNotifier);
        }
      } else {
        // Reload from storage to pick up any updated lastVerified
        await _loadLicense();
      }
      await prefs.setString(_lastRefreshKey, current.toIso8601String());
    } catch (e) {
      // Non-fatal: network issues must not block app startup
      appLogger.debug('Startup premium refresh failed (non-fatal): $e');
    }
  }

  /// Activate subscription license with key.
  ///
  /// If [verificationService] is provided, immediately calls the backend
  /// to fetch billing metadata (billingCycle, expiresAt, isAutoRenew)
  /// that is not available at activation time.
  Future<void> activateLicense(
    String key, {
    String? paymentMethod,
    String? transactionId,
    BillingCycle? billingCycle,
    DateTime? expiresAt,
    bool isAutoRenew = true,
    LicenseVerificationService? verificationService,
  }) async {
    // Verify FIRST, then activate. Pre-fix this activated locally + tried
    // to sync metadata afterwards; if backend said the key was revoked /
    // expired / invalid, the local state was already premium AND the
    // tombstone-clear callback fired. User pastes a revoked key → app
    // thinks premium. Broad ultra-review Round 8 catch.
    //
    // verificationService is null for VidCombo PHP path (no Go verify
    // endpoint exists for those keys) — in that case we trust the caller
    // and skip the verify step. Caller should already have hit
    // checkkey.php to confirm status.
    if (verificationService != null) {
      final response = await verificationService.verifyKey(key);
      if (!response.isValid) {
        appLogger.warning(
          'Backend verify rejected license key on activation '
          '(reason: ${response.reason ?? "unknown"}). Refusing local activate.',
        );
        throw const FormatException(
          'License key is not valid or has been revoked',
        );
      }
      // Verify OK — use backend-authoritative metadata.
      final cycle =
          response.billingCycle != null
              ? BillingCycle.fromString(response.billingCycle!)
              : billingCycle;
      state = await _service.activateLicense(
        key,
        paymentMethod: paymentMethod,
        transactionId: transactionId,
        billingCycle: cycle,
        expiresAt: response.expiresAt ?? expiresAt,
        isAutoRenew: isAutoRenew,
      );
      // Sync isAutoRenew from backend if available.
      try {
        state = await _service.updateLicenseMetadata(
          billingCycle: cycle,
          expiresAt: response.expiresAt,
          isAutoRenew: response.isAutoRenew,
        );
      } catch (e) {
        appLogger.debug('License metadata update failed (non-fatal): $e');
      }
    } else {
      // No verification service — caller responsibility. Activate locally.
      state = await _service.activateLicense(
        key,
        paymentMethod: paymentMethod,
        transactionId: transactionId,
        billingCycle: billingCycle,
        expiresAt: expiresAt,
        isAutoRenew: isAutoRenew,
      );
    }

    // Explicit user re-activation: clear VidCombo deactivate tombstone so
    // future launches resume normal legacy-file behavior. No-op on SSvid /
    // when no callback configured.
    await _fireActivationSuccessCallback();
  }

  /// Activate license from a backend that already verified it (e.g. VidCombo PHP).
  ///
  /// Unlike [activateLicense], this skips Go backend verification since the
  /// PHP backend already returned license status + metadata.
  ///
  /// Fires [onActivationSuccess] so the VidCombo deactivate tombstone is
  /// cleared: server is the source of truth, so if PHP returns active
  /// premium for a previously-deactivated user (they re-purchased on the
  /// website, or the previous deactivate was transient), the local tombstone
  /// state MUST converge with reality — otherwise the next launch sees a
  /// "premium + tombstoned" contradiction. Broad ultra-review 2026-05-21
  /// catch.
  Future<void> activateLicenseFromBackend(
    String key, {
    String? billingCycle,
    DateTime? expiresAt,
    bool? isAutoRenew,
  }) async {
    final cycle =
        billingCycle != null ? BillingCycle.fromString(billingCycle) : null;
    final existing = await _service.getLicense();
    final isSameLicense = existing.licenseKey == key;

    state = await _service.activateLicense(
      key,
      paymentMethod: isSameLicense ? existing.paymentMethod : null,
      transactionId: isSameLicense ? existing.transactionId : null,
      billingCycle: cycle,
      expiresAt: expiresAt,
      isAutoRenew: isAutoRenew ?? (isSameLicense ? existing.isAutoRenew : true),
    );

    appLogger.info(
      'License activated from backend '
      '(cycle: ${cycle?.name}, expires: $expiresAt)',
    );

    await _fireActivationSuccessCallback();
  }

  /// Activate backend-verified premium access when the backend does not return
  /// a license key, e.g. legacy VidCombo PHP device-bound premium records.
  ///
  /// Same tombstone-convergence concern as [activateLicenseFromBackend] —
  /// fires [onActivationSuccess] for consistency.
  Future<void> activateVerifiedPremiumFromBackend({
    String? key,
    String? billingCycle,
    DateTime? expiresAt,
  }) async {
    final cycle =
        billingCycle != null ? BillingCycle.fromString(billingCycle) : null;

    state = await _service.activateVerifiedPremium(
      key: key,
      billingCycle: cycle,
      expiresAt: expiresAt,
    );

    await _fireActivationSuccessCallback();
  }

  /// Fire the success callback (tombstone clear) — shared by every
  /// activation path. Failures are non-fatal: tombstone clear is polish,
  /// it never blocks the actual activation.
  Future<void> _fireActivationSuccessCallback() async {
    final cb = _onActivationSuccess;
    if (cb == null) return;
    try {
      await cb();
    } catch (e) {
      appLogger.debug('Activation success callback failed (non-fatal): $e');
    }
  }

  /// Cancel subscription (stays active until expiry)
  Future<void> cancelSubscription() async {
    state = await _service.cancelSubscription();
  }

  /// Deactivate license (revert to free immediately, FULL wipe incl. key).
  ///
  /// Reserved for explicit user Deactivate or a DEFINITIVE server revoke.
  /// Accepts optional [quotaNotifier] to reset daily counter on downgrade.
  Future<void> deactivateLicense({DownloadQuotaNotifier? quotaNotifier}) async {
    state = await _service.deactivateLicense();
    await quotaNotifier?.reset();
  }

  /// Soft-deactivate license (revert to free immediately, KEEP stored key).
  ///
  /// For non-definitive demote signals (expired / network / grace /
  /// format-corrupt / unknown): drops premium but preserves the secure-storage
  /// key so the user auto-recovers when the backend re-confirms. INVARIANT #1.
  /// Accepts optional [quotaNotifier] to reset daily counter on downgrade.
  Future<void> softDeactivateLicense({
    DownloadQuotaNotifier? quotaNotifier,
  }) async {
    state = await _service.softDeactivateLicense();
    await quotaNotifier?.reset();
  }

  /// Update verification timestamp after successful server check
  Future<void> updateVerification() async {
    state = await _service.updateVerification();
  }

  /// Refresh license from storage
  Future<void> refresh() async {
    await _loadLicense();
  }
}
