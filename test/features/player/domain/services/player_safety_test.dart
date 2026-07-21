import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/player/domain/services/player_safety.dart';

void main() {
  group('PlayerSafety', () {
    test('swallows disposed-player assertions', () {
      var reached = false;

      PlayerSafety.safeCall(() {
        throw AssertionError('[Player] has been disposed');
      });
      reached = true;

      expect(reached, isTrue);
    });

    test('rethrows unrelated errors', () {
      expect(
        () => PlayerSafety.safeCall(() => throw StateError('codec failed')),
        throwsA(isA<StateError>()),
      );
    });

    test('swallows async disposed-player assertions', () async {
      final uncaught = <Object>[];

      await (runZonedGuarded<Future<void>>(() async {
            PlayerSafety.safeCall(() async {
              throw AssertionError('[Player] has been disposed');
            });
            await Future<void>.delayed(Duration.zero);
          }, (error, stackTrace) => uncaught.add(error)) ??
          Future<void>.value());

      expect(uncaught, isEmpty);
    });

    test('surfaces unrelated async errors to the zone', () async {
      final uncaught = <Object>[];

      await (runZonedGuarded<Future<void>>(() async {
            PlayerSafety.safeCall(() async {
              throw StateError('codec failed');
            });
            await Future<void>.delayed(Duration.zero);
          }, (error, stackTrace) => uncaught.add(error)) ??
          Future<void>.value());

      expect(uncaught, hasLength(1));
      expect(uncaught.single, isA<StateError>());
    });
  });
}
