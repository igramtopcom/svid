/// Abstraction over OS-level auto-launch-on-login.
///
/// Per spec v2.1 §Q7: floating capture defaults `auto-launch on login = ON`
/// for new installs (so capture is available immediately after reboot).
///
/// Concrete implementations:
/// - `LaunchAtStartupAutoLauncher` — wraps `launch_at_startup` plugin
///   (macOS uses Login Items, Windows uses HKCU\Run registry)
/// - `MockAutoLauncher` — controllable for tests
///
/// Service must be initialized once at app start via [initialize] before
/// querying or mutating state.
abstract class AutoLaunchService {
  /// Initialize the underlying platform integration. Must be called once
  /// before [enable]/[disable]/[isEnabled].
  ///
  /// [appName] should match the app's bundle name (used as the display name
  /// in macOS Login Items and Windows registry value name).
  /// [appPath] is the executable path. Pass current binary path.
  Future<void> initialize({
    required String appName,
    required String appPath,
  });

  /// Set app to auto-launch at system login.
  /// Returns true on success.
  Future<bool> enable();

  /// Disable auto-launch at login.
  /// Returns true on success.
  Future<bool> disable();

  /// Check current auto-launch state from OS.
  Future<bool> isEnabled();

  /// Whether [initialize] has been called.
  bool get isInitialized;
}
