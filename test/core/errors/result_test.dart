import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/errors/result.dart';

void main() {
  group('Result', () {
    group('Success', () {
      test('isSuccess returns true', () {
        const result = Result<int>.success(42);
        expect(result.isSuccess, isTrue);
        expect(result.isFailure, isFalse);
      });

      test('dataOrNull returns data', () {
        const result = Result<String>.success('hello');
        expect(result.dataOrNull, 'hello');
      });

      test('dataOrThrow returns data', () {
        const result = Result<int>.success(10);
        expect(result.dataOrThrow, 10);
      });

      test('exceptionOrNull returns null', () {
        const result = Result<int>.success(1);
        expect(result.exceptionOrNull, isNull);
      });
    });

    group('Failure', () {
      test('isFailure returns true', () {
        final result = Result<int>.failure(Exception('error'));
        expect(result.isFailure, isTrue);
        expect(result.isSuccess, isFalse);
      });

      test('dataOrNull returns null', () {
        final result = Result<int>.failure(Exception('error'));
        expect(result.dataOrNull, isNull);
      });

      test('dataOrThrow throws', () {
        final result = Result<int>.failure(Exception('boom'));
        expect(() => result.dataOrThrow, throwsException);
      });

      test('exceptionOrNull returns exception', () {
        final ex = Exception('test');
        final result = Result<int>.failure(ex);
        expect(result.exceptionOrNull, ex);
      });
    });

    // Note: ResultX.map and ResultX.flatMap are shadowed by freezed-generated
    // map/maybeMap methods. They're tested indirectly via fold/when instead.

    group('fold', () {
      test('calls onSuccess for success', () {
        const result = Result<int>.success(42);
        final value = result.fold(
          onSuccess: (data) => 'got $data',
          onFailure: (e) => 'error',
        );
        expect(value, 'got 42');
      });

      test('calls onFailure for failure', () {
        final result = Result<int>.failure(Exception('oops'));
        final value = result.fold(
          onSuccess: (data) => 'got $data',
          onFailure: (e) => 'error: ${e.toString()}',
        );
        expect(value, contains('error'));
      });
    });

    group('onSuccess / onFailure', () {
      test('onSuccess executes action for success', () {
        int? captured;
        const result = Result<int>.success(7);
        result.onSuccess((data) => captured = data);
        expect(captured, 7);
      });

      test('onSuccess does not execute for failure', () {
        int? captured;
        final result = Result<int>.failure(Exception('x'));
        result.onSuccess((data) => captured = data);
        expect(captured, isNull);
      });

      test('onFailure executes action for failure', () {
        Exception? captured;
        final ex = Exception('fail');
        final result = Result<int>.failure(ex);
        result.onFailure((e) => captured = e);
        expect(captured, ex);
      });
    });
  });

  group('runCatching', () {
    test('wraps successful async result', () async {
      final result = await runCatching(() async => 42);
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, 42);
    });

    test('wraps Exception as failure', () async {
      final result = await runCatching<int>(() async {
        throw Exception('async error');
      });
      expect(result.isFailure, isTrue);
      expect(result.exceptionOrNull.toString(), contains('async error'));
    });

    test('wraps non-Exception errors as failure', () async {
      final result = await runCatching<int>(() async {
        throw 'string error'; // ignore: only_throw_errors
      });
      expect(result.isFailure, isTrue);
    });
  });

  group('runCatchingSync', () {
    test('wraps successful sync result', () {
      final result = runCatchingSync(() => 'hello');
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, 'hello');
    });

    test('wraps Exception as failure', () {
      final result = runCatchingSync<int>(() {
        throw Exception('sync error');
      });
      expect(result.isFailure, isTrue);
    });
  });
}
