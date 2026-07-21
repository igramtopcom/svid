import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../errors/result.dart';
import '../../data/repositories/cookie_repository_impl.dart';
import '../../domain/entities/platform_cookie.dart';
import '../../domain/repositories/cookie_repository.dart';
import '../../domain/usecases/save_platform_cookies_usecase.dart';
import '../../domain/usecases/get_platform_cookies_usecase.dart';
import '../../domain/usecases/get_all_platform_cookies_usecase.dart';
import '../../domain/usecases/remove_platform_cookies_usecase.dart';
import '../../domain/usecases/remove_all_platform_cookies_usecase.dart';
import '../../domain/usecases/get_cookie_string_usecase.dart';
import '../../../../features/settings/presentation/providers/settings_provider.dart';

// ==================== REPOSITORY ====================

/// Provider for cookie repository
final cookieRepositoryProvider = Provider<CookieRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return CookieRepositoryImpl(prefs);
});

// ==================== USE CASES ====================

/// Provider for save platform cookies use case
final savePlatformCookiesUseCaseProvider = Provider<SavePlatformCookiesUseCase>((ref) {
  final repository = ref.watch(cookieRepositoryProvider);
  return SavePlatformCookiesUseCase(repository);
});

/// Provider for get platform cookies use case
final getPlatformCookiesUseCaseProvider = Provider<GetPlatformCookiesUseCase>((ref) {
  final repository = ref.watch(cookieRepositoryProvider);
  return GetPlatformCookiesUseCase(repository);
});

/// Provider for get all platform cookies use case
final getAllPlatformCookiesUseCaseProvider = Provider<GetAllPlatformCookiesUseCase>((ref) {
  final repository = ref.watch(cookieRepositoryProvider);
  return GetAllPlatformCookiesUseCase(repository);
});

/// Provider for remove platform cookies use case
final removePlatformCookiesUseCaseProvider = Provider<RemovePlatformCookiesUseCase>((ref) {
  final repository = ref.watch(cookieRepositoryProvider);
  return RemovePlatformCookiesUseCase(repository);
});

/// Provider for remove all platform cookies use case
final removeAllPlatformCookiesUseCaseProvider = Provider<RemoveAllPlatformCookiesUseCase>((ref) {
  final repository = ref.watch(cookieRepositoryProvider);
  return RemoveAllPlatformCookiesUseCase(repository);
});

/// Provider for get cookie string use case
final getCookieStringUseCaseProvider = Provider<GetCookieStringUseCase>((ref) {
  final repository = ref.watch(cookieRepositoryProvider);
  return GetCookieStringUseCase(repository);
});

// ==================== STATE PROVIDERS ====================

/// FutureProvider for all platform cookies (prevents FutureBuilder memory leak)
final allPlatformCookiesProvider = FutureProvider<List<PlatformCookie>>((ref) async {
  final getAllCookiesUseCase = ref.watch(getAllPlatformCookiesUseCaseProvider);
  final result = await getAllCookiesUseCase();
  return result.dataOrNull ?? [];
});
