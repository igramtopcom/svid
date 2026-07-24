import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/platform_detector.dart';
import '../../domain/entities/intercepted_media.dart';
import '../../domain/entities/unified_media_item.dart';
import '../../domain/services/page_video_scanner_service.dart';
import 'browser_providers.dart';
import 'media_detector_provider.dart';

/// Current page URL in the browser — updated on navigation events.
/// The browser screen sets this whenever the URL changes.
final browserPageUrlProvider = StateProvider<String?>((ref) => null);

/// Unified media provider that merges DOM-scanned video links and
/// network-intercepted media into a single smart list.
///
/// Classification logic:
/// - DOM video links → [MediaItemType.videoPageLink] (yt-dlp extraction)
/// - HLS manifests → [MediaItemType.hlsManifest] (Rust HLS engine)
/// - Most CDN activity on known platforms → [MediaItemType.streamingSignal] (yt-dlp)
/// - Facebook CDN video/audio → [MediaItemType.directMediaFile] (Rust fallback)
/// - Direct media files on unknown sites → [MediaItemType.directMediaFile] (Rust)
/// - DASH/segments/tiny fragments → filtered out
final unifiedMediaProvider = Provider<List<UnifiedMediaItem>>((ref) {
  final domVideos = ref.watch(browserDetectedVideosProvider);
  final interceptedMedia = ref.watch(interceptedMediaProvider);
  final currentPageUrl = ref.watch(browserPageUrlProvider);

  return _mergeAndClassify(
    domVideos: domVideos,
    interceptedMedia: interceptedMedia,
    currentPageUrl: currentPageUrl,
  );
});

/// Number of downloadable items in the unified list.
final unifiedDownloadableCountProvider = Provider<int>((ref) {
  final items = ref.watch(unifiedMediaProvider);
  return items.where((item) => item.isDownloadable).length;
});

// ── Classification Logic ──

List<UnifiedMediaItem> _mergeAndClassify({
  required List<DetectedVideoLink> domVideos,
  required List<InterceptedMedia> interceptedMedia,
  required String? currentPageUrl,
}) {
  final results = <UnifiedMediaItem>[];
  final seenKeys = <String>{};

  final currentPlatform =
      currentPageUrl != null
          ? PlatformDetector.detectPlatform(currentPageUrl)
          : VideoPlatform.unknown;

  // 1. DOM-scanned video links take priority — these have page URLs that work
  //    with yt-dlp and provide quality selection.
  //
  //    On feed pages (YouTube home, etc.), cap at 6 items to avoid noisy lists.
  final isFeedPage = currentPageUrl != null && _isFeedUrl(currentPageUrl);
  var domCount = 0;
  for (final video in domVideos) {
    if (isFeedPage && domCount >= 6) break;
    final key = 'page:${video.url}';
    if (seenKeys.contains(key)) continue;
    seenKeys.add(key);

    // Clean title: if it looks like a hash/video ID, extract from URL instead
    var title = video.title;
    if (title.isEmpty || _isCdnHash(title)) {
      title = _titleFromUrl(video.url);
      // If _titleFromUrl gives generic path like "watch", use domain + index
      if (title == 'watch' ||
          title == 'shorts' ||
          title == 'reel' ||
          title == 'video' ||
          title == 'p') {
        final domain = _extractDomain(video.url);
        title = '$domain video ${domCount + 1}';
      }
    }

    results.add(
      UnifiedMediaItem(
        displayUrl: video.url,
        pageUrl: video.url,
        type: MediaItemType.videoPageLink,
        title: title,
        platform: video.platform,
        domain: _extractDomain(video.url),
        detectedAt: DateTime.now(),
        source: MediaItemSource.dom,
      ),
    );
    // Register this video's title so a later network manifest for the same
    // video doesn't add a duplicate row.
    final domTitleKey = _titleKey(title, _extractDomain(video.url));
    if (domTitleKey != null) seenKeys.add(domTitleKey);
    domCount++;
  }

  // Track which platforms already have DOM links — network signals for the
  // same platform are redundant.
  final domPlatforms = <VideoPlatform>{};
  for (final video in domVideos) {
    domPlatforms.add(video.platform);
  }

  // 2. Network-intercepted media — classify based on type and context.
  for (final media in interceptedMedia) {
    // Skip segments (too noisy, not independently downloadable)
    if (media.category == MediaCategory.streamSegment) continue;

    final item = _classifyInterceptedMedia(
      media,
      currentPageUrl,
      currentPlatform,
      domPlatforms,
    );

    // Skip undownloadable items entirely
    if (item == null || item.type == MediaItemType.undownloadable) continue;

    // Collapse every rendition/CDN variant of the SAME video into one row. A
    // single video exposes a master playlist plus per-quality and token-varied
    // manifests (all different URLs) that otherwise show as many identical
    // "Download" rows. The human title is the most reliable "same video" signal,
    // so group by it; fall back to the HLS directory or the URL when there is no
    // meaningful title.
    final key = _titleKey(item.title, item.domain) ??
        (item.type == MediaItemType.hlsManifest
            ? _hlsGroupKey(item.displayUrl)
            : item.deduplicationKey);
    if (seenKeys.contains(key)) continue;
    seenKeys.add(key);

    results.add(item);
  }

  // Sort: videoPageLink first, then directMediaFile, hlsManifest, streamingSignal
  results.sort((a, b) => a.type.index.compareTo(b.type.index));

  return results;
}

UnifiedMediaItem? _classifyInterceptedMedia(
  InterceptedMedia media,
  String? currentPageUrl,
  VideoPlatform currentPlatform,
  Set<VideoPlatform> domPlatforms,
) {
  // HLS manifest → always downloadable via Rust HLS engine
  if (media.category == MediaCategory.hlsStream) {
    return UnifiedMediaItem(
      displayUrl: media.url,
      downloadUrl: media.url,
      type: MediaItemType.hlsManifest,
      title: _smartTitle(media),
      filename: media.filename,
      domain: media.domain,
      estimatedSize: media.estimatedSize,
      contentType: media.contentType,
      detectedAt: media.detectedAt,
      source: MediaItemSource.network,
      supportsRange: media.supportsRange,
      originalCategory: media.category,
    );
  }

  // DASH manifest → undownloadable (needs full DASH parser, not supported)
  if (media.category == MediaCategory.dashStream) {
    return null;
  }

  // Belt-and-suspenders: never surface a raw HLS/DASH segment as a standalone
  // download (a single .ts/.m4s is unplayable, e.g. seg-1-v1-a1.ts). classifyUrl
  // tags most of these as segments, but extensionless CDN segments can slip
  // through — the .m3u8 manifest above is the real, assemblable item.
  if (_looksLikeStreamSegment(media.url)) return null;

  // Known platform CDN activity → streaming signal (route to yt-dlp)
  if (currentPlatform != VideoPlatform.unknown) {
    if (_isFacebookDirectCdnMedia(media, currentPlatform)) {
      return UnifiedMediaItem(
        displayUrl: media.url,
        downloadUrl: media.url,
        type: MediaItemType.directMediaFile,
        title: _smartTitle(media, fallbackUrl: currentPageUrl),
        platform: currentPlatform,
        filename: media.filename,
        domain: media.domain,
        estimatedSize: media.estimatedSize,
        contentType: media.contentType,
        detectedAt: media.detectedAt,
        source: MediaItemSource.network,
        supportsRange: media.supportsRange,
        originalCategory: media.category,
      );
    }

    // If DOM already found links for this platform, skip the network signal
    // (DOM links are more reliable — they have the specific video page URL)
    if (domPlatforms.contains(currentPlatform)) return null;

    // Don't create streamingSignal for feed/explore/home pages — the page URL
    // isn't a specific video and yt-dlp can't extract from feeds.
    if (currentPageUrl != null && _isFeedUrl(currentPageUrl)) return null;

    return UnifiedMediaItem(
      displayUrl: media.url,
      pageUrl: currentPageUrl,
      type: MediaItemType.streamingSignal,
      title: _smartTitle(media, fallbackUrl: currentPageUrl),
      platform: currentPlatform,
      domain: media.domain,
      estimatedSize: media.estimatedSize,
      contentType: media.contentType,
      detectedAt: media.detectedAt,
      source: MediaItemSource.network,
      originalCategory: media.category,
    );
  }

  // Unknown platform: check if it's a real downloadable file
  // Skip tiny items (< 100KB) — likely DASH init segments or tracking pixels
  final size = media.estimatedSize;
  if (size != null && size > 0 && size < 102400) {
    return null;
  }

  // Direct media file (video/audio with no known platform → Rust engine)
  if (media.category == MediaCategory.video ||
      media.category == MediaCategory.audio ||
      media.category == MediaCategory.unknown) {
    return UnifiedMediaItem(
      displayUrl: media.url,
      downloadUrl: media.url,
      type: MediaItemType.directMediaFile,
      title: _smartTitle(media),
      filename: media.filename,
      domain: media.domain,
      estimatedSize: media.estimatedSize,
      contentType: media.contentType,
      detectedAt: media.detectedAt,
      source: MediaItemSource.network,
      supportsRange: media.supportsRange,
      originalCategory: media.category,
    );
  }

  return null;
}

bool _isFacebookDirectCdnMedia(
  InterceptedMedia media,
  VideoPlatform currentPlatform,
) {
  if (currentPlatform != VideoPlatform.facebook) return false;
  final host = media.domain.toLowerCase();
  if (!host.endsWith('fbcdn.net') && !host.endsWith('fbsbx.com')) {
    return false;
  }
  return media.category == MediaCategory.video ||
      media.category == MediaCategory.audio ||
      media.category == MediaCategory.unknown;
}

/// Whether the current browser page is a feed/explore/home page on a known
/// platform (where streaming signals are noise, not specific videos).
final isBrowserOnFeedProvider = Provider<bool>((ref) {
  final url = ref.watch(browserPageUrlProvider);
  if (url == null) return false;
  final platform = PlatformDetector.detectPlatform(url);
  if (platform == VideoPlatform.unknown) return false;
  return _isFeedUrl(url);
});

// ── Helpers ──

/// Feed/explore/home/profile-root patterns that can't be extracted by yt-dlp.
bool _isFeedUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  final path = uri.path;

  // Exact feed paths
  const feedPaths = {
    '/',
    '',
    '/explore',
    '/explore/',
    '/reels',
    '/reels/',
    '/feed',
    '/feed/',
    '/home',
    '/home/',
    '/foryou',
    '/foryou/',
    '/following',
    '/following/',
    '/discover',
    '/discover/',
  };
  if (feedPaths.contains(path)) return true;

  // Profile root pages: /username/ or /@username/
  // But NOT /p/XXX/, /reel/XXX/, /video/XXX/, etc.
  final isProfileRoot =
      RegExp(r'^/@?[^/]+/?$').hasMatch(path) &&
      !RegExp(
        r'^/(p|reel|tv|watch|shorts|video|status|comments)/',
      ).hasMatch(path);
  if (isProfileRoot) return true;

  return false;
}

/// Whether a URL points at an individual HLS/DASH stream segment (not a full,
/// independently playable file). Matches `.ts`/`.m4s` files and the common
/// seg-/segment/chunk/frag naming, so a single segment is never offered as a
/// standalone download.
/// Grouping key derived from a human title, or null when the title is missing,
/// too short, or just the domain (which would over-collapse unrelated media).
/// Lets every rendition/CDN variant of one video collapse to a single row.
String? _titleKey(String? title, String domain) {
  final t = title?.trim() ?? '';
  if (t.length <= 3) return null;
  if (t.toLowerCase() == domain.toLowerCase()) return null;
  return 'title:${t.toLowerCase()}';
}

/// Grouping key for HLS manifests: host + the directory holding the manifest
/// (filename and query dropped). master.m3u8, 720p.m3u8, audio.m3u8 and
/// token-varied copies under the same folder collapse to one video.
String _hlsGroupKey(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return 'hls:$url';
  final segs = uri.pathSegments;
  final dir =
      segs.length > 1 ? segs.sublist(0, segs.length - 1).join('/') : '';
  return 'hls:${uri.host}/$dir';
}

bool _looksLikeStreamSegment(String url) {
  final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
  if (path.endsWith('.ts') || path.endsWith('.m4s')) return true;
  return RegExp(r'[/_-](seg|segment|chunk|frag)[-_]?\d').hasMatch(path);
}

String _extractDomain(String url) {
  try {
    return Uri.parse(url).host;
  } catch (_) {
    return '';
  }
}

/// Smart title extraction using page context from JS interception.
///
/// Priority: page title → clean filename → URL path → domain.
/// Page title is the most human-readable since it comes from `document.title`.
String _smartTitle(InterceptedMedia media, {String? fallbackUrl}) {
  // 1. Page title from document.title at interception time
  if (media.pageTitle != null && media.pageTitle!.isNotEmpty) {
    var title = media.pageTitle!;
    // Skip generic single-word platform names (e.g. "YouTube", "Instagram")
    final isGenericPlatformName = RegExp(
      r'^(YouTube|Instagram|TikTok|Facebook|X|Twitter|Reddit|Vimeo|Pinterest|Dailymotion|SoundCloud|Bilibili|Google)$',
      caseSensitive: false,
    ).hasMatch(title.trim());
    if (!isGenericPlatformName) {
      // Clean common suffixes: " - YouTube", " | Instagram", " on X"
      title =
          title
              .replaceFirst(
                RegExp(
                  r'\s*[-–|•]\s*(YouTube|Instagram|TikTok|Facebook|X|Twitter|Reddit|Vimeo|Pinterest|Dailymotion|SoundCloud|Bilibili)\s*$',
                  caseSensitive: false,
                ),
                '',
              )
              .replaceFirst(
                RegExp(r'\s+on\s+(X|Twitter)\s*$', caseSensitive: false),
                '',
              )
              .trim();
      if (title.isNotEmpty && title.length > 2) return title;
    }
  }

  // 2. Clean filename if it looks human-readable (not a hash/ID)
  if (media.filename != null) {
    final name = media.filename!;
    // Skip CDN hashes and platform video IDs
    if (!_isCdnHash(name)) {
      // Strip extension for display
      final dotIdx = name.lastIndexOf('.');
      final display = dotIdx > 0 ? name.substring(0, dotIdx) : name;
      final cleaned = display.replaceAll(RegExp(r'[_-]+'), ' ').trim();
      if (cleaned.isNotEmpty && cleaned.length > 2) return cleaned;
    }
  }

  // 3. Try to extract from fallback URL
  if (fallbackUrl != null) {
    final fromUrl = _titleFromUrl(fallbackUrl);
    if (fromUrl.isNotEmpty && !_isCdnHash(fromUrl)) return fromUrl;
  }

  // 4. Domain as last resort
  return media.domain;
}

/// Whether a filename/string looks like a CDN hash or platform video ID
/// (not human-readable).
bool _isCdnHash(String name) {
  // Strip extension first
  final dotIdx = name.lastIndexOf('.');
  final base = dotIdx > 0 ? name.substring(0, dotIdx) : name;
  if (base.length < 6) return false;

  // Pure alphanumeric (no spaces, hyphens, underscores) = likely video ID or hash
  // YouTube IDs are 11 chars, Vimeo ~8-9 digits, etc.
  if (RegExp(r'^[A-Za-z0-9]+$').hasMatch(base) && base.length <= 20) {
    // Short mixed-case alphanumeric = platform video ID
    if (RegExp(r'[A-Z]').hasMatch(base) && RegExp(r'[a-z]').hasMatch(base)) {
      return true;
    }
    // Pure digits = likely numeric ID (Vimeo, etc.)
    if (RegExp(r'^\d+$').hasMatch(base)) return true;
  }

  // All alphanumeric/underscore without spaces = likely CDN hash
  if (RegExp(r'^[A-Za-z0-9_=]+$').hasMatch(base) && base.length > 16) {
    return true;
  }
  // Contains no vowels or spaces = likely hash
  if (!RegExp(r'[aeiouAEIOU\s-]').hasMatch(base) && base.length > 10) {
    return true;
  }
  return false;
}

String _titleFromUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  final path = uri.path;
  if (path.isEmpty || path == '/') return uri.host;
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return uri.host;
  final last = Uri.decodeComponent(segments.last);
  // Don't return CDN hashes
  if (_isCdnHash(last)) {
    // Try the second-to-last segment
    if (segments.length > 1) {
      final prev = Uri.decodeComponent(segments[segments.length - 2]);
      if (!_isCdnHash(prev)) return prev;
    }
    return uri.host;
  }
  return last;
}
