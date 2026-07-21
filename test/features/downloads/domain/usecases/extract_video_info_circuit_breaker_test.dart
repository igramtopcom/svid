/// Regression tests for the circuit-breaker recording contract.
///
/// Bug history (2026-05-07):
///
/// **First bug** — counter conflation. The YouTube fallback chain (4
/// player clients) had per-yt-dlp-call recording → 1 user click was
/// counted as 4 failures, tripping the 3-failure threshold mid-chain.
/// Initial fix moved recording up to `_extractWithClientFallback`
/// outer.
///
/// **Second bug (this file's main coverage)** — the initial fix
/// over-corrected: only the YouTube path got recording. Non-YouTube
/// platforms (Vimeo, SoundCloud, Dailymotion, etc.) routed through
/// `_extractWithYtdlp` directly with NO recording, leaving the circuit
/// breaker INERT for ~80% of platforms. Image-capable platforms (IG,
/// Pinterest, Twitter, Reddit, TikTok, Facebook) had partial recording
/// (only on gallery-dl success). `_retryWithoutCookies` recovery path
/// also lost recording.
///
/// **Final fix** — single source of truth at `_dispatchExtraction`
/// outer wrapper. Every extraction (regardless of path: YouTube
/// fallback chain, image-capable parallel race, generic yt-dlp,
/// retry-without-cookies) records exactly once at the dispatcher
/// level. Severity classifier prefers typed `YtDlpErrorType` over
/// fragile string matching.
///
/// Tests cover: counter-conflation regression (YouTube), platform-
/// coverage regression (Vimeo + IG), severity classifier (typed +
/// stringified), recovery on success.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ssvid/core/services/circuit_breaker_service.dart';
import 'package:ssvid/features/downloads/data/datasources/ytdlp_datasource.dart';
import 'package:ssvid/features/downloads/domain/usecases/extract_video_info_usecase.dart';
import 'package:ssvid/features/settings/domain/enums/download_engine.dart';

import '../../../../shared/mocks/mocks.dart';

void main() {
  late MockSSvidApiService mockApi;
  late MockYtDlpDataSource mockYtdlp;
  late MockGalleryDlDataSource mockGalleryDl;
  late CircuitBreakerService circuitBreaker;
  late ExtractVideoInfoUseCase useCase;

  const youtubeUrl = 'https://www.youtube.com/watch?v=cbtest123';
  const vimeoUrl = 'https://vimeo.com/123456789';
  const instagramUrl = 'https://www.instagram.com/p/CtestPostId/';
  const soundcloudUrl = 'https://soundcloud.com/artist/track';

  setUp(() {
    mockApi = MockSSvidApiService();
    mockYtdlp = MockYtDlpDataSource();
    mockGalleryDl = MockGalleryDlDataSource();
    // Use a real circuit breaker so we observe its consecutiveFailures
    // counter directly via getState(), not through a mock spy.
    circuitBreaker = CircuitBreakerService(
      failureThreshold: 3,
      cooldownDuration: const Duration(seconds: 60),
    );
    useCase = ExtractVideoInfoUseCase(
      mockApi,
      mockYtdlp,
      mockGalleryDl,
      circuitBreaker: circuitBreaker,
      delay: (_) async {},
    );
    when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
    when(() => mockGalleryDl.isAvailable()).thenAnswer((_) async => false);
  });

  When<Future<YtDlpVideoInfo>> whenExtractInfo() => when(
        () => mockYtdlp.extractInfo(
          any(),
          cookiesFile: any(named: 'cookiesFile'),
          cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
          proxyUrl: any(named: 'proxyUrl'),
          extractorClient: any(named: 'extractorClient'),
          timeoutSecs: any(named: 'timeoutSecs'),
        ),
      );

  group('circuit breaker — counter conflation regression (P0)', () {
    test(
      'fallback chain with all 4 YouTube clients failing trips circuit only once, not 4 times',
      () async {
        // Every internal yt-dlp call throws a "platform-broken" error
        // (network failure — not user-induced). Pre-fix: 4 failures
        // recorded → circuit OPEN after 3rd. Post-fix: 1 failure
        // recorded → circuit still CLOSED (1 < threshold of 3).
        whenExtractInfo().thenThrow(
          YtDlpException(
            YtDlpErrorType.networkError,
            'Network connection failed',
          ),
        );

        // 1 user click — internally runs 4 fallback clients.
        await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);

        // CONTRACT: One logical extraction = at most one circuit-breaker
        // counter increment. With threshold=3, a single failed extraction
        // must NOT open the circuit.
        expect(circuitBreaker.getState('youtube'), CircuitBreakerState.closed,
            reason:
                'Single user click must not trip circuit (was: tripped via fallback chain inflation)');
      },
    );

    test(
      'three independent user clicks (each running full fallback chain) DO trip the circuit',
      () async {
        whenExtractInfo().thenThrow(
          YtDlpException(
            YtDlpErrorType.networkError,
            'Network connection failed',
          ),
        );

        // Three user-initiated extractions, each fully runs the chain.
        await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);
        await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);
        await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);

        // 3 user clicks × 1 record each = 3 failures → threshold trip.
        expect(circuitBreaker.getState('youtube'), CircuitBreakerState.open,
            reason:
                'Threshold of 3 failed user-initiated extractions must trip the circuit');
      },
    );

    test(
      'success path resets the circuit',
      () async {
        // First click fails — 1 counter increment.
        whenExtractInfo().thenThrow(
          YtDlpException(
            YtDlpErrorType.networkError,
            'Network connection failed',
          ),
        );
        await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);

        // Second click succeeds — counter resets.
        whenExtractInfo().thenAnswer((_) async => YtDlpVideoInfo(
              id: 'cbtest123',
              title: 'OK',
              description: '',
              uploader: 'X',
              platform: 'youtube',
              formats: [
                YtDlpFormat(
                    formatId: '137',
                    ext: 'mp4',
                    height: 1080,
                    width: 1920,
                    vcodec: 'avc1',
                    acodec: 'none'),
                YtDlpFormat(
                    formatId: '140',
                    ext: 'm4a',
                    vcodec: 'none',
                    acodec: 'mp4a'),
              ],
              isLive: false,
            ));
        await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);

        // Third click can fail twice in a row without tripping
        // (counter was reset by success).
        whenExtractInfo().thenThrow(
          YtDlpException(
            YtDlpErrorType.networkError,
            'Network connection failed',
          ),
        );
        await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);
        await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);

        expect(circuitBreaker.getState('youtube'), CircuitBreakerState.closed,
            reason:
                'Counter reset on success — only 2 fails since last success, below threshold');
      },
    );
  });

  group('circuit breaker — severity classifier (user-induced skip)', () {
    Future<void> assertUserInducedDoesNotTrip(String errorMessage) async {
      whenExtractInfo().thenThrow(
        YtDlpException(YtDlpErrorType.unknown, errorMessage),
      );

      // 5 attempts — way over the threshold of 3 — must NOT trip.
      for (var i = 0; i < 5; i++) {
        await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);
      }

      expect(
        circuitBreaker.getState('youtube'),
        CircuitBreakerState.closed,
        reason:
            'User-induced error "$errorMessage" must NOT count toward circuit',
      );
    }

    test(
      'cookies-required error ("Sign in to confirm") does not trip circuit',
      () async {
        // Real-world example from the diagnostic log on 2026-05-07.
        await assertUserInducedDoesNotTrip(
          "Sign in to confirm you're not a bot. Use --cookies-from-browser",
        );
      },
    );

    test(
      'format-not-available is treated as URL-specific (does not trip)',
      () async {
        await assertUserInducedDoesNotTrip(
          'Requested format is not available. Use --list-formats',
        );
      },
    );

    test(
      'video-private is URL-specific (does not trip)',
      () async {
        await assertUserInducedDoesNotTrip(
          'This video is private',
        );
      },
    );

    test(
      'geo-restricted is URL/account-specific (does not trip)',
      () async {
        await assertUserInducedDoesNotTrip(
          'Video not available in your country',
        );
      },
    );

    test(
      'circuit breaker rejection is not double-counted',
      () async {
        // Once the circuit IS open (via earlier failures), subsequent
        // requests throw `circuitBreakerOpen`. That message must not
        // re-record — would double-count and indefinitely extend the
        // cooldown.
        await assertUserInducedDoesNotTrip(
          'Circuit breaker open for youtube — cooldown 45s remaining',
        );
      },
    );

    test(
      'platform-broken errors (HTTP 5xx, network) DO trip after threshold',
      () async {
        whenExtractInfo().thenThrow(
          YtDlpException(YtDlpErrorType.networkError, 'HTTP 503 Service Unavailable'),
        );

        await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);
        await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);
        await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);

        expect(circuitBreaker.getState('youtube'), CircuitBreakerState.open,
            reason: 'Genuine platform-broken errors must still trip circuit');
      },
    );
  });

  // =========================================================================
  // Platform-coverage regression — protects against the fix moving recording
  // up to YouTube-only orchestrator and silently leaving other platforms
  // without circuit-breaker protection.
  // =========================================================================
  group('platform coverage — generic non-YouTube path (Vimeo/SoundCloud/etc)',
      () {
    test(
      'Vimeo: 3 platform-broken failures DO trip the circuit (not inert)',
      () async {
        whenExtractInfo().thenThrow(
          YtDlpException(YtDlpErrorType.networkError, 'HTTP 503'),
        );

        await useCase(vimeoUrl, engine: DownloadEngine.ytdlpOnly);
        await useCase(vimeoUrl, engine: DownloadEngine.ytdlpOnly);
        await useCase(vimeoUrl, engine: DownloadEngine.ytdlpOnly);

        expect(
          circuitBreaker.getState('vimeo'),
          CircuitBreakerState.open,
          reason:
              'Pre-fix bug: non-YouTube paths had NO circuit-breaker recording, '
              'so circuit could never trip regardless of consecutive failures.',
        );
      },
    );

    test(
      'Vimeo: success after failures resets the counter',
      () async {
        // Two failures — counter at 2/3, not open yet.
        whenExtractInfo().thenThrow(
          YtDlpException(YtDlpErrorType.networkError, 'HTTP 503'),
        );
        await useCase(vimeoUrl, engine: DownloadEngine.ytdlpOnly);
        await useCase(vimeoUrl, engine: DownloadEngine.ytdlpOnly);

        // Success — must reset.
        whenExtractInfo().thenAnswer((_) async => YtDlpVideoInfo(
              id: 'cbtest123',
              title: 'OK',
              description: '',
              uploader: 'X',
              platform: 'vimeo',
              formats: [
                YtDlpFormat(
                    formatId: 'http-1080p',
                    ext: 'mp4',
                    height: 1080,
                    width: 1920,
                    vcodec: 'h264',
                    acodec: 'aac'),
              ],
              isLive: false,
            ));
        await useCase(vimeoUrl, engine: DownloadEngine.ytdlpOnly);

        // After reset, 2 fails alone shouldn't trip.
        whenExtractInfo().thenThrow(
          YtDlpException(YtDlpErrorType.networkError, 'HTTP 503'),
        );
        await useCase(vimeoUrl, engine: DownloadEngine.ytdlpOnly);
        await useCase(vimeoUrl, engine: DownloadEngine.ytdlpOnly);

        expect(circuitBreaker.getState('vimeo'), CircuitBreakerState.closed,
            reason:
                'Counter must reset on success — pre-fix bug also broke this '
                'because non-YouTube path never recorded success either.');
      },
    );

    test(
      'SoundCloud: user-induced errors do NOT trip on non-YouTube path',
      () async {
        whenExtractInfo().thenThrow(
          YtDlpException(
            YtDlpErrorType.formatNotAvailable,
            'Requested format is not available',
          ),
        );

        for (var i = 0; i < 5; i++) {
          await useCase(soundcloudUrl, engine: DownloadEngine.ytdlpOnly);
        }

        expect(
          circuitBreaker.getState('soundcloud'),
          CircuitBreakerState.closed,
          reason:
              'User-induced errors must skip recording on EVERY platform, '
              'not just YouTube.',
        );
      },
    );
  });

  group('platform coverage — image-capable path (Instagram/Pinterest/etc)',
      () {
    test(
      'Instagram: 3 yt-dlp platform-broken failures DO trip the circuit',
      () async {
        // Image-capable platforms route through `_extractWithParallelGalleryDl`
        // which races yt-dlp and gallery-dl. Pre-fix: yt-dlp success on this
        // path didn't record (only gallery-dl success did). Failures were
        // also unrecorded since gallery-dl was unavailable in tests.
        when(() => mockGalleryDl.isAvailable()).thenAnswer((_) async => false);
        whenExtractInfo().thenThrow(
          YtDlpException(YtDlpErrorType.networkError, 'HTTP 503'),
        );

        await useCase(instagramUrl, engine: DownloadEngine.ytdlpOnly);
        await useCase(instagramUrl, engine: DownloadEngine.ytdlpOnly);
        await useCase(instagramUrl, engine: DownloadEngine.ytdlpOnly);

        expect(
          circuitBreaker.getState('instagram'),
          CircuitBreakerState.open,
          reason:
              'Image-capable paths must record failures so the circuit '
              'can protect users from runaway IG/Pinterest/Twitter retries.',
        );
      },
    );
  });

  // =========================================================================
  // Severity classifier — typed-enum tier (resilient to yt-dlp message churn)
  // =========================================================================
  group('severity classifier — typed YtDlpErrorType (Tier 1)', () {
    test('loginRequired type → user-induced (does not trip)', () async {
      // Simulates the case where stderr parser tagged the error type
      // BEFORE message bubbles up — string-matching tier never fires.
      whenExtractInfo().thenThrow(
        YtDlpException(
          YtDlpErrorType.loginRequired,
          'opaque message that string-matcher cannot parse',
        ),
      );
      for (var i = 0; i < 5; i++) {
        await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);
      }
      expect(circuitBreaker.getState('youtube'), CircuitBreakerState.closed,
          reason: 'loginRequired type must classify as user-induced even when '
              'message string is opaque.');
    });

    test('formatNotAvailable type → user-induced', () async {
      whenExtractInfo().thenThrow(
        YtDlpException(YtDlpErrorType.formatNotAvailable, 'opaque'),
      );
      for (var i = 0; i < 5; i++) {
        await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);
      }
      expect(circuitBreaker.getState('youtube'), CircuitBreakerState.closed);
    });

    test('geoRestricted / ageRestricted / notFound → user-induced', () async {
      // Run each across the threshold to confirm none trip individually.
      for (final type in [
        YtDlpErrorType.geoRestricted,
        YtDlpErrorType.ageRestricted,
        YtDlpErrorType.notFound,
      ]) {
        // Reset between cases so previous case doesn't pollute.
        circuitBreaker.resetPlatform('youtube');
        whenExtractInfo().thenThrow(YtDlpException(type, 'opaque'));
        for (var i = 0; i < 5; i++) {
          await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);
        }
        expect(circuitBreaker.getState('youtube'), CircuitBreakerState.closed,
            reason: '$type must classify as user-induced');
      }
    });

    test('circuitBreakerOpen type → user-induced (no double-counting)',
        () async {
      // When the circuit is already open from prior failures, subsequent
      // requests throw with `circuitBreakerOpen` type. That MUST NOT
      // re-record (would extend cooldown indefinitely on every retry).
      whenExtractInfo().thenThrow(
        YtDlpException(YtDlpErrorType.circuitBreakerOpen,
            'Circuit breaker open for youtube — cooldown 50s remaining'),
      );
      for (var i = 0; i < 5; i++) {
        await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);
      }
      expect(circuitBreaker.getState('youtube'), CircuitBreakerState.closed,
          reason: 'Self-rejection must not feed back into counter.');
    });

    test('timeout / networkError / rateLimited → platform-broken (does trip)',
        () async {
      for (final type in [
        YtDlpErrorType.timeout,
        YtDlpErrorType.networkError,
        YtDlpErrorType.rateLimited,
      ]) {
        circuitBreaker.resetPlatform('vimeo');
        whenExtractInfo().thenThrow(YtDlpException(type, 'msg'));
        for (var i = 0; i < 3; i++) {
          await useCase(vimeoUrl, engine: DownloadEngine.ytdlpOnly);
        }
        expect(circuitBreaker.getState('vimeo'), CircuitBreakerState.open,
            reason:
                '$type is platform-broken and must trip after threshold');
      }
    });
  });

  // =========================================================================
  // Latency regression — the circuit-breaker counter fix originally walked
  // the full 4-client YouTube fallback chain on every failure (225s worst
  // case) because the buggy pre-fix counter accidentally bailed at 135s.
  // Smart early-bail restores fast failure for user-actionable errors
  // without resurrecting the counter conflation.
  // =========================================================================
  group('YouTube fallback chain — early-bail on user-induced errors', () {
    test(
      'loginRequired walks full chain — different client may have valid auth path',
      () async {
        // Production design: loginRequired IS recoverable via client swap.
        // Different YouTube player_clients use different auth bindings —
        // an ios/web cookie that's been flagged for bot scoring may still
        // pass when the request comes in via mweb/web or android paths
        // (different visitor-data + SIDTS rotation). See
        // _isRecoverableViaClientSwapResult in extract_video_info_usecase.dart.
        var callCount = 0;
        whenExtractInfo().thenAnswer((_) async {
          callCount++;
          throw YtDlpException(
            YtDlpErrorType.loginRequired,
            "Sign in to confirm you're not a bot",
          );
        });

        await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);

        // ios/web (default) + mweb,web + android + android_creator + tv_embedded = 5
        expect(callCount, 5,
            reason:
                'loginRequired is in the recoverable-via-client-swap set — '
                'walks full 5-client chain because a different player_client '
                'genuinely may pass YouTube\'s auth scoring.');
      },
    );

    test(
      'formatNotAvailable walks full chain — different clients expose different format manifests',
      () async {
        // Production design: formatNotAvailable IS recoverable via client
        // swap. Real-world: `mweb,web` may expose progressive MP4 that
        // `ios,web` only returned DASH for; `android` returns m3u8 HLS
        // where web client offered nothing. Switching clients changes
        // the format manifest YouTube returns.
        var callCount = 0;
        whenExtractInfo().thenAnswer((_) async {
          callCount++;
          throw YtDlpException(
            YtDlpErrorType.formatNotAvailable,
            'Requested format is not available',
          );
        });

        await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);

        expect(callCount, 5,
            reason: 'formatNotAvailable is recoverable via client swap — '
                'different player_clients expose different format manifests.');
      },
    );

    test(
      'video-private / geo-restricted / age-restricted all bail early',
      () async {
        for (final type in [
          YtDlpErrorType.notFound,
          YtDlpErrorType.geoRestricted,
          YtDlpErrorType.ageRestricted,
        ]) {
          var callCount = 0;
          whenExtractInfo().thenAnswer((_) async {
            callCount++;
            throw YtDlpException(type, 'msg');
          });

          await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);
          expect(callCount, 1,
              reason: '$type is intrinsic to the URL/account — bail');
        }
      },
    );

    test(
      'platform-broken errors STILL walk the full chain (different client may work)',
      () async {
        // HTTP 5xx / network blip / persistent timeout can be transient on
        // a specific player_client backend. The chain must still walk all
        // 5 clients because a different backend genuinely might succeed
        // (this is the whole point of having a fallback chain).
        var callCount = 0;
        whenExtractInfo().thenAnswer((_) async {
          callCount++;
          throw YtDlpException(
            YtDlpErrorType.networkError,
            'HTTP 503',
          );
        });

        await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);

        // 5 clients = ios,web (default) + mweb,web + android + android_creator + tv_embedded.
        expect(callCount, 5,
            reason:
                'Platform-broken errors must walk the full chain — different '
                'player_client backends might hit different YouTube servers, '
                'one of which could still be healthy.');
      },
    );

    test(
      'mixed platform-broken + recoverable user-induced still walks full chain',
      () async {
        // Mixed scenario: first client fails with HTTP 5xx (legit transient),
        // second client (mweb,web) returns "Sign in to confirm bot" because
        // YouTube applied account flag mid-chain. Both networkError and
        // loginRequired are recoverable via client swap (loginRequired
        // because different clients have different auth bindings), so the
        // chain continues to tv_embedded — one of android/android_creator/
        // tv_embedded may have unflagged auth state.
        var callCount = 0;
        whenExtractInfo().thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            throw YtDlpException(YtDlpErrorType.networkError, 'HTTP 503');
          } else {
            throw YtDlpException(
              YtDlpErrorType.loginRequired,
              "Sign in to confirm",
            );
          }
        });

        await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);

        expect(callCount, 5,
            reason: 'Both networkError and loginRequired are recoverable '
                'via client swap — walks full 5-client chain.');
      },
    );

    test(
      'mixed platform-broken + NON-recoverable user-induced bails on non-recoverable',
      () async {
        // Mixed scenario: first networkError (recoverable), then second
        // attempt returns geoRestricted — TRULY non-recoverable since geo
        // gating is enforced at YouTube backend regardless of player_client.
        // Must bail at attempt 2.
        var callCount = 0;
        whenExtractInfo().thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            throw YtDlpException(YtDlpErrorType.networkError, 'HTTP 503');
          } else {
            throw YtDlpException(
              YtDlpErrorType.geoRestricted,
              'Video not available in your country',
            );
          }
        });

        await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);

        expect(callCount, 2,
            reason: 'geoRestricted is non-recoverable user-induced — bail '
                'at attempt 2, no point walking remaining clients.');
      },
    );
  });
}
