import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svid/core/binaries/update_schedule_service.dart';

void main() {
  group('UpdateScheduleService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Future<UpdateScheduleService> createService({
      DateTime Function()? clock,
      Map<String, Object>? initialValues,
    }) async {
      if (initialValues != null) {
        SharedPreferences.setMockInitialValues(initialValues);
      }
      final prefs = await SharedPreferences.getInstance();
      return UpdateScheduleService(prefs, clock: clock);
    }

    test('shouldCheckForUpdate returns true when never checked', () async {
      final service = await createService();
      expect(service.shouldCheckForUpdate(), isTrue);
    });

    test('shouldCheckForUpdate returns false within cooldown', () async {
      final now = DateTime(2025, 3, 1, 12, 0, 0);
      final service = await createService(clock: () => now);

      await service.recordCheckTime();

      // 1 hour later — still within 2h cooldown
      final later = DateTime(2025, 3, 1, 13, 0, 0);
      final service2 = await createService(clock: () => later);
      expect(service2.shouldCheckForUpdate(), isFalse);
    });

    test('shouldCheckForUpdate returns true after cooldown elapsed', () async {
      final now = DateTime(2025, 3, 1, 12, 0, 0);
      final service = await createService(clock: () => now);

      await service.recordCheckTime();

      // 3 hours later — past 2h cooldown
      final later = DateTime(2025, 3, 1, 15, 0, 0);
      final service2 = await createService(clock: () => later);
      expect(service2.shouldCheckForUpdate(), isTrue);
    });

    test('shouldCheckForUpdate returns true with corrupted data', () async {
      final service = await createService(
        initialValues: {'last_ytdlp_update_check': 'not-a-date'},
      );
      expect(service.shouldCheckForUpdate(), isTrue);
    });

    test('recordCheckTime stores current time', () async {
      final now = DateTime(2025, 3, 1, 12, 0, 0);
      final service = await createService(clock: () => now);

      await service.recordCheckTime();

      final lastCheck = service.getLastCheckTime();
      expect(lastCheck, isNotNull);
      expect(lastCheck, now);
    });

    test('getLastCheckTime returns null when never checked', () async {
      final service = await createService();
      expect(service.getLastCheckTime(), isNull);
    });

    test('respects custom cooldown duration', () async {
      final now = DateTime(2025, 3, 1, 12, 0, 0);
      final service = await createService(clock: () => now);
      await service.recordCheckTime();

      // 2 hours later
      final later = DateTime(2025, 3, 1, 14, 0, 0);
      final service2 = await createService(clock: () => later);

      // 1h cooldown → should check
      expect(
        service2.shouldCheckForUpdate(cooldown: const Duration(hours: 1)),
        isTrue,
      );
      // 24h cooldown → should not check
      expect(
        service2.shouldCheckForUpdate(cooldown: const Duration(hours: 24)),
        isFalse,
      );
    });
  });
}
