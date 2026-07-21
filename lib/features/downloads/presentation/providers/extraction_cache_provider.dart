import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../data/datasources/extraction_cache.dart';
import '../../domain/entities/video_info.dart';
import '../../domain/services/extraction_cache_service.dart';

/// Provider for ExtractionCache
final extractionCacheProvider = Provider<ExtractionCache>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ExtractionCache(prefs);
});

/// Provider for extraction history (reactive)
final extractionHistoryProvider = StateNotifierProvider<ExtractionHistoryNotifier, List<CacheEntry>>((ref) {
  final cache = ref.watch(extractionCacheProvider);
  return ExtractionHistoryNotifier(cache);
});

/// Notifier for extraction history state
class ExtractionHistoryNotifier extends StateNotifier<List<CacheEntry>> {
  final ExtractionCache _cache;
  ExtractionCacheService? _fileCache;
  bool _isInitialized = false;

  ExtractionHistoryNotifier(this._cache) : super([]) {
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    await _cache.initialize();
    if (!mounted) return;
    _isInitialized = true;
    state = _cache.getHistory();
  }

  /// Lazy-init file-based cache (24h TTL, 100MB max, survives app restarts).
  Future<ExtractionCacheService> _getFileCache() async {
    if (_fileCache != null) return _fileCache!;
    final appSupport = await getApplicationSupportDirectory();
    final cacheDir = p.join(appSupport.path, 'extraction_cache');
    _fileCache = ExtractionCacheService(cacheDir);
    // Housekeeping: prune expired entries on first access (fire-and-forget)
    unawaited(_fileCache!.pruneExpired().catchError((_) => 0));
    return _fileCache!;
  }

  /// Ensure cache is initialized before use
  Future<void> ensureInitialized() async {
    if (!_isInitialized) {
      await _cache.initialize();
      _isInitialized = true;
    }
  }

  /// Refresh history from cache
  Future<void> refresh() async {
    await ensureInitialized();
    if (!mounted) return;
    state = _cache.getHistory();
  }

  /// Add new extraction to history
  Future<void> addExtraction(String url, VideoInfo info) async {
    await _cache.set(url, info);
    if (!mounted) return;
    state = _cache.getHistory();

    // Also persist to file-based cache for cross-session reuse (fire-and-forget)
    unawaited(_getFileCache().then((fc) => fc.put(url, info)).catchError((_) {}));
  }

  /// Get cached video info (async - ensures initialization).
  ///
  /// Two-layer lookup:
  /// 1. In-memory cache (SharedPreferences, 1h TTL) — instant
  /// 2. File-based cache (disk, 24h TTL) — fallback for cross-session hits
  Future<VideoInfo?> getCachedAsync(String url) async {
    await ensureInitialized();

    // Layer 1: in-memory (fast)
    final memoryResult = _cache.get(url);
    if (memoryResult != null) return memoryResult;

    // Layer 2: file-based disk cache (survives app restarts)
    try {
      final fileCache = await _getFileCache();
      final diskResult = await fileCache.get(url);
      if (diskResult != null) {
        appLogger.info('⚡ [DiskCache] Hit — promoting to memory: ${url.substring(0, url.length.clamp(0, 60))}');
        // Promote to memory cache for instant access next time
        await _cache.set(url, diskResult);
        if (!mounted) return diskResult;
        state = _cache.getHistory();
        return diskResult;
      }
    } catch (e) {
      appLogger.debug('File cache lookup failed: $e');
    }

    return null;
  }

  /// Get cached video info (sync - only works after initialization)
  /// Prefer getCachedAsync() for reliable results
  VideoInfo? getCached(String url) {
    return _cache.get(url);
  }

  /// Check if URL is cached (async - ensures initialization)
  Future<bool> isCachedAsync(String url) async {
    await ensureInitialized();
    if (_cache.contains(url)) return true;

    // Also check file cache
    try {
      final fileCache = await _getFileCache();
      return await fileCache.contains(url);
    } catch (_) {
      return false;
    }
  }

  /// Check if URL is cached (sync - only works after initialization)
  bool isCached(String url) {
    return _cache.contains(url);
  }

  /// Remove item from history
  Future<void> removeItem(String url) async {
    await _cache.remove(url);
    if (!mounted) return;
    state = _cache.getHistory();
  }

  /// Clear all history (both memory and disk)
  Future<void> clearAll() async {
    await _cache.clear();
    if (!mounted) return;
    state = [];
    // Also clear file cache
    unawaited(_getFileCache().then((fc) => fc.clear()).catchError((_) {}));
  }

  /// Get cache stats
  int get cacheSize => _cache.size;
}
