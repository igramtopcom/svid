import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/domain/services/smart_preload_service.dart';

/// Builds a SmartPreloadService wired to a temporary directory and an
/// injectable fetcher so tests never touch the network.
SmartPreloadService makeService({
  required Directory tempDir,
  Future<void> Function(String url, File dest, int bytes)? fetcher,
}) {
  return SmartPreloadService(
    cacheDir: () async => tempDir,
    fetcher: fetcher,
  );
}

/// A fetcher that writes [fillBytes] of zero-bytes to [dest].
Future<void> fakeFetcher(String url, File dest, int bytes) async {
  await dest.writeAsBytes(List.filled(bytes, 0));
}

/// A fetcher that always throws (simulates network error).
Future<void> errorFetcher(String url, File dest, int bytes) async {
  throw const SocketException('network unavailable');
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('preload_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('SmartPreloadService.cacheKeyFor', () {
    test('same URL produces same key', () {
      const url = 'https://example.com/video.mp4';
      expect(SmartPreloadService.cacheKeyFor(url), SmartPreloadService.cacheKeyFor(url));
    });

    test('different URLs produce different keys', () {
      expect(
        SmartPreloadService.cacheKeyFor('https://a.com/v1.mp4'),
        isNot(SmartPreloadService.cacheKeyFor('https://b.com/v2.mp4')),
      );
    });

    test('query params are stripped before hashing', () {
      const base = 'https://example.com/video.mp4';
      const withQuery = 'https://example.com/video.mp4?token=abc&expire=999';
      // Both should have the same key (stripped query).
      expect(SmartPreloadService.cacheKeyFor(base), SmartPreloadService.cacheKeyFor(withQuery));
    });

    test('key length is 64 hex chars (SHA-256)', () {
      expect(SmartPreloadService.cacheKeyFor('https://x.com').length, 64);
    });
  });

  group('hasCacheFor / preload / getCachedBytesFor', () {
    test('hasCacheFor returns false before any preload', () async {
      final svc = makeService(tempDir: tempDir);
      expect(await svc.hasCacheFor('https://example.com/v.mp4'), isFalse);
    });

    test('hasCacheFor returns true after successful preload', () async {
      final svc = makeService(tempDir: tempDir, fetcher: fakeFetcher);
      const url = 'https://example.com/v.mp4';
      await svc.preload(url, bytes: 1024);
      expect(await svc.hasCacheFor(url), isTrue);
    });

    test('getCachedBytesFor returns 0 when not cached', () async {
      final svc = makeService(tempDir: tempDir);
      expect(await svc.getCachedBytesFor('https://x.com/v.mp4'), 0);
    });

    test('getCachedBytesFor returns bytes written after preload', () async {
      final svc = makeService(tempDir: tempDir, fetcher: fakeFetcher);
      const url = 'https://x.com/v.mp4';
      await svc.preload(url, bytes: 2048);
      expect(await svc.getCachedBytesFor(url), 2048);
    });
  });

  group('getCachedPathFor', () {
    test('returns null when not cached', () async {
      final svc = makeService(tempDir: tempDir);
      expect(await svc.getCachedPathFor('https://x.com/v.mp4'), isNull);
    });

    test('returns a valid path ending in .preload after preload', () async {
      final svc = makeService(tempDir: tempDir, fetcher: fakeFetcher);
      const url = 'https://x.com/v.mp4';
      await svc.preload(url, bytes: 512);
      final p = await svc.getCachedPathFor(url);
      expect(p, isNotNull);
      expect(p, endsWith('.preload'));
      expect(File(p!).existsSync(), isTrue);
    });
  });

  group('clearFor / clearAll', () {
    test('clearFor removes specific cache entry', () async {
      final svc = makeService(tempDir: tempDir, fetcher: fakeFetcher);
      const url = 'https://x.com/v.mp4';
      await svc.preload(url, bytes: 512);
      await svc.clearFor(url);
      expect(await svc.hasCacheFor(url), isFalse);
    });

    test('clearAll removes all entries', () async {
      final svc = makeService(tempDir: tempDir, fetcher: fakeFetcher);
      await svc.preload('https://a.com/v1.mp4', bytes: 512);
      await svc.preload('https://b.com/v2.mp4', bytes: 512);
      await svc.clearAll();
      expect(await svc.totalCacheSize(), 0);
    });
  });

  group('totalCacheSize', () {
    test('returns 0 when cache is empty', () async {
      final svc = makeService(tempDir: tempDir);
      expect(await svc.totalCacheSize(), 0);
    });

    test('returns sum of cached file sizes', () async {
      final svc = makeService(tempDir: tempDir, fetcher: fakeFetcher);
      await svc.preload('https://a.com/v1.mp4', bytes: 1000);
      await svc.preload('https://b.com/v2.mp4', bytes: 2000);
      expect(await svc.totalCacheSize(), 3000);
    });
  });

  group('prune', () {
    test('prune removes oldest entries to stay below maxSize', () async {
      final svc = makeService(tempDir: tempDir, fetcher: fakeFetcher);
      await svc.preload('https://a.com/v1.mp4', bytes: 1000);
      // Small delay to ensure different mtime
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await svc.preload('https://b.com/v2.mp4', bytes: 1000);
      // Prune to 1000 bytes — should drop the oldest
      await svc.prune(maxSize: 1000);
      expect(await svc.totalCacheSize(), lessThanOrEqualTo(1000));
    });
  });

  group('seedDestination', () {
    test('returns 0 and does not create file when no cache exists', () async {
      final svc = makeService(tempDir: tempDir);
      final destPath = '${tempDir.path}/output.mp4';
      final seeded = await svc.seedDestination('https://no-cache.com/v.mp4', destPath);
      expect(seeded, 0);
      expect(File(destPath).existsSync(), isFalse);
    });

    test('copies cached bytes to destination and returns correct byte count', () async {
      final svc = makeService(tempDir: tempDir, fetcher: fakeFetcher);
      const url = 'https://example.com/seed.mp4';
      await svc.preload(url, bytes: 512);

      final destPath = '${tempDir.path}/output.mp4';
      final seeded = await svc.seedDestination(url, destPath);

      expect(seeded, 512);
      expect(File(destPath).existsSync(), isTrue);
      expect(File(destPath).lengthSync(), 512);
    });

    test('cache entry is still present after seedDestination', () async {
      final svc = makeService(tempDir: tempDir, fetcher: fakeFetcher);
      const url = 'https://example.com/keep.mp4';
      await svc.preload(url, bytes: 256);

      await svc.seedDestination(url, '${tempDir.path}/copy.mp4');

      // Original cache should be intact
      expect(await svc.hasCacheFor(url), isTrue);
    });
  });

  group('error resilience', () {
    test('failed fetch does not leave partial cache file', () async {
      final svc = makeService(tempDir: tempDir, fetcher: errorFetcher);
      const url = 'https://broken.com/v.mp4';
      // Should not throw
      await svc.preload(url, bytes: 512);
      expect(await svc.hasCacheFor(url), isFalse);
    });
  });
}
