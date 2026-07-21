import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/floating_capture/domain/entities/snooze_duration.dart';

void main() {
  group('wireKey round-trip', () {
    test('every variant has a unique stable wireKey', () {
      final keys = SnoozeDuration.values.map((v) => v.wireKey).toList();
      expect(keys.toSet().length, keys.length, reason: 'wireKeys not unique');
    });

    test('snoozeDurationFromWire reverses wireKey for every variant', () {
      for (final v in SnoozeDuration.values) {
        expect(snoozeDurationFromWire(v.wireKey), v);
      }
    });

    test('unknown wire string returns null (forward compat)', () {
      expect(snoozeDurationFromWire('quarterCentury'), isNull);
    });

    test('null input returns null', () {
      expect(snoozeDurationFromWire(null), isNull);
    });
  });

  group('resolveEnd', () {
    final reference = DateTime(2026, 1, 15, 10, 30); // noon-ish weekday

    test('thirtyMinutes adds 30 minutes', () {
      expect(
        SnoozeDuration.thirtyMinutes.resolveEnd(reference),
        DateTime(2026, 1, 15, 11, 0),
      );
    });

    test('oneHour adds 1 hour', () {
      expect(
        SnoozeDuration.oneHour.resolveEnd(reference),
        DateTime(2026, 1, 15, 11, 30),
      );
    });

    test('fourHours adds 4 hours', () {
      expect(
        SnoozeDuration.fourHours.resolveEnd(reference),
        DateTime(2026, 1, 15, 14, 30),
      );
    });

    test('oneDay returns now + 24 hours (Codex P1 #7 fix)', () {
      // Spec §13: "1 day" = 24 hours from selection moment.
      // Previously this variant was untilEndOfDay (midnight today),
      // which gave 23:50-pickers only 10 minutes of snooze.
      expect(
        SnoozeDuration.oneDay.resolveEnd(reference),
        reference.add(const Duration(days: 1)),
      );
    });

    test('oneDay across month boundary still adds 24h literally', () {
      final endOfMonth = DateTime(2026, 1, 31, 23, 59);
      expect(
        SnoozeDuration.oneDay.resolveEnd(endOfMonth),
        DateTime(2026, 2, 1, 23, 59),
      );
    });

    test('legacy untilEndOfDay wireKey deserialises to oneDay', () {
      // Backward compat: state persisted by Phase 1A.5–1A.7 builds
      // used wireKey "untilEndOfDay". After the rename, fromWire()
      // must still parse it so existing snoozes survive the upgrade.
      expect(
        snoozeDurationFromWire('untilEndOfDay'),
        SnoozeDuration.oneDay,
      );
    });

    test('untilManuallyResumed returns null', () {
      expect(
        SnoozeDuration.untilManuallyResumed.resolveEnd(reference),
        isNull,
      );
    });
  });
}
