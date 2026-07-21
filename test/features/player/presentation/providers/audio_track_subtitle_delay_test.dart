// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:ssvid/features/player/presentation/providers/player_providers.dart';
import 'package:ssvid/features/player/presentation/widgets/subtitle_controls.dart';

void main() {
  group('subtitleDelayProvider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is 0', () {
      expect(container.read(subtitleDelayProvider), 0);
    });

    test('can be set to a positive value', () {
      container.read(subtitleDelayProvider.notifier).state = 500;
      expect(container.read(subtitleDelayProvider), 500);
    });

    test('can be set to a negative value', () {
      container.read(subtitleDelayProvider.notifier).state = -300;
      expect(container.read(subtitleDelayProvider), -300);
    });

    test('can be reset to 0', () {
      container.read(subtitleDelayProvider.notifier).state = 1000;
      container.read(subtitleDelayProvider.notifier).state = 0;
      expect(container.read(subtitleDelayProvider), 0);
    });

    test('clamp formula: positive step stays within +5000', () {
      const current = 4950;
      final result = (current + 100).clamp(-5000, 5000);
      expect(result, 5000);
    });

    test('clamp formula: negative step stays within -5000', () {
      const current = -4950;
      final result = (current - 100).clamp(-5000, 5000);
      expect(result, -5000);
    });
  });

  group('currentAudioTrackProvider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is AudioTrack.no()', () {
      final track = container.read(currentAudioTrackProvider);
      expect(track.id, 'no');
    });

    test('can be set to a different track', () {
      final track = AudioTrack('1', 'English', 'eng');
      container.read(currentAudioTrackProvider.notifier).state = track;
      expect(container.read(currentAudioTrackProvider).id, '1');
    });

    test('can be reset to no-track', () {
      final track = AudioTrack('1', 'English', 'eng');
      container.read(currentAudioTrackProvider.notifier).state = track;
      container.read(currentAudioTrackProvider.notifier).state =
          AudioTrack.no();
      expect(container.read(currentAudioTrackProvider).id, 'no');
    });
  });

  group('isoToLanguageName', () {
    test('returns English for eng', () {
      expect(isoToLanguageName('eng'), 'English');
    });

    test('is case-insensitive (ENG → English)', () {
      expect(isoToLanguageName('ENG'), 'English');
    });

    test('returns Japanese for jpn', () {
      expect(isoToLanguageName('jpn'), 'Japanese');
    });

    test('returns Vietnamese for vie', () {
      expect(isoToLanguageName('vie'), 'Vietnamese');
    });

    test('returns Undetermined for und', () {
      expect(isoToLanguageName('und'), 'Undetermined');
    });

    test('returns original code for unknown code', () {
      expect(isoToLanguageName('xyz'), 'xyz');
    });
  });
}
