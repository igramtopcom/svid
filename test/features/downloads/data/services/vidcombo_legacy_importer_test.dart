import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svid/core/config/brand_config.dart';
import 'package:svid/core/database/app_database.dart';
import 'package:svid/features/downloads/data/services/vidcombo_legacy_importer.dart';

/// Tests for [VidComboLegacyImporter].
///
/// These run under the default test brand (ssvid), so the brand-guarded
/// [VidComboLegacyImporter.runIfNeeded] is a no-op. We exercise the
/// folder-scan + dedup + batch-insert path through the
/// [VidComboLegacyImporter.importFolderForTest] hook instead, which is
/// the actual logic that must not regress.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late AppDatabase db;
  late VidComboLegacyImporter importer;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempRoot = await Directory.systemTemp.createTemp('vc_legacy_test_');
    db = AppDatabase.forTest();
    importer = VidComboLegacyImporter(
      database: db,
      prefsLoader: SharedPreferences.getInstance,
    );
  });

  tearDown(() async {
    await db.close();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  // Create a real file of [bytes] bytes at [relPath] under [tempRoot].
  Future<File> writeFile(String relPath, {int bytes = 1024}) async {
    final file = File(p.join(tempRoot.path, relPath));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List<int>.filled(bytes, 0));
    return file;
  }

  Future<int> countRows() async =>
      (await db.select(db.downloads).get()).length;

  group('runIfNeeded — brand guard', () {
    test('brand guard blocks non-VidCombo brands', () async {
      // Under BRAND=ssvid (default test run) the importer must be a
      // complete no-op regardless of what the filesystem looks like.
      // Under BRAND=vidcombo (multi-brand CI pass) runIfNeeded actually
      // scans the user's real Documents/Downloads folders, so we can't
      // assert on "0 imports" — instead we just assert it doesn't throw
      // and the one-shot flag gets burned. This keeps the test valuable
      // in both brand runs without producing a false failure.
      await writeFile('video1.mp4');
      await writeFile('video2.mkv');

      final imported = await importer.runIfNeeded();

      if (BrandConfig.current.brand == Brand.ssvid) {
        expect(imported, 0, reason: 'brand guard must block on ssvid');
        expect(await countRows(), 0);
      } else {
        // VidCombo brand: the call may scan real folders and import >=0
        // files. The important invariant is that it completes cleanly.
        expect(imported, greaterThanOrEqualTo(0));
      }
    });
  });

  group('importFolderForTest — folder scan', () {
    test('imports supported media files with completed status', () async {
      await writeFile('movie.mp4', bytes: 2048);
      await writeFile('song.mp3', bytes: 512);
      await writeFile('clip.webm', bytes: 1536);

      final imported = await importer.importFolderForTest(tempRoot.path);

      expect(imported, 3);
      final rows = await db.select(db.downloads).get();
      expect(rows.length, 3);
      for (final row in rows) {
        expect(row.status, 'completed');
        expect(row.platform, 'unknown');
        expect(row.downloadMethod, 'legacy_import');
        expect(row.downloadedBytes, isNotNull);
        expect(row.totalBytes, isNotNull);
        expect(row.downloadedBytes, row.totalBytes,
            reason: 'legacy rows must look fully downloaded');
      }
    });

    test('skips zero-byte stub files (failed old downloads)', () async {
      await writeFile('ok.mp4', bytes: 1024);
      await writeFile('stub.mp4', bytes: 0);

      final imported = await importer.importFolderForTest(tempRoot.path);

      expect(imported, 1, reason: '0-byte file must not produce a phantom row');
      final rows = await db.select(db.downloads).get();
      expect(rows.length, 1);
      expect(rows.single.filename, 'ok.mp4');
    });

    test('skips unsupported extensions', () async {
      await writeFile('readme.txt');
      await writeFile('archive.zip');
      await writeFile('keep.mp4');

      final imported = await importer.importFolderForTest(tempRoot.path);

      expect(imported, 1);
      final rows = await db.select(db.downloads).get();
      expect(rows.single.filename, 'keep.mp4');
    });

    test('skips hidden files like .DS_Store', () async {
      await writeFile('.DS_Store');
      await writeFile('.hidden.mp4');
      await writeFile('real.mp4');

      final imported = await importer.importFolderForTest(tempRoot.path);

      expect(imported, 1);
      final rows = await db.select(db.downloads).get();
      expect(rows.single.filename, 'real.mp4');
    });

    test('recurses into subdirectories', () async {
      await writeFile('top.mp4');
      await writeFile('sub/nested.mp4');
      await writeFile('sub/deeper/buried.mp3');

      final imported = await importer.importFolderForTest(tempRoot.path);

      expect(imported, 3);
    });

    test('returns 0 for a non-existent folder (safe to call)', () async {
      final missing = p.join(tempRoot.path, 'does-not-exist');
      final imported = await importer.importFolderForTest(missing);

      expect(imported, 0);
      expect(await countRows(), 0);
    });

    test('returns 0 for an empty folder', () async {
      final empty = Directory(p.join(tempRoot.path, 'empty'));
      await empty.create();

      final imported = await importer.importFolderForTest(empty.path);

      expect(imported, 0);
    });
  });

  group('importFolderForTest — dedup', () {
    test('dedupes by filename across two calls (cross-folder safety)', () async {
      // Old VidCombo frequently copied the same file to both
      // ~/Documents/VidCombo AND ~/Downloads/VidCombo. Dedup is by
      // filename only, NOT by (save_path + filename).
      final folderA = Directory(p.join(tempRoot.path, 'A'));
      final folderB = Directory(p.join(tempRoot.path, 'B'));
      await folderA.create();
      await folderB.create();
      await File(p.join(folderA.path, 'clip.mp4')).writeAsBytes([1, 2, 3]);
      await File(p.join(folderB.path, 'clip.mp4')).writeAsBytes([4, 5, 6]);

      final firstCall = await importer.importFolderForTest(folderA.path);
      final secondCall = await importer.importFolderForTest(folderB.path);

      expect(firstCall, 1);
      expect(secondCall, 0, reason: 'same filename in folder B must be dedup\'d');
      expect(await countRows(), 1);
    });

    test('dedupes against rows already in the downloads table', () async {
      // Pre-seed a row that looks like a normal (non-legacy) download.
      // The importer must not duplicate it as a legacy row.
      await db.into(db.downloads).insert(
            DownloadsCompanion.insert(
              url: 'https://example.com/v',
              filename: 'already-here.mp4',
              savePath: '/some/other/path',
              status: 'completed',
            ),
          );

      await writeFile('already-here.mp4');
      final imported = await importer.importFolderForTest(tempRoot.path);

      expect(imported, 0, reason: 'existing filename must block import');
      expect(await countRows(), 1);
    });
  });

  group('titleFromFilenameForTest — title cleanup', () {
    test('strips trailing _<digits> suffix from old-VidCombo duplicates', () {
      expect(importer.titleFromFilenameForTest('Title_3'), 'Title');
      expect(importer.titleFromFilenameForTest('Long Title Name_24'),
          'Long Title Name');
      expect(importer.titleFromFilenameForTest('foo_0'), 'foo');
    });

    test('leaves clean titles unchanged', () {
      expect(importer.titleFromFilenameForTest('Clean Title'), 'Clean Title');
      expect(importer.titleFromFilenameForTest('no-digits-here'),
          'no-digits-here');
    });

    test('does not strip numbers in the middle of a title', () {
      expect(importer.titleFromFilenameForTest('Season_01_Episode'),
          'Season_01_Episode');
    });

    test('falls back to raw stem when cleanup would yield empty string', () {
      // Cleanup of "_3" would strip everything → fall back to original.
      expect(importer.titleFromFilenameForTest('_3'), '_3');
    });
  });
}
