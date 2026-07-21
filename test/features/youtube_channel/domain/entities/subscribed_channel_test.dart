import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/youtube_channel/domain/entities/subscribed_channel.dart';

void main() {
  SubscribedChannel make({
    int id = 1,
    String channelId = 'UC123',
    String channelName = 'Test Channel',
    String? channelHandle,
    String webpageUrl = 'https://www.youtube.com/@test',
    DateTime? subscribedAt,
    DateTime? lastChecked,
    DateTime? latestVideoDate,
    bool hasNewVideos = false,
  }) =>
      SubscribedChannel(
        id: id,
        channelId: channelId,
        channelName: channelName,
        channelHandle: channelHandle,
        webpageUrl: webpageUrl,
        subscribedAt: subscribedAt ?? DateTime(2025, 1, 1),
        lastChecked: lastChecked,
        latestVideoDate: latestVideoDate,
        hasNewVideos: hasNewVideos,
      );

  group('SubscribedChannel', () {
    group('displayHandle', () {
      test('returns handle with @ when present', () {
        expect(make(channelHandle: '@johndoe').displayHandle, '@johndoe');
      });

      test('adds @ prefix if missing', () {
        expect(make(channelHandle: 'johndoe').displayHandle, '@johndoe');
      });

      test('falls back to channel name', () {
        expect(make(channelName: 'My Channel').displayHandle, 'My Channel');
      });

      test('falls back when handle is empty', () {
        expect(
          make(channelHandle: '', channelName: 'Fallback').displayHandle,
          'Fallback',
        );
      });
    });

    group('lastCheckedDisplay', () {
      test('returns not checked for null', () {
        expect(make().lastCheckedDisplay, 'Not checked yet');
      });

      test('returns just now for recent', () {
        final ch = make(lastChecked: DateTime.now());
        expect(ch.lastCheckedDisplay, 'Just now');
      });

      test('returns minutes ago', () {
        final ch = make(
          lastChecked: DateTime.now().subtract(const Duration(minutes: 15)),
        );
        expect(ch.lastCheckedDisplay, '15m ago');
      });

      test('returns hours ago', () {
        final ch = make(
          lastChecked: DateTime.now().subtract(const Duration(hours: 3)),
        );
        expect(ch.lastCheckedDisplay, '3h ago');
      });

      test('returns days ago', () {
        final ch = make(
          lastChecked: DateTime.now().subtract(const Duration(days: 5)),
        );
        expect(ch.lastCheckedDisplay, '5d ago');
      });
    });

    group('latestVideoDateDisplay', () {
      test('returns empty for null', () {
        expect(make().latestVideoDateDisplay, '');
      });

      test('returns Yesterday for 1 day ago', () {
        final ch = make(
          latestVideoDate:
              DateTime.now().subtract(const Duration(hours: 25)),
        );
        expect(ch.latestVideoDateDisplay, 'Yesterday');
      });

      test('returns days ago for recent', () {
        final ch = make(
          latestVideoDate:
              DateTime.now().subtract(const Duration(days: 4)),
        );
        expect(ch.latestVideoDateDisplay, '4 days ago');
      });
    });

    test('hasNewVideos defaults to false', () {
      expect(make().hasNewVideos, isFalse);
    });

    test('freezed equality', () {
      final a = make(id: 1, channelId: 'UC1');
      final b = make(id: 1, channelId: 'UC1');
      expect(a, equals(b));
    });
  });
}
