import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../downloads/domain/entities/video_preview.dart';
import '../../domain/entities/floating_window_event.dart';
import '../../domain/entities/popup_action_result.dart';
import '../../domain/entities/snooze_duration.dart';
import '../../domain/services/floating_window.dart';

/// Parse a raw IPC method name + payload from the popup window into a
/// typed [FloatingWindowEvent]. Returns null for:
///   - Unknown method names (forward-compat: popup binary may be ahead).
///   - Required fields missing or wrong type (silently dropped — caller
///     decides whether to log or surface).
///
/// Top-level so it is unit-testable without instantiating the plugin.
/// v2.2 Phase 2C reviewer-3 Fix 6: terminal-hide predicate as a top-level
/// function so the bridge behavior is unit-testable. Used by the bridge
/// `_handleIncoming` to decide whether to defensively hide the OS window
/// when an event arrives from the popup.
///
/// Returns `true` when the event implies the popup is gone (user dismiss,
/// menu open, snooze, or "Tuỳ chọn…" download click that opens the dialog).
/// Returns `false` for `DownloadClicked(directDownload: true)` — popup must
/// stay visible to render the State 6 banner from setActionResult.
@visibleForTesting
bool isTerminalHideEvent(FloatingWindowEvent event) {
  if (event is PopupDismissed) return true;
  if (event is OpenInAppClicked) return true;
  if (event is MenuOpenAppRequested) return true;
  if (event is MenuOpenSettingsRequested) return true;
  if (event is SnoozeSelected) return true;
  if (event is DownloadClicked) return !event.directDownload;
  // Phase 2D.1 (CPO feedback): Completed-banner CTAs are terminal —
  // popup hides itself, main side defensively syncs visibility.
  if (event is OpenSavedFolderClicked) return true;
  if (event is PlayFileClicked) return true;
  return false;
}

/// v2.2 Phase 2C reviewer-3 Fix 6: identifies the special-case popup-side
/// auto-hide notification (≠ `PopupDismissed`, no URL blocklist).
@visibleForTesting
bool isPopupAutoHiddenMethod(String method) => method == 'onPopupAutoHidden';

@visibleForTesting
FloatingWindowEvent? parseFloatingWindowEvent(String method, dynamic args) {
  final map = args is Map ? args.cast<String, dynamic>() : const {};
  switch (method) {
    case 'onDownloadClicked':
      final url = map['url'] as String?;
      if (url == null) return null;
      // v2.2 Phase 2B: popup sends `directDownload: true|false` to
      // distinguish "Tải ngay" (primary, direct-capable) vs "Tuỳ chọn…"
      // (secondary, force dialog). Default true for forward-compat with
      // older popup engines that didn't send the flag.
      final directDownload = map['directDownload'] as bool? ?? true;
      return DownloadClicked(
        url: url,
        presetKey: map['presetKey'] as String?,
        directDownload: directDownload,
      );

    case 'onSnoozeSelected':
      final wire = map['duration'] as String?;
      final dur = snoozeDurationFromWire(wire);
      if (dur == null) return null;
      return SnoozeSelected(dur);

    case 'onMenuOpenApp':
      return const MenuOpenAppRequested();

    case 'onMenuOpenSettings':
      return const MenuOpenSettingsRequested();

    case 'onPositionChanged':
      final x = (map['x'] as num?)?.toDouble();
      final y = (map['y'] as num?)?.toDouble();
      final mid = map['monitorId'] as String?;
      if (x == null || y == null || mid == null) return null;
      return PositionChanged(x: x, y: y, monitorId: mid);

    case 'onPopupDismissed':
      return const PopupDismissed();

    case 'onThumbnailClicked':
      final url = map['url'] as String?;
      if (url == null) return null;
      return ThumbnailClicked(url);

    case 'onOpenInAppClicked':
      final url = map['url'] as String?;
      if (url == null) return null;
      return OpenInAppClicked(url);

    case 'onOpenSavedFolder':
      final path = map['path'] as String?;
      if (path == null || path.isEmpty) return null;
      return OpenSavedFolderClicked(path);

    case 'onPlayFile':
      final path = map['path'] as String?;
      if (path == null || path.isEmpty) return null;
      return PlayFileClicked(path);

    default:
      return null;
  }
}

/// Production [FloatingWindow] backed by `desktop_multi_window` plugin.
///
/// Spawns a separate Flutter engine for the popup. State is NOT shared via
/// Riverpod — instead the two engines exchange messages over
/// [WindowMethodChannel] (per spec §3.3).
///
/// Channel design:
///   - Single channel `ssvid.floating_capture` shared by both ends.
///   - Methods FROM main → popup are imperative commands
///     (`showPreview`, `pushQueue`, `clearQueue`, `setQuotaState`).
///   - Methods FROM popup → main are events with `on*` prefix
///     (`onDownloadClicked`, `onSnoozeSelected`, `onPositionChanged`, etc.)
///     and are translated into [FloatingWindowEvent] subclasses.
///
/// The initial preview is forwarded via window-launch arguments (JSON
/// blob), NOT via the channel — this avoids a startup race where the
/// popup engine hasn't yet registered its handler when we call
/// `invokeMethod` for the first time.
///
/// Plugin gaps acknowledged (see floating_window_spike.dart §FINDINGS):
///   - `WindowController` has no built-in `close()`. We register a popup-side
///     `disposeForQuit` command. On Windows the popup hides instead of calling
///     `windowManager.destroy()` because that posts a process-level
///     `PostQuitMessage`; the main quit path owns final process termination.
///     Other platforms still use popup-side destroy where the plugin supports
///     a normal child-window teardown.
///   - No `setFrame` / `setPosition` — handled at the popup side via
///     `window_manager` (existing dep). Future native channel work in
///     spec §6.2 covers always-on-top + focus-steal prevention.
class DesktopMultiWindowFloatingWindow implements FloatingWindow {
  static const String _channelName = 'ssvid.floating_capture';
  static const String _windowType = 'floating_capture';

  /// Optional plugin shim — production passes null (uses real plugin).
  /// Tests can pass a fake to drive `WindowController.create` semantics
  /// without a real native window. Phase 1A.3b ships without unit tests
  /// for this class — the plugin's own surface is verified by the
  /// floating_window_spike + manual smoke tests on each platform.
  final Future<WindowController> Function(WindowConfiguration)?
  _windowFactoryOverride;
  final Rect? Function()? _avoidBoundsProvider;

  WindowController? _controller;
  WindowMethodChannel? _channel;
  bool _disposed = false;
  bool _visible = false;

  /// Completes when the popup engine signals it has finished setting up
  /// its WindowMethodChannel handler (Codex audit P1 #4 — cross-engine
  /// ready race). Until then, any `invokeMethod` from this side could be
  /// dropped because the popup hasn't registered a handler yet.
  ///
  /// Reset on each [spawn]. Has a 3-second timeout fallback so a popup
  /// that never reports ready (rare — bug or crashed engine) doesn't
  /// block the main app's CaptureService forever.
  Completer<void>? _popupReady;
  static const _kPopupReadyTimeout = Duration(seconds: 3);

  final StreamController<FloatingWindowEvent> _events =
      StreamController<FloatingWindowEvent>.broadcast();

  DesktopMultiWindowFloatingWindow({Rect? Function()? avoidBoundsProvider})
    : _windowFactoryOverride = null,
      _avoidBoundsProvider = avoidBoundsProvider;

  /// Test/debug constructor — inject a custom window factory. Production
  /// code uses the default constructor.
  @visibleForTesting
  DesktopMultiWindowFloatingWindow.withFactory(
    Future<WindowController> Function(WindowConfiguration) factory, {
    Rect? Function()? avoidBoundsProvider,
  }) : _windowFactoryOverride = factory,
       _avoidBoundsProvider = avoidBoundsProvider;

  /// Locale code passed to the popup engine via launch arguments. Read
  /// from the host's EasyLocalization state by callers (typically the
  /// captureLifecycleControllerProvider) and forwarded on each spawn.
  /// English is the safe fallback if unset.
  String _localeCode = 'en';
  set localeCode(String code) => _localeCode = code;

  @override
  Stream<FloatingWindowEvent> get events => _events.stream;

  @override
  bool get isSpawned => _controller != null && !_disposed;

  @override
  bool get isVisible => isSpawned && _visible;

  @override
  Future<void> spawn({required VideoPreview initialPreview}) async {
    _ensureNotDisposed('spawn');
    if (isSpawned) return;

    final args = jsonEncode({
      'windowType': _windowType,
      'initialPreview': initialPreview.toJson(),
      // Phase 1D: locale flows main → popup via launch args. Popup
      // engine doesn't import easy_localization (boot-speed cost) so
      // it consults its inline _PopupStrings table keyed by this code.
      'localeCode': _localeCode,
      ..._placementArgs(),
    });

    final config = WindowConfiguration(
      arguments: args,
      // Keep hidden until the popup-side UI has positioned itself; the
      // popup's own main() calls show() once it's ready.
      hiddenAtLaunch: true,
    );

    final factory = _windowFactoryOverride ?? WindowController.create;

    try {
      // Reset the ready completer BEFORE creating the window so the
      // popup engine's first IPC call (popupReady) can complete it
      // even if the window starts up exceptionally fast.
      _popupReady = Completer<void>();

      _controller = await factory(config);
      _visible = false; // hidden until popup calls show on its side

      // Wire inbound channel AFTER controller is up so the engine
      // exists to deliver messages.
      _channel = const WindowMethodChannel(_channelName);
      _channel!.setMethodCallHandler(_handleIncoming);

      // Codex audit P1 #4 fix: wait for the popup engine to signal it
      // has registered its own setMethodCallHandler before any
      // commands (showPreview/setQuotaState/etc.) are issued. Without
      // this, the very first invokeMethod can race past the popup's
      // handler registration and silently drop. 3-second timeout
      // protects against a popup that never reports ready (e.g.,
      // crashed during init) — main proceeds and may drop the first
      // command, but at least doesn't hang.
      try {
        await _popupReady!.future.timeout(_kPopupReadyTimeout);
      } on TimeoutException {
        appLogger.warning(
          '[FloatingWindow] popup ready timeout — proceeding anyway',
        );
      }

      appLogger.info('[FloatingWindow] spawned: id=${_controller!.windowId}');
    } catch (e, stack) {
      appLogger.error('[FloatingWindow] spawn failed', e, stack);
      _controller = null;
      _channel = null;
      _popupReady = null;
      rethrow;
    }
  }

  @override
  Future<void> show() async {
    _ensureNotDisposed('show');
    final c = _controller;
    if (c == null) {
      throw StateError(
        'DesktopMultiWindowFloatingWindow.show() called before spawn()',
      );
    }
    if (!_visible) {
      await _applyPlacement();
    }
    await c.show();
    _visible = true;
  }

  @override
  Future<void> hide() async {
    _ensureNotDisposed('hide');
    final c = _controller;
    if (c == null) return;
    await c.hide();
    _visible = false;
  }

  @override
  Future<void> pushQueue(VideoPreview preview) async {
    _ensureNotDisposed('pushQueue');
    await _invoke('pushQueue', preview.toJson());
  }

  @override
  Future<void> showPreview(VideoPreview preview) async {
    _ensureNotDisposed('showPreview');
    final c = _controller;
    if (c == null) {
      throw StateError(
        'DesktopMultiWindowFloatingWindow.showPreview() called before spawn()',
      );
    }
    // showPreview is "show *this* preview" — it must actually reveal the
    // popup if it's hidden, otherwise the IPC update is silent and the user
    // sees no feedback after copying a URL. Show first so the popup paints
    // its current state, then push the new content so it overwrites.
    if (!_visible) {
      await _applyPlacement();
      await c.show();
      _visible = true;
    }
    await _invoke('showPreview', preview.toJson());
  }

  @override
  Future<void> clearQueue() async {
    _ensureNotDisposed('clearQueue');
    await _invoke('clearQueue', null);
    _visible = false;
  }

  @override
  Future<void> setQuotaState({required int remaining}) async {
    _ensureNotDisposed('setQuotaState');
    await _invoke('setQuotaState', {'remaining': remaining});
  }

  @override
  Future<void> setActionResult(PopupActionResult result) async {
    _ensureNotDisposed('setActionResult');
    try {
      await _invoke('setActionResult', result.toJson());
    } catch (e) {
      // v2.2 Phase 2C: tolerate older popup engines that lack the handler
      // (e.g. mid-rollout where popup binary is one release behind main).
      // Swallow + log; UI just stays in the previous state which is
      // acceptable degradation.
      if (kDebugMode) {
        debugPrint('[FloatingCapture] setActionResult ignored: $e');
      }
    }
  }

  Map<String, Object?> _placementArgs() {
    final avoid = _avoidBoundsProvider?.call();
    if (avoid == null) return const {};
    return {
      'avoidRects': [_rectToJson(avoid)],
    };
  }

  Future<void> _applyPlacement() async {
    final args = _placementArgs();
    if (args.isEmpty) return;
    try {
      await _invoke('applyPlacement', args);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FloatingCapture] applyPlacement ignored: $e');
      }
    }
  }

  Map<String, double> _rectToJson(Rect rect) {
    return {
      'left': rect.left,
      'top': rect.top,
      'width': rect.width,
      'height': rect.height,
    };
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final c = _controller;
    final ch = _channel;
    if (c != null && ch != null) {
      var closeCommandCompleted = false;
      try {
        // Close the popup engine from inside that engine. desktop_multi_window
        // only exposes show/hide cross-engine; the package README documents
        // custom commands for close. A short timeout is intentional because
        // destroying the target engine can drop the IPC response.
        await ch
            .invokeMethod('disposeForQuit')
            .timeout(const Duration(milliseconds: 700));
        closeCommandCompleted = true;
      } catch (e, stack) {
        appLogger.warning(
          '[FloatingWindow] disposeForQuit IPC did not complete; hiding fallback',
          e,
          stack,
        );
      }
      if (!closeCommandCompleted) {
        try {
          await c.hide();
        } catch (e, stack) {
          appLogger.error('[FloatingWindow] hide on dispose failed', e, stack);
        }
      }
    }
    // Unregister after the close attempt. Doing this before disposeForQuit would
    // unregister this engine from the bidirectional channel and make the command
    // unreachable.
    try {
      ch?.setMethodCallHandler(null);
    } catch (e, stack) {
      appLogger.error('[FloatingWindow] handler unregister failed', e, stack);
    }
    _controller = null;
    _channel = null;
    _visible = false;
    await _events.close();
  }

  Future<void> _invoke(String method, Object? args) async {
    final ch = _channel;
    if (ch == null) {
      throw StateError(
        'DesktopMultiWindowFloatingWindow.$method() called before spawn()',
      );
    }
    try {
      await ch.invokeMethod(method, args);
    } catch (e, stack) {
      // Log and rethrow — caller (CaptureService) decides how to handle.
      // Most likely cause: popup engine torn down externally.
      appLogger.error('[FloatingWindow] $method failed', e, stack);
      rethrow;
    }
  }

  /// Translate raw popup → main messages into typed events.
  /// Unknown methods are logged and silently dropped (forward compat —
  /// popup binary may be ahead of main in mismatched-version scenarios).
  Future<dynamic> _handleIncoming(MethodCall call) async {
    final method = call.method;
    final args = call.arguments;

    // Codex audit P1 #4: handshake message — popup engine signals it
    // has finished registering its setMethodCallHandler. spawn() is
    // awaiting this completer before returning so subsequent
    // invokeMethod calls don't race the popup's handler registration.
    if (method == 'popupReady') {
      final ready = _popupReady;
      if (ready != null && !ready.isCompleted) {
        ready.complete();
      }
      return null;
    }

    // v2.2 Phase 2C reviewer-2 P0b + reviewer-3 Fix 6: pure visibility
    // sync for popup auto-close (NOT a user action — don't blocklist URL,
    // don't route through parsed-event path). Predicate extracted to
    // [isPopupAutoHiddenMethod] for unit-testability.
    if (isPopupAutoHiddenMethod(method)) {
      _visible = false;
      return null;
    }

    try {
      final event = parseFloatingWindowEvent(method, args);
      if (event != null) {
        // Terminal-hide predicate extracted to [isTerminalHideEvent] for
        // unit-testability + single source of truth across reviewer fixes.
        if (isTerminalHideEvent(event)) {
          _visible = false;
          unawaited(
            _controller?.hide().catchError((Object e, StackTrace s) {
              appLogger.error(
                '[FloatingWindow] defensive hide on terminal event failed',
                e,
                s,
              );
            }),
          );
        }
        _events.add(event);
      } else {
        appLogger.info('[FloatingWindow] unknown event: $method');
      }
    } catch (e, stack) {
      appLogger.error(
        '[FloatingWindow] failed to parse event $method',
        e,
        stack,
      );
    }
    return null;
  }

  void _ensureNotDisposed(String method) {
    if (_disposed) {
      throw StateError(
        'DesktopMultiWindowFloatingWindow.$method() called after dispose()',
      );
    }
  }
}
