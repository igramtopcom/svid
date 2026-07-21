import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/home/domain/services/url_classifier_service.dart';

void main() {
  const c = UrlClassifierService();

  group('UrlClassifierService — empty / whitespace', () {
    test('empty string → empty', () {
      expect(c.classify(''), SmartInputType.empty);
    });

    test('whitespace only → empty', () {
      expect(c.classify('   \n  \t '), SmartInputType.empty);
    });
  });

  group('UrlClassifierService — single supported video URLs', () {
    final cases = <String, String>{
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ': 'youtube long-form',
      'https://youtu.be/dQw4w9WgXcQ': 'youtu.be short link',
      'https://www.tiktok.com/@scout/video/7100': 'tiktok video',
      'https://www.instagram.com/p/AbC123/': 'instagram post',
      'https://www.facebook.com/watch/?v=12345': 'facebook watch',
      'https://twitter.com/jack/status/1234567890': 'twitter status',
      'https://x.com/elon/status/1234567890': 'x status',
    };

    for (final entry in cases.entries) {
      test('${entry.value} → singleVideo', () {
        expect(c.classify(entry.key), SmartInputType.singleVideo);
      });
    }
  });

  group('UrlClassifierService — channel URLs', () {
    test('youtube /@handle → channel', () {
      expect(
        c.classify('https://www.youtube.com/@MrBeast'),
        SmartInputType.channel,
      );
    });

    test('tiktok /@handle → channel', () {
      expect(
        c.classify('https://www.tiktok.com/@khaby.lame'),
        SmartInputType.channel,
      );
    });

    test('youtube /c/Name legacy → channel', () {
      expect(
        c.classify('https://www.youtube.com/c/PewDiePie'),
        SmartInputType.channel,
      );
    });

    test('youtube /channel/UC... → channel', () {
      expect(
        c.classify('https://www.youtube.com/channel/UCabcdefg1234'),
        SmartInputType.channel,
      );
    });

    test('youtube /user/Name → channel', () {
      expect(
        c.classify('https://www.youtube.com/user/PewDiePie'),
        SmartInputType.channel,
      );
    });
  });

  group('UrlClassifierService — playlist URLs', () {
    test('youtube playlist URL → playlist', () {
      expect(
        c.classify('https://www.youtube.com/playlist?list=PLrAXtmErZgOe'),
        SmartInputType.playlist,
      );
    });

    test('youtube watch+list combo → playlist', () {
      expect(
        c.classify(
          'https://www.youtube.com/watch?v=abc&list=PLrAXtmErZgOe',
        ),
        SmartInputType.playlist,
      );
    });
  });

  group('UrlClassifierService — multipleUrls (whitespace / comma / newline)', () {
    test('two URLs space-separated → multipleUrls', () {
      expect(
        c.classify('https://yt.com/watch?v=a https://tiktok.com/@x/video/1'),
        SmartInputType.multipleUrls,
      );
    });

    test('two URLs comma-separated → multipleUrls', () {
      expect(
        c.classify('https://yt.com/watch?v=a, https://tiktok.com/@x/video/1'),
        SmartInputType.multipleUrls,
      );
    });

    test('two URLs newline-separated → multipleUrls', () {
      expect(
        c.classify('https://yt.com/watch?v=a\nhttps://tiktok.com/@x/video/1'),
        SmartInputType.multipleUrls,
      );
    });

    test('three URLs mixed separators → multipleUrls', () {
      expect(
        c.classify(
          'https://yt.com/watch?v=a, https://tiktok.com/@x/video/1\n'
          'https://twitter.com/y/status/2',
        ),
        SmartInputType.multipleUrls,
      );
    });
  });

  group('UrlClassifierService — unsupported & search', () {
    test('valid HTTP URL but unsupported platform → unsupportedUrl', () {
      expect(
        c.classify('https://example.com/some/page'),
        SmartInputType.unsupportedUrl,
      );
    });

    test('plain text keyword → searchKeyword', () {
      expect(
        c.classify('lofi chill playlist 2026'),
        SmartInputType.searchKeyword,
      );
    });

    test('keyword mixed with one URL → searchKeyword (not URL)', () {
      // Spec §4.1 — mixed text → ignore non-URL → treat as keyword.
      expect(
        c.classify('check this https://yt.com/watch?v=abc'),
        SmartInputType.searchKeyword,
      );
    });

    test('vietnamese keyword → searchKeyword', () {
      expect(
        c.classify('lofi đêm khuya'),
        SmartInputType.searchKeyword,
      );
    });
  });

  group('UrlClassifierService.extractUrlTokens — multi-URL split', () {
    test('empty input → empty list', () {
      expect(c.extractUrlTokens(''), isEmpty);
    });

    test('whitespace-only → empty list', () {
      expect(c.extractUrlTokens('   \n  \t '), isEmpty);
    });

    test('single keyword (no URL) → empty list', () {
      expect(c.extractUrlTokens('lofi chill 2026'), isEmpty);
    });

    test('single URL → list of 1', () {
      expect(
        c.extractUrlTokens('https://www.youtube.com/watch?v=abc'),
        ['https://www.youtube.com/watch?v=abc'],
      );
    });

    test('two URLs space-separated → list of 2', () {
      expect(
        c.extractUrlTokens(
          'https://yt.com/watch?v=a https://tiktok.com/@x/video/1',
        ),
        ['https://yt.com/watch?v=a', 'https://tiktok.com/@x/video/1'],
      );
    });

    test('two URLs comma-separated → list of 2', () {
      expect(
        c.extractUrlTokens(
          'https://yt.com/watch?v=a, https://tiktok.com/@x/video/1',
        ),
        ['https://yt.com/watch?v=a', 'https://tiktok.com/@x/video/1'],
      );
    });

    test('three URLs newline-separated → list of 3', () {
      expect(
        c.extractUrlTokens(
          'https://yt.com/watch?v=a\n'
          'https://tiktok.com/@x/video/1\n'
          'https://twitter.com/y/status/2',
        ),
        [
          'https://yt.com/watch?v=a',
          'https://tiktok.com/@x/video/1',
          'https://twitter.com/y/status/2',
        ],
      );
    });

    test('mixed URL + keyword tokens → URLs only', () {
      expect(
        c.extractUrlTokens(
          'check this https://yt.com/watch?v=abc and that '
          'https://tiktok.com/@x/video/1',
        ),
        ['https://yt.com/watch?v=abc', 'https://tiktok.com/@x/video/1'],
      );
    });

    test('blank lines preserved as whitespace separators (no empty tokens)',
        () {
      expect(
        c.extractUrlTokens(
          'https://yt.com/watch?v=a\n\n\nhttps://tiktok.com/@x/video/1',
        ),
        ['https://yt.com/watch?v=a', 'https://tiktok.com/@x/video/1'],
      );
    });

    test('local file path token dropped (not URL shape)', () {
      expect(
        c.extractUrlTokens(
          r'c:\Users\foo https://yt.com/watch?v=a',
        ),
        ['https://yt.com/watch?v=a'],
      );
    });
  });

  group('UrlClassifierService — edge cases', () {
    test('http (not https) youtube → still recognised', () {
      expect(
        c.classify('http://www.youtube.com/watch?v=abc'),
        SmartInputType.singleVideo,
      );
    });

    test('local file path (c:\\foo) → searchKeyword (not URL)', () {
      expect(c.classify(r'c:\Users\foo'), SmartInputType.searchKeyword);
    });

    test('youtu.be channel-alike (not channel pattern) → singleVideo', () {
      expect(
        c.classify('https://youtu.be/abc123'),
        SmartInputType.singleVideo,
      );
    });

    test('uppercase URL → still recognised', () {
      expect(
        c.classify('HTTPS://YOUTUBE.COM/WATCH?V=ABC'),
        SmartInputType.singleVideo,
      );
    });
  });
}
