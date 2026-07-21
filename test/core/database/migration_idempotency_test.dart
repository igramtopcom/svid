import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw_sqlite;
import 'package:svid/core/database/app_database.dart';

// ---------------------------------------------------------------------------
// Regression test for the 2026-04-07 production incident.
//
// Failure mode: a previous AppDatabase open ran the v15→v16 migration, the
// `addColumn(temp_dir_path)` succeeded and persisted to disk, but Drift never
// got around to bumping `user_version` from 15 to 16 (process killed, app
// force-quit, etc.). On the next launch, Drift saw user_version=15 and re-ran
// the v15→v16 migration. SQLite threw "duplicate column name: temp_dir_path",
// the migration aborted, the database became unopenable, and the downloads UI
// went empty for users with real data on disk.
//
// The fix wraps every onUpgrade DDL in `_safeAddColumn` / `_safeCreateTable`,
// catching the duplicate-column / table-already-exists errors and treating
// "column/table already present" as the desired end state. This test locks
// that contract in.
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppDatabase migration idempotency', () {
    // SQL to create the v15 schema. Mirrors what Drift would have produced
    // when schemaVersion was 15. Includes every column added between v1-v15.
    // Defaults match the table definitions in app_database.dart.
    const createDownloadsV15 = '''
      CREATE TABLE downloads (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        url TEXT NOT NULL,
        filename TEXT NOT NULL,
        save_path TEXT NOT NULL,
        status TEXT NOT NULL,
        total_bytes INTEGER NOT NULL DEFAULT 0,
        downloaded_bytes INTEGER NOT NULL DEFAULT 0,
        speed INTEGER NOT NULL DEFAULT 0,
        thumbnail TEXT,
        platform TEXT NOT NULL DEFAULT 'unknown',
        created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0,
        error_message TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0,
        title TEXT,
        description TEXT,
        uploader TEXT,
        duration INTEGER,
        view_count INTEGER,
        upload_date TEXT,
        download_method TEXT NOT NULL DEFAULT 'unknown',
        quality_label TEXT,
        chapters_json TEXT,
        user_note TEXT NOT NULL DEFAULT '',
        is_watched INTEGER NOT NULL DEFAULT 0,
        scheduled_at INTEGER,
        queue_position INTEGER,
        source_url TEXT NOT NULL DEFAULT '',
        priority INTEGER NOT NULL DEFAULT 0,
        recurrence_rule_json TEXT
      );
    ''';

    const createAppSettings = '''
      CREATE TABLE app_settings (
        key TEXT NOT NULL,
        value TEXT NOT NULL,
        PRIMARY KEY (key)
      );
    ''';

    const createSubscribedChannelsV5 = '''
      CREATE TABLE subscribed_channels (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        channel_id TEXT NOT NULL UNIQUE,
        channel_name TEXT NOT NULL,
        channel_handle TEXT,
        thumbnail TEXT,
        subscriber_count INTEGER,
        video_count INTEGER,
        webpage_url TEXT NOT NULL,
        description TEXT,
        subscribed_at INTEGER NOT NULL DEFAULT 0,
        last_checked INTEGER,
        latest_video_id TEXT,
        latest_video_title TEXT,
        latest_video_date INTEGER,
        has_new_videos INTEGER NOT NULL DEFAULT 0
      );
    ''';

    const createDownloadTagsV9 = '''
      CREATE TABLE download_tags (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        download_id INTEGER NOT NULL REFERENCES downloads(id) ON DELETE CASCADE,
        tag TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT 0
      );
    ''';

    /// Build a raw sqlite3 database in the EXACT broken state Chairman saw on
    /// disk: v15 schema + v16 column already added + user_version frozen at 15.
    raw_sqlite.Database buildPartiallyMigratedDb({required int userVersion}) {
      final db = raw_sqlite.sqlite3.openInMemory();
      db.execute(createDownloadsV15);
      db.execute(createAppSettings);
      db.execute(createSubscribedChannelsV5);
      db.execute(createDownloadTagsV9);
      // v16 partial migration: column added but user_version never bumped.
      db.execute('ALTER TABLE downloads ADD COLUMN temp_dir_path TEXT');
      db.execute('PRAGMA user_version = $userVersion');
      return db;
    }

    test('opens cleanly when v15 user_version + v16 temp_dir_path already present', () async {
      final raw = buildPartiallyMigratedDb(userVersion: 15);

      // Pre-populate two real download rows to mimic Chairman's 221 downloads.
      raw.execute(
        "INSERT INTO downloads (url, filename, save_path, status, total_bytes) "
        "VALUES ('https://test.com/a', 'a.mp4', '/tmp/a.mp4', 'completed', 1024)",
      );
      raw.execute(
        "INSERT INTO downloads (url, filename, save_path, status, total_bytes) "
        "VALUES ('https://test.com/b', 'b.mp4', '/tmp/b.mp4', 'completed', 2048)",
      );

      // Sanity-check: re-running ALTER directly on this DB throws — that's the
      // exact failure mode the fix is guarding against.
      expect(
        () =>
            raw.execute('ALTER TABLE downloads ADD COLUMN temp_dir_path TEXT'),
        throwsA(isA<raw_sqlite.SqliteException>()),
        reason:
            'baseline: SQLite must throw on duplicate column to make this test meaningful',
      );

      // Hand the broken DB to Drift via the test executor and trigger migration.
      final db = AppDatabase.forTestWithExecutor(NativeDatabase.opened(raw));
      addTearDown(() => db.close());

      // Triggering ANY query forces Drift to open the DB and run onUpgrade.
      final rows = await db.getAllDownloads();

      // Existing rows are still readable — no data loss.
      expect(rows, hasLength(2));
      expect(
        rows.map((r) => r.url),
        containsAll(['https://test.com/a', 'https://test.com/b']),
      );

      // Schema bumped all the way to current version (18 — bumped from 17 by
      // the converter merge that added conversion_jobs as v17→v18 migration).
      final versionRow =
          await db.customSelect('PRAGMA user_version').getSingle();
      expect(versionRow.data['user_version'], 20);

      // The v16 column is reachable by Drift's typed API after migration.
      // Inserting a new row exercising the new column proves the schema is
      // consistent end-to-end (not just "didn't crash").
      final insertedId = await db.insertDownload(
        DownloadsCompanion.insert(
          url: 'https://test.com/c',
          filename: 'c.mp4',
          savePath: '/tmp/c.mp4',
          status: 'pending',
          tempDirPath: const Value('/tmp/c.tmp'),
        ),
      );
      final fetched = await db.getDownloadById(insertedId);
      expect(fetched, isA<Download>());
      expect(fetched!.tempDirPath, '/tmp/c.tmp');
    });

    test(
      'opens cleanly when only user_version=14 with v15 column already present',
      () async {
        // Same shape, one version earlier — guards against "the same bug pattern
        // happens again on a future migration." This is what _safeAddColumn
        // promises to handle for ANY DDL step.
        final raw = raw_sqlite.sqlite3.openInMemory();
        raw.execute(
          createDownloadsV15.replaceAll(
            'recurrence_rule_json TEXT',
            // Drop v15 col so we start at v14 schema, then re-add it manually.
            'priority_unused INTEGER',
          ),
        );
        raw.execute(createAppSettings);
        raw.execute(createSubscribedChannelsV5);
        raw.execute(createDownloadTagsV9);
        // Simulate v14→v15 partial: column added, user_version frozen at 14.
        raw.execute(
          'ALTER TABLE downloads ADD COLUMN recurrence_rule_json TEXT',
        );
        raw.execute('PRAGMA user_version = 14');

        final db = AppDatabase.forTestWithExecutor(NativeDatabase.opened(raw));
        addTearDown(() => db.close());

        // Open + query — should not throw despite the partial v15 state.
        await db.getAllDownloads();

        final versionRow =
            await db.customSelect('PRAGMA user_version').getSingle();
        expect(versionRow.data['user_version'], 20);
      },
    );

    test('fresh install (v0) walks the full migration chain to v20', () async {
      // Sanity check that the fix didn't break the "no existing DB" path.
      // A fresh memory DB has no tables and user_version=0 — Drift takes the
      // onCreate path, which also creates the v17 indexes and (post-converter
      // merge) the v18 conversion_jobs table.
      final db = AppDatabase.forTest();
      addTearDown(() => db.close());

      await db.getAllDownloads();

      final versionRow =
          await db.customSelect('PRAGMA user_version').getSingle();
      expect(versionRow.data['user_version'], 20);
    });

    test('foreign_keys pragma is enabled after open', () async {
      // Regression test for the second fix in this hotfix: drift 2.28.2 does
      // NOT enable PRAGMA foreign_keys by default, so we wired it up via
      // `beforeOpen`. Without this, the DownloadTags ON DELETE CASCADE
      // constraint is silently ignored and orphan rows accumulate.
      final db = AppDatabase.forTest();
      addTearDown(() => db.close());

      // Force the DB to open by issuing a query.
      await db.getAllDownloads();

      final fkRow = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(
        fkRow.data['foreign_keys'],
        1,
        reason:
            'PRAGMA foreign_keys must be ON so DownloadTags FK cascades work',
      );
    });

    test(
      'deleting a download cascades to its tags (FK enforcement live)',
      () async {
        // End-to-end proof that foreign_keys=ON is actually doing work, not
        // just reporting "1" cosmetically. Insert a download + tag, delete the
        // download, expect the tag row to be auto-removed by the cascade.
        final db = AppDatabase.forTest();
        addTearDown(() => db.close());

        final downloadId = await db.insertDownload(
          DownloadsCompanion.insert(
            url: 'https://test.com/cascade',
            filename: 'cascade.mp4',
            savePath: '/tmp/cascade.mp4',
            status: 'completed',
          ),
        );
        await db.insertTag(downloadId, 'archive');

        // Sanity: tag is present before delete.
        expect(await db.getTagsForDownload(downloadId), ['archive']);

        await db.deleteDownload(downloadId);

        // After cascade, the tag row should be gone — not just unreferenceable
        // by getTagsForDownload (which filters by downloadId), but actually
        // absent from the underlying table.
        final orphans =
            await db
                .customSelect(
                  'SELECT COUNT(*) AS c FROM download_tags WHERE download_id = ?',
                  variables: [Variable.withInt(downloadId)],
                )
                .getSingle();
        expect(
          orphans.data['c'],
          0,
          reason:
              'FK cascade should have removed tag rows when download was deleted',
        );
      },
    );

    // === v20 — User-curated playlist tables (Hybrid #2 / C-lite) ===
    //
    // The v20 migration adds two NEW tables (`user_playlists` and
    // `user_playlist_items`) — no schema changes to existing tables.
    // Risk surface: re-running the migration on a partial state must
    // be idempotent, and the FK CASCADE on memberships must actually
    // fire (same lesson as DownloadTags — the pragma + the constraint
    // both have to be live).

    test(
      'v20 — user_playlists and user_playlist_items tables exist after migration',
      () async {
        final db = AppDatabase.forTest();
        addTearDown(() => db.close());

        // Force open + onCreate path.
        await db.getAllDownloads();

        // sqlite_master is the source of truth for "does this table
        // exist?" — bypasses Drift's typed API in case the DB is
        // miswired.
        final pl =
            await db
                .customSelect(
                  "SELECT name FROM sqlite_master "
                  "WHERE type='table' AND name='user_playlists'",
                )
                .get();
        final items =
            await db
                .customSelect(
                  "SELECT name FROM sqlite_master "
                  "WHERE type='table' AND name='user_playlist_items'",
                )
                .get();
        expect(pl, hasLength(1));
        expect(items, hasLength(1));
      },
    );

    test(
      'v20 — partial migration is idempotent (table already exists, version frozen)',
      () async {
        // Mirrors the DownloadTags / temp_dir_path pattern: if a prior
        // run created the table but failed to bump user_version, the
        // re-run must NOT throw "table already exists" and abort the
        // entire migration.
        final raw = raw_sqlite.sqlite3.openInMemory();
        // Bring the DB up to v19 manually, then add v20 tables WITHOUT
        // bumping user_version — this is the "crashed mid-migration"
        // shape we're guarding against.
        raw.execute('PRAGMA user_version = 19');
        // Minimal v19 downloads + user_playlists already created on a
        // prior run.
        raw.execute('''
          CREATE TABLE downloads (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url TEXT NOT NULL,
            filename TEXT NOT NULL,
            save_path TEXT NOT NULL,
            status TEXT NOT NULL,
            total_bytes INTEGER NOT NULL DEFAULT 0,
            downloaded_bytes INTEGER NOT NULL DEFAULT 0,
            speed INTEGER NOT NULL DEFAULT 0,
            platform TEXT NOT NULL DEFAULT 'unknown',
            created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
            updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
            retry_count INTEGER NOT NULL DEFAULT 0,
            download_method TEXT NOT NULL DEFAULT 'unknown',
            user_note TEXT NOT NULL DEFAULT '',
            is_watched INTEGER NOT NULL DEFAULT 0,
            source_url TEXT NOT NULL DEFAULT '',
            priority INTEGER NOT NULL DEFAULT 0
          )
        ''');
        // Match the real Drift schema — `currentDateAndTime` translates
        // to `DEFAULT (strftime('%s','now'))` in SQL. Without these
        // defaults the upsert below would hit NOT NULL on created_at.
        raw.execute('''
          CREATE TABLE user_playlists (
            id TEXT NOT NULL PRIMARY KEY,
            title TEXT NOT NULL,
            created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
            updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
          )
        ''');

        // Sanity: re-creating the table directly throws — that's the
        // "already exists" failure mode the safe wrapper handles.
        expect(
          () => raw.execute(
            'CREATE TABLE user_playlists (id TEXT PRIMARY KEY, title TEXT)',
          ),
          throwsA(isA<raw_sqlite.SqliteException>()),
          reason:
              'baseline: SQLite must throw on duplicate table to make this test meaningful',
        );

        final db = AppDatabase.forTestWithExecutor(NativeDatabase.opened(raw));
        addTearDown(() => db.close());

        // Open + trigger migration. Should NOT throw.
        await db.getAllDownloads();

        final versionRow =
            await db.customSelect('PRAGMA user_version').getSingle();
        expect(
          versionRow.data['user_version'],
          20,
          reason: 'Migration should bump to v20 even when partial state exists',
        );

        // Both tables are now usable via Drift's typed API.
        await db.upsertUserPlaylist(id: 'user_test', title: 'After Migration');
        final list = await db.getUserPlaylistSummaries();
        expect(list.where((p) => p.playlistId == 'user_test'), hasLength(1));
      },
    );

    test(
      'v20 — deleting a download cascades to its user_playlist_items memberships',
      () async {
        // Same shape as the DownloadTags cascade test but for the v20
        // join table. If the FK constraint is silently ignored we'd
        // accumulate orphan membership rows pointing at deleted
        // downloads — every "Add to playlist" would slowly poison
        // `getUserPlaylistMemberships` with phantom entries.
        final db = AppDatabase.forTest();
        addTearDown(() => db.close());

        final downloadId = await db.insertDownload(
          DownloadsCompanion.insert(
            url: 'https://test.com/v20',
            filename: 'v20.mp4',
            savePath: '/tmp/v20.mp4',
            status: 'completed',
          ),
        );
        await db.upsertUserPlaylist(id: 'user_v20', title: 'V20 Mix');
        await db.addDownloadsToUserPlaylist(
          playlistId: 'user_v20',
          downloadIds: [downloadId],
        );

        // Sanity: membership row present before delete.
        final preMemberships = await db.getUserPlaylistMemberships();
        expect(
          preMemberships.where((m) => m.downloadId == downloadId),
          hasLength(1),
        );

        await db.deleteDownload(downloadId);

        // After CASCADE, the membership row must be gone.
        final orphans =
            await db
                .customSelect(
                  'SELECT COUNT(*) AS c FROM user_playlist_items '
                  'WHERE download_id = ?',
                  variables: [Variable.withInt(downloadId)],
                )
                .getSingle();
        expect(
          orphans.data['c'],
          0,
          reason:
              'FK cascade should remove memberships when the parent download is deleted',
        );
      },
    );

    test(
      'v20 — deleting a user_playlist cascades to all its memberships',
      () async {
        // Symmetric guarantee: removing a playlist row evicts every
        // membership pointing at it. Otherwise an empty playlist
        // would still show up in `getUserPlaylistMemberships` and the
        // sidebar group header would render with phantom children.
        final db = AppDatabase.forTest();
        addTearDown(() => db.close());

        final id1 = await db.insertDownload(
          DownloadsCompanion.insert(
            url: 'https://t/1',
            filename: '1.mp4',
            savePath: '/tmp',
            status: 'completed',
          ),
        );
        final id2 = await db.insertDownload(
          DownloadsCompanion.insert(
            url: 'https://t/2',
            filename: '2.mp4',
            savePath: '/tmp',
            status: 'completed',
          ),
        );
        await db.upsertUserPlaylist(id: 'user_to_delete', title: 'Doomed');
        await db.addDownloadsToUserPlaylist(
          playlistId: 'user_to_delete',
          downloadIds: [id1, id2],
        );

        // Delete the playlist row directly.
        await (db.delete(db.userPlaylists)
          ..where((t) => t.id.equals('user_to_delete'))).go();

        final orphans =
            await db
                .customSelect(
                  "SELECT COUNT(*) AS c FROM user_playlist_items "
                  "WHERE playlist_id = 'user_to_delete'",
                )
                .getSingle();
        expect(
          orphans.data['c'],
          0,
          reason:
              'FK cascade must remove orphan memberships when the parent playlist is deleted',
        );
      },
    );

    test(
      'v20 — addDownloadsToUserPlaylist appends with monotonically increasing positions',
      () async {
        // Locks the contract that
        // `DownloadRepositoryImpl.addToUserPlaylist` relies on for
        // ordering. The visual lane will sort children by `position`
        // — if two adds in succession produce ties or non-monotonic
        // values, the playlist UI would render wrong order.
        final db = AppDatabase.forTest();
        addTearDown(() => db.close());

        final ids = <int>[];
        for (var i = 0; i < 3; i++) {
          ids.add(
            await db.insertDownload(
              DownloadsCompanion.insert(
                url: 'https://t/$i',
                filename: '$i.mp4',
                savePath: '/tmp',
                status: 'completed',
              ),
            ),
          );
        }
        await db.upsertUserPlaylist(id: 'user_pos', title: 'Pos');

        // Two separate calls — second batch must continue numbering
        // from where the first left off, not reset to 0.
        await db.addDownloadsToUserPlaylist(
          playlistId: 'user_pos',
          downloadIds: [ids[0]],
        );
        await db.addDownloadsToUserPlaylist(
          playlistId: 'user_pos',
          downloadIds: [ids[1], ids[2]],
        );

        final memberships = await db.getUserPlaylistMemberships();
        final filtered =
            memberships.where((m) => m.playlistId == 'user_pos').toList()
              ..sort((a, b) => a.position.compareTo(b.position));
        expect(filtered.map((m) => m.position).toList(), [0, 1, 2]);
        expect(filtered.map((m) => m.downloadId).toList(), ids);
      },
    );

    test(
      'v20 — re-adding the same (playlistId, downloadId) is a no-op (composite PK + INSERT OR IGNORE)',
      () async {
        // Idempotent re-add is the contract for the dialog: tapping
        // an existing playlist row twice in a row must not duplicate
        // the membership or shift positions.
        final db = AppDatabase.forTest();
        addTearDown(() => db.close());

        final downloadId = await db.insertDownload(
          DownloadsCompanion.insert(
            url: 'https://t/dup',
            filename: 'dup.mp4',
            savePath: '/tmp',
            status: 'completed',
          ),
        );
        await db.upsertUserPlaylist(id: 'user_dup', title: 'Dup');

        await db.addDownloadsToUserPlaylist(
          playlistId: 'user_dup',
          downloadIds: [downloadId],
        );
        // Second add — same (playlistId, downloadId) pair.
        await db.addDownloadsToUserPlaylist(
          playlistId: 'user_dup',
          downloadIds: [downloadId],
        );

        final memberships = await db.getUserPlaylistMemberships();
        final dupMemberships =
            memberships.where((m) => m.playlistId == 'user_dup').toList();
        expect(
          dupMemberships,
          hasLength(1),
          reason: 'Composite PK must coalesce re-adds to a single row',
        );
        expect(dupMemberships.first.downloadId, downloadId);
      },
    );

    test(
      'v20 — removing a playlist item compacts remaining positions',
      () async {
        final db = AppDatabase.forTest();
        addTearDown(() => db.close());

        final ids = <int>[];
        for (var i = 0; i < 3; i++) {
          ids.add(
            await db.insertDownload(
              DownloadsCompanion.insert(
                url: 'https://t/remove-$i',
                filename: 'remove-$i.mp4',
                savePath: '/tmp',
                status: 'completed',
              ),
            ),
          );
        }
        await db.upsertUserPlaylist(id: 'user_remove', title: 'Remove');
        await db.addDownloadsToUserPlaylist(
          playlistId: 'user_remove',
          downloadIds: ids,
        );

        await db.removeDownloadFromUserPlaylist(
          playlistId: 'user_remove',
          downloadId: ids[1],
        );

        final memberships =
            (await db.getUserPlaylistMemberships())
                .where((m) => m.playlistId == 'user_remove')
                .toList()
              ..sort((a, b) => a.position.compareTo(b.position));

        expect(memberships.map((m) => m.downloadId), [ids[0], ids[2]]);
        expect(memberships.map((m) => m.position), [0, 1]);
      },
    );

    test(
      'v20 — reorderUserPlaylist rewrites positions and preserves omitted members',
      () async {
        final db = AppDatabase.forTest();
        addTearDown(() => db.close());

        final ids = <int>[];
        for (var i = 0; i < 3; i++) {
          ids.add(
            await db.insertDownload(
              DownloadsCompanion.insert(
                url: 'https://t/reorder-$i',
                filename: 'reorder-$i.mp4',
                savePath: '/tmp',
                status: 'completed',
              ),
            ),
          );
        }
        await db.upsertUserPlaylist(id: 'user_reorder', title: 'Reorder');
        await db.addDownloadsToUserPlaylist(
          playlistId: 'user_reorder',
          downloadIds: ids,
        );

        await db.reorderUserPlaylist(
          playlistId: 'user_reorder',
          orderedDownloadIds: [ids[2], ids[0]],
        );

        final memberships =
            (await db.getUserPlaylistMemberships())
                .where((m) => m.playlistId == 'user_reorder')
                .toList()
              ..sort((a, b) => a.position.compareTo(b.position));

        expect(memberships.map((m) => m.downloadId), [ids[2], ids[0], ids[1]]);
        expect(memberships.map((m) => m.position), [0, 1, 2]);
      },
    );
  });
}
