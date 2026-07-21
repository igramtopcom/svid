import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/utils/platform_detector.dart';
import 'package:svid/features/browser/domain/services/video_url_detector.dart';

void main() {
  group('VideoUrlDetector', () {
    // ==================== YouTube ====================

    group('YouTube', () {
      test('detects watch page', () {
        final result = VideoUrlDetector.detect(
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        );
        expect(result.isVideoPage, isTrue);
        expect(result.platform, VideoPlatform.youtube);
        expect(result.videoId, 'dQw4w9WgXcQ');
      });

      test('detects shorts', () {
        final result = VideoUrlDetector.detect(
          'https://www.youtube.com/shorts/abc123def45',
        );
        expect(result.isVideoPage, isTrue);
        expect(result.platform, VideoPlatform.youtube);
      });

      test('detects youtu.be short link', () {
        final result = VideoUrlDetector.detect(
          'https://youtu.be/dQw4w9WgXcQ',
        );
        expect(result.isVideoPage, isTrue);
        expect(result.platform, VideoPlatform.youtube);
        expect(result.videoId, 'dQw4w9WgXcQ');
      });

      test('rejects YouTube homepage', () {
        final result = VideoUrlDetector.detect(
          'https://www.youtube.com/',
        );
        expect(result.isVideoPage, isFalse);
      });

      test('rejects YouTube feed', () {
        final result = VideoUrlDetector.detect(
          'https://www.youtube.com/feed/subscriptions',
        );
        expect(result.isVideoPage, isFalse);
      });
    });

    // ==================== TikTok ====================

    group('TikTok', () {
      test('detects video page', () {
        final result = VideoUrlDetector.detect(
          'https://www.tiktok.com/@user/video/7123456789012345678',
        );
        expect(result.isVideoPage, isTrue);
        expect(result.platform, VideoPlatform.tiktok);
      });

      test('detects short link', () {
        final result = VideoUrlDetector.detect(
          'https://vt.tiktok.com/ZSrABC123/',
        );
        expect(result.isVideoPage, isTrue);
        expect(result.platform, VideoPlatform.tiktok);
      });

      test('rejects TikTok homepage', () {
        final result = VideoUrlDetector.detect(
          'https://www.tiktok.com/',
        );
        expect(result.isVideoPage, isFalse);
      });
    });

    // ==================== Instagram ====================

    group('Instagram', () {
      test('detects post', () {
        final result = VideoUrlDetector.detect(
          'https://www.instagram.com/p/CxYz123abcd/',
        );
        expect(result.isVideoPage, isTrue);
        expect(result.platform, VideoPlatform.instagram);
      });

      test('detects reel', () {
        final result = VideoUrlDetector.detect(
          'https://www.instagram.com/reel/CxYz123abcd/',
        );
        expect(result.isVideoPage, isTrue);
        expect(result.platform, VideoPlatform.instagram);
      });

      test('detects tv', () {
        final result = VideoUrlDetector.detect(
          'https://www.instagram.com/tv/CxYz123abcd/',
        );
        expect(result.isVideoPage, isTrue);
        expect(result.platform, VideoPlatform.instagram);
      });

      test('rejects Instagram homepage', () {
        final result = VideoUrlDetector.detect(
          'https://www.instagram.com/',
        );
        expect(result.isVideoPage, isFalse);
      });
    });

    // ==================== Facebook ====================

    group('Facebook', () {
      test('detects video page', () {
        final result = VideoUrlDetector.detect(
          'https://www.facebook.com/user/videos/123456789/',
        );
        expect(result.isVideoPage, isTrue);
        expect(result.platform, VideoPlatform.facebook);
      });

      test('detects watch page', () {
        final result = VideoUrlDetector.detect(
          'https://www.facebook.com/watch/?v=123456789',
        );
        expect(result.isVideoPage, isTrue);
        expect(result.platform, VideoPlatform.facebook);
      });

      test('detects reel', () {
        final result = VideoUrlDetector.detect(
          'https://www.facebook.com/reel/123456789',
        );
        expect(result.isVideoPage, isTrue);
        expect(result.platform, VideoPlatform.facebook);
      });

      test('detects fb.watch short link', () {
        final result = VideoUrlDetector.detect(
          'https://fb.watch/abcdef123/',
        );
        expect(result.isVideoPage, isTrue);
        expect(result.platform, VideoPlatform.facebook);
      });

      test('detects share/v/ video link', () {
        final result = VideoUrlDetector.detect(
          'https://www.facebook.com/share/v/1GcFBkxi4W/',
        );
        expect(result.isVideoPage, isTrue);
        expect(result.platform, VideoPlatform.facebook);
      });

      test('detects share/r/ reel link', () {
        final result = VideoUrlDetector.detect(
          'https://www.facebook.com/share/r/1EAcxuuPCB/',
        );
        expect(result.isVideoPage, isTrue);
        expect(result.platform, VideoPlatform.facebook);
      });
    });

    // ==================== Twitter/X ====================

    group('Twitter/X', () {
      test('detects tweet status', () {
        final result = VideoUrlDetector.detect(
          'https://twitter.com/user/status/1234567890123456789',
        );
        expect(result.isVideoPage, isTrue);
        expect(result.platform, VideoPlatform.twitter);
      });

      test('detects x.com status', () {
        final result = VideoUrlDetector.detect(
          'https://x.com/user/status/1234567890123456789',
        );
        expect(result.isVideoPage, isTrue);
        expect(result.platform, VideoPlatform.twitter);
      });

      test('rejects Twitter homepage', () {
        final result = VideoUrlDetector.detect(
          'https://twitter.com/home',
        );
        expect(result.isVideoPage, isFalse);
      });
    });

    // ==================== Vimeo ====================

    group('Vimeo', () {
      test('detects video page', () {
        final result = VideoUrlDetector.detect(
          'https://vimeo.com/123456789',
        );
        expect(result.isVideoPage, isTrue);
        expect(result.platform, VideoPlatform.vimeo);
      });

      test('rejects Vimeo homepage', () {
        final result = VideoUrlDetector.detect(
          'https://vimeo.com/',
        );
        expect(result.isVideoPage, isFalse);
      });
    });

    // ==================== Dailymotion ====================

    group('Dailymotion', () {
      test('detects video page', () {
        final result = VideoUrlDetector.detect(
          'https://www.dailymotion.com/video/x8abc12',
        );
        expect(result.isVideoPage, isTrue);
        expect(result.platform, VideoPlatform.dailymotion);
      });
    });

    // ==================== Reddit ====================

    group('Reddit', () {
      test('detects post with comments', () {
        final result = VideoUrlDetector.detect(
          'https://www.reddit.com/r/videos/comments/abc123/my_video/',
        );
        expect(result.isVideoPage, isTrue);
        expect(result.platform, VideoPlatform.reddit);
      });
    });

    // ==================== SoundCloud ====================

    group('SoundCloud', () {
      test('detects track page', () {
        final result = VideoUrlDetector.detect(
          'https://soundcloud.com/artist-name/track-name',
        );
        expect(result.isVideoPage, isTrue);
        expect(result.platform, VideoPlatform.soundcloud);
      });

      test('rejects discover page', () {
        final result = VideoUrlDetector.detect(
          'https://soundcloud.com/discover',
        );
        expect(result.isVideoPage, isFalse);
      });

      test('rejects search page', () {
        final result = VideoUrlDetector.detect(
          'https://soundcloud.com/search/sounds?q=test',
        );
        expect(result.isVideoPage, isFalse);
      });
    });

    // ==================== Bilibili ====================

    group('Bilibili', () {
      test('detects BV video', () {
        final result = VideoUrlDetector.detect(
          'https://www.bilibili.com/video/BV1xx411c7mD',
        );
        expect(result.isVideoPage, isTrue);
        expect(result.platform, VideoPlatform.bilibili);
      });

      test('detects av video', () {
        final result = VideoUrlDetector.detect(
          'https://www.bilibili.com/video/av12345678',
        );
        expect(result.isVideoPage, isTrue);
        expect(result.platform, VideoPlatform.bilibili);
      });
    });

    // ==================== Pinterest ====================

    group('Pinterest', () {
      test('detects pin page', () {
        final result = VideoUrlDetector.detect(
          'https://www.pinterest.com/pin/123456789/',
        );
        expect(result.isVideoPage, isTrue);
        expect(result.platform, VideoPlatform.pinterest);
      });
    });

    // ==================== Threads ====================

    group('Threads', () {
      test('detects post page', () {
        final result = VideoUrlDetector.detect(
          'https://www.threads.net/@user/post/CxYz123abcd',
        );
        expect(result.isVideoPage, isTrue);
        expect(result.platform, VideoPlatform.threads);
      });

      test('detects short link', () {
        final result = VideoUrlDetector.detect(
          'https://www.threads.net/t/CxYz123abcd',
        );
        expect(result.isVideoPage, isTrue);
        expect(result.platform, VideoPlatform.threads);
      });

      test('rejects Threads homepage', () {
        final result = VideoUrlDetector.detect(
          'https://www.threads.net/',
        );
        expect(result.isVideoPage, isFalse);
      });
    });

    // ==================== Edge cases ====================

    group('Edge cases', () {
      test('returns none for empty URL', () {
        final result = VideoUrlDetector.detect('');
        expect(result.isVideoPage, isFalse);
        expect(result.platform, VideoPlatform.unknown);
      });

      test('returns none for invalid URL', () {
        final result = VideoUrlDetector.detect('not a url');
        expect(result.isVideoPage, isFalse);
      });

      test('returns none for unknown platform', () {
        final result = VideoUrlDetector.detect(
          'https://www.example.com/some/video',
        );
        expect(result.isVideoPage, isFalse);
        expect(result.platform, VideoPlatform.unknown);
      });

      test('detection preserves original URL', () {
        const url = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
        final result = VideoUrlDetector.detect(url);
        expect(result.url, url);
      });
    });
  });
}
