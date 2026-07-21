typedef OverlayCallback = void Function();
typedef OverlayScheduler = void Function(OverlayCallback callback);
typedef PlayerUnregister = void Function(String playerId);
typedef OverlayWait = Future<void> Function();
typedef SystemPipExit = Future<void> Function();

/// Coordinates safe teardown for mini-player and PiP overlays.
///
/// The key rule is: remove overlay state first, wait for the widget tree to
/// unmount, then dispose the underlying player. This prevents widgets from
/// touching a player that has already been disposed.
class PlayerOverlayLifecycleService {
  const PlayerOverlayLifecycleService();

  String audioMiniPlayerId(String downloadId) => 'mini_audio_$downloadId';
  String videoPipPlayerId(String downloadId) => 'pip_video_$downloadId';

  void disposeReplacedAudioAfterFrame({
    required String downloadId,
    required OverlayScheduler scheduleAfterFrame,
    required PlayerUnregister unregisterPlayer,
  }) {
    scheduleAfterFrame(() {
      unregisterPlayer(audioMiniPlayerId(downloadId));
    });
  }

  void disposeReplacedVideoAfterFrame({
    required String downloadId,
    required OverlayScheduler scheduleAfterFrame,
    required PlayerUnregister unregisterPlayer,
  }) {
    scheduleAfterFrame(() {
      unregisterPlayer(videoPipPlayerId(downloadId));
    });
  }

  Future<void> closeAudioOverlay({
    required String downloadId,
    required OverlayCallback clearState,
    required OverlayWait waitForOverlayUnmount,
    required PlayerUnregister unregisterPlayer,
  }) async {
    clearState();
    await waitForOverlayUnmount();
    unregisterPlayer(audioMiniPlayerId(downloadId));
  }

  Future<void> closeVideoOverlay({
    required String downloadId,
    required bool systemPipActive,
    required OverlayCallback clearState,
    required OverlayWait waitForOverlayUnmount,
    required SystemPipExit exitSystemPip,
    required PlayerUnregister unregisterPlayer,
  }) async {
    clearState();
    await waitForOverlayUnmount();
    if (systemPipActive) {
      await exitSystemPip();
    }
    unregisterPlayer(videoPipPlayerId(downloadId));
  }
}
