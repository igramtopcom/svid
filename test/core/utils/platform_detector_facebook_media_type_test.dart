import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/core/utils/platform_detector.dart';

/// RC10.1 of Ultra Plan v3 — Facebook URL pattern → media-type
/// classification. Confirmed-video URLs MUST skip gallery-dl
/// pre-warm; image / album URLs MUST stay in parallel path;
/// ambiguous patterns (e.g., `/posts/<id>`) default to unknown so
/// the parallel path remains safe.
void main() {
  group('PlatformDetector.detectFacebookMediaType — RC10.1', () {
    group('Video patterns (skip gallery-dl)', () {
      test('share/r/<id> reel short-link → video', () {
        // Wilson-class production URL pattern from session-codex.md
        // 2026-05-23 incident.
        expect(
          PlatformDetector.detectFacebookMediaType(
            'https://www.facebook.com/share/r/199MQqRXgh/',
          ),
          FacebookMediaType.video,
        );
      });

      test('share/v/<id> video-share → video (Codex-round-2 catch 8)', () {
        // Facebook has BOTH /share/r/ (reel-share) AND /share/v/
        // (video-share) URL patterns. Pre-fix only /share/r/ was
        // matched — /share/v/ leaked to gallery-dl path.
        expect(
          PlatformDetector.detectFacebookMediaType(
            'https://www.facebook.com/share/v/abc123/',
          ),
          FacebookMediaType.video,
        );
      });

      test('/reel/<id> → video', () {
        expect(
          PlatformDetector.detectFacebookMediaType(
            'https://www.facebook.com/reel/1234567890',
          ),
          FacebookMediaType.video,
        );
      });

      test('/watch?v=<id> → video', () {
        expect(
          PlatformDetector.detectFacebookMediaType(
            'https://www.facebook.com/watch?v=1234567890',
          ),
          FacebookMediaType.video,
        );
      });

      test('/<page>/videos/<id> → video', () {
        expect(
          PlatformDetector.detectFacebookMediaType(
            'https://www.facebook.com/somepage/videos/1234567890',
          ),
          FacebookMediaType.video,
        );
      });

      test('fb.watch/<id> short link → video', () {
        expect(
          PlatformDetector.detectFacebookMediaType(
            'https://fb.watch/abc123',
          ),
          FacebookMediaType.video,
        );
      });

      test('case-insensitive: WATCH path → video', () {
        expect(
          PlatformDetector.detectFacebookMediaType(
            'https://www.FACEBOOK.com/WATCH?v=1234',
          ),
          FacebookMediaType.video,
        );
      });
    });

    group('Image patterns (keep parallel gallery-dl)', () {
      test('/photo/?fbid=<id> → image', () {
        expect(
          PlatformDetector.detectFacebookMediaType(
            'https://www.facebook.com/photo/?fbid=1234567890',
          ),
          FacebookMediaType.image,
        );
      });

      test('/photo.php?fbid=<id> → image', () {
        expect(
          PlatformDetector.detectFacebookMediaType(
            'https://www.facebook.com/photo.php?fbid=1234567890',
          ),
          FacebookMediaType.image,
        );
      });

      test('/media/set/?set=<id> album → image', () {
        expect(
          PlatformDetector.detectFacebookMediaType(
            'https://www.facebook.com/media/set/?set=a.1234567890',
          ),
          FacebookMediaType.image,
        );
      });

      test('/<user>/albums/<id> → image', () {
        expect(
          PlatformDetector.detectFacebookMediaType(
            'https://www.facebook.com/someuser/albums/1234567890',
          ),
          FacebookMediaType.image,
        );
      });
    });

    group('Ambiguous patterns (default to unknown — parallel path)', () {
      test('/posts/<id> — could be text/image/video → unknown', () {
        // Per docstring: /posts/<id> can be either text-only,
        // image, or video. Treat as unknown so the parallel path
        // (yt-dlp + gallery-dl race) handles it correctly.
        expect(
          PlatformDetector.detectFacebookMediaType(
            'https://www.facebook.com/someuser/posts/1234567890',
          ),
          FacebookMediaType.unknown,
        );
      });

      test('/profile.php?id=<id> profile page → unknown', () {
        expect(
          PlatformDetector.detectFacebookMediaType(
            'https://www.facebook.com/profile.php?id=1234567890',
          ),
          FacebookMediaType.unknown,
        );
      });

      test('bare facebook.com → unknown', () {
        expect(
          PlatformDetector.detectFacebookMediaType(
            'https://www.facebook.com/',
          ),
          FacebookMediaType.unknown,
        );
      });
    });

    group('Edge cases', () {
      test('empty string → unknown', () {
        expect(
          PlatformDetector.detectFacebookMediaType(''),
          FacebookMediaType.unknown,
        );
      });

      test('non-Facebook URL → unknown (defensive)', () {
        // The classifier is called from the extraction dispatch
        // AFTER PlatformDetector.detectPlatform returns facebook,
        // so non-Facebook URLs reaching this method represents a
        // upstream bug. Default to unknown (safe — parallel path
        // still runs).
        expect(
          PlatformDetector.detectFacebookMediaType(
            'https://example.com/random/url',
          ),
          FacebookMediaType.unknown,
        );
      });
    });
  });
}
