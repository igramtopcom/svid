import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/database/app_database.dart';
import 'package:svid/features/downloads/domain/services/batch_file_operations_service.dart';

void main() {
  late AppDatabase db;
  late BatchFileOperationsService svc;

  setUp(() {
    db = AppDatabase.forTest();
    svc = BatchFileOperationsService();
  });

  tearDown(() async {
    await db.close();
  });

  // ---------------------------------------------------------------------------
  // Helper
  // ---------------------------------------------------------------------------

  Future<int> insertDownload({
    String url = 'https://example.com/video.mp4',
    String filename = 'video.mp4',
    String savePath = '/tmp',
    String status = 'completed',
    String? title,
    String? uploader,
    String? uploadDate,
  }) =>
      db.insertDownload(
        DownloadsCompanion.insert(
          url: url,
          filename: filename,
          savePath: savePath,
          status: status,
          title: title != null ? Value(title) : const Value.absent(),
          uploader: uploader != null ? Value(uploader) : const Value.absent(),
          uploadDate:
              uploadDate != null ? Value(uploadDate) : const Value.absent(),
        ),
      );

  Future<Download?> fetchRow(int id) =>
      (db.select(db.downloads)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  // ---------------------------------------------------------------------------
  // applyPattern — pure, no DB
  // ---------------------------------------------------------------------------

  group('applyPattern', () {
    test('replaces {title} token', () {
      expect(
        svc.applyPattern('{title}',
            filename: 'v.mp4', title: 'My Video', index: 1),
        equals('My Video'),
      );
    });

    test('replaces {uploader} token', () {
      expect(
        svc.applyPattern('{uploader}',
            filename: 'v.mp4', uploader: 'Creator', index: 1),
        equals('Creator'),
      );
    });

    test('replaces {index} token', () {
      expect(
        svc.applyPattern('{index}', filename: 'v.mp4', index: 7),
        equals('7'),
      );
    });

    test('replaces {date} token when uploadDate is 8 digits', () {
      expect(
        svc.applyPattern('{date}',
            filename: 'v.mp4', uploadDate: '20241231', index: 1),
        equals('2024-12-31'),
      );
    });

    test('{date} is empty string when uploadDate is null', () {
      expect(
        svc.applyPattern('{date}', filename: 'v.mp4', index: 1),
        equals(''),
      );
    });

    test('{date} is empty string when uploadDate is not 8 digits', () {
      expect(
        svc.applyPattern('{date}',
            filename: 'v.mp4', uploadDate: 'short', index: 1),
        equals(''),
      );
    });

    test('multiple tokens replaced in one pattern', () {
      final result = svc.applyPattern(
        '{title} - {uploader} [{index}]',
        filename: 'v.mp4',
        title: 'Cool Video',
        uploader: 'JohnDoe',
        index: 3,
      );
      expect(result, equals('Cool Video - JohnDoe [3]'));
    });

    test('falls back to filename stem when title is null', () {
      expect(
        svc.applyPattern('{title}', filename: 'video_stem.mp4', index: 1),
        equals('video_stem'),
      );
    });

    test('falls back to filename stem when title is empty', () {
      expect(
        svc.applyPattern('{title}',
            filename: 'video_stem.mp4', title: '', index: 1),
        equals('video_stem'),
      );
    });

    test('falls back to "unknown" when uploader is null', () {
      expect(
        svc.applyPattern('{uploader}', filename: 'v.mp4', index: 1),
        equals('unknown'),
      );
    });

    test('empty string uploader falls back to "unknown"', () {
      expect(
        svc.applyPattern('{uploader}',
            filename: 'v.mp4', uploader: '', index: 1),
        equals('unknown'),
      );
    });

    test('literal text without tokens is returned as-is', () {
      expect(
        svc.applyPattern('fixed_name', filename: 'v.mp4', index: 1),
        equals('fixed_name'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // deleteFiles
  // ---------------------------------------------------------------------------

  group('deleteFiles', () {
    test('empty ids returns allSucceeded with zero counts', () async {
      final result = await svc.deleteFiles([], db: db);
      expect(result.allSucceeded, isTrue);
      expect(result.succeeded, equals(0));
      expect(result.failed, equals(0));
    });

    test('deletes record from DB', () async {
      final id = await insertDownload();
      expect(await fetchRow(id), isNotNull);

      final result =
          await svc.deleteFiles([id], db: db, deleteFromDisk: false);

      expect(result.succeeded, equals(1));
      expect(result.failed, equals(0));
      expect(await fetchRow(id), isNull);
    });

    test('non-existent id increments failed count', () async {
      final result =
          await svc.deleteFiles([9999], db: db, deleteFromDisk: false);
      expect(result.failed, equals(1));
      expect(result.errors, isNotEmpty);
    });

    test('deletes multiple records', () async {
      final id1 = await insertDownload(url: 'https://a.com/1.mp4');
      final id2 = await insertDownload(url: 'https://a.com/2.mp4');

      final result =
          await svc.deleteFiles([id1, id2], db: db, deleteFromDisk: false);

      expect(result.succeeded, equals(2));
      expect(await fetchRow(id1), isNull);
      expect(await fetchRow(id2), isNull);
    });

    test('partial success when some ids missing', () async {
      final id = await insertDownload();

      final result = await svc.deleteFiles([id, 9999], db: db, deleteFromDisk: false);

      expect(result.succeeded, equals(1));
      expect(result.failed, equals(1));
    });

    test('deleteFromDisk=true on non-completed file skips disk delete', () async {
      final id =
          await insertDownload(status: 'pending', savePath: '/nonexistent');
      final result = await svc.deleteFiles([id], db: db, deleteFromDisk: true);
      expect(result.succeeded, equals(1));
      expect(await fetchRow(id), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // moveFiles
  // ---------------------------------------------------------------------------

  group('moveFiles', () {
    test('empty ids returns allSucceeded', () async {
      final result = await svc.moveFiles([], '/target', db: db);
      expect(result.allSucceeded, isTrue);
      expect(result.succeeded, equals(0));
    });

    test('updates savePath in DB for completed download', () async {
      final id = await insertDownload(savePath: '/original');

      final result = await svc.moveFiles([id], '/new/path', db: db);

      expect(result.succeeded, equals(1));
      final row = await fetchRow(id);
      expect(row?.savePath, equals('/new/path'));
    });

    test('updates savePath even for non-completed download (no file to move)',
        () async {
      final id = await insertDownload(status: 'pending', savePath: '/old');

      final result = await svc.moveFiles([id], '/new', db: db);

      expect(result.succeeded, equals(1));
      final row = await fetchRow(id);
      expect(row?.savePath, equals('/new'));
    });

    test('non-existent id increments failed count', () async {
      final result = await svc.moveFiles([9999], '/target', db: db);
      expect(result.failed, equals(1));
    });

    test('moves multiple downloads', () async {
      final id1 = await insertDownload(url: 'https://a.com/1.mp4');
      final id2 = await insertDownload(url: 'https://a.com/2.mp4');

      final result = await svc.moveFiles([id1, id2], '/bulk_target', db: db);

      expect(result.succeeded, equals(2));
      expect((await fetchRow(id1))?.savePath, equals('/bulk_target'));
      expect((await fetchRow(id2))?.savePath, equals('/bulk_target'));
    });
  });

  // ---------------------------------------------------------------------------
  // renameFiles
  // ---------------------------------------------------------------------------

  group('renameFiles', () {
    test('empty ids returns allSucceeded', () async {
      final result = await svc.renameFiles([], '{title}', db: db);
      expect(result.allSucceeded, isTrue);
      expect(result.succeeded, equals(0));
    });

    test('updates filename in DB using title token', () async {
      final id = await insertDownload(
        filename: 'original.mp4',
        title: 'Great Video',
        status: 'pending',
      );

      final result = await svc.renameFiles([id], '{title}', db: db);

      expect(result.succeeded, equals(1));
      final row = await fetchRow(id);
      expect(row?.filename, equals('Great Video.mp4'));
    });

    test('preserves file extension', () async {
      final id = await insertDownload(
        filename: 'clip.mkv',
        title: 'New Name',
        status: 'pending',
      );

      await svc.renameFiles([id], '{title}', db: db);

      final row = await fetchRow(id);
      expect(row?.filename, endsWith('.mkv'));
    });

    test('uses index token with correct 1-based numbering', () async {
      final id1 = await insertDownload(url: 'https://a.com/1.mp4', filename: 'a.mp4');
      final id2 = await insertDownload(url: 'https://a.com/2.mp4', filename: 'b.mp4');

      await svc.renameFiles([id1, id2], 'track_{index}', db: db);

      expect((await fetchRow(id1))?.filename, equals('track_1.mp4'));
      expect((await fetchRow(id2))?.filename, equals('track_2.mp4'));
    });

    test('no-op when new filename equals old filename', () async {
      final id = await insertDownload(filename: 'fixed_name.mp4');
      final result = await svc.renameFiles([id], 'fixed_name', db: db);
      expect(result.succeeded, equals(1));
    });

    test('non-existent id increments failed count', () async {
      final result = await svc.renameFiles([9999], '{title}', db: db);
      expect(result.failed, equals(1));
    });

    test('sanitizes illegal chars in renamed file', () async {
      final id = await insertDownload(
        filename: 'vid.mp4',
        title: 'My: Movie/Cut',
        status: 'pending',
      );

      await svc.renameFiles([id], '{title}', db: db);

      final row = await fetchRow(id);
      expect(row?.filename, isNotNull);
      expect(row!.filename, isNot(contains(':')));
      expect(row.filename, isNot(contains('/')));
    });
  });

  // ---------------------------------------------------------------------------
  // BatchResult helpers
  // ---------------------------------------------------------------------------

  group('BatchResult', () {
    test('allSucceeded is true when failed == 0', () {
      expect(
          const BatchResult(succeeded: 5, failed: 0, errors: []).allSucceeded,
          isTrue);
    });

    test('allSucceeded is false when failed > 0', () {
      expect(
          const BatchResult(succeeded: 3, failed: 1, errors: []).allSucceeded,
          isFalse);
    });

    test('toString includes counts', () {
      final r =
          const BatchResult(succeeded: 2, failed: 1, errors: ['e']);
      expect(r.toString(), contains('succeeded: 2'));
      expect(r.toString(), contains('failed: 1'));
    });

    test('equality is by succeeded and failed', () {
      const a = BatchResult(succeeded: 3, failed: 0, errors: []);
      const b = BatchResult(succeeded: 3, failed: 0, errors: ['x']);
      expect(a, equals(b));
    });
  });
}
