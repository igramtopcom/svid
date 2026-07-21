import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:svid/core/services/pii_scrubber.dart';

void main() {
  group('piiScrubber', () {
    test('scrubs URLs from event message', () {
      final event = SentryEvent(
        message: SentryMessage(
          'Failed to download from https://www.youtube.com/watch?v=abc123',
        ),
      );

      final scrubbed = piiScrubber(event);
      expect(scrubbed.message!.formatted, contains('[URL_REDACTED]'));
      expect(scrubbed.message!.formatted, isNot(contains('youtube.com')));
    });

    test('scrubs macOS user paths', () {
      final event = SentryEvent(
        message: SentryMessage(
          'File not found: /Users/johndoe/Downloads/video.txt',
        ),
      );

      final scrubbed = piiScrubber(event);
      expect(scrubbed.message!.formatted, contains('[PATH_REDACTED]'));
      expect(scrubbed.message!.formatted, isNot(contains('johndoe')));
    });

    test('scrubs Linux user paths', () {
      final event = SentryEvent(
        message: SentryMessage(
          'Error at /home/alice/videos/file.txt',
        ),
      );

      final scrubbed = piiScrubber(event);
      expect(scrubbed.message!.formatted, contains('[PATH_REDACTED]'));
      expect(scrubbed.message!.formatted, isNot(contains('alice')));
    });

    test('scrubs Windows user paths', () {
      final event = SentryEvent(
        message: SentryMessage(
          r'Error at C:\Users\bob\Downloads\file.txt',
        ),
      );

      final scrubbed = piiScrubber(event);
      expect(scrubbed.message!.formatted, contains('[PATH_REDACTED]'));
      expect(scrubbed.message!.formatted, isNot(contains('bob')));
    });

    test('scrubs media filenames', () {
      final event = SentryEvent(
        message: SentryMessage(
          'Failed to process my-vacation-video.mp4 and song.mp3',
        ),
      );

      final scrubbed = piiScrubber(event);
      expect(scrubbed.message!.formatted, isNot(contains('.mp4')));
      expect(scrubbed.message!.formatted, isNot(contains('.mp3')));
      expect(scrubbed.message!.formatted, contains('[MEDIA_REDACTED]'));
    });

    test('scrubs exception values', () {
      final event = SentryEvent(
        exceptions: [
          SentryException(
            type: 'NetworkError',
            value: 'Connection to https://api.example.com/download failed',
          ),
        ],
      );

      final scrubbed = piiScrubber(event);
      expect(scrubbed.exceptions!.first.value, contains('[URL_REDACTED]'));
      expect(scrubbed.exceptions!.first.value, isNot(contains('api.example.com')));
      expect(scrubbed.exceptions!.first.type, equals('NetworkError'));
    });

    test('scrubs breadcrumb messages', () {
      final event = SentryEvent(
        breadcrumbs: [
          Breadcrumb(
            message: 'Downloading https://cdn.example.com/video.mp4',
            timestamp: DateTime.now(),
          ),
        ],
      );

      final scrubbed = piiScrubber(event);
      expect(scrubbed.breadcrumbs!.first.message, contains('[URL_REDACTED]'));
      expect(scrubbed.breadcrumbs!.first.message, isNot(contains('cdn.example.com')));
    });

    test('scrubs breadcrumb data values', () {
      final event = SentryEvent(
        breadcrumbs: [
          Breadcrumb(
            message: 'Download started',
            data: {'path': '/Users/test/Downloads/song.mp3'},
            timestamp: DateTime.now(),
          ),
        ],
      );

      final scrubbed = piiScrubber(event);
      final data = scrubbed.breadcrumbs!.first.data!;
      // _userPathPattern is greedy through subdirs — consumes the entire
      // `/Users/test/Downloads/song.mp3` into a single [PATH_REDACTED]
      // before _mediaFilePattern can match the trailing filename.
      // Privacy intent: full path hidden behind one sentinel.
      expect(data['path'], contains('[PATH_REDACTED]'));
      expect(data['path'], isNot(contains('song.mp3')));
    });

    test('preserves events with no PII', () {
      final event = SentryEvent(
        message: SentryMessage('App started successfully'),
      );

      final scrubbed = piiScrubber(event);
      expect(scrubbed.message!.formatted, equals('App started successfully'));
    });
  });
}
