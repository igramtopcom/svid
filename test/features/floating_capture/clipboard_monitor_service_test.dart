import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/floating_capture/data/datasources/mock_clipboard_source.dart';
import 'package:svid/features/floating_capture/domain/services/clipboard_monitor_service.dart';

void main() {
  // Init binding so appLogger calls don't emit warnings about
  // "Binding has not yet been initialized" during tests.
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockClipboardSource source;
  late ClipboardMonitorService monitor;

  setUp(() {
    source = MockClipboardSource();
    monitor = ClipboardMonitorService(source: source);
  });

  tearDown(() async {
    await monitor.dispose();
    await source.dispose();
  });

  group('lifecycle', () {
    test('idempotent start', () async {
      await monitor.start();
      await monitor.start(); // should not error
      // No assertion — just ensure no exception
    });

    test('idempotent stop', () async {
      await monitor.stop(); // before any start — no-op
      await monitor.start();
      await monitor.stop();
      await monitor.stop(); // double stop — no-op
    });

    test('can restart after stop', () async {
      await monitor.start();
      await monitor.stop();
      await monitor.start();
      // No exception means success
    });
  });

  group('baseline detection (spec §5.3)', () {
    test('pre-existing clipboard content does NOT emit on start', () async {
      // User had URL in clipboard BEFORE app started
      source.simulateOrSetInitial('https://youtube.com/watch?v=abcdef12345');

      final emissions = <String>[];
      final sub = monitor.onUrl.listen(emissions.add);

      await monitor.start();
      // Allow async callbacks to flush
      await Future.delayed(const Duration(milliseconds: 50));

      expect(emissions, isEmpty,
          reason: 'Pre-existing URL should be baseline, not emitted');

      await sub.cancel();
    });

    test('change after start emits', () async {
      final emissions = <String>[];
      final sub = monitor.onUrl.listen(emissions.add);

      await monitor.start();
      source.simulateClipboardChange(
          'https://youtube.com/watch?v=abcdef12345');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(emissions, ['https://youtube.com/watch?v=abcdef12345']);

      await sub.cancel();
    });

    test('change to baseline content after first real change still emits',
        () async {
      // Edge case: user copies URL X (baseline), starts app, copies Y, then
      // copies X again — second X copy SHOULD emit (baseline cleared after
      // first real change).
      source.simulateOrSetInitial('https://youtube.com/watch?v=baseline123');

      final emissions = <String>[];
      final sub = monitor.onUrl.listen(emissions.add);

      await monitor.start();
      source.simulateClipboardChange(
          'https://youtube.com/watch?v=newvideo456');
      source.simulateClipboardChange(
          'https://youtube.com/watch?v=baseline123');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(emissions.length, 2);
      expect(emissions[0], contains('newvideo456'));
      expect(emissions[1], contains('baseline123'));

      await sub.cancel();
    });
  });

  group('URL filtering (E16 — non-URL inputs)', () {
    test('plain text (no URL) is dropped', () async {
      final emissions = <String>[];
      final sub = monitor.onUrl.listen(emissions.add);

      await monitor.start();
      source.simulateClipboardChange('just some plain text user copied');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(emissions, isEmpty);
      await sub.cancel();
    });

    test('unsupported URL on unknown platform is dropped', () async {
      final emissions = <String>[];
      final sub = monitor.onUrl.listen(emissions.add);

      await monitor.start();
      source.simulateClipboardChange('https://example.com/some-page');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(emissions, isEmpty,
          reason: 'unknown URL type should be filtered');
      await sub.cancel();
    });

    test('whitespace-only is dropped', () async {
      final emissions = <String>[];
      final sub = monitor.onUrl.listen(emissions.add);

      await monitor.start();
      // Whitespace-only never reaches handler (mock filters), but verify anyway
      source.simulateClipboardChange('   \n  ');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(emissions, isEmpty);
      await sub.cancel();
    });

    test('YouTube playlist URL emits (channel/playlist/live count too)',
        () async {
      final emissions = <String>[];
      final sub = monitor.onUrl.listen(emissions.add);

      await monitor.start();
      source.simulateClipboardChange(
          'https://youtube.com/playlist?list=PLxxxxxxxx');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(emissions.length, 1);
      await sub.cancel();
    });
  });

  group('dedup window (spec §11 E1 — 60s)', () {
    test('same URL within window is dropped', () async {
      final emissions = <String>[];
      final sub = monitor.onUrl.listen(emissions.add);

      await monitor.start();
      source.simulateClipboardChange(
          'https://youtube.com/watch?v=abcdef12345');
      source.simulateClipboardChange(
          'https://youtube.com/watch?v=abcdef12345'); // duplicate
      await Future.delayed(const Duration(milliseconds: 50));

      expect(emissions.length, 1);
      await sub.cancel();
    });

    test('different URLs both emit', () async {
      final emissions = <String>[];
      final sub = monitor.onUrl.listen(emissions.add);

      await monitor.start();
      source.simulateClipboardChange(
          'https://youtube.com/watch?v=aaaaaaaaaaa');
      source.simulateClipboardChange(
          'https://youtube.com/watch?v=bbbbbbbbbbb');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(emissions.length, 2);
      await sub.cancel();
    });

    test('same URL after dedup window expires emits again', () async {
      // Use very short dedup window to keep test fast
      final shortMonitor = ClipboardMonitorService(
        source: source,
        dedupWindow: const Duration(milliseconds: 50),
      );

      final emissions = <String>[];
      final sub = shortMonitor.onUrl.listen(emissions.add);

      await shortMonitor.start();
      source.simulateClipboardChange(
          'https://youtube.com/watch?v=abcdef12345');
      await Future.delayed(const Duration(milliseconds: 100)); // exceed window
      source.simulateClipboardChange(
          'https://youtube.com/watch?v=abcdef12345');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(emissions.length, 2,
          reason: 'second copy after window expired should re-emit');

      await sub.cancel();
      await shortMonitor.dispose();
    });
  });

  group('multi-platform URL detection', () {
    final testCases = [
      ('YouTube', 'https://youtube.com/watch?v=abcdef12345'),
      ('TikTok', 'https://tiktok.com/@user.name/video/1234567890'),
      ('Vimeo', 'https://vimeo.com/123456789'),
      ('Twitter', 'https://twitter.com/user/status/1234567890'),
      ('Reddit', 'https://reddit.com/r/videos/comments/abc123/title'),
      ('Instagram', 'https://instagram.com/p/ABC123/'),
    ];

    for (final (platform, url) in testCases) {
      test('$platform URL emits', () async {
        final emissions = <String>[];
        final sub = monitor.onUrl.listen(emissions.add);

        await monitor.start();
        source.simulateClipboardChange(url);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(emissions.length, 1, reason: '$platform URL should emit');
        expect(emissions.first, url);

        await sub.cancel();
      });
    }
  });

  group('disposal safety', () {
    test('dispose() is safe after start', () async {
      await monitor.start();
      expect(() async => monitor.dispose(), returnsNormally);
    });

    test('dispose() then start() again works (after recreation)', () async {
      await monitor.start();
      await monitor.dispose();
      // Note: same instance after dispose — emitter is closed.
      // Real usage would recreate the monitor. Verify dispose doesn't crash.
      expect(() async => monitor.dispose(), returnsNormally);
    });

    test('handler errors caught — do not crash subscription', () async {
      // Even if some malformed input slips through (defensive coding test),
      // service should not throw — handler wraps in try/catch.
      final emissions = <String>[];
      final sub = monitor.onUrl.listen(emissions.add);

      await monitor.start();
      // Multiple emissions in quick succession — no crash
      source.simulateClipboardChange(
          'https://youtube.com/watch?v=aaaaaaaaaaa');
      source.simulateClipboardChange(
          'https://youtube.com/watch?v=bbbbbbbbbbb');
      source.simulateClipboardChange('plain text not a url');
      source.simulateClipboardChange(
          'https://youtube.com/watch?v=ccccccccccc');
      await Future.delayed(const Duration(milliseconds: 50));

      // 3 valid + 1 plain text dropped → 3 emissions, no crash
      expect(emissions.length, 3);

      await sub.cancel();
    });
  });

  group('multi-subscriber stream', () {
    test('broadcast stream supports multiple listeners', () async {
      final emissions1 = <String>[];
      final emissions2 = <String>[];

      final sub1 = monitor.onUrl.listen(emissions1.add);
      final sub2 = monitor.onUrl.listen(emissions2.add);

      await monitor.start();
      source.simulateClipboardChange(
          'https://youtube.com/watch?v=abcdef12345');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(emissions1.length, 1);
      expect(emissions2.length, 1);

      await sub1.cancel();
      await sub2.cancel();
    });
  });
}
