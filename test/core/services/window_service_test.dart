import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/services/window_service.dart';

void main() {
  group('WindowService.restoreWindowState', () {
    test('clamps size to minimum and screen bounds', () {
      final state = WindowService.restoreWindowState(
        screenWidth: 1200,
        screenHeight: 900,
        rawWidth: 400,
        rawHeight: 400,
        rawX: null,
        rawY: null,
        isMaximized: false,
      );

      // Default minimum bumped from 960×600 → 1024×720 (AppMinWidth.appWindow).
      expect(state.size, const Size(1024, 720));
      expect(state.position, isNull);
      expect(state.isMaximized, isFalse);
    });

    test('caps oversized window to 90 percent of screen', () {
      final state = WindowService.restoreWindowState(
        screenWidth: 1400,
        screenHeight: 1000,
        rawWidth: 3000,
        rawHeight: 3000,
        rawX: null,
        rawY: null,
        isMaximized: true,
      );

      expect(state.size, const Size(1260, 900));
      expect(state.isMaximized, isTrue);
    });

    test('preserves valid position on screen', () {
      final state = WindowService.restoreWindowState(
        screenWidth: 1920,
        screenHeight: 1080,
        rawWidth: 1200,
        rawHeight: 800,
        rawX: 100,
        rawY: 80,
        isMaximized: false,
      );

      expect(state.position, const Offset(100, 80));
    });

    test('drops off-screen position and recenters later', () {
      final state = WindowService.restoreWindowState(
        screenWidth: 1920,
        screenHeight: 1080,
        rawWidth: 1200,
        rawHeight: 800,
        rawX: 1900,
        rawY: 100,
        isMaximized: false,
      );

      expect(state.position, isNull);
    });
  });
}
