import 'package:flutter/foundation.dart';

/// Circuit breaker states
enum CircuitBreakerState {
  /// Normal operation — all requests pass through
  closed,

  /// Circuit is open — requests are blocked to protect the system
  open,

  /// Probing — allows one request to test if the service has recovered
  halfOpen,
}

/// Tracks circuit breaker state for a single platform
class _PlatformCircuit {
  CircuitBreakerState state = CircuitBreakerState.closed;
  int consecutiveFailures = 0;
  DateTime? firstFailureTime;
  DateTime? openedAt;

  void reset() {
    state = CircuitBreakerState.closed;
    consecutiveFailures = 0;
    firstFailureTime = null;
    openedAt = null;
  }
}

/// Circuit Breaker for yt-dlp extraction calls.
///
/// Prevents hammering yt-dlp when it's consistently failing for a platform
/// (e.g., rate limiting, geo-blocking). Tracks failures per-platform and
/// transitions through Closed → Open → HalfOpen states.
///
/// - **Closed**: Normal operation, all requests pass through.
/// - **Open**: After [failureThreshold] consecutive failures within
///   [failureWindow], blocks all requests for [cooldownDuration].
/// - **HalfOpen**: After cooldown expires, allows exactly one probe request.
///   If it succeeds → Closed. If it fails → Open again.
class CircuitBreakerService {
  /// Number of consecutive failures before opening the circuit
  final int failureThreshold;

  /// Time window in which failures must occur to count as consecutive
  final Duration failureWindow;

  /// How long the circuit stays open before allowing a probe
  final Duration cooldownDuration;

  /// Injectable clock for testing
  final DateTime Function() _clock;

  final Map<String, _PlatformCircuit> _circuits = {};

  CircuitBreakerService({
    this.failureThreshold = 3,
    this.failureWindow = const Duration(minutes: 5),
    this.cooldownDuration = const Duration(seconds: 60),
    @visibleForTesting DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Get the current state for a platform
  CircuitBreakerState getState(String platform) {
    final circuit = _circuits[platform];
    if (circuit == null) return CircuitBreakerState.closed;

    // If open, check if cooldown has expired
    if (circuit.state == CircuitBreakerState.open) {
      final elapsed = _clock().difference(circuit.openedAt!);
      if (elapsed >= cooldownDuration) {
        circuit.state = CircuitBreakerState.halfOpen;
        debugPrint(
          '⚡ [CircuitBreaker] $platform: Open → HalfOpen '
          '(cooldown ${cooldownDuration.inSeconds}s expired)',
        );
        return CircuitBreakerState.halfOpen;
      }
    }

    return circuit.state;
  }

  /// Check if a request is allowed for the given platform.
  /// Returns `true` if the request can proceed, `false` if blocked.
  bool isRequestAllowed(String platform) {
    final state = getState(platform);
    switch (state) {
      case CircuitBreakerState.closed:
      case CircuitBreakerState.halfOpen:
        return true;
      case CircuitBreakerState.open:
        return false;
    }
  }

  /// Record a successful request for the platform.
  /// Resets the circuit to Closed state.
  void recordSuccess(String platform) {
    final circuit = _circuits[platform];
    if (circuit == null) return;

    final previousState = circuit.state;
    circuit.reset();

    if (previousState != CircuitBreakerState.closed) {
      debugPrint(
        '✅ [CircuitBreaker] $platform: $previousState → Closed (success)',
      );
    }
  }

  /// Record a failed request for the platform.
  /// May transition the circuit to Open state.
  void recordFailure(String platform) {
    final circuit = _circuits.putIfAbsent(platform, _PlatformCircuit.new);
    final now = _clock();

    // Late failures from requests that were already in flight when the circuit
    // opened should not extend the cooldown indefinitely.
    if (circuit.state == CircuitBreakerState.open) {
      debugPrint(
        '⚠️ [CircuitBreaker] $platform: failure ignored '
        '(already open, cooldown ${cooldownDuration.inSeconds}s)',
      );
      return;
    }

    // If in halfOpen and the probe failed → back to Open
    if (circuit.state == CircuitBreakerState.halfOpen) {
      circuit.state = CircuitBreakerState.open;
      circuit.openedAt = now;
      debugPrint(
        '🔴 [CircuitBreaker] $platform: HalfOpen → Open '
        '(probe failed, cooldown ${cooldownDuration.inSeconds}s)',
      );
      return;
    }

    // Check if the failure window has expired — reset counter if so
    if (circuit.firstFailureTime != null) {
      final elapsed = now.difference(circuit.firstFailureTime!);
      if (elapsed > failureWindow) {
        circuit.consecutiveFailures = 0;
        circuit.firstFailureTime = null;
      }
    }

    // Record the failure
    circuit.consecutiveFailures++;
    circuit.firstFailureTime ??= now;

    debugPrint(
      '⚠️ [CircuitBreaker] $platform: failure '
      '${circuit.consecutiveFailures}/$failureThreshold',
    );

    // Check threshold
    if (circuit.consecutiveFailures >= failureThreshold) {
      circuit.state = CircuitBreakerState.open;
      circuit.openedAt = now;
      debugPrint(
        '🔴 [CircuitBreaker] $platform: Closed → Open '
        '(${circuit.consecutiveFailures} failures in '
        '${failureWindow.inMinutes}min, cooldown ${cooldownDuration.inSeconds}s)',
      );
    }
  }

  /// Record a parser/auth-style failure that should be visible in logs but
  /// must not open the circuit. These failures are usually user-actionable
  /// (cookies/login/session) rather than platform-wide extractor outages.
  void recordParserFailure(String platform, {String? reason}) {
    debugPrint(
      '⚠️ [CircuitBreaker] $platform: parser/auth failure ignored '
      '(not counted toward circuit${reason == null ? '' : ': $reason'})',
    );
  }

  /// Get remaining cooldown time in seconds for an open circuit.
  /// Returns 0 if the circuit is not open or cooldown has expired.
  int getRemainingCooldownSeconds(String platform) {
    final circuit = _circuits[platform];
    if (circuit == null || circuit.state != CircuitBreakerState.open) return 0;
    if (circuit.openedAt == null) return 0;

    final elapsed = _clock().difference(circuit.openedAt!);
    final remaining = cooldownDuration - elapsed;
    return remaining.isNegative ? 0 : remaining.inSeconds;
  }

  /// Reset the circuit breaker for a specific platform
  void resetPlatform(String platform) {
    _circuits.remove(platform);
  }

  /// Reset all circuit breakers
  void resetAll() {
    _circuits.clear();
  }
}
