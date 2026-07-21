import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/core/utils/platform_detector.dart';
import 'package:ssvid/features/downloads/domain/entities/video_preview.dart';
import 'package:ssvid/features/floating_capture/data/datasources/mock_floating_window.dart';
import 'package:ssvid/features/floating_capture/domain/entities/floating_window_event.dart';
import 'package:ssvid/features/floating_capture/domain/entities/snooze_duration.dart';

void main() {
  late MockFloatingWindow window;

  VideoPreview preview({String url = 'https://youtube.com/watch?v=abcdef12345'}) {
    return VideoPreview(
      rawUrl: url,
      platform: VideoPlatform.youtube,
      urlType: UrlType.video,
      itemId: 'abcdef12345',
      title: 'T',
      uploader: 'U',
      thumbnailUrl: 'https://x/y.jpg',
      hasFetchedMetadata: true,
    );
  }

  setUp(() {
    window = MockFloatingWindow();
  });

  group('initial state', () {
    test('isSpawned=false, isVisible=false before spawn', () {
      expect(window.isSpawned, isFalse);
      expect(window.isVisible, isFalse);
    });

    test('counters start at zero, buffers empty', () {
      expect(window.spawnCallCount, 0);
      expect(window.previewsShown, isEmpty);
      expect(window.queuePushes, isEmpty);
      expect(window.quotaUpdates, isEmpty);
    });
  });

  group('spawn lifecycle', () {
    test('spawn flips spawned + visible, records preview', () async {
      final p = preview();
      await window.spawn(initialPreview: p);

      expect(window.isSpawned, isTrue);
      expect(window.isVisible, isTrue);
      expect(window.spawnCallCount, 1);
      expect(window.previewsShown, [p]);
    });

    test('idempotent spawn — second call no-op', () async {
      await window.spawn(initialPreview: preview());
      await window.spawn(initialPreview: preview(url: 'https://other'));

      expect(window.spawnCallCount, 2,
          reason: 'counter still increments');
      expect(window.previewsShown.length, 1,
          reason: 'second spawn does not re-record preview');
    });
  });

  group('visibility', () {
    setUp(() async {
      await window.spawn(initialPreview: preview());
    });

    test('hide flips visible=false, keeps spawned=true', () async {
      await window.hide();
      expect(window.isVisible, isFalse);
      expect(window.isSpawned, isTrue);
    });

    test('show after hide makes visible=true again', () async {
      await window.hide();
      await window.show();
      expect(window.isVisible, isTrue);
    });

    test('show before spawn throws StateError', () async {
      final fresh = MockFloatingWindow();
      expect(() => fresh.show(), throwsStateError);
    });

    test('hide before spawn is a no-op (does not throw)', () async {
      final fresh = MockFloatingWindow();
      await fresh.hide();
      expect(fresh.hideCallCount, 1);
      expect(fresh.isVisible, isFalse);
    });
  });

  group('queue + preview forwarding', () {
    setUp(() async {
      await window.spawn(initialPreview: preview());
    });

    test('pushQueue appends in order', () async {
      final p1 = preview(url: 'a');
      final p2 = preview(url: 'b');
      await window.pushQueue(p1);
      await window.pushQueue(p2);

      expect(window.queuePushes, [p1, p2]);
    });

    test('showPreview replaces, restores visibility', () async {
      await window.hide();
      final p = preview(url: 'new');
      await window.showPreview(p);

      expect(window.previewsShown.last, p);
      expect(window.isVisible, isTrue);
    });

    test('clearQueue empties + hides', () async {
      await window.pushQueue(preview(url: 'a'));
      await window.pushQueue(preview(url: 'b'));
      await window.clearQueue();

      expect(window.queuePushes, isEmpty);
      expect(window.isVisible, isFalse);
      expect(window.clearQueueCallCount, 1);
    });

    test('pushQueue before spawn throws', () async {
      final fresh = MockFloatingWindow();
      expect(() => fresh.pushQueue(preview()), throwsStateError);
    });
  });

  group('quota', () {
    setUp(() async {
      await window.spawn(initialPreview: preview());
    });

    test('setQuotaState records each update in order', () async {
      await window.setQuotaState(remaining: 5);
      await window.setQuotaState(remaining: 4);
      await window.setQuotaState(remaining: 0);
      expect(window.quotaUpdates, [5, 4, 0]);
    });

    test('-1 (unlimited) is preserved as sentinel', () async {
      await window.setQuotaState(remaining: -1);
      expect(window.quotaUpdates.single, -1);
    });
  });

  group('event emission (popup → main)', () {
    setUp(() async {
      await window.spawn(initialPreview: preview());
    });

    test('emits to subscribers via broadcast stream', () async {
      final received = <FloatingWindowEvent>[];
      final sub = window.events.listen(received.add);

      window.emit(const DownloadClicked(url: 'u1'));
      window.emit(const SnoozeSelected(SnoozeDuration.oneHour));
      window.emit(const PopupDismissed());

      // Pump microtasks so listener fires.
      await Future<void>.delayed(Duration.zero);

      expect(received.length, 3);
      expect(received[0], isA<DownloadClicked>());
      expect((received[0] as DownloadClicked).url, 'u1');
      expect(received[1], isA<SnoozeSelected>());
      expect(received[2], isA<PopupDismissed>());

      await sub.cancel();
    });

    test('multiple subscribers (broadcast)', () async {
      final a = <FloatingWindowEvent>[];
      final b = <FloatingWindowEvent>[];
      final subA = window.events.listen(a.add);
      final subB = window.events.listen(b.add);

      window.emit(const PopupDismissed());
      await Future<void>.delayed(Duration.zero);

      expect(a.length, 1);
      expect(b.length, 1);

      await subA.cancel();
      await subB.cancel();
    });

    test('emit after dispose throws', () async {
      await window.dispose();
      expect(() => window.emit(const PopupDismissed()), throwsStateError);
    });
  });

  group('failure simulation', () {
    setUp(() async {
      await window.spawn(initialPreview: preview());
    });

    test('failNextCall throws on next call then auto-resets', () async {
      window.failNextCall = StateError('boom');

      await expectLater(
        window.pushQueue(preview()),
        throwsA(isA<StateError>()),
      );

      // Second call succeeds.
      await window.pushQueue(preview(url: 'b'));
      expect(window.queuePushes.length, 1, reason: 'first push threw');
    });
  });

  group('disposal', () {
    test('dispose clears flags + closes events stream', () async {
      await window.spawn(initialPreview: preview());
      final received = <FloatingWindowEvent>[];
      final sub = window.events.listen(received.add, onDone: () {});

      await window.dispose();

      expect(window.isSpawned, isFalse);
      expect(window.isVisible, isFalse);
      expect(window.disposeCallCount, 1);

      // After dispose, calls throw.
      expect(() => window.show(), throwsStateError);

      await sub.cancel();
    });

    test('dispose is idempotent', () async {
      await window.spawn(initialPreview: preview());
      await window.dispose();
      await window.dispose();
      expect(window.disposeCallCount, 1, reason: 'second dispose is no-op');
    });

    test('dispose without spawn safe', () async {
      await window.dispose();
      expect(window.disposeCallCount, 1);
    });
  });
}
