import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/domain/entities/video_info.dart';
import 'package:svid/features/downloads/domain/services/extraction_cache_service.dart';

/// Replicate URL hashing for test file creation (corrupted file test).
String _hashUrl(String url) {
  final normalized = _normalizeUrl(url);
  return sha256.convert(utf8.encode(normalized)).toString();
}

String _normalizeUrl(String url) {
  try {
    var uri = Uri.parse(url.trim());
    const trackingParams = {
      'utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content',
      'si', 'feature', 'ref', 'fbclid', 'gclid',
    };
    final cleanParams = Map<String, String>.from(uri.queryParameters)
      ..removeWhere((key, _) => trackingParams.contains(key));
    uri = uri.replace(queryParameters: cleanParams.isEmpty ? null : cleanParams);
    var path = uri.path;
    if (path.endsWith('/') && path.length > 1) {
      path = path.substring(0, path.length - 1);
    }
    return '${uri.scheme}://${uri.host.toLowerCase()}$path'
        '${uri.query.isNotEmpty ? '?${uri.query}' : ''}';
  } catch (_) {
    return url.trim().toLowerCase();
  }
}

void main() {
  late Directory tempDir;
  late ExtractionCacheService service;
  late DateTime fakeNow;

  VideoInfo makeVideoInfo(String url, String title) {
    return VideoInfo(
      url: url,
      title: title,
      availableQualities: [
        const Quality(
          qualityText: '1080p',
          size: '100 MB',
          encryptedUrl: 'ytdlp:1080p',
          mediaType: MediaType.video,
        ),
      ],
    );
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('extraction_cache_test_');
    fakeNow = DateTime(2026, 2, 28, 12, 0, 0);
    service = ExtractionCacheService(
      tempDir.path,
      ttl: const Duration(hours: 24),
      maxSizeBytes: 1024 * 1024, // 1 MB for testing
      clock: () => fakeNow,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('put and get', () {
    test('stores and retrieves VideoInfo', () async {
      final info = makeVideoInfo('https://youtube.com/watch?v=abc', 'Test Video');

      await service.put('https://youtube.com/watch?v=abc', info);
      final cached = await service.get('https://youtube.com/watch?v=abc');

      expect(cached, isNotNull);
      expect(cached!.title, 'Test Video');
      expect(cached.url, 'https://youtube.com/watch?v=abc');
      expect(cached.availableQualities.length, 1);
    });

    test('returns null for uncached URL', () async {
      final cached = await service.get('https://youtube.com/watch?v=nonexistent');
      expect(cached, isNull);
    });

    test('overwrites existing entry', () async {
      final url = 'https://youtube.com/watch?v=abc';

      await service.put(url, makeVideoInfo(url, 'Version 1'));
      await service.put(url, makeVideoInfo(url, 'Version 2'));

      final cached = await service.get(url);
      expect(cached, isNotNull);
      expect(cached!.title, 'Version 2');
    });
  });

  group('contains', () {
    test('returns true for cached URL', () async {
      final url = 'https://youtube.com/watch?v=abc';
      await service.put(url, makeVideoInfo(url, 'Test'));

      expect(await service.contains(url), isTrue);
    });

    test('returns false for uncached URL', () async {
      expect(await service.contains('https://youtube.com/watch?v=nope'), isFalse);
    });
  });

  group('getCacheSize', () {
    test('returns 0 for empty cache', () async {
      expect(await service.getCacheSize(), 0);
    });

    test('returns total size after storing entries', () async {
      await service.put(
        'https://youtube.com/watch?v=a',
        makeVideoInfo('https://youtube.com/watch?v=a', 'Video A'),
      );

      final size = await service.getCacheSize();
      expect(size, greaterThan(0));
    });
  });

  group('getEntryCount', () {
    test('returns 0 for empty cache', () async {
      expect(await service.getEntryCount(), 0);
    });

    test('returns correct count', () async {
      await service.put(
        'https://youtube.com/watch?v=1',
        makeVideoInfo('https://youtube.com/watch?v=1', 'V1'),
      );
      await service.put(
        'https://youtube.com/watch?v=2',
        makeVideoInfo('https://youtube.com/watch?v=2', 'V2'),
      );

      expect(await service.getEntryCount(), 2);
    });
  });

  group('clear', () {
    test('removes all cached entries', () async {
      await service.put('https://a.com/1', makeVideoInfo('https://a.com/1', 'A'));
      await service.put('https://b.com/2', makeVideoInfo('https://b.com/2', 'B'));

      expect(await service.getEntryCount(), 2);

      await service.clear();

      expect(await service.getEntryCount(), 0);
      expect(await service.getCacheSize(), 0);
    });
  });

  group('pruneExpired', () {
    test('removes only expired entries', () async {
      await service.put('https://a.com/old', makeVideoInfo('https://a.com/old', 'Old'));

      // Advance time past TTL
      fakeNow = fakeNow.add(const Duration(hours: 25));

      // Add a fresh entry at new time
      await service.put('https://b.com/new', makeVideoInfo('https://b.com/new', 'New'));

      final removed = await service.pruneExpired();
      expect(removed, 1);
      expect(await service.getEntryCount(), 1);

      final cached = await service.get('https://b.com/new');
      expect(cached, isNotNull);
      expect(cached!.title, 'New');
    });
  });

  group('LRU eviction', () {
    test('evicts oldest entries when exceeding max size', () async {
      // Use very small max size for test
      service = ExtractionCacheService(
        tempDir.path,
        maxSizeBytes: 500, // Very small — will trigger eviction
        clock: () => fakeNow,
      );

      // Store entries with increasing timestamps
      for (int i = 0; i < 5; i++) {
        fakeNow = fakeNow.add(const Duration(seconds: 1));
        await service.put(
          'https://example.com/$i',
          makeVideoInfo('https://example.com/$i', 'Video $i'),
        );
      }

      // Some entries should have been evicted
      final count = await service.getEntryCount();
      expect(count, lessThan(5));
    });
  });

  group('URL normalization', () {
    test('same URL with different tracking params maps to same cache key', () async {
      final url1 = 'https://youtube.com/watch?v=abc';
      final url2 = 'https://youtube.com/watch?v=abc&utm_source=twitter';

      await service.put(url1, makeVideoInfo(url1, 'Video'));

      final cached = await service.get(url2);
      expect(cached, isNotNull);
      expect(cached!.title, 'Video');
    });

    test('different video IDs map to different cache keys', () async {
      final url1 = 'https://youtube.com/watch?v=abc';
      final url2 = 'https://youtube.com/watch?v=xyz';

      await service.put(url1, makeVideoInfo(url1, 'Video ABC'));

      final cached = await service.get(url2);
      expect(cached, isNull);
    });
  });

  group('formatSize', () {
    test('formats bytes correctly', () {
      expect(ExtractionCacheService.formatSize(0), '0 B');
      expect(ExtractionCacheService.formatSize(512), '512 B');
      expect(ExtractionCacheService.formatSize(1024), '1.0 KB');
      expect(ExtractionCacheService.formatSize(1536), '1.5 KB');
      expect(ExtractionCacheService.formatSize(1048576), '1.0 MB');
      expect(ExtractionCacheService.formatSize(1073741824), '1.0 GB');
    });
  });

  group('error handling', () {
    test('handles corrupted JSON gracefully', () async {
      // Use a non-YouTube URL to avoid canonicalization mismatch
      // (service canonicalizes youtube.com → www.youtube.com, changing the hash)
      final url = 'https://example.com/video/corrupt';
      final hash = _hashUrl(url);
      final filePath = '${tempDir.path}/$hash.info.json';
      await File(filePath).writeAsString('{invalid json!!!');

      final cached = await service.get(url);
      expect(cached, isNull);

      // File should be deleted
      expect(await File(filePath).exists(), isFalse);
    });

    test('handles missing cache directory gracefully', () async {
      final nonExistentService = ExtractionCacheService(
        '${tempDir.path}/nonexistent',
        clock: () => fakeNow,
      );

      expect(await nonExistentService.getCacheSize(), 0);
      expect(await nonExistentService.getEntryCount(), 0);
      expect(await nonExistentService.get('https://example.com'), isNull);
    });
  });
}
