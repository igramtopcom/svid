import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/errors/app_exception.dart';

void main() {
  group('AppException', () {
    group('factory constructors', () {
      test('network creates NetworkException', () {
        const ex = AppException.network(message: 'timeout', statusCode: 408);
        expect(ex, isA<NetworkException>());
        expect(ex.isNetworkError, isTrue);
        expect(ex.isDownloadError, isFalse);
      });

      test('download creates DownloadException', () {
        const ex = AppException.download(message: 'failed', url: 'https://x.com');
        expect(ex, isA<DownloadException>());
        expect(ex.isDownloadError, isTrue);
        expect(ex.isNetworkError, isFalse);
      });

      test('storage creates StorageException', () {
        const ex = AppException.storage(message: 'disk full', path: '/tmp');
        expect(ex, isA<StorageException>());
        expect(ex.isStorageError, isTrue);
      });

      test('permission creates PermissionException', () {
        const ex = AppException.permission(message: 'denied', resource: 'camera');
        expect(ex, isA<PermissionException>());
      });

      test('validation creates ValidationException', () {
        const ex = AppException.validation(
          message: 'invalid',
          errors: {'url': 'required'},
        );
        expect(ex, isA<ValidationException>());
      });

      test('unknown creates UnknownException', () {
        const ex = AppException.unknown(message: 'something broke');
        expect(ex, isA<UnknownException>());
      });

      test('rust creates RustException', () {
        const ex = AppException.rust(message: 'ffi crash', details: 'segfault');
        expect(ex, isA<RustException>());
      });
    });

    group('userMessage', () {
      test('network with statusCode', () {
        const ex = AppException.network(message: 'timeout', statusCode: 408);
        expect(ex.userMessage, 'Network error (408): timeout');
      });

      test('network without statusCode', () {
        const ex = AppException.network(message: 'no internet');
        expect(ex.userMessage, 'Network error: no internet');
      });

      test('download', () {
        const ex = AppException.download(message: 'cancelled');
        expect(ex.userMessage, 'Download failed: cancelled');
      });

      test('storage', () {
        const ex = AppException.storage(message: 'no space');
        expect(ex.userMessage, 'Storage error: no space');
      });

      test('permission', () {
        const ex = AppException.permission(message: 'blocked');
        expect(ex.userMessage, 'Permission denied: blocked');
      });

      test('validation', () {
        const ex = AppException.validation(message: 'bad input');
        expect(ex.userMessage, 'Validation error: bad input');
      });

      test('unknown', () {
        const ex = AppException.unknown(message: 'oops');
        expect(ex.userMessage, 'An error occurred: oops');
      });

      test('rust', () {
        const ex = AppException.rust(message: 'panic');
        expect(ex.userMessage, 'Native error: panic');
      });
    });

    group('type checks', () {
      test('isNetworkError correctly identifies network exceptions', () {
        const network = AppException.network(message: 'x');
        const download = AppException.download(message: 'x');
        expect(network.isNetworkError, isTrue);
        expect(download.isNetworkError, isFalse);
      });

      test('isDownloadError correctly identifies download exceptions', () {
        const download = AppException.download(message: 'x');
        const storage = AppException.storage(message: 'x');
        expect(download.isDownloadError, isTrue);
        expect(storage.isDownloadError, isFalse);
      });

      test('isStorageError correctly identifies storage exceptions', () {
        const storage = AppException.storage(message: 'x');
        const network = AppException.network(message: 'x');
        expect(storage.isStorageError, isTrue);
        expect(network.isStorageError, isFalse);
      });
    });
  });
}
