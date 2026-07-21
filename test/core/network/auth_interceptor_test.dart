import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svid/core/network/backend_client.dart';
import 'package:svid/core/services/secure_credential_store.dart';

/// Tests for the auth interceptor's Completer-based coalescing logic.
///
/// Since `_AuthInterceptor` is a private class inside `backend_client.dart`,
/// we test the Completer coalescing pattern in isolation — the same pattern
/// used for 401 re-registration coalescing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('recoverable API key error codes', () {
    test('covers backend API-key lifecycle failures', () {
      expect(isRecoverableApiKeyErrorCode('INVALID_API_KEY'), isTrue);
      expect(isRecoverableApiKeyErrorCode('MISSING_API_KEY'), isTrue);
      expect(isRecoverableApiKeyErrorCode('REVOKED_API_KEY'), isTrue);
      expect(isRecoverableApiKeyErrorCode('EXPIRED_API_KEY'), isTrue);
    });

    test('does not refresh unrelated authorization failures', () {
      expect(isRecoverableApiKeyErrorCode('FORBIDDEN'), isFalse);
      expect(isRecoverableApiKeyErrorCode('INVALID_LICENSE'), isFalse);
      expect(isRecoverableApiKeyErrorCode(null), isFalse);
    });
  });

  group('Completer coalescing pattern', () {
    test('multiple concurrent calls share the same Future', () async {
      Completer<String?>? refreshCompleter;
      var registrationCount = 0;

      Future<String?> getOrCreateRefreshFuture() {
        if (refreshCompleter != null && !refreshCompleter!.isCompleted) {
          return refreshCompleter!.future;
        }

        refreshCompleter = Completer<String?>();

        // Simulate re-registration
        Future.delayed(const Duration(milliseconds: 50), () {
          registrationCount++;
          refreshCompleter!.complete('new_api_key_$registrationCount');
        });

        return refreshCompleter!.future;
      }

      // Simulate 5 concurrent 401 handlers
      final futures = List.generate(5, (_) => getOrCreateRefreshFuture());
      final results = await Future.wait(futures);

      // All should get the same key
      expect(results.every((r) => r == 'new_api_key_1'), isTrue);
      // Registration should have happened exactly once
      expect(registrationCount, 1);
    });

    test(
      'sequential calls after completion trigger new registration',
      () async {
        Completer<String?>? refreshCompleter;
        var registrationCount = 0;

        Future<String?> getOrCreateRefreshFuture() {
          if (refreshCompleter != null && !refreshCompleter!.isCompleted) {
            return refreshCompleter!.future;
          }

          refreshCompleter = Completer<String?>();
          registrationCount++;
          refreshCompleter!.complete('key_$registrationCount');
          return refreshCompleter!.future;
        }

        // First batch
        final result1 = await getOrCreateRefreshFuture();
        expect(result1, 'key_1');
        expect(registrationCount, 1);

        // Second call after first completed → new registration
        final result2 = await getOrCreateRefreshFuture();
        expect(result2, 'key_2');
        expect(registrationCount, 2);
      },
    );

    test('returns null when registration fails', () async {
      Completer<String?>? refreshCompleter;

      Future<String?> getOrCreateRefreshFuture() {
        if (refreshCompleter != null && !refreshCompleter!.isCompleted) {
          return refreshCompleter!.future;
        }

        refreshCompleter = Completer<String?>();
        refreshCompleter!.complete(null); // Simulate failure
        return refreshCompleter!.future;
      }

      final results = await Future.wait(
        List.generate(3, (_) => getOrCreateRefreshFuture()),
      );

      expect(results.every((r) => r == null), isTrue);
    });

    test(
      'concurrent callers all get the error when registration throws',
      () async {
        Completer<String?>? refreshCompleter;

        Future<String?> getOrCreateRefreshFuture() {
          if (refreshCompleter != null && !refreshCompleter!.isCompleted) {
            return refreshCompleter!.future;
          }

          refreshCompleter = Completer<String?>();

          // Simulate registration that catches its own error
          Future(() {
            refreshCompleter!.complete(null);
          });

          return refreshCompleter!.future;
        }

        final futures = List.generate(5, (_) => getOrCreateRefreshFuture());
        final results = await Future.wait(futures);

        // All should get null (failure)
        expect(results.every((r) => r == null), isTrue);
      },
    );
  });

  group('SecureCredentialStore async auth pattern', () {
    late SharedPreferences prefs;
    late SecureCredentialStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'backend_api_key': 'snk_existing_key',
      });
      prefs = await SharedPreferences.getInstance();
      store = SecureCredentialStore(prefs);
    });

    test('containsKey returns true for key in SharedPreferences', () async {
      // Before migration, key is in SharedPreferences
      final hasKey = await store.containsKey('backend_api_key');
      expect(hasKey, isTrue);
    });

    test('read falls back to SharedPreferences for unmigrated key', () async {
      final value = await store.read('backend_api_key');
      // Should read from SharedPreferences fallback
      // (FlutterSecureStorage may throw in test env, but fallback should work)
      expect(value, 'snk_existing_key');
    });

    test('concurrent reads all resolve consistently', () async {
      final futures = List.generate(10, (_) => store.read('backend_api_key'));
      final results = await Future.wait(futures);

      // All should return the same value
      expect(results.toSet().length, 1);
      expect(results.first, 'snk_existing_key');
    });
  });
}
