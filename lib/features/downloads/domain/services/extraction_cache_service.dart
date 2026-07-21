import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../../../core/logging/app_logger.dart';
import '../../data/datasources/extraction_cache.dart';
import '../entities/video_info.dart';

/// File-based extraction metadata cache for yt-dlp results.
///
/// Stores serialized VideoInfo as `.info.json` files on disk with:
/// - 24-hour TTL (configurable)
/// - 100MB max size with LRU eviction
/// - URL normalization + SHA-256 hashing for filenames
///
/// Complements the in-memory ExtractionCache (SharedPreferences, 1h TTL)
/// by providing longer-term, larger-capacity caching that survives app restarts.
class ExtractionCacheService {
  static const Duration defaultTtl = Duration(hours: 24);
  static const int defaultMaxSizeBytes = 100 * 1024 * 1024; // 100 MB

  final String _cacheDir;
  final Duration _ttl;
  final int _maxSizeBytes;

  final DateTime Function()? _clock;

  ExtractionCacheService(
    this._cacheDir, {
    Duration? ttl,
    int? maxSizeBytes,
    DateTime Function()? clock,
  })  : _ttl = ttl ?? defaultTtl,
        _maxSizeBytes = maxSizeBytes ?? defaultMaxSizeBytes,
        _clock = clock;

  DateTime get _now => _clock?.call() ?? DateTime.now();

  /// Get cached VideoInfo for [url], or null if not cached/expired.
  Future<VideoInfo?> get(String url) async {
    final file = File(_pathForUrl(url));

    if (!await file.exists()) return null;

    try {
      final stat = await file.stat();
      if (_isExpired(stat.modified)) {
        await file.delete();
        appLogger.debug('🗑️ [MetadataCache] Expired: ${_hashUrl(url)}');
        return null;
      }

      final json = await file.readAsString();
      final data = jsonDecode(json) as Map<String, dynamic>;
      final entry = CacheEntry.fromJson(data);

      // Update access time for LRU
      await file.setLastModified(_now);

      appLogger.debug('✅ [MetadataCache] Hit: ${_hashUrl(url).substring(0, 8)}');
      return entry.videoInfo;
    } catch (e) {
      appLogger.warning('⚠️ [MetadataCache] Read error: $e');
      // Corrupted file — delete
      try {
        await file.delete();
      } catch (_) {}
      return null;
    }
  }

  /// Cache [videoInfo] for [url].
  Future<void> put(String url, VideoInfo videoInfo) async {
    try {
      final dir = Directory(_cacheDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final entry = CacheEntry(
        videoInfo: videoInfo,
        extractedAt: _now,
      );

      final file = File(_pathForUrl(url));
      final json = jsonEncode(entry.toJson());
      await file.writeAsString(json);
      // Sync file modification time with our clock (important for TTL + LRU)
      await file.setLastModified(_now);

      appLogger.debug('💾 [MetadataCache] Stored: ${_hashUrl(url).substring(0, 8)}');

      // Evict if over size limit
      await _evictIfNeeded();
    } catch (e) {
      appLogger.warning('⚠️ [MetadataCache] Write error: $e');
    }
  }

  /// Check if [url] is cached and not expired (without reading full data).
  Future<bool> contains(String url) async {
    final file = File(_pathForUrl(url));
    if (!await file.exists()) return false;

    final stat = await file.stat();
    if (_isExpired(stat.modified)) {
      await file.delete();
      return false;
    }
    return true;
  }

  /// Get total cache size in bytes.
  Future<int> getCacheSize() async {
    final dir = Directory(_cacheDir);
    if (!await dir.exists()) return 0;

    int total = 0;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.info.json')) {
        total += await entity.length();
      }
    }
    return total;
  }

  /// Get number of cached entries.
  Future<int> getEntryCount() async {
    final dir = Directory(_cacheDir);
    if (!await dir.exists()) return 0;

    int count = 0;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.info.json')) {
        count++;
      }
    }
    return count;
  }

  /// Clear all cached metadata files.
  Future<void> clear() async {
    final dir = Directory(_cacheDir);
    if (!await dir.exists()) return;

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.info.json')) {
        await entity.delete();
      }
    }
    appLogger.info('🗑️ [MetadataCache] Cleared all entries');
  }

  /// Remove expired entries.
  Future<int> pruneExpired() async {
    final dir = Directory(_cacheDir);
    if (!await dir.exists()) return 0;

    int removed = 0;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.info.json')) {
        final stat = await entity.stat();
        if (_isExpired(stat.modified)) {
          await entity.delete();
          removed++;
        }
      }
    }

    if (removed > 0) {
      appLogger.debug('🗑️ [MetadataCache] Pruned $removed expired entries');
    }
    return removed;
  }

  bool _isExpired(DateTime modified) {
    return _now.difference(modified) > _ttl;
  }

  /// Evict oldest files if total cache size exceeds max.
  Future<void> _evictIfNeeded() async {
    final dir = Directory(_cacheDir);
    if (!await dir.exists()) return;

    final files = <(File, FileStat)>[];
    int totalSize = 0;

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.info.json')) {
        final stat = await entity.stat();
        files.add((entity, stat));
        totalSize += stat.size;
      }
    }

    if (totalSize <= _maxSizeBytes) return;

    // Sort by last modified (oldest first) for LRU eviction
    files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));

    int evicted = 0;
    for (final (file, stat) in files) {
      if (totalSize <= _maxSizeBytes) break;
      totalSize -= stat.size;
      await file.delete();
      evicted++;
    }

    if (evicted > 0) {
      appLogger.debug('🗑️ [MetadataCache] LRU evicted $evicted entries');
    }
  }

  String _pathForUrl(String url) {
    return '$_cacheDir/${_hashUrl(url)}.info.json';
  }

  /// Normalize URL and compute SHA-256 hash for filename.
  static String _hashUrl(String url) {
    final normalized = _normalizeUrl(url);
    return sha256.convert(utf8.encode(normalized)).toString();
  }

  /// Normalize URL by canonicalizing platform variants, removing tracking
  /// parameters, and normalizing host/path.
  ///
  /// YouTube: youtu.be/X, /shorts/X, m.youtube.com → youtube.com/watch?v=X
  /// Twitter/X: x.com → twitter.com
  static String _normalizeUrl(String url) {
    try {
      var uri = Uri.parse(url.trim());

      // Canonicalize platform-specific URL variants first
      uri = _canonicalizePlatformUrl(uri);

      // Remove tracking parameters
      const trackingParams = {
        'utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content',
        'si', 'feature', 'ref', 'fbclid', 'gclid',
      };

      final cleanParams = Map<String, String>.from(uri.queryParameters)
        ..removeWhere((key, _) => trackingParams.contains(key));

      uri = uri.replace(queryParameters: cleanParams.isEmpty ? null : cleanParams);

      // Remove trailing slash
      var path = uri.path;
      if (path.endsWith('/') && path.length > 1) {
        path = path.substring(0, path.length - 1);
      }

      // Lowercase host
      return '${uri.scheme}://${uri.host.toLowerCase()}$path'
          '${uri.query.isNotEmpty ? '?${uri.query}' : ''}';
    } catch (_) {
      return url.trim().toLowerCase();
    }
  }

  /// Canonicalize platform-specific URL variants to a single form.
  static Uri _canonicalizePlatformUrl(Uri uri) {
    final host = uri.host.toLowerCase();

    // YouTube: all forms → youtube.com/watch?v=ID
    if (host == 'youtu.be') {
      final videoId = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      if (videoId != null && videoId.isNotEmpty) {
        return Uri.parse('https://www.youtube.com/watch?v=$videoId');
      }
    }
    if (host.contains('youtube.com')) {
      final path = uri.path;
      String? videoId;

      final shortMatch = RegExp(r'^/(shorts|embed|v)/([a-zA-Z0-9_-]+)').firstMatch(path);
      if (shortMatch != null) {
        videoId = shortMatch.group(2);
      }
      videoId ??= uri.queryParameters['v'];

      if (videoId != null && videoId.isNotEmpty) {
        return Uri.parse('https://www.youtube.com/watch?v=$videoId');
      }
      return uri.replace(host: 'www.youtube.com');
    }

    // Twitter/X: x.com → twitter.com
    if (host == 'x.com' || host == 'www.x.com') {
      return uri.replace(host: 'twitter.com');
    }

    // Instagram: www prefix normalization
    if (host == 'instagram.com') {
      return uri.replace(host: 'www.instagram.com');
    }

    // TikTok: www prefix normalization
    if (host == 'tiktok.com') {
      return uri.replace(host: 'www.tiktok.com');
    }

    return uri;
  }

  /// Format cache size for display (e.g., "12.5 MB").
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
