import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/player/domain/services/system_pip_service.dart';
import '../constants/app_constants.dart';
import '../design/design_tokens.dart' show AppMinWidth;
import '../logging/app_logger.dart';

@immutable
class RestoredWindowState {
  final Size size;
  final Offset? position;
  final bool isMaximized;

  const RestoredWindowState({
    required this.size,
    required this.position,
    required this.isMaximized,
  });
}

/// Window Manager Service
/// Handles window size, position, state persistence
class WindowService {
  static const String _keyWindowWidth = 'window_width';
  static const String _keyWindowHeight = 'window_height';
  static const String _keyWindowX = 'window_x';
  static const String _keyWindowY = 'window_y';
  static const String _keyIsMaximized = 'window_maximized';
  // V2 Spec §4.4.1 mandates 1024×720 minimum window size; replaces the
  // earlier 960×600 default so the V2 layout (3-column + min-widths
  // chain) never drops below its lowest responsive layer. Sourced from
  // [AppMinWidth] via design_tokens.dart so any future token change
  // propagates here automatically.
  static const double _minRestoredWidth = AppMinWidth.appWindow;
  static const double _minRestoredHeight = AppMinWidth.appWindowHeight;

  // Debounce timer for window state saving (prevents disk I/O spam)
  static Timer? _saveStateTimer;

  /// Dispose resources and cancel pending timers
  static Future<void> dispose() async {
    _saveStateTimer?.cancel();
    _saveStateTimer = null;
  }

  /// Initialize window manager with saved state.
  ///
  /// Hot restart safety: On hot restart, the native window persists but Dart
  /// resets. Calls that trigger NSWindow delegate events (setSize, setPosition,
  /// show, focus, maximize) cause a re-entrant method channel deadlock:
  ///   Dart→native "setBounds" → native setFrame → windowDidResize delegate
  ///   → native→Dart "onEvent" → Dart blocked awaiting "setBounds" → deadlock
  ///
  /// We detect hot restart via isVisible() (window hidden on first launch by
  /// hiddenWindowAtLaunch() in MainFlutterWindow.swift) and skip those calls.
  static Future<void> initialize() async {
    try {
      await windowManager.ensureInitialized();

      // Keep native close semantics. AppScaffold's WindowListener saves state
      // and destroys the window when the platform emits a close event.

      // Detect hot restart: window is already visible from previous run.
      // On first launch, hiddenWindowAtLaunch() in Swift hides the window,
      // so isVisible() returns false. On hot restart, the window persists
      // visible from the previous run, so isVisible() returns true.
      final isHotRestart = await windowManager.isVisible();

      // Get screen bounds for validation
      final primaryDisplay = await screenRetriever.getPrimaryDisplay();
      final screenWidth = primaryDisplay.size.width;
      final screenHeight = primaryDisplay.size.height;

      // Load saved window state
      final prefs = await SharedPreferences.getInstance();
      final rawWidth = prefs.getDouble(_keyWindowWidth) ?? 1200.0;
      final rawHeight = prefs.getDouble(_keyWindowHeight) ?? 800.0;
      final rawX = prefs.getDouble(_keyWindowX);
      final rawY = prefs.getDouble(_keyWindowY);
      final isMaximized = prefs.getBool(_keyIsMaximized) ?? false;

      final restoredState = restoreWindowState(
        screenWidth: screenWidth,
        screenHeight: screenHeight,
        rawWidth: rawWidth,
        rawHeight: rawHeight,
        rawX: rawX,
        rawY: rawY,
        isMaximized: isMaximized,
      );

      // Safe calls: these don't trigger NSWindow delegate events
      await windowManager.setMinimumSize(
        const Size(_minRestoredWidth, _minRestoredHeight),
      );
      await windowManager.setTitle(AppConstants.appName);

      // Title bar: macOS configures natively in MainFlutterWindow.swift
      // (setTitleBarStyle crashes on macOS hot restart — force-unwrap at WindowManager.swift:392).
      // Windows/Linux: safe to call from Dart (just sets a string + margins, no crash risk).
      if (!Platform.isMacOS) {
        await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      }

      if (isHotRestart) {
        // Hot restart: window already visible with correct size/position.
        // Skip delegate-triggering calls to prevent deadlock.
        appLogger.info('Hot restart detected, skipping window reconfiguration');
      } else {
        // First launch: window is hidden by hiddenWindowAtLaunch().
        // Configure size, position, then show.
        await windowManager.setSize(restoredState.size);

        if (restoredState.position != null) {
          await windowManager.setPosition(restoredState.position!);
        } else {
          await windowManager.setAlignment(Alignment.center);
        }

        if (restoredState.isMaximized) {
          await windowManager.maximize();
        }

        // Show window (was hidden by hiddenWindowAtLaunch in Swift)
        await windowManager.show();
        await windowManager.focus();
      }

      // Listen to window events for state persistence
      _setupWindowListeners();

      appLogger.info('Window configured successfully');
    } catch (e, stackTrace) {
      appLogger.error('Failed to initialize window manager', e, stackTrace);
      // Safeguard: ensure window is visible even if setup failed.
      // hiddenWindowAtLaunch() hides the window, so if we crash before show(),
      // the window stays invisible. Force show as last resort.
      try {
        await windowManager.show();
      } catch (_) {}
    }
  }

  /// Setup listeners to save window state
  static void _setupWindowListeners() {
    // Save state on window resize/move
    // This will be handled by WindowListener mixin in app_scaffold.dart
  }

  @visibleForTesting
  static RestoredWindowState restoreWindowState({
    required double screenWidth,
    required double screenHeight,
    required double rawWidth,
    required double rawHeight,
    required double? rawX,
    required double? rawY,
    required bool isMaximized,
  }) {
    final restoredWidth = rawWidth.clamp(_minRestoredWidth, screenWidth * 0.9);
    final restoredHeight = rawHeight.clamp(
      _minRestoredHeight,
      screenHeight * 0.9,
    );

    Offset? restoredPosition;
    if (rawX != null && rawY != null) {
      // Ensure window is at least 100px visible on screen
      if (rawX >= -100 &&
          rawX < screenWidth - 100 &&
          rawY >= -100 &&
          rawY < screenHeight - 100) {
        restoredPosition = Offset(rawX, rawY);
      }
    }

    return RestoredWindowState(
      size: Size(restoredWidth, restoredHeight),
      position: restoredPosition,
      isMaximized: isMaximized,
    );
  }

  /// Save current window state (debounced to prevent disk I/O spam)
  static void saveWindowStateDebounced() {
    // Don't persist PiP window geometry — the saved state should reflect
    // the normal window configuration so restarts use the right size.
    if (SystemPipService.isActive) return;

    // Cancel existing timer
    _saveStateTimer?.cancel();

    // Set new timer - save state 500ms after last window event
    _saveStateTimer = Timer(const Duration(milliseconds: 500), () {
      saveWindowState();
    });
  }

  /// Save current window state immediately (for app close)
  static Future<void> saveWindowState() async {
    if (SystemPipService.isActive) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final size = await windowManager.getSize();
      final position = await windowManager.getPosition();
      final isMaximized = await windowManager.isMaximized();

      await prefs.setDouble(_keyWindowWidth, size.width);
      await prefs.setDouble(_keyWindowHeight, size.height);
      await prefs.setDouble(_keyWindowX, position.dx);
      await prefs.setDouble(_keyWindowY, position.dy);
      await prefs.setBool(_keyIsMaximized, isMaximized);

      appLogger.debug('Window state saved');
    } catch (e) {
      appLogger.error('Failed to save window state', e);
    }
  }

  /// Show window
  static Future<void> show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  /// Hide window
  static Future<void> hide() async {
    await windowManager.hide();
  }

  /// Toggle window visibility: show+focus if hidden/minimized, hide if visible.
  static Future<void> toggle() async {
    final visible = await windowManager.isVisible();
    if (visible) {
      await windowManager.hide();
    } else {
      await windowManager.show();
      await windowManager.focus();
    }
  }

  /// Minimize window
  static Future<void> minimize() async {
    await windowManager.minimize();
  }

  /// Maximize/restore window
  static Future<void> toggleMaximize() async {
    final isMaximized = await windowManager.isMaximized();
    if (isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  /// Close window (quit app)
  static Future<void> close() async {
    await saveWindowState();
    await windowManager.close();
  }

  /// Set window to always on top
  static Future<void> setAlwaysOnTop(bool enabled) async {
    await windowManager.setAlwaysOnTop(enabled);
  }

  /// Get primary display info
  static Future<Display> getPrimaryDisplay() async {
    return await screenRetriever.getPrimaryDisplay();
  }

  /// Get all displays
  static Future<List<Display>> getAllDisplays() async {
    return await screenRetriever.getAllDisplays();
  }

  /// Check if window is visible
  static Future<bool> isVisible() async {
    return await windowManager.isVisible();
  }

  /// Check if app is focused
  static Future<bool> isFocused() async {
    return await windowManager.isFocused();
  }

  /// Platform-specific shortcuts hint
  static String get platformModifierKey {
    return Platform.isMacOS ? 'Cmd' : 'Ctrl';
  }
}
