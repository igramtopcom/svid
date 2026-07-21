import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssvid/core/errors/result.dart';
import 'package:ssvid/features/player/domain/services/watch_progress_service.dart';
import '../../../../shared/mocks/mocks.dart';

void main() {
  late WatchProgressService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    service = WatchProgressService(prefs);
  });

  group('WatchProgressService', () {
    test('getProgress returns null when no progress saved', () {
      expect(service.getProgress(1), isNull);
    });

    test('savePosition stores progress correctly', () {
      service.savePosition(
        1,
        const Duration(minutes: 5),
        const Duration(minutes: 10),
      );

      final progress = service.getProgress(1);
      expect(progress, isNotNull);
      expect(progress!.positionMs, 5 * 60 * 1000);
      expect(progress.durationMs, 10 * 60 * 1000);
      expect(progress.fraction, closeTo(0.5, 0.01));
    });

    test('savePosition does not save if position < 5% of duration', () {
      service.savePosition(
        1,
        const Duration(seconds: 2),
        const Duration(minutes: 10),
      );

      expect(service.getProgress(1), isNull);
    });

    test('saveResumePoint stores progress below 5% for player continuity', () {
      service.saveResumePoint(
        1,
        const Duration(seconds: 2),
        const Duration(minutes: 10),
      );

      final progress = service.getProgress(1);
      expect(progress, isNotNull);
      expect(progress!.position, const Duration(seconds: 2));
    });

    test('saveResumePoint ignores near-zero positions', () {
      service.saveResumePoint(
        1,
        const Duration(milliseconds: 400),
        const Duration(minutes: 10),
      );

      expect(service.getProgress(1), isNull);
    });

    test('savePosition clears progress if position >= 90% of duration', () {
      // First save at 50%
      service.savePosition(
        1,
        const Duration(minutes: 5),
        const Duration(minutes: 10),
      );
      expect(service.getProgress(1), isNotNull);

      // Now save at 95% — should auto-clear
      service.savePosition(
        1,
        const Duration(minutes: 9, seconds: 30),
        const Duration(minutes: 10),
      );
      expect(service.getProgress(1), isNull);
    });

    test('savePosition does nothing when duration is zero', () {
      service.savePosition(1, const Duration(seconds: 30), Duration.zero);
      expect(service.getProgress(1), isNull);
    });

    test('clearProgress removes saved data', () {
      service.savePosition(
        1,
        const Duration(minutes: 5),
        const Duration(minutes: 10),
      );
      expect(service.getProgress(1), isNotNull);

      service.clearProgress(1);
      expect(service.getProgress(1), isNull);
    });

    test('getWatchFraction returns correct fraction', () {
      service.savePosition(
        1,
        const Duration(minutes: 3),
        const Duration(minutes: 10),
      );

      final fraction = service.getWatchFraction(1);
      expect(fraction, isNotNull);
      expect(fraction, closeTo(0.3, 0.01));
    });

    test('getWatchFraction returns null when no progress', () {
      expect(service.getWatchFraction(99), isNull);
    });

    test('tracks multiple downloads independently', () {
      service.savePosition(
        1,
        const Duration(minutes: 2),
        const Duration(minutes: 10),
      );
      service.savePosition(
        2,
        const Duration(minutes: 7),
        const Duration(minutes: 10),
      );

      expect(service.getWatchFraction(1), closeTo(0.2, 0.01));
      expect(service.getWatchFraction(2), closeTo(0.7, 0.01));
    });

    test('savePosition overwrites previous progress', () {
      service.savePosition(
        1,
        const Duration(minutes: 2),
        const Duration(minutes: 10),
      );
      expect(service.getWatchFraction(1), closeTo(0.2, 0.01));

      service.savePosition(
        1,
        const Duration(minutes: 6),
        const Duration(minutes: 10),
      );
      expect(service.getWatchFraction(1), closeTo(0.6, 0.01));
    });

    test('handles corrupt stored data gracefully', () async {
      SharedPreferences.setMockInitialValues({
        'watch_progress_1': 'not-valid-json',
      });
      final prefs = await SharedPreferences.getInstance();
      final svc = WatchProgressService(prefs);

      // Should return null and clean up corrupt data
      expect(svc.getProgress(1), isNull);
    });

    test('savePosition at exactly 5% threshold saves correctly', () {
      // 5% of 100s = 5s
      service.savePosition(
        1,
        const Duration(seconds: 5),
        const Duration(seconds: 100),
      );
      expect(service.getProgress(1), isNotNull);
    });

    test('savePosition at exactly 90% threshold clears', () {
      // First save valid position
      service.savePosition(
        1,
        const Duration(seconds: 50),
        const Duration(seconds: 100),
      );
      expect(service.getProgress(1), isNotNull);

      // Now save at exactly 90%
      service.savePosition(
        1,
        const Duration(seconds: 90),
        const Duration(seconds: 100),
      );
      expect(service.getProgress(1), isNull);
    });
  });

  group('WatchProgress', () {
    test('formattedPosition formats minutes correctly', () {
      final progress = WatchProgress(
        positionMs: 5 * 60 * 1000 + 30 * 1000, // 5:30
        durationMs: 10 * 60 * 1000,
        updatedAt: DateTime(2026),
      );
      expect(progress.formattedPosition, '5:30');
    });

    test('formattedPosition formats hours correctly', () {
      final progress = WatchProgress(
        positionMs: 1 * 3600 * 1000 + 23 * 60 * 1000 + 5 * 1000, // 1:23:05
        durationMs: 2 * 3600 * 1000,
        updatedAt: DateTime(2026),
      );
      expect(progress.formattedPosition, '1:23:05');
    });

    test('formattedPosition handles zero seconds padding', () {
      final progress = WatchProgress(
        positionMs: 2 * 60 * 1000, // 2:00
        durationMs: 10 * 60 * 1000,
        updatedAt: DateTime(2026),
      );
      expect(progress.formattedPosition, '2:00');
    });

    test('fraction clamps to 0-1 range', () {
      final progress = WatchProgress(
        positionMs: 0,
        durationMs: 100000,
        updatedAt: DateTime(2026),
      );
      expect(progress.fraction, 0.0);
    });

    test('fraction returns 0 when duration is 0', () {
      final progress = WatchProgress(
        positionMs: 5000,
        durationMs: 0,
        updatedAt: DateTime(2026),
      );
      expect(progress.fraction, 0.0);
    });

    test('position getter returns correct Duration', () {
      final progress = WatchProgress(
        positionMs: 65000,
        durationMs: 100000,
        updatedAt: DateTime(2026),
      );
      expect(progress.position, const Duration(milliseconds: 65000));
    });

    test('duration getter returns correct Duration', () {
      final progress = WatchProgress(
        positionMs: 65000,
        durationMs: 100000,
        updatedAt: DateTime(2026),
      );
      expect(progress.duration, const Duration(milliseconds: 100000));
    });
  });

  group('Watch status — short video threshold', () {
    test('short video (<30s) uses 80% threshold instead of 90%', () {
      // 25s video, position at 85% (21.25s) — should clear (short video threshold)
      service.savePosition(
        1,
        const Duration(milliseconds: 21250),
        const Duration(seconds: 25),
      );
      // 85% >= 80% short-video threshold → progress cleared
      expect(service.getProgress(1), isNull);
    });

    test('short video at 79% does NOT auto-clear', () {
      service.savePosition(
        1,
        const Duration(milliseconds: 19750), // 79%
        const Duration(seconds: 25),
      );
      expect(service.getProgress(1), isNotNull);
    });

    test('standard video (>=30s) at 85% does NOT auto-clear', () {
      // 60s video at 85% — below 90% threshold
      service.savePosition(
        1,
        const Duration(seconds: 51), // 85%
        const Duration(seconds: 60),
      );
      expect(service.getProgress(1), isNotNull);
    });

    test('standard video at exactly 30s uses 90% threshold', () {
      // 30s video at 85% — exactly at cutoff, standard threshold applies
      service.savePosition(
        1,
        const Duration(milliseconds: 25500), // 85%
        const Duration(seconds: 30),
      );
      expect(service.getProgress(1), isNotNull);
    });
  });

  group('Watch status — repository integration', () {
    late MockDownloadRepository mockRepo;
    late WatchProgressService svcWithRepo;

    setUp(() async {
      mockRepo = MockDownloadRepository();
      when(
        () =>
            mockRepo.updateIsWatched(any(), isWatched: any(named: 'isWatched')),
      ).thenAnswer((_) async => const Success(null));
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      svcWithRepo = WatchProgressService(prefs, repository: mockRepo);
    });

    test('savePosition at >=90% calls markAsWatched on repository', () {
      svcWithRepo.savePosition(
        42,
        const Duration(seconds: 91),
        const Duration(seconds: 100),
      );
      verify(() => mockRepo.updateIsWatched(42, isWatched: true)).called(1);
    });

    test(
      'markAsWatched calls repository.updateIsWatched with isWatched=true',
      () {
        svcWithRepo.markAsWatched(7);
        verify(() => mockRepo.updateIsWatched(7, isWatched: true)).called(1);
      },
    );

    test(
      'markAsUnwatched calls repository.updateIsWatched with isWatched=false',
      () {
        svcWithRepo.markAsUnwatched(7);
        verify(() => mockRepo.updateIsWatched(7, isWatched: false)).called(1);
      },
    );

    test('markAsUnwatched suppresses auto-mark on subsequent savePosition', () {
      svcWithRepo.markAsUnwatched(42);
      // Reaching threshold should NOT re-mark watched
      svcWithRepo.savePosition(
        42,
        const Duration(seconds: 95),
        const Duration(seconds: 100),
      );
      // updateIsWatched(42, true) must never have been called
      verifyNever(() => mockRepo.updateIsWatched(42, isWatched: true));
    });

    test('markAsUnwatched only suppresses the specific ID, not others', () {
      svcWithRepo.markAsUnwatched(42);
      svcWithRepo.savePosition(
        99,
        const Duration(seconds: 95),
        const Duration(seconds: 100),
      );
      // ID 99 is NOT in manuallyUnwatched → should be marked watched
      verify(() => mockRepo.updateIsWatched(99, isWatched: true)).called(1);
    });

    test('onPlaybackEnd calls markAsWatched on repository', () {
      svcWithRepo.onPlaybackEnd(55);
      verify(() => mockRepo.updateIsWatched(55, isWatched: true)).called(1);
    });

    test('onPlaybackEnd is suppressed when manually unwatched', () {
      svcWithRepo.markAsUnwatched(55);
      svcWithRepo.onPlaybackEnd(55);
      // markAsUnwatched called updateIsWatched(false), but onPlaybackEnd should NOT call (true)
      verifyNever(() => mockRepo.updateIsWatched(55, isWatched: true));
    });

    test('no repository = no crash on markAsWatched', () {
      // service without repo — should not throw
      expect(() => service.markAsWatched(1), returnsNormally);
    });

    test('no repository = no crash on markAsUnwatched', () {
      expect(() => service.markAsUnwatched(1), returnsNormally);
    });
  });

  group('pruneOldEntries', () {
    test('prunes entries older than 30 days', () async {
      // Create entry with old timestamp
      final oldTime = DateTime.now().subtract(const Duration(days: 31));
      SharedPreferences.setMockInitialValues({
        'watch_progress_1':
            '{"positionMs":5000,"durationMs":10000,"updatedAt":${oldTime.millisecondsSinceEpoch}}',
      });
      final prefs = await SharedPreferences.getInstance();
      final svc = WatchProgressService(prefs);

      final pruned = svc.pruneOldEntries();
      expect(pruned, 1);
      expect(svc.getProgress(1), isNull);
    });

    test('keeps entries newer than 30 days', () async {
      final recentTime = DateTime.now().subtract(const Duration(days: 5));
      SharedPreferences.setMockInitialValues({
        'watch_progress_1':
            '{"positionMs":5000,"durationMs":10000,"updatedAt":${recentTime.millisecondsSinceEpoch}}',
      });
      final prefs = await SharedPreferences.getInstance();
      final svc = WatchProgressService(prefs);

      final pruned = svc.pruneOldEntries();
      expect(pruned, 0);
      expect(svc.getProgress(1), isNotNull);
    });

    test('prunes corrupt entries', () async {
      SharedPreferences.setMockInitialValues({
        'watch_progress_1': 'corrupt-data',
      });
      final prefs = await SharedPreferences.getInstance();
      final svc = WatchProgressService(prefs);

      final pruned = svc.pruneOldEntries();
      expect(pruned, 1);
    });

    test('returns 0 when no entries exist', () {
      expect(service.pruneOldEntries(), 0);
    });
  });
}
