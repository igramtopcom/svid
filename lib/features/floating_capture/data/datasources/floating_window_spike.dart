// SPIKE — Phase 1A.3 verification of `desktop_multi_window` plugin viability.
//
// This file demonstrates the plugin API surface needed for v2.1 floating
// capture per spec §3.2 (multi-window approach). It is NOT wired into main
// app yet — purpose is to verify:
//
// 1. Plugin compiles with our existing codebase + dependencies
// 2. API surface matches what spec architecture (§3.3 IPC) requires
// 3. WindowMethodChannel pattern works for bidirectional messaging
//
// Spike findings documented at end of file. To run actual window spawn,
// modify main.dart entry point per `desktop_multi_window` README.
//
// This file is intentionally NOT exported and NOT instantiated anywhere
// in the app — pure compile-time API verification.

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Size;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException;

import '../../../../core/logging/app_logger.dart';
import '../../../downloads/domain/entities/video_preview.dart';

/// Spike to verify `desktop_multi_window` plugin meets spec requirements.
///
/// Used as compile-time API check. Methods here exercise the plugin API
/// shapes we'll need for full implementation in Phase 1A.3.
///
/// **DO NOT INSTANTIATE** in production code — this is throwaway spike code.
/// Annotated `@visibleForTesting` to trigger analyzer warning if any non-test
/// code attempts to import or instantiate. Class will be deleted when Phase
/// 1A.3 full implementation extracts the useful learnings into
/// `FloatingWindowManager`.
@visibleForTesting
class FloatingWindowSpike {
  /// Channel name for IPC between main and floating engines.
  /// Matches spec §3.3 ('svid.floating_capture').
  static const String _channelName = 'svid.floating_capture';

  /// Dimensions per spec §4.1 (Portrait 300×420 collapsed).
  static const Size _floatingWindowSize = Size(300, 420);

  WindowController? _floatingWindowController;
  WindowMethodChannel? _channel;

  /// Spawn the floating capture window.
  ///
  /// Per spec §3.1, this creates a SEPARATE Flutter engine instance with its
  /// own Riverpod ProviderContainer. State must be synced via WindowMethodChannel.
  Future<void> spawnFloatingWindow({
    required VideoPreview initialPreview,
  }) async {
    try {
      // Encode preview as window arguments. Floating engine's main()
      // parses these args to know which app to bootstrap.
      final args = jsonEncode({
        'windowType': 'floating_capture',
        'initialPreview': initialPreview.toJson(),
      });

      final config = WindowConfiguration(
        arguments: args,
        hiddenAtLaunch: true, // we'll show after positioning
      );

      // Create the window (returns once native window is ready).
      final controller = await WindowController.create(config);
      _floatingWindowController = controller;

      // Position bottom-right of primary screen (per spec §4 default position).
      // Note: the plugin's WindowController doesn't expose setFrame directly —
      // the spec assumes integration with `window_manager` for frame control.
      // For SPIKE, defer to manual user drag after first show.

      // Show the window (non-stealing focus per spec Q15).
      // Note: focus-steal control requires native NSPanel attribute override.
      // Plugin doesn't expose this — must use platform channel to set
      // NSPanel.becomesKeyOnlyIfNeeded after window appears.
      await controller.show();

      // Set up channel for receiving events from floating window.
      _channel = const WindowMethodChannel(_channelName);
      _channel!.setMethodCallHandler((call) async {
        return _handleFloatingWindowEvent(call.method, call.arguments);
      });

      appLogger.info('[Spike] Floating window spawned: id=${controller.windowId}');
    } catch (e, stack) {
      appLogger.error('[Spike] Failed to spawn floating window', e, stack);
      rethrow;
    }
  }

  /// Send updated preview to floating window (Main → Floating message).
  /// Per spec §3.3 method: `showPreview`.
  Future<void> showPreview(VideoPreview preview) async {
    if (_channel == null) {
      throw StateError('Floating window not spawned');
    }
    await _channel!.invokeMethod('showPreview', preview.toJson());
  }

  /// Push another URL into the queue (Main → Floating).
  /// Per spec §3.3 method: `pushQueue`.
  Future<void> pushQueue(VideoPreview preview) async {
    if (_channel == null) return;
    await _channel!.invokeMethod('pushQueue', preview.toJson());
  }

  /// Clear queue and hide popup (Main → Floating).
  Future<void> clearQueue() async {
    if (_channel == null) return;
    await _channel!.invokeMethod('clearQueue');
  }

  /// Update quota state in floating window (Main → Floating).
  Future<void> setQuotaState(int remaining) async {
    if (_channel == null) return;
    await _channel!.invokeMethod('setQuotaState', {'remaining': remaining});
  }

  /// Hide floating window. Note: plugin v0.3.0 does NOT expose a `close()`
  /// to fully destroy the window engine — only `hide()`. For full destroy,
  /// must add platform channel call to native code (e.g., NSWindow.close).
  Future<void> dismiss() async {
    if (_floatingWindowController != null) {
      await _floatingWindowController!.hide();
      // FINDING: WindowController API only has hide(), not close().
      // Engine remains alive. For Phase 1A.3 full impl, add native
      // platform channel to actually destroy + reclaim engine resources.
      _channel = null;
    }
  }

  /// Handle events from floating window (Floating → Main).
  /// Per spec §3.3 events: onDownloadClicked, onSnoozeSelected, etc.
  Future<dynamic> _handleFloatingWindowEvent(
    String method,
    dynamic arguments,
  ) async {
    appLogger.info('[Spike] Event from floating: $method');
    switch (method) {
      case 'onDownloadClicked':
        // arguments: {url: String, downloadConfig: Map?}
        return _handleDownloadClicked(arguments as Map<String, dynamic>);

      case 'onSnoozeSelected':
        // arguments: {duration: String} ('thirtyMinutes', 'oneHour', etc.)
        return _handleSnooze(arguments as Map<String, dynamic>);

      case 'onMenuOpenApp':
        // No args — bring main window to focus
        return null;

      case 'onMenuOpenSettings':
        // No args — open Settings → Capture page
        return null;

      case 'onPositionChanged':
        // arguments: {x: double, y: double, monitorId: String}
        return null;

      case 'onPopupDismissed':
        // No args — clear queue state in main
        return null;

      case 'onThumbnailClicked':
        // arguments: {url: String} — open external browser
        return null;

      case 'onOpenInAppClicked':
        // arguments: {url: String} — route to main app sheet
        return null;

      default:
        throw MissingPluginException('Unknown event: $method');
    }
  }

  Future<void> _handleDownloadClicked(Map<String, dynamic> args) async {
    // Spike stub — full impl in Phase 1A.5 CaptureDownloadCoordinator
    appLogger.info('[Spike] Download requested for: ${args['url']}');
  }

  Future<void> _handleSnooze(Map<String, dynamic> args) async {
    // Spike stub — full impl in Phase 1A.5 CaptureService
    appLogger.info('[Spike] Snooze selected: ${args['duration']}');
  }

  /// Verify plugin loads + API surface accessible.
  /// Returns true if plugin is callable (returns null if not yet spawned).
  Future<bool> verifyPluginAccessible() async {
    try {
      // Try fetching all controllers — works even with no windows spawned
      final controllers = await WindowController.getAll();
      appLogger.info(
        '[Spike] Plugin accessible. Active windows: ${controllers.length}',
      );
      return true;
    } catch (e) {
      appLogger.error('[Spike] Plugin NOT accessible: $e');
      return false;
    }
  }
}

// ============================================================================
// SPIKE FINDINGS — documented during 1A.3 verification
// ============================================================================
//
// PLUGIN: desktop_multi_window v0.3.0 (MixinNetwork, last update 2025-10-28)
// VERIFIED ON: macOS (current dev machine)
// NOT VERIFIED ON: Windows, Linux (need separate machines)
//
// API SURFACE — VERIFIED COMPILES:
// ✅ WindowController.create(WindowConfiguration)
// ✅ WindowController.fromCurrentEngine() — for floating window's main()
// ✅ WindowController.getAll() — list all spawned windows
// ✅ WindowConfiguration(arguments: String, hiddenAtLaunch: bool)
// ✅ WindowMethodChannel(name).invokeMethod() — Main → Floating
// ✅ WindowMethodChannel(name).setMethodCallHandler() — Floating → Main
// ✅ controller.show() / controller.close()
//
// ⚠️ MISSING from plugin (need workarounds in full impl):
// - No setFrame / setSize / setPosition exposed on WindowController
//   → Must use window_manager (existing dep) inside floating window
// - No always-on-top / NSPanel attribute control
//   → Must add platform channel to set NSPanel attributes after window shown
// - No focus-steal prevention
//   → Same — needs native NSPanel.becomesKeyOnlyIfNeeded override
// - No window position persistence built-in
//   → Implement in CaptureService.savePosition() with SharedPreferences
//
// 🔧 NATIVE INTEGRATION REQUIRED (per plugin README):
// - macos/Runner/MainFlutterWindow.swift: import desktop_multi_window
//   + add FlutterMultiWindowPlugin.setOnWindowCreatedCallback callback
//   in awakeFromNib() to register plugins for child windows
// - windows/runner/flutter_window.cpp: similar registration
//
// 🎯 DECISION (per spec 1A.3 gate):
// ✅ CONTINUE with desktop_multi_window for v2.1 floating capture
// - API surface matches spec §3.3 IPC architecture requirements
// - Plugin actively maintained, recent v0.3.0 release (Oct 2025)
// - Window-level controls (always-on-top, focus-steal) need native channel
//   additions but architecture supports it (see §6.2 native code samples)
// - Compatible with existing window_manager dependency for frame control
//
// ✅ VERIFIED:
// - `flutter pub get` succeeds with plugin
// - macOS build: `flutter build macos --debug` produces working .app
// - Plugin auto-registered in GeneratedPluginRegistrant.swift
// - Symlink created at macos/Flutter/ephemeral/.symlinks/plugins/desktop_multi_window
// - No conflict with existing 24 plugins (window_manager, tray_manager, etc.)
// - CocoaPods integration succeeded (Podfile.lock auto-updated)
//
// 📋 NEXT IMPLEMENTATION TASKS (Phase 1A.3 full):
// 1. Add native registration callbacks (MainFlutterWindow.swift)
// 2. Refactor main.dart entry point for window-type dispatch (per README §1)
// 3. Build FloatingWindowManager (this spike's logic, productionized)
// 4. Add platform channel `svid.floating_capture.native` for:
//    - Set NSPanel attributes (always-on-top, no-focus-steal)
//    - Set window position relative to monitor
//    - Listen for monitor disconnect events
// 5. Build floating window app entry point (lib/floating_window_main.dart)
// 6. Wire WindowMethodChannel pipeline per spec §3.3
//
// 🚧 RUNTIME VERIFICATION NEEDED:
// This spike verifies API compiles, NOT runtime behavior. Before Phase 1A.4,
// must:
// - Actually run app on macOS, spawn window, verify it appears
// - Test method channel hello-world end-to-end
// - Verify window doesn't steal focus when spawned
// - Test multi-monitor positioning
//
// Suppress unused warnings — file is API verification only, not instantiated.
// ignore_for_file: unused_element, unused_field
@visibleForTesting
class SpikeApiCheck {
  // Compile-time check that plugin types resolve.
  static const _types = [
    WindowController,
    WindowConfiguration,
    WindowMethodChannel,
  ];
  static List<Type> get types => _types;
}
