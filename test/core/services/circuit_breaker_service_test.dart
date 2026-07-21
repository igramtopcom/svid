import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/services/circuit_breaker_service.dart';

void main() {
  late CircuitBreakerService service;
  late DateTime now;

  setUp(() {
    now = DateTime(2026, 2, 28, 12, 0, 0);
    service = CircuitBreakerService(
      failureThreshold: 3,
      failureWindow: const Duration(minutes: 5),
      cooldownDuration: const Duration(seconds: 60),
      clock: () => now,
    );
  });

  group('CircuitBreakerService', () {
    test('starts in closed state for unknown platform', () {
      expect(service.getState('youtube'), CircuitBreakerState.closed);
      expect(service.isRequestAllowed('youtube'), true);
    });

    test('stays closed after fewer failures than threshold', () {
      service.recordFailure('youtube');
      service.recordFailure('youtube');

      expect(service.getState('youtube'), CircuitBreakerState.closed);
      expect(service.isRequestAllowed('youtube'), true);
    });

    test('transitions to open after threshold failures', () {
      service.recordFailure('youtube');
      service.recordFailure('youtube');
      service.recordFailure('youtube');

      expect(service.getState('youtube'), CircuitBreakerState.open);
      expect(service.isRequestAllowed('youtube'), false);
    });

    test('tracks platforms independently', () {
      // Fail YouTube 3 times
      service.recordFailure('youtube');
      service.recordFailure('youtube');
      service.recordFailure('youtube');

      // TikTok should still be closed
      expect(service.getState('youtube'), CircuitBreakerState.open);
      expect(service.getState('tiktok'), CircuitBreakerState.closed);
      expect(service.isRequestAllowed('tiktok'), true);
    });

    test('success resets failure count', () {
      service.recordFailure('youtube');
      service.recordFailure('youtube');
      service.recordSuccess('youtube');

      // Now fail 2 more times — should NOT open (counter was reset)
      service.recordFailure('youtube');
      service.recordFailure('youtube');

      expect(service.getState('youtube'), CircuitBreakerState.closed);
    });

    test('transitions to halfOpen after cooldown expires', () {
      // Open the circuit
      service.recordFailure('youtube');
      service.recordFailure('youtube');
      service.recordFailure('youtube');
      expect(service.getState('youtube'), CircuitBreakerState.open);

      // Advance clock past cooldown
      now = now.add(const Duration(seconds: 61));

      expect(service.getState('youtube'), CircuitBreakerState.halfOpen);
      expect(service.isRequestAllowed('youtube'), true);
    });

    test('halfOpen transitions to closed on success', () {
      // Open the circuit
      service.recordFailure('youtube');
      service.recordFailure('youtube');
      service.recordFailure('youtube');

      // Advance past cooldown
      now = now.add(const Duration(seconds: 61));
      expect(service.getState('youtube'), CircuitBreakerState.halfOpen);

      // Probe succeeds
      service.recordSuccess('youtube');

      expect(service.getState('youtube'), CircuitBreakerState.closed);
    });

    test('halfOpen transitions back to open on failure', () {
      // Open the circuit
      service.recordFailure('youtube');
      service.recordFailure('youtube');
      service.recordFailure('youtube');

      // Advance past cooldown
      now = now.add(const Duration(seconds: 61));
      expect(service.getState('youtube'), CircuitBreakerState.halfOpen);

      // Probe fails
      service.recordFailure('youtube');

      expect(service.getState('youtube'), CircuitBreakerState.open);
      expect(service.isRequestAllowed('youtube'), false);
    });

    test('getRemainingCooldownSeconds returns correct value', () {
      service.recordFailure('youtube');
      service.recordFailure('youtube');
      service.recordFailure('youtube');

      expect(service.getRemainingCooldownSeconds('youtube'), 60);

      // Advance 30 seconds
      now = now.add(const Duration(seconds: 30));
      expect(service.getRemainingCooldownSeconds('youtube'), 30);

      // Advance past cooldown
      now = now.add(const Duration(seconds: 31));
      expect(service.getRemainingCooldownSeconds('youtube'), 0);
    });

    test('additional failures while open do not extend cooldown', () {
      service.recordFailure('youtube');
      service.recordFailure('youtube');
      service.recordFailure('youtube');

      now = now.add(const Duration(seconds: 30));
      service.recordFailure('youtube');

      expect(service.getState('youtube'), CircuitBreakerState.open);
      expect(service.getRemainingCooldownSeconds('youtube'), 30);
    });

    test('parser failures do not open circuit', () {
      service.recordParserFailure('facebook', reason: 'cannot parse data');
      service.recordParserFailure('facebook', reason: 'cannot parse data');
      service.recordParserFailure('facebook', reason: 'cannot parse data');

      expect(service.getState('facebook'), CircuitBreakerState.closed);
    });

    test('getRemainingCooldownSeconds returns 0 for closed circuit', () {
      expect(service.getRemainingCooldownSeconds('youtube'), 0);
    });

    test('failure window resets counter when window expires', () {
      service.recordFailure('youtube');
      service.recordFailure('youtube');

      // Advance past failure window (5 minutes)
      now = now.add(const Duration(minutes: 6));

      // These 2 failures should NOT trigger open (counter was reset)
      service.recordFailure('youtube');
      service.recordFailure('youtube');

      expect(service.getState('youtube'), CircuitBreakerState.closed);
    });

    test('resetPlatform clears circuit for specific platform', () {
      service.recordFailure('youtube');
      service.recordFailure('youtube');
      service.recordFailure('youtube');
      expect(service.getState('youtube'), CircuitBreakerState.open);

      service.resetPlatform('youtube');
      expect(service.getState('youtube'), CircuitBreakerState.closed);
      expect(service.isRequestAllowed('youtube'), true);
    });

    test('resetAll clears all circuits', () {
      service.recordFailure('youtube');
      service.recordFailure('youtube');
      service.recordFailure('youtube');
      service.recordFailure('tiktok');
      service.recordFailure('tiktok');
      service.recordFailure('tiktok');

      service.resetAll();

      expect(service.getState('youtube'), CircuitBreakerState.closed);
      expect(service.getState('tiktok'), CircuitBreakerState.closed);
    });

    test('custom configuration works', () {
      final custom = CircuitBreakerService(
        failureThreshold: 2,
        failureWindow: const Duration(minutes: 1),
        cooldownDuration: const Duration(seconds: 30),
        clock: () => now,
      );

      custom.recordFailure('instagram');
      expect(custom.getState('instagram'), CircuitBreakerState.closed);

      custom.recordFailure('instagram');
      expect(custom.getState('instagram'), CircuitBreakerState.open);

      // Verify custom cooldown
      now = now.add(const Duration(seconds: 29));
      expect(custom.isRequestAllowed('instagram'), false);

      now = now.add(const Duration(seconds: 2));
      expect(custom.isRequestAllowed('instagram'), true);
      expect(custom.getState('instagram'), CircuitBreakerState.halfOpen);
    });
  });
}
