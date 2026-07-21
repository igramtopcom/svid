import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/core/database/app_database.dart';
import 'package:ssvid/features/downloads/domain/services/tagging_service.dart';

void main() {
  late AppDatabase db;
  late TaggingService svc;

  setUp(() {
    db = AppDatabase.forTest();
    svc = TaggingService(db);
  });

  tearDown(() async {
    await db.close();
  });

  // Helper: insert a minimal download row to satisfy the FK constraint.
  Future<int> insertDownload() async {
    return db.insertDownload(
      DownloadsCompanion.insert(
        url: 'https://example.com/video.mp4',
        filename: 'video.mp4',
        savePath: '/tmp',
        status: 'pending',
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // normalizeTag
  // ---------------------------------------------------------------------------

  group('normalizeTag', () {
    test('trims whitespace', () {
      expect(normalizeTag('  hello  '), equals('hello'));
    });

    test('lowercases', () {
      expect(normalizeTag('MUSIC'), equals('music'));
    });

    test('trims + lowercases together', () {
      expect(normalizeTag('  FaVoRiTe  '), equals('favorite'));
    });

    test('truncates to 30 characters', () {
      final long = 'a' * 40;
      expect(normalizeTag(long).length, equals(30));
    });

    test('returns empty string for blank input', () {
      expect(normalizeTag('   '), equals(''));
    });

    test('returns empty string for empty input', () {
      expect(normalizeTag(''), equals(''));
    });
  });

  // ---------------------------------------------------------------------------
  // TaggingService.addTag
  // ---------------------------------------------------------------------------

  group('addTag', () {
    test('returns normalized tag and persists it', () async {
      final id = await insertDownload();

      final result = await svc.addTag(id, '  MyTag  ');

      expect(result, equals('mytag'));
      final tags = await svc.getTagsForDownload(id);
      expect(tags, contains('mytag'));
    });

    test('returns null for blank tag', () async {
      final id = await insertDownload();
      final result = await svc.addTag(id, '   ');
      expect(result, isNull);
    });

    test('deduplicates silently', () async {
      final id = await insertDownload();
      await svc.addTag(id, 'music');
      await svc.addTag(id, 'music');
      final tags = await svc.getTagsForDownload(id);
      expect(tags.where((t) => t == 'music').length, equals(1));
    });
  });

  // ---------------------------------------------------------------------------
  // TaggingService.removeTag
  // ---------------------------------------------------------------------------

  group('removeTag', () {
    test('removes existing tag', () async {
      final id = await insertDownload();
      await svc.addTag(id, 'sport');
      await svc.removeTag(id, 'sport');
      final tags = await svc.getTagsForDownload(id);
      expect(tags, isEmpty);
    });

    test('no-op for non-existent tag', () async {
      final id = await insertDownload();
      await svc.addTag(id, 'music');
      await svc.removeTag(id, 'ghost');
      final tags = await svc.getTagsForDownload(id);
      expect(tags, equals(['music']));
    });

    test('normalizes before remove', () async {
      final id = await insertDownload();
      await svc.addTag(id, 'study');
      await svc.removeTag(id, '  STUDY  ');
      final tags = await svc.getTagsForDownload(id);
      expect(tags, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // TaggingService.getTagsForDownload
  // ---------------------------------------------------------------------------

  group('getTagsForDownload', () {
    test('returns empty list when no tags', () async {
      final id = await insertDownload();
      final tags = await svc.getTagsForDownload(id);
      expect(tags, isEmpty);
    });

    test('returns tags in alphabetical order', () async {
      final id = await insertDownload();
      await svc.addTag(id, 'zebra');
      await svc.addTag(id, 'apple');
      await svc.addTag(id, 'mango');
      final tags = await svc.getTagsForDownload(id);
      expect(tags, equals(['apple', 'mango', 'zebra']));
    });
  });

  // ---------------------------------------------------------------------------
  // TaggingService.getAllTags
  // ---------------------------------------------------------------------------

  group('getAllTags', () {
    test('returns distinct tags across downloads', () async {
      final id1 = await insertDownload();
      final id2 = await insertDownload();
      await svc.addTag(id1, 'music');
      await svc.addTag(id2, 'music');
      await svc.addTag(id2, 'sport');
      final all = await svc.getAllTags();
      expect(all, containsAll(['music', 'sport']));
      expect(all.where((t) => t == 'music').length, equals(1)); // distinct
    });
  });

  // ---------------------------------------------------------------------------
  // TaggingService.getDownloadsByTag
  // ---------------------------------------------------------------------------

  group('getDownloadsByTag', () {
    test('returns download IDs with given tag', () async {
      final id1 = await insertDownload();
      final id2 = await insertDownload();
      await svc.addTag(id1, 'travel');
      await svc.addTag(id2, 'music');
      final ids = await svc.getDownloadsByTag('travel');
      expect(ids, contains(id1));
      expect(ids, isNot(contains(id2)));
    });

    test('returns empty list for blank tag', () async {
      final result = await svc.getDownloadsByTag('   ');
      expect(result, isEmpty);
    });

    test('normalizes tag before querying', () async {
      final id = await insertDownload();
      await svc.addTag(id, 'fitness');
      final ids = await svc.getDownloadsByTag('  FITNESS  ');
      expect(ids, contains(id));
    });
  });

  // ---------------------------------------------------------------------------
  // TaggingService.getAllTagsMap
  // ---------------------------------------------------------------------------

  group('getAllTagsMap', () {
    test('returns map with tags per download', () async {
      final id1 = await insertDownload();
      final id2 = await insertDownload();
      await svc.addTag(id1, 'music');
      await svc.addTag(id1, 'sport');
      await svc.addTag(id2, 'travel');

      final map = await svc.getAllTagsMap();

      expect(map[id1], containsAll(['music', 'sport']));
      expect(map[id2], equals(['travel']));
    });

    test('returns empty map when no tags exist', () async {
      final map = await svc.getAllTagsMap();
      expect(map, isEmpty);
    });
  });
}
