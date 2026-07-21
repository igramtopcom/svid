/// Phase A tests — `cookies-from-browser` auto-fallback retry.
///
/// Goal: when the primary cookies-file path fails with a session-likely
/// error (loginRequired / formatNotAvailable), the usecase auto-retries
/// with `--cookies-from-browser <auto-detected-browser>`. Live browser
/// session cookies carry binding signals (PO Token visitor data,
/// SIDTS/SIDCC rotation) that the WebView-extracted file format strips,
/// so success rate is materially higher.
///
/// Contract this file locks:
///   1. Fallback fires ONLY on retry, never on first attempt — respects
///      privacy default of "no browser cookie reads".
///   2. Fallback fires ONLY when user has NOT explicitly configured a
///      browser via Settings (else they already control the path).
///   3. Fallback fires ONLY for session-likely errors.
///   4. Fallback success short-circuits — does NOT proceed to
///      retry-without-cookies.
///   5. Fallback failure falls through to retry-without-cookies as
///      last resort, preserving current safety net.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ssvid/core/errors/result.dart';
import 'package:ssvid/features/downloads/data/datasources/ytdlp_datasource.dart';
import 'package:ssvid/features/downloads/domain/usecases/extract_video_info_usecase.dart';
import 'package:ssvid/features/settings/domain/enums/download_engine.dart';

import '../../../../shared/mocks/mocks.dart';

void main() {
  late MockSSvidApiService mockApi;
  late MockYtDlpDataSource mockYtdlp;
  late MockGalleryDlDataSource mockGalleryDl;
  late ExtractVideoInfoUseCase useCase;

  const youtubeUrl = 'https://www.youtube.com/watch?v=phaseAtest';

  YtDlpVideoInfo makeVideoInfo() => YtDlpVideoInfo(
    id: 'phaseAtest',
    title: 'Phase A Test',
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
        acodec: 'none',
      ),
      YtDlpFormat(formatId: '140', ext: 'm4a', vcodec: 'none', acodec: 'mp4a'),
    ],
    isLive: false,
  );

  setUp(() {
    mockApi = MockSSvidApiService();
    mockYtdlp = MockYtDlpDataSource();
    mockGalleryDl = MockGalleryDlDataSource();
    useCase = ExtractVideoInfoUseCase(
      mockApi,
      mockYtdlp,
      mockGalleryDl,
      delay: (_) async {},
    );
    when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
    when(() => mockGalleryDl.isAvailable()).thenAnswer((_) async => false);
  });

  group('cookies-from-browser fallback — happy path (retry succeeds)', () {
    test(
      'primary cookies path returns formatNotAvailable, fallback retries with browser cookies and succeeds',
      () async {
        // Track which calls used cookies-file vs cookies-from-browser.
        final calls = <Map<String, String?>>[];
        when(
          () => mockYtdlp.extractInfo(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            proxyUrl: any(named: 'proxyUrl'),
            extractorClient: any(named: 'extractorClient'),
            timeoutSecs: any(named: 'timeoutSecs'),
          ),
        ).thenAnswer((invocation) async {
          final cookiesFile =
              invocation.namedArguments[#cookiesFile] as String?;
          final cookiesFromBrowser =
              invocation.namedArguments[#cookiesFromBrowser] as String?;
          calls.add({
            'cookiesFile': cookiesFile,
            'cookiesFromBrowser': cookiesFromBrowser,
          });
          // First call: with file cookies → fail
          // Second call: with cookies-from-browser → succeed
          if (cookiesFromBrowser != null) {
            return makeVideoInfo();
          }
          throw YtDlpException(
            YtDlpErrorType.formatNotAvailable,
            'Requested format is not available',
          );
        });

        final result = await useCase(
          youtubeUrl,
          engine: DownloadEngine.ytdlpOnly,
          cookiesFile: '/tmp/cookies.txt',
          cookiesFromBrowserFallback: 'chrome',
        );

        expect(
          result.isSuccess,
          isTrue,
          reason: 'fallback retry should rescue the failed primary path',
        );
        expect(
          calls.length,
          greaterThanOrEqualTo(2),
          reason:
              'Should make at least 2 yt-dlp calls — primary (file) + fallback (browser)',
        );
        expect(calls.first['cookiesFile'], '/tmp/cookies.txt');
        expect(
          calls.first['cookiesFromBrowser'],
          isNull,
          reason:
              'First call must not use cookies-from-browser — privacy default',
        );
        // The cookies-from-browser call appears later in the chain.
        expect(
          calls.any((c) => c['cookiesFromBrowser'] == 'chrome'),
          isTrue,
          reason: 'Must retry with the supplied fallback browser',
        );
      },
    );

    test(
      'loginRequired (Sign in to confirm bot) triggers browser-cookies retry',
      () async {
        var callCount = 0;
        when(
          () => mockYtdlp.extractInfo(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            proxyUrl: any(named: 'proxyUrl'),
            extractorClient: any(named: 'extractorClient'),
            timeoutSecs: any(named: 'timeoutSecs'),
          ),
        ).thenAnswer((invocation) async {
          callCount++;
          final fromBrowser =
              invocation.namedArguments[#cookiesFromBrowser] as String?;
          if (fromBrowser == 'edge') return makeVideoInfo();
          throw YtDlpException(
            YtDlpErrorType.loginRequired,
            "Sign in to confirm you're not a bot",
          );
        });

        final result = await useCase(
          youtubeUrl,
          engine: DownloadEngine.ytdlpOnly,
          cookiesFile: '/tmp/cookies.txt',
          cookiesFromBrowserFallback: 'edge',
        );

        expect(result.isSuccess, isTrue);
        expect(callCount, greaterThanOrEqualTo(2));
      },
    );
  });

  group('cookies-from-browser fallback — privacy + opt-in safeguards', () {
    test(
      'fallback does NOT fire on first attempt — privacy default respected',
      () async {
        // The very first extractInfo call must NEVER receive a non-null
        // cookiesFromBrowser when the user hasn't explicitly set one.
        // Even with `cookiesFromBrowserFallback: 'chrome'` provided as
        // the auto-detected hint, the primary attempt must use only the
        // file cookies — fallback fires solely on retry.
        when(
          () => mockYtdlp.extractInfo(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            proxyUrl: any(named: 'proxyUrl'),
            extractorClient: any(named: 'extractorClient'),
            timeoutSecs: any(named: 'timeoutSecs'),
          ),
        ).thenAnswer((_) async => makeVideoInfo());

        final result = await useCase(
          youtubeUrl,
          engine: DownloadEngine.ytdlpOnly,
          cookiesFile: '/tmp/cookies.txt',
          cookiesFromBrowserFallback: 'chrome',
        );

        expect(result.isSuccess, isTrue);
        verify(
          () => mockYtdlp.extractInfo(
            any(),
            cookiesFile: '/tmp/cookies.txt',
            cookiesFromBrowser: null, // ← critical: NOT 'chrome' on first try
            proxyUrl: any(named: 'proxyUrl'),
            extractorClient: any(named: 'extractorClient'),
            timeoutSecs: any(named: 'timeoutSecs'),
          ),
        ).called(1);
      },
    );

    test(
      'fallback does NOT fire when user already has explicit cookiesFromBrowser',
      () async {
        // If user explicitly set `cookiesFromBrowser: 'firefox'` via
        // Settings, that's the primary path — auto-fallback would be
        // redundant and might surprise them by reading a different
        // browser. The fallback short-circuits when primary
        // cookiesFromBrowser is non-null.
        when(
          () => mockYtdlp.extractInfo(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            proxyUrl: any(named: 'proxyUrl'),
            extractorClient: any(named: 'extractorClient'),
            timeoutSecs: any(named: 'timeoutSecs'),
          ),
        ).thenAnswer((_) async {
          throw YtDlpException(YtDlpErrorType.formatNotAvailable, 'fail');
        });

        await useCase(
          youtubeUrl,
          engine: DownloadEngine.ytdlpOnly,
          cookiesFile: '/tmp/cookies.txt',
          cookiesFromBrowser: 'firefox', // explicit user choice
          cookiesFromBrowserFallback: 'chrome', // auto-hint also present
        );

        // Verify chrome was never called — user's firefox choice respected.
        verifyNever(
          () => mockYtdlp.extractInfo(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: 'chrome',
            proxyUrl: any(named: 'proxyUrl'),
            extractorClient: any(named: 'extractorClient'),
            timeoutSecs: any(named: 'timeoutSecs'),
          ),
        );
      },
    );

    test(
      'fallback does NOT fire when no fallback browser detected (null)',
      () async {
        when(
          () => mockYtdlp.extractInfo(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            proxyUrl: any(named: 'proxyUrl'),
            extractorClient: any(named: 'extractorClient'),
            timeoutSecs: any(named: 'timeoutSecs'),
          ),
        ).thenAnswer((_) async {
          throw YtDlpException(YtDlpErrorType.formatNotAvailable, 'fail');
        });

        await useCase(
          youtubeUrl,
          engine: DownloadEngine.ytdlpOnly,
          cookiesFile: '/tmp/cookies.txt',
          cookiesFromBrowserFallback: null, // no browser detected
        );

        // Confirm no call ever passed cookiesFromBrowser != null.
        verifyNever(
          () => mockYtdlp.extractInfo(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(
              named: 'cookiesFromBrowser',
              that: isNotNull,
            ),
            proxyUrl: any(named: 'proxyUrl'),
            extractorClient: any(named: 'extractorClient'),
            timeoutSecs: any(named: 'timeoutSecs'),
          ),
        );
      },
    );
  });

  group('cookies-from-browser fallback — error-type gating', () {
    test('networkError does NOT trigger browser-cookies fallback', () async {
      // Network errors are not session-related — cookies-from-browser
      // wouldn't help. Only loginRequired / formatNotAvailable /
      // unknown should fire the fallback.
      when(
        () => mockYtdlp.extractInfo(
          any(),
          cookiesFile: any(named: 'cookiesFile'),
          cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
          proxyUrl: any(named: 'proxyUrl'),
          extractorClient: any(named: 'extractorClient'),
          timeoutSecs: any(named: 'timeoutSecs'),
        ),
      ).thenThrow(YtDlpException(YtDlpErrorType.networkError, 'HTTP 503'));

      await useCase(
        youtubeUrl,
        engine: DownloadEngine.ytdlpOnly,
        cookiesFile: '/tmp/cookies.txt',
        cookiesFromBrowserFallback: 'chrome',
      );

      verifyNever(
        () => mockYtdlp.extractInfo(
          any(),
          cookiesFile: any(named: 'cookiesFile'),
          cookiesFromBrowser: 'chrome',
          proxyUrl: any(named: 'proxyUrl'),
          extractorClient: any(named: 'extractorClient'),
          timeoutSecs: any(named: 'timeoutSecs'),
        ),
      );
    });
  });

  group(
    'cookies-from-browser fallback — graceful degradation when fallback also fails',
    () {
      test('fallback fails → falls through to retry-without-cookies', () async {
        final calls = <String?>[]; // collect cookiesFromBrowser per call
        when(
          () => mockYtdlp.extractInfo(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            proxyUrl: any(named: 'proxyUrl'),
            extractorClient: any(named: 'extractorClient'),
            timeoutSecs: any(named: 'timeoutSecs'),
          ),
        ).thenAnswer((invocation) async {
          final fromBrowser =
              invocation.namedArguments[#cookiesFromBrowser] as String?;
          calls.add(fromBrowser);
          throw YtDlpException(YtDlpErrorType.formatNotAvailable, 'fail');
        });

        final result = await useCase(
          youtubeUrl,
          engine: DownloadEngine.ytdlpOnly,
          cookiesFile: '/tmp/cookies.txt',
          cookiesFromBrowserFallback: 'chrome',
        );

        expect(result.isFailure, isTrue);
        // Expect: primary (null) → fallback (chrome) → retry-without (null)
        expect(
          calls,
          containsAll([null, 'chrome']),
          reason:
              'Both fallback (chrome) and retry-without-cookies (null) should fire when each preceding step fails',
        );
      });

      test(
        'fallback chain advances when a browser fails with Windows DPAPI decrypt error',
        () async {
          final calls = <String?>[];
          when(
            () => mockYtdlp.extractInfo(
              any(),
              cookiesFile: any(named: 'cookiesFile'),
              cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
              proxyUrl: any(named: 'proxyUrl'),
              extractorClient: any(named: 'extractorClient'),
              timeoutSecs: any(named: 'timeoutSecs'),
            ),
          ).thenAnswer((invocation) async {
            final fromBrowser =
                invocation.namedArguments[#cookiesFromBrowser] as String?;
            calls.add(fromBrowser);
            if (fromBrowser == 'edge') {
              throw YtDlpException(
                YtDlpErrorType.unknown,
                'ERROR: Failed to decrypt with DPAPI. '
                'See https://github.com/yt-dlp/yt-dlp/issues/10927 for more info',
              );
            }
            if (fromBrowser == 'chrome') {
              return makeVideoInfo();
            }
            throw YtDlpException(
              YtDlpErrorType.loginRequired,
              "Sign in to confirm you're not a bot",
            );
          });

          final result = await useCase(
            youtubeUrl,
            engine: DownloadEngine.ytdlpOnly,
            cookiesFile: null,
            cookiesFromBrowserFallbackChain: const ['edge', 'chrome'],
          );

          expect(result.isSuccess, isTrue);
          expect(
            calls,
            containsAllInOrder([null, 'edge', 'chrome']),
            reason:
                'DPAPI failure is a browser-cookie-source failure, so the '
                'chain must advance instead of surfacing raw stderr or '
                'misrouting to login.',
          );
        },
      );
    },
  );

  // =========================================================================
  // Reviewer P1 fixes — cookiesFile gate removal + proxyUrl threading.
  // 2026-05-07 review caught: browser-cookies retry was gated behind
  // `cookiesFile != null`, locking out users who have Chrome logged in
  // but never logged in via app webview. Plus proxyUrl was dropped on
  // the retry path, defeating IP-rotation users on the layer most
  // likely to be the actual blocker.
  // =========================================================================
  group('Reviewer P1 — cookiesFile gate removal', () {
    test('browser-cookies retry fires even when cookiesFile is null', () async {
      // Pre-fix: `cookiesFile != null` gate prevented this entire
      // path. User with Chrome login but no app-webview cookies
      // would fail loginRequired with no recovery option. Post-fix:
      // gate removed, browser fallback fires regardless of file.
      var sawBrowserCall = false;
      when(
        () => mockYtdlp.extractInfo(
          any(),
          cookiesFile: any(named: 'cookiesFile'),
          cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
          proxyUrl: any(named: 'proxyUrl'),
          extractorClient: any(named: 'extractorClient'),
          timeoutSecs: any(named: 'timeoutSecs'),
        ),
      ).thenAnswer((invocation) async {
        final fromBrowser =
            invocation.namedArguments[#cookiesFromBrowser] as String?;
        if (fromBrowser == 'chrome') {
          sawBrowserCall = true;
          return makeVideoInfo();
        }
        throw YtDlpException(
          YtDlpErrorType.loginRequired,
          "Sign in to confirm you're not a bot",
        );
      });

      final result = await useCase(
        youtubeUrl,
        engine: DownloadEngine.ytdlpOnly,
        cookiesFile: null, // ← null cookiesFile
        cookiesFromBrowserFallback: 'chrome',
      );

      expect(
        sawBrowserCall,
        isTrue,
        reason:
            'Reviewer P1 fix: browser-cookies retry must fire even when cookiesFile is null '
            '(user has Chrome login but no app webview cookies)',
      );
      expect(result.isSuccess, isTrue);
    });
  });

  group('Reviewer P1 — proxyUrl threading', () {
    test('browser-cookies retry forwards proxyUrl to yt-dlp', () async {
      // Pre-fix: _retryWithCookiesFromBrowser dropped proxyUrl,
      // making the retry hit raw home IP — defeating users who
      // configured a proxy specifically to bypass IP-flag scoring.
      // Post-fix: proxy threads through.
      const proxy = 'http://proxy.local:8080';
      var browserCallProxy = '__not_seen__';
      when(
        () => mockYtdlp.extractInfo(
          any(),
          cookiesFile: any(named: 'cookiesFile'),
          cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
          proxyUrl: any(named: 'proxyUrl'),
          extractorClient: any(named: 'extractorClient'),
          timeoutSecs: any(named: 'timeoutSecs'),
        ),
      ).thenAnswer((invocation) async {
        final fromBrowser =
            invocation.namedArguments[#cookiesFromBrowser] as String?;
        if (fromBrowser == 'chrome') {
          browserCallProxy =
              invocation.namedArguments[#proxyUrl] as String? ?? '__null__';
          return makeVideoInfo();
        }
        throw YtDlpException(
          YtDlpErrorType.formatNotAvailable,
          'Requested format is not available',
        );
      });

      await useCase(
        youtubeUrl,
        engine: DownloadEngine.ytdlpOnly,
        cookiesFile: '/tmp/cookies.txt',
        cookiesFromBrowserFallback: 'chrome',
        proxyUrl: proxy,
      );

      expect(
        browserCallProxy,
        proxy,
        reason:
            'Reviewer P1 fix: proxyUrl must thread to browser-cookies retry — '
            'IP-rotation users would otherwise see retry hit raw home IP',
      );
    });
  });

  // =========================================================================
  // Login-loop suppression — discovered via Chairman runtime test 2026-05-07.
  // Pre-fix: yt-dlp formatNotAvailable (real signal: PO Token required)
  // → app retry without cookies → "Sign in to confirm" → loginRequired
  // escalation → UI auto-login flow → user logs in → re-extract →
  // formatNotAvailable again → INFINITE LOOP. Fix: suppress retry-without-
  // cookies artifact, surface ORIGINAL exception to caller.
  // =========================================================================
  group('Login-loop suppression — original error wins over retry artifact', () {
    test(
      'formatNotAvailable + retry-without-cookies fails with loginRequired → '
      'caller receives ORIGINAL formatNotAvailable, NOT loginRequired',
      () async {
        // Sequence simulates exact production scenario from Chairman's
        // runtime log:
        //   call 1 (with cookies file): formatNotAvailable
        //   call 2 (cookies-from-browser): formatNotAvailable
        //   call 3 (retry-without-cookies): loginRequired (Sign in)
        // Pre-fix: caller received loginRequired, UI triggered login flow.
        // Post-fix: caller MUST receive formatNotAvailable.
        var callCount = 0;
        when(
          () => mockYtdlp.extractInfo(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            proxyUrl: any(named: 'proxyUrl'),
            extractorClient: any(named: 'extractorClient'),
            timeoutSecs: any(named: 'timeoutSecs'),
          ),
        ).thenAnswer((invocation) async {
          callCount++;
          final hasCookieFile = invocation.namedArguments[#cookiesFile] != null;
          final hasBrowserCookies =
              invocation.namedArguments[#cookiesFromBrowser] != null;
          if (hasCookieFile || hasBrowserCookies) {
            // Calls with any cookies → format not available (PO Token required)
            throw YtDlpException(
              YtDlpErrorType.formatNotAvailable,
              'Requested format is not available',
            );
          } else {
            // Call without ANY cookies → bot challenge
            throw YtDlpException(
              YtDlpErrorType.loginRequired,
              "Sign in to confirm you're not a bot",
            );
          }
        });

        final result = await useCase(
          youtubeUrl,
          engine: DownloadEngine.ytdlpOnly,
          cookiesFile: '/tmp/cookies.txt',
          cookiesFromBrowserFallback: 'chrome',
        );

        expect(result.isFailure, isTrue);
        final exception = result.exceptionOrNull;
        expect(
          exception,
          isA<YtDlpException>(),
          reason: 'Typed exception preserved (not wrapped in AppException)',
        );
        final ytException = exception as YtDlpException;
        expect(
          ytException.type,
          YtDlpErrorType.formatNotAvailable,
          reason:
              'CRITICAL: caller must receive ORIGINAL formatNotAvailable '
              '(real signal — PO Token required), NOT the retry-without-cookies '
              'loginRequired artifact (which would loop the auto-login flow '
              'forever on PO-Token-required URLs).',
        );
        // At least 2 calls (primary + retry-without-cookies).
        expect(callCount, greaterThanOrEqualTo(2));
      },
    );

    test(
      'retry-without-cookies SUCCESS still returns the success (suppression only fires on retry failure)',
      () async {
        // Don't break the legitimate case: when retry-without-cookies
        // actually succeeds (e.g. cookies were genuinely bad), return
        // the success unchanged. Suppression is ONLY for the failure
        // path where retry escalates to a noisier error.
        when(
          () => mockYtdlp.extractInfo(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            proxyUrl: any(named: 'proxyUrl'),
            extractorClient: any(named: 'extractorClient'),
            timeoutSecs: any(named: 'timeoutSecs'),
          ),
        ).thenAnswer((invocation) async {
          final hasCookieFile = invocation.namedArguments[#cookiesFile] != null;
          if (hasCookieFile) {
            throw YtDlpException(
              YtDlpErrorType.formatNotAvailable,
              'Requested format is not available',
            );
          }
          // Call without cookies → success (cookies were the issue)
          return makeVideoInfo();
        });

        final result = await useCase(
          youtubeUrl,
          engine: DownloadEngine.ytdlpOnly,
          cookiesFile: '/tmp/cookies.txt',
        );

        expect(
          result.isSuccess,
          isTrue,
          reason:
              'Retry-without-cookies success path must still return success — '
              'suppression is only for the artifact-on-failure case',
        );
      },
    );
  });
}

/// Trivial helper to make `lessThanOrEqualTo` work with raw int.
Iterable<int> calls(int n) => List.generate(n, (i) => i);
