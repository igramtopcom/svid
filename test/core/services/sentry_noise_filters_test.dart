// ignore_for_file: deprecated_member_use

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:ssvid/core/services/sentry_noise_filters.dart';

/// Locks the noise-filter surface against accidental widening. Each test
/// pins one of the two filters AND verifies a near-miss case is preserved
/// so the filter never grows to swallow real user-actionable errors.
void main() {
  SentryEvent eventWith({
    String? message,
    String? excType,
    String? excValue,
    Map<String, dynamic>? extra,
  }) {
    return SentryEvent(
      message: message != null ? SentryMessage(message) : null,
      exceptions: excValue != null
          ? [SentryException(type: excType ?? 'Exception', value: excValue)]
          : null,
      extra: extra,
    );
  }

  group('isYouTubeThumbnail404 — drops', () {
    test('hqdefault.jpg with 404 on img.youtube.com', () {
      final event = eventWith(
        excType: 'NetworkImageLoadException',
        excValue:
            'HTTP request failed, statusCode: 404, https://img.youtube.com/vi/abc123/hqdefault.jpg',
      );
      expect(SentryNoiseFilters.shouldDrop(event), isTrue);
    });

    test('mqdefault.jpg with 404', () {
      final event = eventWith(
        excValue:
            'NetworkImageLoadException: 404 on https://img.youtube.com/vi/xyz/mqdefault.jpg',
      );
      expect(SentryNoiseFilters.shouldDrop(event), isTrue);
    });

    test('sddefault.jpg with 404', () {
      final event = eventWith(
        excValue:
            '404 https://img.youtube.com/vi/zzz/sddefault.jpg failed',
      );
      expect(SentryNoiseFilters.shouldDrop(event), isTrue);
    });

    test('maxresdefault.jpg with 404 on i.ytimg.com', () {
      final event = eventWith(
        excValue:
            'HTTP/1.1 404 Not Found https://i.ytimg.com/vi/qqq/maxresdefault.jpg',
      );
      expect(SentryNoiseFilters.shouldDrop(event), isTrue);
    });

    test('plain /vi/<id>/default.jpg with 404 (no prefix)', () {
      final event = eventWith(
        excValue:
            'statusCode: 404 https://img.youtube.com/vi/abc/default.jpg',
      );
      expect(SentryNoiseFilters.shouldDrop(event), isTrue);
    });

    test('matches when URL is in extra payload', () {
      final event = eventWith(
        excType: 'HttpException',
        excValue: 'statusCode: 404',
        extra: {
          'imageUrl': 'https://img.youtube.com/vi/abc/hqdefault.jpg',
        },
      );
      expect(SentryNoiseFilters.shouldDrop(event), isTrue);
    });
  });

  group('isYouTubeThumbnail404 — KEEPS (negative cases)', () {
    test('preserves YouTube 403 (auth-class, user-actionable)', () {
      final event = eventWith(
        excValue:
            'statusCode: 403 https://img.youtube.com/vi/abc/hqdefault.jpg',
      );
      expect(SentryNoiseFilters.shouldDrop(event), isFalse);
    });

    test('preserves YouTube 500 (server-class, signal worth tracking)', () {
      final event = eventWith(
        excValue:
            'statusCode: 500 https://img.youtube.com/vi/abc/hqdefault.jpg',
      );
      expect(SentryNoiseFilters.shouldDrop(event), isFalse);
    });

    test('preserves 404 from a non-YouTube host with /vi/ path', () {
      final event = eventWith(
        excValue:
            'statusCode: 404 https://cdn.example.com/vi/anything/hqdefault.jpg',
      );
      expect(SentryNoiseFilters.shouldDrop(event), isFalse);
    });

    test('preserves 404 from YouTube on a non-thumbnail path (e.g. /watch)',
        () {
      final event = eventWith(
        excValue:
            'statusCode: 404 https://www.youtube.com/watch?v=abc',
      );
      expect(SentryNoiseFilters.shouldDrop(event), isFalse);
    });

    test('preserves an arbitrary thumbnail 404 (not in our pattern set)', () {
      final event = eventWith(
        excValue:
            'statusCode: 404 https://img.youtube.com/vi/abc/preview.jpg',
      );
      expect(SentryNoiseFilters.shouldDrop(event), isFalse);
    });

    test('preserves empty/no-context events', () {
      expect(SentryNoiseFilters.shouldDrop(eventWith()), isFalse);
    });
  });

  group('isVidComboHealthProbeTimeout — drops', () {
    test('TimeoutException on api.vidcombo.net/version.php', () {
      final event = eventWith(
        excType: 'TimeoutException',
        excValue:
            'TimeoutException after 10s on https://api.vidcombo.net/version.php',
      );
      expect(SentryNoiseFilters.shouldDrop(event), isTrue);
    });

    test('TimeoutException on checkkey.php host', () {
      final event = eventWith(
        excType: 'TimeoutException',
        excValue:
            'TimeoutException https://api.vidcombo.net/checkkey.php during license probe',
      );
      expect(SentryNoiseFilters.shouldDrop(event), isTrue);
    });
  });

  group('isVidComboHealthProbeTimeout — KEEPS (negative cases)', () {
    test('preserves SocketException on the same probe (different class)', () {
      final event = eventWith(
        excType: 'SocketException',
        excValue:
            'SocketException connect failed on https://api.vidcombo.net/version.php',
      );
      expect(SentryNoiseFilters.shouldDrop(event), isFalse);
    });

    test('preserves TimeoutException on a non-probe Vidcombo endpoint', () {
      final event = eventWith(
        excType: 'TimeoutException',
        excValue:
            'TimeoutException https://api.vidcombo.net/login.php during sign-in',
      );
      expect(SentryNoiseFilters.shouldDrop(event), isFalse);
    });

    test('preserves TimeoutException on Go backend probe (different host)',
        () {
      final event = eventWith(
        excType: 'TimeoutException',
        excValue:
            'TimeoutException https://api.ssvid.app/v1/health during heartbeat',
      );
      expect(SentryNoiseFilters.shouldDrop(event), isFalse);
    });
  });
}
