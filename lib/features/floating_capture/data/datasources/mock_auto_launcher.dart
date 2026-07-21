import '../../domain/services/auto_launch_service.dart';

/// In-memory [AutoLaunchService] implementation for tests.
///
/// Tracks state without OS interaction. Allows simulation of failure modes
/// via [failNextOperation].
class MockAutoLauncher implements AutoLaunchService {
  bool _initialized = false;
  bool _enabled = false;

  /// Counter of operations performed — useful for verifying ordering.
  int enableCallCount = 0;
  int disableCallCount = 0;
  int isEnabledCallCount = 0;
  int initializeCallCount = 0;

  /// If true, next enable/disable/isEnabled call returns false (simulates
  /// platform error). Auto-resets to false after one failure.
  bool failNextOperation = false;

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize({
    required String appName,
    required String appPath,
  }) async {
    initializeCallCount++;
    _initialized = true;
  }

  @override
  Future<bool> enable() async {
    _ensureInitialized('enable');
    enableCallCount++;
    if (failNextOperation) {
      failNextOperation = false;
      return false;
    }
    _enabled = true;
    return true;
  }

  @override
  Future<bool> disable() async {
    _ensureInitialized('disable');
    disableCallCount++;
    if (failNextOperation) {
      failNextOperation = false;
      return false;
    }
    _enabled = false;
    return true;
  }

  @override
  Future<bool> isEnabled() async {
    _ensureInitialized('isEnabled');
    isEnabledCallCount++;
    if (failNextOperation) {
      failNextOperation = false;
      return false;
    }
    return _enabled;
  }

  /// Test helper: directly set state (e.g., simulate user's pre-existing OS
  /// auto-launch configuration before app first runs).
  void setStateForTest(bool enabled) {
    _enabled = enabled;
  }

  void _ensureInitialized(String method) {
    if (!_initialized) {
      throw StateError(
        'MockAutoLauncher.$method() called before initialize()',
      );
    }
  }
}
