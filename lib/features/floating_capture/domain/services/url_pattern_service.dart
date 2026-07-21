import '../../../../core/utils/platform_detector.dart';
import '../../../downloads/domain/entities/video_preview.dart';

/// Classifies URLs into [UrlType] and extracts platform-specific identifiers.
///
/// Pure URL parsing — no network calls. Used by [CaptureService] to decide
/// whether a clipboard URL is a single video (eligible for preview popup),
/// playlist/channel (route to main app sheet), search keyword, or non-URL.
///
/// Per spec v2.1 §3.4 (capture-to-download flow) and §11 edge cases E16-E20:
/// - E16: non-URL text → returns [UrlType.notUrl]
/// - E18: very long URLs accepted (no truncation here; display layer handles)
/// - E19: URL with fragment `#t=120s` preserved in [UrlClassification.rawUrl];
///   fragment timestamp parsed alongside `?t=` param
class UrlPatternService {
  const UrlPatternService();

  /// Classify a string as a URL of specific type or non-URL keyword.
  ///
  /// Examples:
  /// - `https://youtube.com/watch?v=abc12345678` → video, YouTube, id=abc12345678
  /// - `https://youtube.com/@MrBeast` → channel, YouTube
  /// - `MrBeast latest` → notUrl (search keyword)
  UrlClassification classify(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return UrlClassification.notUrl(trimmed);

    // Quick check: must start with http(s):// or be a known short pattern
    if (!_looksLikeUrl(trimmed)) {
      return UrlClassification.notUrl(trimmed);
    }

    // Parse Uri — invalid URI → notUrl fallback
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.scheme.isEmpty) {
      return UrlClassification.notUrl(trimmed);
    }

    final platform = PlatformDetector.detectPlatform(trimmed);

    // Per-platform classification
    switch (platform) {
      case VideoPlatform.youtube:
        return _classifyYouTube(trimmed, uri);
      case VideoPlatform.tiktok:
        return _classifyTikTok(trimmed, uri);
      case VideoPlatform.vimeo:
        return _classifyVimeo(trimmed, uri);
      case VideoPlatform.twitter:
        return _classifyTwitter(trimmed, uri);
      case VideoPlatform.reddit:
        return _classifyReddit(trimmed, uri);
      case VideoPlatform.instagram:
      case VideoPlatform.facebook:
      case VideoPlatform.pinterest:
      case VideoPlatform.dailymotion:
      case VideoPlatform.soundcloud:
      case VideoPlatform.bilibili:
      case VideoPlatform.linkedin:
      case VideoPlatform.douyin:
      case VideoPlatform.threads:
        // Tier-2 platforms: assume video URL when on supported platform.
        // Channel/playlist detection deferred to main app's full extraction.
        return UrlClassification(
          rawUrl: trimmed,
          platform: platform,
          urlType: UrlType.video,
          itemId: null,
          startTimestamp: _parseTimestamp(uri),
        );
      case VideoPlatform.unknown:
        // HTTP(S) URL on unsupported platform → unknown (per §4.1 routes
        // to "Mở trình duyệt" CTA in smart input, but for floating capture
        // we treat this as not-eligible).
        return UrlClassification(
          rawUrl: trimmed,
          platform: VideoPlatform.unknown,
          urlType: UrlType.unknown,
          itemId: null,
        );
    }
  }

  /// Whether the input looks like a URL worth parsing.
  bool _looksLikeUrl(String input) {
    final lower = input.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  /// YouTube URL classification.
  ///
  /// Patterns:
  /// - youtube.com/watch?v=ID (video)
  /// - youtu.be/ID (video, short)
  /// - youtube.com/shorts/ID (video, vertical)
  /// - youtube.com/embed/ID (video, embed)
  /// - youtube.com/live/ID (live)
  /// - youtube.com/playlist?list=ID (playlist)
  /// - youtube.com/@channelname or youtube.com/c/name or youtube.com/channel/UCxxx (channel)
  /// - youtube.com/results?search_query=... (search)
  UrlClassification _classifyYouTube(String url, Uri uri) {
    final path = uri.path;
    final queryParams = uri.queryParameters;
    final timestamp = _parseTimestamp(uri);

    // Live URL: /live/VIDEO_ID
    final liveMatch = RegExp(r'^/live/([a-zA-Z0-9_-]{11})').firstMatch(path);
    if (liveMatch != null) {
      return UrlClassification(
        rawUrl: url,
        platform: VideoPlatform.youtube,
        urlType: UrlType.live,
        itemId: liveMatch.group(1),
        startTimestamp: timestamp,
      );
    }

    // Search URL: /results?search_query=...
    if (path == '/results' && queryParams.containsKey('search_query')) {
      return UrlClassification(
        rawUrl: url,
        platform: VideoPlatform.youtube,
        urlType: UrlType.search,
        itemId: null,
      );
    }

    // Playlist URL: /playlist?list=ID (no video ID present)
    if (path == '/playlist' && queryParams.containsKey('list')) {
      return UrlClassification(
        rawUrl: url,
        platform: VideoPlatform.youtube,
        urlType: UrlType.playlist,
        itemId: queryParams['list'],
        playlistId: queryParams['list'],
      );
    }

    // Channel patterns: /@handle, /c/name, /channel/UCxxx, /user/name
    if (path.startsWith('/@') ||
        path.startsWith('/c/') ||
        path.startsWith('/channel/') ||
        path.startsWith('/user/')) {
      return UrlClassification(
        rawUrl: url,
        platform: VideoPlatform.youtube,
        urlType: UrlType.channel,
        itemId: null,
      );
    }

    // Video patterns
    final videoId = _extractYouTubeVideoId(url);
    if (videoId != null) {
      return UrlClassification(
        rawUrl: url,
        platform: VideoPlatform.youtube,
        urlType: UrlType.video,
        itemId: videoId,
        startTimestamp: timestamp,
        playlistId: queryParams['list'], // video can be in playlist context
      );
    }

    // YouTube domain but no recognizable pattern (community post, music, etc.)
    return UrlClassification(
      rawUrl: url,
      platform: VideoPlatform.youtube,
      urlType: UrlType.unknown,
      itemId: null,
    );
  }

  /// TikTok URL classification.
  ///
  /// Patterns:
  /// - tiktok.com/@user/video/ID (video)
  /// - vm.tiktok.com/SHORT (short, needs redirect resolve at fetch time)
  /// - tiktok.com/@user (channel)
  UrlClassification _classifyTikTok(String url, Uri uri) {
    final path = uri.path;

    // Short URL — defer resolution to fetch time
    if (uri.host.contains('vm.tiktok.com') || uri.host.contains('vt.tiktok.com')) {
      return UrlClassification(
        rawUrl: url,
        platform: VideoPlatform.tiktok,
        urlType: UrlType.video, // assume video; resolved at fetch
        itemId: null,
      );
    }

    // Video URL: /@user/video/ID
    final videoMatch = RegExp(r'^/@[\w.-]+/video/(\d+)').firstMatch(path);
    if (videoMatch != null) {
      return UrlClassification(
        rawUrl: url,
        platform: VideoPlatform.tiktok,
        urlType: UrlType.video,
        itemId: videoMatch.group(1),
      );
    }

    // Channel URL: /@user
    if (RegExp(r'^/@[\w.-]+/?$').hasMatch(path)) {
      return UrlClassification(
        rawUrl: url,
        platform: VideoPlatform.tiktok,
        urlType: UrlType.channel,
        itemId: null,
      );
    }

    return UrlClassification(
      rawUrl: url,
      platform: VideoPlatform.tiktok,
      urlType: UrlType.unknown,
      itemId: null,
    );
  }

  /// Vimeo URL classification.
  ///
  /// Patterns:
  /// - vimeo.com/123456789 (video)
  /// - vimeo.com/user12345 (channel/user)
  /// - vimeo.com/channels/staffpicks (curated channel)
  UrlClassification _classifyVimeo(String url, Uri uri) {
    final path = uri.path;

    // Channel: /channels/name
    if (path.startsWith('/channels/')) {
      return UrlClassification(
        rawUrl: url,
        platform: VideoPlatform.vimeo,
        urlType: UrlType.channel,
        itemId: null,
      );
    }

    // User profile: /user12345 (numeric prefix "user")
    if (RegExp(r'^/user\d+/?$').hasMatch(path)) {
      return UrlClassification(
        rawUrl: url,
        platform: VideoPlatform.vimeo,
        urlType: UrlType.channel,
        itemId: null,
      );
    }

    // Video: /123456789 (numeric ID)
    final videoMatch = RegExp(r'^/(\d+)/?$').firstMatch(path);
    if (videoMatch != null) {
      return UrlClassification(
        rawUrl: url,
        platform: VideoPlatform.vimeo,
        urlType: UrlType.video,
        itemId: videoMatch.group(1),
        startTimestamp: _parseTimestamp(uri),
      );
    }

    return UrlClassification(
      rawUrl: url,
      platform: VideoPlatform.vimeo,
      urlType: UrlType.unknown,
      itemId: null,
    );
  }

  /// Twitter/X URL classification.
  ///
  /// Patterns:
  /// - twitter.com/user/status/ID or x.com/user/status/ID (single tweet, may have video)
  /// - twitter.com/user (profile / channel-like)
  UrlClassification _classifyTwitter(String url, Uri uri) {
    final path = uri.path;

    // Status: /user/status/ID
    final statusMatch = RegExp(r'^/[\w]+/status/(\d+)').firstMatch(path);
    if (statusMatch != null) {
      return UrlClassification(
        rawUrl: url,
        platform: VideoPlatform.twitter,
        urlType: UrlType.video, // tweet may have video; oEmbed will tell
        itemId: statusMatch.group(1),
      );
    }

    // User profile
    if (RegExp(r'^/[\w]+/?$').hasMatch(path)) {
      return UrlClassification(
        rawUrl: url,
        platform: VideoPlatform.twitter,
        urlType: UrlType.channel,
        itemId: null,
      );
    }

    return UrlClassification(
      rawUrl: url,
      platform: VideoPlatform.twitter,
      urlType: UrlType.unknown,
      itemId: null,
    );
  }

  /// Reddit URL classification.
  ///
  /// Patterns:
  /// - reddit.com/r/sub/comments/ID/title (post, may have video)
  /// - reddit.com/r/sub (subreddit, channel-like)
  UrlClassification _classifyReddit(String url, Uri uri) {
    final path = uri.path;

    // Post: /r/sub/comments/ID/...
    final postMatch =
        RegExp(r'^/r/[\w]+/comments/([a-z0-9]+)').firstMatch(path);
    if (postMatch != null) {
      return UrlClassification(
        rawUrl: url,
        platform: VideoPlatform.reddit,
        urlType: UrlType.video, // post may have video; oEmbed will tell
        itemId: postMatch.group(1),
      );
    }

    // Subreddit
    if (RegExp(r'^/r/[\w]+/?').hasMatch(path)) {
      return UrlClassification(
        rawUrl: url,
        platform: VideoPlatform.reddit,
        urlType: UrlType.channel,
        itemId: null,
      );
    }

    return UrlClassification(
      rawUrl: url,
      platform: VideoPlatform.reddit,
      urlType: UrlType.unknown,
      itemId: null,
    );
  }

  /// Extract YouTube video ID from any supported pattern.
  ///
  /// Returns 11-character video ID, or null if no match.
  /// Patterns: /watch?v=ID, /youtu.be/ID, /shorts/ID, /embed/ID, /live/ID
  String? _extractYouTubeVideoId(String url) {
    // Pattern 1: /watch?v=ID
    final watch = RegExp(r'[?&]v=([a-zA-Z0-9_-]{11})').firstMatch(url);
    if (watch != null) return watch.group(1);

    // Pattern 2: youtu.be/ID
    final shortPat = RegExp(r'youtu\.be/([a-zA-Z0-9_-]{11})').firstMatch(url);
    if (shortPat != null) return shortPat.group(1);

    // Pattern 3: /shorts/ID
    final shorts = RegExp(r'/shorts/([a-zA-Z0-9_-]{11})').firstMatch(url);
    if (shorts != null) return shorts.group(1);

    // Pattern 4: /embed/ID
    final embed = RegExp(r'/embed/([a-zA-Z0-9_-]{11})').firstMatch(url);
    if (embed != null) return embed.group(1);

    // Pattern 5: /live/ID (also handled in _classifyYouTube but include here
    // for callers using extractYouTubeId directly)
    final live = RegExp(r'/live/([a-zA-Z0-9_-]{11})').firstMatch(url);
    if (live != null) return live.group(1);

    return null;
  }

  /// Parse timestamp from URL query params or fragment.
  ///
  /// Examples:
  /// - `?t=120s` → 120 seconds
  /// - `?t=2m30s` → 150 seconds
  /// - `?t=1h2m3s` → 3723 seconds
  /// - `?start=60` → 60 seconds
  /// - `#t=45` → 45 seconds (per E19)
  ///
  /// Returns null if no timestamp param present.
  Duration? _parseTimestamp(Uri uri) {
    // Try query params first
    final queryT = uri.queryParameters['t'] ??
        uri.queryParameters['start'] ??
        uri.queryParameters['time_continue'];
    if (queryT != null) {
      final dur = _parseTimeString(queryT);
      if (dur != null) return dur;
    }

    // Fragment: #t=Ns or #t=NmNs etc.
    final fragment = uri.fragment;
    if (fragment.isNotEmpty) {
      final match = RegExp(r't=([\dhms]+)').firstMatch(fragment);
      if (match != null) {
        final dur = _parseTimeString(match.group(1)!);
        if (dur != null) return dur;
      }
    }

    return null;
  }

  /// Parse time string like "2m30s", "1h2m3s", "120s", or "120" (raw seconds).
  Duration? _parseTimeString(String input) {
    if (input.isEmpty) return null;

    // Pure numeric → seconds
    final pureSeconds = int.tryParse(input);
    if (pureSeconds != null) {
      return Duration(seconds: pureSeconds);
    }

    // Composite like "1h2m3s" or "2m30s"
    final regex = RegExp(r'(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?');
    final match = regex.firstMatch(input);
    if (match == null) return null;

    final h = int.tryParse(match.group(1) ?? '0') ?? 0;
    final m = int.tryParse(match.group(2) ?? '0') ?? 0;
    final s = int.tryParse(match.group(3) ?? '0') ?? 0;

    if (h == 0 && m == 0 && s == 0) return null;

    return Duration(hours: h, minutes: m, seconds: s);
  }
}

/// Output of [UrlPatternService.classify].
///
/// Either represents a parsed URL (with platform + type) or a non-URL
/// keyword. Caller routes based on [urlType].
class UrlClassification {
  /// Original URL string passed to [UrlPatternService.classify].
  /// For non-URL inputs, contains the trimmed input text.
  final String rawUrl;

  /// Detected platform. [VideoPlatform.unknown] when input is not a URL or
  /// not on a recognized platform.
  final VideoPlatform platform;

  /// Type of URL — drives routing decisions in capture flow.
  final UrlType urlType;

  /// Platform-specific item identifier (video ID, post ID, etc.). Null for
  /// non-item URL types (channel, search, etc.).
  final String? itemId;

  /// Start timestamp parsed from `?t=` query param or `#t=` fragment.
  /// Null if URL has no timestamp marker.
  final Duration? startTimestamp;

  /// Playlist ID parsed from `&list=` query param. Present when video URL
  /// has playlist context (YouTube only currently).
  final String? playlistId;

  const UrlClassification({
    required this.rawUrl,
    required this.platform,
    required this.urlType,
    this.itemId,
    this.startTimestamp,
    this.playlistId,
  });

  /// Convenience constructor for non-URL inputs (search keywords).
  factory UrlClassification.notUrl(String input) => UrlClassification(
        rawUrl: input,
        platform: VideoPlatform.unknown,
        urlType: UrlType.notUrl,
        itemId: null,
      );

  /// Whether this URL is eligible for floating capture popup display
  /// (single video item with extractable metadata).
  bool get isPreviewable => urlType == UrlType.video;

  /// Whether this URL represents a known item type
  /// (video/playlist/channel/live/search) vs. a non-URL keyword or
  /// unknown URL. Codex audit P1 #6 fix: include `UrlType.search` so
  /// search URLs flow through ClipboardMonitorService → CaptureService
  /// and surface in the popup with an "Open in Svid" action (spec Q18).
  /// Previously they were silently dropped at the monitor layer.
  bool get isKnownUrlType =>
      urlType == UrlType.video ||
      urlType == UrlType.playlist ||
      urlType == UrlType.channel ||
      urlType == UrlType.live ||
      urlType == UrlType.search;

  @override
  String toString() =>
      'UrlClassification(${platform.name}/$urlType, id=$itemId, '
      'ts=$startTimestamp, playlist=$playlistId)';
}
