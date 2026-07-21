import '../l10n/app_localizations.dart';

/// Supported video platforms
enum VideoPlatform {
  youtube,
  tiktok,
  instagram,
  facebook,
  twitter,
  reddit,
  pinterest,
  vimeo,
  dailymotion,
  soundcloud,
  bilibili,
  linkedin,
  douyin,
  threads,
  unknown;

  /// Whether this platform requires YouTube conversion flow
  bool get requiresYouTubeConversion => this == VideoPlatform.youtube;

  /// Whether trying gallery-dl as a fallback makes sense for this platform.
  /// gallery-dl handles image/carousel posts (Instagram, Pinterest, Reddit,
  /// Twitter, Threads, Facebook, LinkedIn). Pure video/audio platforms
  /// always return exit 64 "Unsupported URL" — skip the round trip.
  bool get supportsGalleryDlFallback {
    switch (this) {
      case VideoPlatform.youtube:
      case VideoPlatform.vimeo:
      case VideoPlatform.dailymotion:
      case VideoPlatform.soundcloud:
      case VideoPlatform.bilibili:
      case VideoPlatform.tiktok:
      case VideoPlatform.douyin:
        return false;
      case VideoPlatform.instagram:
      case VideoPlatform.facebook:
      case VideoPlatform.twitter:
      case VideoPlatform.reddit:
      case VideoPlatform.pinterest:
      case VideoPlatform.linkedin:
      case VideoPlatform.threads:
      case VideoPlatform.unknown:
        return true;
    }
  }

  /// Display name for UI
  String get displayName {
    switch (this) {
      case VideoPlatform.youtube:
        return AppLocalizations.platformYoutube;
      case VideoPlatform.tiktok:
        return AppLocalizations.platformTiktok;
      case VideoPlatform.instagram:
        return AppLocalizations.platformInstagram;
      case VideoPlatform.facebook:
        return AppLocalizations.platformFacebook;
      case VideoPlatform.twitter:
        return AppLocalizations.platformTwitter;
      case VideoPlatform.reddit:
        return AppLocalizations.platformReddit;
      case VideoPlatform.pinterest:
        return AppLocalizations.platformPinterest;
      case VideoPlatform.vimeo:
        return AppLocalizations.platformVimeo;
      case VideoPlatform.dailymotion:
        return AppLocalizations.platformDailymotion;
      case VideoPlatform.soundcloud:
        return AppLocalizations.platformSoundcloud;
      case VideoPlatform.bilibili:
        return AppLocalizations.platformBilibili;
      case VideoPlatform.linkedin:
        return AppLocalizations.platformLinkedin;
      case VideoPlatform.douyin:
        return AppLocalizations.platformDouyin;
      case VideoPlatform.threads:
        return AppLocalizations.platformThreads;
      case VideoPlatform.unknown:
        return AppLocalizations.platformUnknown;
    }
  }

  /// Convert to database string
  String toDbString() {
    return name;
  }

  /// Convert from database string
  static VideoPlatform fromDbString(String value) {
    return VideoPlatform.values.firstWhere(
      (platform) => platform.name == value,
      orElse: () => VideoPlatform.unknown,
    );
  }
}

/// Result of `PlatformDetector.detectFacebookMediaType(url)` — used by
/// extraction dispatch to skip gallery-dl pre-warm for confirmed
/// Facebook VIDEO URLs (reel / watch / share/r/ / video/). Image and
/// ambiguous Facebook URLs still go through the parallel gallery-dl
/// fallback path because the platform legitimately hosts both video
/// and image carousel posts.
///
/// RC10.1 of Ultra Plan v3 — closes the noise + complicated recovery
/// caused by gallery-dl unconditionally attempting Facebook video
/// URLs and failing with "Unsupported URL".
enum FacebookMediaType { video, image, unknown }

class PlatformDetector {
  /// RC10.1 of Ultra Plan v3 — Facebook URL pattern classifier.
  ///
  /// Returns [FacebookMediaType.video] for confirmed video patterns
  /// so extraction dispatch can skip gallery-dl pre-warm (gallery-dl
  /// is an IMAGE/gallery downloader; attempting it on a Facebook reel
  /// produces an unsupported-URL error that adds latency + log noise).
  ///
  /// Returns [FacebookMediaType.image] for confirmed image/album
  /// patterns so the parallel path still runs (gallery-dl is the
  /// correct engine for image carousel posts).
  ///
  /// Returns [FacebookMediaType.unknown] for ambiguous URLs (the
  /// caller should default to the parallel path to remain safe —
  /// yt-dlp + gallery-dl race resolves correctness via whichever
  /// extractor handles the URL).
  ///
  /// Patterns sourced from yt-dlp's Facebook extractor +
  /// `_VALID_URL` regex (yt-dlp version 2024+).
  static FacebookMediaType detectFacebookMediaType(String url) {
    final lower = url.toLowerCase();
    // Video patterns — yt-dlp's Facebook extractor handles these.
    // Reel short-links like /share/r/<id>/ are the canonical reel
    // shape (Wilson-class incident URL pattern). Watch + video +
    // reel + fb.watch are explicit video shapes.
    if (lower.contains('/watch') ||
        lower.contains('/reel/') ||
        // /share/r/ = reel-share, /share/v/ = video-share. Both
        // explicit-video shapes (Codex-round-2 catch 8).
        RegExp(r'/share/[rv]/').hasMatch(lower) ||
        // /video/ AND /videos/ (page video index) both match
        RegExp(r'/videos?/').hasMatch(lower) ||
        lower.contains('fb.watch/')) {
      return FacebookMediaType.video;
    }
    // Image patterns — gallery-dl handles these (carousel posts,
    // single-photo URLs, album media sets).
    if (lower.contains('/photo/') ||
        lower.contains('/photo.php') ||
        lower.contains('/media/set/') ||
        lower.contains('/albums/')) {
      return FacebookMediaType.image;
    }
    // Posts (/posts/<id>) can be either text-only, image, or video
    // — gallery-dl + yt-dlp race resolves; treat as unknown so the
    // parallel path stays.
    return FacebookMediaType.unknown;
  }

  /// Detect platform from URL
  static VideoPlatform detectPlatform(String url) {
    final lowerUrl = url.toLowerCase();

    // YouTube
    if (lowerUrl.contains('youtube.com') ||
        lowerUrl.contains('youtu.be') ||
        lowerUrl.contains('m.youtube.com')) {
      return VideoPlatform.youtube;
    }

    // TikTok
    if (lowerUrl.contains('tiktok.com') || lowerUrl.contains('vt.tiktok.com')) {
      return VideoPlatform.tiktok;
    }

    // Instagram
    if (lowerUrl.contains('instagram.com') || lowerUrl.contains('instagr.am')) {
      return VideoPlatform.instagram;
    }

    // Facebook
    if (lowerUrl.contains('facebook.com') ||
        lowerUrl.contains('fb.com') ||
        lowerUrl.contains('fb.watch')) {
      return VideoPlatform.facebook;
    }

    // Twitter/X
    // Note: t.co check uses regex to avoid false positives (reddit.com, pinterest.com contain "t.co")
    if (lowerUrl.contains('twitter.com') ||
        lowerUrl.contains('x.com') ||
        RegExp(r'(^|[./])t\.co(/|$)').hasMatch(lowerUrl)) {
      return VideoPlatform.twitter;
    }

    // Reddit
    if (lowerUrl.contains('reddit.com') || lowerUrl.contains('redd.it')) {
      return VideoPlatform.reddit;
    }

    // Pinterest
    if (lowerUrl.contains('pinterest.com') || lowerUrl.contains('pin.it')) {
      return VideoPlatform.pinterest;
    }

    // Vimeo
    if (lowerUrl.contains('vimeo.com')) {
      return VideoPlatform.vimeo;
    }

    // Dailymotion
    if (lowerUrl.contains('dailymotion.com') || lowerUrl.contains('dai.ly')) {
      return VideoPlatform.dailymotion;
    }

    // SoundCloud
    if (lowerUrl.contains('soundcloud.com')) {
      return VideoPlatform.soundcloud;
    }

    // Bilibili
    if (lowerUrl.contains('bilibili.com') ||
        lowerUrl.contains('bilibili.tv') ||
        lowerUrl.contains('b23.tv')) {
      return VideoPlatform.bilibili;
    }

    // LinkedIn
    if (lowerUrl.contains('linkedin.com') || lowerUrl.contains('lnkd.in')) {
      return VideoPlatform.linkedin;
    }

    // Douyin
    if (lowerUrl.contains('douyin.com') || lowerUrl.contains('v.douyin.com')) {
      return VideoPlatform.douyin;
    }

    // Threads
    if (lowerUrl.contains('threads.net')) {
      return VideoPlatform.threads;
    }

    return VideoPlatform.unknown;
  }

  /// Get the login URL for a platform (for cookie auto-navigate flow)
  static String? getLoginUrl(VideoPlatform platform) {
    const loginUrls = {
      VideoPlatform.youtube: 'https://accounts.google.com/ServiceLogin?continue=https://www.youtube.com/',
      VideoPlatform.instagram: 'https://www.instagram.com/accounts/login',
      VideoPlatform.facebook: 'https://www.facebook.com/login',
      VideoPlatform.tiktok: 'https://www.tiktok.com/login',
      VideoPlatform.twitter: 'https://twitter.com/i/flow/login',
      VideoPlatform.reddit: 'https://www.reddit.com/login',
      VideoPlatform.pinterest: 'https://www.pinterest.com/login',
      VideoPlatform.bilibili: 'https://passport.bilibili.com/login',
      VideoPlatform.douyin: 'https://www.douyin.com/',
    };
    return loginUrls[platform];
  }

  /// Get all supported platforms (excluding unknown)
  static List<VideoPlatform> getAllPlatforms() {
    return VideoPlatform.values.where((p) => p != VideoPlatform.unknown).toList();
  }

  /// Extract YouTube video ID from URL
  /// Pattern: [a-zA-Z0-9_-]{11}
  static String? extractYouTubeVideoId(String url) {
    // Pattern 1: youtube.com/watch?v=VIDEO_ID
    final watchPattern = RegExp(r'[?&]v=([a-zA-Z0-9_-]{11})');
    var match = watchPattern.firstMatch(url);
    if (match != null) {
      return match.group(1);
    }

    // Pattern 2: youtu.be/VIDEO_ID
    final shortPattern = RegExp(r'youtu\.be/([a-zA-Z0-9_-]{11})');
    match = shortPattern.firstMatch(url);
    if (match != null) {
      return match.group(1);
    }

    // Pattern 3: youtube.com/embed/VIDEO_ID
    final embedPattern = RegExp(r'/embed/([a-zA-Z0-9_-]{11})');
    match = embedPattern.firstMatch(url);
    if (match != null) {
      return match.group(1);
    }

    // Pattern 4: youtube.com/v/VIDEO_ID
    final vPattern = RegExp(r'/v/([a-zA-Z0-9_-]{11})');
    match = vPattern.firstMatch(url);
    if (match != null) {
      return match.group(1);
    }

    // Pattern 5: youtube.com/shorts/VIDEO_ID or youtube.com/live/VIDEO_ID
    final shortsLivePattern = RegExp(r'/(?:shorts|live)/([a-zA-Z0-9_-]{11})');
    match = shortsLivePattern.firstMatch(url);
    if (match != null) {
      return match.group(1);
    }

    return null;
  }

  /// Check if URL is a direct download link (starts with http/https)
  static bool isDirectUrl(String url) {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  /// Check if URL is HLS/M3U8 stream
  static bool isHlsStream(String url) {
    final path = url.toLowerCase().split('?').first.split('#').first;
    return path.endsWith('.m3u8');
  }

  /// Parse file size string to bytes
  /// Examples: "1.9 MB" -> 1992294, "450 KB" -> 460800
  static int parseFileSizeToBytes(String sizeStr) {
    try {
      final cleaned = sizeStr.trim().toUpperCase();
      final parts = cleaned.split(' ');

      if (parts.length != 2) return -1;

      final value = double.tryParse(parts[0]);
      if (value == null) return -1;

      final unit = parts[1];

      switch (unit) {
        case 'B':
        case 'BYTES':
          return value.toInt();
        case 'KB':
          return (value * 1024).toInt();
        case 'MB':
          return (value * 1024 * 1024).toInt();
        case 'GB':
          return (value * 1024 * 1024 * 1024).toInt();
        default:
          return -1;
      }
    } catch (e) {
      return -1;
    }
  }
}
