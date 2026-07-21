import '../../../../core/utils/platform_detector.dart';

/// Detection result for a URL — indicates whether it's a video page
class VideoUrlDetection {
  final bool isVideoPage;
  final String url;
  final VideoPlatform platform;
  final String? videoId;

  const VideoUrlDetection({
    required this.isVideoPage,
    required this.url,
    required this.platform,
    this.videoId,
  });

  const VideoUrlDetection.none({required this.url})
      : isVideoPage = false,
        platform = VideoPlatform.unknown,
        videoId = null;
}

/// Detects whether a URL is a video page on a supported platform.
///
/// Distinct from [PlatformDetector] which identifies WHICH platform;
/// this detects if it's a VIDEO PAGE specifically (e.g. youtube.com/watch
/// vs youtube.com/feed).
class VideoUrlDetector {
  VideoUrlDetector._();

  /// Analyze a URL and return detection result
  static VideoUrlDetection detect(String url) {
    if (url.isEmpty) return VideoUrlDetection.none(url: url);

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return VideoUrlDetection.none(url: url);

    final platform = PlatformDetector.detectPlatform(url);
    if (platform == VideoPlatform.unknown) {
      return VideoUrlDetection.none(url: url);
    }

    final lowerUrl = url.toLowerCase();
    final path = uri.path.toLowerCase();

    switch (platform) {
      case VideoPlatform.youtube:
        return _detectYouTube(url, lowerUrl, path, uri);
      case VideoPlatform.tiktok:
        return _detectTikTok(url, lowerUrl, path);
      case VideoPlatform.instagram:
        return _detectInstagram(url, lowerUrl, path);
      case VideoPlatform.facebook:
        return _detectFacebook(url, lowerUrl, path);
      case VideoPlatform.twitter:
        return _detectTwitter(url, lowerUrl, path);
      case VideoPlatform.vimeo:
        return _detectVimeo(url, lowerUrl, path);
      case VideoPlatform.dailymotion:
        return _detectDailymotion(url, lowerUrl, path);
      case VideoPlatform.reddit:
        return _detectReddit(url, lowerUrl, path);
      case VideoPlatform.soundcloud:
        return _detectSoundCloud(url, lowerUrl, path);
      case VideoPlatform.bilibili:
        return _detectBilibili(url, lowerUrl, path);
      case VideoPlatform.pinterest:
        return _detectPinterest(url, lowerUrl, path);
      case VideoPlatform.threads:
        return _detectThreads(url, lowerUrl, path);
      case VideoPlatform.linkedin:
      case VideoPlatform.douyin:
        return VideoUrlDetection.none(url: url);
      case VideoPlatform.unknown:
        return VideoUrlDetection.none(url: url);
    }
  }

  // ==================== YouTube ====================

  static VideoUrlDetection _detectYouTube(
      String url, String lowerUrl, String path, Uri uri) {
    // youtube.com/watch?v=ID
    if (path.contains('/watch') && uri.queryParameters.containsKey('v')) {
      return VideoUrlDetection(
        isVideoPage: true,
        url: url,
        platform: VideoPlatform.youtube,
        videoId: PlatformDetector.extractYouTubeVideoId(url),
      );
    }

    // youtube.com/shorts/ID
    if (RegExp(r'/shorts/[a-zA-Z0-9_-]+').hasMatch(path)) {
      return VideoUrlDetection(
        isVideoPage: true,
        url: url,
        platform: VideoPlatform.youtube,
        videoId: PlatformDetector.extractYouTubeVideoId(url),
      );
    }

    // youtu.be/ID
    if (lowerUrl.contains('youtu.be/')) {
      return VideoUrlDetection(
        isVideoPage: true,
        url: url,
        platform: VideoPlatform.youtube,
        videoId: PlatformDetector.extractYouTubeVideoId(url),
      );
    }

    return VideoUrlDetection.none(url: url);
  }

  // ==================== TikTok ====================

  static VideoUrlDetection _detectTikTok(
      String url, String lowerUrl, String path) {
    // tiktok.com/@user/video/1234567890
    if (RegExp(r'/@[^/]+/video/\d+').hasMatch(path)) {
      return VideoUrlDetection(
        isVideoPage: true,
        url: url,
        platform: VideoPlatform.tiktok,
      );
    }

    // Short link: vt.tiktok.com/XXXXX/ or tiktok.com/t/XXXXX/
    if (lowerUrl.contains('vt.tiktok.com/') ||
        RegExp(r'/t/[a-zA-Z0-9]+').hasMatch(path)) {
      return VideoUrlDetection(
        isVideoPage: true,
        url: url,
        platform: VideoPlatform.tiktok,
      );
    }

    return VideoUrlDetection.none(url: url);
  }

  // ==================== Instagram ====================

  static VideoUrlDetection _detectInstagram(
      String url, String lowerUrl, String path) {
    // instagram.com/p/CODE/ or /reel/CODE/ or /tv/CODE/
    if (RegExp(r'/(p|reel|tv)/[a-zA-Z0-9_-]+').hasMatch(path)) {
      return VideoUrlDetection(
        isVideoPage: true,
        url: url,
        platform: VideoPlatform.instagram,
      );
    }

    return VideoUrlDetection.none(url: url);
  }

  // ==================== Facebook ====================

  static VideoUrlDetection _detectFacebook(
      String url, String lowerUrl, String path) {
    // facebook.com/*/videos/123 or /watch/?v=123 or /reel/123
    if (path.contains('/videos/') ||
        path.contains('/watch') ||
        path.contains('/reel/')) {
      return VideoUrlDetection(
        isVideoPage: true,
        url: url,
        platform: VideoPlatform.facebook,
      );
    }

    // facebook.com/share/v/CODE or /share/r/CODE (share redirect URLs)
    if (path.contains('/share/v/') || path.contains('/share/r/')) {
      return VideoUrlDetection(
        isVideoPage: true,
        url: url,
        platform: VideoPlatform.facebook,
      );
    }

    // fb.watch/XXXX
    if (lowerUrl.contains('fb.watch/')) {
      return VideoUrlDetection(
        isVideoPage: true,
        url: url,
        platform: VideoPlatform.facebook,
      );
    }

    return VideoUrlDetection.none(url: url);
  }

  // ==================== Twitter/X ====================

  static VideoUrlDetection _detectTwitter(
      String url, String lowerUrl, String path) {
    // twitter.com/user/status/1234567890 or x.com/user/status/1234567890
    if (RegExp(r'/[^/]+/status/\d+').hasMatch(path)) {
      return VideoUrlDetection(
        isVideoPage: true,
        url: url,
        platform: VideoPlatform.twitter,
      );
    }

    return VideoUrlDetection.none(url: url);
  }

  // ==================== Vimeo ====================

  static VideoUrlDetection _detectVimeo(
      String url, String lowerUrl, String path) {
    // vimeo.com/123456789
    if (RegExp(r'^/\d+(/|$)').hasMatch(path)) {
      return VideoUrlDetection(
        isVideoPage: true,
        url: url,
        platform: VideoPlatform.vimeo,
      );
    }

    return VideoUrlDetection.none(url: url);
  }

  // ==================== Dailymotion ====================

  static VideoUrlDetection _detectDailymotion(
      String url, String lowerUrl, String path) {
    // dailymotion.com/video/x1234 or dai.ly/x1234
    if (path.contains('/video/') || lowerUrl.contains('dai.ly/')) {
      return VideoUrlDetection(
        isVideoPage: true,
        url: url,
        platform: VideoPlatform.dailymotion,
      );
    }

    return VideoUrlDetection.none(url: url);
  }

  // ==================== Reddit ====================

  static VideoUrlDetection _detectReddit(
      String url, String lowerUrl, String path) {
    // reddit.com/r/subreddit/comments/id/title
    if (path.contains('/comments/')) {
      return VideoUrlDetection(
        isVideoPage: true,
        url: url,
        platform: VideoPlatform.reddit,
      );
    }

    return VideoUrlDetection.none(url: url);
  }

  // ==================== SoundCloud ====================

  static VideoUrlDetection _detectSoundCloud(
      String url, String lowerUrl, String path) {
    // soundcloud.com/user/track-name (2-segment path, not /discover, /search, etc.)
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length >= 2) {
      // Exclude known non-track pages
      const excludedFirstSegments = [
        'discover', 'search', 'stream', 'upload', 'you',
        'settings', 'messages', 'notifications', 'charts',
        'pages', 'jobs', 'legal', 'press',
      ];
      if (!excludedFirstSegments.contains(segments[0])) {
        return VideoUrlDetection(
          isVideoPage: true,
          url: url,
          platform: VideoPlatform.soundcloud,
        );
      }
    }

    return VideoUrlDetection.none(url: url);
  }

  // ==================== Bilibili ====================

  static VideoUrlDetection _detectBilibili(
      String url, String lowerUrl, String path) {
    // bilibili.com/video/BVxxxxxx or /video/avxxxxxx
    // Note: path is lowercased, so match bv/av
    if (RegExp(r'/video/(bv|av)[a-zA-Z0-9]+').hasMatch(path)) {
      return VideoUrlDetection(
        isVideoPage: true,
        url: url,
        platform: VideoPlatform.bilibili,
      );
    }

    return VideoUrlDetection.none(url: url);
  }

  // ==================== Pinterest ====================

  static VideoUrlDetection _detectPinterest(
      String url, String lowerUrl, String path) {
    // pinterest.com/pin/123456789
    if (RegExp(r'/pin/\d+').hasMatch(path)) {
      return VideoUrlDetection(
        isVideoPage: true,
        url: url,
        platform: VideoPlatform.pinterest,
      );
    }

    return VideoUrlDetection.none(url: url);
  }

  // ==================== Threads ====================

  static VideoUrlDetection _detectThreads(
      String url, String lowerUrl, String path) {
    // threads.net/@user/post/CODE or threads.net/t/CODE
    if (RegExp(r'/@[^/]+/post/[a-zA-Z0-9_-]+').hasMatch(path) ||
        RegExp(r'/t/[a-zA-Z0-9_-]+').hasMatch(path)) {
      return VideoUrlDetection(
        isVideoPage: true,
        url: url,
        platform: VideoPlatform.threads,
      );
    }

    return VideoUrlDetection.none(url: url);
  }
}
