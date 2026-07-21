import '../../../errors/result.dart';
import '../../../logging/app_logger.dart';
import '../entities/platform_cookie.dart';
import '../repositories/cookie_repository.dart';

/// Use case for getting platform cookies
class GetPlatformCookiesUseCase {
  final CookieRepository _repository;

  GetPlatformCookiesUseCase(this._repository);

  Future<Result<PlatformCookie?>> call(String platform) async {
    try {
      appLogger.debug('🔍 Getting cookies for platform: $platform');

      if (platform.isEmpty) {
        return Result.failure(Exception('Platform cannot be empty'));
      }

      final result = await _repository.getCookies(platform);

      if (result.isSuccess && result.dataOrNull != null) {
        if (result.dataOrNull!.isExpired) {
          appLogger.warning('⚠️ Cookies expired for $platform');
          // Remove expired cookies
          await _repository.removeCookies(platform);
          return Result.success(null);
        }
        appLogger.debug('✅ Found cookies for $platform');
      } else {
        appLogger.debug('ℹ️ No cookies found for $platform');
      }

      return result;
    } catch (e) {
      appLogger.error('❌ Exception getting cookies: $e');
      return Result.failure(Exception('Failed to get cookies: $e'));
    }
  }
}
