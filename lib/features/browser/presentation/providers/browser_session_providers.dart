import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/presentation/providers/auth_providers.dart';
import '../../../../core/errors/result.dart';
import '../../domain/services/cookie_inspector_service.dart';
import 'browser_providers.dart';

/// Provides a [CookieInspectorService] instance.
final cookieInspectorServiceProvider = Provider<CookieInspectorService>((ref) {
  return CookieInspectorService();
});

/// Session health summary for the platform matching the current browser URL.
///
/// Returns null when no video detection is active (e.g. on Google homepage).
final browserSessionHealthProvider =
    FutureProvider<CookieSessionSummary?>((ref) async {
  final detection = ref.watch(browserVideoDetectionProvider);
  if (detection == null) return null;

  final platform = detection.platform.toDbString();
  if (platform == 'unknown') return null;

  final getCookies = ref.read(getPlatformCookiesUseCaseProvider);
  final result = await getCookies(platform);
  if (!result.isSuccess || result.dataOrNull == null) {
    // No cookies → not logged in
    return CookieSessionSummary(
      platform: platform,
      totalCookies: 0,
      authCookieCount: 0,
      expiringSoonCount: 0,
      isHealthy: false,
    );
  }

  final cookie = result.dataOrNull!;
  final inspector = ref.read(cookieInspectorServiceProvider);
  final entries = inspector.parseCookies(cookie.cookieString);
  return inspector.summarize(platform, entries);
});

/// All session summaries across every platform with saved cookies.
final allSessionSummariesProvider =
    FutureProvider<List<CookieSessionSummary>>((ref) async {
  final cookies = await ref.watch(allPlatformCookiesProvider.future);
  final inspector = ref.read(cookieInspectorServiceProvider);

  return cookies
      .map((c) =>
          inspector.summarize(c.platform, inspector.parseCookies(c.cookieString)))
      .toList();
});
