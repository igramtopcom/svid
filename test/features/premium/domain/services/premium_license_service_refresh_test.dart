import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svid/core/network/backend_client.dart';
import 'package:svid/core/services/secure_credential_store.dart';
import 'package:svid/features/premium/data/datasources/premium_local_datasource.dart';
import 'package:svid/features/premium/data/services/license_verification_service.dart';
import 'package:svid/features/premium/domain/entities/premium_feature.dart';
import 'package:svid/features/premium/domain/entities/premium_license.dart';
import 'package:svid/features/premium/domain/entities/premium_tier.dart';
import 'package:svid/features/premium/domain/services/premium_license_service.dart';
import 'package:svid/features/premium/presentation/providers/premium_providers.dart';

import '../../../../helpers/brand_test_keys.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeSecureStorage {
  final Map<String, String> _store = {};
  Future<String?> read({required String key}) async => _store[key];
  Future<void> write({required String key, required String value}) async =>
      _store[key] = value;
  Future<void> delete({required String key}) async => _store.remove(key);
}

class _TestDatasource extends PremiumLocalDatasource {
  final _FakeSecureStorage _secure = _FakeSecureStorage();
  _TestDatasource(SharedPreferences prefs)
    : super(prefs, SecureCredentialStore(prefs));

  @override
  Future<String?> getLicenseKey() async =>
      _secure.read(key: 'premium_license_key');
  @override
  Future<void> saveLicenseKey(String key) async =>
      _secure.write(key: 'premium_license_key', value: key);
  @override
  Future<void> deleteLicenseKey() async =>
      _secure.delete(key: 'premium_license_key');
}

/// [LicenseVerificationService] that delegates [verify] to an injected callback.
/// Uses real deps for the super constructor (never accessed since verify() is overridden).
class _FakeLicenseVerificationService extends LicenseVerificationService {
  final Future<VerificationResult> Function() _verifyFn;

  _FakeLicenseVerificationService(
    this._verifyFn, {
    required PremiumLicenseService licenseService,
    required SharedPreferences prefs,
  }) : super(BackendClient(SecureCredentialStore(prefs)), licenseService);

  @override
  Future<VerificationResult> verify({DateTime? now}) async => _verifyFn();
}

// ── Helpers ───────────────────────────────────────────────────────────────────

PremiumLicense _premiumLicense({DateTime? expiresAt}) {
  return PremiumLicense(
    tier: PremiumTier.premium,
    licenseKey: TestLicenseKeys.valid,
    purchaseDate: DateTime(2026, 1, 1),
    lastVerified: DateTime.now(),
    billingCycle: BillingCycle.monthly,
    expiresAt: expiresAt,
  );
}

_FakeLicenseVerificationService _makeFake(
  Future<VerificationResult> Function() fn,
  PremiumLicenseService svc,
  SharedPreferences p,
) => _FakeLicenseVerificationService(fn, licenseService: svc, prefs: p);

Future<SharedPreferences> _freshPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late SharedPreferences prefs;
  late _TestDatasource datasource;
  late PremiumLicenseService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    datasource = _TestDatasource(prefs);
    service = PremiumLicenseService(datasource);
  });

  // ── Grace period ───────────────────────────────────────────────────────────

  group('isFeatureAvailable — 7-day grace period', () {
    test('active subscription → true', () {
      final license = _premiumLicense(
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      );
      expect(
        service.isFeatureAvailable(PremiumFeature.smartCollections, license),
        true,
      );
    });

    test('expired 1 day ago → true (within 7-day grace)', () {
      final license = _premiumLicense(
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(
        service.isFeatureAvailable(PremiumFeature.smartCollections, license),
        true,
      );
    });

    test('expired exactly 7 days ago → true (boundary inclusive)', () {
      final now = DateTime(2026, 3, 10, 12);
      final license = _premiumLicense(
        expiresAt: now.subtract(const Duration(days: 7)),
      );
      expect(
        service.isFeatureAvailable(
          PremiumFeature.smartCollections,
          license,
          now: now,
        ),
        true,
      );
    });

    test('expired 8 days ago → false (outside grace window)', () {
      final now = DateTime(2026, 3, 10, 12);
      final license = _premiumLicense(
        expiresAt: now.subtract(const Duration(days: 8)),
      );
      expect(
        service.isFeatureAvailable(
          PremiumFeature.smartCollections,
          license,
          now: now,
        ),
        false,
      );
    });

    test('expired 30 days ago → false', () {
      final license = _premiumLicense(
        expiresAt: DateTime.now().subtract(const Duration(days: 30)),
      );
      expect(
        service.isFeatureAvailable(PremiumFeature.highQuality4K, license),
        false,
      );
    });

    test('free tier → false regardless of expiresAt', () {
      expect(
        service.isFeatureAvailable(
          PremiumFeature.smartCollections,
          PremiumLicense.free,
        ),
        false,
      );
    });

    test('premium with no expiresAt → true (perpetual)', () {
      final license = _premiumLicense(expiresAt: null);
      expect(
        service.isFeatureAvailable(PremiumFeature.browserShield, license),
        true,
      );
    });

    test('gracePeriodAfterExpiryDays constant is 7', () {
      expect(PremiumLicenseService.gracePeriodAfterExpiryDays, 7);
    });

    test('injectable now controls grace boundary precisely', () {
      final expiry = DateTime(2026, 1, 1);
      final license = _premiumLicense(expiresAt: expiry);

      // 6 days in grace → accessible
      expect(
        service.isFeatureAvailable(
          PremiumFeature.smartCollections,
          license,
          now: DateTime(2026, 1, 7),
        ),
        true,
      );
      // 8 days → locked
      expect(
        service.isFeatureAvailable(
          PremiumFeature.smartCollections,
          license,
          now: DateTime(2026, 1, 9),
        ),
        false,
      );
    });
  });

  // ── PremiumNotifier.refreshLicense ────────────────────────────────────────

  group('PremiumNotifier.refreshLicense', () {
    setUp(() async {
      // Pre-load premium license so notifier starts as premium.
      await service.activateLicense(
        TestLicenseKeys.valid,
        paymentMethod: 'stripe',
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      );
    });

    test('no-op when called on free-tier notifier', () async {
      final emptyPrefs = await _freshPrefs();
      final emptyService = PremiumLicenseService(_TestDatasource(emptyPrefs));
      final notifier = PremiumNotifier(emptyService);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.isFree, true);

      var verifyCalled = false;
      final fake = _makeFake(
        () async {
          verifyCalled = true;
          return VerificationResult.success;
        },
        emptyService,
        emptyPrefs,
      );
      await notifier.refreshLicense(
        verificationService: fake,
        prefs: emptyPrefs,
      );
      expect(verifyCalled, false);
    });

    test('skips backend call for free users', () async {
      final emptyPrefs = await _freshPrefs();
      final emptyService = PremiumLicenseService(_TestDatasource(emptyPrefs));

      var verifyCalled = false;
      final fake = _makeFake(
        () async {
          verifyCalled = true;
          return VerificationResult.success;
        },
        emptyService,
        emptyPrefs,
      );

      final notifier = PremiumNotifier(emptyService);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.isFree, true);

      await notifier.refreshLicense(
        verificationService: fake,
        prefs: emptyPrefs,
      );
      expect(verifyCalled, false);
    });

    test('calls backend if premium and no cached timestamp', () async {
      var verifyCalled = false;
      final fake = _makeFake(
        () async {
          verifyCalled = true;
          return VerificationResult.success;
        },
        service,
        prefs,
      );

      final notifier = PremiumNotifier(service);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.isPremium, true);

      await notifier.refreshLicense(verificationService: fake, prefs: prefs);
      expect(verifyCalled, true);
    });

    test('skips backend if last refresh was <24h ago', () async {
      await prefs.setString(
        PremiumNotifier.lastRefreshKeyForTest,
        DateTime.now().subtract(const Duration(hours: 23)).toIso8601String(),
      );

      var verifyCalled = false;
      final fake = _makeFake(
        () async {
          verifyCalled = true;
          return VerificationResult.success;
        },
        service,
        prefs,
      );

      final notifier = PremiumNotifier(service);
      await Future<void>.delayed(Duration.zero);

      await notifier.refreshLicense(verificationService: fake, prefs: prefs);
      expect(verifyCalled, false);
    });

    test(
      'ignoreCooldown bypasses cached timestamp for in-session entitlement checks',
      () async {
        await prefs.setString(
          PremiumNotifier.lastRefreshKeyForTest,
          DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
        );

        var verifyCalled = false;
        final fake = _makeFake(
          () async {
            verifyCalled = true;
            return VerificationResult.success;
          },
          service,
          prefs,
        );

        final notifier = PremiumNotifier(service);
        await Future<void>.delayed(Duration.zero);

        await notifier.refreshLicense(
          verificationService: fake,
          prefs: prefs,
          ignoreCooldown: true,
        );
        expect(verifyCalled, true);
      },
    );

    test('calls backend if last refresh was >24h ago', () async {
      await prefs.setString(
        PremiumNotifier.lastRefreshKeyForTest,
        DateTime.now().subtract(const Duration(hours: 25)).toIso8601String(),
      );

      var verifyCalled = false;
      final fake = _makeFake(
        () async {
          verifyCalled = true;
          return VerificationResult.success;
        },
        service,
        prefs,
      );

      final notifier = PremiumNotifier(service);
      await Future<void>.delayed(Duration.zero);

      await notifier.refreshLicense(verificationService: fake, prefs: prefs);
      expect(verifyCalled, true);
    });

    test('deactivates license when shouldDeactivate=true', () async {
      final fake = _makeFake(
        () async => const VerificationResult(
          verified: false,
          shouldDeactivate: true,
          reason: 'revoked',
          definitive: true,
        ),
        service,
        prefs,
      );

      final notifier = PremiumNotifier(service);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.isPremium, true);

      await notifier.refreshLicense(verificationService: fake, prefs: prefs);
      expect(notifier.state.isFree, true);
    });

    test('DEFINITIVE revoke → full wipe (key deleted)', () async {
      // Sanity: key is present after setUp activation.
      expect(await datasource.getLicenseKey(), TestLicenseKeys.valid);

      final fake = _makeFake(
        () async => const VerificationResult(
          verified: false,
          shouldDeactivate: true,
          reason: 'revoked',
          definitive: true,
        ),
        service,
        prefs,
      );

      final notifier = PremiumNotifier(service);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.isPremium, true);

      await notifier.refreshLicense(verificationService: fake, prefs: prefs);

      expect(notifier.state.isFree, true);
      // Definitive revoke wipes the key.
      expect(await datasource.getLicenseKey(), isNull);
    });

    test('UNCERTAIN demote (expired) → soft, key PRESERVED', () async {
      expect(await datasource.getLicenseKey(), TestLicenseKeys.valid);

      final fake = _makeFake(
        () async => const VerificationResult(
          verified: false,
          shouldDeactivate: true,
          reason: 'subscription_expired',
          // definitive defaults to false (uncertain).
        ),
        service,
        prefs,
      );

      final notifier = PremiumNotifier(service);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.isPremium, true);

      await notifier.refreshLicense(verificationService: fake, prefs: prefs);

      // Demoted to free locally...
      expect(notifier.state.isFree, true);
      // ...but the key MUST survive so renewal auto-recovers premium.
      expect(await datasource.getLicenseKey(), TestLicenseKeys.valid);
    });

    test('UNCERTAIN demote (grace_period_expired) → key PRESERVED', () async {
      final fake = _makeFake(
        () async => VerificationResult.offlineExpired,
        service,
        prefs,
      );

      final notifier = PremiumNotifier(service);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.isPremium, true);

      await notifier.refreshLicense(verificationService: fake, prefs: prefs);

      expect(notifier.state.isFree, true);
      expect(await datasource.getLicenseKey(), TestLicenseKeys.valid);
    });

    test('updates cache timestamp after successful refresh', () async {
      final before = DateTime.now();
      final fake = _makeFake(
        () async => VerificationResult.success,
        service,
        prefs,
      );

      final notifier = PremiumNotifier(service);
      await Future<void>.delayed(Duration.zero);
      await notifier.refreshLicense(verificationService: fake, prefs: prefs);

      final cached = prefs.getString(PremiumNotifier.lastRefreshKeyForTest);
      expect(cached, isNotNull);
      expect(
        DateTime.parse(
          cached!,
        ).isAfter(before.subtract(const Duration(seconds: 2))),
        true,
      );
    });

    test('does not crash on network error (startup must not fail)', () async {
      final fake = _makeFake(
        () async => throw Exception('network unreachable'),
        service,
        prefs,
      );

      final notifier = PremiumNotifier(service);
      await Future<void>.delayed(Duration.zero);

      await expectLater(
        notifier.refreshLicense(verificationService: fake, prefs: prefs),
        completes,
      );
      expect(notifier.state.isPremium, true); // unchanged
    });

    test(
      'does not update cache on network error (retries next launch)',
      () async {
        final fake = _makeFake(
          () async => throw Exception('network unreachable'),
          service,
          prefs,
        );

        final notifier = PremiumNotifier(service);
        await Future<void>.delayed(Duration.zero);
        await notifier.refreshLicense(verificationService: fake, prefs: prefs);

        expect(prefs.getString(PremiumNotifier.lastRefreshKeyForTest), isNull);
      },
    );
  });
}
