import '../../../../core/errors/result.dart';
import '../entities/platform_cookie.dart';

/// Repository interface for platform cookie operations
abstract class CookieRepository {
  /// Save platform cookies
  Future<Result<void>> saveCookies({
    required String platform,
    required String cookieString,
    DateTime? expiresAt,
  });

  /// Get cookies for a specific platform
  Future<Result<PlatformCookie?>> getCookies(String platform);

  /// Get all saved platform cookies
  Future<Result<List<PlatformCookie>>> getAllCookies();

  /// Check if platform has saved cookies
  Future<Result<bool>> hasCookies(String platform);

  /// Remove cookies for a specific platform
  Future<Result<void>> removeCookies(String platform);

  /// Remove all platform cookies
  Future<Result<int>> removeAllCookies();

  /// Get cookie string for yt-dlp (formatted)
  Future<Result<String?>> getCookieString(String platform);
}
