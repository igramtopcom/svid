import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/floating_capture/data/datasources/in_memory_snooze_store.dart';
import 'package:ssvid/features/floating_capture/domain/entities/snooze_duration.dart';
import 'package:ssvid/features/floating_capture/domain/entities/snooze_state.dart';

void main() {
  group('isActive', () {
    final reference = DateTime(2026, 1, 15, 10, 0);

    test('inactive state is never active', () {
      expect(SnoozeState.inactive.isActive(reference), isFalse);
    });

    test('timed snooze active before endsAt', () {
      final s = SnoozeState(
        endsAt: DateTime(2026, 1, 15, 11, 0),
        duration: SnoozeDuration.oneHour,
      );
      expect(s.isActive(reference), isTrue);
    });

    test('timed snooze inactive at exact endsAt', () {
      final endsAt = DateTime(2026, 1, 15, 11, 0);
      final s = SnoozeState(
        endsAt: endsAt,
        duration: SnoozeDuration.oneHour,
      );
      expect(s.isActive(endsAt), isFalse, reason: 'inclusive boundary');
    });

    test('timed snooze inactive after endsAt', () {
      final s = SnoozeState(
        endsAt: DateTime(2026, 1, 15, 9, 0),
        duration: SnoozeDuration.oneHour,
      );
      expect(s.isActive(reference), isFalse);
    });

    test('manual snooze always active regardless of endsAt', () {
      const s = SnoozeState(
        endsAt: null,
        duration: SnoozeDuration.untilManuallyResumed,
      );
      expect(s.isActive(DateTime(2026, 1, 15)), isTrue);
      expect(s.isActive(DateTime(2030, 1, 1)), isTrue);
    });
  });

  group('JSON round-trip', () {
    test('inactive round-trips to inactive', () {
      final json = SnoozeState.inactive.toJson();
      expect(json, isEmpty);
      expect(SnoozeState.fromJson(json), SnoozeState.inactive);
    });

    test('timed state preserves endsAt + duration', () {
      final original = SnoozeState(
        endsAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        duration: SnoozeDuration.fourHours,
      );
      final round = SnoozeState.fromJson(original.toJson());
      expect(round, original);
    });

    test('manual state preserves duration even with null endsAt', () {
      const original = SnoozeState(
        duration: SnoozeDuration.untilManuallyResumed,
      );
      final round = SnoozeState.fromJson(original.toJson());
      expect(round.duration, SnoozeDuration.untilManuallyResumed);
      expect(round.endsAt, isNull);
    });

    test('unknown duration wireKey collapses to inactive (forward compat)', () {
      final json = {'duration': 'oneCentury', 'endsAtMs': 999};
      expect(SnoozeState.fromJson(json), SnoozeState.inactive);
    });

    test('missing endsAtMs but valid duration → endsAt null', () {
      final json = {'duration': 'thirtyMinutes'};
      final s = SnoozeState.fromJson(json);
      expect(s.duration, SnoozeDuration.thirtyMinutes);
      expect(s.endsAt, isNull);
    });
  });

  group('equality', () {
    test('two inactive states are equal', () {
      expect(SnoozeState.inactive, const SnoozeState());
    });

    test('different endsAt → not equal', () {
      final a = SnoozeState(
        endsAt: DateTime(2026, 1, 1),
        duration: SnoozeDuration.oneHour,
      );
      final b = SnoozeState(
        endsAt: DateTime(2026, 1, 2),
        duration: SnoozeDuration.oneHour,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('InMemorySnoozeStore', () {
    test('starts inactive when no initial state', () async {
      final store = InMemorySnoozeStore();
      expect(await store.read(), SnoozeState.inactive);
      expect(store.readCount, 1);
    });

    test('initial state is reflected', () async {
      const initial = SnoozeState(
        duration: SnoozeDuration.untilManuallyResumed,
      );
      final store = InMemorySnoozeStore(initial: initial);
      expect(await store.read(), initial);
    });

    test('write replaces current and adds to writes log', () async {
      final store = InMemorySnoozeStore();
      final s1 = SnoozeState(
        endsAt: DateTime(2026, 1, 1),
        duration: SnoozeDuration.thirtyMinutes,
      );
      final s2 = SnoozeState(
        endsAt: DateTime(2026, 1, 2),
        duration: SnoozeDuration.oneHour,
      );
      await store.write(s1);
      await store.write(s2);
      expect(await store.read(), s2);
      expect(store.writes, [s1, s2]);
    });
  });
}
