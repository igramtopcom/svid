import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/domain/entities/download_error_code.dart';
import 'package:ssvid/features/downloads/domain/services/download_error_classifier.dart';

void main() {
  group('DownloadErrorClassifier', () {
    group('network errors', () {
      test('classifies SocketException as networkOffline', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'SocketException: No internet connection',
          ),
          DownloadErrorCode.networkOffline,
        );
      });

      test('classifies failed host lookup as networkOffline', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'Failed host lookup: youtube.com',
          ),
          DownloadErrorCode.networkOffline,
        );
      });

      test('classifies timeout as networkTimeout', () {
        expect(
          DownloadErrorClassifier.classifyMessage('TimeoutException after 30s'),
          DownloadErrorCode.networkTimeout,
        );
      });

      test('classifies timed out as networkTimeout', () {
        expect(
          DownloadErrorClassifier.classifyMessage('Connection timed out'),
          DownloadErrorCode.networkTimeout,
        );
      });

      test('classifies Windows WSAETIMEDOUT 10060 as networkTimeout', () {
        // Windows Sockets surfaces numeric codes when the OS locale has
        // no English text. Production telemetry contains raw
        // `SocketException: errno = 10060` strings that previously
        // routed to `unknown`.
        expect(
          DownloadErrorClassifier.classifyMessage(
            'SocketException: errno = 10060, address = api.example.com',
          ),
          DownloadErrorCode.networkTimeout,
        );
      });

      test(
        'classifies Chinese zh-CN 信号灯超时 (semaphore timed out) as networkTimeout',
        () {
          // Real CN-locale Windows error string captured in production:
          // `SocketException: 信号灯超时。` — was misclassified as unknown
          // until B2.6 added the Chinese pattern.
          expect(
            DownloadErrorClassifier.classifyMessage(
              'SocketException: 信号灯超时。 (OS Error: 信号灯超时。, errno = 121)',
            ),
            DownloadErrorCode.networkTimeout,
          );
        },
      );

      test(
        'classifies Chinese zh-TW 信號燈逾時 (semaphore timed out) as networkTimeout',
        () {
          expect(
            DownloadErrorClassifier.classifyMessage(
              'SocketException: 信號燈逾時。',
            ),
            DownloadErrorCode.networkTimeout,
          );
        },
      );

      test(
        'classifies Japanese ja-JP セマフォがタイムアウトしました as networkTimeout',
        () {
          // Real production capture (log2.md 2026-05-23, v1.6.2 macOS
          // user with JP locale): WSAETIMEDOUT surfaces as
          // 'SocketException: セマフォがタイムアウトしました。' which
          // routed to `unknown` before the JP pattern was added — same
          // class of bug as the CN/TW patterns one Codex audit earlier.
          expect(
            DownloadErrorClassifier.classifyMessage(
              'SocketException: セマフォがタイムアウトしました。 (OS Error: セマフォがタイムアウトしました。, errno = 121)',
            ),
            DownloadErrorCode.networkTimeout,
          );
        },
      );

      test(
        'classifies Korean ko-KR 세마포 시간이 초과되었습니다 as networkTimeout',
        () {
          expect(
            DownloadErrorClassifier.classifyMessage(
              'SocketException: 세마포 시간이 초과되었습니다.',
            ),
            DownloadErrorCode.networkTimeout,
          );
        },
      );

      test(
        'classifies Windows WSAECONNREFUSED 10061 as connectionRefused',
        () {
          expect(
            DownloadErrorClassifier.classifyMessage(
              'SocketException: errno = 10061',
            ),
            DownloadErrorCode.connectionRefused,
          );
        },
      );

      test('classifies connection refused as connectionRefused', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'Connection refused by server',
          ),
          DownloadErrorCode.connectionRefused,
        );
      });

      test('classifies connection reset as connectionRefused', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'ECONNRESET: Connection was reset',
          ),
          DownloadErrorCode.connectionRefused,
        );
      });

      test('classifies DNS lookup errors as connectionRefused', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'DNS lookup failed for youtube.com',
          ),
          DownloadErrorCode.connectionRefused,
        );
      });

      test('classifies getaddrinfo errors as connectionRefused', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'getaddrinfo ENOTFOUND youtube.com',
          ),
          DownloadErrorCode.connectionRefused,
        );
      });

      test('classifies HTTP 500 as serverError', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'HTTP error 500: Internal Server Error',
          ),
          DownloadErrorCode.serverError,
        );
      });

      test('classifies HTTP 502 as serverError', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'HTTP status 502 Bad Gateway',
          ),
          DownloadErrorCode.serverError,
        );
      });

      test('classifies HTTP 503 as serverError', () {
        expect(
          DownloadErrorClassifier.classifyMessage('Service unavailable'),
          DownloadErrorCode.serverError,
        );
      });

      test(
        'classifies TikTok webpage challenge response as retryable serverError',
        () {
          final code = DownloadErrorClassifier.classifyMessage(
            'ERROR: [TikTok] 7624412140237065486: Unexpected response from webpage request',
          );

          expect(code, DownloadErrorCode.serverError);
          expect(code.isRetryable, isTrue);
        },
      );

      test(
        'classifies TikTok rehydration extraction failure as retryable serverError',
        () {
          final code = DownloadErrorClassifier.classifyMessage(
            'ERROR: [TikTok] 7624412140237065486: Unable to extract universal data for rehydration',
          );

          expect(code, DownloadErrorCode.serverError);
          expect(code.isRetryable, isTrue);
        },
      );
    });

    group('yt-dlp errors', () {
      test('classifies rate limiting as rateLimited', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'HTTP Error 429: Too Many Requests',
          ),
          DownloadErrorCode.rateLimited,
        );
      });

      test('classifies throttling as rateLimited', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'Download throttled by server',
          ),
          DownloadErrorCode.rateLimited,
        );
      });

      test('classifies login required', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'Login required to view this video',
          ),
          DownloadErrorCode.loginRequired,
        );
      });

      test('explicit login-required wrapper wins over raw 403 stderr', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'Login required: YouTube refused the media stream or requested '
            'authentication. Please sign in and retry. Raw yt-dlp error: '
            'ERROR: unable to download video data: HTTP Error 403: Forbidden',
          ),
          DownloadErrorCode.loginRequired,
        );
      });

      test(
        'P1 (2026-05-25): bare Facebook "Cannot parse data" no longer auto-loginRequired',
        () {
          // Pre-fix the blanket rule promoted every facebook + cannot
          // parse data to loginRequired, causing a login-spam loop
          // when the underlying cause was a FB payload / yt-dlp
          // extractor issue (re-login does not help). New rule
          // requires an explicit auth marker in the same message;
          // bare cannot-parse-data falls through to `unknown`.
          expect(
            DownloadErrorClassifier.classifyMessage(
              'yt-dlp error: ERROR: [facebook] 1659131188558491: Cannot parse data; please report this issue on  https://github.com/yt-dlp/yt-dlp/issues',
            ),
            DownloadErrorCode.unknown,
            reason:
                'Bare cannot-parse-data with no auth marker must NOT '
                'be auto-promoted to loginRequired',
          );
        },
      );

      test(
        'P1: Facebook "Cannot parse data" + explicit auth marker IS loginRequired',
        () {
          // When yt-dlp surfaces a login-wall response alongside the
          // cannot-parse-data error, the auth marker is the positive
          // signal and the auto-promotion is correct.
          expect(
            DownloadErrorClassifier.classifyMessage(
              'yt-dlp error: ERROR: [facebook] 123: Cannot parse data. Use --cookies to provide a usable session.',
            ),
            DownloadErrorCode.loginRequired,
          );
          expect(
            DownloadErrorClassifier.classifyMessage(
              'yt-dlp error: ERROR: [facebook] 123: Cannot parse data; login required',
            ),
            DownloadErrorCode.loginRequired,
          );
          expect(
            DownloadErrorClassifier.classifyMessage(
              'yt-dlp error: ERROR: [facebook] 123: Cannot parse data — please log in to continue',
            ),
            DownloadErrorCode.loginRequired,
          );
        },
      );

      test('P1: non-Facebook "cannot parse data" stays unknown', () {
        // The rule only applies to Facebook URLs. A generic parse
        // failure on another platform should not piggyback on the
        // Facebook-specific auth heuristic.
        expect(
          DownloadErrorClassifier.classifyMessage(
            'yt-dlp error: ERROR: [generic] Cannot parse data',
          ),
          DownloadErrorCode.unknown,
        );
      });

      test('classifies private video as loginRequired', () {
        expect(
          DownloadErrorClassifier.classifyMessage('This is a private video'),
          DownloadErrorCode.loginRequired,
        );
      });

      test('classifies geo restriction', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'Video not available in your country',
          ),
          DownloadErrorCode.geoRestricted,
        );
      });

      test('classifies age restriction', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'Please confirm your age to continue',
          ),
          DownloadErrorCode.ageRestricted,
        );
      });

      test('classifies format unavailable', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'Requested format is not available',
          ),
          DownloadErrorCode.formatUnavailable,
        );
      });

      test('classifies video not found', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'Video unavailable: removed by user',
          ),
          DownloadErrorCode.videoNotFound,
        );
      });

      test('classifies unable to extract as videoNotFound', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'Unable to extract video data',
          ),
          DownloadErrorCode.videoNotFound,
        );
      });

      test('classifies yt-dlp binary missing', () {
        expect(
          DownloadErrorClassifier.classifyMessage('yt-dlp not found in PATH'),
          DownloadErrorCode.ytdlpBinaryMissing,
        );
      });
    });

    // yt-dlp 2025.11.12+ requires an external JS runtime (Deno/Node/QuickJS)
    // to solve YouTube nsig + n-challenge. The classifier must detect the
    // runtime-missing signature BEFORE format-unavailable / login-required
    // because the stderr lines overlap with those categories — a misroute
    // would fire the auto-login flow on a video that just needs Deno.
    group('JS runtime unavailable (priority over login/format)', () {
      test('routes "Signature solving failed" → jsRuntimeUnavailable', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'ERROR: [youtube] dQw4w9WgXcQ: Signature solving failed; please '
            'install a JavaScript interpreter such as Deno or Node.js',
          ),
          DownloadErrorCode.jsRuntimeUnavailable,
        );
      });

      test('routes "n challenge solving failed" → jsRuntimeUnavailable', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'WARNING: [youtube] bSiyU_gZYhs: n challenge solving failed: '
            'Unsupported JS expression',
          ),
          DownloadErrorCode.jsRuntimeUnavailable,
        );
      });

      test('routes "could not find any usable JavaScript runtime" → '
          'jsRuntimeUnavailable', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'ERROR: Could not find any usable JavaScript runtime; '
            'install Deno or Node.js',
          ),
          DownloadErrorCode.jsRuntimeUnavailable,
        );
      });

      test('routes "no usable JavaScript runtime" → jsRuntimeUnavailable', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'No usable JavaScript runtime found',
          ),
          DownloadErrorCode.jsRuntimeUnavailable,
        );
      });

      test('routes our internal jsRuntimeUnavailable token', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'jsRuntimeUnavailable: Deno binary missing',
          ),
          DownloadErrorCode.jsRuntimeUnavailable,
        );
      });

      test('priority: stderr containing both "format" AND nsig wins as JS '
          'runtime, NOT formatUnavailable', () {
        // Real-world stderr: yt-dlp prints both "Requested format" warning
        // AND "n challenge solving failed" when Deno is missing. The JS
        // runtime cause is the actionable one — the format symptom is
        // downstream.
        expect(
          DownloadErrorClassifier.classifyMessage(
            'WARNING: Requested format is not available. '
            'n challenge solving failed: install Deno',
          ),
          DownloadErrorCode.jsRuntimeUnavailable,
        );
      });

      test('priority: stderr mentioning "sign in" AND nsig wins as JS runtime, '
          'NOT loginRequired', () {
        // The word "sign" appears in "Signature solving failed". Without
        // priority ordering, _loginRequiredPatterns ("sign in") could
        // accidentally match. We assert it does NOT.
        expect(
          DownloadErrorClassifier.classifyMessage(
            'Signature solving failed. Please sign in or install Deno.',
          ),
          DownloadErrorCode.jsRuntimeUnavailable,
        );
      });

      test(
        'plain formatUnavailable WITHOUT JS-runtime markers stays format',
        () {
          // Regression guard: pure format-unavailable (e.g. user picked 8K but
          // video maxes at 1080p) must NOT misroute to jsRuntimeUnavailable.
          expect(
            DownloadErrorClassifier.classifyMessage(
              'Requested format is not available. Use --list-formats',
            ),
            DownloadErrorCode.formatUnavailable,
          );
        },
      );
    });

    group('access denied (HTTP 403)', () {
      test('classifies HTTP 403 as accessDenied', () {
        expect(
          DownloadErrorClassifier.classifyMessage('HTTP error 403: Forbidden'),
          DownloadErrorCode.accessDenied,
        );
      });

      test('classifies 403 with status context as accessDenied', () {
        expect(
          DownloadErrorClassifier.classifyMessage('Server returned status 403'),
          DownloadErrorCode.accessDenied,
        );
      });

      test('classifies http forbidden as accessDenied', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'HTTP Forbidden: access denied',
          ),
          DownloadErrorCode.accessDenied,
        );
      });

      test('does not match filesystem permission denied as accessDenied', () {
        // "Permission denied" without HTTP 403 context should be permissionDenied, not accessDenied
        expect(
          DownloadErrorClassifier.classifyMessage(
            'Permission denied: /usr/local/bin',
          ),
          DownloadErrorCode.permissionDenied,
        );
      });
    });

    group('content unavailable', () {
      test('classifies copyright as contentUnavailable', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'Video removed due to copyright claim',
          ),
          DownloadErrorCode.contentUnavailable,
        );
      });

      test('classifies DMCA as contentUnavailable', () {
        expect(
          DownloadErrorClassifier.classifyMessage('Removed by DMCA takedown'),
          DownloadErrorCode.contentUnavailable,
        );
      });

      test('classifies terms of service as contentUnavailable', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'Removed for violating terms of service',
          ),
          DownloadErrorCode.contentUnavailable,
        );
      });

      test('classifies community guidelines as contentUnavailable', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'Removed for community guidelines violation',
          ),
          DownloadErrorCode.contentUnavailable,
        );
      });

      test('classifies removed by uploader as contentUnavailable', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'This video was removed by the uploader',
          ),
          DownloadErrorCode.contentUnavailable,
        );
      });
    });

    group('storage errors', () {
      test('classifies disk full', () {
        expect(
          DownloadErrorClassifier.classifyMessage('No space left on device'),
          DownloadErrorCode.diskFull,
        );
      });

      test('classifies ENOSPC as disk full', () {
        expect(
          DownloadErrorClassifier.classifyMessage('ENOSPC: write failed'),
          DownloadErrorCode.diskFull,
        );
      });

      test('classifies permission denied', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'Permission denied: /usr/local/bin',
          ),
          DownloadErrorCode.permissionDenied,
        );
      });

      test('classifies EACCES as permission denied', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'EACCES: operation not permitted',
          ),
          DownloadErrorCode.permissionDenied,
        );
      });

      test('classifies path not found', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'No such file or directory: /tmp/downloads',
          ),
          DownloadErrorCode.pathNotFound,
        );
      });
    });

    group('unknown errors', () {
      test('returns unknown for unrecognized messages', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'Something completely unexpected',
          ),
          DownloadErrorCode.unknown,
        );
      });

      test('returns unknown for empty string', () {
        expect(
          DownloadErrorClassifier.classifyMessage(''),
          DownloadErrorCode.unknown,
        );
      });
    });

    group('classify (Object)', () {
      test('classifies Exception objects', () {
        expect(
          DownloadErrorClassifier.classify(Exception('Connection timed out')),
          DownloadErrorCode.networkTimeout,
        );
      });

      test('classifies arbitrary objects via toString', () {
        expect(
          DownloadErrorClassifier.classify('No space left on device'),
          DownloadErrorCode.diskFull,
        );
      });
    });

    group('Task 67.2: retry classification integration', () {
      test('network errors are retryable', () {
        final code = DownloadErrorClassifier.classifyMessage(
          'Connection timed out',
        );
        expect(code, DownloadErrorCode.networkTimeout);
        expect(code.isRetryable, isTrue);
      });

      test('rate limited is retryable', () {
        final code = DownloadErrorClassifier.classifyMessage(
          'HTTP Error 429: Too Many Requests',
        );
        expect(code, DownloadErrorCode.rateLimited);
        expect(code.isRetryable, isTrue);
      });

      test('access denied is NOT retryable (expired URL)', () {
        final code = DownloadErrorClassifier.classifyMessage(
          'HTTP error 403: Forbidden',
        );
        expect(code, DownloadErrorCode.accessDenied);
        expect(code.isRetryable, isFalse);
      });

      test('video not found is NOT retryable', () {
        final code = DownloadErrorClassifier.classifyMessage(
          'Video unavailable',
        );
        expect(code, DownloadErrorCode.videoNotFound);
        expect(code.isRetryable, isFalse);
      });

      test('geo restricted is NOT retryable', () {
        final code = DownloadErrorClassifier.classifyMessage(
          'Video not available in your country',
        );
        expect(code, DownloadErrorCode.geoRestricted);
        expect(code.isRetryable, isFalse);
      });

      test('content unavailable is NOT retryable', () {
        final code = DownloadErrorClassifier.classifyMessage(
          'Removed by DMCA takedown',
        );
        expect(code, DownloadErrorCode.contentUnavailable);
        expect(code.isRetryable, isFalse);
      });

      test('age restricted is NOT retryable', () {
        final code = DownloadErrorClassifier.classifyMessage(
          'Please confirm your age',
        );
        expect(code, DownloadErrorCode.ageRestricted);
        expect(code.isRetryable, isFalse);
      });

      test('unknown errors are NOT retryable', () {
        final code = DownloadErrorClassifier.classifyMessage(
          'Something unexpected',
        );
        expect(code, DownloadErrorCode.unknown);
        expect(code.isRetryable, isFalse);
      });
    });

    group('structured HTTP prefixes (Rust engine)', () {
      test('HTTP_403_FORBIDDEN classifies as accessDenied', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'HTTP_403_FORBIDDEN: Access denied (URL may have expired)',
          ),
          DownloadErrorCode.accessDenied,
        );
      });

      test('HTTP_410_GONE classifies as videoNotFound', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'HTTP_410_GONE: Resource no longer available',
          ),
          DownloadErrorCode.videoNotFound,
        );
      });

      test('HTTP_429_TOO_MANY_REQUESTS classifies as rateLimited', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'HTTP_429_TOO_MANY_REQUESTS: Rate limited — too many requests',
          ),
          DownloadErrorCode.rateLimited,
        );
      });

      test('HTTP_404_NOT_FOUND classifies as videoNotFound', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'HTTP_404_NOT_FOUND: Resource not found',
          ),
          DownloadErrorCode.videoNotFound,
        );
      });

      test('HTTP_403 prefix takes priority over pattern matching', () {
        // Ensures the structured prefix check runs before the lower-case pattern
        expect(
          DownloadErrorClassifier.classifyMessage(
            'HTTP_403_FORBIDDEN: something',
          ),
          DownloadErrorCode.accessDenied,
        );
      });

      test('HTTP_410 is not retryable', () {
        final code = DownloadErrorClassifier.classifyMessage(
          'HTTP_410_GONE: Resource no longer available',
        );
        expect(code.isRetryable, isFalse);
      });

      test('HTTP_429 is retryable', () {
        final code = DownloadErrorClassifier.classifyMessage(
          'HTTP_429_TOO_MANY_REQUESTS: Rate limited',
        );
        expect(code.isRetryable, isTrue);
      });
    });

    group('SSL/TLS errors', () {
      test('classifies CERTIFICATE_VERIFY_FAILED as sslError', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'HandshakeException: CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate',
          ),
          DownloadErrorCode.sslError,
        );
      });

      test('classifies HandshakeException as sslError', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'HandshakeException: Connection terminated',
          ),
          DownloadErrorCode.sslError,
        );
      });

      test('classifies bad certificate as sslError', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'Bad certificate from server',
          ),
          DownloadErrorCode.sslError,
        );
      });

      test('classifies TlsException as sslError', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'TlsException: TLS handshake failed',
          ),
          DownloadErrorCode.sslError,
        );
      });

      test('sslError is retryable', () {
        final code = DownloadErrorClassifier.classifyMessage(
          'CERTIFICATE_VERIFY_FAILED',
        );
        expect(code, DownloadErrorCode.sslError);
        expect(code.isRetryable, isTrue);
      });

      test('sslError is a network error', () {
        final code = DownloadErrorClassifier.classifyMessage(
          'HandshakeException: bad certificate',
        );
        expect(code, DownloadErrorCode.sslError);
        expect(code.isNetworkError, isTrue);
      });

      test('SSL is checked before network-offline patterns', () {
        // HandshakeException contains "exception" which could match network patterns
        // SSL should take priority
        expect(
          DownloadErrorClassifier.classifyMessage(
            'HandshakeException: CERTIFICATE_VERIFY_FAILED',
          ),
          DownloadErrorCode.sslError,
        );
      });
    });

    group('CDN errors (Reddit DASH)', () {
      test('classifies conflicting range as serverError', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'ERROR: Conflicting range (start > end) in download',
          ),
          DownloadErrorCode.serverError,
        );
      });

      test('classifies downloaded file is empty as serverError', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'ERROR: Downloaded file is empty',
          ),
          DownloadErrorCode.serverError,
        );
      });

      test('classifies range not satisfiable as serverError', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'HTTP Error 416: Requested Range Not Satisfiable',
          ),
          DownloadErrorCode.serverError,
        );
      });

      test('CDN errors are retryable', () {
        final code = DownloadErrorClassifier.classifyMessage(
          'Conflicting range in DASH segment download',
        );
        expect(code, DownloadErrorCode.serverError);
        expect(code.isRetryable, isTrue);
      });
    });

    group('case insensitivity', () {
      test('matches regardless of case', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'SOCKETEXCEPTION: network is unreachable',
          ),
          DownloadErrorCode.networkOffline,
        );
        expect(
          DownloadErrorClassifier.classifyMessage('VIDEO UNAVAILABLE'),
          DownloadErrorCode.videoNotFound,
        );
      });
    });

    group('extended patterns (audit batch)', () {
      // Login-required additions
      test('classifies premium content as loginRequired', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'This content is premium only',
          ),
          DownloadErrorCode.loginRequired,
        );
      });

      test('classifies requires payment as loginRequired', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'This video requires payment',
          ),
          DownloadErrorCode.loginRequired,
        );
      });

      test('classifies requires a subscription as loginRequired', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'This content requires a subscription',
          ),
          DownloadErrorCode.loginRequired,
        );
      });

      test('classifies subscriber only as loginRequired', () {
        expect(
          DownloadErrorClassifier.classifyMessage('Subscriber only content'),
          DownloadErrorCode.loginRequired,
        );
      });

      test('classifies checkpoint required as loginRequired', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'Checkpoint required: verify identity',
          ),
          DownloadErrorCode.loginRequired,
        );
      });

      // Content unavailable additions
      test('classifies "is unavailable" as contentUnavailable', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'This content is unavailable',
          ),
          DownloadErrorCode.contentUnavailable,
        );
      });

      test('classifies "has been removed" as contentUnavailable', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'This video has been removed',
          ),
          DownloadErrorCode.contentUnavailable,
        );
      });

      test('classifies DRM protected as contentUnavailable', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'DRM protected content cannot be downloaded',
          ),
          DownloadErrorCode.contentUnavailable,
        );
      });

      test('classifies terminated as contentUnavailable', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'This account has been terminated',
          ),
          DownloadErrorCode.contentUnavailable,
        );
      });

      // Video not found additions
      test('classifies unsupported url as videoNotFound', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'Unsupported URL: https://example.com',
          ),
          DownloadErrorCode.videoNotFound,
        );
      });

      test('classifies content not found as videoNotFound', () {
        expect(
          DownloadErrorClassifier.classifyMessage('Content not found'),
          DownloadErrorCode.videoNotFound,
        );
      });

      // Rate limited addition
      test('classifies "please wait a few minutes" as rateLimited', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'Please wait a few minutes before trying again',
          ),
          DownloadErrorCode.rateLimited,
        );
      });

      // Server error — more specific 500 matching
      test('classifies "http error 500" as serverError', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'HTTP error 500: Internal Server Error',
          ),
          DownloadErrorCode.serverError,
        );
      });

      test('classifies "status 500" as serverError', () {
        expect(
          DownloadErrorClassifier.classifyMessage('Server returned status 500'),
          DownloadErrorCode.serverError,
        );
      });

      test('classifies "error 500" as serverError', () {
        expect(
          DownloadErrorClassifier.classifyMessage('error 500 from server'),
          DownloadErrorCode.serverError,
        );
      });

      test('does not match bare 500 without context as serverError', () {
        // A string with "500" but no http/error/status context should NOT match
        expect(
          DownloadErrorClassifier.classifyMessage(
            'Downloaded 500 files successfully',
          ),
          DownloadErrorCode.unknown,
        );
      });
    });

    // Phase 1 (Codex review 2026-05-13) — cookie DB lock detection.
    // Pin every variant yt-dlp emits when --cookies-from-browser
    // hits issue 7271 (Chrome / Edge / Firefox holding the SQLite
    // file open). Misroute would push the user into auto-login;
    // correct route lets the fallback chain advance.
    group('cookieDbLocked', () {
      test('classifies Chrome lock as cookieDbLocked', () {
        // The canonical Windows symptom — production log
        // 2026-05-12 §138 surfaced exactly this string.
        expect(
          DownloadErrorClassifier.classifyMessage(
            'ERROR: Could not copy Chrome cookie database. '
            'See https://github.com/yt-dlp/yt-dlp/issues/7271',
          ),
          DownloadErrorCode.cookieDbLocked,
        );
      });

      test('classifies Edge / Firefox / Brave / generic lock', () {
        for (final variant in [
          'Could not copy Edge cookie database',
          'Could not copy Firefox cookie database',
          'Could not copy Brave cookie database',
          'Could not copy cookie database', // generic form
        ]) {
          expect(
            DownloadErrorClassifier.classifyMessage(variant),
            DownloadErrorCode.cookieDbLocked,
            reason: 'variant "$variant" must classify as cookieDbLocked',
          );
        }
      });

      test('classifies Windows DPAPI decrypt failure as cookieDbLocked', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'ERROR: Failed to decrypt with DPAPI. '
            'See https://github.com/yt-dlp/yt-dlp/issues/10927 for more info',
          ),
          DownloadErrorCode.cookieDbLocked,
        );
      });

      test('cookieDbLocked precedes loginRequired in classifier order '
          '(composite stderr does not misroute to auto-login)', () {
        const composite =
            'ERROR: Could not copy Chrome cookie database. '
            'See https://github.com/yt-dlp/yt-dlp/issues/7271 '
            'Sign in to confirm you are not a bot.';
        expect(
          DownloadErrorClassifier.classifyMessage(composite),
          DownloadErrorCode.cookieDbLocked,
        );
      });

      test('DPAPI failure precedes loginRequired in classifier order '
          '(composite stderr does not misroute to auto-login)', () {
        const composite =
            'ERROR: Failed to decrypt with DPAPI. '
            'Sign in to confirm you are not a bot.';
        expect(
          DownloadErrorClassifier.classifyMessage(composite),
          DownloadErrorCode.cookieDbLocked,
        );
      });

      test('plain loginRequired still classifies as loginRequired', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'ERROR: [youtube] abc: Sign in to confirm you are not a bot. '
            'Use --cookies-from-browser or --cookies for the authentication.',
          ),
          DownloadErrorCode.loginRequired,
        );
      });
    });

    // DL-004 (06-09 bounded telemetry 3-cut): the 1.7.3 `unknown` bucket was
    // ~51% and hid known shapes — many literally prefixed `ffmpegerror:` /
    // `ytdlpexception:` yet still routed to unknown. Each shape below is a
    // real (sanitized) production message that used to land in unknown.
    // Mapping targets are EXISTING codes only (no new enum). 6 of the 7
    // targets (ffmpegError / contentUnavailable / ytdlpBinaryMissing) are
    // behavior-neutral — non-retryable, no fallback, no repair trigger; only
    // telemetry bucketing + the user-facing hint/icon change. The 7th,
    // restricted-low-quality → formatUnavailable, intentionally routes into
    // formatUnavailable's EXISTING download-stage recovery (no-cookie retry +
    // cookie/browser-chain advance) — by design, already locked by
    // start_download_usecase_test.dart.
    group('DL-004: 06-09 telemetry reclassification (was unknown)', () {
      test('ffmpeg post-processing exceeded (hyphenated) → ffmpegError', () {
        for (final variant in [
          'ffmpegError:ffmpeg post-processing exceeded 30m while '
              'converting to mp4.',
          'ffmpegError:ffmpeg post-processing exceeded 5m during audio '
              'extraction.',
          'ffmpeg post-processing exceeded 1h 12m while converting to '
              'video (retry).',
        ]) {
          expect(
            DownloadErrorClassifier.classifyMessage(variant),
            DownloadErrorCode.ffmpegError,
            reason: '"$variant" must classify as ffmpegError',
          );
        }
      });

      test('ffmpeg merge exceeded → ffmpegError', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'ffmpegError:ffmpeg merge exceeded 5m',
          ),
          DownloadErrorCode.ffmpegError,
        );
      });

      test('recode to .mp4 failed → ffmpegError', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'Recode to .mp4 failed. Try mp4 or mkv for the same video.',
          ),
          DownloadErrorCode.ffmpegError,
        );
      });

      test('ffprobe required to verify resolution cap → ffmpegError', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'ffprobe is required to verify the 1080p resolution cap before '
            'completing this download. Open Settings to repair binaries.',
          ),
          DownloadErrorCode.ffmpegError,
        );
      });

      test('app interrupted during conversion → ffmpegError', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'App was interrupted during conversion',
          ),
          DownloadErrorCode.ffmpegError,
        );
      });

      test('YouTube restricted low-quality → formatUnavailable', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'ytdlpException(ytDlpErrorType.formatNotAvailable): YouTube '
            'returned only restricted low-quality formats',
          ),
          DownloadErrorCode.formatUnavailable,
        );
      });

      test('no downloadable content / no files downloaded → '
          'contentUnavailable', () {
        for (final variant in [
          'AppException.download(message: No downloadable content found at '
              'this url, url: null)',
          'ERROR: no files were downloaded',
        ]) {
          expect(
            DownloadErrorClassifier.classifyMessage(variant),
            DownloadErrorCode.contentUnavailable,
            reason: '"$variant" must classify as contentUnavailable',
          );
        }
      });

      test('failed to execute yt-dlp → ytdlpBinaryMissing', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'ytdlpException(ytDlpErrorType.unknown): anyhowException(failed '
            'to execute yt-dlp caused by No such file or directory)',
          ),
          DownloadErrorCode.ytdlpBinaryMissing,
        );
      });

      // Deferred-on-purpose boundary guards: these two shapes were in the
      // GO list but are intentionally NOT reclassified in this commit, so
      // they must STILL be unknown. Locking that here prevents silent drift.
      // - "maximum retry attempts reached" is a retry WRAPPER that masks the
      //   original error; the fix is upstream (preserve the original code
      //   through retry), not pattern-matching the wrapper.
      // - "N bytes read, M more expected" would map to serverError, which is
      //   RETRYABLE → it would add auto-retry behavior. Out of scope for a
      //   classification-only, zero-behavior-change commit.
      test('DEFERRED: "maximum retry attempts reached" stays unknown', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'Maximum retry attempts reached',
          ),
          DownloadErrorCode.unknown,
        );
      });

      test('DEFERRED: incomplete-read "more expected" stays unknown', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'download failed: ERROR: [download] Got error: 12345 bytes read, '
            '67890 more expected. Giving up after 10 retries.',
          ),
          DownloadErrorCode.unknown,
        );
      });
    });

    // =========================================================================
    // DL-017 — yt-dlp spawn-failure classification (06-11 production wave:
    // 40 rows/day, 94/95 Windows). The poisoning mechanism these tests lock:
    // Dart's ProcessException.toString() embeds the FULL command line, whose
    // literal `--socket-timeout 30` flag text satisfied the bare 'timeout'
    // pattern → networkTimeout (RETRYABLE) → infinite futile auto-retry
    // while the engine binary was absent. Classification must key on
    // exception type + binary evidence, never on the localized OS message.
    // =========================================================================
    group('DL-017: yt-dlp spawn failure beats command-line poisoning', () {
      // Real production shape (sanitized): EN Windows. FAILS pre-fix as
      // networkTimeout because of the --socket-timeout flag in the command.
      test('EN ProcessException with --socket-timeout in command '
          '→ ytdlpBinaryMissing, NOT networkTimeout', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'AppException.download(message: ProcessException: The system '
            'cannot find the file specified.\n'
            '  Command: "C:\\Users\\u\\AppData\\Roaming\\VidCombo Desktop\\'
            'bin\\yt-dlp.exe" --newline --progress --continue --no-warnings '
            '--no-playlist --no-check-certificates --socket-timeout 30 '
            'https://www.youtube.com/watch?v=x)',
          ),
          DownloadErrorCode.ytdlpBinaryMissing,
        );
      });

      test('JA localized Windows message → ytdlpBinaryMissing', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'ProcessException: 指定されたファイルが見つかりません。\n'
            '  Command: "C:\\Users\\u\\AppData\\Roaming\\VidCombo Desktop\\'
            'bin\\yt-dlp.exe" --newline --progress --socket-timeout 30 url',
          ),
          DownloadErrorCode.ytdlpBinaryMissing,
        );
      });

      test('KO localized Windows message → ytdlpBinaryMissing', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'ProcessException: 지정된 파일을 찾을 수 없습니다.\n'
            '  Command: "C:\\bin\\yt-dlp.exe" --newline --socket-timeout 30',
          ),
          DownloadErrorCode.ytdlpBinaryMissing,
        );
      });

      test('ZH localized Windows message → ytdlpBinaryMissing', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'ProcessException: 系統找不到指定的檔案。\n'
            '  Command: "C:\\bin\\yt-dlp.exe" --newline --socket-timeout 30',
          ),
          DownloadErrorCode.ytdlpBinaryMissing,
        );
      });

      test('terminal repair-exhausted message → ytdlpBinaryMissing '
          '(via the existing failed-to-execute pattern)', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'Failed to execute yt-dlp: the download engine binary is missing '
            'and automatic repair did not succeed — your antivirus may have '
            'quarantined it.',
          ),
          DownloadErrorCode.ytdlpBinaryMissing,
        );
      });

      test('GUARD: plain network timeout is unaffected', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'Connection timed out after 30000 milliseconds',
          ),
          DownloadErrorCode.networkTimeout,
        );
      });

      test('GUARD: non-yt-dlp ProcessException is NOT ytdlpBinaryMissing', () {
        expect(
          DownloadErrorClassifier.classifyMessage(
            'ProcessException: Access is denied.\n'
            '  Command: "C:\\tools\\sometool.exe" -i input.mp4',
          ),
          isNot(DownloadErrorCode.ytdlpBinaryMissing),
        );
      });
    });
  });
}
