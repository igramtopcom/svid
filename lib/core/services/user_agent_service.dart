import 'dart:math';

import '../../core/utils/platform_detector.dart';

/// Service providing realistic, rotating User-Agent strings to avoid
/// anti-bot fingerprinting by video platforms.
///
/// Maintains a pool of real browser UAs (Chrome, Firefox, Edge) across
/// Windows, macOS, and Linux. Each call to [getRandomUserAgent] returns
/// a different UA from the pool.
///
/// Session rotation: [rotateUserAgent] increments an index so each
/// download session uses a different UA, while staying consistent
/// within the same session.
class UserAgentService {
  UserAgentService({Random? random}) : _random = random ?? Random();

  final Random _random;
  int _rotationIndex = 0;

  /// Pool of realistic, modern browser User-Agent strings.
  /// Updated to Chrome 131-134, Firefox 133-135, Edge 131-133 (2025-2026 era).
  static const List<String> _userAgents = [
    // Chrome on Windows
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    // Chrome on macOS
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36',
    // Chrome on Linux
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
    // Firefox on Windows
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:135.0) Gecko/20100101 Firefox/135.0',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:134.0) Gecko/20100101 Firefox/134.0',
    // Firefox on macOS
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:135.0) Gecko/20100101 Firefox/135.0',
    // Firefox on Linux
    'Mozilla/5.0 (X11; Linux x86_64; rv:135.0) Gecko/20100101 Firefox/135.0',
    // Edge on Windows
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36 Edg/134.0.0.0',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36 Edg/133.0.0.0',
    // Edge on macOS
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36 Edg/134.0.0.0',
  ];

  /// Returns a random User-Agent string from the pool.
  String getRandomUserAgent() {
    return _userAgents[_random.nextInt(_userAgents.length)];
  }

  /// Returns the best User-Agent for a specific video platform.
  ///
  /// - Instagram/TikTok/Pinterest: mobile Safari (avoids desktop-specific blocks)
  /// - YouTube/Bilibili/Vimeo/Dailymotion: desktop Chrome (best compatibility)
  /// - Others: random from pool
  String getUserAgentForPlatform(VideoPlatform platform) {
    switch (platform) {
      case VideoPlatform.instagram:
      case VideoPlatform.tiktok:
      case VideoPlatform.pinterest:
        // Mobile Safari performs better on mobile-first platforms
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_3 like Mac OS X) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 '
            'Mobile/15E148 Safari/604.1';
      case VideoPlatform.youtube:
      case VideoPlatform.bilibili:
      case VideoPlatform.vimeo:
      case VideoPlatform.dailymotion:
      case VideoPlatform.soundcloud:
        // Desktop Chrome works best for these platforms
        return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';
      case VideoPlatform.twitter:
      case VideoPlatform.facebook:
      case VideoPlatform.reddit:
      case VideoPlatform.linkedin:
      case VideoPlatform.douyin:
      case VideoPlatform.threads:
      case VideoPlatform.unknown:
        return getRandomUserAgent();
    }
  }

  /// Returns the next UA in rotation order (sequential, not random).
  ///
  /// Use this when you want consistent UA per download session while
  /// varying between sessions.
  String rotateUserAgent() {
    final ua = _userAgents[_rotationIndex % _userAgents.length];
    _rotationIndex++;
    return ua;
  }

  /// Number of available User-Agent strings.
  static int get poolSize => _userAgents.length;

  /// All available User-Agent strings (for testing/debugging).
  static List<String> get allUserAgents => List.unmodifiable(_userAgents);

  // ---------------------------------------------------------------------------
  // Accept-Language rotation
  // ---------------------------------------------------------------------------

  static const List<String> _acceptLanguages = [
    'en-US,en;q=0.9',
    'en-GB,en;q=0.9',
    'vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7',
    'ja-JP,ja;q=0.9,en-US;q=0.8,en;q=0.7',
    'ko-KR,ko;q=0.9,en-US;q=0.8',
    'zh-CN,zh;q=0.9,en-US;q=0.8',
    'fr-FR,fr;q=0.9,en-US;q=0.8',
    'de-DE,de;q=0.9,en-US;q=0.8',
  ];

  /// Returns a random Accept-Language header value from the pool.
  String getAcceptLanguage() {
    return _acceptLanguages[_random.nextInt(_acceptLanguages.length)];
  }

  /// All available Accept-Language values (for testing).
  static List<String> get allAcceptLanguages => List.unmodifiable(_acceptLanguages);
}
