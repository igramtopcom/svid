import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/services/window_geometry_service.dart';

void main() {
  group('WindowGeometryService.visibleRect', () {
    test('uses full display when visible work area is not provided', () {
      final rect = WindowGeometryService.visibleRect(
        displaySize: const Size(1920, 1080),
      );

      expect(rect, const Rect.fromLTWH(0, 0, 1920, 1080));
    });

    test('uses display work area origin and size when provided', () {
      final rect = WindowGeometryService.visibleRect(
        displaySize: const Size(1920, 1080),
        visiblePosition: const Offset(1920, 40),
        visibleSize: const Size(1920, 1000),
      );

      expect(rect, const Rect.fromLTWH(1920, 40, 1920, 1000));
    });
  });

  group('WindowGeometryService.chooseDisplayForWindow', () {
    const primary = Rect.fromLTWH(0, 0, 1920, 1040);
    const secondary = Rect.fromLTWH(1920, 0, 1920, 1040);

    test('chooses display containing the window center', () {
      final display = WindowGeometryService.chooseDisplayForWindow(
        windowBounds: const Rect.fromLTWH(2300, 120, 1200, 800),
        displayBounds: const [primary, secondary],
        fallback: primary,
      );

      expect(display, secondary);
    });

    test('handles negative-coordinate monitor layouts', () {
      const leftDisplay = Rect.fromLTWH(-1600, 0, 1600, 900);
      final display = WindowGeometryService.chooseDisplayForWindow(
        windowBounds: const Rect.fromLTWH(-1300, 120, 1000, 700),
        displayBounds: const [leftDisplay, primary],
        fallback: primary,
      );

      expect(display, leftDisplay);
    });
  });

  group('WindowGeometryService.bottomRightPosition', () {
    test('places PiP inside work area, not full display area', () {
      final position = WindowGeometryService.bottomRightPosition(
        visibleBounds: const Rect.fromLTWH(0, 0, 1920, 1040),
        windowSize: const Size(400, 240),
      );

      expect(position, const Offset(1500, 780));
    });

    test('includes non-zero display origin', () {
      final position = WindowGeometryService.bottomRightPosition(
        visibleBounds: const Rect.fromLTWH(1920, 40, 1920, 1000),
        windowSize: const Size(400, 240),
      );

      expect(position, const Offset(3420, 780));
    });
  });

  group('WindowGeometryService.clampPosition', () {
    test('keeps restored window fully reachable inside selected display', () {
      final position = WindowGeometryService.clampPosition(
        position: const Offset(3800, 100),
        windowSize: const Size(960, 600),
        visibleBounds: const Rect.fromLTWH(1920, 0, 1920, 1040),
      );

      expect(position.dx, 2860);
      expect(position.dy, 100);
    });
  });

  group('WindowGeometryService.avoidOverlaps', () {
    test('keeps preferred bottom-right position when it does not overlap', () {
      final position = WindowGeometryService.avoidOverlaps(
        preferredPosition: const Offset(1596, 596),
        windowSize: const Size(300, 420),
        visibleBounds: const Rect.fromLTWH(0, 0, 1920, 1040),
        avoidBounds: const [Rect.fromLTWH(40, 40, 400, 240)],
        margin: 24,
      );

      expect(position, const Offset(1596, 596));
    });

    test('stacks popup above bottom-right PiP with a stable gap', () {
      final position = WindowGeometryService.avoidOverlaps(
        preferredPosition: const Offset(1596, 596),
        windowSize: const Size(300, 420),
        visibleBounds: const Rect.fromLTWH(0, 0, 1920, 1040),
        avoidBounds: const [Rect.fromLTWH(1500, 780, 400, 240)],
        gap: 12,
        margin: 24,
      );

      expect(position, const Offset(1596, 348));
      expect(
        (position & const Size(300, 420)).overlaps(
          const Rect.fromLTWH(1500, 780, 400, 240),
        ),
        isFalse,
      );
    });

    test('falls back to the least-overlapping reachable candidate', () {
      final position = WindowGeometryService.avoidOverlaps(
        preferredPosition: const Offset(280, 180),
        windowSize: const Size(300, 420),
        visibleBounds: const Rect.fromLTWH(0, 0, 620, 620),
        avoidBounds: const [Rect.fromLTWH(220, 120, 380, 460)],
        gap: 12,
        margin: 20,
      );

      expect(position.dx, greaterThanOrEqualTo(20));
      expect(position.dy, greaterThanOrEqualTo(20));
      expect(position.dx + 300, lessThanOrEqualTo(600));
      expect(position.dy + 420, lessThanOrEqualTo(600));
    });
  });
}
