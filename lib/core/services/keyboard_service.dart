import 'dart:io';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import '../logging/app_logger.dart';
import 'window_service.dart';

/// Helper to convert logical key to physical key for hotkey
extension on LogicalKeyboardKey {
  PhysicalKeyboardKey get toPhysical {
    // Map logical to physical keys
    if (this == LogicalKeyboardKey.keyQ) return PhysicalKeyboardKey.keyQ;
    if (this == LogicalKeyboardKey.keyW) return PhysicalKeyboardKey.keyW;
    if (this == LogicalKeyboardKey.keyF) return PhysicalKeyboardKey.keyF;
    if (this == LogicalKeyboardKey.keyN) return PhysicalKeyboardKey.keyN;
    if (this == LogicalKeyboardKey.keyH) return PhysicalKeyboardKey.keyH;
    if (this == LogicalKeyboardKey.keyM) return PhysicalKeyboardKey.keyM;
    if (this == LogicalKeyboardKey.keyV) return PhysicalKeyboardKey.keyV;
    if (this == LogicalKeyboardKey.keyP) return PhysicalKeyboardKey.keyP;
    if (this == LogicalKeyboardKey.keyR) return PhysicalKeyboardKey.keyR;
    if (this == LogicalKeyboardKey.keyD) return PhysicalKeyboardKey.keyD;
    if (this == LogicalKeyboardKey.keyS) return PhysicalKeyboardKey.keyS;
    if (this == LogicalKeyboardKey.comma) return PhysicalKeyboardKey.comma;
    return PhysicalKeyboardKey.keyA; // Fallback
  }
}

/// Keyboard Shortcut Service
/// Handles system-wide keyboard shortcuts for desktop platforms
class KeyboardService {
  // Callbacks for in-app keyboard shortcuts
  static Function()? onSearchShortcut;
  static Function()? onNewDownloadShortcut;
  static Function()? onSettingsShortcut;
  static Function()? onPasteAndStartShortcut;
  static Function()? onPauseAllShortcut;
  static Function()? onResumeAllShortcut;
  static Function()? onOpenPlayerShortcut;
  static Function()? onTogglePipShortcut;

  /// Context-aware close handler. When on browser tab, closes the active tab.
  /// When elsewhere, minimizes the window. Set by AppScaffold.
  static Function()? onCloseOrMinimize;

  /// Explicit app quit handler. AppScaffold wires this to the normal native
  /// close path so Ctrl+Q matches the title-bar close behavior.
  static Future<void> Function()? onQuitShortcut;

  // Callbacks for global (system-scope) shortcuts
  /// Show window + open new download dialog (works even when Svid is in background).
  static Function()? onShowAndNewDownload;

  /// Download clipboard URL silently without showing window.
  static Future<void> Function()? onDownloadFromClipboardGlobal;

  /// Toggle window visibility (show/hide).
  static Function()? onToggleVisibility;

  /// Initialize keyboard shortcuts
  static Future<void> initialize() async {
    try {
      // Only enable on desktop platforms
      if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
        return;
      }

      await hotKeyManager.unregisterAll();

      // Register shortcuts based on platform
      await _registerPlatformShortcuts();

      appLogger.info('Keyboard shortcuts initialized');
    } catch (e, stackTrace) {
      appLogger.error('Failed to initialize keyboard shortcuts', e, stackTrace);
    }
  }

  /// Register platform-specific shortcuts
  static Future<void> _registerPlatformShortcuts() async {
    if (Platform.isMacOS) {
      await _registerMacOSShortcuts();
    } else if (Platform.isWindows || Platform.isLinux) {
      await _registerWindowsLinuxShortcuts();
    }
  }

  /// Register macOS-specific shortcuts (Cmd key)
  static Future<void> _registerMacOSShortcuts() async {
    // NOTE: Cmd+Q, Cmd+H, and Cmd+M are handled by macOS natively.
    // We don't register them to maintain native behavior

    // Cmd + W: Context-aware — close browser tab if on browser, else minimize window
    await _registerHotkey(
      HotKey(
        key: LogicalKeyboardKey.keyW.toPhysical,
        modifiers: [HotKeyModifier.meta],
        scope: HotKeyScope.inapp,
      ),
      () async {
        if (onCloseOrMinimize != null) {
          onCloseOrMinimize!();
        } else {
          appLogger.info('Cmd+W pressed - Minimizing window');
          await WindowService.minimize();
        }
      },
      description: 'Close tab or minimize window',
    );

    // Cmd + F: Focus search (use inapp scope to avoid conflicts)
    await _registerHotkey(
      HotKey(
        key: LogicalKeyboardKey.keyF.toPhysical,
        modifiers: [HotKeyModifier.meta],
        scope: HotKeyScope.inapp, // Changed from system to inapp
      ),
      () {
        appLogger.debug('Cmd+F pressed - Focusing search');
        onSearchShortcut?.call();
      },
      description: 'Focus search',
    );

    // Cmd + N: New download (use inapp scope)
    await _registerHotkey(
      HotKey(
        key: LogicalKeyboardKey.keyN.toPhysical,
        modifiers: [HotKeyModifier.meta],
        scope: HotKeyScope.inapp, // Changed from system to inapp
      ),
      () {
        appLogger.debug('Cmd+N pressed - New download');
        onNewDownloadShortcut?.call();
      },
      description: 'New download',
    );

    // Cmd + ,: Settings (macOS standard)
    await _registerHotkey(
      HotKey(
        key: LogicalKeyboardKey.comma.toPhysical,
        modifiers: [HotKeyModifier.meta],
        scope: HotKeyScope.inapp,
      ),
      () {
        appLogger.debug('Cmd+, pressed - Opening settings');
        onSettingsShortcut?.call();
      },
      description: 'Open settings',
    );

    // Cmd + Shift + V: Paste URL and start download
    // NOTE: Cmd+V is intentionally NOT used — it intercepts native text paste in all text fields
    await _registerHotkey(
      HotKey(
        key: LogicalKeyboardKey.keyV.toPhysical,
        modifiers: [HotKeyModifier.meta, HotKeyModifier.shift],
        scope: HotKeyScope.inapp,
      ),
      () {
        appLogger.debug('Cmd+Shift+V pressed - Paste URL and start');
        onPasteAndStartShortcut?.call();
      },
      description: 'Paste URL and start download',
    );

    // Cmd + Shift + P: Pause all downloads
    await _registerHotkey(
      HotKey(
        key: LogicalKeyboardKey.keyP.toPhysical,
        modifiers: [HotKeyModifier.meta, HotKeyModifier.shift],
        scope: HotKeyScope.inapp,
      ),
      () {
        appLogger.debug('Cmd+Shift+P pressed - Pause all');
        onPauseAllShortcut?.call();
      },
      description: 'Pause all downloads',
    );

    // Cmd + Shift + R: Resume all downloads
    await _registerHotkey(
      HotKey(
        key: LogicalKeyboardKey.keyR.toPhysical,
        modifiers: [HotKeyModifier.meta, HotKeyModifier.shift],
        scope: HotKeyScope.inapp,
      ),
      () {
        appLogger.debug('Cmd+Shift+R pressed - Resume all');
        onResumeAllShortcut?.call();
      },
      description: 'Resume all downloads',
    );

    // Cmd + P: Open player (navigate to downloads)
    await _registerHotkey(
      HotKey(
        key: LogicalKeyboardKey.keyP.toPhysical,
        modifiers: [HotKeyModifier.meta],
        scope: HotKeyScope.inapp,
      ),
      () {
        appLogger.debug('Cmd+P pressed - Open player');
        onOpenPlayerShortcut?.call();
      },
      description: 'Open player',
    );

    // Cmd + Shift + M: Toggle PiP mini-player
    await _registerHotkey(
      HotKey(
        key: LogicalKeyboardKey.keyM.toPhysical,
        modifiers: [HotKeyModifier.meta, HotKeyModifier.shift],
        scope: HotKeyScope.inapp,
      ),
      () {
        appLogger.debug('Cmd+Shift+M pressed - Toggle PiP');
        onTogglePipShortcut?.call();
      },
      description: 'Toggle PiP',
    );

    // --- Global (system-scope) shortcuts — work even when Svid is in background ---

    // Cmd + Shift + D: Show window and open new download dialog (global)
    await _registerHotkey(
      HotKey(
        key: LogicalKeyboardKey.keyD.toPhysical,
        modifiers: [HotKeyModifier.meta, HotKeyModifier.shift],
        scope: HotKeyScope.system,
      ),
      () {
        appLogger.debug('Cmd+Shift+D pressed (global) - Show + new download');
        onShowAndNewDownload?.call();
      },
      description: 'Show window + new download (global)',
    );

    // Cmd + Option + V: Download clipboard URL silently, no window required (global)
    await _registerHotkey(
      HotKey(
        key: LogicalKeyboardKey.keyV.toPhysical,
        modifiers: [HotKeyModifier.meta, HotKeyModifier.alt],
        scope: HotKeyScope.system,
      ),
      () async {
        appLogger.debug(
          'Cmd+Option+V pressed (global) - Download from clipboard',
        );
        await onDownloadFromClipboardGlobal?.call();
      },
      description: 'Download clipboard URL silently (global)',
    );

    // Ctrl + Cmd + S: Toggle window visibility (global)
    await _registerHotkey(
      HotKey(
        key: LogicalKeyboardKey.keyS.toPhysical,
        modifiers: [HotKeyModifier.control, HotKeyModifier.meta],
        scope: HotKeyScope.system,
      ),
      () async {
        appLogger.debug(
          'Ctrl+Cmd+S pressed (global) - Toggle window visibility',
        );
        onToggleVisibility?.call();
      },
      description: 'Toggle window visibility (global)',
    );
  }

  /// Register Windows/Linux shortcuts (Ctrl key)
  static Future<void> _registerWindowsLinuxShortcuts() async {
    // Ctrl + Q: Quit app (use inapp scope to reduce conflicts)
    // Note: Not standard Windows shortcut, but common in cross-platform apps
    await _registerHotkey(
      HotKey(
        key: LogicalKeyboardKey.keyQ.toPhysical,
        modifiers: [HotKeyModifier.control],
        scope: HotKeyScope.inapp, // Changed from system to reduce conflicts
      ),
      () async {
        appLogger.info('Ctrl+Q pressed - Quitting app');
        await _handleQuitShortcut();
      },
      description: 'Quit app',
    );

    // Ctrl + W: Context-aware — close browser tab if on browser, else minimize window
    await _registerHotkey(
      HotKey(
        key: LogicalKeyboardKey.keyW.toPhysical,
        modifiers: [HotKeyModifier.control],
        scope: HotKeyScope.inapp,
      ),
      () async {
        if (onCloseOrMinimize != null) {
          onCloseOrMinimize!();
        } else {
          appLogger.info('Ctrl+W pressed - Minimizing window');
          await WindowService.minimize();
        }
      },
      description: 'Close tab or minimize window',
    );

    // Ctrl + F: Focus search (use inapp scope)
    await _registerHotkey(
      HotKey(
        key: LogicalKeyboardKey.keyF.toPhysical,
        modifiers: [HotKeyModifier.control],
        scope: HotKeyScope.inapp, // Changed from system to inapp
      ),
      () {
        appLogger.debug('Ctrl+F pressed - Focusing search');
        onSearchShortcut?.call();
      },
      description: 'Focus search',
    );

    // Ctrl + N: New download (use inapp scope)
    await _registerHotkey(
      HotKey(
        key: LogicalKeyboardKey.keyN.toPhysical,
        modifiers: [HotKeyModifier.control],
        scope: HotKeyScope.inapp, // Changed from system to inapp
      ),
      () {
        appLogger.debug('Ctrl+N pressed - New download');
        onNewDownloadShortcut?.call();
      },
      description: 'New download',
    );

    // Ctrl + ,: Settings (use inapp scope)
    await _registerHotkey(
      HotKey(
        key: LogicalKeyboardKey.comma.toPhysical,
        modifiers: [HotKeyModifier.control],
        scope: HotKeyScope.inapp,
      ),
      () {
        appLogger.debug('Ctrl+, pressed - Opening settings');
        onSettingsShortcut?.call();
      },
      description: 'Open settings',
    );

    // Ctrl + Shift + V: Paste URL and start download
    // NOTE: Ctrl+V is intentionally NOT used — it intercepts native text paste in all text fields
    await _registerHotkey(
      HotKey(
        key: LogicalKeyboardKey.keyV.toPhysical,
        modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
        scope: HotKeyScope.inapp,
      ),
      () {
        appLogger.debug('Ctrl+Shift+V pressed - Paste URL and start');
        onPasteAndStartShortcut?.call();
      },
      description: 'Paste URL and start download',
    );

    // Ctrl + Shift + P: Pause all downloads
    await _registerHotkey(
      HotKey(
        key: LogicalKeyboardKey.keyP.toPhysical,
        modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
        scope: HotKeyScope.inapp,
      ),
      () {
        appLogger.debug('Ctrl+Shift+P pressed - Pause all');
        onPauseAllShortcut?.call();
      },
      description: 'Pause all downloads',
    );

    // Ctrl + Shift + R: Resume all downloads
    await _registerHotkey(
      HotKey(
        key: LogicalKeyboardKey.keyR.toPhysical,
        modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
        scope: HotKeyScope.inapp,
      ),
      () {
        appLogger.debug('Ctrl+Shift+R pressed - Resume all');
        onResumeAllShortcut?.call();
      },
      description: 'Resume all downloads',
    );

    // Ctrl + P: Open player (navigate to downloads)
    await _registerHotkey(
      HotKey(
        key: LogicalKeyboardKey.keyP.toPhysical,
        modifiers: [HotKeyModifier.control],
        scope: HotKeyScope.inapp,
      ),
      () {
        appLogger.debug('Ctrl+P pressed - Open player');
        onOpenPlayerShortcut?.call();
      },
      description: 'Open player',
    );

    // Ctrl + Shift + M: Toggle PiP mini-player
    await _registerHotkey(
      HotKey(
        key: LogicalKeyboardKey.keyM.toPhysical,
        modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
        scope: HotKeyScope.inapp,
      ),
      () {
        appLogger.debug('Ctrl+Shift+M pressed - Toggle PiP');
        onTogglePipShortcut?.call();
      },
      description: 'Toggle PiP',
    );
  }

  static Future<void> _handleQuitShortcut() async {
    final handler = onQuitShortcut;
    if (handler != null) {
      await handler();
      return;
    }
    await WindowService.close();
  }

  /// Register a hotkey with error handling
  static Future<void> _registerHotkey(
    HotKey hotKey,
    Function() handler, {
    String? description,
  }) async {
    try {
      await hotKeyManager.register(
        hotKey,
        keyDownHandler: (hotKey) {
          handler();
        },
      );
      appLogger.debug('Registered hotkey: ${description ?? hotKey.toString()}');
    } catch (e) {
      appLogger.warning('Failed to register hotkey: $description', e);
    }
  }

  /// Unregister all shortcuts
  static Future<void> dispose() async {
    try {
      await hotKeyManager.unregisterAll();
      appLogger.info('All keyboard shortcuts unregistered');
    } catch (e) {
      appLogger.error('Failed to unregister shortcuts', e);
    }
  }

  /// Get platform modifier key name for UI display
  static String get platformModifierName {
    return Platform.isMacOS ? 'Cmd' : 'Ctrl';
  }

  /// Get platform-specific shortcut text
  static String getShortcutText(String key) {
    return '$platformModifierName+$key';
  }
}
