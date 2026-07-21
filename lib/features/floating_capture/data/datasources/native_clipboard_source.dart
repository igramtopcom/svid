import 'dart:async';

import 'package:flutter/services.dart';

import '../../../../core/logging/app_logger.dart';
import '../../domain/services/clipboard_source.dart';

/// Production [ClipboardSource] backed by native platform code.
///
/// macOS: Polls `NSPasteboard.changeCount` @ 500ms (default) — Apple does
/// NOT expose a clipboard-changed notification. See
/// `macos/Runner/MainFlutterWindow.swift` (`ClipboardMonitorPlugin`).
/// Windows: Event-driven via `AddClipboardFormatListener` (no polling).
/// A hidden message-only window (HWND_MESSAGE) receives WM_CLIPBOARDUPDATE.
/// See `windows/runner/clipboard_monitor_plugin.cpp`.
/// Linux: Skipped per spec Q12 (deferred to v2.2).
///
/// Channels (identical names across platforms — Dart code below works
/// unchanged on macOS + Windows):
/// - Method channel `svid.clipboard_monitor/methods` — start/stop/readText
/// - Event channel `svid.clipboard_monitor/events` — clipboard text events
///
/// Native sides emit text-only events; image/file/HTML clipboards are
/// filtered at the native layer (per spec §11 E20).
class NativeClipboardSource implements ClipboardSource {
  static const _methodChannelName = 'svid.clipboard_monitor/methods';
  static const _eventChannelName = 'svid.clipboard_monitor/events';

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final StreamController<String> _controller = StreamController.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;
  bool _started = false;

  /// Construct with default platform channels.
  NativeClipboardSource()
      : _methodChannel = const MethodChannel(_methodChannelName),
        _eventChannel = const EventChannel(_eventChannelName);

  /// Construct with injected channels — for testing with mock method handlers.
  NativeClipboardSource.withChannels({
    required MethodChannel methodChannel,
    required EventChannel eventChannel,
  })  : _methodChannel = methodChannel,
        _eventChannel = eventChannel;

  @override
  Future<String?> readText() async {
    try {
      return await _methodChannel.invokeMethod<String?>('readText');
    } on PlatformException catch (e, stack) {
      appLogger.error('[NativeClipboard] readText() failed', e, stack);
      return null;
    }
  }

  @override
  Future<void> start({
    Duration pollInterval = const Duration(milliseconds: 500),
  }) async {
    if (_started) return;
    _started = true;

    // Subscribe to the event channel BEFORE telling native to start polling.
    // If we invoked start first, the timer could fire (and emit events) before
    // FlutterEventSink is wired up, silently dropping early changes on the
    // native side (`eventSink?(text)` becomes a no-op when nil).
    _eventSubscription = _eventChannel
        .receiveBroadcastStream()
        .listen(
          (event) {
            // Native side already filters: text-only, non-empty.
            // Belt-and-suspenders: re-validate type + emptiness in Dart.
            if (event is String && event.trim().isNotEmpty) {
              _controller.add(event);
            }
          },
          onError: (Object error, StackTrace stack) {
            appLogger.error(
              '[NativeClipboard] event stream error',
              error,
              stack,
            );
          },
        );

    try {
      await _methodChannel.invokeMethod<bool>('start', {
        'intervalMs': pollInterval.inMilliseconds,
      });
    } on PlatformException catch (e, stack) {
      _started = false;
      await _eventSubscription?.cancel();
      _eventSubscription = null;
      appLogger.error('[NativeClipboard] start() failed', e, stack);
      rethrow;
    }

    appLogger.info(
      '[NativeClipboard] started, interval=${pollInterval.inMilliseconds}ms',
    );
  }

  @override
  Future<void> stop() async {
    if (!_started) return;
    _started = false;

    await _eventSubscription?.cancel();
    _eventSubscription = null;

    try {
      await _methodChannel.invokeMethod<bool>('stop');
    } on PlatformException catch (e, stack) {
      // Stop is best-effort — log but don't rethrow (caller can't fix this)
      appLogger.error('[NativeClipboard] stop() failed', e, stack);
    }

    appLogger.info('[NativeClipboard] stopped');
  }

  @override
  Stream<String> get onChange => _controller.stream;

  /// Permanent disposal — close the broadcast stream. Call when service is
  /// no longer needed.
  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
