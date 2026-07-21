import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/services/windows_power_event_service.dart';

void main() {
  tearDown(() {
    WindowsPowerEventService.instance.setHandlerForTesting(null);
  });

  test('dispatches suspend event', () async {
    WindowsPowerEvent? captured;
    WindowsPowerEventService.instance.setHandlerForTesting((event) {
      captured = event;
    });

    await WindowsPowerEventService.instance.handleMethodCallForTesting(
      const MethodCall('handlePowerEvent', 'suspend'),
    );

    expect(captured, WindowsPowerEvent.suspend);
  });

  test('dispatches resume event', () async {
    WindowsPowerEvent? captured;
    WindowsPowerEventService.instance.setHandlerForTesting((event) {
      captured = event;
    });

    await WindowsPowerEventService.instance.handleMethodCallForTesting(
      const MethodCall('handlePowerEvent', 'resume'),
    );

    expect(captured, WindowsPowerEvent.resume);
  });

  test('ignores unknown payload', () async {
    var called = false;
    WindowsPowerEventService.instance.setHandlerForTesting((_) {
      called = true;
    });

    await WindowsPowerEventService.instance.handleMethodCallForTesting(
      const MethodCall('handlePowerEvent', 'hibernate'),
    );

    expect(called, isFalse);
  });

  test('ignores unrelated method', () async {
    var called = false;
    WindowsPowerEventService.instance.setHandlerForTesting((_) {
      called = true;
    });

    await WindowsPowerEventService.instance.handleMethodCallForTesting(
      const MethodCall('otherMethod', 'suspend'),
    );

    expect(called, isFalse);
  });
}
