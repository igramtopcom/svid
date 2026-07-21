import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/domain/services/quiet_hours_service.dart';
import 'package:ssvid/features/downloads/domain/services/network_throughput_monitor.dart';

void main() {
  const svc = QuietHoursService();

  group('QuietHoursService.isQuietHour', () {
    // Overnight window: 22:00–07:00
    const start = 22;
    const end = 7;

    test('23:00 is inside overnight window', () {
      expect(svc.isQuietHour(now: DateTime(2026, 1, 1, 23, 0), startHour: start, endHour: end), isTrue);
    });

    test('00:00 is inside overnight window', () {
      expect(svc.isQuietHour(now: DateTime(2026, 1, 1, 0, 0), startHour: start, endHour: end), isTrue);
    });

    test('06:59 is inside overnight window', () {
      expect(svc.isQuietHour(now: DateTime(2026, 1, 1, 6, 59), startHour: start, endHour: end), isTrue);
    });

    test('07:00 is outside overnight window', () {
      expect(svc.isQuietHour(now: DateTime(2026, 1, 1, 7, 0), startHour: start, endHour: end), isFalse);
    });

    test('12:00 is outside overnight window', () {
      expect(svc.isQuietHour(now: DateTime(2026, 1, 1, 12, 0), startHour: start, endHour: end), isFalse);
    });

    // Same-day window: 09:00–17:00
    const startDay = 9;
    const endDay = 17;

    test('10:00 is inside same-day window', () {
      expect(svc.isQuietHour(now: DateTime(2026, 1, 1, 10, 0), startHour: startDay, endHour: endDay), isTrue);
    });

    test('08:59 is outside same-day window', () {
      expect(svc.isQuietHour(now: DateTime(2026, 1, 1, 8, 59), startHour: startDay, endHour: endDay), isFalse);
    });

    test('17:00 is outside same-day window (exclusive end)', () {
      expect(svc.isQuietHour(now: DateTime(2026, 1, 1, 17, 0), startHour: startDay, endHour: endDay), isFalse);
    });
  });

  group('QuietHoursService.getEffectiveLimitKbps', () {
    const quietKbps = 1024;
    const normalKbps = 0; // unlimited

    test('disabled → returns normalKbps regardless of time', () {
      final result = svc.getEffectiveLimitKbps(
        now: DateTime(2026, 1, 1, 23, 0),
        enabled: false,
        startHour: 22,
        endHour: 7,
        quietKbps: quietKbps,
        normalKbps: normalKbps,
      );
      expect(result, normalKbps);
    });

    test('enabled + inside window → returns quietKbps', () {
      final result = svc.getEffectiveLimitKbps(
        now: DateTime(2026, 1, 1, 23, 0),
        enabled: true,
        startHour: 22,
        endHour: 7,
        quietKbps: quietKbps,
        normalKbps: normalKbps,
      );
      expect(result, quietKbps);
    });

    test('enabled + outside window → returns normalKbps', () {
      final result = svc.getEffectiveLimitKbps(
        now: DateTime(2026, 1, 1, 14, 0),
        enabled: true,
        startHour: 22,
        endHour: 7,
        quietKbps: quietKbps,
        normalKbps: normalKbps,
      );
      expect(result, normalKbps);
    });
  });

  group('SpeedRollingAverage', () {
    test('no samples → average is 0', () {
      final avg = SpeedRollingAverage();
      expect(avg.average, 0);
    });

    test('single sample → average equals sample (padded with zeros)', () {
      final avg = SpeedRollingAverage();
      avg.add(500);
      expect(avg.average, 500 ~/ 5); // 100 — 4 zeros + one 500
    });

    test('5 equal samples → average equals sample', () {
      final avg = SpeedRollingAverage();
      for (int i = 0; i < 5; i++) {
        avg.add(1000);
      }
      expect(avg.average, 1000);
    });

    test('rolling: drops oldest when window full', () {
      final avg = SpeedRollingAverage();
      // Fill window with 0s then add 1000×5
      for (int i = 0; i < 5; i++) {
        avg.add(0);
      }
      for (int i = 0; i < 5; i++) {
        avg.add(1000);
      }
      expect(avg.average, 1000); // all slots now 1000
    });

    test('reset → average becomes 0', () {
      final avg = SpeedRollingAverage();
      for (int i = 0; i < 5; i++) {
        avg.add(1000);
      }
      avg.reset();
      expect(avg.average, 0);
    });
  });
}
