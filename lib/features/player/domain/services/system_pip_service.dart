import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/services/window_geometry_service.dart';

/// Manages system-level Picture-in-Picture by compacting the main window.
///
/// When active, the app window shrinks to a small always-on-top video player.
/// Other apps remain usable underneath. The previous window geometry is saved
/// and restored when PiP is exited.
class SystemPipService {
  static Size? _savedSize;
  static Offset? _savedPosition;
  static bool _savedMaximized = false;
  static bool _isActive = false;
  static Rect? _activeBounds;

  /// Whether system PiP mode is currently active.
  static bool get isActive => _isActive;

  /// Current PiP window bounds in screen coordinates, when active.
  static Rect? get activeBounds => _isActive ? _activeBounds : null;

  /// Enter system PiP: compact window, always-on-top, position at screen corner.
  static Future<void> enter({
    double pipWidth = 400,
    double pipHeight = 240,
  }) async {
    if (_isActive) return;

    try {
      // Save current window state for restoration
      _savedSize = await windowManager.getSize();
      _savedPosition = await windowManager.getPosition();
      _savedMaximized = await windowManager.isMaximized();

      if (_savedMaximized) {
        await windowManager.unmaximize();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      // Allow small PiP sizes (override normal 960×600 minimum)
      await windowManager.setMinimumSize(const Size(240, 135));

      final pipSize = Size(pipWidth, pipHeight);
      final visibleBounds = await _displayForCurrentWindow();
      final pipPosition = WindowGeometryService.bottomRightPosition(
        visibleBounds: visibleBounds,
        windowSize: pipSize,
      );
      _activeBounds = pipPosition & pipSize;
      _isActive = true;

      await windowManager.setSize(pipSize);
      await windowManager.setPosition(pipPosition);
      await windowManager.setAlwaysOnTop(true);

      appLogger.info(
        'System PiP entered: ${pipWidth.toInt()}×${pipHeight.toInt()}',
      );
    } catch (e) {
      _isActive = false;
      _activeBounds = null;
      appLogger.error('Failed to enter system PiP', e);
    }
  }

  /// Exit system PiP: restore window to pre-PiP state.
  static Future<void> exit() async {
    if (!_isActive) return;

    try {
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setMinimumSize(const Size(960, 600));

      if (_savedSize != null) {
        await windowManager.setSize(_savedSize!);
      }
      if (_savedPosition != null) {
        final visibleBounds = await _displayForSavedWindow();
        final safePosition = WindowGeometryService.clampPosition(
          position: _savedPosition!,
          windowSize: _savedSize ?? const Size(960, 600),
          visibleBounds: visibleBounds,
        );
        await windowManager.setPosition(safePosition);
      }
      if (_savedMaximized) {
        await windowManager.maximize();
      }

      _isActive = false;
      _activeBounds = null;
      _savedSize = null;
      _savedPosition = null;
      _savedMaximized = false;

      appLogger.info('System PiP exited, window restored');
    } catch (e) {
      appLogger.error('Failed to exit system PiP', e);
    }
  }

  static Future<Rect> _displayForCurrentWindow() async {
    final size = _savedSize ?? await windowManager.getSize();
    final position = _savedPosition ?? await windowManager.getPosition();
    return _chooseDisplayForWindow(position, size);
  }

  static Future<Rect> _displayForSavedWindow() async {
    final size = _savedSize ?? await windowManager.getSize();
    final position = _savedPosition ?? await windowManager.getPosition();
    return _chooseDisplayForWindow(position, size);
  }

  static Future<Rect> _chooseDisplayForWindow(
    Offset position,
    Size size,
  ) async {
    final primary = await screenRetriever.getPrimaryDisplay();
    final displays = await screenRetriever.getAllDisplays();
    final fallback = _visibleRect(primary);
    final bounds = displays.map(_visibleRect).toList();
    return WindowGeometryService.chooseDisplayForWindow(
      windowBounds: position & size,
      displayBounds: bounds,
      fallback: fallback,
    );
  }

  static Rect _visibleRect(Display display) {
    return WindowGeometryService.visibleRect(
      displaySize: display.size,
      visiblePosition: display.visiblePosition,
      visibleSize: display.visibleSize,
    );
  }
}
