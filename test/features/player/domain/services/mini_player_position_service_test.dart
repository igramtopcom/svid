import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssvid/features/player/domain/services/mini_player_position_service.dart';

void main() {
  late MiniPlayerPositionService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    service = MiniPlayerPositionService(prefs);
  });

  // ---------------------------------------------------------------------------
  // savePosition / loadPosition
  // ---------------------------------------------------------------------------

  group('savePosition + loadPosition', () {
    test('loadPosition returns null when nothing stored', () {
      expect(service.loadPosition(), isNull);
    });

    test('savePosition stores and loadPosition retrieves the same offset', () async {
      await service.savePosition(const Offset(80.0, 120.0));
      final loaded = service.loadPosition();
      expect(loaded, const Offset(80.0, 120.0));
    });

    test('savePosition overwrites previous value', () async {
      await service.savePosition(const Offset(30.0, 40.0));
      await service.savePosition(const Offset(99.0, 55.0));
      final loaded = service.loadPosition();
      expect(loaded, const Offset(99.0, 55.0));
    });

    test('loadPosition returns fractional offsets correctly', () async {
      await service.savePosition(const Offset(25.5, 37.75));
      final loaded = service.loadPosition();
      expect(loaded!.dx, closeTo(25.5, 0.001));
      expect(loaded.dy, closeTo(37.75, 0.001));
    });
  });

  // ---------------------------------------------------------------------------
  // clampPosition
  // ---------------------------------------------------------------------------

  group('clampPosition', () {
    const windowSize = Size(1440, 900);
    const pipWidth = 400.0;
    const pipHeight = 240.0;

    test('position within bounds is returned unchanged', () {
      const input = Offset(100, 150);
      final clamped = service.clampPosition(input, windowSize);
      expect(clamped, input);
    });

    test('clamps dx to minimum margin (20) when too small', () {
      const input = Offset(5, 100);
      final clamped = service.clampPosition(input, windowSize);
      expect(clamped.dx, 20.0);
      expect(clamped.dy, 100.0);
    });

    test('clamps dy to minimum margin (20) when too small', () {
      const input = Offset(100, 3);
      final clamped = service.clampPosition(input, windowSize);
      expect(clamped.dx, 100.0);
      expect(clamped.dy, 20.0);
    });

    test('clamps dx to max when too large (window right edge)', () {
      // maxDx = 1440 - 400 - 20 = 1020
      const input = Offset(2000, 100);
      final clamped = service.clampPosition(input, windowSize);
      expect(clamped.dx, 1440 - pipWidth - 20);
    });

    test('clamps dy to max when too large (window bottom edge)', () {
      // maxDy = 900 - 240 - 20 = 640
      const input = Offset(100, 900);
      final clamped = service.clampPosition(input, windowSize);
      expect(clamped.dy, 900 - pipHeight - 20);
    });

    test('clamps both axes simultaneously', () {
      const input = Offset(-50, 9999);
      final clamped = service.clampPosition(input, windowSize);
      expect(clamped.dx, 20.0);
      expect(clamped.dy, 900 - pipHeight - 20);
    });

    test('respects custom width and height parameters', () {
      // maxDx = 1440 - 300 - 20 = 1120
      const input = Offset(5000, 5000);
      final clamped = service.clampPosition(input, windowSize, width: 300, height: 200);
      expect(clamped.dx, 1440 - 300 - 20);
      expect(clamped.dy, 900 - 200 - 20);
    });
  });
}
