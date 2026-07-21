import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/config/brand_config.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/platform_detector.dart';
import '../../../downloads/domain/entities/video_preview.dart';
import '../../domain/services/url_pattern_service.dart';

/// Fetches lightweight video metadata via a 4-tier strategy (v2.2 spec §2 Shift 3):
///
///   Tier A — Canonical thumbnail derived from itemId (synchronous, no HTTP).
///            YouTube, Vimeo. Always preferred when available because it
///            gives consistent high-resolution thumbnails.
///
///   Tier B — Public oEmbed APIs. Returns title + author + thumbnail_url.
///            Tier-1 platforms: YouTube, Vimeo, TikTok, X/Twitter, Reddit,
///            **Dailymotion (NEW v2.2)**, **SoundCloud (NEW v2.2)**.
///
///   Tier C — Open Graph image meta tag scraping with realistic browser
///            User-Agent. Used for: Threads, Pinterest, LinkedIn, Bilibili.
///            **Skipped for Instagram + Facebook** — Cloudflare bot
///            detection blocks aggressively (ultra-review C4 fix).
///
///   Tier D — Platform logo placeholder (UI uses the platform field — this
///            service returns thumbnailUrl=null for fallback). Phase 2B
///            will render proper SVG asset; Phase 2A keeps existing UI.
///
/// Never throws — failures degrade through tiers. Caller checks
/// [VideoPreview.hasFetchedMetadata] for the rich-vs-fallback signal.
class LightweightPreviewService {
  final http.Client _client;
  final Duration _timeout;
  final UrlPatternService _urlPattern;

  /// User-Agent used for oEmbed/JSON API calls — identifies the app for
  /// platforms that gate by UA (TikTok especially) but doesn't pretend to
  /// be a browser since oEmbed is a documented public API. Brand + version
  /// resolved at runtime to avoid SSvid-identity leak when running as
  /// VidCombo (or any future brand).
  static String get _apiUserAgent {
    final brand = BrandConfig.current;
    return '${brand.appName}/${AppConstants.appVersion} (${brand.websiteUrl})';
  }

  /// Realistic Chrome User-Agent for Tier C OG image scraping. Many
  /// platforms (Threads, Pinterest, LinkedIn) return different markup or
  /// outright block requests carrying scraper-like UAs (ultra-review C4).
  /// Don't use this for oEmbed — that's misleading.
  static const _browserUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// Default 5s timeout — oEmbed typically <500ms; OG scrape can be slower
  /// (up to ~2s for Pinterest), 5s is the upper bound.
  LightweightPreviewService({
    http.Client? client,
    Duration timeout = const Duration(seconds: 5),
    UrlPatternService? urlPattern,
  })  : _client = client ?? http.Client(),
        _timeout = timeout,
        _urlPattern = urlPattern ?? const UrlPatternService();

  /// Fetch preview for a URL via the 4-tier strategy.
  ///
  /// Returns [VideoPreview] populated with whatever metadata each tier
  /// could supply. Caller renders fallback UI when [VideoPreview.hasFetchedMetadata]
  /// is false AND [VideoPreview.thumbnailUrl] is null.
  Future<VideoPreview> fetchPreview(String url) async {
    final c = _urlPattern.classify(url);

    // Non-URL or unknown URL — minimal fallback, no fetch.
    if (c.urlType == UrlType.notUrl || c.urlType == UrlType.unknown) {
      return _buildFallbackPreview(c);
    }

    // Tier A — canonical thumbnail derivable from itemId
    final tierA = _tierAThumbnail(c);

    // Tier B — oEmbed (now includes Dailymotion + SoundCloud per v2.2)
    if (c.urlType == UrlType.video && _supportsOEmbed(c.platform)) {
      final fetched = await _fetchOEmbed(c);
      if (fetched != null) {
        // Prefer Tier A thumb when available (better resolution for YT/Vimeo)
        return tierA != null
            ? fetched.copyWith(thumbnailUrl: tierA)
            : fetched;
      }
    }

    // Tier A standalone (no oEmbed support OR oEmbed failed but ID known)
    if (tierA != null) {
      return _buildFallbackPreview(c).copyWith(thumbnailUrl: tierA);
    }

    // Tier C — OG image scrape (Tier-2 platforms with permissive bot policies)
    if (c.urlType == UrlType.video && _supportsOgImageScrape(c.platform)) {
      final og = await _fetchOgImage(c.rawUrl);
      if (og != null) {
        return _buildFallbackPreview(c).copyWith(thumbnailUrl: og);
      }
    }

    // Tier D — fallback (UI handles platform logo placeholder in Phase 2B).
    return _buildFallbackPreview(c);
  }

  /// Synchronous canonical thumbnail derivation. Returns null if the
  /// platform/itemId pair has no public CDN URL pattern.
  String? _tierAThumbnail(UrlClassification c) {
    if (c.itemId == null) return null;
    switch (c.platform) {
      case VideoPlatform.youtube:
        // maxresdefault.jpg may 404 for older / unlisted videos; UI image
        // widget falls back to hqdefault. Canonical preferred URL is
        // maxres for hi-DPI rendering.
        return 'https://img.youtube.com/vi/${c.itemId}/maxresdefault.jpg';
      case VideoPlatform.vimeo:
        // vumbnail.com is the community-maintained Vimeo thumbnail CDN.
        // Faster than oEmbed for thumb-only path.
        return 'https://vumbnail.com/${c.itemId}.jpg';
      default:
        return null;
    }
  }

  /// Tier-1 platforms that support public oEmbed (no auth token).
  ///
  /// v2.2 changes from v2.1:
  ///   - **Added**: Dailymotion, SoundCloud (both have public oEmbed
  ///     endpoints — em wrong v2.1 to xếp Tier-2)
  ///   - Instagram, Facebook, Pinterest, Threads, LinkedIn, Bilibili,
  ///     Douyin remain non-oEmbed (require app tokens or no public API).
  bool _supportsOEmbed(VideoPlatform platform) {
    switch (platform) {
      case VideoPlatform.youtube:
      case VideoPlatform.vimeo:
      case VideoPlatform.tiktok:
      case VideoPlatform.twitter:
      case VideoPlatform.reddit:
      case VideoPlatform.dailymotion: // v2.2 NEW
      case VideoPlatform.soundcloud:  // v2.2 NEW
        return true;
      case VideoPlatform.instagram:
      case VideoPlatform.facebook:
      case VideoPlatform.pinterest:
      case VideoPlatform.bilibili:
      case VideoPlatform.linkedin:
      case VideoPlatform.douyin:
      case VideoPlatform.threads:
      case VideoPlatform.unknown:
        return false;
    }
  }

  /// Whether to attempt Tier C OG image scraping. **Excludes Instagram and
  /// Facebook** — confirmed Cloudflare-blocked even with realistic browser
  /// UAs (ultra-review C4). Listing them would just add 5s timeout per
  /// capture without producing thumbnails.
  bool _supportsOgImageScrape(VideoPlatform platform) {
    switch (platform) {
      case VideoPlatform.threads:
      case VideoPlatform.pinterest:
      case VideoPlatform.linkedin:
      case VideoPlatform.bilibili:
        return true;
      default:
        return false;
    }
  }

  /// Fetch oEmbed JSON, parse response into [VideoPreview].
  ///
  /// Returns null on any failure (timeout/4xx/5xx/parse error). Caller
  /// degrades to next tier.
  Future<VideoPreview?> _fetchOEmbed(UrlClassification classification) async {
    String urlForOEmbed = classification.rawUrl;
    UrlClassification resolved = classification;

    // TikTok short URLs: resolve redirect first to canonical form.
    if (_isTikTokShortUrl(classification.rawUrl)) {
      final canonical = await _resolveTikTokShortUrl(classification.rawUrl);
      if (canonical == null) {
        appLogger.debug(
          '[oEmbed] TikTok short URL redirect resolution failed: ${classification.rawUrl}',
        );
        return null;
      }
      urlForOEmbed = canonical;
      final reclassified = _urlPattern.classify(canonical);
      resolved = UrlClassification(
        rawUrl: classification.rawUrl,
        platform: reclassified.platform,
        urlType: reclassified.urlType,
        itemId: reclassified.itemId,
        startTimestamp: reclassified.startTimestamp,
        playlistId: reclassified.playlistId,
      );
    }

    final endpoint = _oEmbedEndpointForUrl(resolved.platform, urlForOEmbed);
    if (endpoint == null) return null;

    try {
      final response = await _client.get(
        endpoint,
        headers: _apiHeaders(),
      ).timeout(_timeout);

      if (response.statusCode != 200) {
        appLogger.debug(
          '[oEmbed] ${resolved.platform.name} returned ${response.statusCode} for $urlForOEmbed',
        );
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return _parseOEmbedResponse(resolved, data);
    } on TimeoutException {
      appLogger.debug('[oEmbed] timeout fetching $urlForOEmbed');
      return null;
    } catch (e) {
      appLogger.debug('[oEmbed] error: $e');
      return null;
    }
  }

  /// Tier C: scrape `<meta property="og:image">` from the URL itself.
  ///
  /// Single GET with realistic browser UA, 5s timeout. Lightweight regex
  /// parse — pulling the `html` package would add 200KB+ to the bundle for
  /// one feature. Returns image URL or null on any failure.
  Future<String?> _fetchOgImage(String url) async {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'http' && uri.scheme != 'https') return null;

      final response = await _client
          .get(
            uri,
            headers: const {
              'User-Agent': _browserUserAgent,
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'Accept-Language': 'en-US,en;q=0.9',
            },
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        appLogger.debug(
          '[OgImage] $url returned ${response.statusCode}',
        );
        return null;
      }

      return _parseOgImageFromHtml(response.body);
    } on TimeoutException {
      appLogger.debug('[OgImage] timeout fetching $url');
      return null;
    } catch (e) {
      appLogger.debug('[OgImage] error: $e');
      return null;
    }
  }

  /// Extract `<meta property="og:image" content="...">` URL from HTML.
  ///
  /// Handles attribute order variations (property/content can be in either
  /// order) and quote types (single or double). Returns null if not found.
  /// Visible-for-testing public so unit tests can lock the parser shape.
  String? parseOgImageFromHtml(String html) => _parseOgImageFromHtml(html);

  String? _parseOgImageFromHtml(String html) {
    // Match <meta ... property="og:image" ... content="URL" ... >
    // OR    <meta ... content="URL" ... property="og:image" ... >
    // Tolerates single OR double quotes; case-insensitive on attributes.
    final patterns = [
      RegExp(
        r'''<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']''',
        caseSensitive: false,
      ),
      RegExp(
        r'''<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']''',
        caseSensitive: false,
      ),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(html);
      if (m != null) {
        final url = m.group(1);
        if (url != null && url.isNotEmpty) return url;
      }
    }
    return null;
  }

  /// Headers for documented JSON oEmbed endpoints — we identify honestly
  /// since these are public APIs.
  Map<String, String> _apiHeaders() => {
        'User-Agent': _apiUserAgent,
        'Accept': 'application/json',
      };

  bool _isTikTokShortUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('vm.tiktok.com') || lower.contains('vt.tiktok.com');
  }

  Future<String?> _resolveTikTokShortUrl(String shortUrl) async {
    try {
      final uri = Uri.parse(shortUrl);
      final request = http.Request('HEAD', uri)..followRedirects = false;
      request.headers.addAll(_apiHeaders());

      final streamedResponse = await _client.send(request).timeout(_timeout);
      const redirectStatuses = {301, 302, 303, 307, 308};
      if (redirectStatuses.contains(streamedResponse.statusCode)) {
        final location = streamedResponse.headers['location'];
        if (location != null && location.isNotEmpty) {
          final resolvedUri = Uri.parse(location);
          return resolvedUri.replace(queryParameters: {}).toString();
        }
      }
      return null;
    } on TimeoutException {
      return null;
    } catch (e) {
      appLogger.debug('[oEmbed] TikTok redirect resolve error: $e');
      return null;
    }
  }

  /// Build platform-specific oEmbed URL.
  Uri? _oEmbedEndpointForUrl(VideoPlatform platform, String url) {
    final encodedUrl = Uri.encodeQueryComponent(url);

    switch (platform) {
      case VideoPlatform.youtube:
        return Uri.parse(
          'https://www.youtube.com/oembed?url=$encodedUrl&format=json',
        );
      case VideoPlatform.vimeo:
        return Uri.parse(
          'https://vimeo.com/api/oembed.json?url=$encodedUrl',
        );
      case VideoPlatform.tiktok:
        return Uri.parse(
          'https://www.tiktok.com/oembed?url=$encodedUrl',
        );
      case VideoPlatform.twitter:
        return Uri.parse(
          'https://publish.twitter.com/oembed?url=$encodedUrl',
        );
      case VideoPlatform.reddit:
        return Uri.parse(
          'https://www.reddit.com/oembed?url=$encodedUrl',
        );
      case VideoPlatform.dailymotion: // v2.2
        return Uri.parse(
          'https://www.dailymotion.com/services/oembed?url=$encodedUrl',
        );
      case VideoPlatform.soundcloud: // v2.2
        return Uri.parse(
          'https://soundcloud.com/oembed?url=$encodedUrl&format=json',
        );
      default:
        return null;
    }
  }

  /// Parse oEmbed JSON into [VideoPreview].
  VideoPreview _parseOEmbedResponse(
    UrlClassification c,
    Map<String, dynamic> data,
  ) {
    final title = data['title'] as String?;
    final uploader = data['author_name'] as String?;
    var thumbnail = data['thumbnail_url'] as String?;

    // Tier A override for YouTube — maxres CDN URL is sharper than oEmbed default
    if (c.platform == VideoPlatform.youtube && c.itemId != null) {
      thumbnail = 'https://img.youtube.com/vi/${c.itemId}/maxresdefault.jpg';
    }

    return VideoPreview(
      rawUrl: c.rawUrl,
      platform: c.platform,
      urlType: c.urlType,
      itemId: c.itemId,
      title: title,
      uploader: uploader,
      thumbnailUrl: thumbnail,
      startTimestamp: c.startTimestamp,
      playlistId: c.playlistId,
      hasFetchedMetadata: title != null || uploader != null,
    );
  }

  VideoPreview _buildFallbackPreview(UrlClassification c) {
    // For YouTube fallback, hqdefault is more reliable than maxresdefault
    // (always exists, even for restricted videos).
    String? thumbnail;
    if (c.platform == VideoPlatform.youtube && c.itemId != null) {
      thumbnail = 'https://img.youtube.com/vi/${c.itemId}/hqdefault.jpg';
    }

    return VideoPreview(
      rawUrl: c.rawUrl,
      platform: c.platform,
      urlType: c.urlType,
      itemId: c.itemId,
      title: null,
      uploader: null,
      thumbnailUrl: thumbnail,
      startTimestamp: c.startTimestamp,
      playlistId: c.playlistId,
      hasFetchedMetadata: false,
    );
  }

  void dispose() {
    _client.close();
  }
}
