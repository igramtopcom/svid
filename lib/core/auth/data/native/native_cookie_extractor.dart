import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as iaw;

import '../../../config/brand_config.dart';
import '../../../services/webview_environment_service.dart';

/// Native cookie data from platform
class NativeCookie {
  final String name;
  final String value;
  final String domain;
  final String path;
  final DateTime? expiresDate;
  final bool isSecure;
  final bool isHttpOnly;
  final bool isSessionOnly;

  NativeCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    this.expiresDate,
    required this.isSecure,
    required this.isHttpOnly,
    required this.isSessionOnly,
  });

  factory NativeCookie.fromMap(Map<dynamic, dynamic> map) {
    final expiresTimestamp = map['expiresDate'] as num?;

    return NativeCookie(
      name: map['name'] as String? ?? '',
      value: map['value'] as String? ?? '',
      domain: map['domain'] as String? ?? '',
      path: map['path'] as String? ?? '/',
      expiresDate: _dateTimeFromCookieExpires(expiresTimestamp),
      isSecure: map['isSecure'] as bool? ?? false,
      isHttpOnly: map['isHttpOnly'] as bool? ?? false,
      isSessionOnly: map['isSessionOnly'] as bool? ?? false,
    );
  }

  /// Cookie APIs are inconsistent here:
  ///
  /// - WKHTTPCookieStore/native map values have historically arrived as Unix
  ///   seconds.
  /// - flutter_inappwebview's WebView2 CookieManager also returns a Unix
  ///   seconds value, despite the Dart field name being `expiresDate`.
  ///
  /// Treat sub-1e12 values as seconds and larger values as milliseconds. The
  /// previous Windows path interpreted seconds as milliseconds, writing 1970
  /// expirations to Netscape files; yt-dlp then discarded all Google auth
  /// cookies and reported "Sign in to confirm you're not a bot".
  static DateTime? _dateTimeFromCookieExpires(num? raw) {
    if (raw == null || raw <= 0) return null;
    final millis = raw < 1000000000000 ? raw * 1000 : raw;
    return DateTime.fromMillisecondsSinceEpoch(millis.round());
  }

  /// Convert to Netscape cookie format line
  /// Format: domain\tinclude_subdomains\tpath\tsecure\texpiration\tname\tvalue
  String toNetscapeLine() {
    final includeSubdomains = domain.startsWith('.') ? 'TRUE' : 'FALSE';
    final secure = isSecure ? 'TRUE' : 'FALSE';
    final expiration =
        expiresDate != null
            ? (expiresDate!.millisecondsSinceEpoch ~/ 1000)
            : (DateTime.now()
                    .add(const Duration(days: 365))
                    .millisecondsSinceEpoch ~/
                1000);

    return '$domain\t$includeSubdomains\t$path\t$secure\t$expiration\t$name\t$value';
  }

  @override
  String toString() =>
      'NativeCookie($name=$value, domain=$domain, httpOnly=$isHttpOnly)';
}

/// Extracts cookies using native platform APIs
/// This allows access to HttpOnly cookies that JavaScript cannot read
class NativeCookieExtractor {
  static final _channel = MethodChannel(
    '${BrandConfig.current.methodChannelPrefix}/native_cookies',
  );

  /// Check if native cookie extraction is supported on this platform
  /// macOS: WKHTTPCookieStore via method channel
  /// Windows: InAppWebView CookieManager (WebView2)
  static bool get isSupported => Platform.isMacOS || Platform.isWindows;

  /// Get all cookies from the WebView data store
  /// Returns empty list on unsupported platforms
  static Future<List<NativeCookie>> getAllCookies() async {
    if (!isSupported) {
      debugPrint('[NativeCookie] Platform not supported, returning empty list');
      return [];
    }

    if (Platform.isWindows) {
      // Windows: use InAppWebView CookieManager
      debugPrint(
        '[NativeCookie] Windows: getAllCookies not supported (use getCookiesForDomain)',
      );
      return [];
    }

    try {
      final result = await _channel.invokeMethod('getAllCookies');
      if (result == null) return [];

      final cookies =
          (result as List).map((e) => NativeCookie.fromMap(e as Map)).toList();

      debugPrint('[NativeCookie] Got ${cookies.length} cookies from native');
      return cookies;
    } on PlatformException catch (e) {
      debugPrint('[NativeCookie] Platform error: ${e.message}');
      return [];
    } catch (e) {
      debugPrint('[NativeCookie] Error getting cookies: $e');
      return [];
    }
  }

  /// Get cookies for a specific domain
  /// Includes subdomains (e.g., domain "youtube.com" matches ".youtube.com")
  static Future<List<NativeCookie>> getCookiesForDomain(String domain) async {
    if (!isSupported) {
      debugPrint('[NativeCookie] Platform not supported');
      return [];
    }

    if (Platform.isWindows) {
      return _getWindowsCookiesForDomain(domain);
    }

    try {
      final result = await _channel.invokeMethod('getCookiesForDomain', {
        'domain': domain,
      });
      if (result == null) return [];

      final cookies =
          (result as List).map((e) => NativeCookie.fromMap(e as Map)).toList();

      debugPrint(
        '[NativeCookie] Got ${cookies.length} cookies for domain $domain',
      );

      // Log HttpOnly cookies specifically
      final httpOnlyCookies = cookies.where((c) => c.isHttpOnly).toList();
      if (httpOnlyCookies.isNotEmpty) {
        debugPrint(
          '[NativeCookie] Found ${httpOnlyCookies.length} HttpOnly cookies: '
          '${httpOnlyCookies.map((c) => c.name).join(", ")}',
        );
      }

      return cookies;
    } on PlatformException catch (e) {
      debugPrint('[NativeCookie] Platform error: ${e.message}');
      return [];
    } catch (e) {
      debugPrint('[NativeCookie] Error getting cookies for domain: $e');
      return [];
    }
  }

  /// Windows-specific cookie extraction via InAppWebView CookieManager (WebView2)
  static Future<List<NativeCookie>> _getWindowsCookiesForDomain(
    String domain,
  ) async {
    try {
      final cookieManager = iaw.CookieManager.instance(
        webViewEnvironment: WebViewEnvironmentService.instance,
      );
      final url = iaw.WebUri('https://$domain/');
      final cookies = await cookieManager.getCookies(url: url);

      final nativeCookies =
          cookies
              .map(
                (c) => NativeCookie(
                  name: c.name,
                  value: c.value?.toString() ?? '',
                  domain: c.domain ?? '.$domain',
                  path: c.path ?? '/',
                  expiresDate: NativeCookie._dateTimeFromCookieExpires(
                    c.expiresDate,
                  ),
                  isSecure: c.isSecure ?? false,
                  isHttpOnly: c.isHttpOnly ?? false,
                  isSessionOnly: c.expiresDate == null,
                ),
              )
              .toList();

      debugPrint(
        '[NativeCookie] Windows: Got ${nativeCookies.length} cookies for $domain',
      );

      final httpOnlyCookies = nativeCookies.where((c) => c.isHttpOnly).toList();
      if (httpOnlyCookies.isNotEmpty) {
        debugPrint(
          '[NativeCookie] Windows: Found ${httpOnlyCookies.length} HttpOnly cookies: '
          '${httpOnlyCookies.map((c) => c.name).join(", ")}',
        );
      }

      return nativeCookies;
    } catch (e) {
      debugPrint(
        '[NativeCookie] Windows: Error getting cookies for $domain: $e',
      );
      return [];
    }
  }

  /// Clear all cookies from the WebView data store
  static Future<bool> clearCookies() async {
    if (!isSupported) return false;

    if (Platform.isWindows) {
      try {
        final cookieManager = iaw.CookieManager.instance(
          webViewEnvironment: WebViewEnvironmentService.instance,
        );
        await cookieManager.deleteAllCookies();
        return true;
      } catch (e) {
        debugPrint('[NativeCookie] Windows: Error clearing cookies: $e');
        return false;
      }
    }

    try {
      final result = await _channel.invokeMethod('clearCookies');
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('[NativeCookie] Error clearing cookies: $e');
      return false;
    }
  }

  /// Debug: Get ALL cookies from ALL sources
  /// Returns cookies with source info (WKWebsiteDataStore vs HTTPCookieStorage)
  static Future<List<NativeCookie>> debugGetAllCookies() async {
    if (!isSupported) return [];
    if (Platform.isWindows) return []; // Windows: use getCookiesForDomain

    try {
      final result = await _channel.invokeMethod('debugGetAllCookies');
      if (result == null) return [];

      final cookies =
          (result as List).map((e) => NativeCookie.fromMap(e as Map)).toList();

      // Log by domain for debugging
      final byDomain = <String, int>{};
      for (final c in cookies) {
        byDomain[c.domain] = (byDomain[c.domain] ?? 0) + 1;
      }
      debugPrint('[NativeCookie] DEBUG All cookies by domain: $byDomain');

      // Log auth cookies specifically
      final authNames = [
        'SID',
        'HSID',
        'SSID',
        'LOGIN_INFO',
        'SAPISID',
        '__Secure-1PSID',
        'c_user',
        'xs',
      ];
      final authCookies =
          cookies.where((c) => authNames.contains(c.name)).toList();
      if (authCookies.isNotEmpty) {
        debugPrint(
          '[NativeCookie] DEBUG Auth cookies found: ${authCookies.map((c) => "${c.name}@${c.domain}").join(", ")}',
        );
      } else {
        debugPrint('[NativeCookie] DEBUG No auth cookies found in any store!');
      }

      return cookies;
    } catch (e) {
      debugPrint('[NativeCookie] Error in debugGetAllCookies: $e');
      return [];
    }
  }

  /// Convert cookies to Netscape format string for yt-dlp
  static String cookiesToNetscapeFormat(List<NativeCookie> cookies) {
    final buffer = StringBuffer();
    buffer.writeln('# Netscape HTTP Cookie File');
    buffer.writeln('# https://curl.haxx.se/docs/http-cookies.html');
    buffer.writeln(
      '# This file was generated by ${BrandConfig.current.appName} (native). Do not edit.',
    );
    buffer.writeln();

    for (final cookie in cookies) {
      if (cookie.name.isEmpty || cookie.value.isEmpty) continue;
      buffer.writeln(cookie.toNetscapeLine());
    }

    return buffer.toString();
  }

  /// Get the primary domain for a platform
  static String getPlatformDomain(String platform) {
    switch (platform.toLowerCase()) {
      case 'youtube':
        return 'youtube.com';
      case 'instagram':
        return 'instagram.com';
      case 'facebook':
        return 'facebook.com';
      case 'tiktok':
        return 'tiktok.com';
      case 'twitter':
      case 'x':
        return 'twitter.com';
      case 'reddit':
        return 'reddit.com';
      case 'pinterest':
        return 'pinterest.com';
      default:
        return '$platform.com';
    }
  }
}
