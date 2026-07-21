import 'dart:async';

/// Runs a periodic check (default every 60 s) that fires a callback so the
/// [DownloadsNotifier] can start any downloads whose scheduled time has passed.
class DownloadSchedulerService {
  final Duration _interval;
  Timer? _timer;

  DownloadSchedulerService({Duration interval = const Duration(seconds: 60)})
      : _interval = interval;

  /// Start the scheduler.  [onTick] is called immediately and then every
  /// [interval] until [stop] is called.
  void start(void Function() onTick) {
    stop(); // cancel any running timer first
    onTick(); // fire immediately so we don't wait 60 s on first launch
    _timer = Timer.periodic(_interval, (_) => onTick());
  }

  /// Stop the scheduler.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  bool get isRunning => _timer != null;
}
