import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/utils/platform_detector.dart';
import 'package:svid/features/downloads/domain/entities/video_preview.dart';
import 'package:svid/features/floating_capture/domain/services/url_pattern_service.dart';

void main() {
  const service = UrlPatternService();

  group('UrlPatternService.classify — non-URL inputs', () {
    test('empty string returns notUrl', () {
      final r = service.classify('');
      expect(r.urlType, UrlType.notUrl);
      expect(r.platform, VideoPlatform.unknown);
    });

    test('plain text returns notUrl', () {
      final r = service.classify('MrBeast latest video');
      expect(r.urlType, UrlType.notUrl);
    });

    test('whitespace-only returns notUrl', () {
      final r = service.classify('   \n  ');
      expect(r.urlType, UrlType.notUrl);
    });

    test('non-http scheme returns notUrl', () {
      final r = service.classify('ftp://example.com/file');
      expect(r.urlType, UrlType.notUrl);
    });

    test('malformed URL returns notUrl', () {
      final r = service.classify('https://');
      // Still HTTPS prefix — Uri.tryParse may succeed with empty host
      expect(r.urlType, isIn([UrlType.notUrl, UrlType.unknown]));
    });
  });

  group('UrlPatternService.classify — YouTube videos', () {
    test('standard /watch?v= URL', () {
      final r = service.classify('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(r.urlType, UrlType.video);
      expect(r.platform, VideoPlatform.youtube);
      expect(r.itemId, 'dQw4w9WgXcQ');
    });

    test('youtu.be short URL', () {
      final r = service.classify('https://youtu.be/dQw4w9WgXcQ');
      expect(r.urlType, UrlType.video);
      expect(r.itemId, 'dQw4w9WgXcQ');
    });

    test('shorts URL', () {
      final r = service.classify('https://youtube.com/shorts/abcdef12345');
      expect(r.urlType, UrlType.video);
      expect(r.itemId, 'abcdef12345');
    });

    test('embed URL', () {
      final r = service.classify('https://youtube.com/embed/abcdef12345');
      expect(r.urlType, UrlType.video);
      expect(r.itemId, 'abcdef12345');
    });

    test('URL with timestamp ?t=120s', () {
      final r =
          service.classify('https://youtube.com/watch?v=abcdef12345&t=120s');
      expect(r.urlType, UrlType.video);
      expect(r.startTimestamp, const Duration(seconds: 120));
    });

    test('URL with timestamp ?t=2m30s', () {
      final r =
          service.classify('https://youtube.com/watch?v=abcdef12345&t=2m30s');
      expect(r.startTimestamp, const Duration(minutes: 2, seconds: 30));
    });

    test('URL with timestamp ?t=1h2m3s', () {
      final r =
          service.classify('https://youtube.com/watch?v=abcdef12345&t=1h2m3s');
      expect(r.startTimestamp, const Duration(hours: 1, minutes: 2, seconds: 3));
    });

    test('URL with raw seconds ?t=60', () {
      final r =
          service.classify('https://youtube.com/watch?v=abcdef12345&t=60');
      expect(r.startTimestamp, const Duration(seconds: 60));
    });

    test('URL with playlist context', () {
      final r = service.classify(
        'https://youtube.com/watch?v=abcdef12345&list=PLxxxx',
      );
      expect(r.urlType, UrlType.video);
      expect(r.itemId, 'abcdef12345');
      expect(r.playlistId, 'PLxxxx');
    });

    test('URL with fragment timestamp #t=45', () {
      final r =
          service.classify('https://youtube.com/watch?v=abcdef12345#t=45');
      expect(r.startTimestamp, const Duration(seconds: 45));
    });
  });

  group('UrlPatternService.classify — YouTube non-video', () {
    test('live URL', () {
      final r = service.classify('https://youtube.com/live/abcdef12345');
      expect(r.urlType, UrlType.live);
      expect(r.itemId, 'abcdef12345');
    });

    test('playlist URL (no video)', () {
      final r =
          service.classify('https://youtube.com/playlist?list=PLxxxxxxxx');
      expect(r.urlType, UrlType.playlist);
      expect(r.itemId, 'PLxxxxxxxx');
      expect(r.playlistId, 'PLxxxxxxxx');
    });

    test('channel handle URL', () {
      final r = service.classify('https://youtube.com/@MrBeast');
      expect(r.urlType, UrlType.channel);
    });

    test('legacy /c/ channel URL', () {
      final r = service.classify('https://youtube.com/c/MrBeast');
      expect(r.urlType, UrlType.channel);
    });

    test('legacy /channel/ URL', () {
      final r = service.classify('https://youtube.com/channel/UCxxxxxx');
      expect(r.urlType, UrlType.channel);
    });

    test('search results URL', () {
      final r =
          service.classify('https://youtube.com/results?search_query=test');
      expect(r.urlType, UrlType.search);
    });
  });

  group('UrlPatternService.classify — TikTok', () {
    test('video URL', () {
      final r = service.classify(
        'https://www.tiktok.com/@user.name/video/1234567890',
      );
      expect(r.urlType, UrlType.video);
      expect(r.platform, VideoPlatform.tiktok);
      expect(r.itemId, '1234567890');
    });

    test('vm.tiktok.com short URL', () {
      final r = service.classify('https://vm.tiktok.com/SHORTCODE');
      expect(r.urlType, UrlType.video);
      expect(r.platform, VideoPlatform.tiktok);
    });

    test('user profile URL', () {
      final r = service.classify('https://www.tiktok.com/@user.name');
      expect(r.urlType, UrlType.channel);
    });
  });

  group('UrlPatternService.classify — Vimeo', () {
    test('video URL', () {
      final r = service.classify('https://vimeo.com/123456789');
      expect(r.urlType, UrlType.video);
      expect(r.platform, VideoPlatform.vimeo);
      expect(r.itemId, '123456789');
    });

    test('user URL', () {
      final r = service.classify('https://vimeo.com/user12345');
      expect(r.urlType, UrlType.channel);
    });

    test('curated channel URL', () {
      final r = service.classify('https://vimeo.com/channels/staffpicks');
      expect(r.urlType, UrlType.channel);
    });
  });

  group('UrlPatternService.classify — Twitter/X', () {
    test('tweet URL', () {
      final r =
          service.classify('https://twitter.com/user/status/1234567890');
      expect(r.urlType, UrlType.video);
      expect(r.platform, VideoPlatform.twitter);
      expect(r.itemId, '1234567890');
    });

    test('x.com tweet URL', () {
      final r = service.classify('https://x.com/user/status/1234567890');
      expect(r.urlType, UrlType.video);
      expect(r.platform, VideoPlatform.twitter);
    });

    test('user profile URL', () {
      final r = service.classify('https://twitter.com/elonmusk');
      expect(r.urlType, UrlType.channel);
    });
  });

  group('UrlPatternService.classify — Reddit', () {
    test('post URL', () {
      final r = service.classify(
        'https://www.reddit.com/r/videos/comments/abc123/title_slug',
      );
      expect(r.urlType, UrlType.video);
      expect(r.platform, VideoPlatform.reddit);
      expect(r.itemId, 'abc123');
    });

    test('subreddit URL', () {
      final r = service.classify('https://www.reddit.com/r/videos');
      expect(r.urlType, UrlType.channel);
    });
  });

  group('UrlPatternService.classify — tier-2 platforms', () {
    test('Instagram URL → video (deferred classification)', () {
      final r = service.classify('https://www.instagram.com/p/ABC123/');
      expect(r.urlType, UrlType.video);
      expect(r.platform, VideoPlatform.instagram);
    });

    test('Facebook URL → video', () {
      final r = service.classify(
        'https://www.facebook.com/watch/?v=1234567890',
      );
      expect(r.urlType, UrlType.video);
      expect(r.platform, VideoPlatform.facebook);
    });
  });

  group('UrlPatternService.classify — unsupported URLs', () {
    test('random HTTPS URL on unknown platform', () {
      final r = service.classify('https://example.com/page');
      expect(r.urlType, UrlType.unknown);
      expect(r.platform, VideoPlatform.unknown);
    });
  });

  group('UrlClassification helpers', () {
    test('isPreviewable true for video', () {
      final r = service.classify('https://youtube.com/watch?v=abcdef12345');
      expect(r.isPreviewable, isTrue);
    });

    test('isPreviewable false for playlist', () {
      final r = service.classify('https://youtube.com/playlist?list=PLxxx');
      expect(r.isPreviewable, isFalse);
    });

    test('isKnownUrlType true for channel', () {
      final r = service.classify('https://youtube.com/@MrBeast');
      expect(r.isKnownUrlType, isTrue);
    });

    test('isKnownUrlType true for search (Codex audit P1 #6 fix)', () {
      final r =
          service.classify('https://youtube.com/results?search_query=cats');
      expect(r.urlType, UrlType.search);
      expect(
        r.isKnownUrlType,
        isTrue,
        reason: 'search URLs must reach popup → "Open in SSvid" per spec Q18',
      );
    });

    test('isKnownUrlType false for notUrl', () {
      final r = service.classify('search keyword');
      expect(r.isKnownUrlType, isFalse);
    });
  });
}
