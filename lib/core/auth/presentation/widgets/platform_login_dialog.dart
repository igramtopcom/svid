import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../features/browser/data/webview/app_webview.dart';
import '../../../core.dart';
import '../../data/native/native_cookie_extractor.dart';
import '../providers/auth_providers.dart';

/// Login status for the WebView
enum LoginStatus {
  waitingForLogin,
  loginDetected,
  extractingCookies,
  success,
  failed,
}

/// Platform login dialog with embedded webview
/// Extracts cookies after successful login
class PlatformLoginDialog extends ConsumerStatefulWidget {
  final String platform;
  final String loginUrl;

  const PlatformLoginDialog({
    super.key,
    required this.platform,
    required this.loginUrl,
  });

  @override
  ConsumerState<PlatformLoginDialog> createState() =>
      _PlatformLoginDialogState();

  /// MARKER GUARD specs per Chairman + Codex Decision Package
  /// 2026-05-21. A "marker" is a cookie that, when present in the
  /// captured set, indicates the user is genuinely authenticated
  /// (not just visiting the platform anonymously). Auto-save is
  /// GATED on these markers — if the cookies the in-app browser
  /// holds do NOT include the required marker(s), we DO NOT save
  /// them. This prevents the legacy YouTube-only gate from leaving
  /// Facebook/IG/X out, AND prevents the new generalized auto-save
  /// from polluting the cookie store with anonymous trackers that
  /// would not authenticate any subsequent download.
  ///
  /// Semantics:
  ///   - YT: ANY ONE of the listed cookies satisfies (Google ships
  ///     several SID variants depending on browser + region).
  ///   - FB: BOTH c_user AND xs required (Facebook authentication
  ///     pair — Codex specified).
  ///   - IG: sessionid required (better with ds_user_id but
  ///     sessionid alone is enough).
  ///   - X: auth_token required (better with ct0).
  /// Adding a platform = (a) add to this map, (b) update the
  /// success-URL detector to trigger this dialog for that platform.
  static const Map<String, AuthMarkerSpec> authMarkers = {
    'youtube': AuthMarkerSpec(
      anyOf: {
        'SID',
        'HSID',
        'SSID',
        'APISID',
        'SAPISID',
        '__Secure-1PSID',
        '__Secure-3PSID',
      },
    ),
    'facebook': AuthMarkerSpec(allOf: {'c_user', 'xs'}),
    'instagram': AuthMarkerSpec(allOf: {'sessionid'}),
    'twitter': AuthMarkerSpec(allOf: {'auth_token'}),
    'x': AuthMarkerSpec(allOf: {'auth_token'}),
    // RC8.1 — parity with browser_cookie_auto_capture_service. Pre-RC8.1
    // these 3 platforms had auto-capture via WebView but the dialog-
    // driven re-login skipped them (unknown platform → no auto-save).
    // Marker cookie names sourced from browser_cookie_auto_capture_service.dart
    // (requiredMarkers list) so dialog auto-save fires symmetrically.
    'tiktok': AuthMarkerSpec(allOf: {'sessionid'}),
    'reddit': AuthMarkerSpec(allOf: {'reddit_session'}),
    'pinterest': AuthMarkerSpec(allOf: {'_pinterest_sess'}),
  };

  /// Return `true` when [capturedCookieNames] satisfies the marker
  /// spec for [platform]. Used by the auto-save flow to gate the
  /// persist step. Unknown platform → never auto-save (defensive,
  /// opt-in only).
  static bool hasRequiredAuthMarker(
    String platform,
    Set<String> capturedCookieNames,
  ) {
    final spec = authMarkers[platform.toLowerCase()];
    if (spec == null) return false;
    return spec.matches(capturedCookieNames);
  }
}

class _PlatformLoginDialogState extends ConsumerState<PlatformLoginDialog> {
  late final AppWebViewController _webViewController;
  bool _isLoading = true;
  String? _errorMessage;
  LoginStatus _loginStatus = LoginStatus.waitingForLogin;
  bool _isClosing = false;
  bool _autoSaveScheduled = false;

  static const Set<String> _youtubeAuthCookieNames = {
    'SID',
    'HSID',
    'SSID',
    'APISID',
    'SAPISID',
    'LOGIN_INFO',
    '__Secure-1PSID',
    '__Secure-3PSID',
    '__Secure-1PSIDTS',
    '__Secure-3PSIDTS',
  };

  // Marker spec moved to PlatformLoginDialog (public widget class)
  // so external test files can reference it without exposing the
  // private state class.

  // URLs that indicate user is STILL on login page (should NOT trigger success)
  static const Map<String, List<String>> _loginPagePatterns = {
    'youtube': [
      'accounts.google.com/v3/signin',
      'accounts.google.com/signin',
      'accounts.google.com/ServiceLogin',
      'accounts.google.com/AccountChooser',
      'accounts.google.com/InteractiveLogin',
      'accounts.google.com/CheckCookie',
      'accounts.google.com/speedbump',
      'youtube.com/signin',
      'youtube.com/o/oauth2',
    ],
    'instagram': ['instagram.com/accounts/login', 'instagram.com/challenge'],
    'facebook': [
      'facebook.com/login',
      'facebook.com/checkpoint',
      'm.facebook.com/login',
    ],
    'tiktok': ['tiktok.com/login', 'tiktok.com/signup'],
    'reddit': ['reddit.com/login', 'reddit.com/register'],
    'pinterest': ['pinterest.com/login'],
    'x': [
      'twitter.com/i/flow/login',
      'twitter.com/login',
      'x.com/i/flow/login',
    ],
    'douyin': ['douyin.com/passport', 'douyin.com/login'],
  };

  // URLs that indicate successful login (user reached main content)
  static const Map<String, List<String>> _successUrlPatterns = {
    'youtube': [
      'youtube.com/feed',
      'youtube.com/watch',
      'youtube.com/channel',
      'youtube.com/c/',
      'youtube.com/@',
      'studio.youtube.com',
    ],
    'instagram': [
      'instagram.com/direct',
      'instagram.com/explore',
      'instagram.com/reels',
      'instagram.com/accounts/onetap',
    ],
    'facebook': [
      'facebook.com/home',
      'facebook.com/?sk=',
      'facebook.com/groups',
      'facebook.com/watch',
      'facebook.com/marketplace',
    ],
    'tiktok': ['tiktok.com/foryou', 'tiktok.com/following', 'tiktok.com/@'],
    'reddit': ['reddit.com/r/', 'reddit.com/user/', 'reddit.com/submit'],
    'pinterest': [
      'pinterest.com/ideas',
      'pinterest.com/pin/',
      'pinterest.com/search',
    ],
    'x': [
      'twitter.com/home',
      'twitter.com/compose',
      'x.com/home',
      'x.com/compose',
    ],
    'douyin': ['douyin.com/recommend', 'douyin.com/follow', 'douyin.com/user/'],
  };

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _webViewController = AppWebViewController(
      initialUrl: widget.loginUrl,
      // Use Safari UA - Google blocks Chrome-like UA in WebViews
      userAgent:
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) '
          'Version/17.2 Safari/605.1.15',
      callbacks: WebViewNavigationCallbacks(
        onPageStarted: (String url) {
          if (!mounted) return;
          setState(() {
            _isLoading = true;
            _errorMessage = null;
          });
        },
        onPageFinished: (String url) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
          });

          // Check login status based on URL
          _checkLoginStatus(url);
        },
        onError: (String description, {bool isUnknown = false}) {
          if (!mounted) return;
          // Ignore minor resource errors (images, scripts, etc.)
          if (isUnknown) return;

          setState(() {
            _errorMessage = 'Load error: $description';
            _isLoading = false;
          });
          appLogger.warning('WebView resource error: $description');
        },
        onNavigationRequest: (String url, bool isMainFrame) {
          if (_shouldBlockPostLoginNavigation(url, isMainFrame)) {
            appLogger.info(
              '[Login] Blocking post-login navigation and saving cookies: $url',
            );
            _markLoginDetected();
            _scheduleAutoSaveCookies();
            return false;
          }

          return true;
        },
      ),
    );
  }

  /// Get all related domains for a platform (for cookie extraction)
  /// YouTube needs google.com cookies, Facebook needs instagram cross-domain, etc.
  List<String> _getRelatedDomains(String platform) {
    switch (platform.toLowerCase()) {
      case 'youtube':
        return [
          'youtube.com',
          'www.youtube.com',
          'm.youtube.com',
          'google.com',
          'accounts.google.com',
          'myaccount.google.com',
          'google.com.vn',
          'googleapis.com',
        ];
      case 'instagram':
        return ['instagram.com', 'facebook.com'];
      case 'facebook':
        return ['facebook.com', 'instagram.com'];
      case 'tiktok':
        return ['tiktok.com', 'bytedance.com'];
      case 'twitter':
      case 'x':
        return ['twitter.com', 'x.com'];
      case 'reddit':
        return ['reddit.com'];
      case 'pinterest':
        return ['pinterest.com'];
      case 'douyin':
        return ['douyin.com'];
      default:
        return ['$platform.com'];
    }
  }

  /// Check login status based on current URL
  void _checkLoginStatus(String url) {
    final platform = widget.platform.toLowerCase();

    // First check if still on login page
    final loginPatterns = _loginPagePatterns[platform] ?? [];
    for (final pattern in loginPatterns) {
      if (url.contains(pattern)) {
        // Still on login page - don't change status
        appLogger.debug('[Login] Still on login page: $url');
        return;
      }
    }

    // Check if reached success URL
    final successPatterns = _successUrlPatterns[platform] ?? [];
    for (final pattern in successPatterns) {
      if (url.contains(pattern)) {
        appLogger.info('[Login] Success URL detected: $url');
        _markLoginDetected();
        _scheduleAutoSaveCookies();
        return;
      }
    }

    // Generic fallback: if URL is on the platform's main domain
    // and not on a login page, assume logged in.
    // This handles pre-authenticated sessions and unrecognized success URLs.
    const platformDomains = {
      'youtube': ['youtube.com'],
      'instagram': ['instagram.com'],
      'facebook': ['facebook.com'],
      'tiktok': ['tiktok.com'],
      'reddit': ['reddit.com'],
      'pinterest': ['pinterest.com'],
      'x': ['twitter.com', 'x.com'],
      'douyin': ['douyin.com'],
    };

    final domains = platformDomains[platform] ?? [];
    for (final domain in domains) {
      if (url.contains(domain)) {
        appLogger.info(
          '[Login] On platform domain, not on login page — login detected: $url',
        );
        _markLoginDetected();
        _scheduleAutoSaveCookies();
        return;
      }
    }
  }

  bool _shouldBlockPostLoginNavigation(String url, bool isMainFrame) {
    if (!Platform.isWindows || !isMainFrame) return false;
    if (widget.platform.toLowerCase() != 'youtube') return false;

    final lower = url.toLowerCase();
    if (lower.isEmpty) return false;
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return false;
    }
    if (lower.contains('accounts.google.com') ||
        lower.contains('accounts.youtube.com')) {
      return false;
    }
    if (!lower.contains('youtube.com')) return false;

    return !_isLoginPageUrl(lower);
  }

  bool _isLoginPageUrl(String lowerUrl) {
    final platform = widget.platform.toLowerCase();
    final loginPatterns = _loginPagePatterns[platform] ?? const <String>[];
    return loginPatterns.any((pattern) => lowerUrl.contains(pattern));
  }

  void _markLoginDetected() {
    if (!mounted || _isClosing) return;
    if (_loginStatus == LoginStatus.loginDetected ||
        _loginStatus == LoginStatus.extractingCookies ||
        _loginStatus == LoginStatus.success) {
      return;
    }
    setState(() {
      _loginStatus = LoginStatus.loginDetected;
    });
  }

  void _scheduleAutoSaveCookies() {
    // Codex Decision Package 2026-05-21: auto-save was previously
    // gated to `Platform.isWindows && platform == 'youtube'`. Both
    // restrictions are removed — auto-save applies to every
    // supported platform, on every OS. The marker-guard check
    // inside `_extractAndSaveCookies` ensures we only PERSIST
    // cookies that actually authenticate (no anonymous cookie
    // pollution). The legacy gate left Wilson-class Facebook
    // users unable to capture cookies because the dialog never
    // auto-fired for FB; this generalization closes that.
    final platform = widget.platform.toLowerCase();
    if (!PlatformLoginDialog.authMarkers.containsKey(platform)) {
      // Unknown platform → no marker spec → cannot safely auto-save.
      // The manual "Done" path still works and the user gets the
      // legacy save behavior.
      return;
    }
    if (_autoSaveScheduled || _isClosing) return;

    _autoSaveScheduled = true;
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 700), () async {
        _autoSaveScheduled = false;
        if (!mounted || _isClosing) return;
        if (_loginStatus != LoginStatus.loginDetected) return;

        appLogger.info(
          '[Login] Auto-saving cookies after ${widget.platform} login',
        );
        setState(() {
          _loginStatus = LoginStatus.extractingCookies;
        });
        await _extractAndSaveCookies();
      }),
    );
  }

  /// Manual "Done" button pressed - extract cookies
  Future<void> _onDonePressed() async {
    if (_isClosing) return;

    // Get current URL to check if user is still on login page
    final currentUrl = await _webViewController.currentUrl() ?? '';
    final platform = widget.platform.toLowerCase();

    // Check if still on login page
    final loginPatterns = _loginPagePatterns[platform] ?? [];
    for (final pattern in loginPatterns) {
      if (currentUrl.contains(pattern)) {
        // Still on login page - warn user
        if (!mounted) return;
        AppSnackBar.warning(
          context,
          message:
              'Please complete the login first. You are still on the login page.',
        );
        return;
      }
    }

    setState(() {
      _loginStatus = LoginStatus.extractingCookies;
    });

    await _extractAndSaveCookies();
  }

  /// Extract cookies from webview and save
  /// Uses native platform APIs (WKHTTPCookieStore on macOS) to get HttpOnly cookies
  /// Falls back to JavaScript extraction on unsupported platforms
  Future<void> _extractAndSaveCookies() async {
    if (_isClosing) return;
    _isClosing = true;

    try {
      appLogger.info('[Login] Extracting cookies for ${widget.platform}...');

      String cookieString = '';
      int httpOnlyCount = 0;
      var nativeAttempted = false;
      var nativeCookieCount = 0;
      var nativeAuthCookieCount = 0;

      // Try native extraction first (includes HttpOnly cookies)
      if (NativeCookieExtractor.isSupported) {
        nativeAttempted = true;
        appLogger.info(
          '[Login] Using native cookie extraction (includes HttpOnly)',
        );

        // Debug: Log ALL cookies from ALL sources (dev only — method channel is expensive)
        if (kDebugMode) {
          await NativeCookieExtractor.debugGetAllCookies();
        }

        // Get all related domains for this platform
        final domains = _getRelatedDomains(widget.platform);
        final allNativeCookies = <NativeCookie>[];

        for (final domain in domains) {
          final cookies = await NativeCookieExtractor.getCookiesForDomain(
            domain,
          );
          appLogger.debug('[Login] Got ${cookies.length} cookies from $domain');
          allNativeCookies.addAll(cookies);
        }

        // Remove duplicates (same name+domain)
        final uniqueCookies = <String, NativeCookie>{};
        for (final cookie in allNativeCookies) {
          final key = '${cookie.domain}:${cookie.name}';
          uniqueCookies[key] = cookie;
        }
        var nativeCookies = uniqueCookies.values.toList();

        final jsCookieString = await _readDocumentCookie();
        if (jsCookieString.isNotEmpty) {
          final jsCookies = _documentCookiesToNativeCookies(jsCookieString);
          var addedJsCookies = 0;
          for (final cookie in jsCookies) {
            final key = '${cookie.domain}:${cookie.name}';
            if (!uniqueCookies.containsKey(key)) {
              uniqueCookies[key] = cookie;
              addedJsCookies++;
            }
          }
          if (addedJsCookies > 0) {
            nativeCookies = uniqueCookies.values.toList();
            appLogger.info(
              '[Login] Merged $addedJsCookies JavaScript-visible cookies '
              'with native HttpOnly cookies',
            );
          }
        }

        nativeCookieCount = nativeCookies.length;

        if (nativeCookies.isNotEmpty) {
          httpOnlyCount = nativeCookies.where((c) => c.isHttpOnly).length;

          appLogger.info(
            '[Login] Native extraction: ${nativeCookies.length} cookies '
            '($httpOnlyCount HttpOnly)',
          );

          // Log important auth cookies
          final foundAuthCookies =
              nativeCookies
                  .where(
                    (c) => _isAuthCookieForPlatform(widget.platform, c.name),
                  )
                  .map((c) => c.name)
                  .toList();
          nativeAuthCookieCount = foundAuthCookies.length;

          if (foundAuthCookies.isNotEmpty) {
            appLogger.info(
              '[Login] Found auth cookies: ${foundAuthCookies.join(", ")}',
            );
          } else {
            appLogger.warning(
              '[Login] No auth cookies found! Login may not be complete.',
            );
          }

          // MARKER GUARD — per Chairman/Codex Decision Package
          // 2026-05-21. Before persisting cookies, verify the
          // captured set contains the platform's required auth
          // marker. Without this gate the generalized auto-save
          // (extended from YouTube-only to FB/IG/X) would happily
          // save anonymous cookies after a partial / aborted login,
          // polluting the cookie store with tokens that don't
          // authenticate any subsequent download. Skip means: log
          // + leave the user on the login dialog (manual "Done"
          // path still works if they complete the login).
          final capturedNames =
              nativeCookies.map((c) => c.name).toSet();
          if (!PlatformLoginDialog.hasRequiredAuthMarker(
              widget.platform, capturedNames)) {
            appLogger.warning(
              '[Login] Marker guard FAILED for ${widget.platform}: '
              'captured set does not contain the required auth '
              'cookie(s). Skipping auto-save — user must complete '
              'login + retry. Found: ${capturedNames.take(8).join(", ")}'
              '${capturedNames.length > 8 ? "..." : ""}',
            );
            if (mounted) {
              setState(() {
                _loginStatus = LoginStatus.waitingForLogin;
                _errorMessage = null;
              });
            }
            return;
          }

          // Convert to Netscape format DIRECTLY (preserves domain info)
          // This is crucial for yt-dlp to authenticate properly
          cookieString = NativeCookieExtractor.cookiesToNetscapeFormat(
            nativeCookies,
          );
        }
      }

      final platformKey = widget.platform.toLowerCase();
      final nativeYouTubeCookieUsable =
          nativeAttempted &&
          nativeCookieCount > 0 &&
          nativeAuthCookieCount > 0 &&
          httpOnlyCount > 0;

      if (platformKey == 'youtube' &&
          NativeCookieExtractor.isSupported &&
          !nativeYouTubeCookieUsable) {
        const message =
            'Could not read YouTube auth cookies from the embedded browser. '
            'Please close the login dialog, reopen it, sign in again, and try once more. '
            'If this persists, close Chrome/Edge before trying browser cookie fallback.';
        appLogger.warning(
          '[Login] YouTube native cookie extraction unusable: '
          'nativeAttempted=$nativeAttempted, nativeCookieCount=$nativeCookieCount, '
          'httpOnlyCount=$httpOnlyCount, authCookieCount=$nativeAuthCookieCount',
        );
        if (!mounted) return;
        setState(() {
          _loginStatus = LoginStatus.failed;
          _errorMessage = message;
        });
        _isClosing = false;
        return;
      }

      // Fallback to JavaScript if native failed or not supported
      if (cookieString.isEmpty) {
        appLogger.warning('[Login] Falling back to JavaScript extraction');

        cookieString = await _readDocumentCookie();

        if (cookieString.isEmpty) {
          // Try alternative method
          final altCookies =
              await _webViewController.runJavaScriptReturningResult('''
            (function() {
              try { return document.cookie || ''; }
              catch(e) { return ''; }
            })()
          ''')
                  as String;

          cookieString = altCookies.replaceAll('"', '').trim();
        }

        if (cookieString.isNotEmpty) {
          appLogger.info(
            '[Login] JavaScript extraction: ${cookieString.split(";").length} cookies (no HttpOnly)',
          );
        }
      }

      if (cookieString.isEmpty) {
        appLogger.warning('[Login] No cookies found!');
      }

      appLogger.debug(
        '[Login] Total cookie string: ${cookieString.length} chars',
      );

      // Save cookies using use case
      final saveUseCase = ref.read(savePlatformCookiesUseCaseProvider);
      final result = await saveUseCase(
        platform: widget.platform.toLowerCase(),
        cookieString: cookieString,
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      );

      if (!mounted) return;

      if (result.isSuccess) {
        setState(() {
          _loginStatus = LoginStatus.success;
        });

        // Small delay to show success state, then close
        await Future.delayed(const Duration(milliseconds: 500));

        if (!mounted) return;

        // Close dialog safely
        Navigator.of(context).pop(true);

        // Show success snackbar after dialog closes
        final message =
            httpOnlyCount > 0
                ? '${widget.platform} login saved ($httpOnlyCount auth cookies)'
                : AppLocalizations.platformLoginSuccess(widget.platform);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          AppSnackBar.success(context, message: message);
        });
      } else {
        setState(() {
          _loginStatus = LoginStatus.failed;
          _errorMessage =
              result.exceptionOrNull != null
                  ? AppExceptionX.readableMessage(result.exceptionOrNull!)
                  : 'Failed to save cookies';
        });
        _isClosing = false;
      }
    } catch (e) {
      appLogger.error('[Login] Error extracting cookies: $e');
      if (!mounted) return;

      setState(() {
        _loginStatus = LoginStatus.failed;
        _errorMessage = 'Error: ${e.toString()}';
      });
      _isClosing = false;
    }
  }

  Future<String> _readDocumentCookie() async {
    try {
      final raw = await _webViewController.runJavaScriptReturningResult(
        'document.cookie',
      );
      final cookieString = _normalizeJavaScriptCookieResult(raw);
      if (cookieString.isNotEmpty) return cookieString;

      final fallback = await _webViewController.runJavaScriptReturningResult('''
        (function() {
          try { return document.cookie || ''; }
          catch(e) { return ''; }
        })()
      ''');
      return _normalizeJavaScriptCookieResult(fallback);
    } catch (e) {
      appLogger.debug('[Login] JavaScript cookie read failed: $e');
      return '';
    }
  }

  String _normalizeJavaScriptCookieResult(Object? raw) {
    var value = raw?.toString().trim() ?? '';
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    return value.trim();
  }

  List<NativeCookie> _documentCookiesToNativeCookies(String cookieString) {
    final platformDomain = NativeCookieExtractor.getPlatformDomain(
      widget.platform,
    );
    final domain =
        platformDomain.startsWith('.') ? platformDomain : '.$platformDomain';
    final cookies = <NativeCookie>[];

    for (final part in cookieString.split(';')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;

      final equalsIndex = trimmed.indexOf('=');
      if (equalsIndex <= 0) continue;

      final name = trimmed.substring(0, equalsIndex).trim();
      final value = trimmed.substring(equalsIndex + 1).trim();
      if (name.isEmpty || value.isEmpty) continue;

      cookies.add(
        NativeCookie(
          name: name,
          value: value,
          domain: domain,
          path: '/',
          isSecure: true,
          isHttpOnly: false,
          isSessionOnly: true,
        ),
      );
    }

    return cookies;
  }

  bool _isAuthCookieForPlatform(String platform, String cookieName) {
    switch (platform.toLowerCase()) {
      case 'youtube':
        return _youtubeAuthCookieNames.contains(cookieName);
      case 'instagram':
        return cookieName == 'sessionid';
      case 'facebook':
        return cookieName == 'c_user' ||
            cookieName == 'xs' ||
            cookieName == 'datr';
      default:
        return false;
    }
  }

  /// Reload the WebView
  Future<void> _reloadPage() async {
    await _webViewController.reload();
    setState(() {
      _errorMessage = null;
      _loginStatus = LoginStatus.waitingForLogin;
    });
  }

  /// Get status text for display
  String _getStatusText() {
    final platform = _platformLabel;
    switch (_loginStatus) {
      case LoginStatus.waitingForLogin:
        return AppLocalizations.platformLoginTitle(platform);
      case LoginStatus.loginDetected:
        return 'Login detected! Click "Done" to save.';
      case LoginStatus.extractingCookies:
        return AppLocalizations.platformLoginExtractingCookies;
      case LoginStatus.success:
        return AppLocalizations.platformLoginSuccess(platform);
      case LoginStatus.failed:
        return AppLocalizations.platformLoginFailed;
    }
  }

  /// Get status color
  Color _getStatusColor(BuildContext context) {
    return _toneForStatus(context).accent;
  }

  String get _platformLabel {
    final value = widget.platform.trim();
    if (value.isEmpty) return 'Platform';
    return value[0].toUpperCase() + value.substring(1);
  }

  _LoginTone _toneForStatus(BuildContext context) {
    return switch (_loginStatus) {
      LoginStatus.waitingForLogin => _LoginTone.info(context),
      LoginStatus.loginDetected => _LoginTone.success(context),
      LoginStatus.extractingCookies => _LoginTone.brand(context),
      LoginStatus.success => _LoginTone.success(context),
      LoginStatus.failed => _LoginTone.error(context),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);
    final availableWidth = size.width - AppSpacing.lg * 2;
    final availableHeight = size.height - AppSpacing.lg * 2;
    final dialogWidth =
        availableWidth < 640 ? availableWidth : availableWidth.clamp(640, 1040);
    final dialogHeight =
        availableHeight < 520
            ? availableHeight
            : availableHeight.clamp(520, 820);
    final tone = _toneForStatus(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: AppSpacing.edgeInsets.lg,
      child: Container(
        width: dialogWidth.toDouble(),
        height: dialogHeight.toDouble(),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: AppRadius.borderRadius.dialog,
          border: Border.all(color: AppColors.border(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: AppOpacity.scrim),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header with platform info
            Container(
              padding: AppSpacing.edgeInsets.md,
              decoration: BoxDecoration(
                color:
                    isDark
                        ? AppColors.surface2(context)
                        : AppColors.surface1(context),
                borderRadius: BorderRadius.only(
                  topLeft: AppRadius.borderRadius.dialog.topLeft,
                  topRight: AppRadius.borderRadius.dialog.topRight,
                ),
                border: Border(
                  bottom: BorderSide(color: AppColors.border(context)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row with buttons
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(
                            alpha: isDark ? 0.18 : 0.10,
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          border: Border.all(
                            color: cs.primary.withValues(
                              alpha: isDark ? 0.26 : 0.18,
                            ),
                          ),
                        ),
                        child: PlatformIcon(
                          platform: widget.platform,
                          size: 22,
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.platformLoginTitle(
                                _platformLabel,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _isLoading
                                  ? AppLocalizations.platformLoginLoading
                                  : _getStatusText(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Reload button
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _reloadPage,
                        tooltip: AppLocalizations.browserRefresh,
                      ),
                      // Done button (highlighted when login detected)
                      FilledButton.icon(
                        onPressed:
                            _loginStatus == LoginStatus.extractingCookies
                                ? null
                                : _onDonePressed,
                        icon:
                            _loginStatus == LoginStatus.extractingCookies
                                ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: theme.colorScheme.onPrimary,
                                  ),
                                )
                                : Icon(
                                  _loginStatus == LoginStatus.loginDetected
                                      ? Icons.check_circle
                                      : Icons.check,
                                ),
                        label: Text(AppLocalizations.playerDone),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              _loginStatus == LoginStatus.loginDetected
                                  ? AppColors.success(context)
                                  : null,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      // Close button
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed:
                            _isClosing
                                ? null
                                : () => Navigator.of(context).pop(false),
                        tooltip: AppLocalizations.platformLoginCancel,
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.sm),

                  // Status indicator
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: tone.container,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(color: tone.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_loginStatus == LoginStatus.extractingCookies)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: tone.accent,
                              ),
                            ),
                          )
                        else
                          Icon(
                            _loginStatus == LoginStatus.loginDetected ||
                                    _loginStatus == LoginStatus.success
                                ? Icons.check_circle
                                : _loginStatus == LoginStatus.failed
                                ? Icons.error
                                : Icons.hourglass_empty,
                            size: 16,
                            color: _getStatusColor(context),
                          ),
                        const SizedBox(width: 6),
                        Text(
                          _getStatusText(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: tone.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Loading indicator
            if (_isLoading)
              LinearProgressIndicator(
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  theme.colorScheme.primary,
                ),
              ),

            // Error message
            if (_errorMessage != null)
              _LoginNotice(
                icon: Icons.error_outline,
                message: _errorMessage!,
                actionLabel: AppLocalizations.commonRetry,
                onAction: _reloadPage,
                tone: _LoginTone.error(context),
              ),

            // WebView — SizedBox.expand ensures WebView2 gets explicit dimensions on Windows
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.only(
                    bottomLeft: AppRadius.borderRadius.dialog.bottomLeft,
                    bottomRight: AppRadius.borderRadius.dialog.bottomRight,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.only(
                    bottomLeft: AppRadius.borderRadius.dialog.bottomLeft,
                    bottomRight: AppRadius.borderRadius.dialog.bottomRight,
                  ),
                  child: SizedBox.expand(
                    child: _webViewController.buildWidget(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Defines the marker-cookie spec for a platform. Either ANY of
/// [anyOf] or ALL of [allOf] must be present in the captured cookie
/// set for the platform to be considered authenticated. Per
/// Chairman + Codex Decision Package 2026-05-21.
///
/// YT uses `anyOf` because Google ships different SID variants
/// (cookie set varies by region + browser). FB/IG/X use `allOf`
/// because each platform has a canonical auth-pair that is always
/// present together when logged in.
class AuthMarkerSpec {
  final Set<String>? anyOf;
  final Set<String>? allOf;
  const AuthMarkerSpec({this.anyOf, this.allOf});

  bool matches(Set<String> captured) {
    if (anyOf != null) {
      return anyOf!.any(captured.contains);
    }
    if (allOf != null) {
      return allOf!.every(captured.contains);
    }
    return false;
  }
}

class _LoginNotice extends StatelessWidget {
  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final _LoginTone tone;

  const _LoginNotice({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.smMd,
      ),
      decoration: BoxDecoration(
        color: tone.container,
        border: Border(bottom: BorderSide(color: tone.border)),
      ),
      child: Row(
        children: [
          Icon(icon, color: tone.accent, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tone.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _LoginTone {
  final Color accent;
  final Color container;
  final Color border;
  final Color text;

  const _LoginTone({
    required this.accent,
    required this.container,
    required this.border,
    required this.text,
  });

  factory _LoginTone.brand(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _LoginTone(
      accent: cs.primary,
      container: cs.primary.withValues(alpha: isDark ? 0.16 : 0.08),
      border: cs.primary.withValues(alpha: isDark ? 0.28 : 0.18),
      text: cs.onSurface,
    );
  }

  factory _LoginTone.info(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColors.info(context);
    return _LoginTone(
      accent: accent,
      container: accent.withValues(alpha: isDark ? 0.14 : 0.08),
      border: accent.withValues(alpha: isDark ? 0.26 : 0.16),
      text: cs.onSurface,
    );
  }

  factory _LoginTone.success(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColors.success(context);
    return _LoginTone(
      accent: accent,
      container: accent.withValues(alpha: isDark ? 0.15 : 0.09),
      border: accent.withValues(alpha: isDark ? 0.30 : 0.20),
      text: cs.onSurface,
    );
  }

  factory _LoginTone.error(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _LoginTone(
      accent: cs.error,
      container: cs.errorContainer.withValues(alpha: isDark ? 0.42 : 1),
      border: cs.error.withValues(alpha: isDark ? 0.30 : 0.20),
      text: cs.onErrorContainer,
    );
  }
}

/// Helper function to show platform login dialog
/// Returns true if login was successful, false if cancelled
Future<bool> showPlatformLoginDialog({
  required BuildContext context,
  required String platform,
  required String loginUrl,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder:
        (context) =>
            PlatformLoginDialog(platform: platform, loginUrl: loginUrl),
  );
  return result ?? false;
}
