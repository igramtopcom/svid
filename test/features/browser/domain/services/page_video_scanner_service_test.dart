import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/utils/platform_detector.dart';
import 'package:svid/features/browser/domain/services/page_video_scanner_service.dart';

void main() {
  late PageVideoScannerService service;

  setUp(() {
    service = PageVideoScannerService();
  });

  group('generateScanScript', () {
    test('returns a self-executing function', () {
      final script = service.generateScanScript();
      expect(script.trim(), startsWith('(function()'));
      expect(script.trim(), endsWith('})()'));
    });

    test('scans a[href] links', () {
      final script = service.generateScanScript();
      expect(script, contains("a[href]"));
    });

    test('scans video[src] and source[src]', () {
      final script = service.generateScanScript();
      expect(script, contains("video[src]"));
      expect(script, contains("source[src]"));
    });

    test('scans iframe[src]', () {
      final script = service.generateScanScript();
      expect(script, contains("iframe[src]"));
    });

    test('scans og:video meta tags', () {
      final script = service.generateScanScript();
      expect(script, contains('og:video'));
    });

    test('returns JSON.stringify results', () {
      final script = service.generateScanScript();
      expect(script, contains('JSON.stringify(results)'));
    });

    test('deduplicates by normalized URL', () {
      final script = service.generateScanScript();
      expect(script, contains('seen[normalized]'));
    });

    test('includes video platform URL patterns', () {
      final script = service.generateScanScript();
      expect(script, contains('youtube'));
      expect(script, contains('tiktok'));
      expect(script, contains('instagram'));
      expect(script, contains('vimeo'));
    });
  });

  group('parseResults', () {
    test('returns empty list for empty string', () {
      expect(service.parseResults(''), isEmpty);
    });

    test('returns empty list for empty array', () {
      expect(service.parseResults('[]'), isEmpty);
    });

    test('parses YouTube video link', () {
      final json = jsonEncode([
        {
          'url': 'https://www.youtube.com/watch?v=abc123',
          'title': 'My Video',
          'sourceType': 'link',
        },
      ]);
      final results = service.parseResults(json);
      expect(results, hasLength(1));
      expect(results[0].url, 'https://www.youtube.com/watch?v=abc123');
      expect(results[0].title, 'My Video');
      expect(results[0].platform, VideoPlatform.youtube);
      expect(results[0].sourceType, VideoSourceType.link);
    });

    test('parses TikTok video link', () {
      final json = jsonEncode([
        {
          'url': 'https://www.tiktok.com/@user/video/1234567890',
          'title': 'TikTok Video',
          'sourceType': 'link',
        },
      ]);
      final results = service.parseResults(json);
      expect(results, hasLength(1));
      expect(results[0].platform, VideoPlatform.tiktok);
    });

    test('parses Instagram reel', () {
      final json = jsonEncode([
        {
          'url': 'https://www.instagram.com/reel/Cxyz123/',
          'title': '',
          'sourceType': 'link',
        },
      ]);
      final results = service.parseResults(json);
      expect(results, hasLength(1));
      expect(results[0].platform, VideoPlatform.instagram);
      // Empty title falls back to URL segment
      expect(results[0].title, isNotEmpty);
    });

    test('parses Vimeo embed', () {
      final json = jsonEncode([
        {
          'url': 'https://player.vimeo.com/video/123456789',
          'title': '',
          'sourceType': 'embed',
        },
      ]);
      final results = service.parseResults(json);
      expect(results, hasLength(1));
      expect(results[0].platform, VideoPlatform.vimeo);
      expect(results[0].sourceType, VideoSourceType.embed);
    });

    test('parses og:video meta tag', () {
      final json = jsonEncode([
        {
          'url': 'https://www.dailymotion.com/video/x1234abc',
          'title': 'Page Title',
          'sourceType': 'meta',
        },
      ]);
      final results = service.parseResults(json);
      expect(results, hasLength(1));
      expect(results[0].platform, VideoPlatform.dailymotion);
      expect(results[0].sourceType, VideoSourceType.meta);
      expect(results[0].title, 'Page Title');
    });

    test('deduplicates by normalized URL', () {
      final json = jsonEncode([
        {
          'url': 'https://www.youtube.com/watch?v=abc123',
          'title': 'First',
          'sourceType': 'link',
        },
        {
          'url': 'https://www.youtube.com/watch?v=abc123&t=10',
          'title': 'Second',
          'sourceType': 'link',
        },
      ]);
      final results = service.parseResults(json);
      // Both normalize to youtube.com/watch (query stripped)
      expect(results, hasLength(1));
      expect(results[0].title, 'First'); // First one wins
    });

    test('keeps distinct video URLs', () {
      final json = jsonEncode([
        {
          'url': 'https://www.youtube.com/shorts/abc123',
          'title': 'Video 1',
          'sourceType': 'link',
        },
        {
          'url': 'https://www.youtube.com/shorts/def456',
          'title': 'Video 2',
          'sourceType': 'link',
        },
      ]);
      final results = service.parseResults(json);
      expect(results, hasLength(2));
    });

    test('filters out non-video URLs', () {
      final json = jsonEncode([
        {
          'url': 'https://www.google.com/search?q=test',
          'title': 'Search',
          'sourceType': 'link',
        },
        {
          'url': 'https://www.youtube.com/watch?v=abc123',
          'title': 'Video',
          'sourceType': 'link',
        },
      ]);
      final results = service.parseResults(json);
      expect(results, hasLength(1));
      expect(results[0].platform, VideoPlatform.youtube);
    });

    test('handles quoted JSON from WebView', () {
      final inner = jsonEncode([
        {
          'url': 'https://www.youtube.com/watch?v=abc123',
          'title': 'Test',
          'sourceType': 'link',
        },
      ]);
      // WebView may wrap the result in extra quotes
      final quoted = "'$inner'";
      final results = service.parseResults(quoted);
      expect(results, hasLength(1));
    });

    test('handles empty URL in results', () {
      final json = jsonEncode([
        {
          'url': '',
          'title': 'Empty',
          'sourceType': 'link',
        },
        {
          'url': 'https://www.youtube.com/watch?v=abc123',
          'title': 'Valid',
          'sourceType': 'link',
        },
      ]);
      final results = service.parseResults(json);
      expect(results, hasLength(1));
      expect(results[0].title, 'Valid');
    });

    test('handles malformed JSON gracefully', () {
      final results = service.parseResults('not json at all');
      expect(results, isEmpty);
    });

    test('parses Facebook video link', () {
      final json = jsonEncode([
        {
          'url': 'https://www.facebook.com/user/videos/123456789',
          'title': 'FB Video',
          'sourceType': 'link',
        },
      ]);
      final results = service.parseResults(json);
      expect(results, hasLength(1));
      expect(results[0].platform, VideoPlatform.facebook);
    });

    test('parses Twitter/X status link', () {
      final json = jsonEncode([
        {
          'url': 'https://x.com/user/status/1234567890',
          'title': 'Tweet',
          'sourceType': 'link',
        },
      ]);
      final results = service.parseResults(json);
      expect(results, hasLength(1));
      expect(results[0].platform, VideoPlatform.twitter);
    });

    test('parses Reddit comments link', () {
      final json = jsonEncode([
        {
          'url': 'https://www.reddit.com/r/test/comments/abc123/title',
          'title': 'Reddit Post',
          'sourceType': 'link',
        },
      ]);
      final results = service.parseResults(json);
      expect(results, hasLength(1));
      expect(results[0].platform, VideoPlatform.reddit);
    });

    test('parses SoundCloud track link', () {
      final json = jsonEncode([
        {
          'url': 'https://soundcloud.com/artist/track-name',
          'title': 'Track',
          'sourceType': 'link',
        },
      ]);
      final results = service.parseResults(json);
      expect(results, hasLength(1));
      expect(results[0].platform, VideoPlatform.soundcloud);
    });

    test('parses Bilibili video link', () {
      final json = jsonEncode([
        {
          'url': 'https://www.bilibili.com/video/BV1xx411c7mD',
          'title': 'Bilibili',
          'sourceType': 'link',
        },
      ]);
      final results = service.parseResults(json);
      expect(results, hasLength(1));
      expect(results[0].platform, VideoPlatform.bilibili);
    });

    test('parses multiple platforms in one scan', () {
      final json = jsonEncode([
        {
          'url': 'https://www.youtube.com/watch?v=abc',
          'title': 'YT',
          'sourceType': 'link',
        },
        {
          'url': 'https://vimeo.com/123456789',
          'title': 'Vimeo',
          'sourceType': 'embed',
        },
        {
          'url': 'https://www.tiktok.com/@user/video/99999',
          'title': 'TT',
          'sourceType': 'link',
        },
      ]);
      final results = service.parseResults(json);
      expect(results, hasLength(3));
      expect(results.map((v) => v.platform).toSet(), {
        VideoPlatform.youtube,
        VideoPlatform.vimeo,
        VideoPlatform.tiktok,
      });
    });
  });

  group('DetectedVideoLink', () {
    test('equality based on URL', () {
      const a = DetectedVideoLink(
        url: 'https://youtube.com/watch?v=abc',
        title: 'Title A',
        platform: VideoPlatform.youtube,
        sourceType: VideoSourceType.link,
      );
      const b = DetectedVideoLink(
        url: 'https://youtube.com/watch?v=abc',
        title: 'Title B',
        platform: VideoPlatform.youtube,
        sourceType: VideoSourceType.embed,
      );
      expect(a, equals(b));
    });

    test('inequality for different URLs', () {
      const a = DetectedVideoLink(
        url: 'https://youtube.com/watch?v=abc',
        title: 'Title',
        platform: VideoPlatform.youtube,
        sourceType: VideoSourceType.link,
      );
      const b = DetectedVideoLink(
        url: 'https://youtube.com/watch?v=def',
        title: 'Title',
        platform: VideoPlatform.youtube,
        sourceType: VideoSourceType.link,
      );
      expect(a, isNot(equals(b)));
    });

    test('toString contains url and platform', () {
      const v = DetectedVideoLink(
        url: 'https://youtube.com/watch?v=abc',
        title: 'My Video',
        platform: VideoPlatform.youtube,
        sourceType: VideoSourceType.link,
      );
      expect(v.toString(), contains('youtube'));
      expect(v.toString(), contains('https://youtube.com/watch?v=abc'));
    });

    test('hashCode based on URL', () {
      const a = DetectedVideoLink(
        url: 'https://youtube.com/watch?v=abc',
        title: 'A',
        platform: VideoPlatform.youtube,
        sourceType: VideoSourceType.link,
      );
      const b = DetectedVideoLink(
        url: 'https://youtube.com/watch?v=abc',
        title: 'B',
        platform: VideoPlatform.youtube,
        sourceType: VideoSourceType.embed,
      );
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
