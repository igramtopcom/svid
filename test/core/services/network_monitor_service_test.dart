import 'dart:async';

// Tests for NetworkMonitorService (WiFi-Only Download Mode — #173)

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ssvid/core/services/network_monitor_service.dart';

class MockConnectivity extends Mock implements Connectivity {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockConnectivity mockConnectivity;
  late NetworkMonitorService service;

  setUp(() {
    mockConnectivity = MockConnectivity();
    service = NetworkMonitorService(mockConnectivity);
  });

  group('NetworkMonitorService.isWifi()', () {
    test('returns true when WiFi is the only result', () async {
      when(
        () => mockConnectivity.checkConnectivity(),
      ).thenAnswer((_) async => [ConnectivityResult.wifi]);

      expect(await service.isWifi(), isTrue);
    });

    test('returns true when WiFi is among multiple results', () async {
      when(() => mockConnectivity.checkConnectivity()).thenAnswer(
        (_) async => [ConnectivityResult.wifi, ConnectivityResult.ethernet],
      );

      expect(await service.isWifi(), isTrue);
    });

    test('returns false when only mobile data', () async {
      when(
        () => mockConnectivity.checkConnectivity(),
      ).thenAnswer((_) async => [ConnectivityResult.mobile]);

      expect(await service.isWifi(), isFalse);
    });

    test('returns false when only ethernet (not WiFi)', () async {
      when(
        () => mockConnectivity.checkConnectivity(),
      ).thenAnswer((_) async => [ConnectivityResult.ethernet]);

      expect(await service.isWifi(), isFalse);
    });

    test('returns false when no connection', () async {
      when(
        () => mockConnectivity.checkConnectivity(),
      ).thenAnswer((_) async => [ConnectivityResult.none]);

      expect(await service.isWifi(), isFalse);
    });
  });

  group('NetworkMonitorService.onlineStream', () {
    test(
      'emits connectivity states and swallows platform stream errors',
      () async {
        final controller = StreamController<List<ConnectivityResult>>();
        addTearDown(controller.close);
        when(
          () => mockConnectivity.onConnectivityChanged,
        ).thenAnswer((_) => controller.stream);

        final emitted = <bool>[];
        final errors = <Object>[];
        final sub = service.onlineStream.listen(
          emitted.add,
          onError: errors.add,
        );
        addTearDown(sub.cancel);

        controller.add([ConnectivityResult.wifi]);
        await Future<void>.delayed(Duration.zero);
        controller.addError(
          Exception('NetworkManager::StartListen'),
          StackTrace.current,
        );
        await Future<void>.delayed(Duration.zero);
        controller.add([ConnectivityResult.none]);
        await Future<void>.delayed(Duration.zero);

        expect(emitted, [true, false]);
        expect(errors, isEmpty);
      },
    );
  });
}
