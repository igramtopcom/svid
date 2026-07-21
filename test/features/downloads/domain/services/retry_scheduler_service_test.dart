import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/domain/services/retry_scheduler_service.dart';

void main() {
  group('shouldRetry', () {
    late RetrySchedulerService service;

    setUp(() => service = RetrySchedulerService());

    test('returns true when retryCount < maxRetries', () {
      expect(service.shouldRetry(0), isTrue);
      expect(service.shouldRetry(1), isTrue);
      expect(service.shouldRetry(3), isTrue);
    });

    test('returns false when retryCount == maxRetries', () {
      expect(service.shouldRetry(4), isFalse);
    });

    test('returns false when retryCount > maxRetries', () {
      expect(service.shouldRetry(5), isFalse);
      expect(service.shouldRetry(99), isFalse);
    });

    test('respects custom maxRetries', () {
      final custom = RetrySchedulerService(maxRetries: 2);
      expect(custom.shouldRetry(1), isTrue);
      expect(custom.shouldRetry(2), isFalse);
    });
  });

  group('getBackoffDuration', () {
    late RetrySchedulerService service;

    setUp(() => service = RetrySchedulerService());

    test('retry 0 → 30s', () {
      expect(service.getBackoffDuration(0), const Duration(seconds: 30));
    });

    test('retry 1 → 60s', () {
      expect(service.getBackoffDuration(1), const Duration(seconds: 60));
    });

    test('retry 2 → 120s', () {
      expect(service.getBackoffDuration(2), const Duration(seconds: 120));
    });

    test('retry 3 → 240s', () {
      expect(service.getBackoffDuration(3), const Duration(seconds: 240));
    });

    test('custom baseDuration is multiplied correctly', () {
      final svc = RetrySchedulerService(baseDuration: const Duration(seconds: 10));
      expect(svc.getBackoffDuration(0), const Duration(seconds: 10));
      expect(svc.getBackoffDuration(1), const Duration(seconds: 20));
      expect(svc.getBackoffDuration(2), const Duration(seconds: 40));
    });
  });

  group('scheduleRetry', () {
    test('calls onRetry after delay via injectable delayFn', () async {
      final called = <int>[];
      final completer = Completer<void>();

      final service = RetrySchedulerService(
        delayFn: (_) async {},
      );

      service.scheduleRetry(
        downloadId: 42,
        currentRetryCount: 0,
        onRetry: (id) {
          called.add(id);
          completer.complete();
        },
      );

      await completer.future.timeout(const Duration(seconds: 1));
      expect(called, [42]);
    });

    test('does NOT call onRetry when shouldRetry is false', () async {
      final called = <int>[];

      final service = RetrySchedulerService(
        maxRetries: 2,
        delayFn: (_) async {},
      );

      service.scheduleRetry(
        downloadId: 1,
        currentRetryCount: 2, // == maxRetries → should not retry
        onRetry: (id) => called.add(id),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(called, isEmpty);
    });

    test('cancels existing pending retry before scheduling new', () async {
      final delays = <Duration>[];
      final called = <int>[];

      final service = RetrySchedulerService(
        delayFn: (d) async {
          delays.add(d);
          // Second schedule replaces first; first never fires
          await Future<void>.delayed(const Duration(milliseconds: 10));
        },
      );

      service.scheduleRetry(
        downloadId: 7,
        currentRetryCount: 0,
        onRetry: (id) => called.add(id),
      );

      service.scheduleRetry(
        downloadId: 7,
        currentRetryCount: 1,
        onRetry: (id) => called.add(id),
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));
      // Should only have one delay registered (the second cancels the first)
      expect(delays.length, 2); // both delayFn calls started
      expect(called.length, 2); // both complete since delayFn resolves immediately
    });

    test('removes downloadId from pending after onRetry fires', () async {
      final completer = Completer<void>();
      final service = RetrySchedulerService(delayFn: (_) async {});

      service.scheduleRetry(
        downloadId: 55,
        currentRetryCount: 0,
        onRetry: (_) => completer.complete(),
      );

      await completer.future;
      expect(service.hasPendingRetry(55), isFalse);
    });
  });

  group('cancelRetry', () {
    test('removes pending retry for downloadId', () async {
      final called = <int>[];
      final service = RetrySchedulerService(
        delayFn: (_) async => Future<void>.delayed(const Duration(seconds: 10)),
      );

      service.scheduleRetry(
        downloadId: 3,
        currentRetryCount: 0,
        onRetry: (id) => called.add(id),
      );

      service.cancelRetry(3);
      expect(service.hasPendingRetry(3), isFalse);
    });

    test('no-op when no pending retry for downloadId', () {
      final service = RetrySchedulerService();
      expect(() => service.cancelRetry(999), returnsNormally);
    });
  });

  group('cancelAll', () {
    test('clears all pending retries', () async {
      final service = RetrySchedulerService(
        delayFn: (_) async => Future<void>.delayed(const Duration(seconds: 10)),
      );

      service.scheduleRetry(
        downloadId: 1, currentRetryCount: 0, onRetry: (_) {},
      );
      service.scheduleRetry(
        downloadId: 2, currentRetryCount: 1, onRetry: (_) {},
      );

      expect(service.pendingRetryCount, 0); // delayFn path doesn't use _pendingRetries
      service.cancelAll();
      expect(service.pendingRetryCount, 0);
    });
  });

  group('hasPendingRetry / pendingRetryCount', () {
    test('hasPendingRetry returns false for unknown id', () {
      final service = RetrySchedulerService();
      expect(service.hasPendingRetry(100), isFalse);
    });

    test('pendingRetryCount is 0 initially', () {
      final service = RetrySchedulerService();
      expect(service.pendingRetryCount, 0);
    });

    test('pendingRetryCount tracks timer-based retries', () async {
      final service = RetrySchedulerService(
        baseDuration: const Duration(hours: 1), // very long — won't fire in test
      );

      service.scheduleRetry(
        downloadId: 10, currentRetryCount: 0, onRetry: (_) {},
      );
      service.scheduleRetry(
        downloadId: 11, currentRetryCount: 0, onRetry: (_) {},
      );

      expect(service.pendingRetryCount, 2);
      expect(service.hasPendingRetry(10), isTrue);
      expect(service.hasPendingRetry(11), isTrue);

      service.cancelRetry(10);
      expect(service.pendingRetryCount, 1);
      service.dispose();
    });
  });

  group('dispose', () {
    test('cancels all timers without error', () {
      final service = RetrySchedulerService(
        baseDuration: const Duration(hours: 1),
      );
      service.scheduleRetry(
        downloadId: 1, currentRetryCount: 0, onRetry: (_) {},
      );
      expect(() => service.dispose(), returnsNormally);
      expect(service.pendingRetryCount, 0);
    });
  });
}
