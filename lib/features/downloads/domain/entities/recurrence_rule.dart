import 'dart:convert';

/// Recurrence type for scheduled downloads.
enum RecurrenceType {
  none,
  daily,
  weekdays, // Mon–Fri
  weekends, // Sat–Sun
  weekly, // Custom days-of-week selection
}

/// Immutable value object describing how a scheduled download recurs.
///
/// Stored as JSON in [DownloadEntity.recurrenceRuleJson].
class RecurrenceRule {
  final RecurrenceType type;

  /// ISO weekday numbers (1=Mon … 7=Sun).
  /// Only meaningful when [type] is [RecurrenceType.weekly].
  final Set<int> daysOfWeek;

  const RecurrenceRule({required this.type, this.daysOfWeek = const {}});

  static const RecurrenceRule none = RecurrenceRule(type: RecurrenceType.none);

  bool get isRecurring => type != RecurrenceType.none;

  /// Returns the next scheduled datetime at the same time-of-day after [lastFired].
  DateTime nextOccurrence(DateTime lastFired) {
    switch (type) {
      case RecurrenceType.none:
        return lastFired;
      case RecurrenceType.daily:
        return lastFired.add(const Duration(days: 1));
      case RecurrenceType.weekdays:
        var next = lastFired.add(const Duration(days: 1));
        while (next.weekday == DateTime.saturday || next.weekday == DateTime.sunday) {
          next = next.add(const Duration(days: 1));
        }
        return next;
      case RecurrenceType.weekends:
        var next = lastFired.add(const Duration(days: 1));
        while (next.weekday != DateTime.saturday && next.weekday != DateTime.sunday) {
          next = next.add(const Duration(days: 1));
        }
        return next;
      case RecurrenceType.weekly:
        if (daysOfWeek.isEmpty) return lastFired.add(const Duration(days: 7));
        var next = lastFired.add(const Duration(days: 1));
        for (int i = 0; i < 7; i++) {
          if (daysOfWeek.contains(next.weekday)) return next;
          next = next.add(const Duration(days: 1));
        }
        return lastFired.add(const Duration(days: 7));
    }
  }

  String toJson() => jsonEncode({
        'type': type.name,
        'daysOfWeek': (daysOfWeek.toList()..sort()),
      });

  static RecurrenceRule fromJson(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final type = RecurrenceType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => RecurrenceType.none,
      );
      final days = (map['daysOfWeek'] as List?)?.map((e) => e as int).toSet() ?? {};
      return RecurrenceRule(type: type, daysOfWeek: days);
    } catch (_) {
      return RecurrenceRule.none;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is RecurrenceRule &&
      other.type == type &&
      _setsEqual(other.daysOfWeek, daysOfWeek);

  @override
  int get hashCode => Object.hash(type, Object.hashAll(daysOfWeek.toList()..sort()));

  bool _setsEqual(Set<int> a, Set<int> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  @override
  String toString() => 'RecurrenceRule(type: $type, daysOfWeek: $daysOfWeek)';
}
