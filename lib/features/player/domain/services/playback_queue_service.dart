import 'dart:math';

import '../../../downloads/domain/entities/download_entity.dart';

/// Playback queue repeat mode.
enum QueueRepeatMode {
  /// No repeat — stop after last item.
  off,

  /// Repeat the current item endlessly.
  repeatOne,

  /// Repeat the entire queue after the last item.
  repeatAll,
}

/// In-memory playback queue for sequential media playback.
///
/// Tracks an ordered list of [DownloadEntity] items, a current index,
/// and shuffle/repeat modes. The queue is session-scoped (not persisted).
class PlaybackQueueService {
  final List<DownloadEntity> _items = [];
  int _currentIndex = -1;
  QueueRepeatMode _repeatMode = QueueRepeatMode.off;
  bool _shuffleEnabled = false;
  final _random = Random();

  // --- Getters ---

  /// All items in the queue.
  List<DownloadEntity> get items => List.unmodifiable(_items);

  /// Current playback index (-1 if queue is empty or nothing playing).
  int get currentIndex => _currentIndex;

  /// Current item or null.
  DownloadEntity? get currentItem =>
      _currentIndex >= 0 && _currentIndex < _items.length
          ? _items[_currentIndex]
          : null;

  /// Whether the queue has items.
  bool get isNotEmpty => _items.isNotEmpty;

  /// Whether the queue is empty.
  bool get isEmpty => _items.isEmpty;

  /// Number of items in queue.
  int get length => _items.length;

  /// Current repeat mode.
  QueueRepeatMode get repeatMode => _repeatMode;

  /// Whether shuffle is enabled.
  bool get shuffleEnabled => _shuffleEnabled;

  /// Whether there is a next item (accounting for repeat mode).
  bool get hasNext {
    if (_items.isEmpty) return false;
    if (_repeatMode == QueueRepeatMode.repeatOne) return true;
    if (_repeatMode == QueueRepeatMode.repeatAll) return true;
    return _currentIndex < _items.length - 1;
  }

  /// Whether there is a previous item.
  bool get hasPrevious {
    if (_items.isEmpty) return false;
    if (_repeatMode == QueueRepeatMode.repeatOne) return true;
    if (_repeatMode == QueueRepeatMode.repeatAll) return true;
    return _currentIndex > 0;
  }

  // --- Queue Manipulation ---

  /// Set the entire queue and start at [startIndex].
  void setQueue(List<DownloadEntity> downloads, {int startIndex = 0}) {
    _items.clear();
    _items.addAll(downloads);
    _currentIndex = _items.isEmpty ? -1 : startIndex.clamp(0, _items.length - 1);
  }

  /// Add a download to the end of the queue.
  void addToQueue(DownloadEntity download) {
    // Don't add duplicates
    if (_items.any((d) => d.id == download.id)) return;
    _items.add(download);
    // If queue was empty, set current to 0
    if (_currentIndex < 0) _currentIndex = 0;
  }

  /// Insert a download right after the currently playing item ("Play Next").
  void playNext(DownloadEntity download) {
    // Remove existing occurrence if present
    _items.removeWhere((d) => d.id == download.id);
    // Adjust current index if removal shifted it
    if (_currentIndex >= _items.length) {
      _currentIndex = _items.length - 1;
    }

    if (_items.isEmpty) {
      _items.add(download);
      _currentIndex = 0;
    } else {
      final insertAt = _currentIndex + 1;
      _items.insert(insertAt.clamp(0, _items.length), download);
    }
  }

  /// Remove an item from the queue by its download ID.
  void removeFromQueue(int downloadId) {
    final idx = _items.indexWhere((d) => d.id == downloadId);
    if (idx < 0) return;

    _items.removeAt(idx);
    if (_items.isEmpty) {
      _currentIndex = -1;
    } else if (idx < _currentIndex) {
      _currentIndex--;
    } else if (idx == _currentIndex && _currentIndex >= _items.length) {
      _currentIndex = _items.length - 1;
    }
  }

  /// Reorder an item from [oldIndex] to [newIndex].
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _items.length) return;
    if (newIndex < 0 || newIndex >= _items.length) return;
    if (oldIndex == newIndex) return;

    final item = _items.removeAt(oldIndex);
    _items.insert(newIndex, item);

    // Update currentIndex to follow the currently playing item
    if (_currentIndex == oldIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex--;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex++;
    }
  }

  /// Clear the entire queue.
  void clear() {
    _items.clear();
    _currentIndex = -1;
  }

  // --- Navigation ---

  /// Advance to the next item. Returns the next [DownloadEntity] or null
  /// if there is no next item.
  DownloadEntity? next() {
    if (_items.isEmpty) return null;

    if (_repeatMode == QueueRepeatMode.repeatOne) {
      return currentItem;
    }

    if (_shuffleEnabled && _items.length > 1) {
      int nextIdx;
      do {
        nextIdx = _random.nextInt(_items.length);
      } while (nextIdx == _currentIndex);
      _currentIndex = nextIdx;
      return currentItem;
    }

    if (_currentIndex < _items.length - 1) {
      _currentIndex++;
      return currentItem;
    }

    // At end of queue
    if (_repeatMode == QueueRepeatMode.repeatAll) {
      _currentIndex = 0;
      return currentItem;
    }

    return null; // No next item (off mode, at end)
  }

  /// Go to the previous item. Returns the [DownloadEntity] or null.
  DownloadEntity? previous() {
    if (_items.isEmpty) return null;

    if (_repeatMode == QueueRepeatMode.repeatOne) {
      return currentItem;
    }

    if (_currentIndex > 0) {
      _currentIndex--;
      return currentItem;
    }

    // At start of queue
    if (_repeatMode == QueueRepeatMode.repeatAll) {
      _currentIndex = _items.length - 1;
      return currentItem;
    }

    return null; // No previous item
  }

  /// Jump to a specific index in the queue.
  DownloadEntity? jumpTo(int index) {
    if (index < 0 || index >= _items.length) return null;
    _currentIndex = index;
    return currentItem;
  }

  /// Peek at the next item without advancing the index.
  ///
  /// Returns null if there is no next item, shuffle is enabled (non-deterministic),
  /// or the queue is empty. Callers can use this to preload the next track.
  DownloadEntity? peekNext() {
    if (_items.isEmpty) return null;
    if (_repeatMode == QueueRepeatMode.repeatOne) return currentItem;
    if (_shuffleEnabled) return null; // shuffle order is non-deterministic

    if (_currentIndex < _items.length - 1) {
      return _items[_currentIndex + 1];
    }

    if (_repeatMode == QueueRepeatMode.repeatAll && _items.length > 1) {
      return _items[0];
    }

    return null;
  }

  // --- Mode Controls ---

  /// Set repeat mode.
  void setRepeatMode(QueueRepeatMode mode) {
    _repeatMode = mode;
  }

  /// Cycle to the next repeat mode: off → repeatAll → repeatOne → off.
  QueueRepeatMode cycleRepeatMode() {
    switch (_repeatMode) {
      case QueueRepeatMode.off:
        _repeatMode = QueueRepeatMode.repeatAll;
      case QueueRepeatMode.repeatAll:
        _repeatMode = QueueRepeatMode.repeatOne;
      case QueueRepeatMode.repeatOne:
        _repeatMode = QueueRepeatMode.off;
    }
    return _repeatMode;
  }

  /// Toggle shuffle on/off.
  bool toggleShuffle() {
    _shuffleEnabled = !_shuffleEnabled;
    return _shuffleEnabled;
  }

  /// Set shuffle mode.
  void setShuffle(bool enabled) {
    _shuffleEnabled = enabled;
  }
}
