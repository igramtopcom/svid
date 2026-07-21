import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:svid/core/services/vidcombo/vidcombo_backend_adapter.dart';

const _testBaseUrl = 'https://test.vidcombo.net';

void main() {
  group('VidComboCheckKeyResponse.fromJson', () {
    test('parses active premium response', () {
      final json = {
        'license_key': 'ABCDEF01234567890ABCDEF012345678',
        'mess': 'License is active',
        'status': 'active',
        'end_date': '2027-01-01',
        'count_free': 5,
        'lever': 'plan2',
      };

      final response = VidComboCheckKeyResponse.fromJson(json);

      expect(response.licenseKey, 'ABCDEF01234567890ABCDEF012345678');
      expect(response.message, 'License is active');
      expect(response.status, 'active');
      expect(response.endDate, '2027-01-01');
      expect(response.countFree, 5);
      expect(response.plan, 'plan2');
    });

    test('parses inactive/free response', () {
      final json = {
        'license_key': null,
        'mess': 'Free user',
        'status': 'inactive',
        'count_free': 3,
      };

      final response = VidComboCheckKeyResponse.fromJson(json);

      expect(response.licenseKey, isNull);
      expect(response.status, 'inactive');
      expect(response.countFree, 3);
      expect(response.plan, isNull);
      expect(response.endDate, isNull);
    });

    test('parses minimal response with missing fields', () {
      final json = <String, dynamic>{'status': 'invalid'};

      final response = VidComboCheckKeyResponse.fromJson(json);

      expect(response.licenseKey, isNull);
      expect(response.message, isNull);
      expect(response.status, 'invalid');
      expect(response.endDate, isNull);
      expect(response.countFree, 0);
      expect(response.plan, isNull);
    });

    test('defaults status to invalid when null', () {
      final json = <String, dynamic>{};

      final response = VidComboCheckKeyResponse.fromJson(json);

      expect(response.status, 'invalid');
      expect(response.countFree, 0);
    });

    test('clamps negative count_free to zero', () {
      final json = {'status': 'invalid', 'count_free': -5};

      final response = VidComboCheckKeyResponse.fromJson(json);

      expect(response.countFree, 0);
    });

    test('clamps excessively large count_free to 9999', () {
      final json = {'status': 'active', 'count_free': 999999};

      final response = VidComboCheckKeyResponse.fromJson(json);

      expect(response.countFree, 9999);
    });

    test('handles count_free as non-int (string) gracefully', () {
      final json = <String, dynamic>{
        'status': 'active',
        'count_free': 'not_a_number',
      };

      final response = VidComboCheckKeyResponse.fromJson(json);

      expect(response.countFree, 0);
    });

    test('handles count_free as null', () {
      final json = <String, dynamic>{'status': 'active', 'count_free': null};

      final response = VidComboCheckKeyResponse.fromJson(json);

      expect(response.countFree, 0);
    });

    test('parses lifetime plan', () {
      final json = {
        'license_key': '12345678901234567890123456789012',
        'status': 'active',
        'count_free': 999,
        'lever': 'lifetime',
        'end_date': '',
      };

      final response = VidComboCheckKeyResponse.fromJson(json);

      expect(response.plan, 'lifetime');
      expect(response.isPremium, isTrue);
    });
  });

  group('VidComboCheckKeyResponse computed properties', () {
    test('isPremium is true when status is active', () {
      final response = VidComboCheckKeyResponse(status: 'active', countFree: 5);
      expect(response.isPremium, isTrue);
    });

    test('isPremium is false when status is inactive', () {
      final response = VidComboCheckKeyResponse(
        status: 'inactive',
        countFree: 3,
      );
      expect(response.isPremium, isFalse);
    });

    test('isPremium is false when status is invalid', () {
      final response = VidComboCheckKeyResponse(
        status: 'invalid',
        countFree: 0,
      );
      expect(response.isPremium, isFalse);
    });

    test('isTrial is true when invalid + no license key', () {
      final response = VidComboCheckKeyResponse(
        status: 'invalid',
        countFree: 5,
        licenseKey: null,
      );
      expect(response.isTrial, isTrue);
    });

    test('isTrial is false when invalid but has license key', () {
      final response = VidComboCheckKeyResponse(
        status: 'invalid',
        countFree: 0,
        licenseKey: 'ABCDEF01234567890ABCDEF012345678',
      );
      expect(response.isTrial, isFalse);
    });

    test('isTrial is false when active', () {
      final response = VidComboCheckKeyResponse(status: 'active', countFree: 5);
      expect(response.isTrial, isFalse);
    });
  });

  group('toLicenseVerification', () {
    late VidComboBackendAdapter adapter;

    setUp(() {
      adapter = VidComboBackendAdapter(
        httpClient: MockClient((_) async => http.Response('{}', 200)),
        deviceId: 'test-device-id',
        baseUrl: _testBaseUrl,
      );
    });

    test('active monthly plan', () {
      final ck = VidComboCheckKeyResponse(
        status: 'active',
        countFree: 10,
        plan: 'plan1',
        endDate: '2027-06-15',
        licenseKey: 'ABCDEF01234567890ABCDEF012345678',
      );

      final result = adapter.toLicenseVerification(ck);

      expect(result.isValid, isTrue);
      expect(result.tier, 'premium');
      expect(result.billingCycle, 'monthly');
      expect(result.expiresAt, DateTime.parse('2027-06-15'));
      expect(result.isAutoRenew, isTrue);
      expect(result.reason, isNull);
    });

    // Plan code mapping verified against PHP backend (api.vidcombo.com):
    //   plan1   = $6.99/mo            → monthly      (5-device limit, recurring)
    //   plan2   = $29.34 = 6×$4.89    → semiannual   (7-device limit, recurring)
    //   plan3   = $41.88 = 12×$3.49   → yearly       (10-device limit, fixed-term)
    //   lifetime = $9.90              → lifetime     (separate branch in PHP)
    //
    // Earlier mapping had plan2→yearly + plan3→lifetime, which silently
    // mislabeled every paid VidCombo user. Yearly buyers (plan3) saw themselves
    // as "lifetime" in the UI and got no renewal warning — when their
    // PHP-side license expired they lost premium with no explanation.
    test('plan2 → semiannual (recurring)', () {
      final ck = VidComboCheckKeyResponse(
        status: 'active',
        countFree: 10,
        plan: 'plan2',
        endDate: '2028-01-01',
      );

      final result = adapter.toLicenseVerification(ck);

      expect(result.isValid, isTrue);
      expect(result.billingCycle, 'semiannual');
      expect(result.isAutoRenew, isTrue);
      expect(result.expiresAt, DateTime.parse('2028-01-01'));
    });

    test('plan3 → yearly (fixed-term, no auto-renew)', () {
      // Regression: this used to be "lifetime" — yearly users were
      // misclassified and silently lost premium when their year ended.
      final ck = VidComboCheckKeyResponse(
        status: 'active',
        countFree: 999,
        plan: 'plan3',
        endDate: '2027-04-07',
      );

      final result = adapter.toLicenseVerification(ck);

      expect(result.billingCycle, 'yearly');
      expect(
        result.isAutoRenew,
        isFalse,
        reason: 'plan3 is a fixed 1-year purchase, not a recurring sub',
      );
      expect(result.expiresAt, DateTime.parse('2027-04-07'));
    });

    test('lifetime → lifetime (no auto-renew, no expiry)', () {
      final ck = VidComboCheckKeyResponse(
        status: 'active',
        countFree: 999,
        plan: 'lifetime',
        endDate: '',
      );

      final result = adapter.toLicenseVerification(ck);

      expect(result.isValid, isTrue);
      expect(result.billingCycle, 'lifetime');
      expect(result.isAutoRenew, isFalse);
      expect(result.expiresAt, isNull); // empty string → null
    });

    test('inactive user', () {
      final ck = VidComboCheckKeyResponse(
        status: 'inactive',
        countFree: 3,
        message: 'License expired',
      );

      final result = adapter.toLicenseVerification(ck);

      expect(result.isValid, isFalse);
      expect(result.tier, isNull);
      expect(result.reason, 'License expired');
      expect(result.billingCycle, isNull);
      expect(result.isAutoRenew, isFalse);
    });

    test('invalid status with no plan', () {
      final ck = VidComboCheckKeyResponse(status: 'invalid', countFree: 0);

      final result = adapter.toLicenseVerification(ck);

      expect(result.isValid, isFalse);
      expect(result.tier, isNull);
      expect(result.billingCycle, isNull);
    });

    test('verifiedAt is set to approximately now', () {
      final before = DateTime.now();
      final ck = VidComboCheckKeyResponse(
        status: 'active',
        countFree: 10,
        plan: 'plan1',
      );

      final result = adapter.toLicenseVerification(ck);
      final after = DateTime.now();

      expect(
        result.verifiedAt.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        result.verifiedAt.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });
  });

  group('checkKey — HTTP integration', () {
    test('parses successful checkkey.php response', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, contains('checkkey.php'));
        expect(request.url.queryParameters['device_id'], 'test-device-123');
        expect(request.url.queryParameters['app_name'], isNotEmpty);

        return http.Response(
          jsonEncode({
            'license_key': 'ABCDEF01234567890ABCDEF012345678',
            'status': 'active',
            'count_free': 10,
            'lever': 'plan2',
            'end_date': '2027-12-31',
            'mess': 'Active license',
          }),
          200,
        );
      });

      final adapter = VidComboBackendAdapter(
        httpClient: mockClient,
        deviceId: 'test-device-123',
        baseUrl: _testBaseUrl,
      );

      final result = await adapter.checkKey();

      expect(result.status, 'active');
      expect(result.licenseKey, 'ABCDEF01234567890ABCDEF012345678');
      expect(result.countFree, 10);
      expect(result.plan, 'plan2');
      expect(result.isPremium, isTrue);
    });

    test('sends license_key when provided', () async {
      final mockClient = MockClient((request) async {
        expect(
          request.url.queryParameters['license_key'],
          'ABCDEF01234567890ABCDEF012345678',
        );

        return http.Response(
          jsonEncode({
            'status': 'active',
            'count_free': 10,
            'license_key': 'ABCDEF01234567890ABCDEF012345678',
          }),
          200,
        );
      });

      final adapter = VidComboBackendAdapter(
        httpClient: mockClient,
        deviceId: 'test-device-123',
        baseUrl: _testBaseUrl,
      );

      await adapter.checkKey(licenseKey: 'ABCDEF01234567890ABCDEF012345678');
    });

    test('caches 32-char license key from response', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'active',
            'count_free': 10,
            'license_key': 'ABCDEF01234567890ABCDEF012345678',
          }),
          200,
        );
      });

      final adapter = VidComboBackendAdapter(
        httpClient: mockClient,
        deviceId: 'test-device-123',
        baseUrl: _testBaseUrl,
      );

      expect(adapter.licenseKey, isNull);
      await adapter.checkKey();
      expect(adapter.licenseKey, 'ABCDEF01234567890ABCDEF012345678');
    });

    test('does not cache short license key', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'inactive',
            'count_free': 3,
            'license_key': 'short',
          }),
          200,
        );
      });

      final adapter = VidComboBackendAdapter(
        httpClient: mockClient,
        deviceId: 'test-device-123',
        baseUrl: _testBaseUrl,
      );

      await adapter.checkKey();
      expect(adapter.licenseKey, isNull);
    });

    test('caches uppercase alphanumeric 32-char manual PHP key', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'active',
            'count_free': 10,
            'license_key': 'ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ',
          }),
          200,
        );
      });

      final adapter = VidComboBackendAdapter(
        httpClient: mockClient,
        deviceId: 'test-device-123',
        baseUrl: _testBaseUrl,
      );

      await adapter.checkKey();
      expect(adapter.licenseKey, 'ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ');
    });

    test('throws on non-200 status code', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Server Error', 500);
      });

      final adapter = VidComboBackendAdapter(
        httpClient: mockClient,
        deviceId: 'test-device-123',
        baseUrl: _testBaseUrl,
      );

      expect(() => adapter.checkKey(), throwsException);
    });

    test('throws on invalid JSON', () async {
      final mockClient = MockClient((request) async {
        return http.Response('not json', 200);
      });

      final adapter = VidComboBackendAdapter(
        httpClient: mockClient,
        deviceId: 'test-device-123',
        baseUrl: _testBaseUrl,
      );

      expect(() => adapter.checkKey(), throwsA(isA<FormatException>()));
    });

    test('throws FormatException on HTML error page', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          '<html><body><h1>500 Internal Server Error</h1></body></html>',
          200, // PHP often returns 200 with error body
        );
      });

      final adapter = VidComboBackendAdapter(
        httpClient: mockClient,
        deviceId: 'test-device-123',
        baseUrl: _testBaseUrl,
      );

      expect(() => adapter.checkKey(), throwsA(isA<FormatException>()));
    });

    test('throws StateError if device ID is empty', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{}', 200);
      });

      final adapter = VidComboBackendAdapter(
        httpClient: mockClient,
        deviceId: '',
        baseUrl: _testBaseUrl,
      );

      expect(() => adapter.checkKey(), throwsA(isA<StateError>()));
    });
  });

  group('checkUpdate — HTTP integration', () {
    test('parses update available response', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, contains('version.php'));
        expect(request.url.queryParameters['app_name'], isNotEmpty);

        return http.Response(
          jsonEncode({
            'latest_version': '99.0.0',
            'download_url': 'https://vidcombo.net/download',
            'message': 'New features available',
          }),
          200,
        );
      });

      final adapter = VidComboBackendAdapter(
        httpClient: mockClient,
        deviceId: 'test-device-123',
        baseUrl: _testBaseUrl,
      );

      final result = await adapter.checkUpdate();

      expect(result.updateAvailable, isTrue);
      expect(result.latestVersion, '99.0.0');
      expect(result.downloadUrl, 'https://vidcombo.net/download');
      expect(result.releaseNotes, 'New features available');
      expect(result.isMandatory, isFalse); // VidCombo never sets mandatory
    });

    test('no update when version is same or older', () async {
      // AppConstants.appVersion defaults to '0.0.0' in test (init() not called)
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'latest_version': '0.0.0'}), 200);
      });

      final adapter = VidComboBackendAdapter(
        httpClient: mockClient,
        deviceId: 'test-device-123',
        baseUrl: _testBaseUrl,
      );

      final result = await adapter.checkUpdate();

      expect(result.updateAvailable, isFalse);
    });

    test('no update when latest_version is missing', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'message': 'no version info'}), 200);
      });

      final adapter = VidComboBackendAdapter(
        httpClient: mockClient,
        deviceId: 'test-device-123',
        baseUrl: _testBaseUrl,
      );

      final result = await adapter.checkUpdate();

      expect(result.updateAvailable, isFalse);
    });

    test('returns no-update on HTTP error', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Not Found', 404);
      });

      final adapter = VidComboBackendAdapter(
        httpClient: mockClient,
        deviceId: 'test-device-123',
        baseUrl: _testBaseUrl,
      );

      final result = await adapter.checkUpdate();

      expect(result.updateAvailable, isFalse);
    });

    test('returns no-update on network exception', () async {
      final mockClient = MockClient((request) async {
        throw Exception('Network unreachable');
      });

      final adapter = VidComboBackendAdapter(
        httpClient: mockClient,
        deviceId: 'test-device-123',
        baseUrl: _testBaseUrl,
      );

      final result = await adapter.checkUpdate();

      expect(result.updateAvailable, isFalse);
    });

    test('returns no-update on invalid JSON', () async {
      final mockClient = MockClient((request) async {
        return http.Response('not json at all', 200);
      });

      final adapter = VidComboBackendAdapter(
        httpClient: mockClient,
        deviceId: 'test-device-123',
        baseUrl: _testBaseUrl,
      );

      final result = await adapter.checkUpdate();

      expect(result.updateAvailable, isFalse);
    });

    test('returns no-update when latest_version is empty string', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'latest_version': ''}), 200);
      });

      final adapter = VidComboBackendAdapter(
        httpClient: mockClient,
        deviceId: 'test-device-123',
        baseUrl: _testBaseUrl,
      );

      final result = await adapter.checkUpdate();

      expect(result.updateAvailable, isFalse);
    });

    test('returns no-update on HTML error page from version.php', () async {
      final mockClient = MockClient((request) async {
        return http.Response('<html><body>PHP Fatal Error</body></html>', 200);
      });

      final adapter = VidComboBackendAdapter(
        httpClient: mockClient,
        deviceId: 'test-device-123',
        baseUrl: _testBaseUrl,
      );

      final result = await adapter.checkUpdate();

      expect(result.updateAvailable, isFalse);
    });
  });

  group('adapter state management', () {
    test('deviceId is accessible after construction with injection', () {
      final adapter = VidComboBackendAdapter(
        httpClient: MockClient((_) async => http.Response('{}', 200)),
        deviceId: 'my-device-uuid',
        baseUrl: _testBaseUrl,
      );

      expect(adapter.deviceId, 'my-device-uuid');
    });

    test('uses cached license key on subsequent checkKey calls', () async {
      var callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        if (callCount == 1) {
          // First call: no license_key in params
          expect(
            request.url.queryParameters.containsKey('license_key'),
            isFalse,
          );
        } else {
          // Second call: cached license_key sent automatically
          expect(
            request.url.queryParameters['license_key'],
            'ABCDEF01234567890ABCDEF012345678',
          );
        }

        return http.Response(
          jsonEncode({
            'status': 'active',
            'count_free': 10,
            'license_key': 'ABCDEF01234567890ABCDEF012345678',
          }),
          200,
        );
      });

      final adapter = VidComboBackendAdapter(
        httpClient: mockClient,
        deviceId: 'test-device-123',
        baseUrl: _testBaseUrl,
      );

      await adapter.checkKey(); // First call — caches key
      await adapter.checkKey(); // Second call — should send cached key

      expect(callCount, 2);
    });
  });
}
