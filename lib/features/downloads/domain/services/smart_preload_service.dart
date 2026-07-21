import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Pre-downloads the first [defaultPreloadBytes] of a video URL into a
/// local cache so that:
///   1. Playback can start instantly (read from cache file).
///   2. The full download can reuse already-fetched bytes (copy + resume).
///
/// All methods are safe to call concurrently. Each URL is identified by a
/// SHA-256 cache key. Cache size is bounded to [maxCacheSize] and entries
/// expire after [maxCacheAge].
class SmartPreloadService {
  SmartPreloadService({
    Future<Directory> Function()? cacheDir,
    Future<void> Function(String url, File dest, int bytes)? fetcher,
    HttpClient? httpClient,
  })  : _cacheDir = cacheDir ?? _defaultCacheDir,
        _fetcher = fetcher,
        _httpClient = httpClient;

  static const int defaultPreloadBytes = 5 * 1024 * 1024; // 5 MB
  static const int maxCacheSize = 50 * 1024 * 1024; // 50 MB
  static const Duration maxCacheAge = Duration(hours: 2);

  final Future<Directory> Function() _cacheDir;

  /// Optional injected fetcher for tests. If null, the built-in HTTP
  /// Range-request fetcher is used.
  final Future<void> Function(String url, File dest, int bytes)? _fetcher;
  final HttpClient? _httpClient;

  // Tracks in-flight preloads to avoid duplicate concurrent fetches.
  final Map<String, Future<void>> _inFlight = <String, Future<void>>{};

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// SHA-256 of the normalized URL — stable, filesystem-safe cache key.
  static String cacheKeyFor(String url) {
    final normalized = url.trim().split('?').first; // strip query params
    return sha256.convert(utf8.encode(normalized)).toString();
  }

  /// Start preloading [url] in the background. Returns once preloading
  /// completes or is skipped (cache hit). Concurrent calls for the same URL
  /// are deduplicated — only one fetch is active at a time.
  Future<void> preload(
    String url, {
    int bytes = defaultPreloadBytes,
  }) async {
    final key = cacheKeyFor(url);
    // Skip if already cached.
    if (await hasCacheFor(url)) return;
    // If already fetching this key, wait for the existing fetch.
    final existing = _inFlight[key];
    if (existing != null) {
      await existing;
      return;
    }
    // Start a new fetch and register it.
    final future = _fetch(url, key, bytes);
    _inFlight[key] = future;
    try {
      await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  /// Returns `true` if a valid (non-expired) preload cache exists for [url].
  Future<bool> hasCacheFor(String url) async {
    final f = await _cacheFile(cacheKeyFor(url));
    if (!f.existsSync()) return false;
    final age = DateTime.now().difference(f.statSync().modified);
    return age < maxCacheAge;
  }

  /// Bytes available in cache for [url]. Returns 0 if no cache entry.
  Future<int> getCachedBytesFor(String url) async {
    final f = await _cacheFile(cacheKeyFor(url));
    return f.existsSync() ? f.lengthSync() : 0;
  }

  /// Absolute path to the cached preload file, or `null` if not cached.
  Future<String?> getCachedPathFor(String url) async {
    if (!await hasCacheFor(url)) return null;
    final f = await _cacheFile(cacheKeyFor(url));
    return f.path;
  }

  /// Remove the cache entry for [url] (no-op if not present).
  Future<void> clearFor(String url) async {
    final f = await _cacheFile(cacheKeyFor(url));
    if (f.existsSync()) await f.delete();
  }

  /// Copies the cached preload file to [destPath], returning the number of
  /// bytes seeded. Returns `0` if no valid cache entry exists for [url].
  ///
  /// Use this to seed the output file before starting a Rust download:
  /// the engine will receive `resumeOffset = seededBytes` and issue
  /// `Range: bytes=<seededBytes>-` to fetch the remainder.
  Future<int> seedDestination(String url, String destPath) async {
    if (!await hasCacheFor(url)) return 0;
    final src = await getCachedPathFor(url);
    if (src == null) return 0;
    await File(src).copy(destPath);
    final seeded = File(destPath).lengthSync();
    return seeded;
  }

  /// Remove ALL cache entries.
  Future<void> clearAll() async {
    final dir = await _cacheDir();
    if (dir.existsSync()) {
      for (final e in dir.listSync()) {
        if (e is File && e.path.endsWith('.preload')) await e.delete();
      }
    }
  }

  /// Total bytes used by the preload cache.
  Future<int> totalCacheSize() async {
    final dir = await _cacheDir();
    if (!dir.existsSync()) return 0;
    int total = 0;
    for (final e in dir.listSync()) {
      if (e is File && e.path.endsWith('.preload')) {
        total += e.lengthSync();
      }
    }
    return total;
  }

  /// Remove oldest cache entries until total size is below [maxSize].
  Future<void> prune({int maxSize = maxCacheSize}) async {
    final dir = await _cacheDir();
    if (!dir.existsSync()) return;

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.preload'))
        .toList()
      ..sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));

    int total = files.fold(0, (sum, f) => sum + f.lengthSync());
    for (final f in files) {
      if (total <= maxSize) break;
      final size = f.lengthSync();
      await f.delete();
      total -= size;
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static Future<Directory> _defaultCacheDir() async {
    final base = await getApplicationCacheDirectory();
    final dir = Directory(path.join(base.path, 'preload_cache'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<File> _cacheFile(String key) async {
    final dir = await _cacheDir();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File(path.join(dir.path, '$key.preload'));
  }

  Future<void> _fetch(String url, String key, int bytes) async {
    final dest = await _cacheFile(key);
    try {
      if (_fetcher != null) {
        await _fetcher(url, dest, bytes);
        return;
      }
      await _fetchWithRangeRequest(url, dest, bytes);
    } catch (_) {
      // Best-effort: silently discard errors (preload is always optional).
      if (dest.existsSync()) await dest.delete();
    }
  }

  Future<void> _fetchWithRangeRequest(String url, File dest, int bytes) async {
    final client = _httpClient ?? HttpClient();
    final disposeClient = _httpClient == null;
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.add('Range', 'bytes=0-${bytes - 1}');
      request.headers.add(
        'User-Agent',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/120.0.0.0 Safari/537.36',
      );
      final response = await request.close();
      // Accept 206 Partial Content or 200 OK (server may ignore Range header).
      if (response.statusCode != 206 && response.statusCode != 200) return;

      final sink = dest.openWrite();
      int written = 0;
      await for (final chunk in response) {
        if (written >= bytes) break;
        final remaining = bytes - written;
        final toWrite = chunk.length <= remaining ? chunk : chunk.sublist(0, remaining);
        sink.add(toWrite);
        written += toWrite.length;
      }
      await sink.flush();
      await sink.close();
    } finally {
      if (disposeClient) client.close();
    }
  }
}
