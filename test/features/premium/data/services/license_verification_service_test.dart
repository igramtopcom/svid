import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svid/core/config/brand_config.dart';
import 'package:svid/core/errors/app_exception.dart';
import 'package:svid/core/network/backend_client.dart';
import 'package:svid/core/services/secure_credential_store.dart';
import 'package:svid/features/premium/data/datasources/premium_local_datasource.dart';
import 'package:svid/features/premium/data/services/license_verification_service.dart';
import 'package:svid/features/premium/domain/entities/premium_license.dart';
import 'package:svid/features/premium/domain/entities/premium_tier.dart';
import 'package:svid/features/premium/domain/services/premium_license_service.dart';

import '../../../../helpers/brand_test_keys.dart';

/// In-memory secure storage so the fake datasource never touches the platform
/// Keychain.
class _FakeSecureStorage {
  final Map<String, String> _store = {};
  Future<String?> read({required String key}) async => _store[key];
  Future<void> write({required String key, required String value}) async =>
      _store[key] = value;
  Future<void> delete({required String key}) async => _store.remove(key);
}

class _TestDatasource extends PremiumLocalDatasource {
  final _FakeSecureStorage _fakeSecure;

  _TestDatasource(SharedPreferences prefs)
    : _fakeSecure = _FakeSecureStorage(),
      super(prefs, SecureCredentialStore(prefs));

  @override
  Future<String?> getLicenseKey() async =>
      _fakeSecure.read(key: 'premium_license_key');

  @override
  Future<void> saveLicenseKey(String key) async =>
      _fakeSecure.write(key: 'premium_license_key', value: key);

  @override
  Future<void> deleteLicenseKey() async =>
      _fakeSecure.delete(key: 'premium_license_key');
}

/// Fake backend client that returns a canned [LicenseVerificationResponse] or
/// throws a canned error from `post`, driving the REAL [verify] flow without a
/// network round-trip.
class _FakeBackendClient extends BackendClient {
  Object? _throw;
  Map<String, dynamic>? _verifyJson;
  int postCalls = 0;
  String? lastPath;
  Object? lastData;

  // ignore: use_super_parameters
  _FakeBackendClient(SecureCredentialStore credentials) : super(credentials);

  void stubThrow(Object error) {
    _throw = error;
    _verifyJson = null;
  }

  void stubResponse(Map<String, dynamic> json) {
    _verifyJson = json;
    _throw = null;
  }

  void Function()? _onPost;

  /// Like [stubResponse] but invokes [onPost] when the POST is made — proves
  /// the server was actually contacted.
  void stubResponseSpy(void Function() onPost, Map<String, dynamic> json) {
    _onPost = onPost;
    _verifyJson = json;
    _throw = null;
  }

  @override
  Future<T> post<T>(
    String path, {
    dynamic data,
    Options? options,
    required T Function(dynamic json) fromJson,
  }) async {
    postCalls += 1;
    lastPath = path;
    lastData = data as Object?;
    _onPost?.call();
    if (_throw != null) throw _throw!;
    return fromJson(_verifyJson);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LicenseVerificationResponse', () {
    test('fromJson parses valid response', () {
      final json = {
        'is_valid': true,
        'tier': 'premium',
        'verified_at': '2026-02-28T12:00:00.000Z',
        'device_count': 1,
        'max_devices': 3,
      };

      final response = LicenseVerificationResponse.fromJson(json);
      expect(response.isValid, true);
      expect(response.tier, 'premium');
      expect(response.verifiedAt, DateTime.utc(2026, 2, 28, 12));
      expect(response.deviceCount, 1);
      expect(response.maxDevices, 3);
      expect(response.reason, isNull);
    });

    test('fromJson parses invalid response with reason', () {
      final json = {
        'is_valid': false,
        'verified_at': '2026-02-28T12:00:00.000Z',
        'reason': 'revoked',
      };

      final response = LicenseVerificationResponse.fromJson(json);
      expect(response.isValid, false);
      expect(response.reason, 'revoked');
    });

    test('fromJson handles device_limit_exceeded', () {
      final json = {
        'is_valid': false,
        'verified_at': '2026-02-28T12:00:00.000Z',
        'reason': 'device_limit_exceeded',
        'device_count': 3,
        'max_devices': 3,
      };

      final response = LicenseVerificationResponse.fromJson(json);
      expect(response.isValid, false);
      expect(response.reason, 'device_limit_exceeded');
      expect(response.deviceCount, 3);
      expect(response.maxDevices, 3);
    });

    test('fromJson defaults is_valid to false when missing', () {
      final json = <String, dynamic>{'verified_at': '2026-02-28T12:00:00.000Z'};

      final response = LicenseVerificationResponse.fromJson(json);
      expect(response.isValid, false);
    });

    test('fromJson handles null verified_at gracefully', () {
      final json = <String, dynamic>{'is_valid': true};

      final response = LicenseVerificationResponse.fromJson(json);
      expect(response.isValid, true);
      // verifiedAt should default to now
      expect(response.verifiedAt.year, DateTime.now().year);
    });
  });

  group('VerificationResult', () {
    test('success is verified', () {
      expect(VerificationResult.success.verified, true);
      expect(VerificationResult.success.shouldDeactivate, false);
    });

    test('offlineGrace is verified with reason', () {
      expect(VerificationResult.offlineGrace.verified, true);
      expect(VerificationResult.offlineGrace.reason, 'offline_grace');
      expect(VerificationResult.offlineGrace.shouldDeactivate, false);
    });

    test('offlineExpired is not verified and should deactivate', () {
      expect(VerificationResult.offlineExpired.verified, false);
      expect(VerificationResult.offlineExpired.shouldDeactivate, true);
      expect(VerificationResult.offlineExpired.reason, 'grace_period_expired');
    });

    test('custom result with device limit info', () {
      const result = VerificationResult(
        verified: false,
        shouldDeactivate: true,
        reason: 'device_limit_exceeded',
        deviceCount: 3,
        maxDevices: 3,
      );

      expect(result.verified, false);
      expect(result.shouldDeactivate, true);
      expect(result.deviceCount, 3);
      expect(result.maxDevices, 3);
    });

    test('defaults to non-definitive (uncertain → keep key)', () {
      const result = VerificationResult(verified: true);
      expect(result.definitive, false);
    });

    test('offlineExpired is NOT definitive (keep key)', () {
      // Offline > 30d is uncertain, not a server revoke — preserve the key.
      expect(VerificationResult.offlineExpired.definitive, false);
    });
  });

  group('VerificationResult.isDefinitiveServerRevoke', () {
    LicenseVerificationResponse resp({String? reason, String? tier}) =>
        LicenseVerificationResponse(
          isValid: false,
          verifiedAt: DateTime(2026, 6, 2),
          reason: reason,
          tier: tier,
        );

    test('reason==revoked → definitive', () {
      expect(
        VerificationResult.isDefinitiveServerRevoke(resp(reason: 'revoked')),
        true,
      );
    });

    test('tier==free → definitive', () {
      expect(
        VerificationResult.isDefinitiveServerRevoke(resp(tier: 'free')),
        true,
      );
    });

    test('is_valid=false with no reason and tier premium → NOT definitive', () {
      // The backend 0-grace post-expiry contradiction: this must NOT wipe key.
      expect(
        VerificationResult.isDefinitiveServerRevoke(resp(tier: 'premium')),
        false,
      );
    });

    test('is_valid=false with no reason and no tier → NOT definitive', () {
      expect(VerificationResult.isDefinitiveServerRevoke(resp()), false);
    });

    test('expired reason → NOT definitive (renewal lag, keep key)', () {
      expect(
        VerificationResult.isDefinitiveServerRevoke(resp(reason: 'expired')),
        false,
      );
    });
  });

  group('LicenseVerificationService constants', () {
    test('grace period is 30 days', () {
      expect(LicenseVerificationService.gracePeriodDays, 30);
    });

    test('verification interval is 7 days', () {
      expect(LicenseVerificationService.verificationIntervalDays, 7);
    });
  });

  group('PremiumLicense verification helpers', () {
    test('free license does not need verification', () {
      expect(PremiumLicense.free.needsVerification(), false);
    });

    test('premium with null lastVerified needs verification', () {
      const license = PremiumLicense(
        tier: PremiumTier.premium,
        licenseKey: 'SVID-1234-5678-9abc-def0-1234-5678-9abc-def0',
      );
      expect(license.needsVerification(), true);
    });

    test('premium with recent lastVerified does not need verification', () {
      final license = PremiumLicense(
        tier: PremiumTier.premium,
        licenseKey: 'SVID-1234-5678-9abc-def0-1234-5678-9abc-def0',
        lastVerified: DateTime.now().subtract(const Duration(days: 3)),
      );
      expect(license.needsVerification(), false);
    });

    test('premium with old lastVerified needs verification', () {
      final license = PremiumLicense(
        tier: PremiumTier.premium,
        licenseKey: 'SVID-1234-5678-9abc-def0-1234-5678-9abc-def0',
        lastVerified: DateTime.now().subtract(const Duration(days: 8)),
      );
      expect(license.needsVerification(), true);
    });

    test('exactly 7 days ago needs verification', () {
      final license = PremiumLicense(
        tier: PremiumTier.premium,
        licenseKey: 'SVID-1234-5678-9abc-def0-1234-5678-9abc-def0',
        lastVerified: DateTime.now().subtract(const Duration(days: 7)),
      );
      expect(license.needsVerification(), true);
    });

    test('within grace period (verified 20 days ago)', () {
      final license = PremiumLicense(
        tier: PremiumTier.premium,
        licenseKey: 'SVID-1234-5678-9abc-def0-1234-5678-9abc-def0',
        lastVerified: DateTime.now().subtract(const Duration(days: 20)),
      );
      expect(license.isWithinGracePeriod(), true);
    });

    test('outside grace period (verified 31 days ago)', () {
      final license = PremiumLicense(
        tier: PremiumTier.premium,
        licenseKey: 'SVID-1234-5678-9abc-def0-1234-5678-9abc-def0',
        lastVerified: DateTime.now().subtract(const Duration(days: 31)),
      );
      expect(license.isWithinGracePeriod(), false);
    });

    test('exactly 30 days is outside grace period', () {
      final license = PremiumLicense(
        tier: PremiumTier.premium,
        licenseKey: 'SVID-1234-5678-9abc-def0-1234-5678-9abc-def0',
        lastVerified: DateTime.now().subtract(const Duration(days: 30)),
      );
      expect(license.isWithinGracePeriod(), false);
    });

    test('free license is not within grace period', () {
      expect(PremiumLicense.free.isWithinGracePeriod(), false);
    });

    test('null lastVerified is not within grace period', () {
      const license = PremiumLicense(
        tier: PremiumTier.premium,
        licenseKey: 'SVID-1234-5678-9abc-def0-1234-5678-9abc-def0',
      );
      expect(license.isWithinGracePeriod(), false);
    });
  });

  // FIX #2 + FIX #4 — verify() flow against a fake backend client.
  // Default brand in tests is Svid (Go backend) so these exercise the real
  // server-POST path (no PHP early-skip).
  group('verify() flow', () {
    late SharedPreferences prefs;
    late _TestDatasource datasource;
    late PremiumLicenseService licenseService;
    late _FakeBackendClient client;
    late LicenseVerificationService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      datasource = _TestDatasource(prefs);
      licenseService = PremiumLicenseService(datasource);
      client = _FakeBackendClient(SecureCredentialStore(prefs));
      service = LicenseVerificationService(client, licenseService);
    });

    /// Persist a premium license. Defaults make the flow reach the server POST:
    /// stale enough to need verification, not locally expired.
    Future<void> seedPremium({
      DateTime? lastVerified,
      DateTime? expiresAt,
      BillingCycle? billingCycle,
    }) async {
      final lv =
          lastVerified ?? DateTime.now().subtract(const Duration(days: 8));
      final exp = expiresAt ?? DateTime.now().add(const Duration(days: 30));
      await datasource.saveMetadata({
        'tier': 'premium',
        'purchaseDate': lv.toIso8601String(),
        'lastVerified': lv.toIso8601String(),
        if (billingCycle != null) 'billingCycle': billingCycle.name,
        'expiresAt': exp.toIso8601String(),
        'isAutoRenew': true,
      });
      await datasource.saveLicenseKey(TestLicenseKeys.valid);
    }

    AppException net(int status, {String? code}) =>
        AppException.network(message: 'x', statusCode: status, data: code);

    // ---- FIX #4: classify 4xx instead of fail-open offline grace ----

    test('403 device_limit → soft demote, key kept (NOT grace)', () async {
      await seedPremium();
      client.stubThrow(net(403, code: 'device_limit_exceeded'));

      final result = await service.verify();

      expect(result.verified, false);
      expect(
        result.shouldDeactivate,
        true,
        reason: '403 is a server verdict, not offline grace',
      );
      expect(result.reason, 'device_limit_exceeded');
      expect(
        result.definitive,
        false,
        reason: 'device_limit is SOFT — key preserved for auto-recovery',
      );
    });

    test('404 invalid_license_key → soft demote, NOT offline grace', () async {
      await seedPremium();
      client.stubThrow(net(404, code: 'invalid_license_key'));

      final result = await service.verify();

      expect(result.verified, false);
      expect(
        result.shouldDeactivate,
        true,
        reason: 'a recognized license-verdict code is a server verdict',
      );
      expect(result.reason, 'invalid_license_key');
      expect(result.definitive, false);
    });

    test(
      '404 with NO / unrecognized error code → offline grace, NOT demote (P2)',
      () async {
        // P2 (review): a 4xx WITHOUT a known license-verdict code (a bare 404, or
        // an auth/infra code like UNAUTHORIZED / MISSING_API_KEY) must NOT demote
        // a paying user — default-deny so it falls through to offline grace.
        await seedPremium();
        client.stubThrow(net(404));

        final result = await service.verify();

        expect(
          result.shouldDeactivate,
          false,
          reason:
              'no recognized license-verdict code → offline grace, no demote',
        );
      },
    );

    test('403 revoked → DEFINITIVE demote (full wipe)', () async {
      await seedPremium();
      client.stubThrow(net(403, code: 'revoked'));

      final result = await service.verify();

      expect(result.shouldDeactivate, true);
      expect(result.reason, 'revoked');
      expect(
        result.definitive,
        true,
        reason: 'revoked is the only 4xx that justifies a full key-wipe',
      );
    });

    test(
      'connectionError (no statusCode) → offline grace keeps premium 30d',
      () async {
        // Verified 10 days ago → still inside the 30-day offline grace.
        await seedPremium(
          lastVerified: DateTime.now().subtract(const Duration(days: 10)),
        );
        // Connectivity failure carries NO statusCode.
        client.stubThrow(
          const AppException.network(message: 'Cannot connect to server'),
        );

        final result = await service.verify();

        expect(result.verified, true, reason: 'offline grace keeps premium');
        expect(result.shouldDeactivate, false);
        expect(result.reason, 'offline_grace');
      },
    );

    test(
      'connectionError past 30-day grace → offline-expired demote (key kept)',
      () async {
        await seedPremium(
          lastVerified: DateTime.now().subtract(const Duration(days: 31)),
        );
        client.stubThrow(
          const AppException.network(message: 'Cannot connect to server'),
        );

        final result = await service.verify();

        expect(result.verified, false);
        expect(result.shouldDeactivate, true);
        expect(result.reason, 'grace_period_expired');
        expect(result.definitive, false);
      },
    );

    test('5xx server error → offline grace (not a client verdict)', () async {
      // A 500 is not a license verdict; treat as transient → grace.
      await seedPremium(
        lastVerified: DateTime.now().subtract(const Duration(days: 10)),
      );
      client.stubThrow(net(500, code: 'internal'));

      final result = await service.verify();

      expect(result.verified, true);
      expect(result.reason, 'offline_grace');
    });

    test('valid 200 → success, unaffected by classification', () async {
      await seedPremium();
      client.stubResponse({
        'is_valid': true,
        'tier': 'premium',
        'verified_at': DateTime.now().toIso8601String(),
        'billing_cycle': 'monthly',
        'expires_at':
            DateTime.now().add(const Duration(days: 60)).toIso8601String(),
        'is_auto_renew': true,
      });

      final result = await service.verify();

      expect(result.verified, true);
      expect(result.shouldDeactivate, false);
    });

    test(
      'server is_valid=false revoked → definitive demote (unchanged)',
      () async {
        await seedPremium();
        client.stubResponse({
          'is_valid': false,
          'reason': 'revoked',
          'verified_at': DateTime.now().toIso8601String(),
        });

        final result = await service.verify();

        expect(result.shouldDeactivate, true);
        expect(result.reason, 'revoked');
        expect(result.definitive, true);
      },
    );

    // ---- FIX #2: local expiry asks server FIRST, no pre-server demote ----

    test(
      'locally expired + server renews → success (no pre-server demote)',
      () async {
        // expiresAt 60 days ago = well past the 7-day feature grace, so the old
        // code would have returned subscription_expired before the POST.
        await seedPremium(
          expiresAt: DateTime.now().subtract(const Duration(days: 60)),
          lastVerified: DateTime.now().subtract(const Duration(days: 60)),
        );
        client.stubResponse({
          'is_valid': true,
          'tier': 'premium',
          'verified_at': DateTime.now().toIso8601String(),
          'billing_cycle': 'monthly',
          'expires_at':
              DateTime.now().add(const Duration(days: 30)).toIso8601String(),
          'is_auto_renew': true,
        });

        final result = await service.verify();

        expect(
          result.verified,
          true,
          reason: 'server renewal authority overrides stale local expiry',
        );
        expect(result.shouldDeactivate, false);
      },
    );

    test(
      'locally expired reaches server even inside 7-day verify interval',
      () async {
        // lastVerified yesterday → needsVerification() is false, BUT local expiry
        // must still force a server check (else a just-renewed user stays stuck).
        await seedPremium(
          lastVerified: DateTime.now().subtract(const Duration(days: 1)),
          expiresAt: DateTime.now().subtract(const Duration(days: 60)),
        );
        var posted = false;
        client.stubResponseSpy(() => posted = true, {
          'is_valid': true,
          'tier': 'premium',
          'verified_at': DateTime.now().toIso8601String(),
          'expires_at':
              DateTime.now().add(const Duration(days: 30)).toIso8601String(),
        });

        final result = await service.verify();

        expect(posted, true, reason: 'local expiry forces a server POST');
        expect(result.verified, true);
      },
    );

    test(
      'locally expired OFFLINE → reaches 30-day grace (NOT pre-server demote)',
      () async {
        // The critical FIX #2 regression: an OFFLINE locally-expired paid user
        // must still get the offline grace, which the old pre-server demote blocked.
        await seedPremium(
          expiresAt: DateTime.now().subtract(const Duration(days: 60)),
          lastVerified: DateTime.now().subtract(const Duration(days: 10)),
        );
        client.stubThrow(
          const AppException.network(message: 'Cannot connect to server'),
        );

        final result = await service.verify();

        expect(
          result.verified,
          true,
          reason: 'offline locally-expired user keeps premium within grace',
        );
        expect(result.reason, 'offline_grace');
      },
    );

    test(
      'locally expired + server confirms expired → demote (server verdict)',
      () async {
        await seedPremium(
          expiresAt: DateTime.now().subtract(const Duration(days: 60)),
          lastVerified: DateTime.now().subtract(const Duration(days: 60)),
        );
        // Server confirms is_valid=false with reason expired (NOT definitive →
        // soft demote, key kept for renewal auto-recovery).
        client.stubResponse({
          'is_valid': false,
          'reason': 'expired',
          'tier': 'premium',
          'verified_at': DateTime.now().toIso8601String(),
        });

        final result = await service.verify();

        expect(result.shouldDeactivate, true);
        expect(result.reason, 'expired');
        expect(
          result.definitive,
          false,
          reason: 'expired is renewal-lag uncertain → keep key',
        );
      },
    );
  });

  group('serverVerdictFor4xx — only known license codes demote (P2)', () {
    late LicenseVerificationService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final datasource = _TestDatasource(prefs);
      final licenseService = PremiumLicenseService(datasource);
      final client = _FakeBackendClient(SecureCredentialStore(prefs));
      service = LicenseVerificationService(client, licenseService);
    });

    AppException net(int? status, [String? code]) =>
        AppException.network(message: 'x', statusCode: status, data: code);

    test('auth-lifecycle 4xx do NOT demote (null → offline grace)', () {
      expect(service.serverVerdictFor4xx(net(401, 'UNAUTHORIZED')), isNull);
      expect(service.serverVerdictFor4xx(net(401, 'MISSING_API_KEY')), isNull);
      expect(service.serverVerdictFor4xx(net(401, 'EXPIRED_API_KEY')), isNull);
      expect(
        service.serverVerdictFor4xx(net(401, 'REVOKED_API_KEY')),
        isNull,
        reason: 'REVOKED_API_KEY is auth, NOT a license revoke',
      );
      expect(service.serverVerdictFor4xx(net(403, 'DEVICE_INACTIVE')), isNull);
      expect(
        service.serverVerdictFor4xx(net(400, 'INVALID_DEVICE_ID')),
        isNull,
      );
      expect(service.serverVerdictFor4xx(net(429, 'RATE_LIMITED')), isNull);
    });

    test('unknown code / no code → null (default-deny demote)', () {
      expect(service.serverVerdictFor4xx(net(404, 'SOMETHING_NEW')), isNull);
      expect(service.serverVerdictFor4xx(net(404)), isNull);
    });

    test('license-verdict codes demote SOFT (key kept)', () {
      for (final code in const [
        'device_limit_exceeded',
        'invalid_license_key',
        'expired',
        'license_expired',
      ]) {
        final v = service.serverVerdictFor4xx(net(403, code));
        expect(v, isNotNull, reason: code);
        expect(v!.shouldDeactivate, true, reason: code);
        expect(v.definitive, false, reason: '$code is soft (key kept)');
      }
    });

    test('revoked is the only definitive verdict (full key-wipe)', () {
      expect(
        service.serverVerdictFor4xx(net(403, 'revoked'))!.definitive,
        true,
      );
      expect(
        service.serverVerdictFor4xx(net(403, 'LICENSE_REVOKED'))!.definitive,
        true,
        reason: 'matched case-insensitively',
      );
    });

    test('5xx / no-statusCode / non-AppException → null (not a verdict)', () {
      expect(service.serverVerdictFor4xx(net(500, 'INTERNAL_ERROR')), isNull);
      expect(service.serverVerdictFor4xx(net(null)), isNull);
      expect(service.serverVerdictFor4xx(Exception('x')), isNull);
    });
  });

  group('verifyKey() Go-format routing', () {
    late SharedPreferences prefs;
    late _TestDatasource datasource;
    late PremiumLicenseService licenseService;
    late _FakeBackendClient client;
    late LicenseVerificationService service;

    setUp(() async {
      BrandConfig.setForTest(Brand.vidcombo);
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      datasource = _TestDatasource(prefs);
      licenseService = PremiumLicenseService(datasource);
      client = _FakeBackendClient(SecureCredentialStore(prefs));
      service = LicenseVerificationService(client, licenseService);
    });

    tearDown(() {
      BrandConfig.setForTest(null);
    });

    test(
      'VidCombo Go key verifies through Go backend despite PHP brand',
      () async {
        client.stubResponse({
          'is_valid': true,
          'tier': 'premium',
          'verified_at': DateTime.utc(2026, 6, 3).toIso8601String(),
          'billing_cycle': 'monthly',
        });

        final response = await service.verifyKey(TestLicenseKeys.valid);

        expect(response.isValid, isTrue);
        expect(client.postCalls, 1);
        expect(client.lastPath, '/premium/licenses/verify');
        expect(
          (client.lastData as Map<String, dynamic>)['key'],
          TestLicenseKeys.valid,
        );
      },
    );

    test('VidCombo PHP legacy key is not sent to Go verifier', () async {
      client.stubResponse({
        'is_valid': true,
        'tier': 'premium',
        'verified_at': DateTime.utc(2026, 6, 3).toIso8601String(),
      });

      expect(
        () => service.verifyKey(TestLicenseKeys.validPhpLegacy),
        throwsA(isA<UnsupportedError>()),
      );
      expect(client.postCalls, 0);
    });
  });
}
