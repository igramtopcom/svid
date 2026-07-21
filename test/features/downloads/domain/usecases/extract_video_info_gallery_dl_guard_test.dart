/// Regression tests for the `supportsGalleryDlFallback` platform guard.
///
/// History: commit `2d626617` ("skip gallery-dl on pure video") added a
/// `platform.supportsGalleryDlFallback` check around the gallery-dl
/// fallback inside `_extractWithYtdlp` — so a YouTube extraction
/// failure would not waste another ~60s timeout on a gallery-dl
/// attempt that is guaranteed to return exit 64 ("Unsupported URL").
/// The check was lost in the V2 reconcile merges (`b7b88a0b`,
/// `7cf8a5ae`) — the call sites reverted to `!skipGalleryDlFallback`
/// alone, and the helper `VideoPlatform.supportsGalleryDlFallback`
/// became dead code. On Windows the regression compounded with
/// Defender real-time scan + DPAPI cookie decrypt, making the
/// extra round-trip user-visible as slow extracts on failure.
///
/// These tests pin the contract restored by today's fix so the
/// guard cannot be silently dropped again on the next reconcile.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ssvid/core/errors/result.dart';
import 'package:ssvid/core/services/circuit_breaker_service.dart';
import 'package:ssvid/features/downloads/data/datasources/ytdlp_datasource.dart';
import 'package:ssvid/features/downloads/domain/usecases/extract_video_info_usecase.dart';
import 'package:ssvid/features/settings/domain/enums/download_engine.dart';

import '../../../../shared/mocks/mocks.dart';

void main() {
  // Initialize Flutter binding so `appLogger` and any plugin-backed
  // service we touch during the use case run can attach without the
  // "Binding has not yet been initialized" warnings that otherwise
  // noise the test output.
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSSvidApiService mockApi;
  late MockYtDlpDataSource mockYtdlp;
  late MockGalleryDlDataSource mockGalleryDl;
  late CircuitBreakerService circuitBreaker;
  late ExtractVideoInfoUseCase useCase;

  // URLs covering the YouTube variants the detector branches on:
  // youtube.com/watch, youtu.be short, music subdomain. If any of
  // these slips past the detector the guard regression returns; the
  // tests below catch the slip.
  const youtubeWatchUrl = 'https://www.youtube.com/watch?v=guardtest1';
  const youtubeShortUrl = 'https://youtu.be/guardtest2';
  const youtubeMusicUrl = 'https://music.youtube.com/watch?v=guardtest3';

  // Pure-video platforms (other than YouTube) — same guard applies.
  const vimeoUrl = 'https://vimeo.com/123456789';
  const soundcloudUrl = 'https://soundcloud.com/artist/track-name';

  // Image-capable platforms — guard must NOT block them; gallery-dl
  // is the whole point on Instagram / Pinterest / Reddit / Twitter
  // posts where yt-dlp cannot extract carousel images.
  const instagramUrl = 'https://www.instagram.com/p/CtestPostId/';
  const pinterestUrl = 'https://www.pinterest.com/pin/12345/';
  const redditUrl = 'https://www.reddit.com/r/test/comments/abc/post/';

  // `unknown` platform = URL the detector can't classify. Must
  // default to gallery-dl ALLOWED (defensive fallback for unknown
  // URLs — losing this would silently regress 3rd-party sources
  // that depend on gallery-dl's broad extractor catalogue).
  const unknownUrl = 'https://some-obscure-video-host.example/video/42';

  setUp(() {
    mockApi = MockSSvidApiService();
    mockYtdlp = MockYtDlpDataSource();
    mockGalleryDl = MockGalleryDlDataSource();
    circuitBreaker = CircuitBreakerService(
      failureThreshold: 3,
      cooldownDuration: const Duration(seconds: 60),
    );
    useCase = ExtractVideoInfoUseCase(
      mockApi,
      mockYtdlp,
      mockGalleryDl,
      circuitBreaker: circuitBreaker,
      // delay collapsed so rate-limit / cookies-from-browser retries
      // do not stall the test runner.
      delay: (_) async {},
    );
    when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
    when(() => mockGalleryDl.isAvailable()).thenAnswer((_) async => true);
  });

  /// Every yt-dlp call throws a generic network failure. This is the
  /// canonical "extract failed" entry into the gallery-dl fallback
  /// branch under `on YtDlpException catch (e)`.
  void stubYtdlpNetworkFailure() {
    when(
      () => mockYtdlp.extractInfo(
        any(),
        cookiesFile: any(named: 'cookiesFile'),
        cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
        proxyUrl: any(named: 'proxyUrl'),
        extractorClient: any(named: 'extractorClient'),
        timeoutSecs: any(named: 'timeoutSecs'),
      ),
    ).thenThrow(
      YtDlpException(
        YtDlpErrorType.networkError,
        'Network connection failed',
      ),
    );
  }

  /// Every yt-dlp call throws a generic Dart error (Exception, not
  /// `YtDlpException`). This routes into the `} catch (e, stack)`
  /// branch — the second guarded site Codex flagged.
  void stubYtdlpGenericFailure() {
    when(
      () => mockYtdlp.extractInfo(
        any(),
        cookiesFile: any(named: 'cookiesFile'),
        cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
        proxyUrl: any(named: 'proxyUrl'),
        extractorClient: any(named: 'extractorClient'),
        timeoutSecs: any(named: 'timeoutSecs'),
      ),
    ).thenThrow(Exception('unexpected error'));
  }

  /// gallery-dl is configured to throw if called — tests that expect
  /// the guard to BLOCK gallery-dl never trigger this. Tests that
  /// expect gallery-dl to fire stub it explicitly inside the test.
  void verifyGalleryDlNeverCalled() {
    verifyNever(
      () => mockGalleryDl.extractInfo(
        any(),
        cookiesFile: any(named: 'cookiesFile'),
      ),
    );
  }

  group('YouTube fail + gallery-dl available => guard blocks gallery-dl', () {
    test('youtube.com/watch URL routes via YtDlpException catch', () async {
      stubYtdlpNetworkFailure();
      await useCase(youtubeWatchUrl, engine: DownloadEngine.ytdlpOnly);
      verifyGalleryDlNeverCalled();
    });

    test('youtu.be short URL is also recognised as YouTube', () async {
      stubYtdlpNetworkFailure();
      await useCase(youtubeShortUrl, engine: DownloadEngine.ytdlpOnly);
      verifyGalleryDlNeverCalled();
    });

    test('music.youtube.com is also recognised as YouTube', () async {
      stubYtdlpNetworkFailure();
      await useCase(youtubeMusicUrl, engine: DownloadEngine.ytdlpOnly);
      verifyGalleryDlNeverCalled();
    });

    test('generic-catch branch also respects the guard', () async {
      // YouTube URL + non-YtDlpException error → enters the second
      // catch site. Pre-fix this site would call gallery-dl too;
      // post-fix it must respect the guard symmetrically.
      stubYtdlpGenericFailure();
      await useCase(youtubeWatchUrl, engine: DownloadEngine.ytdlpOnly);
      verifyGalleryDlNeverCalled();
    });
  });

  group('other pure-video platforms => guard blocks gallery-dl', () {
    test('Vimeo failure does not round-trip through gallery-dl', () async {
      stubYtdlpNetworkFailure();
      await useCase(vimeoUrl, engine: DownloadEngine.ytdlpOnly);
      verifyGalleryDlNeverCalled();
    });

    test('SoundCloud failure does not round-trip through gallery-dl',
        () async {
      stubYtdlpNetworkFailure();
      await useCase(soundcloudUrl, engine: DownloadEngine.ytdlpOnly);
      verifyGalleryDlNeverCalled();
    });

    // NOTE: TikTok is intentionally NOT covered here even though
    // its `supportsGalleryDlFallback` returns false — TikTok is also
    // in `_imageCapablePlatforms`, so the dispatcher races gallery-dl
    // in parallel BEFORE this guard ever runs. The guard inside
    // `_extractWithYtdlp` is correct (skips the sequential round-
    // trip), but a mock-based test can't distinguish "called via
    // parallel race" from "called via sequential fallback" without
    // additional spying infrastructure. The Vimeo + SoundCloud cases
    // above cover the pure-video × non-race intersection — the
    // exact shape of the regression the guard restores.
  });

  group('image-capable platforms => guard does NOT block gallery-dl', () {
    /// Stub gallery-dl to throw a clear failure too — the test does
    /// not care whether it succeeds; it only needs to verify the
    /// fallback was *attempted*. Throwing keeps the test cheap and
    /// lets us assert via `verify(...).called(N)`.
    void stubGalleryDlFailure() {
      when(
        () => mockGalleryDl.extractInfo(
          any(),
          cookiesFile: any(named: 'cookiesFile'),
        ),
      ).thenThrow(Exception('gallery-dl not authenticated'));
    }

    test('Instagram failure invokes gallery-dl', () async {
      stubYtdlpNetworkFailure();
      stubGalleryDlFailure();
      await useCase(instagramUrl, engine: DownloadEngine.ytdlpOnly);
      // Instagram races yt-dlp + gallery-dl in parallel for the
      // top-level dispatch (`_extractWithBothEngines`), AND the
      // ytdlp-only branch can also call gallery-dl as a sequential
      // fallback. Either way it must be invoked at least once for
      // the image-capable platform.
      verify(
        () => mockGalleryDl.extractInfo(
          any(),
          cookiesFile: any(named: 'cookiesFile'),
        ),
      ).called(greaterThanOrEqualTo(1));
    });

    test('Pinterest failure invokes gallery-dl', () async {
      stubYtdlpNetworkFailure();
      stubGalleryDlFailure();
      await useCase(pinterestUrl, engine: DownloadEngine.ytdlpOnly);
      verify(
        () => mockGalleryDl.extractInfo(
          any(),
          cookiesFile: any(named: 'cookiesFile'),
        ),
      ).called(greaterThanOrEqualTo(1));
    });

    test('Reddit failure invokes gallery-dl', () async {
      stubYtdlpNetworkFailure();
      stubGalleryDlFailure();
      await useCase(redditUrl, engine: DownloadEngine.ytdlpOnly);
      verify(
        () => mockGalleryDl.extractInfo(
          any(),
          cookiesFile: any(named: 'cookiesFile'),
        ),
      ).called(greaterThanOrEqualTo(1));
    });
  });

  group('unknown platform => guard preserves defensive fallback', () {
    test('unknown URL still invokes gallery-dl on failure', () async {
      // Defensive default: if the detector cannot classify the URL
      // we keep the gallery-dl round-trip because it is the only
      // option for 3rd-party / obscure sources. Losing this would
      // silently regress every non-mainstream URL.
      stubYtdlpNetworkFailure();
      when(
        () => mockGalleryDl.extractInfo(
          any(),
          cookiesFile: any(named: 'cookiesFile'),
        ),
      ).thenThrow(Exception('gallery-dl exit 64'));
      final result = await useCase(unknownUrl, engine: DownloadEngine.ytdlpOnly);
      verify(
        () => mockGalleryDl.extractInfo(
          any(),
          cookiesFile: any(named: 'cookiesFile'),
        ),
      ).called(greaterThanOrEqualTo(1));
      // Failure result is fine for this assertion — we are only
      // pinning that the round-trip WAS attempted.
      expect(result.isFailure, isTrue);
    });
  });

  // Codex round-2 audit (2026-05-09) flagged that the patch only
  // covered the two catch branches in `_extractWithYtdlp`, while the
  // third gallery-dl entry point — yt-dlp returns metadata but no
  // usable media formats (`_buildVideoInfoResult` → null) — still
  // round-tripped through gallery-dl on the strength of
  // `!skipGalleryDlFallback` alone. That branch is the canonical
  // YouTube "storyboards-only" symptom on machines where Deno is
  // missing or unhealthy (the very class of failure Phase B Deno
  // bundling is supposed to handle). These tests pin the third site
  // so the same regression cannot re-emerge through it.
  group(
      'YouTube returns empty formats => guard blocks gallery-dl no-formats path',
      () {
    /// yt-dlp "success" with no media formats — only a metadata
    /// envelope. `_buildVideoInfoResult` rejects this as null,
    /// which is the gate site we just guarded.
    void stubYtdlpEmptyFormats() {
      when(
        () => mockYtdlp.extractInfo(
          any(),
          cookiesFile: any(named: 'cookiesFile'),
          cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
          proxyUrl: any(named: 'proxyUrl'),
          extractorClient: any(named: 'extractorClient'),
          timeoutSecs: any(named: 'timeoutSecs'),
        ),
      ).thenAnswer((_) async => YtDlpVideoInfo(
            id: 'storyboards1',
            title: 'No formats',
            description: '',
            uploader: 'Test',
            platform: 'youtube',
            formats: const [],
          ));
    }

    test('youtube.com/watch + empty formats does NOT call gallery-dl',
        () async {
      stubYtdlpEmptyFormats();
      final result =
          await useCase(youtubeWatchUrl, engine: DownloadEngine.ytdlpOnly);
      verifyGalleryDlNeverCalled();
      expect(result.isFailure, isTrue);
    });

    test('youtu.be short + empty formats does NOT call gallery-dl', () async {
      stubYtdlpEmptyFormats();
      final result =
          await useCase(youtubeShortUrl, engine: DownloadEngine.ytdlpOnly);
      verifyGalleryDlNeverCalled();
      expect(result.isFailure, isTrue);
    });

    test('Vimeo + empty formats does NOT call gallery-dl', () async {
      stubYtdlpEmptyFormats();
      final result =
          await useCase(vimeoUrl, engine: DownloadEngine.ytdlpOnly);
      verifyGalleryDlNeverCalled();
      expect(result.isFailure, isTrue);
    });
  });

  group('return shape on YouTube failure (guard does not swallow error)',
      () {
    test('returns a Failure carrying the original yt-dlp error', () async {
      // The guard must only skip the gallery-dl detour; it must NOT
      // turn a failure into a silent success or strip the typed
      // error that downstream classifiers rely on.
      stubYtdlpNetworkFailure();
      final result =
          await useCase(youtubeWatchUrl, engine: DownloadEngine.ytdlpOnly);
      expect(result.isFailure, isTrue);
      // The guard preserves the typed `YtDlpException` from
      // `_extractWithYtdlp`'s `Result.failure(e)` rather than wrapping
      // it as `AppException.network(...)`. Downstream classifiers
      // (`_dispatchExtraction._classifySeverity`) rely on the typed
      // form so circuit-breaker severity routing stays on enum keys,
      // not fragile stderr substring matching.
      expect(result.exceptionOrNull, isA<YtDlpException>());
    });
  });
}
