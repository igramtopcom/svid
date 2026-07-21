import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/core/database/app_database.dart';
import 'package:ssvid/features/downloads/domain/services/tagging_service.dart';

// ---------------------------------------------------------------------------
// Tests for AppDatabase.watchAllTagsMap() and TaggingService.watchAllTagsMap()
// ---------------------------------------------------------------------------

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

  // Helper: insert a minimal download row to satisfy FK constraint.
  Future<int> insertDownload({String url = 'https://example.com/video.mp4'}) {
    return db.insertDownload(
      DownloadsCompanion.insert(
        url: url,
        filename: 'video.mp4',
        savePath: '/tmp',
        status: 'pending',
      ),
    );
  }

  // -------------------------------------------------------------------------
  // AppDatabase.watchAllTagsMap
  // -------------------------------------------------------------------------

  group('AppDatabase.watchAllTagsMap', () {
    test('emits empty map when no tags exist', () async {
      await insertDownload();
      final map = await db.watchAllTagsMap().first;
      expect(map, isEmpty);
    });

    test('emits map with tags after insertion', () async {
      final id = await insertDownload();
      await db.insertTag(id, 'music');
      await db.insertTag(id, 'chill');

      final map = await db.watchAllTagsMap().first;
      expect(map[id], containsAll(['music', 'chill']));
    });

    test('groups tags by downloadId correctly', () async {
      final id1 = await insertDownload(url: 'https://example.com/v1.mp4');
      final id2 = await insertDownload(url: 'https://example.com/v2.mp4');
      await db.insertTag(id1, 'action');
      await db.insertTag(id2, 'comedy');

      final map = await db.watchAllTagsMap().first;
      expect(map[id1], equals(['action']));
      expect(map[id2], equals(['comedy']));
    });

    test('emits updated map after tag deletion', () async {
      final id = await insertDownload();
      await db.insertTag(id, 'keep');
      await db.insertTag(id, 'remove');
      await db.deleteTag(id, 'remove');

      final map = await db.watchAllTagsMap().first;
      expect(map[id], equals(['keep']));
      expect(map[id], isNot(contains('remove')));
    });

    test('stream updates after tag is added', () async {
      final id = await insertDownload();

      // Collect 2 emissions: initial (empty) + after insert
      final emissions = db.watchAllTagsMap().take(2);
      final collected = <Map<int, List<String>>>[];

      final done = emissions.listen(collected.add).asFuture();

      // Insert tag after subscribing
      await Future.delayed(const Duration(milliseconds: 10));
      await db.insertTag(id, 'jazz');

      await done;
      expect(collected.first, isEmpty);
      expect(collected.last[id], contains('jazz'));
    });
  });

  // -------------------------------------------------------------------------
  // TaggingService.watchAllTagsMap
  // -------------------------------------------------------------------------

  group('TaggingService.watchAllTagsMap', () {
    test('delegates to database and returns stream', () async {
      final id = await insertDownload();
      await svc.addTag(id, 'rock');

      final map = await svc.watchAllTagsMap().first;
      expect(map[id], contains('rock'));
    });

    test('reflects tag removal', () async {
      final id = await insertDownload();
      await svc.addTag(id, 'pop');
      await svc.removeTag(id, 'pop');

      final map = await svc.watchAllTagsMap().first;
      expect(map[id] ?? [], isNot(contains('pop')));
    });

    test('normalizes tags before storage (visible via stream)', () async {
      final id = await insertDownload();
      await svc.addTag(id, '  JAZZ  ');

      final map = await svc.watchAllTagsMap().first;
      // Normalized: lowercase, trimmed
      expect(map[id], contains('jazz'));
      expect(map[id], isNot(contains('JAZZ')));
    });
  });

  // -------------------------------------------------------------------------
  // StreamProvider type-compatibility (regression guard)
  // -------------------------------------------------------------------------

  group('tagsMapProvider emits correct type', () {
    test('watchAllTagsMap returns Stream of Map', () {
      final stream = db.watchAllTagsMap();
      expect(stream, isA<Stream<Map<int, List<String>>>>());
    });
  });
}
