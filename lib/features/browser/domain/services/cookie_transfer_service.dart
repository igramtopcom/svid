import '../../../../core/auth/domain/entities/platform_cookie.dart';
import '../../../../core/auth/domain/repositories/cookie_repository.dart';
import '../../../../core/config/brand_config.dart';

/// Service to export and import cookies for cross-device transfer.
///
/// Uses a brand-specific format with platform headers:
/// ```
/// # {AppName} Cookie Export v1
/// # Platform: youtube
/// .youtube.com	TRUE	/	TRUE	1234567890	SID	abc123
/// # Platform: instagram
/// .instagram.com	TRUE	/	TRUE	1234567890	sessionid	xyz789
/// ```
class CookieTransferService {
  final CookieRepository _cookieRepository;

  static String get _header => '# ${BrandConfig.current.appName} Cookie Export v1';
  static const _platformPrefix = '# Platform: ';

  CookieTransferService(this._cookieRepository);

  /// Export all platform cookies to a single shareable string.
  String exportAllCookies(List<PlatformCookie> cookies) {
    final buffer = StringBuffer();
    buffer.writeln(_header);
    buffer.writeln('# Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln();

    for (final cookie in cookies) {
      buffer.writeln('$_platformPrefix${cookie.platform}');
      buffer.writeln(cookie.cookieString);
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Import cookies from an export file string.
  /// Returns the list of platform names that were successfully imported.
  Future<List<String>> importCookies(String fileContent) async {
    if (!isValidExportFile(fileContent)) {
      return [];
    }

    final imported = <String>[];
    final lines = fileContent.split('\n');
    String? currentPlatform;
    final cookieLines = StringBuffer();

    for (final line in lines) {
      if (line.startsWith(_platformPrefix)) {
        // Save previous platform's cookies
        if (currentPlatform != null && cookieLines.isNotEmpty) {
          await _savePlatformCookies(currentPlatform, cookieLines.toString());
          imported.add(currentPlatform);
        }
        currentPlatform = line.substring(_platformPrefix.length).trim();
        cookieLines.clear();
      } else if (currentPlatform != null &&
          line.trim().isNotEmpty &&
          !line.startsWith('#')) {
        cookieLines.writeln(line);
      }
    }

    // Save last platform
    if (currentPlatform != null && cookieLines.isNotEmpty) {
      await _savePlatformCookies(currentPlatform, cookieLines.toString());
      imported.add(currentPlatform);
    }

    return imported;
  }

  /// Validate that the content is a valid cookie export file for this brand.
  bool isValidExportFile(String content) {
    final trimmed = content.trim();
    return trimmed.startsWith(_header) && trimmed.contains(_platformPrefix);
  }

  Future<void> _savePlatformCookies(
    String platform,
    String cookieString,
  ) async {
    final trimmed = cookieString.trim();
    if (trimmed.isEmpty) return;

    await _cookieRepository.saveCookies(
      platform: platform,
      cookieString: trimmed,
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );
  }
}
