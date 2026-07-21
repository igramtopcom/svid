import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/presentation/providers/downloads_notifier.dart';

/// MEAS-1: locks the `download_complete` telemetry contract — the 7-key shape,
/// the null semantics (start/post-process not observed), the attempt-index
/// passthrough, and content-blindness (no URL/title/path can leak through it).
void main() {
  group('MEAS-1 buildDownloadCompleteEvent', () {
    final completedAt = DateTime(2026, 6, 16, 10, 0, 30);

    test('emits exactly the 7 content-blind keys — no PII surface', () {
      final event = DownloadsNotifier.buildDownloadCompleteEvent(
        method: 'ytdlp',
        sizeBytes: 1000,
        platform: 'youtube',
        startedAt: completedAt.subtract(const Duration(seconds: 30)),
        postProcessStartedAt: null,
        completedAt: completedAt,
        attemptIndex: 0,
      );
      expect(
        event.keys.toSet(),
        {
          'method',
          'size_bytes',
          'platform',
          'duration_ms',
          'post_process_ms',
          'attempt_index',
          'encoder_used',
        },
      );
      // A downloader's URL/title/filename ARE viewing history — none may ride
      // this event (UXH-1 owns scrubbing elsewhere; this event is blind by
      // construction).
      for (final k in event.keys) {
        expect(
          k,
          isNot(anyOf('url', 'title', 'filename', 'path', 'save_path')),
        );
      }
    });

    test('duration_ms = completed − started; null when start not observed', () {
      final withStart = DownloadsNotifier.buildDownloadCompleteEvent(
        method: 'ytdlp',
        sizeBytes: 1000,
        platform: 'youtube',
        startedAt: completedAt.subtract(const Duration(seconds: 12)),
        postProcessStartedAt: null,
        completedAt: completedAt,
        attemptIndex: 0,
      );
      expect(withStart['duration_ms'], 12000);

      // A download in flight across an app restart loses its start stamp →
      // duration_ms is null, NOT a fabricated 0.
      final noStart = DownloadsNotifier.buildDownloadCompleteEvent(
        method: 'ytdlp',
        sizeBytes: 1000,
        platform: 'youtube',
        startedAt: null,
        postProcessStartedAt: null,
        completedAt: completedAt,
        attemptIndex: 0,
      );
      expect(noStart['duration_ms'], isNull);
    });

    test(
      'post_process_ms = completed − postProcessStart; null for native no-op '
      'merge (phase never entered)',
      () {
        final recode = DownloadsNotifier.buildDownloadCompleteEvent(
          method: 'ytdlp',
          sizeBytes: 1000,
          platform: 'youtube',
          startedAt: completedAt.subtract(const Duration(seconds: 30)),
          postProcessStartedAt:
              completedAt.subtract(const Duration(seconds: 8)),
          completedAt: completedAt,
          attemptIndex: 0,
        );
        // Wave A native no-op merge would NOT set this; a genuine recode does.
        expect(recode['post_process_ms'], 8000);
        expect(recode['duration_ms'], 30000);

        final noop = DownloadsNotifier.buildDownloadCompleteEvent(
          method: 'ytdlp',
          sizeBytes: 1000,
          platform: 'youtube',
          startedAt: completedAt.subtract(const Duration(seconds: 30)),
          postProcessStartedAt: null,
          completedAt: completedAt,
          attemptIndex: 0,
        );
        expect(noop['post_process_ms'], isNull);
      },
    );

    test('attempt_index passes through retryCount so retries are separable', () {
      final retry = DownloadsNotifier.buildDownloadCompleteEvent(
        method: 'ytdlp',
        sizeBytes: 1000,
        platform: 'youtube',
        startedAt: null,
        postProcessStartedAt: null,
        completedAt: completedAt,
        attemptIndex: 3,
      );
      expect(retry['attempt_index'], 3);
    });

    test('encoder_used is null until DL-013 wires it; passes through when set', () {
      final defaulted = DownloadsNotifier.buildDownloadCompleteEvent(
        method: 'ytdlp',
        sizeBytes: 1000,
        platform: 'youtube',
        startedAt: null,
        postProcessStartedAt: null,
        completedAt: completedAt,
        attemptIndex: 0,
      );
      expect(defaulted['encoder_used'], isNull);

      final hw = DownloadsNotifier.buildDownloadCompleteEvent(
        method: 'ytdlp',
        sizeBytes: 1000,
        platform: 'youtube',
        startedAt: null,
        postProcessStartedAt: null,
        completedAt: completedAt,
        attemptIndex: 0,
        encoderUsed: 'hw',
      );
      expect(hw['encoder_used'], 'hw');
    });
  });
}
