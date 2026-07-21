import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/core/utils/url_normalizer.dart';

/// RC10 Blocker 1 of Ultra Plan v3 — pin `UrlNormalizer` contract.
/// Used by auth retry filter + duplicate detection + floating-capture
/// URL matching, so the semantic must hold across all callsites.
void main() {
  group('UrlNormalizer.normalize', () {
    test('empty / null / blank → empty string', () {
      expect(UrlNormalizer.normalize(null), '');
      expect(UrlNormalizer.normalize(''), '');
      expect(UrlNormalizer.normalize('   '), '');
    });

    test('lowercases host but preserves path case', () {
      // Per RFC 3986, host is case-insensitive; path is case-sensitive.
      expect(
        UrlNormalizer.normalize('https://YOUTUBE.COM/Watch?v=ABC'),
        'https://youtube.com/Watch?v=ABC',
      );
    });

    test('strips fragment', () {
      expect(
        UrlNormalizer.normalize('https://youtube.com/watch?v=abc#t=10'),
        'https://youtube.com/watch?v=abc',
      );
    });

    test('strips trailing slash on non-root path', () {
      expect(
        UrlNormalizer.normalize('https://example.com/path/'),
        'https://example.com/path',
      );
    });

    test('preserves root slash', () {
      expect(
        UrlNormalizer.normalize('https://example.com/'),
        'https://example.com/',
      );
    });

    test('strips tracking params (utm_*, fbclid, etc.)', () {
      expect(
        UrlNormalizer.normalize(
          'https://example.com/path?id=1&utm_source=fb&fbclid=xyz&utm_medium=cpc',
        ),
        'https://example.com/path?id=1',
      );
    });

    test('strips YouTube tracking params (si, pp, feature)', () {
      expect(
        UrlNormalizer.normalize(
          'https://youtube.com/watch?v=abc&si=share&pp=ad&feature=youtu',
        ),
        'https://youtube.com/watch?v=abc',
      );
    });

    test('sorts remaining query params for stable comparison', () {
      final a = UrlNormalizer.normalize('https://x.com/path?b=2&a=1');
      final b = UrlNormalizer.normalize('https://x.com/path?a=1&b=2');
      expect(a, b);
      expect(a, 'https://x.com/path?a=1&b=2');
    });

    test('strips default ports', () {
      expect(
        UrlNormalizer.normalize('http://example.com:80/path'),
        'http://example.com/path',
      );
      expect(
        UrlNormalizer.normalize('https://example.com:443/path'),
        'https://example.com/path',
      );
    });

    test('preserves non-default ports', () {
      expect(
        UrlNormalizer.normalize('https://example.com:8443/path'),
        'https://example.com:8443/path',
      );
    });

    test('non-parsable input → fallback lowercased + fragment-stripped', () {
      // Without scheme or host the URI parser won't extract a host.
      // The fallback path still produces a stable comparison key.
      expect(UrlNormalizer.normalize('NOT A URL #fragment'), 'not a url ');
    });
  });

  group('UrlNormalizer.same', () {
    test('YouTube short URL canonicalizes to watch?v=<id> → same', () {
      // RC10 Codex-catch D: canonicalize youtu.be/<id> to
      // youtube.com/watch?v=<id> so auth retry + duplicate
      // detection match both shapes of the same video.
      expect(
        UrlNormalizer.same(
          'https://youtu.be/abc',
          'https://youtube.com/watch?v=abc',
        ),
        isTrue,
      );
    });

    test('YouTube Shorts canonicalizes to watch?v=<id> → same', () {
      expect(
        UrlNormalizer.same(
          'https://youtube.com/shorts/abc',
          'https://youtube.com/watch?v=abc',
        ),
        isTrue,
      );
    });

    test('YouTube embed canonicalizes to watch?v=<id> → same', () {
      expect(
        UrlNormalizer.same(
          'https://youtube.com/embed/abc',
          'https://youtube.com/watch?v=abc',
        ),
        isTrue,
      );
    });

    test('YouTube mobile subdomain → canonical youtube.com', () {
      expect(
        UrlNormalizer.same(
          'https://m.youtube.com/watch?v=abc',
          'https://youtube.com/watch?v=abc',
        ),
        isTrue,
      );
    });

    test('YouTube Music subdomain → canonical youtube.com', () {
      expect(
        UrlNormalizer.same(
          'https://music.youtube.com/watch?v=abc',
          'https://youtube.com/watch?v=abc',
        ),
        isTrue,
      );
    });

    test('Mobile Facebook canonicalizes to www.facebook.com → bare', () {
      // RC10 Codex-round-2 catch 7: m.facebook.com → www.facebook.com,
      // then www. stripped → facebook.com canonical.
      expect(
        UrlNormalizer.same(
          'https://m.facebook.com/reel/123',
          'https://facebook.com/reel/123',
        ),
        isTrue,
      );
    });

    test('www.youtube.com canonicalizes to youtube.com (catch 7)', () {
      expect(
        UrlNormalizer.same(
          'https://www.youtube.com/watch?v=abc',
          'https://youtube.com/watch?v=abc',
        ),
        isTrue,
      );
    });

    test('www.facebook.com canonicalizes to facebook.com (catch 7)', () {
      expect(
        UrlNormalizer.same(
          'https://www.facebook.com/reel/123',
          'https://facebook.com/reel/123',
        ),
        isTrue,
      );
    });

    test('YouTube same canonical URL with different tracking → same', () {
      expect(
        UrlNormalizer.same(
          'https://youtube.com/watch?v=abc&si=share',
          'https://youtube.com/watch?v=abc&utm_source=fb&fbclid=xyz',
        ),
        isTrue,
      );
    });

    test('null / blank inputs → not same', () {
      expect(UrlNormalizer.same(null, 'https://x.com'), isFalse);
      expect(UrlNormalizer.same('https://x.com', null), isFalse);
      expect(UrlNormalizer.same('', 'https://x.com'), isFalse);
      expect(UrlNormalizer.same(null, null), isFalse);
    });

    test('case-insensitive host match', () {
      expect(
        UrlNormalizer.same(
          'https://Example.com/path',
          'https://example.com/path',
        ),
        isTrue,
      );
    });

    test('trailing slash agnostic', () {
      expect(
        UrlNormalizer.same(
          'https://example.com/path',
          'https://example.com/path/',
        ),
        isTrue,
      );
    });

    test('fragment agnostic', () {
      expect(
        UrlNormalizer.same(
          'https://example.com/path',
          'https://example.com/path#section-2',
        ),
        isTrue,
      );
    });
  });
}
