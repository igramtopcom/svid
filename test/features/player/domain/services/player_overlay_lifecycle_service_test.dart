import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/player/domain/services/player_overlay_lifecycle_service.dart';

void main() {
  group('PlayerOverlayLifecycleService', () {
    const service = PlayerOverlayLifecycleService();

    test('closeAudioOverlay clears state before unregistering', () async {
      final calls = <String>[];

      await service.closeAudioOverlay(
        downloadId: '42',
        clearState: () => calls.add('clear'),
        waitForOverlayUnmount: () async => calls.add('wait'),
        unregisterPlayer: (playerId) => calls.add('unregister:$playerId'),
      );

      expect(
        calls,
        ['clear', 'wait', 'unregister:mini_audio_42'],
      );
    });

    test('closeVideoOverlay exits system PiP before unregistering', () async {
      final calls = <String>[];

      await service.closeVideoOverlay(
        downloadId: '7',
        systemPipActive: true,
        clearState: () => calls.add('clear'),
        waitForOverlayUnmount: () async => calls.add('wait'),
        exitSystemPip: () async => calls.add('exit'),
        unregisterPlayer: (playerId) => calls.add('unregister:$playerId'),
      );

      expect(
        calls,
        ['clear', 'wait', 'exit', 'unregister:pip_video_7'],
      );
    });

    test('closeVideoOverlay skips system PiP exit when inactive', () async {
      final calls = <String>[];

      await service.closeVideoOverlay(
        downloadId: '9',
        systemPipActive: false,
        clearState: () => calls.add('clear'),
        waitForOverlayUnmount: () async => calls.add('wait'),
        exitSystemPip: () async => calls.add('exit'),
        unregisterPlayer: (playerId) => calls.add('unregister:$playerId'),
      );

      expect(
        calls,
        ['clear', 'wait', 'unregister:pip_video_9'],
      );
    });

    test('disposeReplacedVideoAfterFrame waits for scheduled callback', () {
      final calls = <String>[];
      OverlayCallback? scheduled;

      service.disposeReplacedVideoAfterFrame(
        downloadId: '11',
        scheduleAfterFrame: (callback) {
          calls.add('schedule');
          scheduled = callback;
        },
        unregisterPlayer: (playerId) => calls.add('unregister:$playerId'),
      );

      expect(calls, ['schedule']);

      scheduled!.call();

      expect(calls, ['schedule', 'unregister:pip_video_11']);
    });
  });
}
