import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/player/domain/services/player_speed_service.dart';

void main() {
  group('PlayerSpeedService', () {
    group('presets', () {
      test('contains five standard presets', () {
        expect(PlayerSpeedService.presets, hasLength(5));
      });

      test('presets include 0.5, 1.0, 1.25, 1.5, 2.0', () {
        expect(
          PlayerSpeedService.presets,
          containsAll([0.5, 1.0, 1.25, 1.5, 2.0]),
        );
      });

      test('presets are in ascending order', () {
        final sorted = [...PlayerSpeedService.presets]..sort();
        expect(PlayerSpeedService.presets, sorted);
      });
    });

    group('formatLabel', () {
      test('integer speed shows no decimal — 1.0 → "1x"', () {
        expect(PlayerSpeedService.formatLabel(1.0), '1x');
      });

      test('integer speed 2.0 → "2x"', () {
        expect(PlayerSpeedService.formatLabel(2.0), '2x');
      });

      test('non-integer preserves significant decimals — 1.25 → "1.25x"', () {
        expect(PlayerSpeedService.formatLabel(1.25), '1.25x');
      });

      test('0.5 → "0.5x"', () {
        expect(PlayerSpeedService.formatLabel(0.5), '0.5x');
      });

      test('1.5 → "1.5x"', () {
        expect(PlayerSpeedService.formatLabel(1.5), '1.5x');
      });
    });

    group('clamp', () {
      test('value below min is clamped to minSpeed', () {
        expect(PlayerSpeedService.clamp(0.1), PlayerSpeedService.minSpeed);
      });

      test('value above max is clamped to maxSpeed', () {
        expect(PlayerSpeedService.clamp(10.0), PlayerSpeedService.maxSpeed);
      });

      test('value within range is unchanged', () {
        expect(PlayerSpeedService.clamp(1.5), 1.5);
      });
    });

    group('increase / decrease', () {
      test('increase adds 0.25', () {
        expect(PlayerSpeedService.increase(1.0), closeTo(1.25, 0.001));
      });

      test('decrease subtracts 0.25', () {
        expect(PlayerSpeedService.decrease(1.0), closeTo(0.75, 0.001));
      });

      test('increase at max does not exceed maxSpeed', () {
        expect(
          PlayerSpeedService.increase(PlayerSpeedService.maxSpeed),
          PlayerSpeedService.maxSpeed,
        );
      });

      test('decrease at min does not go below minSpeed', () {
        expect(
          PlayerSpeedService.decrease(PlayerSpeedService.minSpeed),
          PlayerSpeedService.minSpeed,
        );
      });
    });
  });
}
