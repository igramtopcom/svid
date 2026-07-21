import '../entities/capture_preferences.dart';

/// Persists [CapturePreferences] across app restarts.
///
/// Implementations:
/// - `SharedPreferencesCapturePreferencesStore` — production, JSON-encoded
///   under a versioned key.
/// - `InMemoryCapturePreferencesStore` — for tests.
abstract class CapturePreferencesStore {
  /// Returns the persisted preferences, or [CapturePreferences.defaults]
  /// if nothing was ever written or the on-disk payload is malformed.
  Future<CapturePreferences> read();

  /// Replace the persisted state.
  Future<void> write(CapturePreferences prefs);
}
