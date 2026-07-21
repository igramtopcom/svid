import '../../../errors/result.dart';
import '../../../logging/app_logger.dart';
import '../repositories/cookie_repository.dart';

/// Use case for saving platform cookies
class SavePlatformCookiesUseCase {
  final CookieRepository _repository;

  SavePlatformCookiesUseCase(this._repository);

  Future<Result<void>> call({
    required String platform,
    required String cookieString,
    DateTime? expiresAt,
  }) async {
    try {
      appLogger.info('💾 Saving cookies for platform: $platform');

      if (platform.isEmpty) {
        return Result.failure(Exception('Platform cannot be empty'));
      }

      if (cookieString.isEmpty) {
        return Result.failure(Exception('Cookie string cannot be empty'));
      }

      final result = await _repository.saveCookies(
        platform: platform,
        cookieString: cookieString,
        expiresAt: expiresAt,
      );

      if (result.isSuccess) {
        appLogger.info('✅ Cookies saved successfully for $platform');
      } else {
        appLogger.error('❌ Failed to save cookies: ${result.exceptionOrNull}');
      }

      return result;
    } catch (e) {
      appLogger.error('❌ Exception saving cookies: $e');
      return Result.failure(Exception('Failed to save cookies: $e'));
    }
  }
}
