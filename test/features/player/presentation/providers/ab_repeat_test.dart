import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/player/presentation/providers/player_providers.dart';

void main() {
  group('A-B Repeat Providers', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    group('abRepeatPointAProvider', () {
      test('initial state is null', () {
        expect(container.read(abRepeatPointAProvider), isNull);
      });

      test('can set point A', () {
        container.read(abRepeatPointAProvider.notifier).state =
            const Duration(seconds: 10);
        expect(
          container.read(abRepeatPointAProvider),
          const Duration(seconds: 10),
        );
      });

      test('can clear point A', () {
        container.read(abRepeatPointAProvider.notifier).state =
            const Duration(seconds: 10);
        container.read(abRepeatPointAProvider.notifier).state = null;
        expect(container.read(abRepeatPointAProvider), isNull);
      });
    });

    group('abRepeatPointBProvider', () {
      test('initial state is null', () {
        expect(container.read(abRepeatPointBProvider), isNull);
      });

      test('can set point B', () {
        container.read(abRepeatPointBProvider.notifier).state =
            const Duration(seconds: 30);
        expect(
          container.read(abRepeatPointBProvider),
          const Duration(seconds: 30),
        );
      });

      test('can clear point B', () {
        container.read(abRepeatPointBProvider.notifier).state =
            const Duration(seconds: 30);
        container.read(abRepeatPointBProvider.notifier).state = null;
        expect(container.read(abRepeatPointBProvider), isNull);
      });
    });

    group('isAbRepeatActiveProvider', () {
      test('returns false when no points are set', () {
        expect(container.read(isAbRepeatActiveProvider), isFalse);
      });

      test('returns false when only point A is set', () {
        container.read(abRepeatPointAProvider.notifier).state =
            const Duration(seconds: 10);
        expect(container.read(isAbRepeatActiveProvider), isFalse);
      });

      test('returns false when only point B is set', () {
        container.read(abRepeatPointBProvider.notifier).state =
            const Duration(seconds: 30);
        expect(container.read(isAbRepeatActiveProvider), isFalse);
      });

      test('returns true when both points are set', () {
        container.read(abRepeatPointAProvider.notifier).state =
            const Duration(seconds: 10);
        container.read(abRepeatPointBProvider.notifier).state =
            const Duration(seconds: 30);
        expect(container.read(isAbRepeatActiveProvider), isTrue);
      });

      test('returns false after clearing both points', () {
        container.read(abRepeatPointAProvider.notifier).state =
            const Duration(seconds: 10);
        container.read(abRepeatPointBProvider.notifier).state =
            const Duration(seconds: 30);
        expect(container.read(isAbRepeatActiveProvider), isTrue);

        container.read(abRepeatPointAProvider.notifier).state = null;
        container.read(abRepeatPointBProvider.notifier).state = null;
        expect(container.read(isAbRepeatActiveProvider), isFalse);
      });

      test('returns false after clearing only point A', () {
        container.read(abRepeatPointAProvider.notifier).state =
            const Duration(seconds: 10);
        container.read(abRepeatPointBProvider.notifier).state =
            const Duration(seconds: 30);
        expect(container.read(isAbRepeatActiveProvider), isTrue);

        container.read(abRepeatPointAProvider.notifier).state = null;
        expect(container.read(isAbRepeatActiveProvider), isFalse);
      });

      test('returns false after clearing only point B', () {
        container.read(abRepeatPointAProvider.notifier).state =
            const Duration(seconds: 10);
        container.read(abRepeatPointBProvider.notifier).state =
            const Duration(seconds: 30);
        expect(container.read(isAbRepeatActiveProvider), isTrue);

        container.read(abRepeatPointBProvider.notifier).state = null;
        expect(container.read(isAbRepeatActiveProvider), isFalse);
      });
    });

    group('A-B Repeat toggle cycle', () {
      test('toggle cycle: null → A → A+B → null', () {
        // Initially no points
        expect(container.read(abRepeatPointAProvider), isNull);
        expect(container.read(abRepeatPointBProvider), isNull);
        expect(container.read(isAbRepeatActiveProvider), isFalse);

        // Set point A
        container.read(abRepeatPointAProvider.notifier).state =
            const Duration(seconds: 5);
        expect(container.read(abRepeatPointAProvider), isNotNull);
        expect(container.read(abRepeatPointBProvider), isNull);
        expect(container.read(isAbRepeatActiveProvider), isFalse);

        // Set point B
        container.read(abRepeatPointBProvider.notifier).state =
            const Duration(seconds: 20);
        expect(container.read(abRepeatPointAProvider), isNotNull);
        expect(container.read(abRepeatPointBProvider), isNotNull);
        expect(container.read(isAbRepeatActiveProvider), isTrue);

        // Clear both
        container.read(abRepeatPointAProvider.notifier).state = null;
        container.read(abRepeatPointBProvider.notifier).state = null;
        expect(container.read(abRepeatPointAProvider), isNull);
        expect(container.read(abRepeatPointBProvider), isNull);
        expect(container.read(isAbRepeatActiveProvider), isFalse);
      });

      test('point A at zero duration', () {
        container.read(abRepeatPointAProvider.notifier).state = Duration.zero;
        container.read(abRepeatPointBProvider.notifier).state =
            const Duration(seconds: 10);
        expect(container.read(isAbRepeatActiveProvider), isTrue);
        expect(container.read(abRepeatPointAProvider), Duration.zero);
      });

      test('point B at large duration', () {
        container.read(abRepeatPointAProvider.notifier).state =
            const Duration(seconds: 10);
        container.read(abRepeatPointBProvider.notifier).state =
            const Duration(hours: 2, minutes: 30);
        expect(container.read(isAbRepeatActiveProvider), isTrue);
        expect(
          container.read(abRepeatPointBProvider),
          const Duration(hours: 2, minutes: 30),
        );
      });

      test('updating point A preserves point B', () {
        container.read(abRepeatPointAProvider.notifier).state =
            const Duration(seconds: 10);
        container.read(abRepeatPointBProvider.notifier).state =
            const Duration(seconds: 30);

        // Update A to new value
        container.read(abRepeatPointAProvider.notifier).state =
            const Duration(seconds: 15);
        expect(
          container.read(abRepeatPointAProvider),
          const Duration(seconds: 15),
        );
        expect(
          container.read(abRepeatPointBProvider),
          const Duration(seconds: 30),
        );
        expect(container.read(isAbRepeatActiveProvider), isTrue);
      });

      test('isAbRepeatActive becomes true when both set, false when cleared', () {
        // Initially false
        expect(container.read(isAbRepeatActiveProvider), isFalse);

        // Set A → still false
        container.read(abRepeatPointAProvider.notifier).state =
            const Duration(seconds: 5);
        expect(container.read(isAbRepeatActiveProvider), isFalse);

        // Set B → now true
        container.read(abRepeatPointBProvider.notifier).state =
            const Duration(seconds: 15);
        expect(container.read(isAbRepeatActiveProvider), isTrue);

        // Clear A → false again
        container.read(abRepeatPointAProvider.notifier).state = null;
        expect(container.read(isAbRepeatActiveProvider), isFalse);
      });
    });
  });
}
