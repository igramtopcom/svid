import '../../../errors/result.dart';
import '../../../logging/app_logger.dart';
import '../repositories/cookie_repository.dart';

/// Use case for removing all platform cookies
class RemoveAllPlatformCookiesUseCase {
  final CookieRepository _repository;

  RemoveAllPlatformCookiesUseCase(this._repository);

  Future<Result<int>> call() async {
    try {
      appLogger.info('🗑️ Removing all platform cookies');

      final result = await _repository.removeAllCookies();

      if (result.isSuccess) {
        final count = result.dataOrNull ?? 0;
        appLogger.info('✅ Removed $count platform cookies successfully');
      } else {
        appLogger.error('❌ Failed to remove all cookies: ${result.exceptionOrNull}');
      }

      return result;
    } catch (e) {
      appLogger.error('❌ Exception removing all cookies: $e');
      return Result.failure(Exception('Failed to remove all cookies: $e'));
    }
  }
}
