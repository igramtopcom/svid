import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/data/datasources/ytdlp_datasource.dart';
import 'package:svid/features/downloads/domain/entities/download_error_code.dart';
import 'package:svid/features/downloads/domain/services/download_error_classifier.dart';

/// CUX-1: a non-zero-exit recode-contract failure must surface its REAL
/// upstream cause (403 / login / rate-limit / network) instead of the
/// misleading "Recode to .X failed — try MP4/MKV". A genuine post-process or
/// encoder failure still keeps the recode copy. The 403→login mapping is
/// gated on YouTube-without-cookies so a signed-in user is never looped.
///
/// The `stderr` passed in production is the FULL process buffer — it carries
/// ffmpeg's own progress/header lines ('bitrate:', muxer names, 'not found'
/// for atoms/filters). These fixtures use realistic multi-line buffers so a
/// substring collision (the bug the adversarial review caught) cannot pass.
void main() {
  group('CUX-1 classifyRecodeContractFailure', () {
    YtDlpErrorType? classify(
      String stderr, {
      bool isYouTube = true,
      bool cookies = false,
    }) =>
        YtDlpDataSource.classifyRecodeContractFailure(
          stderr: stderr,
          isYouTube: isYouTube,
          hasYouTubeCookies: cookies,
        );

    // A realistic FULL ffmpeg recode buffer: the download+merge succeeded,
    // then the re-encode failed. It contains 'bitrate' (twice) and other
    // ffmpeg noise that a naive substring parser misreads as upstream.
    const ffmpegRecodeFailBuffer = '''
[download] 100% of 12.34MiB in 00:03
[Merger] Merging formats into "video.mkv"
Input #0, matroska,webm, from 'video.mkv':
  Duration: 00:03:21.00, start: 0.000000, bitrate: 2456 kb/s
Stream mapping: Stream #0:0 -> #0:0 (vp9 (native) -> h264 (libx264))
frame=  100 fps= 25 q=28.0 size=512kB time=00:00:04.00 bitrate= 214.3kbits/s
Conversion failed!
ERROR: Postprocessing: Error selecting an encoder for stream 0:0''';

    group('GENUINE recode failures → null (keep recode copy)', () {
      test('full ffmpeg buffer with "bitrate" is NOT misread as rate-limited',
          () {
        // The original bug: "bitrate" contains "rate" → rateLimited (upstream).
        expect(classify(ffmpegRecodeFailBuffer), isNull);
        expect(classify(ffmpegRecodeFailBuffer, cookies: true), isNull);
        expect(classify(ffmpegRecodeFailBuffer, isYouTube: false), isNull);
      });

      test('encoder-not-found ("not found") is NOT misread as upstream notFound',
          () {
        expect(classify('Encoder not found for codec libx264'), isNull);
        expect(classify('Unknown encoder "h264_videotoolbox"'), isNull);
      });

      test('moov-atom-not-found ("not found") is NOT misread as upstream', () {
        expect(
          classify('[mov,mp4] moov atom not found\nConversion failed!'),
          isNull,
        );
      });

      test('ffmpeg muxer-missing ("format … not available") is NOT misread '
          'as upstream formatNotAvailable', () {
        expect(
          classify("Requested output format 'avi' is not available"),
          isNull,
        );
      });

      test('plain conversion failure → null', () {
        expect(
          classify('Conversion failed! ffmpeg exited with code 1'),
          isNull,
        );
      });

      test('unrecognized ffmpeg noise → null (do not fabricate access error)',
          () {
        expect(classify('[ffmpeg] muxer does not support codec'), isNull);
      });

      test('a recode failure of a video whose TITLE contains upstream words '
          '("Forbidden", "Private Video", "Too Many Requests", "Connection '
          'Refused") is NOT misread — title echoes are not ERROR: lines', () {
        const titledRecodeFail = '''
[download] Destination: Forbidden — Too Many Requests to a Private Video (Connection Refused Mix).mkv
[Merger] Merging formats into "Forbidden — Too Many Requests to a Private Video (Connection Refused Mix).mkv"
[VideoConvertor] Destination: Forbidden — Too Many Requests to a Private Video (Connection Refused Mix).avi
Input #0, matroska, from 'Forbidden — Too Many Requests to a Private Video (Connection Refused Mix).mkv':
  Duration: 00:04:10.00, bitrate: 1980 kb/s
ERROR: Postprocessing: Error selecting an encoder for stream 0:0''';
        expect(classify(titledRecodeFail), isNull);
        expect(classify(titledRecodeFail, cookies: true), isNull);
        expect(classify(titledRecodeFail, isYouTube: false), isNull);
      });
    });

    group('UPSTREAM failures → honest cause (not "recode failed")', () {
      test('403 on YouTube without cookies → loginRequired', () {
        expect(
          classify('ERROR: unable to download video data: '
              'HTTP Error 403: Forbidden'),
          YtDlpErrorType.loginRequired,
        );
      });

      test('sign-in-required without cookies → loginRequired', () {
        expect(
          classify('ERROR: Sign in to confirm you are not a bot'),
          YtDlpErrorType.loginRequired,
        );
      });

      test('rate-limit (HTTP 429) → rateLimited (recode never ran)', () {
        expect(
          classify('ERROR: HTTP Error 429: Too Many Requests'),
          YtDlpErrorType.rateLimited,
        );
      });

      test('network failure → networkError', () {
        expect(
          classify('ERROR: unable to download webpage: '
              '<urlopen error [Errno 110] Connection refused>'),
          YtDlpErrorType.networkError,
        );
      });
    });

    group('LOGIN-LOOP GUARD: signed-in user is never looped (critical)', () {
      test('403 WITH cookies → upstream surfaced but NEVER loginRequired', () {
        final t = classify(
            'ERROR: unable to download video data: HTTP Error 403: Forbidden',
            cookies: true);
        expect(t, isNotNull);
        expect(t, isNot(YtDlpErrorType.loginRequired));
      });

      test('"Sign in to confirm you are not a bot" WITH cookies → NEVER '
          'loginRequired (the bot-check line fires even when signed in)', () {
        final t = classify('ERROR: Sign in to confirm you are not a bot',
            cookies: true);
        expect(t, isNotNull); // upstream surfaced, not "recode failed"
        expect(t, isNot(YtDlpErrorType.loginRequired)); // no login loop
      });

      test('"Private video. Sign in…" WITH cookies → NEVER loginRequired', () {
        final t = classify(
            'ERROR: Private video. Sign in if you have been granted access',
            cookies: true);
        expect(t, isNotNull);
        expect(t, isNot(YtDlpErrorType.loginRequired));
      });

      test('non-YouTube auth block → never loginRequired (no sign-in flow we '
          'can drive there)', () {
        expect(
          classify('ERROR: HTTP Error 403: Forbidden', isYouTube: false),
          isNot(YtDlpErrorType.loginRequired),
        );
        expect(
          classify('ERROR: This video is private', isYouTube: false),
          isNot(YtDlpErrorType.loginRequired),
        );
      });
    });
  });

  /// CUX-1b: the pre-existing terminal download-fail branch shared the same
  /// login-loop defect (a login-parsed stderr returned loginRequired even
  /// with cookies). inferDownloadFailureType is the login-safe replacement.
  group('CUX-1b inferDownloadFailureType — terminal download-fail safety', () {
    YtDlpErrorType infer(
      String stderr, {
      bool isYouTube = true,
      bool cookies = false,
    }) =>
        YtDlpDataSource.inferDownloadFailureType(
          stderr: stderr,
          isYouTube: isYouTube,
          hasYouTubeCookies: cookies,
        );

    test('YouTube without cookies: 403 → loginRequired', () {
      expect(
        infer('ERROR: unable to download: HTTP Error 403: Forbidden'),
        YtDlpErrorType.loginRequired,
      );
    });

    test('YouTube without cookies: bot-check sign-in → loginRequired', () {
      expect(
        infer('ERROR: Sign in to confirm you are not a bot'),
        YtDlpErrorType.loginRequired,
      );
    });

    test('signed-in (cookies) bot-check sign-in → NOT loginRequired (the '
        'login-loop the whole fix exists to prevent)', () {
      expect(
        infer('ERROR: Sign in to confirm you are not a bot', cookies: true),
        isNot(YtDlpErrorType.loginRequired),
      );
    });

    test('signed-in (cookies) private-video sign-in → NOT loginRequired', () {
      expect(
        infer('ERROR: Private video. Sign in if you have been granted access',
            cookies: true),
        isNot(YtDlpErrorType.loginRequired),
      );
    });

    test('non-YouTube sign-in → NOT loginRequired (no sign-in flow to drive)',
        () {
      expect(
        infer('ERROR: This video is private. Sign in', isYouTube: false),
        isNot(YtDlpErrorType.loginRequired),
      );
    });

    test('non-login failures pass through unchanged', () {
      expect(
        infer('ERROR: HTTP Error 429: Too Many Requests'),
        YtDlpErrorType.rateLimited,
      );
      expect(
        infer('urlopen error [Errno 110] Connection timed out'),
        YtDlpErrorType.networkError,
      );
    });
  });

  /// END-TO-END (Codex P1): downstream routes on the MESSAGE via
  /// DownloadErrorClassifier.classifyMessage, NOT on YtDlpException.type. These
  /// lock that the EMITTED messages classify to the intended code — so 403/429
  /// never collapse into a network bucket, and a signed-in user's access
  /// failure never re-derives loginRequired (no login loop).
  group('CUX-1 emitted message → classifyMessage routes correctly', () {
    DownloadErrorCode codeFor(YtDlpErrorType t) =>
        DownloadErrorClassifier.classifyMessage(
            YtDlpDataSource.upstreamErrorMessage(t));

    const networkCodes = {
      DownloadErrorCode.networkOffline,
      DownloadErrorCode.networkTimeout,
      DownloadErrorCode.connectionRefused,
    };

    test('403/forbidden message → accessDenied (NOT network, NOT login)', () {
      final c = codeFor(YtDlpErrorType.unknown);
      expect(c, DownloadErrorCode.accessDenied);
      expect(networkCodes.contains(c), isFalse);
      expect(c, isNot(DownloadErrorCode.loginRequired));
    });

    test('429 message → rateLimited (NOT collapsed to a network code)', () {
      final c = codeFor(YtDlpErrorType.rateLimited);
      expect(c, DownloadErrorCode.rateLimited);
      expect(networkCodes.contains(c), isFalse);
    });

    test('network message → a network-family code (NOT access/login/rate)', () {
      final c = codeFor(YtDlpErrorType.networkError);
      expect(networkCodes.contains(c), isTrue);
    });

    test('YouTube-no-cookie login message → loginRequired (intended)', () {
      expect(codeFor(YtDlpErrorType.loginRequired),
          DownloadErrorCode.loginRequired);
    });

    test('signed-in downgrade message (the unknown/access message) → '
        'accessDenied, NEVER loginRequired (the login-loop is closed '
        'end-to-end, not just at the type level)', () {
      // CUX-1b emits upstreamErrorMessage(unknown) for the cookies-present
      // sign-in/bot-check case; it must NOT re-classify back to loginRequired.
      final c = DownloadErrorClassifier.classifyMessage(
          YtDlpDataSource.upstreamErrorMessage(YtDlpErrorType.unknown));
      expect(c, isNot(DownloadErrorCode.loginRequired));
      expect(c, DownloadErrorCode.accessDenied);
    });
  });
}
