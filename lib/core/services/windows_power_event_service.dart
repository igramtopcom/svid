import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/brand_config.dart';
import '../logging/app_logger.dart';

enum WindowsPowerEvent { suspend, resume }

typedef WindowsPowerEventHandler =
    FutureOr<void> Function(WindowsPowerEvent event);

/// Receives native Windows power broadcast messages from the runner.
///
/// Flutter desktop lifecycle events are not precise enough for sleep/resume
/// GPU-context loss. The Win32 runner forwards WM_POWERBROADCAST before the
/// machine suspends so Dart can quiesce media/DirectComposition-heavy surfaces.
class WindowsPowerEventService {
  WindowsPowerEventService._();

  static final WindowsPowerEventService instance = WindowsPowerEventService._();

  final MethodChannel _channel = MethodChannel(
    '${BrandConfig.current.methodChannelPrefix}/power_events',
  );

  WindowsPowerEventHandler? _handler;

  void start({required WindowsPowerEventHandler onEvent}) {
    if (!Platform.isWindows) return;
    _handler = onEvent;
    _channel.setMethodCallHandler(_handleMethodCall);
    appLogger.info('Windows power event service started');
  }

  void stop() {
    if (!Platform.isWindows) return;
    _handler = null;
    _channel.setMethodCallHandler(null);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'handlePowerEvent') return;

    final raw = call.arguments;
    if (raw is! String) {
      appLogger.warning('Windows power event ignored: invalid payload $raw');
      return;
    }

    final event = switch (raw) {
      'suspend' => WindowsPowerEvent.suspend,
      'resume' => WindowsPowerEvent.resume,
      _ => null,
    };

    if (event == null) {
      appLogger.warning('Windows power event ignored: unknown event "$raw"');
      return;
    }

    appLogger.info('Windows power event received: ${event.name}');
    await _handler?.call(event);
  }

  @visibleForTesting
  void setHandlerForTesting(WindowsPowerEventHandler? handler) {
    _handler = handler;
  }

  @visibleForTesting
  Future<void> handleMethodCallForTesting(MethodCall call) {
    return _handleMethodCall(call);
  }
}
