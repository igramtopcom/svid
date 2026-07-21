import 'package:launch_at_startup/launch_at_startup.dart';

import '../../../../core/logging/app_logger.dart';
import '../../domain/services/auto_launch_service.dart';

/// Production [AutoLaunchService] implementation backed by the
/// `launch_at_startup` Flutter plugin.
///
/// Platform behavior:
/// - macOS: registers via SMAppService Login Items (sandboxed-friendly)
/// - Windows: writes to `HKEY_CURRENT_USER\...\Run` registry key
/// - Linux: writes `~/.config/autostart/<appName>.desktop` (XDG)
///
/// Errors are caught and logged — methods return false on failure rather
/// than throwing. This matches spec preference for graceful degradation
/// (per spec §11 — fall back gracefully, don't crash app).
class LaunchAtStartupAutoLauncher implements AutoLaunchService {
  final LaunchAtStartup _backend;
  bool _initialized = false;

  LaunchAtStartupAutoLauncher({LaunchAtStartup? backend})
      : _backend = backend ?? launchAtStartup;

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize({
    required String appName,
    required String appPath,
  }) async {
    if (_initialized) {
      appLogger.warning('[AutoLaunch] initialize() called twice — ignoring');
      return;
    }
    _backend.setup(
      appName: appName,
      appPath: appPath,
    );
    _initialized = true;
    appLogger.info('[AutoLaunch] initialized for app=$appName');
  }

  @override
  Future<bool> enable() async {
    _ensureInitialized('enable');
    try {
      final ok = await _backend.enable();
      appLogger.info('[AutoLaunch] enable() → $ok');
      return ok;
    } catch (e, stack) {
      appLogger.error('[AutoLaunch] enable() failed', e, stack);
      return false;
    }
  }

  @override
  Future<bool> disable() async {
    _ensureInitialized('disable');
    try {
      final ok = await _backend.disable();
      appLogger.info('[AutoLaunch] disable() → $ok');
      return ok;
    } catch (e, stack) {
      appLogger.error('[AutoLaunch] disable() failed', e, stack);
      return false;
    }
  }

  @override
  Future<bool> isEnabled() async {
    _ensureInitialized('isEnabled');
    try {
      return await _backend.isEnabled();
    } catch (e, stack) {
      appLogger.error('[AutoLaunch] isEnabled() failed', e, stack);
      return false;
    }
  }

  void _ensureInitialized(String method) {
    if (!_initialized) {
      throw StateError(
        'AutoLaunchService.$method() called before initialize() — '
        'call initialize(appName, appPath) first.',
      );
    }
  }
}
