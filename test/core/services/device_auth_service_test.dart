import 'package:dio/dio.dart' show Options;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svid/core/constants/app_constants.dart';
import 'package:svid/core/network/backend_client.dart';
import 'package:svid/core/network/backend_dtos.dart';
import 'package:svid/core/services/device_auth_service.dart';
import 'package:svid/core/services/secure_credential_store.dart';

class _FakeCredentialStore extends SecureCredentialStore {
  _FakeCredentialStore(this._prefs) : super(_prefs);

  final SharedPreferences _prefs;
  final Map<String, String> _store = {};

  @override
  Future<bool> containsKey(String key) async => _store.containsKey(key);

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async {
    _store[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
    await _prefs.remove(key);
  }
}

class _FakeBackendClient extends BackendClient {
  _FakeBackendClient(super.credentials);

  dynamic lastPostNoAuthData;
  dynamic lastPostData;
  final postNoAuthCalls = <({String path, dynamic data})>[];
  Object? postNoAuthError;
  Object? postError;
  RegisterResponse registerResponse = RegisterResponse(
    deviceId: 'device-123',
    apiKey: 'api-key-123',
    isNew: true,
  );
  HeartbeatResponse heartbeatResponse = HeartbeatResponse(
    serverTime: '2026-04-17T11:30:00Z',
  );

  @override
  Future<T> postNoAuth<T>(
    String path, {
    data,
    Options? options,
    required T Function(dynamic json) fromJson,
  }) async {
    postNoAuthCalls.add((path: path, data: data));
    if (path == '/devices/register') {
      if (postNoAuthError != null) throw postNoAuthError!;
      lastPostNoAuthData = data;
      return registerResponse as T;
    }
    return fromJson(null);
  }

  @override
  Future<T> post<T>(
    String path, {
    data,
    Options? options, // added in Item B; ignored by this test fake
    required T Function(dynamic json) fromJson,
  }) async {
    if (postError != null) throw postError!;
    lastPostData = data;
    return heartbeatResponse as T;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late _FakeCredentialStore credentials;
  late _FakeBackendClient client;

  DeviceAuthService buildService({
    Future<String?> Function()? generateFingerprint,
    String Function()? generateLegacyFingerprint,
    String Function()? platformOsProvider,
    String Function()? osVersionProvider,
    String Function()? deviceNameProvider,
    String Function()? brandNameProvider,
    String Function()? installIdProvider,
  }) {
    return DeviceAuthService(
      client,
      credentials,
      generateFingerprint: generateFingerprint,
      generateLegacyFingerprint: generateLegacyFingerprint,
      platformOsProvider: platformOsProvider,
      osVersionProvider: osVersionProvider,
      deviceNameProvider: deviceNameProvider,
      brandNameProvider: brandNameProvider,
      installIdProvider: installIdProvider,
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    credentials = _FakeCredentialStore(prefs);
    client = _FakeBackendClient(credentials);
  });

  group('DeviceAuthService.register', () {
    test(
      'sends strong and legacy hardware ids, then persists credentials',
      () async {
        final service = buildService(
          generateLegacyFingerprint: () => 'legacy-fingerprint',
          generateFingerprint: () async => 'strong-fingerprint',
          platformOsProvider: () => 'macos',
          osVersionProvider: () => 'macOS 14.5',
          deviceNameProvider: () => 'My Mac',
          brandNameProvider: () => 'ssvid',
        );

        final success = await service.register();

        expect(success, isTrue);
        expect(client.lastPostNoAuthData, isA<Map<String, dynamic>>());
        expect(
          client.lastPostNoAuthData,
          containsPair('hardware_id', 'strong-fingerprint'),
        );
        expect(
          client.lastPostNoAuthData,
          containsPair('legacy_hardware_id', 'legacy-fingerprint'),
        );
        expect(client.lastPostNoAuthData, containsPair('os', 'macos'));
        expect(
          client.lastPostNoAuthData,
          containsPair('os_version', 'macOS 14.5'),
        );
        expect(
          client.lastPostNoAuthData,
          containsPair('device_name', 'My Mac'),
        );
        expect(client.lastPostNoAuthData, containsPair('brand', 'ssvid'));
        expect(
          client.lastPostNoAuthData,
          containsPair('app_version', AppConstants.appVersion),
        );
        expect(await credentials.read(PrefKeys.backendApiKey), 'api-key-123');
        expect(await credentials.read(PrefKeys.deviceId), 'device-123');
      },
    );

    test('emits bootstrap register started and succeeded events', () async {
      final service = buildService(
        generateLegacyFingerprint: () => 'legacy-fingerprint',
        generateFingerprint: () async => 'strong-fingerprint',
        platformOsProvider: () => 'macos',
        osVersionProvider: () => 'macOS 14.5',
        deviceNameProvider: () => 'My Mac',
        brandNameProvider: () => 'ssvid',
        installIdProvider: () => 'install-test-123',
      );

      final success = await service.register();
      await _drainBootstrapTelemetry();

      expect(success, isTrue);
      final bootstrapCalls =
          client.postNoAuthCalls
              .where((call) => call.path == '/bootstrap/events')
              .toList();
      expect(bootstrapCalls, hasLength(2));
      expect(
        bootstrapCalls[0].data,
        containsPair('install_id', 'install-test-123'),
      );
      expect(bootstrapCalls[0].data, containsPair('stage', 'register'));
      expect(bootstrapCalls[0].data, containsPair('status', 'started'));
      expect(bootstrapCalls[1].data, containsPair('status', 'succeeded'));
      expect(
        await credentials.read(PrefKeys.bootstrapInstallId),
        'install-test-123',
      );
    });

    test(
      'falls back to legacy hardware id when strong fingerprint unavailable',
      () async {
        final service = buildService(
          generateLegacyFingerprint: () => 'legacy-fingerprint',
          generateFingerprint: () async => null,
          platformOsProvider: () => 'windows',
          osVersionProvider: () => 'Windows 11',
          deviceNameProvider: () => 'Desktop',
          brandNameProvider: () => 'vidcombo',
        );

        final success = await service.register();

        expect(success, isTrue);
        expect(
          client.lastPostNoAuthData,
          containsPair('hardware_id', 'legacy-fingerprint'),
        );
        expect(
          (client.lastPostNoAuthData as Map<String, dynamic>).containsKey(
            'legacy_hardware_id',
          ),
          isFalse,
        );
        expect(client.lastPostNoAuthData, containsPair('brand', 'vidcombo'));
      },
    );

    test(
      'returns false and does not persist credentials on backend failure',
      () async {
        client.postNoAuthError = Exception('backend down');
        final service = buildService(
          generateLegacyFingerprint: () => 'legacy-fingerprint',
          generateFingerprint: () async => 'strong-fingerprint',
          installIdProvider: () => 'install-test-123',
        );

        final success = await service.register();
        await _drainBootstrapTelemetry();

        expect(success, isFalse);
        expect(await credentials.read(PrefKeys.backendApiKey), isNull);
        expect(await credentials.read(PrefKeys.deviceId), isNull);
        final failedEvents =
            client.postNoAuthCalls
                .where(
                  (call) =>
                      call.path == '/bootstrap/events' &&
                      (call.data as Map<String, dynamic>)['status'] == 'failed',
                )
                .toList();
        expect(failedEvents, hasLength(1));
        expect(
          failedEvents.single.data,
          containsPair('error_code', 'exception'),
        );
      },
    );
  });

  group('DeviceAuthService.heartbeat', () {
    test('does nothing when device is not registered', () async {
      final service = buildService();

      await service.heartbeat(tier: 'premium');

      expect(client.lastPostData, isNull);
    });

    test('sends brand, app version, and tier when registered', () async {
      await credentials.write(PrefKeys.backendApiKey, 'api-key-123');

      final service = buildService(brandNameProvider: () => 'vidcombo');

      await service.heartbeat(tier: 'premium');

      expect(client.lastPostData, isA<Map<String, dynamic>>());
      expect(client.lastPostData, containsPair('brand', 'vidcombo'));
      expect(client.lastPostData, containsPair('tier', 'premium'));
      expect(
        client.lastPostData,
        containsPair('app_version', AppConstants.appVersion),
      );
    });
  });
}

Future<void> _drainBootstrapTelemetry() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
