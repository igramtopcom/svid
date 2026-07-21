import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../downloads/domain/entities/download_entity.dart';
import '../../domain/services/playback_queue_service.dart';

/// Global singleton for the playback queue service (session-scoped).
final playbackQueueServiceProvider = Provider<PlaybackQueueService>((ref) {
  return PlaybackQueueService();
});

/// Reactive state notifier wrapping [PlaybackQueueService].
///
/// Exposes queue state to the UI and triggers rebuilds on changes.
final playbackQueueProvider =
    StateNotifierProvider<PlaybackQueueNotifier, PlaybackQueueState>((ref) {
  final service = ref.read(playbackQueueServiceProvider);
  return PlaybackQueueNotifier(service);
});

/// Immutable snapshot of queue state for UI consumption.
class PlaybackQueueState {
  final List<DownloadEntity> items;
  final int currentIndex;
  final QueueRepeatMode repeatMode;
  final bool shuffleEnabled;

  const PlaybackQueueState({
    this.items = const [],
    this.currentIndex = -1,
    this.repeatMode = QueueRepeatMode.off,
    this.shuffleEnabled = false,
  });

  DownloadEntity? get currentItem =>
      currentIndex >= 0 && currentIndex < items.length
          ? items[currentIndex]
          : null;

  bool get isNotEmpty => items.isNotEmpty;
  bool get isEmpty => items.isEmpty;
  int get length => items.length;

  bool get hasNext {
    if (items.isEmpty) return false;
    if (repeatMode == QueueRepeatMode.repeatOne) return true;
    if (repeatMode == QueueRepeatMode.repeatAll) return true;
    return currentIndex < items.length - 1;
  }

  bool get hasPrevious {
    if (items.isEmpty) return false;
    if (repeatMode == QueueRepeatMode.repeatOne) return true;
    if (repeatMode == QueueRepeatMode.repeatAll) return true;
    return currentIndex > 0;
  }

  PlaybackQueueState copyWith({
    List<DownloadEntity>? items,
    int? currentIndex,
    QueueRepeatMode? repeatMode,
    bool? shuffleEnabled,
  }) {
    return PlaybackQueueState(
      items: items ?? this.items,
      currentIndex: currentIndex ?? this.currentIndex,
      repeatMode: repeatMode ?? this.repeatMode,
      shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
    );
  }
}

/// Notifier that mutates [PlaybackQueueService] and emits [PlaybackQueueState].
class PlaybackQueueNotifier extends StateNotifier<PlaybackQueueState> {
  final PlaybackQueueService _service;

  PlaybackQueueNotifier(this._service) : super(const PlaybackQueueState());

  /// Snapshot the service state into an immutable state object.
  void _sync() {
    state = PlaybackQueueState(
      items: _service.items,
      currentIndex: _service.currentIndex,
      repeatMode: _service.repeatMode,
      shuffleEnabled: _service.shuffleEnabled,
    );
  }

  /// Set the entire queue.
  void setQueue(List<DownloadEntity> downloads, {int startIndex = 0}) {
    _service.setQueue(downloads, startIndex: startIndex);
    _sync();
  }

  /// Add to the end of queue.
  void addToQueue(DownloadEntity download) {
    _service.addToQueue(download);
    _sync();
  }

  /// Insert right after the currently playing item.
  void playNext(DownloadEntity download) {
    _service.playNext(download);
    _sync();
  }

  /// Remove from queue.
  void removeFromQueue(int downloadId) {
    _service.removeFromQueue(downloadId);
    _sync();
  }

  /// Reorder item from [oldIndex] to [newIndex].
  void reorder(int oldIndex, int newIndex) {
    _service.reorder(oldIndex, newIndex);
    _sync();
  }

  /// Advance to the next item. Returns the item or null.
  DownloadEntity? next() {
    final item = _service.next();
    _sync();
    return item;
  }

  /// Go back to the previous item. Returns the item or null.
  DownloadEntity? previous() {
    final item = _service.previous();
    _sync();
    return item;
  }

  /// Jump to specific index.
  DownloadEntity? jumpTo(int index) {
    final item = _service.jumpTo(index);
    _sync();
    return item;
  }

  /// Cycle repeat mode.
  void cycleRepeatMode() {
    _service.cycleRepeatMode();
    _sync();
  }

  /// Toggle shuffle.
  void toggleShuffle() {
    _service.toggleShuffle();
    _sync();
  }

  /// Clear the queue.
  void clear() {
    _service.clear();
    _sync();
  }
}
