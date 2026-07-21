import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/binaries/binary_update_error_code.dart';

void main() {
  group('BinaryUpdateErrorCode', () {
    group('classify', () {
      test('classifies SocketException as networkOffline', () {
        expect(
          BinaryUpdateErrorCodeX.classify('SocketException: Connection failed'),
          BinaryUpdateErrorCode.networkOffline,
        );
      });

      test('classifies failed host lookup as networkOffline', () {
        expect(
          BinaryUpdateErrorCodeX.classify('Failed host lookup: github.com'),
          BinaryUpdateErrorCode.networkOffline,
        );
      });

      test('classifies TimeoutException as networkTimeout', () {
        expect(
          BinaryUpdateErrorCodeX.classify('TimeoutException after 30s'),
          BinaryUpdateErrorCode.networkTimeout,
        );
      });

      test('classifies connection timed out as networkTimeout', () {
        expect(
          BinaryUpdateErrorCodeX.classify('Connection timed out'),
          BinaryUpdateErrorCode.networkTimeout,
        );
      });

      test('classifies HTTP 403 as httpError', () {
        expect(
          BinaryUpdateErrorCodeX.classify('Download failed: HTTP 403'),
          BinaryUpdateErrorCode.httpError,
        );
      });

      test('classifies HTTP 500 as httpError', () {
        expect(
          BinaryUpdateErrorCodeX.classify('Download failed: HTTP 500'),
          BinaryUpdateErrorCode.httpError,
        );
      });

      test('classifies EACCES as permissionDenied', () {
        expect(
          BinaryUpdateErrorCodeX.classify('FileSystemException: EACCES'),
          BinaryUpdateErrorCode.permissionDenied,
        );
      });

      test('classifies permission denied string as permissionDenied', () {
        expect(
          BinaryUpdateErrorCodeX.classify('Permission denied: /usr/bin/yt-dlp'),
          BinaryUpdateErrorCode.permissionDenied,
        );
      });

      test('classifies ENOSPC as diskFull', () {
        expect(
          BinaryUpdateErrorCodeX.classify('FileSystemException: ENOSPC'),
          BinaryUpdateErrorCode.diskFull,
        );
      });

      test('classifies no space left as diskFull', () {
        expect(
          BinaryUpdateErrorCodeX.classify('No space left on device'),
          BinaryUpdateErrorCode.diskFull,
        );
      });

      test('classifies backup failed as backupFailed', () {
        expect(
          BinaryUpdateErrorCodeX.classify('Backup failed: FileSystemException'),
          BinaryUpdateErrorCode.backupFailed,
        );
      });

      test('classifies not found in archive as extractionFailed', () {
        expect(
          BinaryUpdateErrorCodeX.classify('Binary not found in archive: yt-dlp'),
          BinaryUpdateErrorCode.extractionFailed,
        );
      });

      test('classifies unable to detect archive as archiveCorrupt', () {
        expect(
          BinaryUpdateErrorCodeX.classify('Unable to detect archive format'),
          BinaryUpdateErrorCode.archiveCorrupt,
        );
      });

      test('classifies FormatException as archiveCorrupt', () {
        expect(
          BinaryUpdateErrorCodeX.classify('FormatException: invalid data'),
          BinaryUpdateErrorCode.archiveCorrupt,
        );
      });

      test('classifies unknown error as unknown', () {
        expect(
          BinaryUpdateErrorCodeX.classify('Something went wrong'),
          BinaryUpdateErrorCode.unknown,
        );
      });

      test('classifies empty string as unknown', () {
        expect(
          BinaryUpdateErrorCodeX.classify(''),
          BinaryUpdateErrorCode.unknown,
        );
      });
    });

    group('isRetryable', () {
      test('network errors are retryable', () {
        expect(BinaryUpdateErrorCode.networkOffline.isRetryable, isTrue);
        expect(BinaryUpdateErrorCode.networkTimeout.isRetryable, isTrue);
        expect(BinaryUpdateErrorCode.httpError.isRetryable, isTrue);
      });

      test('filesystem errors are not retryable', () {
        expect(BinaryUpdateErrorCode.permissionDenied.isRetryable, isFalse);
        expect(BinaryUpdateErrorCode.diskFull.isRetryable, isFalse);
        expect(BinaryUpdateErrorCode.backupFailed.isRetryable, isFalse);
      });

      test('archive errors are not retryable', () {
        expect(BinaryUpdateErrorCode.extractionFailed.isRetryable, isFalse);
        expect(BinaryUpdateErrorCode.archiveCorrupt.isRetryable, isFalse);
      });

      test('unknown is not retryable', () {
        expect(BinaryUpdateErrorCode.unknown.isRetryable, isFalse);
      });
    });

    group('icon', () {
      test('returns non-null IconData for all codes', () {
        for (final code in BinaryUpdateErrorCode.values) {
          expect(code.icon, isA<IconData>());
        }
      });
    });
  });
}
