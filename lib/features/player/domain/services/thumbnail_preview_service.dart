import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../data/datasources/ffmpeg_datasource.dart';
import '../../../../core/logging/app_logger.dart';

/// Audio-only file extensions — thumbnail preview is never shown for these.
const _audioExtensions = {
  '.mp3', '.m4a', '.flac', '.opus', '.ogg', '.wav', '.aac', '.wma', '.aiff',
};

/// LRU-capped frame thumbnail cache.
///
/// Keyed by `"$filePath@$secondKey"`. Max 60 entries — at ~40KB/frame ≈ 2.4MB.
class _LruCache {
  static const int maxSize = 60;
  final _map = <String, Uint8List>{};

  _LruCache();

  Uint8List? get(String key) {
    final value = _map.remove(key);
    if (value != null) _map[key] = value; // move to end (most-recent)
    return value;
  }

  void put(String key, Uint8List value) {
    _map.remove(key); // ensure ordering
    _map[key] = value;
    if (_map.length > maxSize) {
      _map.remove(_map.keys.first); // evict oldest
    }
  }

  void clear() => _map.clear();
}

/// Provides frame-accurate thumbnail images for the seek timeline.
///
/// - Extracts JPEG frames via [FFmpegDatasource] (160px wide, ~30–50 KB each).
/// - Caches up to 60 frames in an LRU cache (~2.4 MB max).
/// - Pre-warms 10 evenly-spaced frames in the background after duration is known.
/// - Audio-only files: [isAudioOnly] returns true → callers should skip init.
class ThumbnailPreviewService {
  final FFmpegDatasource _ffmpeg;

  final _cache = _LruCache();
  bool _disposed = false;
  bool _prewarming = false;

  ThumbnailPreviewService(this._ffmpeg);

  // ── public helpers ────────────────────────────────────────────────────────

  /// Returns true if [filePath] appears to be audio-only (by extension).
  static bool isAudioOnlyByExtension(String filePath) {
    final ext = filePath.contains('.')
        ? filePath.substring(filePath.lastIndexOf('.')).toLowerCase()
        : '';
    return _audioExtensions.contains(ext);
  }

  // ── core API ──────────────────────────────────────────────────────────────

  /// Returns the JPEG frame at [position] (rounded to nearest second for caching).
  ///
  /// Returns null if:
  /// - FFmpeg is unavailable / times out (> 500 ms)
  /// - The file is corrupt or audio-only
  /// - [dispose] has been called
  Future<Uint8List?> getFrameAt(String filePath, Duration position) async {
    if (_disposed) return null;

    final secondKey = position.inSeconds;
    final cacheKey = '$filePath@$secondKey';

    final cached = _cache.get(cacheKey);
    if (cached != null) return cached;

    final result = await _ffmpeg.extractFrameAt(
      filePath,
      Duration(seconds: secondKey),
      timeout: const Duration(milliseconds: 3000),
    );

    if (result != null && !_disposed) {
      _cache.put(cacheKey, result);
    }
    return result;
  }

  /// Triggers background pre-warm: 10 evenly-spaced frames across [totalDuration].
  ///
  /// Runs sequentially (not parallel) to avoid I/O spike.
  /// Stops automatically if [dispose] is called.
  Future<void> prewarm(String filePath, Duration totalDuration) async {
    if (_disposed || _prewarming || totalDuration <= Duration.zero) return;
    if (isAudioOnlyByExtension(filePath)) return;

    _prewarming = true;
    appLogger.debug('[ThumbnailPreviewService] Pre-warming $filePath (${totalDuration.inSeconds}s)');

    try {
      const frameCount = 10;
      for (int i = 0; i < frameCount; i++) {
        if (_disposed) break;
        final fraction = (i + 1) / (frameCount + 1); // evenly spaced, skip 0 and end
        final pos = Duration(milliseconds: (totalDuration.inMilliseconds * fraction).round());
        await getFrameAt(filePath, pos);
      }
    } finally {
      _prewarming = false;
    }
  }

  /// Releases cache and prevents further extraction.
  void dispose() {
    _disposed = true;
    _cache.clear();
  }
}
