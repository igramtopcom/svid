import '../entities/snooze_state.dart';

/// Persists the floating-capture snooze decision across app restarts.
///
/// Implementations:
/// - `SharedPreferencesSnoozeStore` — production, JSON-encoded under a
///   single `floating_capture.snooze_state.v1` key.
/// - `InMemorySnoozeStore` — test impl with public payload + counter
///   helpers.
abstract class SnoozeStore {
  /// Read the persisted snooze state. Returns [SnoozeState.inactive] if
  /// nothing was ever written or the on-disk payload is malformed.
  Future<SnoozeState> read();

  /// Replace the persisted snooze state.
  Future<void> write(SnoozeState state);
}
