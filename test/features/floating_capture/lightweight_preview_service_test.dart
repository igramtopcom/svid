import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ssvid/core/utils/platform_detector.dart';
import 'package:ssvid/features/downloads/domain/entities/video_preview.dart';
import 'package:ssvid/features/floating_capture/data/datasources/lightweight_preview_service.dart';

void main() {
  group('LightweightPreviewService — YouTube', () {
    test('successful oEmbed returns rich preview', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.host, 'www.youtube.com');
        expect(request.url.path, '/oembed');
        expect(request.url.queryParameters['format'], 'json');
        return http.Response(
          jsonEncode({
            'title': 'Never Gonna Give You Up',
            'author_name': 'Rick Astley',
            'thumbnail_url':
                'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
            'type': 'video',
          }),
          200,
        );
      });

      final service = LightweightPreviewService(client: mockClient);
      final result = await service.fetchPreview(
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );

      expect(result.platform, VideoPlatform.youtube);
      expect(result.urlType, UrlType.video);
      expect(result.itemId, 'dQw4w9WgXcQ');
      expect(result.title, 'Never Gonna Give You Up');
      expect(result.uploader, 'Rick Astley');
      expect(result.hasFetchedMetadata, isTrue);
      // YouTube uses CDN pattern for thumbnail, prefers maxresdefault
      expect(
        result.thumbnailUrl,
        'https://img.youtube.com/vi/dQw4w9WgXcQ/maxresdefault.jpg',
      );
    });

    test('404 returns fallback preview with Tier A maxresdefault thumbnail',
        () async {
      final mockClient = MockClient((request) async {
        return http.Response('Not Found', 404);
      });

      final service = LightweightPreviewService(client: mockClient);
      final result = await service.fetchPreview(
        'https://www.youtube.com/watch?v=privatevidx',
      );

      expect(result.platform, VideoPlatform.youtube);
      expect(result.urlType, UrlType.video);
      expect(result.itemId, 'privatevidx');
      expect(result.hasFetchedMetadata, isFalse);
      expect(result.title, isNull);
      // v2.2 4-tier strategy: Tier A canonical thumbnail (maxresdefault) is
      // preferred over Tier B oEmbed even when oEmbed fails. UI image widget
      // handles 404 fallback to hqdefault as a presentation concern.
      expect(
        result.thumbnailUrl,
        'https://img.youtube.com/vi/privatevidx/maxresdefault.jpg',
      );
    });

    test('network timeout returns fallback', () async {
      final mockClient = MockClient((request) async {
        // Simulate timeout by waiting longer than service timeout
        await Future.delayed(const Duration(seconds: 10));
        return http.Response('{}', 200);
      });

      final service = LightweightPreviewService(
        client: mockClient,
        timeout: const Duration(milliseconds: 100),
      );

      final result = await service.fetchPreview(
        'https://youtube.com/watch?v=abcdef12345',
      );

      expect(result.hasFetchedMetadata, isFalse);
      expect(result.platform, VideoPlatform.youtube);
    });

    test('malformed JSON returns fallback', () async {
      final mockClient = MockClient((request) async {
        return http.Response('not valid json', 200);
      });

      final service = LightweightPreviewService(client: mockClient);
      final result = await service.fetchPreview(
        'https://youtube.com/watch?v=abcdef12345',
      );

      expect(result.hasFetchedMetadata, isFalse);
    });
  });

  group('LightweightPreviewService — Vimeo', () {
    test('successful oEmbed', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.host, 'vimeo.com');
        expect(request.url.path, '/api/oembed.json');
        return http.Response(
          jsonEncode({
            'title': 'Sample Vimeo Video',
            'author_name': 'Filmmaker',
            'thumbnail_url': 'https://i.vimeocdn.com/thumb.jpg',
          }),
          200,
        );
      });

      final service = LightweightPreviewService(client: mockClient);
      final result =
          await service.fetchPreview('https://vimeo.com/123456789');

      expect(result.platform, VideoPlatform.vimeo);
      expect(result.title, 'Sample Vimeo Video');
      expect(result.uploader, 'Filmmaker');
      // v2.2: Tier A vumbnail.com CDN URL preferred over oEmbed thumbnail_url
      // (faster, sharper for hi-DPI). Behavior intentional — oEmbed metadata
      // (title/author) still consumed; thumbnail field is overridden.
      expect(result.thumbnailUrl, 'https://vumbnail.com/123456789.jpg');
    });
  });

  group('LightweightPreviewService — non-tier-1 platforms', () {
    test('Instagram URL returns fallback without fetch', () async {
      var fetchCalled = false;
      final mockClient = MockClient((request) async {
        fetchCalled = true;
        return http.Response('{}', 200);
      });

      final service = LightweightPreviewService(client: mockClient);
      final result =
          await service.fetchPreview('https://www.instagram.com/p/ABC123/');

      expect(fetchCalled, isFalse, reason: 'Should NOT call oEmbed for Tier-2');
      expect(result.platform, VideoPlatform.instagram);
      expect(result.hasFetchedMetadata, isFalse);
      expect(result.urlType, UrlType.video);
    });

    test('Facebook URL returns fallback without fetch', () async {
      var fetchCalled = false;
      final mockClient = MockClient((request) async {
        fetchCalled = true;
        return http.Response('{}', 200);
      });

      final service = LightweightPreviewService(client: mockClient);
      final result = await service.fetchPreview(
        'https://www.facebook.com/watch/?v=1234567890',
      );

      expect(fetchCalled, isFalse);
      expect(result.platform, VideoPlatform.facebook);
    });
  });

  group('LightweightPreviewService — non-video URL types', () {
    test('YouTube channel URL skips fetch', () async {
      var fetchCalled = false;
      final mockClient = MockClient((request) async {
        fetchCalled = true;
        return http.Response('{}', 200);
      });

      final service = LightweightPreviewService(client: mockClient);
      final result =
          await service.fetchPreview('https://youtube.com/@MrBeast');

      expect(fetchCalled, isFalse);
      expect(result.urlType, UrlType.channel);
    });

    test('YouTube playlist URL skips fetch', () async {
      var fetchCalled = false;
      final mockClient = MockClient((request) async {
        fetchCalled = true;
        return http.Response('{}', 200);
      });

      final service = LightweightPreviewService(client: mockClient);
      final result =
          await service.fetchPreview('https://youtube.com/playlist?list=PLxx');

      expect(fetchCalled, isFalse);
      expect(result.urlType, UrlType.playlist);
    });

    test('plain text (notUrl) returns minimal fallback', () async {
      var fetchCalled = false;
      final mockClient = MockClient((request) async {
        fetchCalled = true;
        return http.Response('{}', 200);
      });

      final service = LightweightPreviewService(client: mockClient);
      final result = await service.fetchPreview('MrBeast latest video');

      expect(fetchCalled, isFalse);
      expect(result.urlType, UrlType.notUrl);
      expect(result.platform, VideoPlatform.unknown);
    });
  });

  group('LightweightPreviewService — TikTok short URL redirect', () {
    test('vm.tiktok.com short URL resolves via HEAD then fetches oEmbed',
        () async {
      var step = 0;
      final mockClient = MockClient((request) async {
        step++;
        if (step == 1) {
          // First call: HEAD redirect resolve
          expect(request.method, 'HEAD');
          expect(request.url.host, 'vm.tiktok.com');
          return http.Response(
            '',
            301,
            headers: {
              'location':
                  'https://www.tiktok.com/@user.name/video/1234567890',
            },
          );
        } else {
          // Second call: oEmbed fetch
          expect(request.method, 'GET');
          expect(request.url.host, 'www.tiktok.com');
          expect(request.url.path, '/oembed');
          return http.Response(
            jsonEncode({
              'title': 'Cool TikTok',
              'author_name': 'tiktokuser',
              'thumbnail_url': 'https://p16-sign-va.tiktokcdn.com/thumb.jpg',
            }),
            200,
          );
        }
      });

      final service = LightweightPreviewService(client: mockClient);
      final result =
          await service.fetchPreview('https://vm.tiktok.com/SHORTCODE');

      expect(step, 2, reason: 'Should make 2 calls: HEAD + GET');
      expect(result.platform, VideoPlatform.tiktok);
      expect(result.title, 'Cool TikTok');
      expect(result.uploader, 'tiktokuser');
      expect(result.itemId, '1234567890',
          reason: 'itemId should come from re-classifying canonical URL');
      expect(result.rawUrl, 'https://vm.tiktok.com/SHORTCODE',
          reason: 'rawUrl preserves original user-pasted URL');
      expect(result.hasFetchedMetadata, isTrue);
    });

    test('vt.tiktok.com short URL also triggers redirect resolution',
        () async {
      var step = 0;
      final mockClient = MockClient((request) async {
        step++;
        if (step == 1) {
          expect(request.method, 'HEAD');
          return http.Response(
            '',
            302,
            headers: {
              'location': 'https://www.tiktok.com/@u/video/9999999999',
            },
          );
        }
        return http.Response(
          jsonEncode({'title': 'X', 'author_name': 'Y'}),
          200,
        );
      });

      final service = LightweightPreviewService(client: mockClient);
      final result =
          await service.fetchPreview('https://vt.tiktok.com/SHORT');

      expect(step, 2);
      expect(result.itemId, '9999999999');
    });

    test('redirect resolution failure returns fallback', () async {
      var step = 0;
      final mockClient = MockClient((request) async {
        step++;
        // No Location header → resolution fails
        return http.Response('', 200);
      });

      final service = LightweightPreviewService(client: mockClient);
      final result =
          await service.fetchPreview('https://vm.tiktok.com/SHORTCODE');

      expect(step, 1, reason: 'Only HEAD attempted; oEmbed skipped');
      expect(result.platform, VideoPlatform.tiktok);
      expect(result.hasFetchedMetadata, isFalse);
      expect(result.rawUrl, 'https://vm.tiktok.com/SHORTCODE');
    });

    test('User-Agent header sent on TikTok redirect HEAD', () async {
      String? sentUa;
      final mockClient = MockClient((request) async {
        sentUa ??= request.headers['User-Agent'];
        return http.Response('', 301, headers: {
          'location': 'https://www.tiktok.com/@u/video/123',
        });
      });

      final service = LightweightPreviewService(client: mockClient);
      await service.fetchPreview('https://vm.tiktok.com/SHORT');

      expect(sentUa, contains('SSvid'));
    });

    test('oEmbed call carries User-Agent + Accept headers', () async {
      Map<String, String>? sentHeaders;
      final mockClient = MockClient((request) async {
        sentHeaders = Map.of(request.headers);
        return http.Response(
          jsonEncode({'title': 'T', 'author_name': 'A'}),
          200,
        );
      });

      final service = LightweightPreviewService(client: mockClient);
      await service.fetchPreview(
        'https://www.youtube.com/watch?v=abcdef12345',
      );

      expect(sentHeaders!['User-Agent'], contains('SSvid'));
      expect(sentHeaders!['Accept'], 'application/json');
    });
  });

  group('LightweightPreviewService — timestamp preservation', () {
    test('URL with ?t=120 preserves startTimestamp', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'title': 'T', 'author_name': 'A'}),
          200,
        );
      });

      final service = LightweightPreviewService(client: mockClient);
      final result = await service.fetchPreview(
        'https://youtube.com/watch?v=abcdef12345&t=120s',
      );

      expect(result.startTimestamp, const Duration(seconds: 120));
    });
  });

  // ===========================================================================
  // v2.2 — 4-tier strategy additions
  // ===========================================================================

  group('LightweightPreviewService v2.2 — Dailymotion (Tier B expansion)', () {
    test('Dailymotion video URL hits oEmbed endpoint', () async {
      var endpoint = '';
      final mockClient = MockClient((request) async {
        endpoint = request.url.toString();
        return http.Response(
          jsonEncode({
            'title': 'A Dailymotion video',
            'author_name': 'creator123',
            'thumbnail_url': 'https://s2.dmcdn.net/v/abc/x720',
          }),
          200,
        );
      });

      final service = LightweightPreviewService(client: mockClient);
      final result = await service.fetchPreview(
        'https://www.dailymotion.com/video/x8x8x8x',
      );

      expect(endpoint, contains('dailymotion.com/services/oembed'));
      expect(result.platform, VideoPlatform.dailymotion);
      expect(result.title, 'A Dailymotion video');
      expect(result.uploader, 'creator123');
      expect(result.thumbnailUrl, 'https://s2.dmcdn.net/v/abc/x720');
      expect(result.hasFetchedMetadata, isTrue);
    });
  });

  group('LightweightPreviewService v2.2 — SoundCloud (Tier B expansion)', () {
    test('SoundCloud track URL hits oEmbed endpoint', () async {
      var endpoint = '';
      final mockClient = MockClient((request) async {
        endpoint = request.url.toString();
        return http.Response(
          jsonEncode({
            'title': 'My Song',
            'author_name': 'Artist',
            'thumbnail_url': 'https://i1.sndcdn.com/artworks-abc-large.jpg',
          }),
          200,
        );
      });

      final service = LightweightPreviewService(client: mockClient);
      final result = await service.fetchPreview(
        'https://soundcloud.com/artist/track-name',
      );

      expect(endpoint, contains('soundcloud.com/oembed'));
      expect(endpoint, contains('format=json'));
      expect(result.platform, VideoPlatform.soundcloud);
      expect(result.title, 'My Song');
      expect(result.thumbnailUrl,
          'https://i1.sndcdn.com/artworks-abc-large.jpg');
    });
  });

  group('LightweightPreviewService v2.2 — Tier C OG image scrape', () {
    test('Threads URL → OG image successfully scraped', () async {
      var capturedUserAgent = '';
      final mockClient = MockClient((request) async {
        capturedUserAgent = request.headers['User-Agent'] ?? '';
        // Realistic HTML response from Threads
        return http.Response(
          '<!DOCTYPE html><html><head>'
          '<meta property="og:title" content="A Thread"/>'
          '<meta property="og:image" content="https://scontent.threads.com/og123.jpg"/>'
          '<meta property="og:description" content="…"/>'
          '</head><body></body></html>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      });

      final service = LightweightPreviewService(client: mockClient);
      final result = await service.fetchPreview(
        'https://www.threads.net/@user/post/abc123',
      );

      // Realistic browser UA used (not 'SSvid/2.2')
      expect(capturedUserAgent, contains('Mozilla/5.0'));
      expect(capturedUserAgent, contains('Chrome'));
      expect(capturedUserAgent, isNot(contains('SSvid')));
      expect(result.thumbnailUrl, 'https://scontent.threads.com/og123.jpg');
      expect(result.platform, VideoPlatform.threads);
    });

    test('Instagram URL does NOT attempt OG scrape (Cloudflare blocked)',
        () async {
      var fetchCalled = false;
      final mockClient = MockClient((request) async {
        fetchCalled = true;
        return http.Response('{}', 200);
      });

      final service = LightweightPreviewService(client: mockClient);
      final result =
          await service.fetchPreview('https://www.instagram.com/p/Cabc/');

      // Per ultra-review C4: Instagram is intentionally NOT in OG scrape list
      // because Cloudflare blocks requests aggressively. Skipping saves 5s
      // of timeout per capture.
      expect(fetchCalled, isFalse);
      expect(result.platform, VideoPlatform.instagram);
      expect(result.thumbnailUrl, isNull);
    });

    test('Facebook URL does NOT attempt OG scrape (Cloudflare blocked)',
        () async {
      var fetchCalled = false;
      final mockClient = MockClient((request) async {
        fetchCalled = true;
        return http.Response('{}', 200);
      });

      final service = LightweightPreviewService(client: mockClient);
      final result =
          await service.fetchPreview('https://www.facebook.com/watch/?v=123');

      expect(fetchCalled, isFalse);
      expect(result.platform, VideoPlatform.facebook);
      expect(result.thumbnailUrl, isNull);
    });

    test('OG scrape: malformed HTML returns null (graceful)', () {
      final service = LightweightPreviewService();
      expect(service.parseOgImageFromHtml('not html'), isNull);
      expect(service.parseOgImageFromHtml(''), isNull);
      expect(
        service.parseOgImageFromHtml('<html><head></head></html>'),
        isNull,
      );
    });

    test('OG scrape: parses double-quoted attribute order property/content',
        () {
      final service = LightweightPreviewService();
      expect(
        service.parseOgImageFromHtml(
          '<meta property="og:image" content="https://x.com/img.jpg">',
        ),
        'https://x.com/img.jpg',
      );
    });

    test('OG scrape: parses reverse attribute order content/property', () {
      final service = LightweightPreviewService();
      expect(
        service.parseOgImageFromHtml(
          '<meta content="https://x.com/img.jpg" property="og:image">',
        ),
        'https://x.com/img.jpg',
      );
    });

    test('OG scrape: parses single-quoted attributes', () {
      final service = LightweightPreviewService();
      expect(
        service.parseOgImageFromHtml(
          "<meta property='og:image' content='https://x.com/img.jpg'>",
        ),
        'https://x.com/img.jpg',
      );
    });

    test('OG scrape: tolerates extra attributes interleaved', () {
      final service = LightweightPreviewService();
      expect(
        service.parseOgImageFromHtml(
          '<meta name="ignore" property="og:image" charset="utf-8" content="https://x.com/img.jpg" foo="bar">',
        ),
        'https://x.com/img.jpg',
      );
    });
  });
}
