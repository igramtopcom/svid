import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/floating_capture/data/datasources/mock_auto_launcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAutoLauncher launcher;

  setUp(() {
    launcher = MockAutoLauncher();
  });

  group('initialization', () {
    test('isInitialized=false before initialize()', () {
      expect(launcher.isInitialized, isFalse);
    });

    test('isInitialized=true after initialize()', () async {
      await launcher.initialize(appName: 'Svid', appPath: '/path/to/app');
      expect(launcher.isInitialized, isTrue);
      expect(launcher.initializeCallCount, 1);
    });

    test('multiple initialize() calls — counter tracks each', () async {
      await launcher.initialize(appName: 'Svid', appPath: '/path');
      await launcher.initialize(appName: 'Svid', appPath: '/path');
      expect(launcher.initializeCallCount, 2);
    });
  });

  group('enable / disable / isEnabled', () {
    setUp(() async {
      await launcher.initialize(appName: 'Svid', appPath: '/path');
    });

    test('initial state is disabled', () async {
      expect(await launcher.isEnabled(), isFalse);
    });

    test('enable() turns on, isEnabled() reflects', () async {
      final ok = await launcher.enable();
      expect(ok, isTrue);
      expect(await launcher.isEnabled(), isTrue);
    });

    test('disable() turns off after enable', () async {
      await launcher.enable();
      final ok = await launcher.disable();
      expect(ok, isTrue);
      expect(await launcher.isEnabled(), isFalse);
    });

    test('idempotent enable — second call still returns true', () async {
      await launcher.enable();
      final second = await launcher.enable();
      expect(second, isTrue);
      expect(await launcher.isEnabled(), isTrue);
    });

    test('idempotent disable — disable when already disabled', () async {
      final ok = await launcher.disable();
      expect(ok, isTrue);
      expect(await launcher.isEnabled(), isFalse);
    });
  });

  group('uninitialized access throws', () {
    test('enable() before initialize throws StateError', () async {
      expect(() => launcher.enable(), throwsStateError);
    });

    test('disable() before initialize throws StateError', () async {
      expect(() => launcher.disable(), throwsStateError);
    });

    test('isEnabled() before initialize throws StateError', () async {
      expect(() => launcher.isEnabled(), throwsStateError);
    });
  });

  group('failure simulation', () {
    setUp(() async {
      await launcher.initialize(appName: 'Svid', appPath: '/path');
    });

    test('enable() returns false when failNextOperation set', () async {
      launcher.failNextOperation = true;
      final ok = await launcher.enable();
      expect(ok, isFalse);
      // Failure flag auto-reset
      expect(launcher.failNextOperation, isFalse);
    });

    test('failure does not change underlying state', () async {
      // Pre-state: disabled
      launcher.failNextOperation = true;
      await launcher.enable(); // fails
      expect(await launcher.isEnabled(), isFalse, reason: 'state unchanged');
    });

    test('failure auto-resets after one call', () async {
      launcher.failNextOperation = true;
      await launcher.enable(); // fails
      final secondOk = await launcher.enable(); // succeeds now
      expect(secondOk, isTrue);
    });
  });

  group('state seeding (pre-existing OS config)', () {
    setUp(() async {
      await launcher.initialize(appName: 'Svid', appPath: '/path');
    });

    test('setStateForTest reflects in isEnabled', () async {
      launcher.setStateForTest(true);
      expect(await launcher.isEnabled(), isTrue);
    });

    test('disable() after seeded enabled state turns off', () async {
      launcher.setStateForTest(true);
      await launcher.disable();
      expect(await launcher.isEnabled(), isFalse);
    });
  });

  group('call tracking (test helpers)', () {
    setUp(() async {
      await launcher.initialize(appName: 'Svid', appPath: '/path');
    });

    test('enable count tracks correctly', () async {
      await launcher.enable();
      await launcher.enable();
      await launcher.enable();
      expect(launcher.enableCallCount, 3);
    });

    test('isEnabled count tracks correctly', () async {
      await launcher.isEnabled();
      await launcher.isEnabled();
      expect(launcher.isEnabledCallCount, 2);
    });

    test('disable + enable + disable counts independently', () async {
      await launcher.disable();
      await launcher.enable();
      await launcher.disable();
      expect(launcher.disableCallCount, 2);
      expect(launcher.enableCallCount, 1);
    });
  });
}
