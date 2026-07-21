/// Regression tests for the YouTube Explore detail-load contract.
///
/// Background: tester log `log.md:36` showed Explore surfacing a raw
/// `YtDlpException(loginRequired): Sign in to confirm you're not a
/// bot` straight to the user, while the home/download flow recovered
/// transparently for the same URL on the same machine. Audit traced
/// it to `youtube_explore_provider._loadVideoDetail` calling
/// `datasource.extractInfo(url)` raw — bypassing the cookies-from-
/// browser fallback retry that `ExtractVideoInfoUseCase` ships in
/// Phase 0/A. The fix mirrors that retry in-provider (raw
/// `YtDlpVideoInfo` is still needed for the detail panel, so we
/// can't simply switch to the domain usecase yet).
///
/// These tests pin the pure decision boundary — when a browser-
/// cookie retry is worth attempting — so a future refactor that
/// changes one side without the other can't silently re-introduce
/// the regression.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/data/datasources/ytdlp_datasource.dart';
import 'package:ssvid/features/youtube_search/presentation/providers/youtube_explore_provider.dart';

void main() {
  group('YouTubeExploreNotifier.isRecoverableViaBrowserCookies', () {
    test('loginRequired => recoverable via browser cookies', () {
      // Canonical SABR / "Sign in to confirm you're not a bot" case.
      // A fresh browser session usually has the YouTube auth cookies
      // that bypass the bot challenge, so a retry is worth firing.
      final err = YtDlpException(
        YtDlpErrorType.loginRequired,
        'Sign in to confirm you are not a bot',
      );
      expect(
        YouTubeExploreNotifier.isRecoverableViaBrowserCookies(err),
        isTrue,
      );
    });

    test('formatNotAvailable => recoverable via browser cookies', () {
      // YouTube serves SABR-protected URLs when the requesting IP
      // is flagged; formats sometimes surface as unavailable until
      // the request carries a valid session cookie. Mirroring the
      // upstream `ExtractVideoInfoUseCase` contract — both
      // user-induced classes get a one-shot retry.
      final err = YtDlpException(
        YtDlpErrorType.formatNotAvailable,
        'Requested format not available',
      );
      expect(
        YouTubeExploreNotifier.isRecoverableViaBrowserCookies(err),
        isTrue,
      );
    });

    test('networkError => NOT recoverable', () {
      // A cookie swap cannot fix a dropped TCP connection. Burning
      // a Keychain prompt + a second extract round-trip on errors
      // a retry cannot help is the bug we are guarding against.
      final err = YtDlpException(
        YtDlpErrorType.networkError,
        'Connection refused',
      );
      expect(
        YouTubeExploreNotifier.isRecoverableViaBrowserCookies(err),
        isFalse,
      );
    });

    test('timeout => NOT recoverable', () {
      final err = YtDlpException(
        YtDlpErrorType.timeout,
        'yt-dlp extraction timeout',
      );
      expect(
        YouTubeExploreNotifier.isRecoverableViaBrowserCookies(err),
        isFalse,
      );
    });

    test('jsRuntimeUnavailable => NOT recoverable (BinaryManager owns it)', () {
      // The repair surface for a missing Deno runtime is
      // `BinaryManager.triggerRepair(BinaryType.deno)`, not a
      // cookie swap — pinning that this gate stays out of that
      // recovery lane.
      final err = YtDlpException(
        YtDlpErrorType.jsRuntimeUnavailable,
        'External JavaScript runtime not found',
      );
      expect(
        YouTubeExploreNotifier.isRecoverableViaBrowserCookies(err),
        isFalse,
      );
    });

    test('circuitBreakerOpen => NOT recoverable (platform-level guard)', () {
      // The circuit is open because the platform itself looks down
      // recently; bypassing it via a cookie retry would defeat the
      // protection.
      final err = YtDlpException(
        YtDlpErrorType.circuitBreakerOpen,
        'Circuit breaker open',
      );
      expect(
        YouTubeExploreNotifier.isRecoverableViaBrowserCookies(err),
        isFalse,
      );
    });

    test('non-YtDlpException Object => NOT recoverable', () {
      // Defensive: anything that wasn't a typed yt-dlp error is
      // probably a Dart-level bug (NoSuchMethodError, etc.) — a
      // cookie retry won't help and we don't want the gate to
      // mask it.
      expect(
        YouTubeExploreNotifier.isRecoverableViaBrowserCookies(
          ArgumentError('not a YtDlpException'),
        ),
        isFalse,
      );
    });

    test('null => NOT recoverable', () {
      expect(
        YouTubeExploreNotifier.isRecoverableViaBrowserCookies(null),
        isFalse,
      );
    });

    test('unknown YtDlpException type => NOT recoverable', () {
      // Conservative default: only the two explicitly user-induced
      // classes are recoverable. Adding a new YtDlpErrorType in
      // the future will fall into this branch by default and
      // forces a deliberate decision to add it to the recoverable
      // set.
      final err = YtDlpException(
        YtDlpErrorType.unknown,
        'Unknown error',
      );
      expect(
        YouTubeExploreNotifier.isRecoverableViaBrowserCookies(err),
        isFalse,
      );
    });
  });

  // Player-client fallback chain — same recoverable set as the
  // cookies retry, but the leverage point is a different YouTube
  // API surface (android / android_creator / tv_embedded) rather
  // than a fresh cookie. Production telemetry showed ~64% of bug
  // reports were `loginRequired`; the home pipeline's chain caught
  // most of these while the Explore surface fell through. These
  // tests pin the gate that decides whether a client swap is
  // worth attempting.
  group('YouTubeExploreNotifier.isRecoverableViaClientSwap', () {
    test('loginRequired => recoverable via client swap', () {
      // SABR / bot-detection challenge. A different YouTube
      // client surface (android, tv_embedded) often passes the
      // same request because YouTube's bot rules are
      // fingerprint-specific.
      final err = YtDlpException(
        YtDlpErrorType.loginRequired,
        'Sign in to confirm you are not a bot',
      );
      expect(
        YouTubeExploreNotifier.isRecoverableViaClientSwap(err),
        isTrue,
      );
    });

    test('formatNotAvailable => recoverable via client swap', () {
      // Different clients sometimes surface different format
      // catalogues — TV embedded shows DASH that web didn't, etc.
      // Worth a swap before giving up.
      final err = YtDlpException(
        YtDlpErrorType.formatNotAvailable,
        'Requested format not available',
      );
      expect(
        YouTubeExploreNotifier.isRecoverableViaClientSwap(err),
        isTrue,
      );
    });

    test('networkError => NOT recoverable via client swap', () {
      // A swapped player_client still hits the same TCP socket —
      // burning the chain on a connectivity failure just makes
      // the user wait through 3 extra timeouts.
      final err = YtDlpException(
        YtDlpErrorType.networkError,
        'Connection refused',
      );
      expect(
        YouTubeExploreNotifier.isRecoverableViaClientSwap(err),
        isFalse,
      );
    });

    test('timeout => NOT recoverable via client swap', () {
      final err = YtDlpException(
        YtDlpErrorType.timeout,
        'yt-dlp extraction timeout',
      );
      expect(
        YouTubeExploreNotifier.isRecoverableViaClientSwap(err),
        isFalse,
      );
    });

    test('circuitBreakerOpen => NOT recoverable via client swap', () {
      // The platform-level circuit is open; swapping clients
      // bypasses the protection that exists for a reason.
      final err = YtDlpException(
        YtDlpErrorType.circuitBreakerOpen,
        'Circuit breaker open',
      );
      expect(
        YouTubeExploreNotifier.isRecoverableViaClientSwap(err),
        isFalse,
      );
    });

    test('jsRuntimeUnavailable => NOT recoverable via client swap', () {
      // Deno missing — repair surface lives in BinaryManager,
      // not yt-dlp client selection.
      final err = YtDlpException(
        YtDlpErrorType.jsRuntimeUnavailable,
        'External JavaScript runtime not found',
      );
      expect(
        YouTubeExploreNotifier.isRecoverableViaClientSwap(err),
        isFalse,
      );
    });

    test('non-YtDlpException Object => NOT recoverable', () {
      expect(
        YouTubeExploreNotifier.isRecoverableViaClientSwap(
          ArgumentError('not a YtDlpException'),
        ),
        isFalse,
      );
    });

    test('null => NOT recoverable', () {
      expect(
        YouTubeExploreNotifier.isRecoverableViaClientSwap(null),
        isFalse,
      );
    });

    test(
      'cookies-retry and client-swap recoverable sets are the same — '
      'change one, you must change the other',
      () {
        // Defensive equivalence pin. Today both gates recognise
        // exactly `loginRequired` + `formatNotAvailable`. If a
        // future change adds (say) `ageRestricted` to one gate
        // but forgets the other, the chain semantics get
        // confusing — the cookies retry would fire but the
        // client swap would not (or vice-versa). This test
        // enforces parity until/unless a deliberate divergence
        // is documented.
        for (final type in YtDlpErrorType.values) {
          final err = YtDlpException(type, '');
          expect(
            YouTubeExploreNotifier.isRecoverableViaClientSwap(err),
            equals(
              YouTubeExploreNotifier.isRecoverableViaBrowserCookies(err),
            ),
            reason:
                'Recoverable-set mismatch for $type — '
                'client-swap and cookies-retry gates diverged',
          );
        }
      },
    );
  });
}
