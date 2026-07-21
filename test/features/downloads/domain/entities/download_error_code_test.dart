import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/domain/entities/download_error_code.dart';

void main() {
  group('DownloadErrorCode', () {
    group('isNetworkError', () {
      test('network errors return true', () {
        expect(DownloadErrorCode.networkOffline.isNetworkError, isTrue);
        expect(DownloadErrorCode.networkTimeout.isNetworkError, isTrue);
        expect(DownloadErrorCode.serverError.isNetworkError, isTrue);
        expect(DownloadErrorCode.connectionRefused.isNetworkError, isTrue);
      });

      test('non-network errors return false', () {
        expect(DownloadErrorCode.videoNotFound.isNetworkError, isFalse);
        expect(DownloadErrorCode.diskFull.isNetworkError, isFalse);
        expect(DownloadErrorCode.loginRequired.isNetworkError, isFalse);
        expect(DownloadErrorCode.unknown.isNetworkError, isFalse);
      });
    });

    group('isRetryable', () {
      test('retryable errors return true', () {
        expect(DownloadErrorCode.networkOffline.isRetryable, isTrue);
        expect(DownloadErrorCode.networkTimeout.isRetryable, isTrue);
        expect(DownloadErrorCode.serverError.isRetryable, isTrue);
        expect(DownloadErrorCode.connectionRefused.isRetryable, isTrue);
        expect(DownloadErrorCode.rateLimited.isRetryable, isTrue);
      });

      test('accessDenied is NOT retryable (expired CDN URL should not auto-retry)', () {
        expect(DownloadErrorCode.accessDenied.isRetryable, isFalse);
      });

      test('non-retryable errors return false', () {
        expect(DownloadErrorCode.videoNotFound.isRetryable, isFalse);
        expect(DownloadErrorCode.geoRestricted.isRetryable, isFalse);
        expect(DownloadErrorCode.loginRequired.isRetryable, isFalse);
        expect(DownloadErrorCode.ageRestricted.isRetryable, isFalse);
        expect(DownloadErrorCode.contentUnavailable.isRetryable, isFalse);
        expect(DownloadErrorCode.diskFull.isRetryable, isFalse);
        expect(DownloadErrorCode.permissionDenied.isRetryable, isFalse);
        expect(DownloadErrorCode.unknown.isRetryable, isFalse);
      });
    });

    group('icon', () {
      test('all error codes have an icon', () {
        for (final code in DownloadErrorCode.values) {
          expect(code.icon, isA<IconData>());
        }
      });

      test('each code has a distinct icon', () {
        expect(DownloadErrorCode.networkOffline.icon, Icons.wifi_off_rounded);
        expect(DownloadErrorCode.diskFull.icon, Icons.storage_rounded);
        expect(DownloadErrorCode.loginRequired.icon, Icons.lock_rounded);
      });
    });

    group('hint', () {
      test('all error codes have a non-empty hint', () {
        for (final code in DownloadErrorCode.values) {
          expect(code.hint, isNotEmpty);
        }
      });

      // Hint now resolves through AppLocalizations.errorFeedbackHint(). In a
      // production app the EasyLocalization widget wraps the tree and `.tr()`
      // returns localized prose; in this pure-unit test there is no locale
      // loaded, so `.tr()` returns the raw `errorFeedback.hint.<code>` key.
      // We assert on either path so the contract holds in both environments.

      test('accessDenied hint maps to errorFeedback.hint.accessDenied', () {
        final hint = DownloadErrorCode.accessDenied.hint;
        expect(hint, isNotEmpty);
        expect(
          hint,
          anyOf(
            equals('errorFeedback.hint.accessDenied'),
            contains('expired'),
          ),
        );
      });

      test('contentUnavailable hint maps to errorFeedback.hint.contentUnavailable', () {
        final hint = DownloadErrorCode.contentUnavailable.hint;
        expect(hint, isNotEmpty);
        expect(
          hint,
          anyOf(
            equals('errorFeedback.hint.contentUnavailable'),
            contains('no longer available'),
          ),
        );
      });

      test('rateLimited hint maps to errorFeedback.hint.rateLimited', () {
        final hint = DownloadErrorCode.rateLimited.hint;
        expect(hint, isNotEmpty);
        expect(
          hint,
          anyOf(
            equals('errorFeedback.hint.rateLimited'),
            contains('retry'),
          ),
        );
      });
    });

    group('new error codes', () {
      test('accessDenied is not a network error', () {
        expect(DownloadErrorCode.accessDenied.isNetworkError, isFalse);
      });

      test('contentUnavailable is not a network error', () {
        expect(DownloadErrorCode.contentUnavailable.isNetworkError, isFalse);
      });

      test('accessDenied has block icon', () {
        expect(DownloadErrorCode.accessDenied.icon, Icons.block_rounded);
      });

      test('contentUnavailable has cloud_off icon', () {
        expect(DownloadErrorCode.contentUnavailable.icon, Icons.cloud_off_rounded);
      });

      test('jsRuntimeUnavailable is not a network error', () {
        // Missing JS runtime is an app-side binary issue, not a connectivity
        // problem — must NOT be classified as network so the UI does not
        // show "check your internet" guidance.
        expect(DownloadErrorCode.jsRuntimeUnavailable.isNetworkError, isFalse);
      });

      test('jsRuntimeUnavailable is not retryable', () {
        // Auto-retry without a working runtime would just loop the same
        // failure. BinaryManager re-downloads Deno in the background; the
        // user retries manually after the engine is restored.
        expect(DownloadErrorCode.jsRuntimeUnavailable.isRetryable, isFalse);
      });

      test('jsRuntimeUnavailable has javascript icon', () {
        expect(
          DownloadErrorCode.jsRuntimeUnavailable.icon,
          Icons.javascript_rounded,
        );
      });

      test('jsRuntimeUnavailable round-trips via stored message', () {
        // Persisted-error pipeline: error written to DB as
        // `jsRuntimeUnavailable:<raw>`, must parse back to the enum so
        // history rows render the right icon/title on relaunch.
        expect(
          DownloadErrorCodeX.fromStoredMessage(
            'jsRuntimeUnavailable:Signature solving failed',
          ),
          DownloadErrorCode.jsRuntimeUnavailable,
        );
      });
    });

    group('fromStoredMessage', () {
      test('parses valid stored message', () {
        expect(
          DownloadErrorCodeX.fromStoredMessage('networkOffline:Socket exception'),
          DownloadErrorCode.networkOffline,
        );
        expect(
          DownloadErrorCodeX.fromStoredMessage('diskFull:No space left on device'),
          DownloadErrorCode.diskFull,
        );
        expect(
          DownloadErrorCodeX.fromStoredMessage('unknown:Something happened'),
          DownloadErrorCode.unknown,
        );
      });

      test('returns null for null or empty input', () {
        expect(DownloadErrorCodeX.fromStoredMessage(null), isNull);
        expect(DownloadErrorCodeX.fromStoredMessage(''), isNull);
      });

      test('returns null for message without colon', () {
        expect(DownloadErrorCodeX.fromStoredMessage('just a message'), isNull);
      });

      test('returns null for unknown code name', () {
        expect(DownloadErrorCodeX.fromStoredMessage('foobar:some error'), isNull);
      });

      test('handles colon in raw message', () {
        expect(
          DownloadErrorCodeX.fromStoredMessage('serverError:HTTP 500: Internal'),
          DownloadErrorCode.serverError,
        );
      });
    });

    group('detailFromStoredMessage', () {
      test('extracts detail from stored message', () {
        expect(
          DownloadErrorCodeX.detailFromStoredMessage('networkTimeout:Timed out after 30s'),
          'Timed out after 30s',
        );
      });

      test('returns null for null or empty input', () {
        expect(DownloadErrorCodeX.detailFromStoredMessage(null), isNull);
        expect(DownloadErrorCodeX.detailFromStoredMessage(''), isNull);
      });

      test('returns original string for legacy format (no colon)', () {
        expect(
          DownloadErrorCodeX.detailFromStoredMessage('Legacy error message'),
          'Legacy error message',
        );
      });

      test('handles colon in raw message', () {
        expect(
          DownloadErrorCodeX.detailFromStoredMessage('serverError:HTTP 500: Internal Server Error'),
          'HTTP 500: Internal Server Error',
        );
      });
    });
  });
}
