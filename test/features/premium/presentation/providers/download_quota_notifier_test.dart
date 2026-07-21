import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svid/features/premium/domain/entities/premium_limits.dart';
import 'package:svid/features/premium/domain/services/download_quota_tracker.dart';
import 'package:svid/features/premium/presentation/providers/premium_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DownloadQuotaNotifier', () {
    late SharedPreferences prefs;
    late DownloadQuotaTracker tracker;
    late DownloadQuotaNotifier notifier;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      tracker = DownloadQuotaTracker(prefs);
      notifier = DownloadQuotaNotifier(tracker);
    });

    test('emits consumed count when free user consumes quota', () {
      expect(notifier.state, 0);

      final consumed = notifier.tryConsume(isPremium: false);

      expect(consumed, isTrue);
      expect(notifier.state, 1);
      expect(tracker.currentPeriodCount(), 1);
    });

    test('emits capped count when free weekly quota is exhausted', () {
      for (var i = 0; i < PremiumLimits.freeWeeklyDownloads; i++) {
        expect(notifier.tryConsume(isPremium: false), isTrue);
      }

      expect(notifier.tryConsume(isPremium: false), isFalse);
      expect(notifier.state, PremiumLimits.freeWeeklyDownloads);
    });

    test('premium consume leaves free quota count unchanged', () {
      final consumed = notifier.tryConsume(isPremium: true);

      expect(consumed, isTrue);
      expect(notifier.state, 0);
      expect(tracker.currentPeriodCount(), 0);
    });

    test('remainingThisWeek returns unlimited marker for premium', () {
      expect(notifier.remainingThisWeek(isPremium: true), -1);
    });

    test('syncFromServer emits synced count', () {
      notifier.syncFromServer(3);

      expect(notifier.state, 3);
      expect(tracker.currentPeriodCount(), 3);
    });

    test('reset clears persisted count and emits zero', () async {
      expect(notifier.tryConsume(isPremium: false), isTrue);

      await notifier.reset();

      expect(notifier.state, 0);
      expect(tracker.currentPeriodCount(), 0);
    });

    test('resets when UTC ISO week changes', () async {
      var now = DateTime.utc(2026, 5, 17, 23); // Sunday
      tracker = DownloadQuotaTracker(prefs, clock: () => now);
      notifier = DownloadQuotaNotifier(tracker);

      expect(notifier.tryConsume(isPremium: false), isTrue);
      expect(notifier.state, 1);

      now = DateTime.utc(2026, 5, 18); // next Monday
      expect(notifier.currentPeriodCount(), 0);
      expect(notifier.remainingThisWeek(isPremium: false), 15);
    });

    test('legacy daily keys do not carry into weekly quota', () async {
      await prefs.setString('download_quota_date', '2026-05-14');
      await prefs.setInt('download_quota_count', 15);

      tracker = DownloadQuotaTracker(
        prefs,
        clock: () => DateTime.utc(2026, 5, 14),
      );
      notifier = DownloadQuotaNotifier(tracker);

      expect(notifier.currentPeriodCount(), 0);
      expect(notifier.remainingThisWeek(isPremium: false), 15);
    });
  });
}
