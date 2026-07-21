import '../../../errors/result.dart';
import '../../../logging/app_logger.dart';
import '../repositories/cookie_repository.dart';

/// Use case for getting cookie string for yt-dlp
class GetCookieStringUseCase {
  final CookieRepository _repository;

  GetCookieStringUseCase(this._repository);

  Future<Result<String?>> call(String platform) async {
    try {
      appLogger.debug('🍪 Getting cookie string for platform: $platform');

      if (platform.isEmpty) {
        return Result.failure(Exception('Platform cannot be empty'));
      }

      final result = await _repository.getCookieString(platform);

      if (result.isSuccess && result.dataOrNull != null) {
        appLogger.debug('✅ Cookie string ready for $platform');
      } else {
        appLogger.debug('ℹ️ No valid cookies for $platform');
      }

      return result;
    } catch (e) {
      appLogger.error('❌ Exception getting cookie string: $e');
      return Result.failure(Exception('Failed to get cookie string: $e'));
    }
  }
}
