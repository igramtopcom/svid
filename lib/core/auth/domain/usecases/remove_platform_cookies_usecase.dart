import '../../../errors/result.dart';
import '../../../logging/app_logger.dart';
import '../repositories/cookie_repository.dart';

/// Use case for removing platform cookies
class RemovePlatformCookiesUseCase {
  final CookieRepository _repository;

  RemovePlatformCookiesUseCase(this._repository);

  Future<Result<void>> call(String platform) async {
    try {
      appLogger.info('🗑️ Removing cookies for platform: $platform');

      if (platform.isEmpty) {
        return Result.failure(Exception('Platform cannot be empty'));
      }

      final result = await _repository.removeCookies(platform);

      if (result.isSuccess) {
        appLogger.info('✅ Cookies removed successfully for $platform');
      } else {
        appLogger.error('❌ Failed to remove cookies: ${result.exceptionOrNull}');
      }

      return result;
    } catch (e) {
      appLogger.error('❌ Exception removing cookies: $e');
      return Result.failure(Exception('Failed to remove cookies: $e'));
    }
  }
}
