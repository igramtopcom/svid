import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/domain/entities/collection_entity.dart';
import 'package:ssvid/features/downloads/domain/entities/download_entity.dart';
import 'package:ssvid/features/downloads/domain/entities/download_status.dart';

DownloadEntity _entity({
  int id = 1,
  String platform = 'youtube',
  DownloadStatus status = DownloadStatus.completed,
}) =>
    DownloadEntity(
      id: id,
      url: 'https://example.com/video',
      filename: 'video.mp4',
      savePath: '/Downloads/video.mp4',
      status: status,
      totalBytes: 1000,
      downloadedBytes: 1000,
      speed: 0,
      platform: platform,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  // ── CollectionFilter ─────────────────────────────────────────────────────

  group('CollectionFilter.isEmpty', () {
    test('returns true when all fields empty', () {
      expect(const CollectionFilter().isEmpty, isTrue);
    });

    test('returns false when platforms not empty', () {
      expect(
        const CollectionFilter(platforms: ['youtube']).isEmpty,
        isFalse,
      );
    });

    test('returns false when statuses not empty', () {
      expect(
        const CollectionFilter(statuses: ['completed']).isEmpty,
        isFalse,
      );
    });

    test('returns false when tags not empty', () {
      expect(
        const CollectionFilter(tags: ['music']).isEmpty,
        isFalse,
      );
    });
  });

  group('CollectionFilter JSON', () {
    test('round-trips through toJson/fromJson', () {
      const filter = CollectionFilter(
        platforms: ['youtube', 'tiktok'],
        statuses: ['completed'],
        tags: ['music', 'favorites'],
      );
      final json = filter.toJson();
      final restored = CollectionFilter.fromJson(json);
      expect(restored.platforms, filter.platforms);
      expect(restored.statuses, filter.statuses);
      expect(restored.tags, filter.tags);
    });

    test('fromJson defaults to empty lists when fields missing', () {
      final filter = CollectionFilter.fromJson({});
      expect(filter.platforms, isEmpty);
      expect(filter.statuses, isEmpty);
      expect(filter.tags, isEmpty);
    });
  });

  // ── CollectionEntity.matchesFilter ────────────────────────────────────────

  group('CollectionEntity.matchesFilter', () {
    final baseCollection = CollectionEntity(
      id: '1',
      name: 'Test',
      filter: const CollectionFilter(),
      createdAt: DateTime(2026, 1, 1),
    );

    test('empty filter matches any download', () {
      final download = _entity(platform: 'vimeo', status: DownloadStatus.failed);
      expect(baseCollection.matchesFilter(download, {}), isTrue);
    });

    test('platform filter matches exact platform', () {
      final c = baseCollection.copyWith(
        filter: const CollectionFilter(platforms: ['youtube']),
      );
      expect(c.matchesFilter(_entity(platform: 'youtube'), {}), isTrue);
    });

    test('platform filter rejects wrong platform', () {
      final c = baseCollection.copyWith(
        filter: const CollectionFilter(platforms: ['youtube']),
      );
      expect(c.matchesFilter(_entity(platform: 'tiktok'), {}), isFalse);
    });

    test('platform filter is case-insensitive', () {
      final c = baseCollection.copyWith(
        filter: const CollectionFilter(platforms: ['YouTube']),
      );
      expect(c.matchesFilter(_entity(platform: 'youtube'), {}), isTrue);
      expect(c.matchesFilter(_entity(platform: 'YOUTUBE'), {}), isTrue);
    });

    test('status filter matches correct status', () {
      final c = baseCollection.copyWith(
        filter: const CollectionFilter(statuses: ['completed']),
      );
      expect(
        c.matchesFilter(_entity(status: DownloadStatus.completed), {}),
        isTrue,
      );
    });

    test('status filter rejects wrong status', () {
      final c = baseCollection.copyWith(
        filter: const CollectionFilter(statuses: ['completed']),
      );
      expect(
        c.matchesFilter(_entity(status: DownloadStatus.failed), {}),
        isFalse,
      );
    });

    test('tags filter matches when download has all required tags', () {
      final c = baseCollection.copyWith(
        filter: const CollectionFilter(tags: ['music', 'favorites']),
      );
      final tagsMap = {
        1: ['music', 'favorites', 'extra'],
      };
      expect(c.matchesFilter(_entity(id: 1), tagsMap), isTrue);
    });

    test('tags filter rejects when download is missing a required tag', () {
      final c = baseCollection.copyWith(
        filter: const CollectionFilter(tags: ['music', 'favorites']),
      );
      final tagsMap = {
        1: ['music'],
      };
      expect(c.matchesFilter(_entity(id: 1), tagsMap), isFalse);
    });

    test('tags filter with empty tagsMap returns false', () {
      final c = baseCollection.copyWith(
        filter: const CollectionFilter(tags: ['music']),
      );
      expect(c.matchesFilter(_entity(id: 1), {}), isFalse);
    });

    test('AND logic: both platform and status must match', () {
      final c = baseCollection.copyWith(
        filter: const CollectionFilter(
          platforms: ['youtube'],
          statuses: ['completed'],
        ),
      );
      // Both match
      expect(
        c.matchesFilter(
          _entity(platform: 'youtube', status: DownloadStatus.completed),
          {},
        ),
        isTrue,
      );
      // Platform matches, status doesn't
      expect(
        c.matchesFilter(
          _entity(platform: 'youtube', status: DownloadStatus.failed),
          {},
        ),
        isFalse,
      );
      // Status matches, platform doesn't
      expect(
        c.matchesFilter(
          _entity(platform: 'tiktok', status: DownloadStatus.completed),
          {},
        ),
        isFalse,
      );
    });
  });

  // ── CollectionEntity.itemCount ────────────────────────────────────────────

  group('CollectionEntity.itemCount', () {
    test('returns 0 for empty downloads list', () {
      final c = CollectionEntity(
        id: '1',
        name: 'Test',
        filter: const CollectionFilter(),
        createdAt: DateTime(2026, 1, 1),
      );
      expect(c.itemCount([], {}), 0);
    });

    test('counts only matching downloads', () {
      final c = CollectionEntity(
        id: '1',
        name: 'YouTube Only',
        filter: const CollectionFilter(platforms: ['youtube']),
        createdAt: DateTime(2026, 1, 1),
      );
      final downloads = [
        _entity(id: 1, platform: 'youtube'),
        _entity(id: 2, platform: 'tiktok'),
        _entity(id: 3, platform: 'youtube'),
      ];
      expect(c.itemCount(downloads, {}), 2);
    });
  });

  // ── CollectionEntity JSON ─────────────────────────────────────────────────

  group('CollectionEntity JSON', () {
    test('round-trips through toJson/fromJson', () {
      final entity = CollectionEntity(
        id: 'abc-123',
        name: 'My Collection',
        description: 'Test description',
        filter: const CollectionFilter(
          platforms: ['youtube'],
          statuses: ['completed'],
        ),
        createdAt: DateTime(2026, 3, 1),
      );
      final json = entity.toJson();
      final restored = CollectionEntity.fromJson(json);
      expect(restored.id, entity.id);
      expect(restored.name, entity.name);
      expect(restored.description, entity.description);
      expect(restored.filter.platforms, entity.filter.platforms);
      expect(restored.filter.statuses, entity.filter.statuses);
      expect(restored.createdAt, entity.createdAt);
    });

    test('fromJson with missing description defaults to empty string', () {
      final json = {
        'id': 'x',
        'name': 'Test',
        'filter': {'platforms': [], 'statuses': [], 'tags': []},
        'createdAt': '2026-01-01T00:00:00.000',
      };
      final entity = CollectionEntity.fromJson(json);
      expect(entity.description, '');
    });
  });
}
