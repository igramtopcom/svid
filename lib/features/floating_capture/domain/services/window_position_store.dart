import '../entities/window_position.dart';

/// Persists the floating capture popup's drag-saved screen position
/// across app restarts.
///
/// Returns null when the user has never dragged — spawn falls back to
/// the spec Q19 "follow mouse cursor" default in that case.
abstract class WindowPositionStore {
  /// Read the persisted position. Null = never set or corrupt payload.
  Future<WindowPosition?> read();

  /// Replace the persisted position.
  Future<void> write(WindowPosition position);
}
