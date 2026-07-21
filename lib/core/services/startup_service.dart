import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../binaries/binary_providers.dart';
import '../binaries/binary_type.dart';
import '../config/brand_config.dart';
import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../logging/app_logger.dart';
import '../network/backend_dtos.dart';
import '../providers/backend_providers.dart';
import '../../features/settings/presentation/providers/settings_provider.dart'
    show sharedPreferencesProvider;
import '../../features/youtube_channel/data/datasources/channel_subscription_local_datasource.dart';
import 'auto_update_service.dart';
import 'error_reporter_service.dart';
import 'instrumentation.dart';
import 'notification_center_service.dart';
import 'subscription_poll_service.dart';
import 'ticket_poll_service.dart';
import '../providers/database_provider.dart';
import 'vidcombo/vidcombo_backend_adapter.dart';
import '../providers/notification_center_provider.dart';
import '../../features/downloads/data/services/vidcombo_installer_marker_policy.dart';
import '../../features/downloads/data/services/vidcombo_legacy_importer.dart';
import '../../features/premium/data/services/license_activation_handler.dart';
import '../../features/premium/data/services/license_verification_service.dart';
import '../../features/premium/domain/entities/premium_license.dart';
import '../../features/premium/presentation/providers/license_verification_providers.dart';
import '../../features/premium/presentation/providers/pdfconv_paypal_providers.dart';
import '../../features/premium/presentation/providers/payment_providers.dart';
import '../../features/premium/presentation/providers/premium_providers.dart';

/// Handles one-time startup tasks: device registration, heartbeat, update check.
/// All operations are non-blocking and failure-tolerant.
/// Delegates to brand-specific backend (Go for SSvid, PHP for VidCombo).
class StartupService {
  /// SharedPreferences key for the VidCombo checkkey.php response cache.
  /// Cache stores the most recent premium response so the next app launch
  /// can activate premium features instantly instead of waiting for a full
  /// PHP round-trip (typical VN mobile RTT ~400-800ms). Invalidated by
  /// [_vidComboCheckKeyCacheTtl] and by the installer-marker state reset.
  static const _vidComboCheckKeyCacheKey = 'vidcombo_checkkey_cache_v1';
  static const _vidComboCheckKeyCacheTtl = Duration(minutes: 15);

  /// SharedPreferences key. Set when user explicitly deactivates premium on
  /// a VidCombo device. While present, [_importLegacyLicenseKey] short-circuits
  /// so a leftover legacy `settings1.gs` cannot silently re-import the key
  /// and undo the user's intent. Cleared on any explicit re-activation
  /// (manual paste, restore-by-email, payment success, deep-link).
  ///
  /// Backend-driven demotion does NOT set the tombstone — server-driven
  /// state changes are not user intent.
  static const _vidComboUserDeactivatedKey = 'vidcombo_user_deactivated_v1';

  /// Initialize backend integration. Fire-and-forget, never blocks app startup.
  static Future<void> initialize(ProviderContainer container) async {
    await instrumentedAsync<void>(
      'startup.backend_init',
      () async {
        if (BrandConfig.current.backendType == BackendType.php) {
          await _initializeVidCombo(container);
        } else {
          await _initializeGo(container);
        }
      },
      attributes: {
        'backend': BrandConfig.current.backendType.name,
        'brand': BrandConfig.current.brand.name,
      },
      rethrowAfterReport: false,
      onError: (e, _) {
        // Non-critical: backend startup failures must not abort the app.
        appLogger.warning('Backend startup failed (non-critical): $e');
      },
      reporter: container.read(errorReporterServiceProvider),
    );

    // Always mark premium bootstrap ready, even on backend failure (was the
    // finally-block in the previous try/finally form). Reading the provider
    // can throw during container disposal; intentional silent — best-effort.
    try {
      container.read(premiumBootstrapReadyProvider.notifier).state = true;
    } catch (_) {}

    // Subscription polling is brand-agnostic (uses yt-dlp, not backend API).
    _startSubscriptionPolling(container);
  }

  /// SSvid startup flow — Go backend with X-API-Key auth.
  static Future<void> _initializeGo(ProviderContainer container) async {
    // Migrate secrets from SharedPreferences to secure storage (one-time)
    final credentials = container.read(secureCredentialStoreProvider);
    await credentials.migrateIfNeeded();

    final authService = container.read(deviceAuthServiceProvider);

    // Register device if not yet registered
    if (!await authService.isRegistered) {
      appLogger.info('First launch: registering device with backend...');
      final success = await authService.register();
      if (!success) {
        appLogger.warning('Device registration failed, will retry next launch');
        return;
      }
    }

    // Send heartbeat (fire-and-forget)
    unawaited(authService.heartbeat());

    // Wire backend crash reporting (alongside Sentry)
    final errorReporter = container.read(errorReporterServiceProvider);
    errorReporter.setBackendService(container.read(backendServiceProvider));

    // Start analytics tracking
    container.read(analyticsServiceProvider).start();
    unawaited(_reconcilePendingUpdateInstall(container));

    // Start ticket reply polling (5-min interval, non-blocking)
    _startTicketPolling(container);

    // Check for updates (non-blocking)
    _checkForUpdates(container);

    // Fetch announcements (non-blocking)
    _fetchAnnouncements(container);

    // Fetch feature flags and remote config (non-blocking)
    _fetchFeatureFlags(container);
    _fetchRemoteConfig(container);

    // Verify premium license (fire-and-forget, non-blocking). Chain the
    // server-entitlement self-heal AFTER verify settles so the free-check
    // below reflects any soft-demote that verify just applied — otherwise a
    // device demoted earlier this boot would be read as still-premium and
    // skip the re-promote it actually needs.
    unawaited(
      _verifyLicense(
        container,
      ).whenComplete(() => _selfHealServerEntitlement(container)),
    );

    // Check for subscription expiry warning (7-day warning, 24h cooldown)
    _checkExpiryWarning(container);

    // Check for pending payment sessions (crash recovery — Layer 3 safety net)
    _recoverPendingPayment(container);

    // Initialize deep-link activation handler + listen for UI feedback
    final activationHandler = container.read(licenseActivationHandlerProvider);
    _listenForActivation(activationHandler, container);

    // Register URL scheme on Windows/Linux (idempotent, non-blocking)
    _registerUrlScheme();

    appLogger.info('Go backend startup tasks completed');
  }

  /// VidCombo startup flow — PHP backend with checkkey.php + version.php.
  ///
  /// Zero-friction license migration: sends raw platform UUID as device_id
  /// to checkkey.php. Backend recognizes existing devices and returns their
  /// license status automatically.
  static Future<void> _initializeVidCombo(ProviderContainer container) async {
    // Migrate secrets from SharedPreferences to secure storage (one-time)
    final credentials = container.read(secureCredentialStoreProvider);
    await credentials.migrateIfNeeded();

    // CRITICAL: On Windows, detect if the Inno Setup installer just ran.
    // Two marker files in %TEMP%:
    //   vidcombo_installer_ran.txt  — ALWAYS written by installer (since v1.3.3)
    //   vidcombo_migrated_key.txt   — only if old VidCombo settings were found
    //
    // Processing order matters:
    // 1. Installer-ran marker → reset ALL stale migration state (one-shot
    //    import flag, stale credentials). Covers "dirty machine" scenario
    //    where old VidCombo was already uninstalled in previous cycles.
    // 2. Migrated-key file → import the actual license key into credentials.
    if (Platform.isWindows) {
      final tempDir =
          Platform.environment['TEMP'] ?? Platform.environment['TMP'] ?? '';
      if (tempDir.isNotEmpty) {
        // STEP A: Check installer-ran marker. All decision logic lives in
        // [decideInstallerMarkerAction] for unit-test coverage; this block
        // just observes facts, asks the policy, and applies the result.
        final installerMarker = File(
          p.join(tempDir, 'vidcombo_installer_ran.txt'),
        );
        try {
          if (await installerMarker.exists()) {
            final prefs = await SharedPreferences.getInstance();
            const kFailCountKey = 'vidcombo_installer_marker_fail_count';
            const kProcessedMtimeKey =
                'vidcombo_installer_marker_processed_mtime';

            int? markerMtimeMs;
            try {
              markerMtimeMs =
                  (await installerMarker.stat())
                      .modified
                      .millisecondsSinceEpoch;
            } catch (_) {}

            final lastProcessed = prefs.getInt(kProcessedMtimeKey);
            final currentFailCount = prefs.getInt(kFailCountKey) ?? 0;

            // Attempt the delete only when the fingerprint doesn't match
            // (otherwise we're in the idempotent-skip branch anyway).
            final alreadyProcessed =
                markerMtimeMs != null && lastProcessed == markerMtimeMs;
            var deleteSucceeded = false;
            if (!alreadyProcessed) {
              try {
                await installerMarker.delete();
                deleteSucceeded = true;
              } catch (e) {
                appLogger.warning(
                  '[VidCombo] Cannot delete installer marker '
                  '(will retry next launch): $e',
                );
              }
            }

            final decision = decideInstallerMarkerAction(
              MarkerObservation(
                markerExists: true,
                markerMtimeMs: markerMtimeMs,
                lastProcessedMtimeMs: lastProcessed,
                currentFailCount: currentFailCount,
                deleteSucceeded: deleteSucceeded,
              ),
            );

            if (!decision.skip) {
              if (decision.clearFailCount) {
                await prefs.remove(kFailCountKey);
              } else if (decision.nextFailCount != null) {
                await prefs.setInt(kFailCountKey, decision.nextFailCount!);
                if (!decision.resetState) {
                  // Retry path — log diagnostically.
                  appLogger.debug(
                    '[VidCombo] Marker delete backoff '
                    '(fail ${decision.nextFailCount}/3 before force-accept).',
                  );
                }
              }

              if (decision.resetState) {
                if (!deleteSucceeded) {
                  appLogger.warning(
                    '[VidCombo] Installer marker could not be deleted '
                    'after ${decision.nextFailCount ?? "?"} launches — '
                    'proceeding with state reset anyway (marker likely '
                    'locked by antivirus). Fingerprinting by mtime.',
                  );
                  safeBreadcrumb(
                    container.read(errorReporterServiceProvider),
                    'marker_policy_force_accepted',
                    data: {
                      'fail_count': decision.nextFailCount ?? -1,
                      'has_mtime': markerMtimeMs != null,
                    },
                  );
                }

                // Persist fingerprint BEFORE state mutations so a crash
                // in the middle still leaves us idempotent next launch.
                if (decision.persistProcessedMtime != null) {
                  await prefs.setInt(
                    kProcessedMtimeKey,
                    decision.persistProcessedMtime!,
                  );
                }
                try {
                  await prefs.remove('vidcombo_legacy_import_done_v1');
                  await prefs.remove('vidcombo_legacy_import_version');
                  appLogger.info(
                    '[VidCombo] Reset legacy import flags (installer detected)',
                  );
                } catch (_) {}
                // The installer-marker handshake is for clearing legacy 32-hex
                // PHP keys so `vidcombo_migrated_key.txt` (STEP B below) can
                // re-import a fresh value from the old settings file the
                // installer just extracted. It must NOT wipe modern Go-backend
                // keys (SSVID-*/VIDCOMBO-*) created by in-app Stripe payment —
                // those are valid across installer cycles and have no
                // migration handoff. Wiping them silently demotes paying
                // users (3 paid users hit this within 2 days of 1.7.0 ship).
                try {
                  final existing = await credentials.read(
                    'premium_license_key',
                  );
                  if (shouldWipeCredentialOnMarkerReset(existing)) {
                    await credentials.delete('premium_license_key');
                    appLogger.info(
                      '[VidCombo] Cleared stored license for installer '
                      'migration handoff (legacy/empty key)',
                    );
                    safeBreadcrumb(
                      container.read(errorReporterServiceProvider),
                      'marker_wiped_legacy_key',
                      data: {'had_key': existing != null},
                    );
                  } else {
                    appLogger.info(
                      '[VidCombo] Preserved Go-backend license key during '
                      'marker reset (Stripe-paid user)',
                    );
                    safeBreadcrumb(
                      container.read(errorReporterServiceProvider),
                      'marker_preserved_go_key',
                    );
                  }
                } catch (_) {}
              }
            }
          }
        } catch (_) {}

        // STEP B: Check migrated-key file (only exists if installer found
        // old VidCombo settings with a valid 32-hex PHP key).
        //
        // CRITICAL: Step A above preserves Go-backend keys (SSVID-*/
        // VIDCOMBO-*) when the marker triggers a state reset. Step B must
        // honour that — overwriting a preserved Go key with the legacy
        // 32-hex would silently demote a paying Stripe user on every
        // installer run that ALSO happens to find an old settings file
        // (e.g. a user who migrated from BLUEBYTE to in-app Stripe but
        // never deleted their old `settings1.gs`).
        final migratedKeyFile = File(
          p.join(tempDir, 'vidcombo_migrated_key.txt'),
        );
        try {
          if (await migratedKeyFile.exists()) {
            final key = (await migratedKeyFile.readAsString()).trim();
            if (key.length == 32 &&
                RegExp(r'^[0-9A-Fa-f]{32}$').hasMatch(key)) {
              final existing = await credentials.read('premium_license_key');
              // Reuse the marker-wipe decision so Step A (wipe) and
              // Step B (import) stay in lockstep — both must preserve
              // Go-backend (Stripe) keys. Without this, Step A would
              // correctly skip the wipe, then Step B would silently
              // overwrite the same Go key with stale legacy 32-hex.
              if (shouldWipeCredentialOnMarkerReset(existing)) {
                await credentials.write('premium_license_key', key);
                appLogger.info(
                  '[VidCombo] Imported installer-migrated license key',
                );
              } else {
                appLogger.info(
                  '[VidCombo] Skipped legacy migrated key — '
                  'Go-backend key already stored (Stripe-paid user)',
                );
                safeBreadcrumb(
                  container.read(errorReporterServiceProvider),
                  'marker_step_b_skipped_for_go_key',
                );
              }
            }
            try {
              await migratedKeyFile.delete();
            } catch (_) {}
          }
        } catch (_) {}
      }
    }

    // Silently import old VidCombo files into the new library on first launch.
    // Idempotent (one-shot flag), brand-guarded, fully background — no UI.
    // Failure here must NEVER block startup.
    unawaited(_runVidComboLegacyImport(container));

    final adapter = VidComboBackendAdapter(
      errorReporter: container.read(errorReporterServiceProvider),
    );
    var vidcomboPremium = false;

    // Call checkkey.php — this auto-registers new devices AND returns license status
    try {
      String? licenseKey = await credentials.read('premium_license_key');

      // On first launch, the new app has no stored key and its device_id
      // (raw MachineGuid) won't match the old VidCombo's device_id format
      // ({GUID} with braces). Import the license key from the old app's
      // settings file so checkkey.php can recognize it directly.
      //
      // Respect explicit user-deactivate intent: when the tombstone is set
      // we skip the file scan so a residual settings1.gs cannot reactivate
      // someone who just clicked Deactivate. Server-side auto-restore via
      // checkkey.php below is still allowed — server is source of truth.
      final prefs = container.read(sharedPreferencesProvider);
      if (licenseKey == null || licenseKey.isEmpty) {
        if (hasVidComboDeactivateTombstone(prefs)) {
          appLogger.info(
            '[VidCombo] Legacy file scan skipped — user-deactivate tombstone set',
          );
        } else {
          licenseKey = await _importLegacyLicenseKey();
          if (licenseKey != null) {
            await credentials.write('premium_license_key', licenseKey);
            appLogger.info('Imported legacy VidCombo license key');
          }
        }
      }

      // Fast-path: if we recently observed this device as premium, skip the
      // full PHP round-trip and use the cached response. A background refresh
      // keeps the cache warm for the NEXT boot so we never serve stale
      // premium state for more than [_vidComboCheckKeyCacheTtl]. Non-premium
      // responses are NOT cached — we want to immediately reflect a
      // just-purchased license on the very next launch.
      final cached = readVidComboCheckKeyCache(prefs, now: DateTime.now());
      VidComboCheckKeyResponse result;
      if (cached != null && cached.isPremium) {
        appLogger.info(
          '[VidCombo] Using cached premium checkkey for bootstrap '
          '(skipping PHP round-trip, refresh queued)',
        );
        safeBreadcrumb(
          container.read(errorReporterServiceProvider),
          'vidcombo_cache_hit',
        );
        result = cached;
        unawaited(
          adapter
              .checkKey(licenseKey: licenseKey)
              .then((rawFresh) async {
                // FIX #5: mirror the SYNC path's BLUEBYTE braced-device-id
                // retry BEFORE deciding to demote. A legacy braced-device
                // VidCombo subscriber's lowercase device_id returns non-premium
                // from PHP, so without this retry the bg refresh would
                // deterministically demote the same device that the cache hit
                // (above) just showed as premium — every single cache-hit boot.
                var fresh = rawFresh;
                if (!fresh.isPremium) {
                  final recovered = await _retryBracedDeviceCheckKey(
                    container,
                    rawDeviceId: adapter.deviceId,
                  );
                  if (recovered != null) fresh = recovered;
                }

                // Pre-resolve Go-backend validity only when needed so PHP
                // "active" responses never pay a Go round-trip.
                final isGoLicense =
                    licenseKey != null && _isGoBackendLicense(licenseKey);
                var goStillValid = false;
                if (!fresh.isPremium && isGoLicense) {
                  goStillValid = await _verifyGoLicenseForVidCombo(
                    container,
                    licenseKey,
                  );
                }

                final decision = decideBackgroundRefreshAction(
                  freshIsPremium: fresh.isPremium,
                  freshMessage: fresh.message,
                  storedLicenseKey: licenseKey,
                  isStoredKeyGoBackend: isGoLicense,
                  goBackendStillValid: goStillValid,
                );

                switch (decision.action) {
                  case BackgroundRefreshAction.writeFreshCache:
                    await writeVidComboCheckKeyCache(
                      prefs,
                      fresh,
                      verifiedAt: DateTime.now(),
                    );
                  case BackgroundRefreshAction.keepCache:
                    appLogger.debug(
                      '[VidCombo] Background refresh: PHP returned inactive '
                      'but Go-backend license is still valid — keeping '
                      'premium state.',
                    );
                  case BackgroundRefreshAction.demote:
                    await prefs.remove(_vidComboCheckKeyCacheKey);
                    await _maybeNotifyDemotion(
                      container,
                      serverMessage: decision.serverMessage,
                      source: 'vidcombo_bg',
                      // The cache hit this boot proved premium (cached.isPremium
                      // gated this branch), so the prior tier was premium.
                      priorTier: 'premium',
                      responseIsValid: fresh.isPremium,
                      responseReason: fresh.status,
                      hadStoredKey: licenseKey != null && licenseKey.isNotEmpty,
                      // FIX #5: suppress the toast — a bg-refresh demote that
                      // contradicts a same-boot cache hit should self-heal on
                      // the next boot, not flash "Premium Deactivated" at a
                      // user who is still using premium this session.
                      suppressNotification: true,
                    );
                    safeBreadcrumb(
                      container.read(errorReporterServiceProvider),
                      'vidcombo_cache_demotion',
                      data: {'had_go_license': decision.hadGoLicense},
                    );
                }
              })
              .catchError((Object e) {
                appLogger.debug(
                  '[VidCombo] Background checkkey refresh failed '
                  '(cache kept): $e',
                );
              }),
        );
      } else {
        safeBreadcrumb(
          container.read(errorReporterServiceProvider),
          'vidcombo_cache_miss',
          data: {'cache_present': cached != null},
        );
        result = await adapter.checkKey(licenseKey: licenseKey);
      }

      // FALLBACK: If not premium, the old BLUEBYTE VidCombo registered
      // devices using Windows GUID format: {UPPERCASE-UUID-WITH-BRACES}
      // (e.g. {985168AE-F117-4744-B5F5-C57609D69276}) — confirmed from
      // production checkkey.php logs. Our getRawPlatformUuid() returns
      // lowercase-without-braces from the registry. Try the exact old
      // format to recover the premium record.
      if (!result.isPremium) {
        final recovered = await _retryBracedDeviceCheckKey(
          container,
          rawDeviceId: adapter.deviceId,
        );
        if (recovered != null) result = recovered;
      }

      appLogger.info(
        'VidCombo checkkey: status=${result.status}, '
        'free=${result.countFree}, plan=${result.plan}',
      );

      // Cache successful premium responses so the next boot skips the PHP
      // round-trip. Gated on `result != cached` so a cache-hit path does not
      // re-write the same entry and prolong its age beyond what the
      // upstream refresh proves.
      if (result.isPremium && !identical(result, cached)) {
        await writeVidComboCheckKeyCache(
          prefs,
          result,
          verifiedAt: DateTime.now(),
        );
      }

      // Store license_key in secure storage for future use
      if (result.licenseKey != null && result.licenseKey!.length == 32) {
        await credentials.write('premium_license_key', result.licenseKey!);
      }

      // Store device_id
      if (adapter.deviceId != null) {
        await credentials.write('device_id', adapter.deviceId!);
      }

      // Snapshot pre-decision tier + key presence for telemetry (prior_tier /
      // had_stored_key). Read BEFORE any activate/demote mutation.
      final syncPriorTier =
          container.read(isPremiumProvider) ? 'premium' : 'free';
      final syncHadStoredKey = licenseKey != null && licenseKey.isNotEmpty;

      // Handle free vs premium status
      if (!result.isPremium) {
        // Go-backend license guard: if the stored license key is in
        // Go format (VIDCOMBO-XXXX or legacy SSVID-XXXX, created via
        // in-app Stripe), PHP checkkey.php won't recognize it and
        // returns inactive. Verify with Go backend instead before demoting.
        if (licenseKey != null && _isGoBackendLicense(licenseKey)) {
          final goVerified = await _verifyGoLicenseForVidCombo(
            container,
            licenseKey,
          );
          if (goVerified) {
            appLogger.info(
              '[VidCombo] Go-backend license verified — '
              'skipping PHP demotion',
            );
            // Go backend confirms premium for this Go-created VidCombo key.
            // Reflect it so _registerVidComboWithGoBackend syncs the Go admin
            // dashboard device.tier='premium' (admin-dashboard correctness;
            // app entitlement itself is license-tier-based, not device-tier).
            vidcomboPremium = true;
            _logLicenseVerifyEvent(
              container,
              result: 'premium',
              reason: 'go_license_verified',
              source: 'vidcombo_sync',
              priorTier: syncPriorTier,
              responseIsValid: false,
              responseReason: result.status,
              decision: 'keep',
              hadStoredKey: syncHadStoredKey,
            );
          } else {
            // Go backend also says not premium — proceed with demotion.
            await _maybeNotifyDemotion(
              container,
              serverMessage: result.message,
              source: 'vidcombo_sync',
              priorTier: syncPriorTier,
              responseIsValid: result.isPremium,
              responseReason: result.status,
              hadStoredKey: syncHadStoredKey,
            );
          }
        } else {
          // PHP-created license or no license — trust checkkey.php result.
          await _maybeNotifyDemotion(
            container,
            serverMessage: result.message,
            source: 'vidcombo_sync',
            priorTier: syncPriorTier,
            responseIsValid: result.isPremium,
            responseReason: result.status,
            hadStoredKey: syncHadStoredKey,
          );
        }
        // NOTE: Do NOT sync PHP's count_free to local quota tracker.
        // PHP reports legacy daily data; the client now enforces 15/week
        // locally and independently.
      }

      // If premium, activate locally + sync tier to Go backend admin
      if (result.isPremium) {
        try {
          final verification = adapter.toLicenseVerification(result);
          final premiumNotifier = container.read(
            premiumLicenseProvider.notifier,
          );
          final activationKey = result.licenseKey ?? licenseKey;
          if (activationKey != null && activationKey.isNotEmpty) {
            await premiumNotifier.activateLicenseFromBackend(
              activationKey,
              billingCycle: verification.billingCycle,
              expiresAt: verification.expiresAt,
            );
          } else {
            await premiumNotifier.activateVerifiedPremiumFromBackend(
              billingCycle: verification.billingCycle,
              expiresAt: verification.expiresAt,
            );
          }
          vidcomboPremium = true;
          appLogger.info('VidCombo premium license activated locally');
          _logLicenseVerifyEvent(
            container,
            result: 'premium',
            source: 'vidcombo_sync',
            priorTier: syncPriorTier,
            responseIsValid: true,
            responseReason: result.status,
            decision: 'keep',
            hadStoredKey:
                syncHadStoredKey ||
                (activationKey != null && activationKey.isNotEmpty),
          );
        } catch (e) {
          appLogger.warning('VidCombo premium activation failed: $e');
        }
      }
    } on FormatException catch (e) {
      appLogger.warning('VidCombo checkkey response parse error: $e');
    } on TimeoutException {
      appLogger.warning('VidCombo checkkey timed out — will retry next launch');
    } on SocketException catch (e) {
      appLogger.warning('VidCombo checkkey network error: $e');
    } catch (e) {
      appLogger.warning('VidCombo checkkey failed: $e');
    }

    // Also register with Go backend for operational features
    // (crash reports, analytics, AI chat, support tickets, payment)
    // Sync premium tier so Go admin dashboard reflects PHP license status.
    await _registerVidComboWithGoBackend(
      container,
      tier: vidcomboPremium ? 'premium' : 'free',
    );

    // Check for updates via version.php (legacy, non-blocking)
    _checkVidComboUpdates(container, adapter);

    // Also check Go backend for updates (primary source for auto-update).
    // Run after the registration attempt so private endpoints on cold-start do
    // not race secure-storage API-key creation. The endpoint is public server-
    // side now, but keeping the order avoids reintroducing the same race when
    // more update metadata becomes auth-aware later.
    _checkForUpdates(container);

    // Check for subscription expiry warning (7-day warning, 24h cooldown)
    _checkExpiryWarning(container);

    // Check for pending payment sessions (crash recovery — Layer 3 safety net)
    _recoverPendingPayment(container);
    unawaited(_recoverPendingPdfConvPayment(container));

    // Initialize deep-link activation handler + listen for UI feedback
    final activationHandler = container.read(licenseActivationHandlerProvider);
    _listenForActivation(activationHandler, container);

    // Register URL scheme on Windows/Linux (idempotent, non-blocking)
    _registerUrlScheme();

    appLogger.info('VidCombo PHP backend startup tasks completed');
  }

  /// Run the silent legacy-file importer for VidCombo, then generate
  /// thumbnails once ffmpeg is available.
  /// Wrapped here so the call site stays clean and errors are swallowed.
  static Future<void> _runVidComboLegacyImport(
    ProviderContainer container,
  ) async {
    try {
      final importer = container.read(vidComboLegacyImporterProvider);
      await importer.runIfNeeded();

      // Always attempt thumbnail generation. The importer may have burned
      // its one-shot flag on a previous launch where ffmpeg was not yet
      // downloaded, leaving legacy rows with no thumbnail. Runs in the
      // background after binaries become available; non-blocking.
      unawaited(_generateLegacyThumbnails(container));
    } catch (e, st) {
      appLogger.warning(
        'VidCombo legacy import failed (non-critical): $e\n$st',
      );
      // Send Sentry event so we can measure migration failure rate across
      // ~50,580 legacy devices. Breadcrumb-only would lose context without
      // a coupled crash; safeCaptureException creates a standalone event.
      // Dedupe gate inside safeCaptureException prevents flood.
      unawaited(
        safeCaptureException(
          container.read(errorReporterServiceProvider),
          e,
          stackTrace: st,
          scopeConfig: (scope) {
            scope.setTag('op', 'vidcombo_legacy_import');
            scope.setTag('brand', BrandConfig.current.brand.name);
          },
          backendMetadata: {
            'op': 'vidcombo_legacy_import',
            'error_type': e.runtimeType.toString(),
          },
        ),
      );
    }
  }

  /// Extract video thumbnails for legacy imports using ffmpeg.
  ///
  /// Waits up to 2 minutes (24 polls × 5 s) for ffmpeg to become
  /// available. If ffmpeg never arrives this launch, falls through
  /// silently — next launch retries because thumbnail column is still
  /// null and this method runs every launch.
  static Future<void> _generateLegacyThumbnails(
    ProviderContainer container,
  ) async {
    try {
      final manager = container.read(binaryManagerProvider);

      String? ffmpegPath;
      for (var i = 0; i < 24; i++) {
        ffmpegPath = await manager.getBinaryPath(BinaryType.ffmpeg);
        if (ffmpegPath != null) break;
        await Future<void>.delayed(const Duration(seconds: 5));
      }
      if (ffmpegPath == null) {
        appLogger.debug(
          '[VidCombo] ffmpeg not available after 2 min — '
          'thumbnail generation deferred to next launch',
        );
        return;
      }

      final importer = container.read(vidComboLegacyImporterProvider);
      final count = await importer.generateMissingThumbnails(ffmpegPath);
      if (count > 0) {
        appLogger.info('[VidCombo] generated $count legacy thumbnail(s)');
      }
    } catch (e) {
      appLogger.debug('Legacy thumbnail generation failed (non-critical): $e');
    }
  }

  /// Register VidCombo device with Go backend for operational features.
  /// This gives VidCombo access to: crash reports, analytics, AI chat, support.
  /// License/payment stays on PHP backend. Non-blocking, failure-tolerant.
  static Future<void> _registerVidComboWithGoBackend(
    ProviderContainer container, {
    String? tier,
  }) async {
    try {
      final authService = container.read(deviceAuthServiceProvider);

      // Register with Go backend (sends brand='vidcombo' in payload)
      if (!await authService.isRegistered) {
        final success = await authService.register();
        if (!success) {
          appLogger.debug(
            'VidCombo Go registration deferred — will retry next launch',
          );
          return;
        }
      }

      // Send heartbeat to Go backend — includes tier so admin dashboard
      // reflects VidCombo premium status verified via PHP checkkey.php
      unawaited(authService.heartbeat(tier: tier));

      // Wire backend crash reporting
      final errorReporter = container.read(errorReporterServiceProvider);
      errorReporter.setBackendService(container.read(backendServiceProvider));

      // Start analytics tracking
      container.read(analyticsServiceProvider).start();
      unawaited(_reconcilePendingUpdateInstall(container));

      // Payment rollout is fail-closed until this authenticated request
      // succeeds. Fetch only after VidCombo has a Go registration so a cold
      // start cannot race API-key creation. Existing intent recovery remains
      // independent from this flag.
      unawaited(_fetchFeatureFlags(container));

      appLogger.info(
        'VidCombo registered with Go backend for operational features',
      );
    } catch (e) {
      appLogger.debug(
        'VidCombo Go backend registration failed (non-critical): $e',
      );
    }
  }

  /// VidCombo-specific update check via version.php.
  static Future<void> _checkVidComboUpdates(
    ProviderContainer container,
    VidComboBackendAdapter adapter,
  ) async {
    try {
      final data = await adapter.checkUpdate();
      if (data.updateAvailable) {
        _notifyUpdate(container, data);
      }
    } catch (e) {
      appLogger.debug('VidCombo update check error: $e');
    }
  }

  /// Start background polling for ticket admin replies.
  static void _startTicketPolling(ProviderContainer container) {
    try {
      final prefs = container.read(sharedPreferencesProvider);
      final backend = container.read(backendServiceProvider);
      final notifications = container.read(notificationCenterServiceProvider);
      final pollService = TicketPollService(backend, notifications, prefs);
      pollService.start();
      // Note: pollService lifecycle is tied to the app — no explicit dispose needed
      // since the app process terminates on close.
    } catch (e) {
      appLogger.debug('Ticket polling start failed (non-critical): $e');
    }
  }

  static void _startSubscriptionPolling(ProviderContainer container) {
    try {
      final database = container.read(databaseProvider);
      final localDataSource = ChannelSubscriptionLocalDataSource(database);

      final pollService = SubscriptionPollService(
        localDataSource: localDataSource,
        container: container,
      );
      pollService.start();
    } catch (e) {
      appLogger.debug('Subscription polling start failed (non-critical): $e');
    }
  }

  static Future<void> _checkForUpdates(ProviderContainer container) async {
    try {
      final backendService = container.read(backendServiceProvider);
      final platform = _getPlatformName();

      // Try backend API first
      final result = await backendService.checkUpdate(
        platform: platform,
        version: AppConstants.appVersion,
      );

      var handled = false;
      result.when(
        success: (data) {
          if (data.updateAvailable) {
            _notifyUpdate(container, data);
            handled = true;
          }
        },
        failure: (e) {
          appLogger.debug('Backend update check failed: $e');
        },
      );

      // Fallback: check version.json when backend has no update info
      if (!handled) {
        await _checkVersionJsonFallback(container, platform);
      }
    } catch (e) {
      appLogger.debug('Update check error: $e');
    }
  }

  /// Fallback update check via version.json (brand-specific URL).
  /// Used when backend DB has no release record (e.g. CI doesn't auto-insert).
  static Future<void> _checkVersionJsonFallback(
    ProviderContainer container,
    String platform,
  ) async {
    final versionUrl = BrandConfig.current.versionCheckUrl;
    if (versionUrl == null) return; // Brand uses different update protocol

    try {
      final response = await http
          .get(Uri.parse(versionUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final latestVersion = json['version'] as String?;
      if (latestVersion == null) return;

      if (!_isNewerVersion(latestVersion, AppConstants.appVersion)) return;

      // Build download URL for this platform
      final downloads = json['downloads'] as Map<String, dynamic>?;
      final downloadUrl = downloads?[platform] as String?;
      final isMandatory = json['mandatory'] as bool? ?? false;
      final changelog = json['changelog'] as String?;

      appLogger.info(
        'Update found via version.json: $latestVersion '
        '(current: ${AppConstants.appVersion})',
      );

      final data = UpdateCheckResponse(
        updateAvailable: true,
        latestVersion: latestVersion,
        currentVersion: AppConstants.appVersion,
        isMandatory: isMandatory,
        releaseNotes: changelog,
        downloadUrl: downloadUrl,
      );

      _notifyUpdate(container, data);
    } catch (e) {
      appLogger.debug('version.json fallback failed (non-critical): $e');
    }
  }

  /// Compare semver strings. Returns true if [latest] > [current].
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

  /// Notify UI and trigger auto-download for mandatory updates.
  static void _notifyUpdate(
    ProviderContainer container,
    UpdateCheckResponse data,
  ) {
    appLogger.info(
      'Update available: ${data.latestVersion} '
      '(mandatory: ${data.isMandatory})',
    );
    container.read(appUpdateProvider.notifier).state = data;

    // Telemetry — `update_available` measures how many devices got an
    // updateAvailable=true response from the update check. This fires
    // BEFORE any UI surface mounts, so it does NOT mean the banner was
    // visually shown. The actual banner-on-screen event is
    // `update_banner_visible`, emitted from the widget's first build
    // (review feedback round 4 caught the semantic lie of calling this
    // event "shown").
    //
    // Audit 2026-04-27 showed only ~11.4% VidCombo adoption to v1.6.3
    // despite backend returning update_available=true for every v1.6.2
    // probe. Funnel: update_available → update_banner_visible →
    // update_install_clicked → update_install_succeeded.
    try {
      container.read(analyticsServiceProvider).track('update_available', {
        'latest_version': data.latestVersion ?? '',
        'is_mandatory': data.isMandatory,
      });
    } catch (_) {
      // Analytics is non-critical — never block the update flow on it.
    }

    if (data.isMandatory &&
        data.downloadUrl != null &&
        data.downloadUrl!.isNotEmpty &&
        BrandConfig.current.canAutoDownloadUpdate) {
      appLogger.info('Mandatory update — starting background download');
      // Telemetry is now emitted from inside downloadUpdate AFTER the
      // race guard, so the funnel counts each download attempt exactly
      // once even when 3 mandatory call sites fire on the same frame.
      // We only pass `source:` to identify which surface initiated.
      container
          .read(autoUpdateProvider.notifier)
          .downloadUpdate(
            data.downloadUrl!,
            data.checksum ?? '',
            data.latestVersion ?? '',
            source: 'startup_mandatory',
          );
    }
  }

  static Future<void> _reconcilePendingUpdateInstall(
    ProviderContainer container,
  ) async {
    try {
      final prefs = container.read(sharedPreferencesProvider);
      final analytics = container.read(analyticsServiceProvider);
      await UpdateInstallAckService.reconcileOnStartup(
        prefs,
        currentVersion: AppConstants.appVersion,
        track: (eventName, properties) {
          analytics.track(eventName, properties);
        },
        flush: analytics.flush,
      );
    } catch (e) {
      appLogger.debug('Pending update install ack skipped: $e');
    }
  }

  /// Recover a pending payment session (Layer 3 safety net).
  ///
  /// If the app was killed while user was paying in browser, the session ID
  /// was persisted to secure storage. On next launch, verify with backend:
  /// - Paid → activate license, clear pending session
  /// - Pending → leave for next startup check
  /// - Expired/failed → clear pending session
  static const _maxPendingSessionAge = Duration(hours: 25);

  static Future<void> _recoverPendingPayment(
    ProviderContainer container,
  ) async {
    try {
      final credentials = container.read(secureCredentialStoreProvider);
      final sessionId = await credentials.read('pending_payment_session');
      if (sessionId == null || sessionId.isEmpty) return;

      final tsStr = await credentials.read('pending_payment_session_ts');
      if (tsStr != null) {
        final created = DateTime.tryParse(tsStr);
        if (created != null &&
            DateTime.now().difference(created) > _maxPendingSessionAge) {
          appLogger.info(
            'Pending payment session expired (>25h), clearing stale marker',
          );
          await credentials.delete('pending_payment_session');
          await credentials.delete('pending_payment_session_ts');
          return;
        }
      }

      appLogger.info('Found pending payment session, verifying...');
      final paymentNotifier = container.read(paymentProvider.notifier);
      await paymentNotifier.recoverPendingSession(
        sessionId,
        onClearSession: () async {
          await credentials.delete('pending_payment_session');
          await credentials.delete('pending_payment_session_ts');
        },
      );
    } catch (e) {
      appLogger.debug('Pending payment recovery error (non-critical): $e');
    }
  }

  /// Recover VidCombo's SnakeLoader-owned PDFConv PayPal purchase intent.
  ///
  /// The persisted draft keeps the original idempotency key and request body,
  /// so replay converges on the same server-side intent and billing cell.
  static Future<void> _recoverPendingPdfConvPayment(
    ProviderContainer container,
  ) async {
    if (BrandConfig.current.brand != Brand.vidcombo) return;
    try {
      await container
          .read(pdfConvPayPalProvider.notifier)
          .recoverPendingCheckout();
    } catch (e) {
      appLogger.debug(
        'Pending PDFConv PayPal recovery error (non-critical): $e',
      );
    }
  }

  /// Verify premium license with backend (fire-and-forget).
  /// Checks every 7 days; 30-day grace period if server unreachable.
  static Future<void> _verifyLicense(ProviderContainer container) async {
    try {
      final verificationService = container.read(
        licenseVerificationServiceProvider,
      );
      final premiumNotifier = container.read(premiumLicenseProvider.notifier);

      // Snapshot the local tier + key presence BEFORE any mutation so the
      // telemetry prior_tier / had_stored_key reflect the pre-decision state
      // (a full demote wipes the key, so reading it later would under-report).
      final wasPremiumLocally = container.read(isPremiumProvider);
      final priorTier = wasPremiumLocally ? 'premium' : 'free';
      final hadStoredKey =
          (container.read(premiumLicenseProvider).licenseKey ?? '').isNotEmpty;

      final result = await verificationService.verify();

      if (result.verified) {
        if (result.reason == 'offline_grace') {
          appLogger.debug('License valid (offline grace period)');
        }
        // Refresh state from storage (updateVerification already saved)
        await premiumNotifier.refresh();
        // Explicit keep/offline_grace emit: previously the verified-grace
        // branch only logged a debug line, so an offline-grace boot was
        // indistinguishable from a never-checked one in telemetry.
        _logLicenseVerifyEvent(
          container,
          result: 'premium',
          reason: result.reason,
          source: 'startup_go',
          priorTier: priorTier,
          responseIsValid: true,
          responseReason: result.reason,
          decision: 'keep',
          hadStoredKey: hadStoredKey,
        );
      } else if (result.shouldDeactivate) {
        appLogger.warning(
          'Deactivating license: ${result.reason} '
          '(definitive: ${result.definitive})',
        );
        // Same silent-demotion guard as VidCombo path: only notify if the
        // local state was actually premium before this check, so we never
        // fire a demotion toast on a fresh install that never had premium.
        final quotaNotifier = container.read(
          downloadQuotaNotifierProvider.notifier,
        );
        final demoteResult = demoteResultForSignal(
          definitive: result.definitive,
        );
        if (demoteResult == 'full_demote') {
          // DEFINITIVE server revoke (reason=='revoked' / tier free) → full
          // wipe including the key.
          await premiumNotifier.deactivateLicense(quotaNotifier: quotaNotifier);
        } else {
          // UNCERTAIN demote (expired / network / grace / format / unknown) →
          // soft demote: drop premium but KEEP the key so the user
          // auto-recovers when the backend re-confirms. INVARIANT #1.
          await premiumNotifier.softDeactivateLicense(
            quotaNotifier: quotaNotifier,
          );
        }
        _logLicenseVerifyEvent(
          container,
          result: demoteResult,
          reason: result.reason,
          source: 'startup_go',
          priorTier: priorTier,
          responseIsValid: false,
          responseReason: result.reason,
          decision: demoteResult == 'full_demote' ? 'full' : 'soft',
          hadStoredKey: hadStoredKey,
        );
        if (wasPremiumLocally) {
          _pushDemotionNotification(container, serverMessage: result.reason);
        }
      }
    } catch (e) {
      appLogger.debug('License verification error (non-critical): $e');
    }
  }

  /// SSvid startup self-heal (FIX #1, symptom-killer).
  ///
  /// Runs ONLY when local premium state is free. Pulls the server-authoritative
  /// entitlement (device-auth, works keyless) and re-promotes if the server
  /// still considers this device premium. This recovers a user whose live
  /// premium flag was soft-demoted on a prior boot (offline grace, transient
  /// backend hiccup, the backend 0-grace post-expiry contradiction) while the
  /// subscription stayed active server-side.
  ///
  /// ADD-ONLY contract:
  ///   * Gated on free so an already-premium user is never touched.
  ///   * Delegates to [PaymentNotifier.reconcileServerEntitlement], which only
  ///     ever calls ACTIVATION sinks (activateLicenseFromBackend /
  ///     activateVerifiedPremiumFromBackend) — never a demote sink. Demote-
  ///     safety stays fully intact.
  ///   * Fire-and-forget; never throws into the startup flow.
  ///
  /// Mirrors the VidCombo premium-activation auto-heal at [_initializeVidCombo]
  /// (the cached/sync premium branch) but for the Go backend's device-auth
  /// entitlement lookup.
  static Future<void> _selfHealServerEntitlement(
    ProviderContainer container,
  ) async {
    try {
      // Gate 1: only attempt a promote when the live state is free. Reading
      // AFTER _verifyLicense settles means a same-boot soft-demote is already
      // reflected here.
      if (container.read(isPremiumProvider)) return;

      // Gate 2: self-heal ONLY an involuntary soft demote (license key still in
      // secure storage). An explicit user Deactivate or a definitive revoke
      // does clearAll (key deleted) — re-promoting those would reverse a
      // deliberate teardown, so the kept key is the marker that this was a
      // soft demote we may recover.
      final hasStoredKey =
          await container.read(premiumLicenseServiceProvider).hasStoredKey();
      if (!hasStoredKey) return;

      final promoted =
          await container
              .read(paymentProvider.notifier)
              .reconcileServerEntitlement();
      if (promoted) {
        appLogger.info(
          'Startup self-heal: server confirmed premium for a soft-demoted '
          'device (key preserved) — re-promoted',
        );
        _logLicenseVerifyEvent(
          container,
          result: 'premium',
          reason: 'self_heal_promote',
          source: 'startup_go',
          priorTier: 'free',
          decision: 'keep',
          hadStoredKey: true,
        );
      }
    } catch (e) {
      appLogger.debug('Startup self-heal failed (non-critical): $e');
    }
  }

  /// Fire in-app notification when subscription expires within 7 days.
  /// Uses 24h cooldown (SharedPreferences) to avoid notification spam.
  static Future<void> _checkExpiryWarning(ProviderContainer container) async {
    try {
      final license = container.read(premiumLicenseProvider);

      // Skip: free tier, lifetime plans, already expired, no expiry, or >7 days remaining
      if (license.isFree) return;
      if (license.billingCycle?.isLifetime ?? false) return;
      if (license.expiresAt == null) return;
      if (license.isExpired) return;
      if (license.daysRemaining > 7) return;

      // 24h cooldown: don't show again within 24 hours
      final prefs = await SharedPreferences.getInstance();
      const cooldownKey = 'premium_expiry_warning_shown_date';
      final lastShown = prefs.getString(cooldownKey);
      if (lastShown != null) {
        final lastDate = DateTime.tryParse(lastShown);
        if (lastDate != null &&
            DateTime.now().difference(lastDate).inHours < 24) {
          return;
        }
      }

      // Fire the notification
      container
          .read(notificationCenterServiceProvider)
          .add(
            AppNotificationType.subscriptionExpiryWarning,
            AppLocalizations.premiumExpiryWarningTitle,
            AppLocalizations.premiumExpiryWarningBody(license.daysRemaining),
          );

      // Record cooldown
      await prefs.setString(cooldownKey, DateTime.now().toIso8601String());
      appLogger.info(
        'Subscription expiry warning shown (${license.daysRemaining} days remaining)',
      );
    } catch (e) {
      appLogger.debug('Expiry warning check failed (non-critical): $e');
    }
  }

  /// Fetch active announcements from backend.
  static Future<void> _fetchAnnouncements(ProviderContainer container) async {
    try {
      final backendService = container.read(backendServiceProvider);
      final result = await backendService.getAnnouncements();

      result.when(
        success: (announcements) {
          // Filter active announcements (within startsAt/expiresAt window)
          final now = DateTime.now().toUtc();
          final active =
              announcements.where((a) {
                if (a.startsAt != null) {
                  final start = DateTime.tryParse(a.startsAt!);
                  if (start != null && now.isBefore(start)) return false;
                }
                if (a.expiresAt != null) {
                  final end = DateTime.tryParse(a.expiresAt!);
                  if (end != null && now.isAfter(end)) return false;
                }
                return true;
              }).toList();

          if (active.isNotEmpty) {
            container.read(announcementsProvider.notifier).state = active;
            appLogger.info('Loaded ${active.length} active announcement(s)');
          }
        },
        failure: (e) {
          appLogger.debug('Announcements fetch failed (non-critical): $e');
        },
      );
    } catch (e) {
      appLogger.debug('Announcements error: $e');
    }
  }

  /// Fetch feature flags from backend.
  static Future<void> _fetchFeatureFlags(ProviderContainer container) async {
    try {
      final backendService = container.read(backendServiceProvider);
      final result = await backendService.getFlags();

      result.when(
        success: (flags) {
          container.read(featureFlagsProvider.notifier).state = flags;
          appLogger.debug('Loaded ${flags.length} feature flag(s)');
        },
        failure: (e) {
          appLogger.debug('Feature flags fetch failed (non-critical): $e');
        },
      );
    } catch (e) {
      appLogger.debug('Feature flags error: $e');
    }
  }

  /// Fetch remote config from backend.
  static Future<void> _fetchRemoteConfig(ProviderContainer container) async {
    try {
      final backendService = container.read(backendServiceProvider);
      final result = await backendService.getRemoteConfig();

      result.when(
        success: (config) {
          container.read(remoteConfigProvider.notifier).state = config;
          appLogger.debug('Loaded ${config.length} remote config(s)');
        },
        failure: (e) {
          appLogger.debug('Remote config fetch failed (non-critical): $e');
        },
      );
    } catch (e) {
      appLogger.debug('Remote config error: $e');
    }
  }

  static String _getPlatformName() {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  /// Register URL scheme on Windows and Linux (brand-aware).
  /// macOS is handled via Info.plist + AppDelegate.swift.
  /// Idempotent — safe to run on every launch.
  static Future<void> _registerUrlScheme() async {
    final scheme = BrandConfig.current.urlScheme;
    final appName = BrandConfig.current.appName;

    try {
      if (Platform.isWindows) {
        final exePath = Platform.resolvedExecutable;
        final regKey = 'HKCU\\SOFTWARE\\Classes\\$scheme';
        // Register under HKCU (no admin required)
        await Process.run('reg', [
          'add',
          regKey,
          '/ve',
          '/d',
          'URL:$appName Protocol',
          '/f',
        ]);
        await Process.run('reg', [
          'add',
          regKey,
          '/v',
          'URL Protocol',
          '/d',
          '',
          '/f',
        ]);
        await Process.run('reg', [
          'add',
          '$regKey\\shell\\open\\command',
          '/ve',
          '/d',
          '"$exePath" "%1"',
          '/f',
        ]);
        appLogger.debug('Windows $scheme:// URL scheme registered');
      } else if (Platform.isLinux) {
        final home = Platform.environment['HOME'] ?? '';
        if (home.isEmpty) return;
        final handlerName = '$scheme-handler';
        final desktopFile =
            '$home/.local/share/applications/$handlerName.desktop';
        final exePath = Platform.resolvedExecutable;
        final content =
            '[Desktop Entry]\n'
            'Type=Application\n'
            'Name=$appName\n'
            'Exec=$exePath %u\n'
            'StartupNotify=false\n'
            'MimeType=x-scheme-handler/$scheme;\n'
            'NoDisplay=true\n';
        await File(desktopFile).writeAsString(content);
        await Process.run('xdg-mime', [
          'default',
          '$handlerName.desktop',
          'x-scheme-handler/$scheme',
        ]);
        appLogger.debug('Linux $scheme:// URL scheme registered');
      }
    } catch (e) {
      appLogger.debug('URL scheme registration skipped: $e');
    }
  }

  /// Scan old VidCombo settings files for a stored license key.
  ///
  /// The old VidCombo app (Flutter/ObjectBox) stored its settings in JSON
  /// files named `settings1.gs` / `settings1.bak` at the platform's
  /// application support directory (`com.tinasoft.vidcombo`). The license
  /// key is in the `lisenceKey` field (sic — typo in original app).
  ///
  /// Returns the 32-char hex license key, or null if not found.
  static Future<String?> _importLegacyLicenseKey() async {
    if (BrandConfig.current.brand != Brand.vidcombo) return null;

    // On Windows, the Inno Setup installer extracts the license key from old
    // VidCombo settings files BEFORE uninstalling the old app (which deletes
    // those files). The key is saved to %TEMP%\vidcombo_migrated_key.txt.
    // Check this file first — the original settings files are likely gone.
    if (Platform.isWindows) {
      final tempDir =
          Platform.environment['TEMP'] ?? Platform.environment['TMP'] ?? '';
      if (tempDir.isNotEmpty) {
        final migratedKeyFile = File(
          p.join(tempDir, 'vidcombo_migrated_key.txt'),
        );
        try {
          if (await migratedKeyFile.exists()) {
            final key = (await migratedKeyFile.readAsString()).trim();
            if (key.length == 32 &&
                RegExp(r'^[0-9A-Fa-f]{32}$').hasMatch(key)) {
              appLogger.info(
                '[VidCombo] Found migrated license key from installer',
              );
              // Clean up temp file after reading
              try {
                await migratedKeyFile.delete();
              } catch (_) {}
              return key;
            }
          }
        } catch (_) {
          // Non-critical — fall through to directory scan.
        }
      }
    }

    // Fallback: scan original settings directories (works on macOS where
    // there's no installer-driven uninstall, and on Windows if the temp
    // file is missing for any reason).
    final candidates = <String>[];

    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ?? '';
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
      // Old BLUEBYTE VidCombo used varying VERSIONINFO across builds, so
      // path_provider returned different directories on each machine.
      // Confirmed paths from real Windows machines:
      //   %APPDATA%\com.VidCombo\VidCombo\settings1.gs
      //   %APPDATA%\VidCombo Youtube Downloader\VidCombo Youtube Downloader\settings1.gs
      if (appData.isNotEmpty) {
        candidates.add(p.join(appData, 'com.VidCombo', 'VidCombo'));
        candidates.add(
          p.join(
            appData,
            'VidCombo Youtube Downloader',
            'VidCombo Youtube Downloader',
          ),
        );
        candidates.add(p.join(appData, 'VidCombo Youtube Downloader'));
        candidates.add(p.join(appData, 'com.tinasoft.vidcombo'));
        candidates.add(p.join(appData, 'VidCombo', 'VidCombo'));
        candidates.add(p.join(appData, 'VidCombo'));
        candidates.add(p.join(appData, 'Vidcombo', 'Vidcombo'));
        candidates.add(p.join(appData, 'Vidcombo'));
      }
      if (localAppData.isNotEmpty) {
        candidates.add(p.join(localAppData, 'com.VidCombo', 'VidCombo'));
        candidates.add(p.join(localAppData, 'com.tinasoft.vidcombo'));
        candidates.add(p.join(localAppData, 'Programs', 'VidCombo'));
      }
    } else if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      if (home.isNotEmpty) {
        candidates.add(
          p.join(
            home,
            'Library',
            'Application Support',
            'com.tinasoft.vidcombo',
          ),
        );
      }
    }

    return scanDirsForLegacyKey(candidates);
  }

  /// Scan a list of directories for old VidCombo settings files containing
  /// a valid 32-char hex license key. Returns the first valid key found.
  @visibleForTesting
  static Future<String?> scanDirsForLegacyKey(List<String> dirs) async {
    for (final dir in dirs) {
      for (final name in [
        'settings1.gs',
        'settings1.bak',
        'settings.gs',
        'settings.bak',
        'settings.json',
      ]) {
        try {
          final file = File(p.join(dir, name));
          if (!await file.exists()) continue;

          final content = await file.readAsString();
          final json = jsonDecode(content) as Map<String, dynamic>;
          final key = json['lisenceKey'] as String?;

          if (key != null &&
              key.length == 32 &&
              RegExp(r'^[0-9A-Fa-f]{32}$').hasMatch(key)) {
            appLogger.info(
              '[VidCombo] Found legacy license key in ${p.join(dir, name)}',
            );
            return key;
          }
        } catch (_) {
          // Non-critical — file missing, unreadable, or not valid JSON.
        }
      }
    }

    return null;
  }

  /// VidCombo checkkey wrapper for silent-demotion detection.
  ///
  /// If [isPremiumProvider] currently reports true (i.e. the user was on
  /// premium *before* this round-trip) and the backend now says they
  /// aren't, we:
  ///   1. Deactivate the local license (revokes premium features).
  ///   2. Reset the free-tier download quota counter.
  ///   3. Push a user-facing notification so they aren't paywalled with
  ///      zero explanation on the very next action.
  ///
  /// If the user was already free-tier, this is a no-op — we never fire a
  /// "premium removed" toast on someone who never had it.
  ///
  /// [definitive] gates whether the stored license KEY is wiped. PHP
  /// checkkey.php returns `inactive`/`invalid` for both genuine revokes and
  /// transient renewal-lag/expired states — it is NOT a definitive revoke
  /// signal — so the default is a soft demote that PRESERVES the key, letting
  /// an active auto-renew subscriber auto-recover when the backend
  /// re-confirms. Only pass `definitive: true` when the server verdict is an
  /// unambiguous revoke. INVARIANT #1.
  static Future<void> _maybeNotifyDemotion(
    ProviderContainer container, {
    String? serverMessage,
    bool definitive = false,
    String? source,
    String? priorTier,
    bool? responseIsValid,
    String? responseReason,
    bool? hadStoredKey,
    bool suppressNotification = false,
  }) async {
    try {
      final wasPremiumLocally = container.read(isPremiumProvider);
      if (!wasPremiumLocally) return;

      final premiumNotifier = container.read(premiumLicenseProvider.notifier);
      final quotaNotifier = container.read(
        downloadQuotaNotifierProvider.notifier,
      );
      final demoteResult = demoteResultForSignal(definitive: definitive);
      if (demoteResult == 'full_demote') {
        // DEFINITIVE server revoke → full wipe including the key.
        await premiumNotifier.deactivateLicense(quotaNotifier: quotaNotifier);
      } else {
        // UNCERTAIN demote (PHP inactive/expired/renewal-lag) → soft demote:
        // drop premium but KEEP the key so the user auto-recovers. INVARIANT #1.
        await premiumNotifier.softDeactivateLicense(
          quotaNotifier: quotaNotifier,
        );
      }
      _logLicenseVerifyEvent(
        container,
        result: demoteResult,
        reason: serverMessage,
        source: source,
        priorTier: priorTier ?? (wasPremiumLocally ? 'premium' : 'free'),
        responseIsValid: responseIsValid,
        responseReason: responseReason,
        decision: demoteResult == 'full_demote' ? 'full' : 'soft',
        hadStoredKey: hadStoredKey,
      );
      // Suppress the user-facing toast when the demote source is a bg-refresh
      // that contradicts a same-boot cache hit (FIX #5): the user already saw
      // premium this boot, so a contradicting bg demote should self-heal next
      // boot, not flash a confusing "Premium Deactivated" notification.
      if (!suppressNotification) {
        _pushDemotionNotification(container, serverMessage: serverMessage);
      }
    } catch (e) {
      appLogger.warning('Demotion handling failed (non-critical): $e');
    }
  }

  /// Derive the legacy BLUEBYTE braced-uppercase device id from a raw
  /// platform UUID, or `null` when the input is null/empty or already braced
  /// (so the caller skips a pointless retry against the same id).
  ///
  /// Pure + [@visibleForTesting] so the format derivation that BOTH the SYNC
  /// and background-refresh recovery paths depend on is pinned without a real
  /// adapter or network. The braces + uppercase are load-bearing: the PHP
  /// backend may use a case-sensitive MySQL collation / utf8_bin column.
  @visibleForTesting
  static String? bracedDeviceIdFor(String? rawDeviceId) {
    final rawId = rawDeviceId;
    if (rawId == null || rawId.isEmpty || rawId.startsWith('{')) return null;
    return '{${rawId.toUpperCase()}}';
  }

  /// BLUEBYTE braced-device-id recovery probe for VidCombo checkkey.
  ///
  /// The legacy BLUEBYTE VidCombo registered devices under the Windows GUID
  /// format `{UPPERCASE-GUID}` (with braces), while our raw platform UUID is
  /// lowercase-without-braces. When a checkkey response says non-premium,
  /// retry once with the braced-uppercase form to recover a legacy premium
  /// record before any demotion.
  ///
  /// Returns the recovered PREMIUM response, or `null` when no recovery
  /// applies (already braced, recovery still non-premium, or error). Shared by
  /// the SYNC path and the background-refresh path so both demote on the SAME
  /// evidence — without this, a legacy braced-device subscriber got a
  /// deterministic premium-then-demote on every cache-hit boot (FIX #5).
  static Future<VidComboCheckKeyResponse?> _retryBracedDeviceCheckKey(
    ProviderContainer container, {
    required String? rawDeviceId,
  }) async {
    final bracedId = bracedDeviceIdFor(rawDeviceId);
    if (bracedId == null) return null;

    appLogger.info(
      '[VidCombo] checkkey returned non-premium, '
      'retrying with BLUEBYTE device_id format: $bracedId',
    );
    safeBreadcrumb(
      container.read(errorReporterServiceProvider),
      'vidcombo_bluebyte_retry_attempt',
    );
    final retryAdapter = VidComboBackendAdapter(
      deviceId: bracedId,
      errorReporter: container.read(errorReporterServiceProvider),
    );
    try {
      final retryResult = await retryAdapter.checkKey();
      if (retryResult.isPremium) {
        appLogger.info(
          '[VidCombo] Recovered premium via BLUEBYTE device_id fallback',
        );
        safeBreadcrumb(
          container.read(errorReporterServiceProvider),
          'vidcombo_bluebyte_retry_recovered',
        );
        return retryResult;
      }
      safeBreadcrumb(
        container.read(errorReporterServiceProvider),
        'vidcombo_bluebyte_retry_not_premium',
      );
      return null;
    } catch (e) {
      appLogger.debug('[VidCombo] BLUEBYTE device_id fallback failed: $e');
      safeBreadcrumb(
        container.read(errorReporterServiceProvider),
        'vidcombo_bluebyte_retry_error',
        data: {'error_type': e.runtimeType.toString()},
      );
      return null;
    }
  }

  /// Pure routing decision for a premium demotion signal. Returns the
  /// telemetry/result label that also selects the deactivation path:
  ///   * `'full_demote'` — DEFINITIVE server revoke (reason=='revoked' / tier
  ///     free): full wipe INCLUDING the stored key.
  ///   * `'soft_demote'` — every UNCERTAIN signal (expired / network / grace /
  ///     format-corrupt / unknown / PHP inactive): drop premium but PRESERVE
  ///     the key so an active auto-renew subscriber auto-recovers when the
  ///     backend re-confirms. INVARIANT #1.
  ///
  /// Isolated for unit test so the never-wipe-on-uncertain contract is pinned
  /// without a ProviderContainer harness.
  @visibleForTesting
  static String demoteResultForSignal({required bool definitive}) =>
      definitive ? 'full_demote' : 'soft_demote';

  /// Emit a lightweight analytics event for every license-verification
  /// decision (startup activation + each demotion path), so the whole
  /// premium/license class is observable in production. Uses the existing
  /// [AnalyticsService.track] string-name + map mechanism — no generated
  /// types. Fire-and-forget; never throws into the startup flow.
  ///
  /// [result] is one of: premium / free / soft_demote / full_demote.
  ///
  /// Enrichment (so a server verdict can be told apart from an offline/
  /// transport demote — today every row carries reason=none):
  ///   * [source] — which sink emitted (startup_go / vidcombo_sync /
  ///     vidcombo_bg / cadence_periodic / cadence_resume).
  ///   * [priorTier] — the local tier BEFORE this decision (free / premium),
  ///     derived from the `wasPremiumLocally` bool the demote sinks compute.
  ///   * [responseHttpStatus] / [responseIsValid] / [responseReason] — the raw
  ///     server verdict, distinguishing a 4xx/200 is_valid=false demote from an
  ///     offline/transport one.
  ///   * [decision] — soft / full / keep (the keep/offline_grace branch now
  ///     emits explicitly instead of going dark).
  ///   * [hadStoredKey] — whether a license key was stored at decision time.
  ///
  /// ABSOLUTELY NO license key (raw or masked) is ever placed in the payload.
  static void _logLicenseVerifyEvent(
    ProviderContainer container, {
    required String result,
    String? reason,
    int? httpStatus,
    bool? coldStart,
    String? source,
    String? priorTier,
    int? responseHttpStatus,
    bool? responseIsValid,
    String? responseReason,
    String? decision,
    bool? hadStoredKey,
  }) {
    try {
      final trimmedResponseReason = responseReason?.trim();
      container.read(analyticsServiceProvider).track('license_verify', {
        'brand': BrandConfig.current.brand.name,
        'result': result,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        if (httpStatus != null) 'http_status': httpStatus,
        if (coldStart != null) 'cold_start': coldStart,
        if (source != null && source.isNotEmpty) 'source': source,
        if (priorTier != null && priorTier.isNotEmpty) 'prior_tier': priorTier,
        if (responseHttpStatus != null)
          'response_http_status': responseHttpStatus,
        if (responseIsValid != null) 'response_is_valid': responseIsValid,
        if (trimmedResponseReason != null && trimmedResponseReason.isNotEmpty)
          'response_reason': trimmedResponseReason,
        if (decision != null && decision.isNotEmpty) 'decision': decision,
        if (hadStoredKey != null) 'had_stored_key': hadStoredKey,
      });
    } catch (e) {
      appLogger.debug('license_verify analytics emit failed: $e');
    }
  }

  /// Adds an in-app notification telling the user why their premium
  /// features have just been revoked. Safe to call from any startup path.
  static void _pushDemotionNotification(
    ProviderContainer container, {
    String? serverMessage,
  }) {
    try {
      final trimmed = serverMessage?.trim();
      final body =
          (trimmed != null && trimmed.isNotEmpty)
              ? trimmed
              : 'Your premium license is no longer active. '
                  'Open the Premium tab for details.';
      container
          .read(notificationCenterServiceProvider)
          .add(
            AppNotificationType.licenseDeactivated,
            'Premium Deactivated',
            body,
          );
      appLogger.info('Silent-demotion notification pushed: $body');
    } catch (e) {
      appLogger.debug('Demotion notification push failed: $e');
    }
  }

  /// Whether a license key was created by the Go backend vs the PHP backend
  /// (32-char hex). Go backend generates brand-aware keys:
  ///   - SSvid:    `SSVID-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX`    (45 chars)
  ///   - VidCombo: `VIDCOMBO-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX`  (48 chars)
  ///   - Legacy:   `SSVID-...` keys created before brand separation also match
  static bool _isGoBackendLicense(String key) {
    if (key.startsWith('SSVID-') && key.length == 45) return true;
    if (key.startsWith('VIDCOMBO-') && key.length == 48) return true;
    return false;
  }

  /// Whether a stored credential should be wiped when the VidCombo installer
  /// marker triggers a state reset. Pure decision logic, isolated for test.
  ///
  /// The marker handshake (Inno writes `%TEMP%\vidcombo_installer_ran.txt`,
  /// startup detects it and resets migration state) is for clearing legacy
  /// 32-hex PHP keys so the migrated-key file the installer just produced
  /// can be re-imported into credentials. It must NOT wipe Go-backend keys
  /// (SSVID-*/VIDCOMBO-*) created by in-app Stripe payment — those have no
  /// migration handoff and silent removal demotes the user on every update.
  ///
  /// Rules:
  ///   - null / empty       → wipe (nothing to lose, no-op in practice)
  ///   - 32-char hex (PHP)  → wipe (installer is about to re-supply this)
  ///   - SSVID-*  (45 char) → preserve (Go backend, Stripe)
  ///   - VIDCOMBO-* (48 ch) → preserve (Go backend, Stripe)
  ///   - other format       → preserve as fail-safe; user-driven deactivate
  ///     flow remains the explicit clear path.
  @visibleForTesting
  static bool shouldWipeCredentialOnMarkerReset(String? existingKey) {
    if (existingKey == null || existingKey.isEmpty) return true;
    if (_isGoBackendLicense(existingKey)) return false;
    if (existingKey.length == 32 &&
        RegExp(r'^[0-9A-Fa-f]{32}$').hasMatch(existingKey)) {
      return true;
    }
    return false;
  }

  /// Verify a Go-backend-created license for VidCombo users.
  ///
  /// When VidCombo users purchase through in-app Stripe, the Go backend
  /// creates the subscription + license. PHP checkkey.php doesn't know
  /// about these keys. This method verifies directly with Go backend
  /// and activates locally if valid.
  ///
  /// Returns true if the license is confirmed premium by Go backend.
  /// On network failure, trusts local premium state (offline grace).
  static Future<bool> _verifyGoLicenseForVidCombo(
    ProviderContainer container,
    String licenseKey,
  ) async {
    try {
      final client = container.read(backendClientProvider);
      final response = await client.post<LicenseVerificationResponse>(
        '/premium/licenses/verify',
        data: {'key': licenseKey},
        fromJson:
            (json) => LicenseVerificationResponse.fromJson(
              json as Map<String, dynamic>,
            ),
      );

      if (response.isValid) {
        final premiumNotifier = container.read(premiumLicenseProvider.notifier);
        final billingCycle =
            response.billingCycle != null
                ? BillingCycle.fromString(response.billingCycle!)
                : null;
        await premiumNotifier.activateLicenseFromBackend(
          licenseKey,
          billingCycle: billingCycle?.name,
          expiresAt: response.expiresAt,
          isAutoRenew: response.isAutoRenew,
        );
        appLogger.info(
          '[VidCombo] Go-backend premium verified '
          '(cycle: ${billingCycle?.name}, '
          'expires: ${response.expiresAt})',
        );
        return true;
      }

      appLogger.info(
        '[VidCombo] Go-backend license invalid: ${response.reason}',
      );
      return false;
    } catch (e) {
      appLogger.debug(
        '[VidCombo] Go-backend verification failed (network): $e',
      );
      // Network error — trust local premium state during offline grace.
      // The periodic verification service handles grace period expiry.
      return container.read(isPremiumProvider);
    }
  }

  /// Listen for deep-link license activation results and show UI feedback.
  static void _listenForActivation(
    LicenseActivationHandler handler,
    ProviderContainer container,
  ) {
    handler.activationResults.listen((result) {
      try {
        final notificationService = container.read(
          notificationCenterServiceProvider,
        );
        switch (result.status) {
          case ActivationStatus.success:
            notificationService.add(
              AppNotificationType.licenseActivated,
              'License Activated',
              'Your premium license has been activated successfully.',
            );
          case ActivationStatus.successOffline:
            notificationService.add(
              AppNotificationType.licenseActivated,
              'License Activated (Offline)',
              'License activated locally. Will verify with server when online.',
            );
          case ActivationStatus.invalidKey:
            notificationService.add(
              AppNotificationType.licenseActivationFailed,
              'Invalid License Key',
              'The license key from the deep link is invalid or malformed.',
            );
          case ActivationStatus.rejected:
            notificationService.add(
              AppNotificationType.licenseActivationFailed,
              'License Rejected',
              result.reason ?? 'The server rejected this license key.',
            );
        }
      } catch (e) {
        appLogger.debug('Activation notification failed: $e');
      }
    });
  }

  /// Persist a premium checkkey.php response so the next launch can
  /// activate premium features instantly without the PHP round-trip.
  /// Caller controls `verifiedAt` (defaults to [DateTime.now]) so tests
  /// can inject a deterministic clock.
  ///
  /// Format: single JSON blob under [_vidComboCheckKeyCacheKey]. Only the
  /// fields premium activation needs (license_key, status, count_free,
  /// plan, end_date) plus a `verified_at_ms` epoch for TTL checks. We
  /// deliberately omit the `message` field so a stale demotion warning
  /// cannot surface on the fast path.
  @visibleForTesting
  static Future<void> writeVidComboCheckKeyCache(
    SharedPreferences prefs,
    VidComboCheckKeyResponse response, {
    DateTime? verifiedAt,
  }) async {
    final stamp = (verifiedAt ?? DateTime.now()).toUtc();
    final payload = <String, dynamic>{
      'license_key': response.licenseKey,
      'status': response.status,
      'count_free': response.countFree,
      'plan': response.plan,
      'end_date': response.endDate,
      'verified_at_ms': stamp.millisecondsSinceEpoch,
    };
    await prefs.setString(_vidComboCheckKeyCacheKey, jsonEncode(payload));
  }

  /// Read a cached checkkey.php response if it is still within TTL.
  /// Returns `null` on cache miss, parse error, or age > TTL. The helper
  /// is static + pure so it is exercised directly by unit tests; the
  /// caller performs all the premium-side-effects afterwards.
  @visibleForTesting
  static VidComboCheckKeyResponse? readVidComboCheckKeyCache(
    SharedPreferences prefs, {
    DateTime? now,
  }) {
    final raw = prefs.getString(_vidComboCheckKeyCacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final verifiedAtMs = decoded['verified_at_ms'];
      if (verifiedAtMs is! int) return null;
      final verifiedAt = DateTime.fromMillisecondsSinceEpoch(
        verifiedAtMs,
        isUtc: true,
      );
      final stamp = (now ?? DateTime.now()).toUtc();
      if (stamp.difference(verifiedAt) >= _vidComboCheckKeyCacheTtl) {
        return null;
      }
      final rawCountFree = decoded['count_free'];
      return VidComboCheckKeyResponse(
        licenseKey: decoded['license_key'] as String?,
        status: decoded['status'] as String? ?? 'invalid',
        endDate: decoded['end_date'] as String?,
        countFree: rawCountFree is int ? rawCountFree : 0,
        plan: decoded['plan'] as String?,
      );
    } catch (_) {
      // Malformed cache (older version, truncated string, etc.) — drop and
      // fall back to a full PHP check.
      return null;
    }
  }

  /// Clear the VidCombo checkkey cache. Brand-agnostic helper exposed so
  /// non-startup code paths (user-initiated deactivate in premium_members_screen)
  /// can purge stale premium state without reaching for the private key.
  ///
  /// SSvid callers are no-op (this is VidCombo-only state).
  static Future<void> clearVidComboCheckKeyCache(
    SharedPreferences prefs,
  ) async {
    await prefs.remove(_vidComboCheckKeyCacheKey);
  }

  /// Whether the user has explicitly deactivated premium on this VidCombo
  /// device. While true, the legacy-key file scan in [_importLegacyLicenseKey]
  /// short-circuits to null so a residual `settings1.gs` cannot silently
  /// re-activate the user.
  ///
  /// Returns false unconditionally for non-VidCombo brands.
  static bool hasVidComboDeactivateTombstone(SharedPreferences prefs) {
    if (BrandConfig.current.backendType != BackendType.php) return false;
    return prefs.getBool(_vidComboUserDeactivatedKey) ?? false;
  }

  /// Set the user-deactivated tombstone. Caller MUST gate this on an
  /// explicit user action (e.g., the Deactivate button in
  /// premium_members_screen). NEVER call from backend-driven demotion paths
  /// — server-driven state changes are not user intent.
  ///
  /// No-op for non-VidCombo brands.
  static Future<void> setVidComboDeactivateTombstone(
    SharedPreferences prefs,
  ) async {
    if (BrandConfig.current.backendType != BackendType.php) return;
    await prefs.setBool(_vidComboUserDeactivatedKey, true);
  }

  /// Clear the user-deactivated tombstone. Must be called on EVERY explicit
  /// re-activation path: manual key paste, restore-by-email success,
  /// payment success (Stripe/crypto), deep-link activation. Missing any
  /// of these paths leaves the user unable to re-activate via that route.
  ///
  /// No-op for non-VidCombo brands.
  static Future<void> clearVidComboDeactivateTombstone(
    SharedPreferences prefs,
  ) async {
    if (BrandConfig.current.backendType != BackendType.php) return;
    await prefs.remove(_vidComboUserDeactivatedKey);
  }

  /// Action to take when the background cache-warming refresh returns.
  ///
  /// Pure decision separated from I/O so the demotion-on-revoke contract
  /// can be exercised without spinning up a real ProviderContainer or PHP
  /// backend. Mirrors the synchronous demotion path in [_initializeVidCombo]
  /// so phantom-premium for the current session never outlives a remote
  /// revoke.
  @visibleForTesting
  static BackgroundRefreshDecision decideBackgroundRefreshAction({
    required bool freshIsPremium,
    required String? freshMessage,
    required String? storedLicenseKey,
    required bool isStoredKeyGoBackend,
    required bool goBackendStillValid,
  }) {
    if (freshIsPremium) {
      return const BackgroundRefreshDecision(
        action: BackgroundRefreshAction.writeFreshCache,
      );
    }
    // Defense in depth: a Stripe-issued Go-backend license is not
    // recognized by the PHP checkkey endpoint, so PHP "inactive" alone
    // must not trigger demotion. Trust the Go verification when applicable.
    if (storedLicenseKey != null &&
        isStoredKeyGoBackend &&
        goBackendStillValid) {
      return const BackgroundRefreshDecision(
        action: BackgroundRefreshAction.keepCache,
      );
    }
    return BackgroundRefreshDecision(
      action: BackgroundRefreshAction.demote,
      serverMessage: freshMessage,
      hadGoLicense: isStoredKeyGoBackend,
    );
  }
}

/// Outcome of [StartupService.decideBackgroundRefreshAction].
enum BackgroundRefreshAction {
  /// Backend confirms premium — overwrite cache with the fresh response.
  writeFreshCache,

  /// PHP says inactive but a Go-backend license is still valid; keep the
  /// existing cache and do NOT demote.
  keepCache,

  /// Genuine demotion — drop cache, deactivate license locally, notify.
  demote,
}

/// Bundled outcome from [StartupService.decideBackgroundRefreshAction] so
/// callers can act on the decision without re-deriving any context.
class BackgroundRefreshDecision {
  final BackgroundRefreshAction action;
  final String? serverMessage;
  final bool hadGoLicense;

  const BackgroundRefreshDecision({
    required this.action,
    this.serverMessage,
    this.hadGoLicense = false,
  });
}
