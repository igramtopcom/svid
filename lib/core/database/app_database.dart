import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'package:sqlite3/sqlite3.dart';
import '../constants/app_constants.dart';
import '../logging/app_logger.dart';

part 'app_database.g.dart';

/// Downloads table schema
class Downloads extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get url => text()();
  TextColumn get filename => text()();
  TextColumn get savePath => text()();
  TextColumn get status =>
      text()(); // pending, downloading, paused, completed, failed, cancelled
  IntColumn get totalBytes => integer().withDefault(const Constant(0))();
  IntColumn get downloadedBytes => integer().withDefault(const Constant(0))();
  IntColumn get speed =>
      integer().withDefault(const Constant(0))(); // bytes per second
  TextColumn get thumbnail => text().nullable()(); // video thumbnail URL
  TextColumn get platform =>
      text().withDefault(
        const Constant('unknown'),
      )(); // youtube, tiktok, instagram, etc.
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get errorMessage => text().nullable()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();

  // Rich metadata (added in v4)
  TextColumn get title => text().nullable()(); // Video title from yt-dlp
  TextColumn get description => text().nullable()(); // Video description
  TextColumn get uploader => text().nullable()(); // Channel/uploader name
  IntColumn get duration => integer().nullable()(); // Duration in seconds
  IntColumn get viewCount => integer().nullable()(); // View count
  TextColumn get uploadDate => text().nullable()(); // Upload date (YYYYMMDD)

  // Download method tracking (added in v4)
  TextColumn get downloadMethod =>
      text().withDefault(
        const Constant('unknown'),
      )(); // 'ytdlp', 'api', 'unknown'

  // Quality label (added in v6) — e.g., "1080p", "720p", "Audio Only"
  TextColumn get qualityLabel => text().nullable()();

  // Chapters JSON (added in v7) — serialized List<{title, startTime, endTime}>
  TextColumn get chaptersJson => text().nullable()();

  // User note (added in v8) — personal note on each download item
  TextColumn get userNote => text().withDefault(const Constant(''))();

  // Watch status (added in v10) — true when user has watched ≥90% (or ≥80% for short clips)
  BoolColumn get isWatched => boolean().withDefault(const Constant(false))();

  // Scheduled start time (added in v11) — null = not scheduled
  DateTimeColumn get scheduledAt => dateTime().nullable()();

  // Queue position for drag-and-drop reorder (added in v12) — null = unordered
  IntColumn get queuePosition => integer().nullable()();

  // Source URL — original page URL for Rust downloads (added in v13).
  // Empty string for ytdlp/unknown downloads (they already store the page URL in `url`).
  TextColumn get sourceUrl => text().withDefault(const Constant(''))();

  // User-set download priority (added in v14): 1=high, 0=normal (default), -1=low.
  IntColumn get priority => integer().withDefault(const Constant(0))();

  // Recurrence rule JSON (added in v15) — serialized RecurrenceRule (null = no recurrence)
  TextColumn get recurrenceRuleJson => text().nullable()();

  // Temp dir path (added in v16) — isolated temp dir for yt-dlp downloads.
  // Persisted so --continue can resume from .part files after app restart.
  // Null for Rust-engine downloads or completed downloads (cleaned up).
  TextColumn get tempDirPath => text().nullable()();

  // Playlist context (added in v19) — when a download originates from
  // a YouTube playlist (or equivalent platform collection), these
  // fields tag every video in the same playlist with a shared
  // [playlistId] so the download manager UI can group + filter by
  // playlist as a first-class concept. Null for ad-hoc single-URL
  // downloads. Populated by HomeBatchDownloadMixin when the user
  // picks videos from a YouTubePlaylistSheet — see Phase 2.B
  // extraction integration.
  TextColumn get playlistId => text().nullable()();
  TextColumn get playlistTitle => text().nullable()();
  IntColumn get playlistIndex => integer().nullable()();
}

/// App settings table schema
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Subscribed YouTube channels table schema (v5)
class SubscribedChannels extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get channelId => text().unique()(); // YouTube channel ID (UC...)
  TextColumn get channelName => text()();
  TextColumn get channelHandle => text().nullable()(); // @username
  TextColumn get thumbnail => text().nullable()();
  IntColumn get subscriberCount => integer().nullable()();
  IntColumn get videoCount => integer().nullable()();
  TextColumn get webpageUrl => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get subscribedAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastChecked =>
      dateTime().nullable()(); // Last time we checked for new videos
  TextColumn get latestVideoId =>
      text().nullable()(); // ID of latest video we've seen
  TextColumn get latestVideoTitle =>
      text().nullable()(); // Title of latest video
  DateTimeColumn get latestVideoDate =>
      dateTime().nullable()(); // Date of latest video
  BoolColumn get hasNewVideos =>
      boolean().withDefault(const Constant(false))(); // Badge indicator

  List<Set<Column>> get customIndexes => [
    {hasNewVideos}, // Index for fast "new videos" queries
  ];
}

/// Download tags table schema (v9)
/// FK: downloadId → downloads.id ON DELETE CASCADE (auto-remove when download deleted)
class DownloadTags extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get downloadId =>
      integer().references(Downloads, #id, onDelete: KeyAction.cascade)();
  TextColumn get tag => text()(); // stored normalized (lowercase, trimmed)
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// User-curated playlist (v20). The id is a string `user_<uuid>` minted
/// by the "Add to playlist" dialog. Title is required — created with
/// non-empty input from the user. yt_* source playlists do NOT live
/// here; they're a derived property of `downloads.playlistId` and
/// remain queryable directly off the downloads table.
class UserPlaylists extends Table {
  TextColumn get id => text()(); // user_<uuid>
  TextColumn get title => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Membership join — a download can belong to N user playlists, and a
/// playlist can hold N downloads. Composite PK (playlistId, downloadId)
/// guarantees idempotent re-adds (ON CONFLICT REPLACE updates
/// position/addedAt without duplicating). Both FKs CASCADE so deleting
/// a playlist evicts its memberships, and deleting a download removes
/// it from every playlist (no orphan rows). (v20)
class UserPlaylistItems extends Table {
  TextColumn get playlistId =>
      text().references(UserPlaylists, #id, onDelete: KeyAction.cascade)();
  IntColumn get downloadId =>
      integer().references(Downloads, #id, onDelete: KeyAction.cascade)();

  /// 0-based ordering within the playlist. Append at max+1; reorder
  /// would re-write positions for the affected range (out of v0 scope).
  IntColumn get position => integer()();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {playlistId, downloadId};
}

/// Conversion jobs table schema (v17)
class ConversionJobs extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get inputPath => text()();
  TextColumn get outputPath => text()();
  TextColumn get inputFilename => text()();
  TextColumn get outputFilename => text()();
  TextColumn get status =>
      text()(); // queued/probing/converting/paused/completed/failed/cancelled
  RealColumn get progress => real().withDefault(const Constant(0.0))();
  IntColumn get inputSize => integer().withDefault(const Constant(0))();
  IntColumn get outputSize => integer().nullable()();
  IntColumn get durationMs => integer().nullable()(); // Input duration in ms
  TextColumn get presetName => text().nullable()();
  TextColumn get configJson => text()(); // Serialized ConversionConfig JSON
  IntColumn get downloadId =>
      integer().nullable()(); // FK to downloads (nullable for external files)
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Downloads,
    AppSettings,
    SubscribedChannels,
    DownloadTags,
    ConversionJobs,
    UserPlaylists,
    UserPlaylistItems,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// In-memory database for tests.
  AppDatabase.forTest() : super(NativeDatabase.memory());

  /// Test constructor that accepts a pre-configured executor.
  /// Used to simulate corrupted/partially-migrated database states (e.g., a
  /// v15 user_version with v16 columns already present) so we can verify the
  /// migration idempotency contract from `onUpgrade` against real failure
  /// modes that `NativeDatabase.memory()` cannot reach.
  AppDatabase.forTestWithExecutor(super.e);

  @override
  int get schemaVersion => 20;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      // Runs on EVERY database open, after any create/upgrade steps. Drift
      // does NOT enable `foreign_keys` pragma by default (drift 2.28.2), so
      // without this hook, every `REFERENCES downloads(id) ON DELETE CASCADE`
      // constraint (e.g., on [downloadTags]) is silently ignored. Deleting a
      // download would leave orphan tag rows forever, bloating the table.
      // Enable it once at open; the setting does not persist across sessions.
      //
      // NOTE: Existing orphan rows from before this fix stay in place. They
      // are harmless (UI filters tags by existing download IDs), and removing
      // them would require a one-shot cleanup pass we don't need right now.
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
        // WAL (Write-Ahead Logging) lets readers and writers coexist without
        // blocking each other. The default `journal_mode=DELETE` serialises
        // every read against every write, and on Windows produced
        // `SqliteException(5): database is locked` whenever a background
        // write (queue dispatch, heartbeat upsert) overlapped with a
        // foreground read (PRAGMA user_version on the bootstrap path,
        // `home_download_mixin.dart:761` in audit). 15 production crashes
        // observed on v1.3.5 / v1.6.2 / v1.3.6.
        //
        // WAL is the SQLite default for any non-trivial app and is a
        // per-database setting that persists across opens, but we set it
        // every open as a safety belt against tools that flip it back.
        await customStatement('PRAGMA journal_mode = WAL');
        // 5s busy-timeout: if a write transaction is in-flight, readers
        // wait instead of throwing immediately. Pairs with WAL — short
        // writes complete in milliseconds, so 5s is more than enough.
        await customStatement('PRAGMA busy_timeout = 5000');
      },
      onCreate: (Migrator m) async {
        await m.createAll();
        // Forward-looking indexes (v17) — also created in upgrade path below.
        // Created here so fresh installs get them without an upgrade step.
        await _createV17Indexes();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // === IDEMPOTENCY CONTRACT ===
        // Every DDL operation below is wrapped in [_safeAddColumn] /
        // [_safeCreateTable] because SQLite ALTER TABLE / CREATE TABLE are
        // auto-committed and CANNOT be rolled back inside a transaction.
        //
        // Failure mode this guards against: a previous build ran the migration,
        // the addColumn/createTable succeeded and persisted to disk, but Drift
        // failed to bump `user_version` (process crash, app force-quit during
        // upgrade, exception in a later step). Next launch sees the old
        // user_version, re-runs the migration, and hits "duplicate column" /
        // "table already exists" → migration aborts → DB unopenable → empty UI.
        //
        // Real incident: 2026-04-07 — user's `svid.db` ended at user_version=15
        // with v16 column `temp_dir_path` already present. addColumn re-run
        // crashed migration, downloads UI went empty. Fix: try/catch every DDL.
        // The desired end state is "column/table present"; if it already is,
        // that's success, not failure.

        // Migration from v1 to v2: Add thumbnail column
        if (from <= 1 && to >= 2) {
          await _safeAddColumn(
            m,
            'v2.thumbnail',
            () => m.addColumn(downloads, downloads.thumbnail),
          );
        }

        // Migration from v2 to v3: Add platform column
        if (from <= 2 && to >= 3) {
          await _safeAddColumn(
            m,
            'v3.platform',
            () => m.addColumn(downloads, downloads.platform),
          );
        }

        // Migration from v3 to v4: Add rich metadata and download method columns
        if (from <= 3 && to >= 4) {
          // Rich metadata columns
          await _safeAddColumn(
            m,
            'v4.title',
            () => m.addColumn(downloads, downloads.title),
          );
          await _safeAddColumn(
            m,
            'v4.description',
            () => m.addColumn(downloads, downloads.description),
          );
          await _safeAddColumn(
            m,
            'v4.uploader',
            () => m.addColumn(downloads, downloads.uploader),
          );
          await _safeAddColumn(
            m,
            'v4.duration',
            () => m.addColumn(downloads, downloads.duration),
          );
          await _safeAddColumn(
            m,
            'v4.viewCount',
            () => m.addColumn(downloads, downloads.viewCount),
          );
          await _safeAddColumn(
            m,
            'v4.uploadDate',
            () => m.addColumn(downloads, downloads.uploadDate),
          );
          // Download method tracking
          await _safeAddColumn(
            m,
            'v4.downloadMethod',
            () => m.addColumn(downloads, downloads.downloadMethod),
          );

          // Mark existing downloads as downloaded via API (for backward
          // compatibility). UPDATE is naturally idempotent — re-running on
          // already-migrated rows is a no-op.
          await customStatement(
            "UPDATE downloads SET download_method = 'api' WHERE download_method = 'unknown'",
          );
        }

        // Migration from v4 to v5: Add subscribed channels table
        if (from <= 4 && to >= 5) {
          await _safeCreateTable(
            m,
            'v5.subscribedChannels',
            () => m.createTable(subscribedChannels),
          );
        }

        // Migration from v5 to v6: Add quality label column
        if (from <= 5 && to >= 6) {
          await _safeAddColumn(
            m,
            'v6.qualityLabel',
            () => m.addColumn(downloads, downloads.qualityLabel),
          );
        }

        // Migration from v6 to v7: Add chapters JSON column
        if (from <= 6 && to >= 7) {
          await _safeAddColumn(
            m,
            'v7.chaptersJson',
            () => m.addColumn(downloads, downloads.chaptersJson),
          );
        }

        // Migration from v7 to v8: Add user note column
        if (from <= 7 && to >= 8) {
          await _safeAddColumn(
            m,
            'v8.userNote',
            () => m.addColumn(downloads, downloads.userNote),
          );
        }

        // Migration from v8 to v9: Add download_tags table
        if (from <= 8 && to >= 9) {
          await _safeCreateTable(
            m,
            'v9.downloadTags',
            () => m.createTable(downloadTags),
          );
        }

        // Migration from v9 to v10: Add is_watched column
        if (from <= 9 && to >= 10) {
          await _safeAddColumn(
            m,
            'v10.isWatched',
            () => m.addColumn(downloads, downloads.isWatched),
          );
        }

        // Migration from v10 to v11: Add scheduled_at column
        if (from <= 10 && to >= 11) {
          await _safeAddColumn(
            m,
            'v11.scheduledAt',
            () => m.addColumn(downloads, downloads.scheduledAt),
          );
        }

        // Migration from v11 to v12: Add queue_position column
        if (from <= 11 && to >= 12) {
          await _safeAddColumn(
            m,
            'v12.queuePosition',
            () => m.addColumn(downloads, downloads.queuePosition),
          );
        }

        // Migration from v12 to v13: Add source_url column
        if (from <= 12 && to >= 13) {
          await _safeAddColumn(
            m,
            'v13.sourceUrl',
            () => m.addColumn(downloads, downloads.sourceUrl),
          );
        }

        // Migration from v13 to v14: Add priority column (user-set priority)
        if (from <= 13 && to >= 14) {
          await _safeAddColumn(
            m,
            'v14.priority',
            () => m.addColumn(downloads, downloads.priority),
          );
        }

        // Migration from v14 to v15: Add recurrence_rule_json column
        if (from <= 14 && to >= 15) {
          await _safeAddColumn(
            m,
            'v15.recurrenceRuleJson',
            () => m.addColumn(downloads, downloads.recurrenceRuleJson),
          );
        }

        // Migration from v15 to v16: Add temp_dir_path column for yt-dlp resume
        if (from <= 15 && to >= 16) {
          await _safeAddColumn(
            m,
            'v16.tempDirPath',
            () => m.addColumn(downloads, downloads.tempDirPath),
          );
        }

        // Migration from v16 to v17: Forward-looking indexes for downloads
        // table. Cheap on small tables, real win once users hit 1000+ items.
        // Covers: status filter, URL dedup lookup, created_at ordering, and
        // tag-by-download FK joins. Already idempotent via IF NOT EXISTS.
        if (from <= 16 && to >= 17) {
          await _createV17Indexes();
        }

        // Migration from v17 to v18: Add conversion_jobs table for the Media
        // Converter feature (merged from feature/converter). Wrapped in
        // [_safeCreateTable] because pre-merge dev/test builds may have already
        // created this table at v17 — without the wrapper a re-run would throw
        // "table already exists" and abort the entire migration.
        if (from <= 17 && to >= 18) {
          await _safeCreateTable(
            m,
            'v18.conversionJobs',
            () => m.createTable(conversionJobs),
          );
        }

        // Migration from v18 to v19: Add playlist context columns to
        // downloads table. All three are nullable so existing rows
        // require no backfill; they remain ad-hoc (non-playlist)
        // downloads. New rows opt in via HomeBatchDownloadMixin when
        // the user picks videos from a YouTubePlaylistSheet.
        if (from <= 18 && to >= 19) {
          await _safeAddColumn(
            m,
            'v19.playlistId',
            () => m.addColumn(downloads, downloads.playlistId),
          );
          await _safeAddColumn(
            m,
            'v19.playlistTitle',
            () => m.addColumn(downloads, downloads.playlistTitle),
          );
          await _safeAddColumn(
            m,
            'v19.playlistIndex',
            () => m.addColumn(downloads, downloads.playlistIndex),
          );
        }

        // Migration from v19 to v20: Split user-curated playlists out
        // of the downloads table into proper M:N storage. The v19
        // user_* tags carried in `downloads.playlistId` were a v0
        // shortcut and never shipped to production users — branch
        // `v2/home-redesign-foundation` is unmerged at the time this
        // migration ships, so there is no production data to copy.
        // Branch testers may carry `user_<uuid>` rows on `downloads`;
        // those are deliberately left in place (harmless — the new
        // code reads only from user_playlists / user_playlist_items)
        // and get cleared the next time the user re-tags a video.
        // yt_* source-playlist data on `downloads.playlistId` stays
        // canonical and is NOT touched by this migration.
        if (from <= 19 && to >= 20) {
          await _safeCreateTable(
            m,
            'v20.userPlaylists',
            () => m.createTable(userPlaylists),
          );
          await _safeCreateTable(
            m,
            'v20.userPlaylistItems',
            () => m.createTable(userPlaylistItems),
          );
        }
      },
    );
  }

  /// Idempotency wrapper for [Migrator.addColumn]. SQLite ALTER TABLE is
  /// auto-committed and cannot be rolled back inside a Drift transaction, so
  /// a partially-applied migration can leave a column present on disk even
  /// though `user_version` was never bumped. Re-running the same addColumn
  /// then throws "duplicate column name" and aborts the entire migration —
  /// rendering the database unopenable. We catch the error, log a warning,
  /// and treat "column already present" as the desired end state.
  ///
  /// Do NOT swallow other failure modes silently — log every catch so a real
  /// permission/disk error still shows up in app logs.
  Future<void> _safeAddColumn(
    Migrator m,
    String label,
    Future<void> Function() addOp,
  ) async {
    try {
      await addOp();
    } catch (e, stack) {
      appLogger.warning(
        'DB migration $label: addColumn skipped (likely already applied from '
        'a partial prior migration). Error: $e\n$stack',
      );
    }
  }

  /// Idempotency wrapper for [Migrator.createTable]. Same rationale as
  /// [_safeAddColumn] — CREATE TABLE is auto-committed, and a re-run after a
  /// partial migration would throw "table already exists" and abort. We treat
  /// "table already present" as the desired end state.
  Future<void> _safeCreateTable(
    Migrator m,
    String label,
    Future<void> Function() createOp,
  ) async {
    try {
      await createOp();
    } catch (e, stack) {
      appLogger.warning(
        'DB migration $label: createTable skipped (likely already applied from '
        'a partial prior migration). Error: $e\n$stack',
      );
    }
  }

  /// Create v17 indexes via IF NOT EXISTS so the same code is safe in both
  /// onCreate (fresh install) and onUpgrade (existing user) paths.
  ///
  /// Each CREATE is wrapped in its own try/catch — indexes are a perf
  /// improvement, NOT a correctness requirement. If one fails to create
  /// (e.g., disk full, permission, weird sqlite state), we log and continue
  /// rather than crash the user's app on startup.
  Future<void> _createV17Indexes() async {
    const statements = [
      'CREATE INDEX IF NOT EXISTS idx_downloads_status ON downloads(status)',
      'CREATE INDEX IF NOT EXISTS idx_downloads_url ON downloads(url)',
      'CREATE INDEX IF NOT EXISTS idx_downloads_created_at ON downloads(created_at DESC)',
      'CREATE INDEX IF NOT EXISTS idx_download_tags_download_id ON download_tags(download_id)',
    ];
    for (final stmt in statements) {
      try {
        await customStatement(stmt);
      } catch (e) {
        appLogger.warning(
          '[AppDatabase] index creation skipped (non-fatal): $e',
        );
      }
    }
  }

  // ==================== DOWNLOADS QUERIES ====================

  /// Get all downloads ordered by creation date (newest first)
  Future<List<Download>> getAllDownloads() async {
    return (select(downloads)..orderBy([
      (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
    ])).get();
  }

  /// Get downloads by status
  Future<List<Download>> getDownloadsByStatus(String status) async {
    return (select(downloads)..where((t) => t.status.equals(status))).get();
  }

  /// Get active downloads (downloading or pending)
  Future<List<Download>> getActiveDownloads() async {
    return (select(downloads)
      ..where((t) => t.status.isIn(['downloading', 'pending']))).get();
  }

  /// Get a single download by ID
  Future<Download?> getDownloadById(int id) async {
    return (select(downloads)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Get download by URL
  Future<Download?> getDownloadByUrl(String url) async {
    final results =
        await (select(downloads)
              ..where((t) => t.url.equals(url))
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
              ..limit(1))
            .get();
    return results.firstOrNull;
  }

  /// Insert a new download
  Future<int> insertDownload(DownloadsCompanion download) async {
    return into(downloads).insert(download);
  }

  /// Update download
  Future<bool> updateDownload(Download download) async {
    return update(downloads).replace(download);
  }

  /// Update is_watched flag for a download
  Future<void> updateIsWatched(int id, {required bool isWatched}) async {
    await (update(downloads)..where((t) => t.id.equals(id))).write(
      DownloadsCompanion(
        isWatched: Value(isWatched),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Update the filename (used when yt-dlp outputs a different extension than expected).
  Future<void> updateFilename(int id, String newFilename) async {
    await (update(downloads)..where((t) => t.id.equals(id))).write(
      DownloadsCompanion(
        filename: Value(newFilename),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Update the download URL (used for CDN URL refresh on 403/410 errors).
  Future<void> updateUrl(int id, String newUrl) async {
    await (update(downloads)..where((t) => t.id.equals(id))).write(
      DownloadsCompanion(url: Value(newUrl), updatedAt: Value(DateTime.now())),
    );
  }

  /// Update scheduled start time (null clears the schedule)
  Future<void> updateScheduledAt(int id, DateTime? scheduledAt) async {
    await (update(downloads)..where((t) => t.id.equals(id))).write(
      DownloadsCompanion(
        scheduledAt: Value(scheduledAt),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Update recurrence rule JSON (null clears the recurrence)
  Future<void> updateRecurrenceRuleJson(int id, String? json) async {
    await (update(downloads)..where((t) => t.id.equals(id))).write(
      DownloadsCompanion(
        recurrenceRuleJson: Value(json),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Update playlist context fields. Used by:
  ///   - Source-grouping (#1): repository-side after createDownload
  ///     when [PlaylistContextHolder] has stamped the URL from
  ///     `HomeBatchDownloadMixin.handleBatchDownload`.
  ///   - User-curated (#2): "Add to playlist" dialog → tags one or
  ///     more existing downloads with a `user_<uuid>` playlistId.
  /// Pass null to clear (e.g. user removes a video from a collection).
  Future<void> updatePlaylistContext(
    int id, {
    String? playlistId,
    String? playlistTitle,
    int? playlistIndex,
  }) async {
    await (update(downloads)..where((t) => t.id.equals(id))).write(
      DownloadsCompanion(
        playlistId: Value(playlistId),
        playlistTitle: Value(playlistTitle),
        playlistIndex: Value(playlistIndex),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// User-curated playlist summaries (v20+) — joins `user_playlists`
  /// with member counts from `user_playlist_items`. Empty playlists
  /// (no members) ARE returned because they exist as first-class
  /// rows now (a user can create an empty collection and add later).
  ///
  /// Order: most-recently-updated first, so the Add-to-playlist
  /// dialog surfaces the user's active collection on top.
  Future<List<({String playlistId, String title, int count})>>
  getUserPlaylistSummaries() async {
    final rows =
        await customSelect(
          'SELECT p.id AS pid, p.title AS ptitle, '
          '(SELECT COUNT(*) FROM user_playlist_items i '
          ' WHERE i.playlist_id = p.id) AS cnt '
          'FROM user_playlists p '
          'ORDER BY p.updated_at DESC',
          readsFrom: {userPlaylists, userPlaylistItems},
        ).get();

    return rows.map((row) {
      return (
        playlistId: row.read<String>('pid'),
        title: row.read<String>('ptitle'),
        count: row.read<int>('cnt'),
      );
    }).toList();
  }

  /// Membership tuples for the playlist tab. Returns lightweight
  /// `(downloadId, playlistId, playlistTitle, position)` rows — the
  /// caller hydrates `Download` from the in-memory list cached by
  /// `downloadsNotifierProvider` (no extra row fetch). Order:
  /// playlist updatedAt DESC, then position ASC, so groups appear in
  /// most-recent-touch order with stable internal ordering.
  Future<
    List<
      ({int downloadId, String playlistId, String playlistTitle, int position})
    >
  >
  getUserPlaylistMemberships() async {
    final rows =
        await customSelect(
          'SELECT i.download_id AS m_did, '
          'i.playlist_id AS m_pid, '
          'i.position AS m_pos, '
          'p.title AS m_ptitle '
          'FROM user_playlist_items i '
          'INNER JOIN user_playlists p ON p.id = i.playlist_id '
          'ORDER BY p.updated_at DESC, i.position ASC',
          readsFrom: {userPlaylists, userPlaylistItems},
        ).get();

    return rows.map((row) {
      return (
        downloadId: row.read<int>('m_did'),
        playlistId: row.read<String>('m_pid'),
        playlistTitle: row.read<String>('m_ptitle'),
        position: row.read<int>('m_pos'),
      );
    }).toList();
  }

  /// Insert (or REPLACE) a user playlist row. REPLACE semantics keep
  /// the call idempotent — re-creating with the same id refreshes
  /// title + updatedAt without disturbing existing memberships.
  Future<void> upsertUserPlaylist({
    required String id,
    required String title,
  }) async {
    await into(userPlaylists).insertOnConflictUpdate(
      UserPlaylistsCompanion(
        id: Value(id),
        title: Value(title),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Rename a user playlist without touching its memberships.
  Future<int> renameUserPlaylist({
    required String playlistId,
    required String title,
  }) async {
    return (update(userPlaylists)..where((t) => t.id.equals(playlistId))).write(
      UserPlaylistsCompanion(
        title: Value(title),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Delete a user playlist. Membership rows cascade via FK.
  Future<int> deleteUserPlaylist(String playlistId) {
    return (delete(userPlaylists)..where((t) => t.id.equals(playlistId))).go();
  }

  /// Append [downloadIds] to [playlistId]. Each row gets a fresh
  /// position starting at the current max+1. Re-adding an existing
  /// member is a no-op via `INSERT OR IGNORE` (composite PK collision
  /// is treated as "already there"). The playlist's updatedAt is
  /// bumped so it floats to the top of the dialog list.
  Future<void> addDownloadsToUserPlaylist({
    required String playlistId,
    required List<int> downloadIds,
  }) async {
    if (downloadIds.isEmpty) return;
    await transaction(() async {
      // Compute next position once — within the txn no concurrent
      // writer can race the max(position) read.
      final result =
          await customSelect(
            'SELECT COALESCE(MAX(position), -1) AS max_pos '
            'FROM user_playlist_items WHERE playlist_id = ?1',
            variables: [Variable.withString(playlistId)],
            readsFrom: {userPlaylistItems},
          ).getSingle();
      var nextPos = result.read<int>('max_pos') + 1;

      for (final id in downloadIds) {
        await into(userPlaylistItems).insert(
          UserPlaylistItemsCompanion(
            playlistId: Value(playlistId),
            downloadId: Value(id),
            position: Value(nextPos),
          ),
          mode: InsertMode.insertOrIgnore,
        );
        nextPos += 1;
      }

      // Bump parent updatedAt so it floats to top of the dialog.
      await (update(userPlaylists)..where(
        (t) => t.id.equals(playlistId),
      )).write(UserPlaylistsCompanion(updatedAt: Value(DateTime.now())));
    });
  }

  /// Remove a single membership. Idempotent — removing a non-member
  /// is a no-op. Does NOT delete the parent playlist row even if it
  /// becomes empty (empty playlists are valid).
  Future<int> removeDownloadFromUserPlaylist({
    required String playlistId,
    required int downloadId,
  }) async {
    return transaction(() async {
      final deleted =
          await (delete(userPlaylistItems)..where(
            (t) =>
                t.playlistId.equals(playlistId) &
                t.downloadId.equals(downloadId),
          )).go();
      if (deleted > 0) {
        await _resequenceUserPlaylist(playlistId);
        await _touchUserPlaylist(playlistId);
      }
      return deleted;
    });
  }

  /// Rewrite item positions in a user playlist.
  ///
  /// [orderedDownloadIds] may be partial: known ids are moved to the
  /// front in the supplied order, and any omitted current members keep
  /// their relative order after them. Unknown ids are ignored.
  Future<void> reorderUserPlaylist({
    required String playlistId,
    required List<int> orderedDownloadIds,
  }) async {
    await transaction(() async {
      final current = await _userPlaylistDownloadIds(playlistId);
      if (current.isEmpty) return;

      final currentSet = current.toSet();
      final seen = <int>{};
      final normalized = <int>[];
      for (final id in orderedDownloadIds) {
        if (!currentSet.contains(id) || !seen.add(id)) continue;
        normalized.add(id);
      }
      for (final id in current) {
        if (seen.add(id)) normalized.add(id);
      }

      await _writeUserPlaylistPositions(playlistId, normalized);
      await _touchUserPlaylist(playlistId);
    });
  }

  /// All playlists a download currently belongs to. Used by the row
  /// context menu to decide whether to show "Remove from playlist".
  Future<List<({String playlistId, String title})>> getPlaylistsForDownload(
    int downloadId,
  ) async {
    final rows =
        await customSelect(
          'SELECT p.id AS pid, p.title AS ptitle '
          'FROM user_playlists p '
          'INNER JOIN user_playlist_items i ON i.playlist_id = p.id '
          'WHERE i.download_id = ?1 '
          'ORDER BY p.updated_at DESC',
          variables: [Variable.withInt(downloadId)],
          readsFrom: {userPlaylists, userPlaylistItems},
        ).get();
    return rows
        .map(
          (row) => (
            playlistId: row.read<String>('pid'),
            title: row.read<String>('ptitle'),
          ),
        )
        .toList();
  }

  /// Watch user-playlist-membership changes. Drift turns this into a
  /// SQL trigger so the FilterTab.playlist popover repaints whenever
  /// add/remove writes land — even from another isolate.
  Stream<void> watchUserPlaylistChanges() {
    return customSelect(
      'SELECT 1 FROM user_playlist_items LIMIT 1',
      readsFrom: {userPlaylists, userPlaylistItems},
    ).watch().map((_) {});
  }

  Future<List<int>> _userPlaylistDownloadIds(String playlistId) async {
    final rows =
        await customSelect(
          'SELECT download_id AS did '
          'FROM user_playlist_items '
          'WHERE playlist_id = ?1 '
          'ORDER BY position ASC, added_at ASC',
          variables: [Variable.withString(playlistId)],
          readsFrom: {userPlaylistItems},
        ).get();
    return rows.map((row) => row.read<int>('did')).toList(growable: false);
  }

  Future<void> _resequenceUserPlaylist(String playlistId) async {
    final ids = await _userPlaylistDownloadIds(playlistId);
    await _writeUserPlaylistPositions(playlistId, ids);
  }

  Future<void> _writeUserPlaylistPositions(
    String playlistId,
    List<int> orderedDownloadIds,
  ) async {
    for (var i = 0; i < orderedDownloadIds.length; i++) {
      await (update(userPlaylistItems)..where(
        (t) =>
            t.playlistId.equals(playlistId) &
            t.downloadId.equals(orderedDownloadIds[i]),
      )).write(UserPlaylistItemsCompanion(position: Value(i)));
    }
  }

  Future<void> _touchUserPlaylist(String playlistId) async {
    await (update(userPlaylists)..where(
      (t) => t.id.equals(playlistId),
    )).write(UserPlaylistsCompanion(updatedAt: Value(DateTime.now())));
  }

  /// Batch-update queue positions for a list of download IDs.
  /// [orderedIds] is the new desired order — position 0 = first.
  /// Downloads NOT in the list retain their existing queuePosition.
  Future<void> updateQueuePositions(List<int> orderedIds) async {
    await transaction(() async {
      for (int i = 0; i < orderedIds.length; i++) {
        await (update(downloads)..where(
          (t) => t.id.equals(orderedIds[i]),
        )).write(DownloadsCompanion(queuePosition: Value(i)));
      }
    });
  }

  /// Update download status
  Future<void> updateDownloadStatus(
    int id,
    String status, {
    String? errorMessage,
  }) async {
    await (update(downloads)..where((t) => t.id.equals(id))).write(
      DownloadsCompanion(
        status: Value(status),
        updatedAt: Value(DateTime.now()),
        errorMessage: Value(errorMessage),
      ),
    );
  }

  /// Update temp dir path (for yt-dlp resume after app restart)
  Future<void> updateTempDirPath(int id, String? tempDirPath) async {
    await (update(downloads)..where((t) => t.id.equals(id))).write(
      DownloadsCompanion(
        tempDirPath: Value(tempDirPath),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Update download progress
  Future<void> updateDownloadProgress({
    required int id,
    required int downloadedBytes,
    required int speed,
  }) async {
    await (update(downloads)..where((t) => t.id.equals(id))).write(
      DownloadsCompanion(
        downloadedBytes: Value(downloadedBytes),
        speed: Value(speed),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Delete a download
  Future<int> deleteDownload(int id) async {
    return (delete(downloads)..where((t) => t.id.equals(id))).go();
  }

  /// Delete all completed downloads
  Future<int> deleteCompletedDownloads() async {
    return (delete(downloads)..where((t) => t.status.equals('completed'))).go();
  }

  /// Delete all failed downloads
  Future<int> deleteFailedDownloads() async {
    return (delete(downloads)..where((t) => t.status.equals('failed'))).go();
  }

  /// Delete all downloads
  Future<int> deleteAllDownloads() async {
    return delete(downloads).go();
  }

  /// Save user note on a download
  Future<void> saveUserNote(int id, String note) async {
    await (update(downloads)..where((t) => t.id.equals(id))).write(
      DownloadsCompanion(
        userNote: Value(note),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Increment retry count
  Future<void> incrementRetryCount(int id) async {
    final download = await getDownloadById(id);
    if (download != null) {
      await (update(downloads)..where((t) => t.id.equals(id))).write(
        DownloadsCompanion(
          retryCount: Value(download.retryCount + 1),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  /// Reset retry count after an explicit user retry.
  Future<void> resetRetryCount(int id) async {
    await (update(downloads)..where((t) => t.id.equals(id))).write(
      DownloadsCompanion(
        retryCount: const Value(0),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // ==================== DOWNLOAD STATISTICS ====================

  /// Get aggregate download statistics for the usage stats widget.
  Future<Map<String, dynamic>> getDownloadStatistics() async {
    final statsResult =
        await customSelect(
          'SELECT '
          'COUNT(*) as total, '
          "SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed, "
          "SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed, "
          "COALESCE(SUM(CASE WHEN status = 'completed' THEN total_bytes ELSE 0 END), 0) as total_bytes "
          'FROM downloads',
        ).getSingle();

    final platformRows =
        await customSelect(
          'SELECT platform, COUNT(*) as cnt FROM downloads '
          'GROUP BY platform ORDER BY cnt DESC',
        ).get();

    return {
      'total': statsResult.read<int>('total'),
      'completed': statsResult.read<int>('completed'),
      'failed': statsResult.read<int>('failed'),
      'totalBytes': statsResult.read<int>('total_bytes'),
      'byPlatform': {
        for (final r in platformRows)
          r.read<String>('platform'): r.read<int>('cnt'),
      },
    };
  }

  // ==================== SETTINGS QUERIES ====================

  /// Get setting value by key
  Future<String?> getSetting(String key) async {
    final result =
        await (select(appSettings)
          ..where((t) => t.key.equals(key))).getSingleOrNull();
    return result?.value;
  }

  /// Set setting value
  Future<void> setSetting(String key, String value) async {
    await into(
      appSettings,
    ).insertOnConflictUpdate(AppSetting(key: key, value: value));
  }

  /// Delete setting
  Future<int> deleteSetting(String key) async {
    return (delete(appSettings)..where((t) => t.key.equals(key))).go();
  }

  /// Get all settings
  Future<List<AppSetting>> getAllSettings() async {
    return select(appSettings).get();
  }

  // ==================== SUBSCRIBED CHANNELS QUERIES ====================

  /// Get all subscribed channels ordered by subscription date (newest first)
  Future<List<SubscribedChannel>> getAllSubscribedChannels() async {
    return (select(subscribedChannels)..orderBy([
      (t) => OrderingTerm(expression: t.subscribedAt, mode: OrderingMode.desc),
    ])).get();
  }

  /// Get channels with new videos
  Future<List<SubscribedChannel>> getChannelsWithNewVideos() async {
    return (select(subscribedChannels)
      ..where((t) => t.hasNewVideos.equals(true))).get();
  }

  /// Get subscribed channel by channel ID
  Future<SubscribedChannel?> getSubscribedChannelByChannelId(
    String channelId,
  ) async {
    return (select(subscribedChannels)
      ..where((t) => t.channelId.equals(channelId))).getSingleOrNull();
  }

  /// Check if channel is subscribed
  Future<bool> isChannelSubscribed(String channelId) async {
    final result = await getSubscribedChannelByChannelId(channelId);
    return result != null;
  }

  /// Subscribe to a channel
  Future<int> subscribeToChannel(SubscribedChannelsCompanion channel) async {
    return into(subscribedChannels).insert(channel);
  }

  /// Unsubscribe from a channel
  Future<int> unsubscribeFromChannel(String channelId) async {
    return (delete(subscribedChannels)
      ..where((t) => t.channelId.equals(channelId))).go();
  }

  /// Update channel info (subscriber count, video count, etc.)
  Future<void> updateChannelInfo({
    required String channelId,
    String? channelName,
    String? thumbnail,
    int? subscriberCount,
    int? videoCount,
  }) async {
    await (update(subscribedChannels)
      ..where((t) => t.channelId.equals(channelId))).write(
      SubscribedChannelsCompanion(
        channelName:
            channelName != null ? Value(channelName) : const Value.absent(),
        thumbnail: thumbnail != null ? Value(thumbnail) : const Value.absent(),
        subscriberCount:
            subscriberCount != null
                ? Value(subscriberCount)
                : const Value.absent(),
        videoCount:
            videoCount != null ? Value(videoCount) : const Value.absent(),
      ),
    );
  }

  /// Update latest video info and mark as having new videos
  Future<void> updateChannelLatestVideo({
    required String channelId,
    required String latestVideoId,
    required String latestVideoTitle,
    required DateTime latestVideoDate,
  }) async {
    await (update(subscribedChannels)
      ..where((t) => t.channelId.equals(channelId))).write(
      SubscribedChannelsCompanion(
        latestVideoId: Value(latestVideoId),
        latestVideoTitle: Value(latestVideoTitle),
        latestVideoDate: Value(latestVideoDate),
        hasNewVideos: const Value(true),
        lastChecked: Value(DateTime.now()),
      ),
    );
  }

  /// Set baseline latest video WITHOUT marking as new.
  /// Used at subscribe time to prevent false positives on first check.
  Future<void> setChannelLatestVideoBaseline({
    required String channelId,
    required String latestVideoId,
    required String latestVideoTitle,
    required DateTime latestVideoDate,
  }) async {
    await (update(subscribedChannels)
      ..where((t) => t.channelId.equals(channelId))).write(
      SubscribedChannelsCompanion(
        latestVideoId: Value(latestVideoId),
        latestVideoTitle: Value(latestVideoTitle),
        latestVideoDate: Value(latestVideoDate),
        hasNewVideos: const Value(false),
        lastChecked: Value(DateTime.now()),
      ),
    );
  }

  /// Mark channel as checked (clear new videos badge)
  Future<void> markChannelAsViewed(String channelId) async {
    await (update(subscribedChannels)..where(
      (t) => t.channelId.equals(channelId),
    )).write(const SubscribedChannelsCompanion(hasNewVideos: Value(false)));
  }

  /// Update last checked timestamp
  Future<void> updateChannelLastChecked(String channelId) async {
    await (update(subscribedChannels)..where(
      (t) => t.channelId.equals(channelId),
    )).write(SubscribedChannelsCompanion(lastChecked: Value(DateTime.now())));
  }

  /// Watch all subscribed channels (reactive stream)
  Stream<List<SubscribedChannel>> watchSubscribedChannels() {
    return (select(subscribedChannels)..orderBy([
      (t) => OrderingTerm(expression: t.subscribedAt, mode: OrderingMode.desc),
    ])).watch();
  }

  /// Watch channels with new videos count
  Stream<int> watchNewVideosCount() {
    final query =
        selectOnly(subscribedChannels)
          ..addColumns([subscribedChannels.id.count()])
          ..where(subscribedChannels.hasNewVideos.equals(true));

    return query
        .map((row) => row.read(subscribedChannels.id.count()) ?? 0)
        .watchSingle();
  }

  // ==================== DOWNLOAD TAGS QUERIES (v9) ====================

  /// Insert a tag for a download. Silently ignored if already exists.
  Future<void> insertTag(int downloadId, String tag) async {
    final exists =
        await (select(downloadTags)..where(
          (t) => t.downloadId.equals(downloadId) & t.tag.equals(tag),
        )).getSingleOrNull();
    if (exists != null) return;
    await into(
      downloadTags,
    ).insert(DownloadTagsCompanion.insert(downloadId: downloadId, tag: tag));
  }

  /// Delete a specific tag from a download.
  Future<void> deleteTag(int downloadId, String tag) async {
    await (delete(downloadTags)
      ..where((t) => t.downloadId.equals(downloadId) & t.tag.equals(tag))).go();
  }

  /// Get all tags for a specific download (sorted alphabetically).
  Future<List<String>> getTagsForDownload(int downloadId) async {
    final rows =
        await (select(downloadTags)
              ..where((t) => t.downloadId.equals(downloadId))
              ..orderBy([(t) => OrderingTerm.asc(t.tag)]))
            .get();
    return rows.map((r) => r.tag).toList();
  }

  /// Get all distinct tags across all downloads (sorted alphabetically).
  Future<List<String>> getAllTags() async {
    final query =
        selectOnly(downloadTags, distinct: true)
          ..addColumns([downloadTags.tag])
          ..orderBy([OrderingTerm.asc(downloadTags.tag)]);
    final rows = await query.get();
    return rows.map((r) => r.read(downloadTags.tag)!).toList();
  }

  /// Get download IDs that have a specific tag.
  Future<List<int>> getDownloadIdsByTag(String tag) async {
    final rows =
        await (select(downloadTags)..where((t) => t.tag.equals(tag))).get();
    return rows.map((r) => r.downloadId).toList();
  }

  /// Get a map of downloadId → list of tags (for efficient bulk lookup).
  Future<Map<int, List<String>>> getAllTagsMap() async {
    final rows = await select(downloadTags).get();
    final map = <int, List<String>>{};
    for (final row in rows) {
      map.putIfAbsent(row.downloadId, () => []).add(row.tag);
    }
    return map;
  }

  /// Watch the full tags map as a stream.
  ///
  /// Emits a new [Map<int, List<String>>] whenever any row in [downloadTags]
  /// is inserted or deleted, allowing Riverpod to rebuild only tag-dependent
  /// providers rather than polling with a Future on every DB change.
  Stream<Map<int, List<String>>> watchAllTagsMap() {
    return select(downloadTags).watch().map((rows) {
      final map = <int, List<String>>{};
      for (final row in rows) {
        map.putIfAbsent(row.downloadId, () => []).add(row.tag);
      }
      return map;
    });
  }

  // ==================== CONVERSION JOBS QUERIES (v17) ====================

  /// Watch all conversion jobs ordered by creation date (newest first)
  Stream<List<ConversionJob>> watchConversionJobs() {
    return (select(conversionJobs)..orderBy([
      (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
    ])).watch();
  }

  /// Get all conversion jobs (non-reactive)
  Future<List<ConversionJob>> getAllConversionJobs() async {
    return (select(conversionJobs)..orderBy([
      (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
    ])).get();
  }

  /// Get a single conversion job by ID
  Future<ConversionJob?> getConversionJobById(String id) async {
    return (select(conversionJobs)
      ..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Insert a new conversion job
  Future<void> insertConversionJob(ConversionJobsCompanion job) async {
    await into(conversionJobs).insert(job);
  }

  /// Update conversion job status
  Future<void> updateConversionJobStatus(
    String id,
    String status, {
    String? errorMessage,
  }) async {
    await (update(conversionJobs)..where((t) => t.id.equals(id))).write(
      ConversionJobsCompanion(
        status: Value(status),
        errorMessage:
            errorMessage != null ? Value(errorMessage) : const Value.absent(),
      ),
    );
  }

  /// Update the persisted output target for a conversion job.
  Future<void> updateConversionJobOutputTarget(
    String id, {
    required String outputPath,
    required String outputFilename,
  }) async {
    await (update(conversionJobs)..where((t) => t.id.equals(id))).write(
      ConversionJobsCompanion(
        outputPath: Value(outputPath),
        outputFilename: Value(outputFilename),
      ),
    );
  }

  /// Update conversion job progress (called during active conversion)
  Future<void> updateConversionJobProgress(
    String id, {
    required String status,
    required double progress,
    int? outputSize,
    String? errorMessage,
    DateTime? startedAt,
    DateTime? completedAt,
  }) async {
    await (update(conversionJobs)..where((t) => t.id.equals(id))).write(
      ConversionJobsCompanion(
        status: Value(status),
        progress: Value(progress),
        outputSize:
            outputSize != null ? Value(outputSize) : const Value.absent(),
        errorMessage:
            errorMessage != null ? Value(errorMessage) : const Value.absent(),
        startedAt: startedAt != null ? Value(startedAt) : const Value.absent(),
        completedAt:
            completedAt != null ? Value(completedAt) : const Value.absent(),
      ),
    );
  }

  /// Delete a conversion job
  Future<int> deleteConversionJob(String id) async {
    return (delete(conversionJobs)..where((t) => t.id.equals(id))).go();
  }

  /// Get conversion jobs by status
  Future<List<ConversionJob>> getConversionJobsByStatus(String status) async {
    return (select(conversionJobs)
      ..where((t) => t.status.equals(status))).get();
  }

  /// Delete all completed conversions
  Future<int> deleteCompletedConversions() async {
    return (delete(conversionJobs)
      ..where((t) => t.status.equals('completed'))).go();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    if (!await dbFolder.exists()) {
      await dbFolder.create(recursive: true);
    }
    final dbName =
        AppConstants.databaseName; // 'svid' or 'vidcombo' (no extension)
    final file = File(p.join(dbFolder.path, '$dbName.db'));

    // === Recovery from c8bbba91 regression ===
    // Multi-brand commit shipped with `databaseName = 'svid.db'` and code that
    // appended `.db` again, producing the orphan path `svid.db.db`. Users who
    // updated to that build had their real DB silently abandoned at the correct
    // path while a fresh empty DB was created at the buggy path.
    //
    // After fixing the typo, code reads the correct path again. For users who
    // installed FRESH during the buggy window, however, all their data is in
    // the orphan `.db.db` file — recover it ONCE if the correct path is empty.
    if (!file.existsSync()) {
      final orphanPath = p.join(dbFolder.path, '$dbName.db.db');
      final orphan = File(orphanPath);
      if (orphan.existsSync()) {
        try {
          // Bring the orphan + its WAL/SHM siblings (if any) to the canonical path.
          orphan.copySync(file.path);
          for (final ext in ['-wal', '-shm']) {
            final sidecar = File(orphanPath + ext);
            if (sidecar.existsSync()) {
              sidecar.copySync(file.path + ext);
            }
          }
          appLogger.warning(
            'DB recovery: copied orphan "$orphanPath" → "${file.path}" '
            '(c8bbba91 regression). Orphan left in place for safety.',
          );
        } catch (e, stack) {
          appLogger.error('DB recovery failed for $orphanPath', e, stack);
        }
      }
    }

    // Make sqlite3 pick a more suitable location for temporary files on Android
    if (Platform.isAndroid) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }

    // Make the sqlite3 dynamic library available for Drift on Linux
    final cacheDir = await getTemporaryDirectory();
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    final cachebase = cacheDir.path;
    sqlite3.tempDirectory = cachebase;

    return NativeDatabase.createInBackground(file);
  });
}
