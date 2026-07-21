import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svid/core/config/brand_config.dart';
import 'package:svid/core/errors/app_exception.dart';
import 'package:svid/core/network/backend_client.dart';
import 'package:svid/core/services/secure_credential_store.dart';
import 'package:svid/features/premium/data/datasources/premium_local_datasource.dart';
import 'package:svid/features/premium/data/services/license_activation_handler.dart';
import 'package:svid/features/premium/data/services/license_verification_service.dart';
import 'package:svid/features/premium/domain/entities/premium_license.dart';
import 'package:svid/features/premium/domain/services/premium_license_service.dart';

import '../../../../helpers/brand_test_keys.dart';

/// Verification service whose [verifyKey] throws a caller-supplied exception,
/// so the Go deep-link catch branch can be exercised deterministically without
/// real HTTP. Mirrors how the real service surfaces backend failures:
/// [BackendClient] throws [AppException.network] with a 4xx statusCode on a
/// server rejection and with NO statusCode on a true transport failure.
class _ThrowingVerificationService extends LicenseVerificationService {
  final Object _error;

  _ThrowingVerificationService(SharedPreferences prefs, this._error)
    : super(
        BackendClient(SecureCredentialStore(prefs)),
        PremiumLicenseService(_TestDatasource(prefs)),
      );

  @override
  Future<LicenseVerificationResponse> verifyKey(String licenseKey) async {
    throw _error;
  }
}

class _RespondingVerificationService extends LicenseVerificationService {
  final LicenseVerificationResponse _response;
  int calls = 0;

  _RespondingVerificationService(SharedPreferences prefs, this._response)
    : super(
        BackendClient(SecureCredentialStore(prefs)),
        PremiumLicenseService(_TestDatasource(prefs)),
      );

  @override
  Future<LicenseVerificationResponse> verifyKey(String licenseKey) async {
    calls += 1;
    return _response;
  }
}

class _RespondingBackendClient extends BackendClient {
  final Map<String, dynamic> _json;
  int calls = 0;
  String? lastPath;
  Object? lastData;

  _RespondingBackendClient(SharedPreferences prefs, this._json)
    : super(SecureCredentialStore(prefs));

  @override
  Future<T> post<T>(
    String path, {
    dynamic data,
    Options? options,
    required T Function(dynamic json) fromJson,
  }) async {
    calls += 1;
    lastPath = path;
    lastData = data as Object?;
    return fromJson(_json);
  }
}

/// Fake secure storage for testing
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LicenseActivationHandler', () {
    group('ActivationStatus', () {
      test('success status', () {
        expect(
          LicenseActivationResult.success.status,
          ActivationStatus.success,
        );
        expect(LicenseActivationResult.success.isSuccess, true);
      });

      test('successOffline status', () {
        expect(
          LicenseActivationResult.successOffline.status,
          ActivationStatus.successOffline,
        );
        expect(LicenseActivationResult.successOffline.isSuccess, true);
      });

      test('invalidKey status', () {
        expect(
          LicenseActivationResult.invalidKey.status,
          ActivationStatus.invalidKey,
        );
        expect(LicenseActivationResult.invalidKey.isSuccess, false);
      });

      test('rejected status with reason', () {
        const result = LicenseActivationResult(
          status: ActivationStatus.rejected,
          reason: 'revoked',
        );
        expect(result.isSuccess, false);
        expect(result.reason, 'revoked');
      });
    });

    group('URI parsing', () {
      late SharedPreferences prefs;
      late _TestDatasource datasource;
      late PremiumLicenseService licenseService;

      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        prefs = await SharedPreferences.getInstance();
        datasource = _TestDatasource(prefs);
        licenseService = PremiumLicenseService(datasource);
      });

      test('valid license key format is accepted', () {
        // Brand-aware fixture — exercises whichever format the current
        // brand defines (SSvid 9-group hex vs VidCombo 32-char hex).
        expect(
          PremiumLicenseService.isValidLicenseKey(TestLicenseKeys.valid),
          true,
        );
      });

      test('invalid license key format is rejected', () {
        expect(PremiumLicenseService.isValidLicenseKey('invalid'), false);
        expect(PremiumLicenseService.isValidLicenseKey(''), false);
        // Truncated SSvid prefix is invalid under both brands.
        expect(
          PremiumLicenseService.isValidLicenseKey('SSVID-1234-5678'),
          false,
        );
        // Old SSvid 4-group format is invalid under both brands.
        expect(
          PremiumLicenseService.isValidLicenseKey('SSVID-1234-5678-9ABC-DEF0'),
          false,
        );
      });

      test('lowercase hex is accepted', () {
        // Both brand formats accept lowercase hex; pick a brand-appropriate
        // fixture and verify it validates.
        final lowercaseKey =
            BrandConfig.current.brand == Brand.ssvid
                ? 'SSVID-abcd-ef01-2345-6789-abcd-ef01-2345-6789'
                : 'abcdef0123456789abcdef0123456789';
        expect(PremiumLicenseService.isValidLicenseKey(lowercaseKey), true);
      });

      test('activate stores key and sets tier to premium', () async {
        final license = await licenseService.activateLicense(
          TestLicenseKeys.valid,
          paymentMethod: 'deep_link',
        );

        expect(license.isPremium, true);
        expect(license.licenseKey, TestLicenseKeys.valid);
        expect(license.paymentMethod, 'deep_link');
        expect(license.lastVerified, isNotNull);
      });

      test('invalid key throws FormatException', () async {
        expect(
          () => licenseService.activateLicense('bad-key'),
          throwsFormatException,
        );
      });
    });

    group('URI routing', () {
      late SharedPreferences prefs;
      late LicenseVerificationService verificationService;

      setUp(() async {
        BrandConfig.setForTest(Brand.vidcombo);
        SharedPreferences.setMockInitialValues({});
        prefs = await SharedPreferences.getInstance();
        verificationService = LicenseVerificationService(
          BackendClient(SecureCredentialStore(prefs)),
          PremiumLicenseService(_TestDatasource(prefs)),
        );
      });

      tearDown(() {
        BrandConfig.setForTest(null);
      });

      test(
        'payment-complete only wakes status refresh and ignores return outcome',
        () async {
          var wakeCalls = 0;
          var activationCalls = 0;
          var phpVerificationCalls = 0;
          final handler = LicenseActivationHandler(
            verificationService: verificationService,
            activateViaNotifier: (
              key, {
              paymentMethod,
              billingCycle,
              expiresAt,
            }) async {
              activationCalls += 1;
            },
            verifyPhpLicenseKey: (key) async {
              phpVerificationCalls += 1;
              throw StateError('payment return must not verify a license');
            },
            onPaymentComplete: () async {
              wakeCalls += 1;
            },
          );
          addTearDown(handler.dispose);

          await handler.handleUri(
            Uri.parse(
              'vidcombo://payment-complete?outcome=success&billing_checkout=opaque',
            ),
          );

          expect(wakeCalls, 1);
          expect(activationCalls, 0);
          expect(phpVerificationCalls, 0);
        },
      );

      test('payment-complete for another scheme is ignored', () async {
        var wakeCalls = 0;
        final handler = LicenseActivationHandler(
          verificationService: verificationService,
          activateViaNotifier:
              (key, {paymentMethod, billingCycle, expiresAt}) async {},
          onPaymentComplete: () async {
            wakeCalls += 1;
          },
        );
        addTearDown(handler.dispose);

        await handler.handleUri(Uri.parse('ssvid://payment-complete'));
        await handler.handleUri(Uri.parse('vidcombo://unrelated'));
        await handler.handleUri(null);

        expect(wakeCalls, 0);
      });

      test('public handleUri preserves verified activation routing', () async {
        String? activatedKey;
        final verifier = _RespondingVerificationService(
          prefs,
          LicenseVerificationResponse(
            isValid: true,
            tier: 'premium',
            verifiedAt: DateTime.utc(2026, 7, 17),
          ),
        );
        final handler = LicenseActivationHandler(
          verificationService: verifier,
          activateViaNotifier: (
            key, {
            paymentMethod,
            billingCycle,
            expiresAt,
          }) async {
            activatedKey = key;
          },
        );
        addTearDown(handler.dispose);

        final resultFuture = handler.activationResults.first;
        await handler.handleUri(
          Uri.parse('vidcombo://activate?key=${TestLicenseKeys.valid}'),
        );

        expect((await resultFuture).status, ActivationStatus.success);
        expect(verifier.calls, 1);
        expect(activatedKey, TestLicenseKeys.valid);
      });
    });

    group('VidCombo PHP deep-link activation', () {
      late SharedPreferences prefs;
      late PremiumLicenseService licenseService;
      late LicenseVerificationService verificationService;

      setUp(() async {
        BrandConfig.setForTest(Brand.vidcombo);
        SharedPreferences.setMockInitialValues({});
        prefs = await SharedPreferences.getInstance();
        licenseService = PremiumLicenseService(_TestDatasource(prefs));
        verificationService = LicenseVerificationService(
          BackendClient(SecureCredentialStore(prefs)),
          licenseService,
        );
      });

      tearDown(() {
        BrandConfig.setForTest(null);
      });

      test('activates only after PHP backend verifies the key', () async {
        String? activatedKey;
        String? activatedPaymentMethod;
        BillingCycle? activatedBillingCycle;
        DateTime? activatedExpiresAt;
        final expectedExpiry = DateTime.utc(2026, 12, 31);

        final handler = LicenseActivationHandler(
          verificationService: verificationService,
          activateViaNotifier: (
            key, {
            paymentMethod,
            billingCycle,
            expiresAt,
          }) async {
            activatedKey = key;
            activatedPaymentMethod = paymentMethod;
            activatedBillingCycle = billingCycle;
            activatedExpiresAt = expiresAt;
          },
          verifyPhpLicenseKey:
              (key) async => LicenseVerificationResponse(
                isValid: true,
                tier: 'premium',
                verifiedAt: DateTime.utc(2026, 6, 3),
                billingCycle: 'yearly',
                expiresAt: expectedExpiry,
              ),
        );
        addTearDown(handler.dispose);

        final resultFuture = handler.activationResults.first;
        await handler.activateFromDeepLink(TestLicenseKeys.validPhpLegacy);
        final result = await resultFuture;

        expect(result.status, ActivationStatus.success);
        expect(activatedKey, TestLicenseKeys.validPhpLegacy);
        expect(activatedPaymentMethod, 'deep_link');
        expect(activatedBillingCycle, BillingCycle.yearly);
        expect(activatedExpiresAt, expectedExpiry);
      });

      test(
        'rejects PHP backend invalid response without local activation',
        () async {
          var activated = false;
          final handler = LicenseActivationHandler(
            verificationService: verificationService,
            activateViaNotifier: (
              key, {
              paymentMethod,
              billingCycle,
              expiresAt,
            }) async {
              activated = true;
            },
            verifyPhpLicenseKey:
                (key) async => LicenseVerificationResponse(
                  isValid: false,
                  tier: 'free',
                  verifiedAt: DateTime.utc(2026, 6, 3),
                  reason: 'revoked',
                ),
          );
          addTearDown(handler.dispose);

          final resultFuture = handler.activationResults.first;
          await handler.activateFromDeepLink(TestLicenseKeys.validPhpLegacy);
          final result = await resultFuture;

          expect(result.status, ActivationStatus.rejected);
          expect(result.reason, 'revoked');
          expect(activated, false);
        },
      );

      test(
        'falls back to offline activation when PHP verification is unavailable',
        () async {
          String? activatedKey;
          String? activatedPaymentMethod;
          final handler = LicenseActivationHandler(
            verificationService: verificationService,
            activateViaNotifier: (
              key, {
              paymentMethod,
              billingCycle,
              expiresAt,
            }) async {
              activatedKey = key;
              activatedPaymentMethod = paymentMethod;
            },
            verifyPhpLicenseKey: (key) async {
              throw StateError('php unavailable');
            },
          );
          addTearDown(handler.dispose);

          final resultFuture = handler.activationResults.first;
          await handler.activateFromDeepLink(TestLicenseKeys.validPhpLegacy);
          final result = await resultFuture;

          expect(result.status, ActivationStatus.successOffline);
          expect(activatedKey, TestLicenseKeys.validPhpLegacy);
          expect(activatedPaymentMethod, 'deep_link');
        },
      );

      test(
        'routes VIDCOMBO Go keys to Go verifier, not PHP checkkey',
        () async {
          String? activatedKey;
          String? activatedPaymentMethod;
          var phpCalled = false;
          final goVerifier = _RespondingVerificationService(
            prefs,
            LicenseVerificationResponse(
              isValid: true,
              tier: 'premium',
              verifiedAt: DateTime.utc(2026, 6, 3),
              billingCycle: 'monthly',
              expiresAt: DateTime.utc(2026, 12, 31),
            ),
          );

          final handler = LicenseActivationHandler(
            verificationService: goVerifier,
            activateViaNotifier: (
              key, {
              paymentMethod,
              billingCycle,
              expiresAt,
            }) async {
              activatedKey = key;
              activatedPaymentMethod = paymentMethod;
            },
            verifyPhpLicenseKey: (key) async {
              phpCalled = true;
              throw StateError('PHP verifier must not handle Go-format keys');
            },
          );
          addTearDown(handler.dispose);

          final resultFuture = handler.activationResults.first;
          await handler.activateFromDeepLink(TestLicenseKeys.valid);
          final result = await resultFuture;

          expect(result.status, ActivationStatus.success);
          expect(goVerifier.calls, 1);
          expect(phpCalled, isFalse);
          expect(activatedKey, TestLicenseKeys.valid);
          expect(activatedPaymentMethod, 'deep_link');
        },
      );

      test(
        'routes VIDCOMBO Go keys through real Go verifier under PHP brand',
        () async {
          String? activatedKey;
          var phpCalled = false;
          final backendClient = _RespondingBackendClient(prefs, {
            'is_valid': true,
            'tier': 'premium',
            'verified_at': DateTime.utc(2026, 6, 3).toIso8601String(),
            'billing_cycle': 'monthly',
            'expires_at': DateTime.utc(2026, 12, 31).toIso8601String(),
          });
          final realGoVerifier = LicenseVerificationService(
            backendClient,
            licenseService,
          );

          final handler = LicenseActivationHandler(
            verificationService: realGoVerifier,
            activateViaNotifier: (
              key, {
              paymentMethod,
              billingCycle,
              expiresAt,
            }) async {
              activatedKey = key;
            },
            verifyPhpLicenseKey: (key) async {
              phpCalled = true;
              throw StateError('PHP verifier must not handle Go-format keys');
            },
          );
          addTearDown(handler.dispose);

          final resultFuture = handler.activationResults.first;
          await handler.activateFromDeepLink(TestLicenseKeys.valid);
          final result = await resultFuture;

          expect(result.status, ActivationStatus.success);
          expect(backendClient.calls, 1);
          expect(backendClient.lastPath, '/premium/licenses/verify');
          expect(
            (backendClient.lastData as Map<String, dynamic>)['key'],
            TestLicenseKeys.valid,
          );
          expect(phpCalled, isFalse);
          expect(activatedKey, TestLicenseKeys.valid);
        },
      );

      test(
        'rejects VIDCOMBO Go keys on Go backend 4xx without PHP fallback',
        () async {
          var activated = false;
          var phpCalled = false;
          final handler = LicenseActivationHandler(
            verificationService: _ThrowingVerificationService(
              prefs,
              const AppException.network(
                message: 'License not found',
                statusCode: 404,
              ),
            ),
            activateViaNotifier: (
              key, {
              paymentMethod,
              billingCycle,
              expiresAt,
            }) async {
              activated = true;
            },
            verifyPhpLicenseKey: (key) async {
              phpCalled = true;
              throw StateError('PHP verifier must not handle Go-format keys');
            },
          );
          addTearDown(handler.dispose);

          final resultFuture = handler.activationResults.first;
          await handler.activateFromDeepLink(TestLicenseKeys.valid);
          final result = await resultFuture;

          expect(result.status, ActivationStatus.rejected);
          expect(result.isSuccess, isFalse);
          expect(activated, isFalse);
          expect(phpCalled, isFalse);
        },
      );

      test(
        'rejects VIDCOMBO Go keys when verification fails before network',
        () async {
          var activated = false;
          final handler = LicenseActivationHandler(
            verificationService: _ThrowingVerificationService(
              prefs,
              UnsupportedError('programming/routing error'),
            ),
            activateViaNotifier: (
              key, {
              paymentMethod,
              billingCycle,
              expiresAt,
            }) async {
              activated = true;
            },
            verifyPhpLicenseKey: (key) async {
              throw StateError('PHP verifier must not handle Go-format keys');
            },
          );
          addTearDown(handler.dispose);

          final resultFuture = handler.activationResults.first;
          await handler.activateFromDeepLink(TestLicenseKeys.valid);
          final result = await resultFuture;

          expect(result.status, ActivationStatus.rejected);
          expect(activated, isFalse);
        },
      );
    });

    group('Go deep-link activation (fail-open leak)', () {
      late SharedPreferences prefs;

      setUp(() async {
        BrandConfig.setForTest(Brand.ssvid);
        SharedPreferences.setMockInitialValues({});
        prefs = await SharedPreferences.getInstance();
      });

      tearDown(() {
        BrandConfig.setForTest(null);
      });

      test(
        'forged key → 404 from Go backend → rejected, premium NOT granted',
        () async {
          var activated = false;
          final handler = LicenseActivationHandler(
            verificationService: _ThrowingVerificationService(
              prefs,
              // BackendClient maps a 4xx server response to a NetworkException
              // carrying the statusCode (see _mapDioError / _unwrap).
              const AppException.network(
                message: 'License not found',
                statusCode: 404,
              ),
            ),
            activateViaNotifier: (
              key, {
              paymentMethod,
              billingCycle,
              expiresAt,
            }) async {
              activated = true;
            },
          );
          addTearDown(handler.dispose);

          final resultFuture = handler.activationResults.first;
          await handler.activateFromDeepLink(TestLicenseKeys.valid);
          final result = await resultFuture;

          expect(result.status, ActivationStatus.rejected);
          expect(result.isSuccess, false);
          expect(activated, false);
        },
      );

      test('valid key → transport failure (no statusCode) → offline activation '
          'still fires', () async {
        String? activatedKey;
        String? activatedPaymentMethod;
        final handler = LicenseActivationHandler(
          verificationService: _ThrowingVerificationService(
            prefs,
            // Connection error / timeout → NetworkException with no
            // statusCode (see _mapDioError default + connectionError cases).
            const AppException.network(message: 'Cannot connect to server'),
          ),
          activateViaNotifier: (
            key, {
            paymentMethod,
            billingCycle,
            expiresAt,
          }) async {
            activatedKey = key;
            activatedPaymentMethod = paymentMethod;
          },
        );
        addTearDown(handler.dispose);

        final resultFuture = handler.activationResults.first;
        await handler.activateFromDeepLink(TestLicenseKeys.valid);
        final result = await resultFuture;

        expect(result.status, ActivationStatus.successOffline);
        expect(result.isSuccess, true);
        expect(activatedKey, TestLicenseKeys.valid);
        expect(activatedPaymentMethod, 'deep_link');
      });
    });
  });

  group('LicenseVerificationResponse', () {
    test('valid response from backend', () {
      final json = {
        'is_valid': true,
        'tier': 'premium',
        'verified_at': '2026-02-28T12:00:00.000Z',
        'device_count': 2,
        'max_devices': 3,
      };

      final response = LicenseVerificationResponse.fromJson(json);
      expect(response.isValid, true);
      expect(response.deviceCount, 2);
      expect(response.maxDevices, 3);
    });

    test('revoked response from backend', () {
      final json = {
        'is_valid': false,
        'verified_at': '2026-02-28T12:00:00.000Z',
        'reason': 'revoked',
      };

      final response = LicenseVerificationResponse.fromJson(json);
      expect(response.isValid, false);
      expect(response.reason, 'revoked');
    });
  });
}
