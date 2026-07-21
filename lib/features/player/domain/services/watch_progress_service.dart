import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../downloads/domain/repositories/download_repository.dart';

/// Tracks playback position per download so users can resume where they left off.
///
/// Data is stored in SharedPreferences (ephemeral, no DB migration needed).
/// Keys: `watch_progress_{downloadId}` → JSON `{positionMs, durationMs, updatedAt}`.
/// Auto-prunes entries older than 30 days.
///
/// Also manages the `isWatched` DB flag and per-session manual-unwatch tracking.
class WatchProgressService {
  final SharedPreferences _prefs;
  final DownloadRepository? _repository;

  static const _keyPrefix = 'watch_progress_';
  static const _pruneDays = 30;

  /// Position must exceed this fraction of duration to be saved (skip first 5%)
  static const _minProgressToSave = 0.05;

  /// Standard watched threshold (videos ≥30s): ≥90% played
  static const _watchedThreshold = 0.90;

  /// Short-video watched threshold (videos <30s): ≥80% played
  static const _shortVideoWatchedThreshold = 0.80;

  /// Videos shorter than this (ms) use the short-video threshold
  static const _shortVideoCutoffMs = 30 * 1000;

  /// Per-session set of downloads manually marked unwatched this session.
  /// Auto-mark is suppressed for these IDs until app restart.
  final Set<int> _manuallyUnwatched = {};

  WatchProgressService(this._prefs, {DownloadRepository? repository})
    : _repository = repository;

  /// Save current playback position for a download and auto-mark watched if threshold reached.
  ///
  /// Thresholds:
  /// - Standard (duration ≥ 30s): watched at ≥ 90% played
  /// - Short video (duration < 30s): watched at ≥ 80% played
  /// - Seek-to-end: seeking to ≥ 90% counts as watched even without linear viewing
  ///
  /// Auto-mark is suppressed if user explicitly called [markAsUnwatched] this session.
  void savePosition(int downloadId, Duration position, Duration duration) {
    _savePosition(downloadId, position, duration, requireMinimumProgress: true);
  }

  /// Save a precise resume point for player surface handoffs and cold re-open.
  ///
  /// Unlike [savePosition], this intentionally does not require the first 5% of
  /// the file to be played. The 5% gate is useful for watch-history badges, but
  /// it makes desktop player UX feel broken: a user can watch 10-20 seconds of a
  /// long video, switch from sidebar to fullscreen, or re-open it from history,
  /// and still expect playback to continue from that exact point.
  ///
  /// Near-end behavior is unchanged: positions past the watched threshold still
  /// clear progress and mark the item watched.
  void saveResumePoint(int downloadId, Duration position, Duration duration) {
    _savePosition(
      downloadId,
      position,
      duration,
      requireMinimumProgress: false,
    );
  }

  void _savePosition(
    int downloadId,
    Duration position,
    Duration duration, {
    required bool requireMinimumProgress,
  }) {
    if (duration.inMilliseconds <= 0) return;
    if (position <= const Duration(milliseconds: 500)) return;

    final fraction = position.inMilliseconds / duration.inMilliseconds;

    // Don't save if barely started
    if (requireMinimumProgress && fraction < _minProgressToSave) return;

    // Determine effective threshold based on video length
    final isShortVideo = duration.inMilliseconds < _shortVideoCutoffMs;
    final threshold =
        isShortVideo ? _shortVideoWatchedThreshold : _watchedThreshold;

    if (fraction >= threshold) {
      clearProgress(downloadId);
      // Auto-mark watched (unless manually unwatched this session)
      if (!_isManuallyUnwatched(downloadId)) {
        markAsWatched(downloadId);
      }
      return;
    }

    final data = {
      'positionMs': position.inMilliseconds,
      'durationMs': duration.inMilliseconds,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };

    _prefs.setString('$_keyPrefix$downloadId', jsonEncode(data));
  }

  /// Called when playback reaches the natural end of the media (stream completion).
  /// Marks watched for all videos, including short clips where onEnd is the reliable signal.
  void onPlaybackEnd(int downloadId) {
    if (!_isManuallyUnwatched(downloadId)) {
      clearProgress(downloadId);
      markAsWatched(downloadId);
    }
  }

  /// Persist [downloadId] as watched in the DB.
  /// Fire-and-forget — failure is logged at debug level.
  void markAsWatched(int downloadId) {
    _repository?.updateIsWatched(downloadId, isWatched: true);
  }

  /// Persist [downloadId] as unwatched in the DB and suppress auto-mark for this session.
  void markAsUnwatched(int downloadId) {
    _manuallyUnwatched.add(downloadId);
    _repository?.updateIsWatched(downloadId, isWatched: false);
  }

  /// Returns true if user manually marked [downloadId] as unwatched this session.
  bool _isManuallyUnwatched(int downloadId) =>
      _manuallyUnwatched.contains(downloadId);

  /// Get saved progress for a download. Returns null if none saved.
  WatchProgress? getProgress(int downloadId) {
    final raw = _prefs.getString('$_keyPrefix$downloadId');
    if (raw == null) return null;

    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return WatchProgress(
        positionMs: data['positionMs'] as int,
        durationMs: data['durationMs'] as int,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          data['updatedAt'] as int,
        ),
      );
    } catch (_) {
      // Corrupt data — remove it
      clearProgress(downloadId);
      return null;
    }
  }

  /// Clear saved progress for a download.
  void clearProgress(int downloadId) {
    _prefs.remove('$_keyPrefix$downloadId');
  }

  /// Get watch fraction (0.0–1.0) for a download, or null if no progress saved.
  double? getWatchFraction(int downloadId) {
    final progress = getProgress(downloadId);
    if (progress == null || progress.durationMs <= 0) return null;
    return (progress.positionMs / progress.durationMs).clamp(0.0, 1.0);
  }

  /// Prune entries older than [_pruneDays]. Call on app startup.
  int pruneOldEntries() {
    final now = DateTime.now();
    final keys =
        _prefs.getKeys().where((k) => k.startsWith(_keyPrefix)).toList();
    var pruned = 0;

    for (final key in keys) {
      try {
        final raw = _prefs.getString(key);
        if (raw == null) continue;
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final updatedAt = DateTime.fromMillisecondsSinceEpoch(
          data['updatedAt'] as int,
        );
        if (now.difference(updatedAt).inDays > _pruneDays) {
          _prefs.remove(key);
          pruned++;
        }
      } catch (_) {
        // Corrupt — remove
        _prefs.remove(key);
        pruned++;
      }
    }

    return pruned;
  }
}

/// Saved watch progress data.
class WatchProgress {
  final int positionMs;
  final int durationMs;
  final DateTime updatedAt;

  const WatchProgress({
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
  });

  Duration get position => Duration(milliseconds: positionMs);
  Duration get duration => Duration(milliseconds: durationMs);
  double get fraction =>
      durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;

  /// Format position as "X:XX" or "X:XX:XX"
  String get formattedPosition {
    final total = positionMs ~/ 1000;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
