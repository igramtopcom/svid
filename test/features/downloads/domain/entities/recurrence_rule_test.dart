import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/domain/entities/recurrence_rule.dart';

void main() {
  group('RecurrenceRule', () {
    // ── toJson / fromJson ──────────────────────────────────────────────────

    group('serialisation', () {
      test('roundtrip — none', () {
        const rule = RecurrenceRule(type: RecurrenceType.none);
        expect(RecurrenceRule.fromJson(rule.toJson()), equals(rule));
      });

      test('roundtrip — daily', () {
        const rule = RecurrenceRule(type: RecurrenceType.daily);
        expect(RecurrenceRule.fromJson(rule.toJson()), equals(rule));
      });

      test('roundtrip — weekdays', () {
        const rule = RecurrenceRule(type: RecurrenceType.weekdays);
        expect(RecurrenceRule.fromJson(rule.toJson()), equals(rule));
      });

      test('roundtrip — weekends', () {
        const rule = RecurrenceRule(type: RecurrenceType.weekends);
        expect(RecurrenceRule.fromJson(rule.toJson()), equals(rule));
      });

      test('roundtrip — weekly with days', () {
        final rule = RecurrenceRule(type: RecurrenceType.weekly, daysOfWeek: {1, 3, 5});
        expect(RecurrenceRule.fromJson(rule.toJson()), equals(rule));
      });

      test('fromJson invalid JSON → returns none', () {
        expect(RecurrenceRule.fromJson('not json'), equals(RecurrenceRule.none));
      });

      test('fromJson unknown type → returns none', () {
        expect(RecurrenceRule.fromJson('{"type":"bogus","daysOfWeek":[]}'),
            equals(RecurrenceRule.none));
      });
    });

    // ── isRecurring ────────────────────────────────────────────────────────

    group('isRecurring', () {
      test('none → false', () => expect(RecurrenceRule.none.isRecurring, isFalse));
      test('daily → true', () => expect(const RecurrenceRule(type: RecurrenceType.daily).isRecurring, isTrue));
    });

    // ── nextOccurrence ─────────────────────────────────────────────────────

    group('nextOccurrence', () {
      // Wednesday 2026-03-04 14:00
      final base = DateTime(2026, 3, 4, 14, 0); // Wednesday

      test('none → returns same datetime', () {
        expect(RecurrenceRule.none.nextOccurrence(base), equals(base));
      });

      test('daily → adds 1 day', () {
        final next = const RecurrenceRule(type: RecurrenceType.daily).nextOccurrence(base);
        expect(next, equals(base.add(const Duration(days: 1))));
      });

      test('weekdays — from Wednesday → Thursday', () {
        final next = const RecurrenceRule(type: RecurrenceType.weekdays).nextOccurrence(base);
        expect(next.weekday, equals(DateTime.thursday));
      });

      test('weekdays — from Friday → Monday (skips Sat+Sun)', () {
        final friday = DateTime(2026, 3, 6, 14, 0);
        final next = const RecurrenceRule(type: RecurrenceType.weekdays).nextOccurrence(friday);
        expect(next.weekday, equals(DateTime.monday));
      });

      test('weekends — from Wednesday → Saturday', () {
        final next = const RecurrenceRule(type: RecurrenceType.weekends).nextOccurrence(base);
        expect(next.weekday, equals(DateTime.saturday));
      });

      test('weekends — from Saturday → Sunday', () {
        final saturday = DateTime(2026, 3, 7, 14, 0);
        final next = const RecurrenceRule(type: RecurrenceType.weekends).nextOccurrence(saturday);
        expect(next.weekday, equals(DateTime.sunday));
      });

      test('weekly custom [Mon,Wed] — from Wednesday → next Monday', () {
        final rule = RecurrenceRule(type: RecurrenceType.weekly, daysOfWeek: {1, 3}); // Mon,Wed
        final next = rule.nextOccurrence(base); // base is Wednesday
        expect(next.weekday, equals(DateTime.monday));
      });

      test('weekly custom [Thu] — from Wednesday → Thursday', () {
        final rule = RecurrenceRule(type: RecurrenceType.weekly, daysOfWeek: {4}); // Thu
        final next = rule.nextOccurrence(base);
        expect(next.weekday, equals(DateTime.thursday));
      });

      test('weekly empty days → falls back to +7 days', () {
        final rule = const RecurrenceRule(type: RecurrenceType.weekly);
        final next = rule.nextOccurrence(base);
        expect(next, equals(base.add(const Duration(days: 7))));
      });
    });

    // ── equality ──────────────────────────────────────────────────────────

    group('equality', () {
      test('same type same days → equal', () {
        final a = RecurrenceRule(type: RecurrenceType.weekly, daysOfWeek: {1, 3});
        final b = RecurrenceRule(type: RecurrenceType.weekly, daysOfWeek: {3, 1});
        expect(a, equals(b));
      });

      test('different types → not equal', () {
        expect(const RecurrenceRule(type: RecurrenceType.daily),
            isNot(const RecurrenceRule(type: RecurrenceType.weekdays)));
      });

      test('same type different days → not equal', () {
        final a = RecurrenceRule(type: RecurrenceType.weekly, daysOfWeek: {1});
        final b = RecurrenceRule(type: RecurrenceType.weekly, daysOfWeek: {2});
        expect(a, isNot(b));
      });
    });
  });
}
