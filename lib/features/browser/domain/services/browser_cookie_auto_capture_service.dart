import '../../../../core/auth/data/native/native_cookie_extractor.dart';
import '../../../../core/auth/domain/usecases/save_platform_cookies_usecase.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/logging/app_logger.dart';

/// Platform-specific cookie capture spec.
/// - [hostPatterns] → which URL hosts count as "user is on this platform"
/// - [cookieHost] → domain passed to NativeCookieExtractor (covers all subdomains)
/// - [requiredMarkers] → session cookies that MUST all be present to conclude
///   the user is actually logged in (as opposed to just visiting the site).
///
/// Marker choice is critical: it must be a cookie the platform only sets
/// after successful authentication, so we don't save a bag of anonymous
/// cookies and mislead yt-dlp into thinking it has a valid session.
class _PlatformSpec {
  final String platform;
  final List<String> hostPatterns;
  final List<String> cookieHosts;
  final List<String> requiredMarkers;

  const _PlatformSpec({
    required this.platform,
    required this.hostPatterns,
    required this.cookieHosts,
    required this.requiredMarkers,
  });

  bool matchesHost(String host) {
    final lower = host.toLowerCase();
    return hostPatterns.any((h) => lower == h || lower.endsWith('.$h'));
  }
}

/// Automatically mirrors session cookies from the in-app browser's WebView
/// cookie store into the `PlatformCookie` database the moment the user
/// completes a login flow — no manual "Paste cookies" dialog required.
///
/// Called fire-and-forget from `onPageFinished`. All failures are swallowed
/// and logged; capture must never break page navigation.
///
/// Throttled per-platform (30s) to avoid hammering the native cookie store
/// on SPA navigation bursts, and deduped by cookie-string hash so repeated
/// captures with unchanged cookies don't spam the DB or rotate the expiry
/// timestamp unnecessarily.
class BrowserCookieAutoCaptureService {
  final SavePlatformCookiesUseCase _saveUseCase;

  final Map<String, DateTime> _lastCaptureAt = {};
  final Map<String, int> _lastSavedHash = {};

  static const Duration _throttle = Duration(seconds: 30);

  // Session markers per platform. Each entry must be a cookie the platform
  // sets ONLY after authenticated login.
  // - youtube.LOGIN_INFO: only appears after the user signs in to a Google
  //   account. SID alone exists for anonymous sessions, so it's not enough.
  // - facebook.c_user + xs: c_user is the user ID, xs is the session token.
  //   Both are HttpOnly and together form the minimum auth pair FB expects.
  // - instagram.sessionid + ds_user_id: mirrors c_user+xs pattern.
  // - tiktok.sessionid: TikTok's primary auth cookie.
  // - x.auth_token + ct0: auth_token is session, ct0 is CSRF — yt-dlp's
  //   twitter extractor checks both. x.com is canonical since Twitter
  //   rebranded; twitter.com redirects so we match both hosts but capture
  //   against x.com where cookies actually live now.
  // - reddit.reddit_session: legacy session cookie, still set alongside
  //   newer token_v2 for compat.
  // - pinterest._pinterest_sess: primary session cookie.
  static const List<_PlatformSpec> _specs = [
    _PlatformSpec(
      platform: 'youtube',
      hostPatterns: ['youtube.com', 'youtu.be'],
      cookieHosts: [
        'youtube.com',
        'www.youtube.com',
        'm.youtube.com',
        'google.com',
        'accounts.google.com',
        'myaccount.google.com',
        'google.com.vn',
      ],
      requiredMarkers: ['LOGIN_INFO'],
    ),
    _PlatformSpec(
      platform: 'facebook',
      hostPatterns: ['facebook.com'],
      cookieHosts: ['facebook.com'],
      requiredMarkers: ['c_user', 'xs'],
    ),
    _PlatformSpec(
      platform: 'instagram',
      hostPatterns: ['instagram.com'],
      cookieHosts: ['instagram.com'],
      requiredMarkers: ['sessionid', 'ds_user_id'],
    ),
    _PlatformSpec(
      platform: 'tiktok',
      hostPatterns: ['tiktok.com'],
      cookieHosts: ['tiktok.com'],
      requiredMarkers: ['sessionid'],
    ),
    _PlatformSpec(
      platform: 'x',
      hostPatterns: ['x.com', 'twitter.com'],
      cookieHosts: ['x.com'],
      requiredMarkers: ['auth_token', 'ct0'],
    ),
    _PlatformSpec(
      platform: 'reddit',
      hostPatterns: ['reddit.com'],
      cookieHosts: ['reddit.com'],
      requiredMarkers: ['reddit_session'],
    ),
    _PlatformSpec(
      platform: 'pinterest',
      hostPatterns: ['pinterest.com'],
      cookieHosts: ['pinterest.com'],
      requiredMarkers: ['_pinterest_sess'],
    ),
  ];

  BrowserCookieAutoCaptureService(this._saveUseCase);

  /// Check the just-finished page against known platforms. If it matches
  /// and the native cookie store contains the required session markers,
  /// save the full cookie set for yt-dlp to use on the next download.
  Future<void> captureIfLoggedIn(String pageUrl) async {
    if (!NativeCookieExtractor.isSupported) return;

    final host = _hostOf(pageUrl);
    if (host == null) return;

    final spec = _specs.where((s) => s.matchesHost(host)).firstOrNull;
    if (spec == null) return;

    // Per-platform throttle — prevents SPA route changes from flooding the
    // native cookie store read path.
    final last = _lastCaptureAt[spec.platform];
    final now = DateTime.now();
    if (last != null && now.difference(last) < _throttle) return;
    _lastCaptureAt[spec.platform] = now;

    try {
      final allCookies = <NativeCookie>[];
      for (final cookieHost in spec.cookieHosts) {
        allCookies.addAll(
          await NativeCookieExtractor.getCookiesForDomain(cookieHost),
        );
      }

      final uniqueCookies = <String, NativeCookie>{};
      for (final cookie in allCookies) {
        uniqueCookies['${cookie.domain}:${cookie.name}'] = cookie;
      }

      final cookies = uniqueCookies.values.toList();
      if (cookies.isEmpty) return;

      final names = cookies.map((c) => c.name).toSet();
      final loggedIn = spec.requiredMarkers.every(
        (marker) => names.contains(marker),
      );
      if (!loggedIn) return;

      final netscape = cookies
          .where((c) => c.name.isNotEmpty && c.value.isNotEmpty)
          .map((c) => c.toNetscapeLine())
          .join('\n');

      // Dedupe: identical cookie set already stored → skip DB write.
      final hash = netscape.hashCode;
      if (_lastSavedHash[spec.platform] == hash) return;
      _lastSavedHash[spec.platform] = hash;

      // Carry the longest-lived cookie's expiry forward as the record's
      // expiry, so yt-dlp knows when to treat it as stale. If no cookie
      // carried an expiry, SavePlatformCookiesUseCase/repository falls back
      // to its own default.
      DateTime? expiresAt;
      for (final c in cookies) {
        final exp = c.expiresDate;
        if (exp == null) continue;
        if (expiresAt == null || exp.isAfter(expiresAt)) expiresAt = exp;
      }

      final result = await _saveUseCase(
        platform: spec.platform,
        cookieString: netscape,
        expiresAt: expiresAt,
      );
      if (result.isSuccess) {
        appLogger.info(
          'Auto-captured ${cookies.length} cookies for ${spec.platform} '
          '(${spec.requiredMarkers.join("+")} present)',
        );
      }
    } catch (e) {
      appLogger.warning('Cookie auto-capture failed for ${spec.platform}: $e');
    }
  }

  String? _hostOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return null;
    return uri.host;
  }
}
