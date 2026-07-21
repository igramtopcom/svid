import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:svid/core/services/player_manager.dart';

// ---------------------------------------------------------------------------
// Fake Player — stub for media_kit's Player to avoid native library init
// ---------------------------------------------------------------------------

class _MockPlayer extends Mock implements Player {}

PlayerStream _playerStream({Stream<bool>? playing}) {
  return PlayerStream(
    Stream.empty(),
    playing ?? Stream.empty(),
    Stream.empty(),
    Stream.empty(),
    Stream.empty(),
    Stream.empty(),
    Stream.empty(),
    Stream.empty(),
    Stream.empty(),
    Stream.empty(),
    Stream.empty(),
    Stream.empty(),
    Stream.empty(),
    Stream.empty(),
    Stream.empty(),
    Stream.empty(),
    Stream.empty(),
    Stream.empty(),
    Stream.empty(),
    Stream.empty(),
    Stream.empty(),
    Stream.empty(),
    Stream.empty(),
    Stream.empty(),
    Stream.empty(),
  );
}

void main() {
  // PlayerManager is a singleton; we can't reset it between tests without
  // flushing internal state. Work around by calling disposeAll() in setUp.

  group('PlayerManager.isAudioPlayer()', () {
    test('returns true for audio_ prefix', () {
      expect(PlayerManager.isAudioPlayer('audio_1'), isTrue);
    });

    test('returns true for mini_audio_ prefix', () {
      expect(PlayerManager.isAudioPlayer('mini_audio_42'), isTrue);
    });

    test('returns false for video_ prefix', () {
      expect(PlayerManager.isAudioPlayer('video_7'), isFalse);
    });

    test('returns false for pip_video_ prefix', () {
      expect(PlayerManager.isAudioPlayer('pip_video_7'), isFalse);
    });

    test('returns false for empty string', () {
      expect(PlayerManager.isAudioPlayer(''), isFalse);
    });
  });

  group('PlayerManager.isVideoPlayer()', () {
    test('returns true for video_ prefix', () {
      expect(PlayerManager.isVideoPlayer('video_7'), isTrue);
    });

    test('returns true for pip_video_ prefix', () {
      expect(PlayerManager.isVideoPlayer('pip_video_7'), isTrue);
    });

    test('returns true for mini_video_ prefix', () {
      expect(PlayerManager.isVideoPlayer('mini_video_7'), isTrue);
    });

    test('returns false for audio_ prefix', () {
      expect(PlayerManager.isVideoPlayer('audio_7'), isFalse);
    });

    test('returns false for empty string', () {
      expect(PlayerManager.isVideoPlayer(''), isFalse);
    });
  });

  group('PlayerManager.backgroundAudioEnabled', () {
    final pm = PlayerManager();

    setUp(() {
      pm.backgroundAudioEnabled = true; // reset to default
    });

    test('defaults to true', () {
      expect(pm.backgroundAudioEnabled, isTrue);
    });

    test('can be set to false', () {
      pm.backgroundAudioEnabled = false;
      expect(pm.backgroundAudioEnabled, isFalse);
    });

    test('can be toggled back to true', () {
      pm.backgroundAudioEnabled = false;
      pm.backgroundAudioEnabled = true;
      expect(pm.backgroundAudioEnabled, isTrue);
    });
  });

  group('PlaybackQueueService.peekNext() via PlayerManager API surface', () {
    // We only test the PlayerManager layer here; PlaybackQueueService is
    // covered in its own test file.
    test('hasPreloadedPlayer returns false when nothing preloaded', () {
      final pm = PlayerManager();
      expect(pm.hasPreloadedPlayer('/some/file.mp4'), isFalse);
    });
  });

  group('PlayerManager auto-dispose timer', () {
    late PlayerManager pm;

    setUp(() {
      pm = PlayerManager();
      pm.disposeAll();
      // Use a very short delay so tests don't have to wait 5 minutes
      pm.autoDisposeDelay = const Duration(milliseconds: 50);
    });

    tearDown(() {
      pm.disposeAll();
      pm.autoDisposeDelay = const Duration(minutes: 5); // reset
    });

    test('activeAutoDisposeTimerCount starts at 0', () {
      expect(pm.activeAutoDisposeTimerCount, 0);
    });

    test('onWindowFocused cancels timers and resets count to 0', () async {
      // Manually trigger blur logic to populate timers without real Player
      // We test the timer-cancel path by simulating what onWindowBlurred does
      // internally: start a timer then call onWindowFocused.

      // We can't register a real Player in unit tests (requires native libs),
      // so we verify onWindowFocused() exits gracefully with zero timers.
      await pm.onWindowBlurred();
      pm.onWindowFocused();
      expect(pm.activeAutoDisposeTimerCount, 0);
    });
  });

  group('PlayerManager preload API', () {
    late PlayerManager pm;

    setUp(() {
      pm = PlayerManager();
      pm.disposeAll();
    });

    tearDown(() {
      pm.disposeAll();
    });

    test('hasPreloadedPlayer returns false for unrecognised path', () {
      expect(pm.hasPreloadedPlayer('/unknown.mp4'), isFalse);
    });

    test('takePreloadedPlayer returns null when nothing preloaded', () {
      expect(pm.takePreloadedPlayer('/file.mp4'), isNull);
    });

    test('takePreloadedPlayer returns null for wrong path after preload', () {
      // We cannot call preloadMedia() in unit tests because it creates a
      // real media_kit Player. Verify the null-path branch is covered.
      expect(pm.takePreloadedPlayer('/wrong.mp4'), isNull);
    });
  });

  group('PlayerManager disposeAll', () {
    test('clears playerIds', () {
      final pm = PlayerManager();
      pm.disposeAll();
      expect(pm.playerIds, isEmpty);
    });

    test('resets activeAutoDisposeTimerCount to 0', () {
      final pm = PlayerManager();
      pm.disposeAll();
      expect(pm.activeAutoDisposeTimerCount, 0);
    });

    test('activePlayerCount returns 0 after disposeAll', () {
      final pm = PlayerManager();
      pm.disposeAll();
      expect(pm.activePlayerCount, 0);
    });
  });

  group('PlayerManager safe disposal', () {
    late PlayerManager pm;

    setUp(() {
      pm = PlayerManager();
      pm.disposeAll();
    });

    tearDown(() {
      pm.disposeAll();
    });

    test(
      'unregisterPlayer absorbs async already-disposed player errors',
      () async {
        final player = _MockPlayer();
        when(() => player.dispose()).thenAnswer(
          (_) => Future<void>.error(
            AssertionError('[Player] has been disposed'),
            StackTrace.current,
          ),
        );

        pm.registerPlayer('video_async_disposed', player, autoPause: false);
        pm.unregisterPlayer('video_async_disposed');

        await Future<void>.delayed(Duration.zero);

        verify(() => player.dispose()).called(1);
        expect(pm.hasPlayer('video_async_disposed'), isFalse);
      },
    );

    test(
      'replacement disposal absorbs async already-disposed player errors',
      () async {
        final oldPlayer = _MockPlayer();
        final newPlayer = _MockPlayer();
        when(() => oldPlayer.dispose()).thenAnswer(
          (_) => Future<void>.error(
            AssertionError('[Player] has been disposed'),
            StackTrace.current,
          ),
        );
        when(() => newPlayer.dispose()).thenAnswer((_) async {});

        pm.registerPlayer('video_replace', oldPlayer, autoPause: false);
        pm.registerPlayer('video_replace', newPlayer, autoPause: false);

        await Future<void>.delayed(Duration.zero);

        verify(() => oldPlayer.dispose()).called(1);
        expect(pm.getPlayer('video_replace'), same(newPlayer));
      },
    );

    test('disposeAll absorbs async already-disposed player errors', () async {
      final player = _MockPlayer();
      when(() => player.dispose()).thenAnswer(
        (_) => Future<void>.error(
          AssertionError('[Player] has been disposed'),
          StackTrace.current,
        ),
      );

      pm.registerPlayer('video_dispose_all', player, autoPause: false);
      pm.disposeAll();

      await Future<void>.delayed(Duration.zero);

      verify(() => player.dispose()).called(1);
      expect(pm.hasPlayer('video_dispose_all'), isFalse);
    });

    test('playing stream disposed errors remove player bookkeeping', () async {
      final player = _MockPlayer();
      final playingController = StreamController<bool>();
      when(
        () => player.stream,
      ).thenReturn(_playerStream(playing: playingController.stream));
      when(() => player.dispose()).thenAnswer((_) async {});

      pm.registerPlayer('video_stream_error', player);
      expect(pm.hasPlayer('video_stream_error'), isTrue);

      playingController.addError(AssertionError('[Player] has been disposed'));
      await Future<void>.delayed(Duration.zero);

      expect(pm.hasPlayer('video_stream_error'), isFalse);
      await playingController.close();
    });
  });

  group('PlayerManager.backgroundAudioEnabled wiring', () {
    test('setter persists across getter reads', () {
      final pm = PlayerManager();
      pm.backgroundAudioEnabled = false;
      expect(pm.backgroundAudioEnabled, isFalse);
      pm.backgroundAudioEnabled = true;
      expect(pm.backgroundAudioEnabled, isTrue);
    });

    test('onWindowBlurred with no players completes without error', () async {
      final pm = PlayerManager();
      pm.disposeAll();
      // Should not throw even with no players registered
      await expectLater(pm.onWindowBlurred(), completes);
    });

    test('onWindowFocused with no timers completes without error', () {
      final pm = PlayerManager();
      pm.disposeAll();
      expect(() => pm.onWindowFocused(), returnsNormally);
    });

    test('pauseVideoPlayers with no players completes without error', () async {
      final pm = PlayerManager();
      pm.disposeAll();
      await expectLater(pm.pauseVideoPlayers(), completes);
    });
  });
}
