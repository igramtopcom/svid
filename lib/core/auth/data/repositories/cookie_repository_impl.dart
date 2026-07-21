import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/errors/result.dart';
import '../../domain/entities/platform_cookie.dart';
import '../../domain/repositories/cookie_repository.dart';

/// Implementation of CookieRepository using SharedPreferences
class CookieRepositoryImpl implements CookieRepository {
  final SharedPreferences _prefs;

  // Key prefix for storing cookies
  static const String _cookiePrefix = 'platform_cookie_';
  static const String _expiryPrefix = 'platform_cookie_expiry_';
  static const String _savedAtPrefix = 'platform_cookie_saved_';
  static const String _platformsKey = 'platform_cookies_list';

  CookieRepositoryImpl(this._prefs);

  @override
  Future<Result<void>> saveCookies({
    required String platform,
    required String cookieString,
    DateTime? expiresAt,
  }) async {
    try {
      final normalizedPlatform = platform.toLowerCase();

      // Save cookie string
      await _prefs.setString('$_cookiePrefix$normalizedPlatform', cookieString);

      // Save saved timestamp
      await _prefs.setString(
        '$_savedAtPrefix$normalizedPlatform',
        DateTime.now().toIso8601String(),
      );

      // Save expiry if provided
      if (expiresAt != null) {
        await _prefs.setString(
          '$_expiryPrefix$normalizedPlatform',
          expiresAt.toIso8601String(),
        );
      }

      // Add platform to list of platforms with cookies
      await _addPlatformToList(normalizedPlatform);

      return Result.success(null);
    } catch (e) {
      return Result.failure(Exception('Failed to save cookies: $e'));
    }
  }

  @override
  Future<Result<PlatformCookie?>> getCookies(String platform) async {
    try {
      final normalizedPlatform = platform.toLowerCase();

      // Keep the in-memory SharedPreferences cache in sync with the platform
      // store. Login capture and extraction retry can happen back-to-back on
      // Windows, and stale cached cookies cause yt-dlp to receive anonymous
      // cookies even after native WebView2 extraction saved auth cookies.
      await _prefs.reload();

      final cookieString = _prefs.getString(
        '$_cookiePrefix$normalizedPlatform',
      );

      if (cookieString == null) {
        return Result.success(null);
      }

      final savedAtStr = _prefs.getString('$_savedAtPrefix$normalizedPlatform');
      final expiresAtStr = _prefs.getString(
        '$_expiryPrefix$normalizedPlatform',
      );

      final savedAt =
          savedAtStr != null
              ? DateTime.tryParse(savedAtStr) ?? DateTime.now()
              : DateTime.now();

      final expiresAt =
          expiresAtStr != null ? DateTime.tryParse(expiresAtStr) : null;

      final cookie = PlatformCookie(
        platform: normalizedPlatform,
        cookieString: cookieString,
        savedAt: savedAt,
        expiresAt: expiresAt,
      );

      return Result.success(cookie);
    } catch (e) {
      return Result.failure(Exception('Failed to get cookies: $e'));
    }
  }

  @override
  Future<Result<List<PlatformCookie>>> getAllCookies() async {
    try {
      await _prefs.reload();

      final platformsStr = _prefs.getString(_platformsKey);
      if (platformsStr == null || platformsStr.isEmpty) {
        return Result.success([]);
      }

      final platforms = platformsStr.split(',');
      final List<PlatformCookie> cookies = [];

      for (final platform in platforms) {
        final result = await getCookies(platform);
        if (result.isSuccess && result.dataOrNull != null) {
          final cookie = result.dataOrNull!;
          // Filter out expired cookies
          if (!cookie.isExpired) {
            cookies.add(cookie);
          }
        }
      }

      return Result.success(cookies);
    } catch (e) {
      return Result.failure(Exception('Failed to get all cookies: $e'));
    }
  }

  @override
  Future<Result<bool>> hasCookies(String platform) async {
    try {
      final normalizedPlatform = platform.toLowerCase();
      await _prefs.reload();

      final cookieString = _prefs.getString(
        '$_cookiePrefix$normalizedPlatform',
      );
      return Result.success(cookieString != null);
    } catch (e) {
      return Result.failure(Exception('Failed to check cookies: $e'));
    }
  }

  @override
  Future<Result<void>> removeCookies(String platform) async {
    try {
      final normalizedPlatform = platform.toLowerCase();

      await _prefs.remove('$_cookiePrefix$normalizedPlatform');
      await _prefs.remove('$_savedAtPrefix$normalizedPlatform');
      await _prefs.remove('$_expiryPrefix$normalizedPlatform');

      await _removePlatformFromList(normalizedPlatform);

      return Result.success(null);
    } catch (e) {
      return Result.failure(Exception('Failed to remove cookies: $e'));
    }
  }

  @override
  Future<Result<int>> removeAllCookies() async {
    try {
      final allCookiesResult = await getAllCookies();
      if (!allCookiesResult.isSuccess) {
        return Result.failure(allCookiesResult.exceptionOrNull!);
      }

      final cookies = allCookiesResult.dataOrNull!;
      for (final cookie in cookies) {
        await removeCookies(cookie.platform);
      }

      await _prefs.remove(_platformsKey);

      return Result.success(cookies.length);
    } catch (e) {
      return Result.failure(Exception('Failed to remove all cookies: $e'));
    }
  }

  @override
  Future<Result<String?>> getCookieString(String platform) async {
    try {
      final result = await getCookies(platform);
      if (!result.isSuccess || result.dataOrNull == null) {
        return Result.success(null);
      }

      final cookie = result.dataOrNull!;

      // Check if expired
      if (cookie.isExpired) {
        await removeCookies(platform);
        return Result.success(null);
      }

      return Result.success(cookie.cookieString);
    } catch (e) {
      return Result.failure(Exception('Failed to get cookie string: $e'));
    }
  }

  // Helper: Add platform to list
  Future<void> _addPlatformToList(String platform) async {
    final platformsStr = _prefs.getString(_platformsKey);
    final platforms =
        platformsStr != null && platformsStr.isNotEmpty
            ? platformsStr.split(',').toSet()
            : <String>{};

    platforms.add(platform);

    await _prefs.setString(_platformsKey, platforms.join(','));
  }

  // Helper: Remove platform from list
  Future<void> _removePlatformFromList(String platform) async {
    final platformsStr = _prefs.getString(_platformsKey);
    if (platformsStr == null) return;

    final platforms = platformsStr.split(',').toSet();
    platforms.remove(platform);

    if (platforms.isEmpty) {
      await _prefs.remove(_platformsKey);
    } else {
      await _prefs.setString(_platformsKey, platforms.join(','));
    }
  }
}
