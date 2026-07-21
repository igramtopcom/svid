import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/floating_capture/domain/services/recent_url_tracker.dart';

void main() {
  group('RecentUrlTracker', () {
    test('isRecentlyActioned returns false for never-marked URL', () {
      final t = RecentUrlTracker();
      expect(t.isRecentlyActioned('https://example.com'), isFalse);
    });

    test('isRecentlyActioned returns true within cooldown', () {
      var now = DateTime(2026, 5, 7, 12, 0, 0);
      final t = RecentUrlTracker(
        cooldown: const Duration(minutes: 2),
        now: () => now,
      );
      t.markActioned('https://example.com');
      now = now.add(const Duration(seconds: 30));
      expect(t.isRecentlyActioned('https://example.com'), isTrue);
    });

    test('isRecentlyActioned returns false after cooldown expires', () {
      var now = DateTime(2026, 5, 7, 12, 0, 0);
      final t = RecentUrlTracker(
        cooldown: const Duration(minutes: 2),
        now: () => now,
      );
      t.markActioned('https://example.com');
      now = now.add(const Duration(minutes: 2, seconds: 1));
      expect(t.isRecentlyActioned('https://example.com'), isFalse);
    });

    test('eviction keeps maxEntries bound, oldest-out', () {
      var now = DateTime(2026, 5, 7, 12, 0, 0);
      final t = RecentUrlTracker(
        maxEntries: 3,
        cooldown: const Duration(hours: 1),
        now: () => now,
      );
      t.markActioned('a');
      now = now.add(const Duration(seconds: 1));
      t.markActioned('b');
      now = now.add(const Duration(seconds: 1));
      t.markActioned('c');
      now = now.add(const Duration(seconds: 1));
      t.markActioned('d'); // 'a' should be evicted
      expect(t.size, 3);
      expect(t.isRecentlyActioned('a'), isFalse);
      expect(t.isRecentlyActioned('b'), isTrue);
      expect(t.isRecentlyActioned('d'), isTrue);
    });

    test('re-marking same URL refreshes timestamp', () {
      var now = DateTime(2026, 5, 7, 12, 0, 0);
      final t = RecentUrlTracker(
        cooldown: const Duration(minutes: 2),
        now: () => now,
      );
      t.markActioned('a');
      now = now.add(const Duration(minutes: 1, seconds: 30));
      t.markActioned('a'); // refresh
      now = now.add(const Duration(minutes: 1)); // 2:30 since first, 1:00 since second
      expect(t.isRecentlyActioned('a'), isTrue); // still within 2min of refresh
    });

    test('clear() resets all entries', () {
      final t = RecentUrlTracker(now: () => DateTime(2026, 5, 7));
      t.markActioned('a');
      t.markActioned('b');
      t.clear();
      expect(t.size, 0);
      expect(t.isRecentlyActioned('a'), isFalse);
      expect(t.isRecentlyActioned('b'), isFalse);
    });

    test('clock drift: now() returns earlier than mark time → no crash', () {
      var now = DateTime(2026, 5, 7, 12, 0, 0);
      final t = RecentUrlTracker(now: () => now);
      t.markActioned('a');
      now = now.subtract(const Duration(hours: 1)); // backwards
      // Negative diff is < cooldown → still considered recent. No crash.
      expect(() => t.isRecentlyActioned('a'), returnsNormally);
    });

    test('isRecentlyActioned does not mark URL itself', () {
      final t = RecentUrlTracker(now: () => DateTime(2026, 5, 7));
      t.isRecentlyActioned('a');
      expect(t.size, 0);
    });
  });
}
