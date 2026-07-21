import '../../../errors/result.dart';
import '../../../logging/app_logger.dart';
import '../entities/platform_cookie.dart';
import '../repositories/cookie_repository.dart';

/// Use case for getting all platform cookies
class GetAllPlatformCookiesUseCase {
  final CookieRepository _repository;

  GetAllPlatformCookiesUseCase(this._repository);

  Future<Result<List<PlatformCookie>>> call() async {
    try {
      appLogger.debug('🔍 Getting all platform cookies');

      final result = await _repository.getAllCookies();

      if (result.isSuccess) {
        final validCookies = result.dataOrNull!.where((c) => c.isValid).toList();
        appLogger.debug('✅ Found ${validCookies.length} valid cookies');
        return Result.success(validCookies);
      }

      return result;
    } catch (e) {
      appLogger.error('❌ Exception getting all cookies: $e');
      return Result.failure(Exception('Failed to get all cookies: $e'));
    }
  }
}
