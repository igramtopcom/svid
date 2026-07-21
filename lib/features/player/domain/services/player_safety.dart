import 'dart:async';

/// Guards stale UI gestures against media_kit's disposed-player assertion.
///
/// Desktop route/PiP transitions can dispose the underlying Player while a
/// delayed gesture callback is still queued. In that case the user action is
/// stale and should no-op, not surface as a production crash.
class PlayerSafety {
  PlayerSafety._();

  static bool isDisposedPlayerError(Object error) {
    final message = error.toString();
    return message.contains('[Player] has been disposed') ||
        message.contains('Player has been disposed');
  }

  static void safeCall(FutureOr<void> Function() action) {
    try {
      final result = action();
      if (result is Future) {
        unawaited(_guardFuture(result));
      }
    } catch (error, stackTrace) {
      if (isDisposedPlayerError(error)) return;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static Future<void> _guardFuture(Future<dynamic> future) async {
    try {
      await future;
    } catch (error, stackTrace) {
      if (isDisposedPlayerError(error)) return;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
