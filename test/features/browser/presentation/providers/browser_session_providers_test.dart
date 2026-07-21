import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ssvid/core/auth/domain/entities/platform_cookie.dart';
import 'package:ssvid/core/auth/domain/repositories/cookie_repository.dart';
import 'package:ssvid/core/auth/domain/usecases/get_platform_cookies_usecase.dart';
import 'package:ssvid/core/auth/presentation/providers/auth_providers.dart';
import 'package:ssvid/core/errors/result.dart';
import 'package:ssvid/core/utils/platform_detector.dart';
import 'package:ssvid/features/browser/domain/services/cookie_inspector_service.dart';
import 'package:ssvid/features/browser/domain/services/video_url_detector.dart';
import 'package:ssvid/features/browser/presentation/providers/browser_providers.dart';
import 'package:ssvid/features/browser/presentation/providers/browser_session_providers.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _makeNetscapeCookie(String name, String value, {int? expiresAt}) {
  final exp = expiresAt ??
      (DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/
          1000);
  return '.youtube.com\tTRUE\t/\tTRUE\t$exp\t$name\t$value';
}

String _makeNetscapeCookieForDomain(
  String domain,
  String name,
  String value, {
  int? expiresAt,
}) {
  final exp = expiresAt ??
      (DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/
          1000);
  return '$domain\tTRUE\t/\tTRUE\t$exp\t$name\t$value';
}

PlatformCookie _makePlatformCookie(
  String platform,
  String cookieString,
) {
  return PlatformCookie(
    platform: platform,
    cookieString: cookieString,
    savedAt: DateTime(2026),
  );
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeCookieRepository implements CookieRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeGetPlatformCookiesUseCase extends GetPlatformCookiesUseCase {
  Result<PlatformCookie?> resultToReturn = const Result.success(null);

  _FakeGetPlatformCookiesUseCase() : super(_FakeCookieRepository());

  @override
  Future<Result<PlatformCookie?>> call(String platform) async {
    return resultToReturn;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('cookieInspectorServiceProvider', () {
    test('returns a CookieInspectorService instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(cookieInspectorServiceProvider);
      expect(service, isA<CookieInspectorService>());
    });
  });

  group('browserSessionHealthProvider', () {
    test('returns null when no video detection is active', () async {
      final container = ProviderContainer(
        overrides: [
          browserVideoDetectionProvider.overrideWith((_) => null),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(browserSessionHealthProvider.future);
      expect(result, isNull);
    });

    test('returns null for unknown platform', () async {
      final container = ProviderContainer(
        overrides: [
          browserVideoDetectionProvider.overrideWith((_) =>
              const VideoUrlDetection(
                isVideoPage: false,
                url: 'https://example.com',
                platform: VideoPlatform.unknown,
              )),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(browserSessionHealthProvider.future);
      expect(result, isNull);
    });

    test('returns unhealthy summary when platform has no cookies (failure)',
        () async {
      final fakeUseCase = _FakeGetPlatformCookiesUseCase()
        ..resultToReturn =
            Result.failure(Exception('No cookies'));

      final container = ProviderContainer(
        overrides: [
          browserVideoDetectionProvider.overrideWith((_) =>
              const VideoUrlDetection(
                isVideoPage: true,
                url: 'https://www.youtube.com/watch?v=abc',
                platform: VideoPlatform.youtube,
              )),
          getPlatformCookiesUseCaseProvider.overrideWithValue(fakeUseCase),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(browserSessionHealthProvider.future);
      expect(result, isNotNull);
      expect(result!.platform, 'youtube');
      expect(result.totalCookies, 0);
      expect(result.authCookieCount, 0);
      expect(result.isHealthy, isFalse);
    });

    test('returns unhealthy summary when cookies result is success(null)',
        () async {
      final fakeUseCase = _FakeGetPlatformCookiesUseCase()
        ..resultToReturn = const Result.success(null);

      final container = ProviderContainer(
        overrides: [
          browserVideoDetectionProvider.overrideWith((_) =>
              const VideoUrlDetection(
                isVideoPage: true,
                url: 'https://www.youtube.com/watch?v=abc',
                platform: VideoPlatform.youtube,
              )),
          getPlatformCookiesUseCaseProvider.overrideWithValue(fakeUseCase),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(browserSessionHealthProvider.future);
      expect(result, isNotNull);
      expect(result!.platform, 'youtube');
      expect(result.totalCookies, 0);
      expect(result.isHealthy, isFalse);
    });

    test('returns valid summary when cookies exist', () async {
      final cookieString = [
        _makeNetscapeCookie('SID', 'abc123'),
        _makeNetscapeCookie('HSID', 'def456'),
        _makeNetscapeCookie('PREF', 'hl=en'),
      ].join('\n');

      final fakeUseCase = _FakeGetPlatformCookiesUseCase()
        ..resultToReturn = Result.success(
          _makePlatformCookie('youtube', cookieString),
        );

      final container = ProviderContainer(
        overrides: [
          browserVideoDetectionProvider.overrideWith((_) =>
              const VideoUrlDetection(
                isVideoPage: true,
                url: 'https://www.youtube.com/watch?v=abc',
                platform: VideoPlatform.youtube,
              )),
          getPlatformCookiesUseCaseProvider.overrideWithValue(fakeUseCase),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(browserSessionHealthProvider.future);
      expect(result, isNotNull);
      expect(result!.platform, 'youtube');
      expect(result.totalCookies, 3);
      expect(result.authCookieCount, 2); // SID + HSID
      expect(result.isHealthy, isTrue);
    });
  });

  group('allSessionSummariesProvider', () {
    test('returns empty list when no cookies', () async {
      final container = ProviderContainer(
        overrides: [
          allPlatformCookiesProvider
              .overrideWith((_) async => <PlatformCookie>[]),
        ],
      );
      addTearDown(container.dispose);

      final result =
          await container.read(allSessionSummariesProvider.future);
      expect(result, isEmpty);
    });

    test('returns summaries for all platforms', () async {
      final ytCookies = [
        _makeNetscapeCookie('SID', 'abc'),
        _makeNetscapeCookie('PREF', 'hl=en'),
      ].join('\n');

      final igCookies = [
        _makeNetscapeCookieForDomain(
            '.instagram.com', 'sessionid', 'sess123'),
      ].join('\n');

      final container = ProviderContainer(
        overrides: [
          allPlatformCookiesProvider.overrideWith((_) async => [
                _makePlatformCookie('youtube', ytCookies),
                _makePlatformCookie('instagram', igCookies),
              ]),
        ],
      );
      addTearDown(container.dispose);

      final result =
          await container.read(allSessionSummariesProvider.future);
      expect(result, hasLength(2));
      expect(result[0].platform, 'youtube');
      expect(result[1].platform, 'instagram');
    });

    test('maps cookies to correct summaries per platform', () async {
      final ytCookies = [
        _makeNetscapeCookie('SID', 'abc'),
        _makeNetscapeCookie('HSID', 'def'),
        _makeNetscapeCookie('__Secure-1PSID', 'ghi'),
      ].join('\n');

      final redditCookies = [
        _makeNetscapeCookieForDomain(
            '.reddit.com', 'reddit_session', 'r_sess'),
        _makeNetscapeCookieForDomain('.reddit.com', 'theme', 'dark'),
      ].join('\n');

      final container = ProviderContainer(
        overrides: [
          allPlatformCookiesProvider.overrideWith((_) async => [
                _makePlatformCookie('youtube', ytCookies),
                _makePlatformCookie('reddit', redditCookies),
              ]),
        ],
      );
      addTearDown(container.dispose);

      final result =
          await container.read(allSessionSummariesProvider.future);
      expect(result, hasLength(2));

      // YouTube: 3 total, 3 auth (SID, HSID, __Secure-1PSID), healthy
      final ytSummary = result.firstWhere((s) => s.platform == 'youtube');
      expect(ytSummary.totalCookies, 3);
      expect(ytSummary.authCookieCount, 3);
      expect(ytSummary.isHealthy, isTrue);

      // Reddit: 2 total, 1 auth (reddit_session), healthy
      final redditSummary = result.firstWhere((s) => s.platform == 'reddit');
      expect(redditSummary.totalCookies, 2);
      expect(redditSummary.authCookieCount, 1);
      expect(redditSummary.isHealthy, isTrue);
    });
  });
}
