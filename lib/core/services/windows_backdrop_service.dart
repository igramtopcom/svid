import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/brand_config.dart';
import '../logging/app_logger.dart';

/// Keeps the native Windows fallback backdrop aligned with the Flutter theme.
///
/// The Win32 host may be visible for a frame while Flutter/ANGLE resizes or
/// recreates the child surface. A matching fallback prevents white/black
/// flashes during restore, maximize, and fullscreen player transitions.
class WindowsBackdropService {
  WindowsBackdropService._();

  static final WindowsBackdropService instance = WindowsBackdropService._();

  final MethodChannel _channel = MethodChannel(
    '${BrandConfig.current.methodChannelPrefix}/theme_events',
  );

  String? _lastTheme;

  Future<void> syncThemeMode(ThemeMode mode) async {
    if (!Platform.isWindows) return;

    final theme = resolveBackdropTheme(mode);
    if (_lastTheme == theme) return;
    _lastTheme = theme;

    try {
      await _channel.invokeMethod<void>('setBackdropTheme', theme);
    } catch (e) {
      _lastTheme = null;
      appLogger.warning('Failed to sync Windows backdrop theme: $e');
    }
  }

  @visibleForTesting
  String resolveBackdropTheme(
    ThemeMode mode, {
    Brightness? platformBrightness,
  }) {
    final effectiveBrightness = switch (mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system =>
        platformBrightness ??
            WidgetsBinding.instance.platformDispatcher.platformBrightness,
    };
    return effectiveBrightness == Brightness.dark ? 'dark' : 'light';
  }

  @visibleForTesting
  void resetForTesting() {
    _lastTheme = null;
  }
}
