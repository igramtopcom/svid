import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/config/brand_config.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/providers/database_provider.dart';

/// Imports media files from old VidCombo install locations into the new
/// app's Drift Downloads table on first launch — silently and idempotently.
///
/// **Why this exists**
/// The old VidCombo (PHP/ObjectBox-based) stored downloaded files at
/// `~/Documents/VidCombo/` and `~/Downloads/VidCombo/`. Its ObjectBox DB
/// is essentially schema-only (no rich download history per real-world
/// inspection), so the only signal we can trust is the filesystem itself.
///
/// **What it does**
/// On the first launch of the new VidCombo app:
///   1. Scans the two legacy folders for media files.
///   2. Inserts a Drift `Downloads` row for each one with status=completed,
///      `platform='unknown'` (UI badge hides cleanly + distribution lumps
///      under "Other"), `downloadMethod='legacy_import'` (internal-only
///      marker, never displayed), title derived from filename,
///      createdAt = file mtime.
///   3. Sets a SharedPreferences flag so it never re-runs.
///
/// **Vision**: Seamless. The user never sees a dialog, notification, or any
/// hint that a migration happened. They open the new app and their old
/// library is just there.
///
/// Brand-guarded: no-op for SSvid.
class VidComboLegacyImporter {
  VidComboLegacyImporter({
    required AppDatabase database,
    required Future<SharedPreferences> Function() prefsLoader,
  })  : _database = database,
        _prefsLoader = prefsLoader;

  final AppDatabase _database;
  final Future<SharedPreferences> Function() _prefsLoader;

  /// SharedPreferences key — stores the app version that last ran the import.
  /// Re-scans on every new app version to catch files missed by earlier builds
  /// (e.g. bug fixes to path scanning, new folders added). Dedup by filename
  /// prevents re-importing already-imported files.
  static const _kDoneFlag = 'vidcombo_legacy_import_done_v1';
  static const _kVersionFlag = 'vidcombo_legacy_import_version';

  /// Media extensions we'll import. Mirrors the resolver's set so the two
  /// stay in sync (anything we count as "live legacy" we will also import).
  static const _supportedExts = <String>{
    '.mp4', '.mkv', '.webm', '.mov', '.m4v', '.avi', '.flv', '.ts',
    '.mp3', '.m4a', '.opus', '.ogg', '.wav', '.flac', '.aac',
  };

  /// Run if needed. Always safe to call from any startup path.
  /// Returns the number of files imported (0 if no-op).
  Future<int> runIfNeeded() async {
    if (BrandConfig.current.brand != Brand.vidcombo) {
      return 0;
    }

    SharedPreferences prefs;
    try {
      prefs = await _prefsLoader();
    } catch (e) {
      appLogger.warning(
        '[VidComboLegacyImporter] cannot load prefs: $e (skipping)',
      );
      return 0;
    }

    // Version-aware gate: re-scan on every new app version to catch files
    // missed by earlier builds (new scan paths, bug fixes). Dedup by filename
    // prevents re-importing. Also respects the legacy boolean flag for
    // backward compatibility — new installs use the version flag instead.
    final doneVersion = prefs.getString(_kVersionFlag);
    if (doneVersion == AppConstants.appVersion) {
      return 0;
    }
    // Also check the old boolean flag — if set AND we haven't switched to
    // version tracking yet, honour it (no re-scan on same version upgrade).
    if (doneVersion == null && prefs.getBool(_kDoneFlag) == true) {
      // Migrate to version-based tracking: mark current version as done.
      try {
        await prefs.setString(_kVersionFlag, AppConstants.appVersion);
      } catch (_) {}
      return 0;
    }

    final home = Platform.isWindows
        ? (Platform.environment['USERPROFILE'] ?? '')
        : (Platform.environment['HOME'] ?? '');
    if (home.isEmpty) {
      // No home directory — nothing we can do. Don't set the flag (try again
      // next launch).
      return 0;
    }

    final candidates = <String>{
      p.join(home, 'Documents', 'VidCombo'),
      p.join(home, 'Downloads', 'VidCombo'),
      p.join(home, 'Downloads', 'VidCombo App Downloader'),
      // Users who manually filed VidCombo output under a Dropbox / Google
      // Drive root still deserve a seamless migration. Cloud providers do
      // not set a uniform env var on Windows the way OneDrive does, so we
      // probe the standard install locations directly.
      p.join(home, 'Dropbox', 'VidCombo'),
      p.join(home, 'Dropbox', 'Documents', 'VidCombo'),
      p.join(home, 'Dropbox', 'Downloads', 'VidCombo'),
      p.join(home, 'Google Drive', 'VidCombo'),
      p.join(home, 'Google Drive', 'Documents', 'VidCombo'),
      p.join(home, 'Google Drive', 'Downloads', 'VidCombo'),
    };

    // Windows OneDrive often redirects Documents/Downloads folders via
    // Known Folder Move. Scan the OneDrive-rooted paths so users whose
    // profile folders are backed by OneDrive don't miss their legacy
    // library.
    if (Platform.isWindows) {
      final oneDrive = Platform.environment['OneDrive'] ?? '';
      if (oneDrive.isNotEmpty) {
        candidates
          ..add(p.join(oneDrive, 'Documents', 'VidCombo'))
          ..add(p.join(oneDrive, 'Downloads', 'VidCombo'))
          ..add(p.join(oneDrive, 'Downloads', 'VidCombo App Downloader'));
      }
    }

    // Pre-load every existing filename into an in-memory Set so folder
    // scanning runs one DB query total, not one per file. In production
    // ~50k VidCombo devices often have libraries of thousands of files —
    // under the old `_isAlreadyImported` path, each legacy file triggered
    // its own SELECT, turning first-launch import into thousands of
    // sequential fsync'd reads. Fetch once, compare in-memory, done.
    final Set<String> existingFilenames = await _loadExistingFilenames();

    int total = 0;
    bool shouldRetry = false;
    for (final folderPath in candidates) {
      try {
        total += await _importFolder(folderPath, existingFilenames);
      } on FileSystemException catch (e) {
        // TCC permission denied (Documents/Downloads access not granted) or
        // similar I/O blockage. The folder may exist with real legacy files
        // we just can't see yet — DO NOT burn the one-shot flag. Retry on
        // the next launch after the user grants access in
        // System Settings → Privacy & Security → Files and Folders.
        shouldRetry = true;
        appLogger.warning(
          '[VidComboLegacyImporter] cannot read $folderPath '
          '(permission denied — will retry next launch): ${e.message}',
        );
      } catch (e, st) {
        // Any error scanning a folder means we might have missed files.
        // Don't burn the flag — retry next launch.
        shouldRetry = true;
        appLogger.warning(
          '[VidComboLegacyImporter] folder import failed for '
          '$folderPath: $e\n$st',
        );
      }
    }

    // Mark this version as scanned only on a clean sweep. If ANY folder
    // had an error (permission, I/O, corrupted symlink, etc.), leave the
    // flag unset so the next launch retries. Dedup by filename prevents
    // already-imported files from being re-inserted.
    if (!shouldRetry) {
      try {
        await prefs.setString(_kVersionFlag, AppConstants.appVersion);
        // Also set old boolean flag for backward compat (in case user
        // downgrades to an older build that only checks the boolean).
        await prefs.setBool(_kDoneFlag, true);
      } catch (e) {
        appLogger.warning(
          '[VidComboLegacyImporter] could not persist flag: $e',
        );
      }
    }

    if (total > 0) {
      appLogger.info(
        '[VidComboLegacyImporter] silently imported $total legacy file(s)',
      );
    } else if (shouldRetry) {
      appLogger.debug(
        '[VidComboLegacyImporter] no files imported '
        '(errors encountered — will retry next launch)',
      );
    } else {
      appLogger.debug(
        '[VidComboLegacyImporter] no legacy files found (flag set)',
      );
    }
    return total;
  }

  Future<int> _importFolder(
    String folderPath,
    Set<String> existingFilenames,
  ) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return 0;

    // Collect first, then insert in ONE transaction. Old-VidCombo users
    // with thousands of legacy files otherwise triggered thousands of
    // individual SQLite writes on first launch (first-launch lag).
    final rows = <DownloadsCompanion>[];

    // handleError: true so the stream survives unreadable subdirectories
    // (e.g. TCC-blocked, broken symlinks) instead of aborting mid-scan.
    await for (final entity in dir
        .list(recursive: true, followLinks: false)
        .handleError((Object e) {
      appLogger.debug(
        '[VidComboLegacyImporter] listing error in $folderPath: $e',
      );
    })) {
      if (entity is! File) continue;
      final basename = p.basename(entity.path);
      if (basename.startsWith('.')) continue; // .DS_Store etc.

      final ext = p.extension(basename).toLowerCase();
      if (!_supportedExts.contains(ext)) continue;

      try {
        final parentDir = p.dirname(entity.path);
        // Filename-only dedup — matches the old behaviour where the same
        // file often existed in both ~/Documents/VidCombo/ and
        // ~/Downloads/VidCombo/. Also prevents cross-folder re-insertion
        // within a single run (the set is shared across all candidate
        // folders, and we mutate it as we go).
        if (existingFilenames.contains(basename)) continue;

        final stat = await entity.stat();
        // Anything ≤ 0 bytes is a stub from a failed download — skip it,
        // we don't want phantom rows in the new library.
        if (stat.size <= 0) continue;

        final title = _titleFromFilename(p.basenameWithoutExtension(basename));

        rows.add(
          DownloadsCompanion.insert(
            url: '', // Source URL was never recorded by old app.
            filename: basename,
            savePath: parentDir,
            status: 'completed',
            totalBytes: Value(stat.size),
            downloadedBytes: Value(stat.size),
            // platform='unknown' so UI badge hides cleanly and the
            // platform-distribution rank groups these under "Other".
            // The internal marker lives in downloadMethod, which is
            // never displayed in any UI surface (audited 2026-04-07).
            platform: const Value('unknown'),
            downloadMethod: const Value('legacy_import'),
            title: Value(title),
            createdAt: Value(stat.modified),
            updatedAt: Value(stat.modified),
          ),
        );
        existingFilenames.add(basename);
      } catch (e) {
        appLogger.debug(
          '[VidComboLegacyImporter] skipped ${entity.path}: $e',
        );
      }
    }

    if (rows.isEmpty) return 0;

    // One transaction, one commit — 1000 legacy files no longer = 1000
    // individual fsync() writes on first launch.
    await _database.transaction(() async {
      await _database.batch((b) {
        b.insertAll(_database.downloads, rows);
      });
    });
    return rows.length;
  }

  /// @visibleForTesting — direct entry point so unit tests can exercise the
  /// folder-scan + dedup + 0-byte-skip + batch-insert path without having to
  /// mock out [BrandConfig] for the brand-guarded [runIfNeeded] wrapper.
  ///
  /// If [existingFilenames] is omitted, the current DB contents are loaded
  /// first — matching the pre-optimization behaviour where each file check
  /// queried the database. Callers that invoke this helper repeatedly (e.g.
  /// the "dedup across folders" test) should pass the same set on each call
  /// to preserve cross-call dedup.
  @visibleForTesting
  Future<int> importFolderForTest(
    String folderPath, {
    Set<String>? existingFilenames,
  }) async {
    final set = existingFilenames ?? await _loadExistingFilenames();
    return _importFolder(folderPath, set);
  }

  /// @visibleForTesting — expose the title cleanup for direct assertions.
  @visibleForTesting
  String titleFromFilenameForTest(String stem) => _titleFromFilename(stem);

  /// One query replaces N per-file `_isAlreadyImported` round-trips. The
  /// caller passes the returned set to `_importFolder` and we mutate it as
  /// rows are queued, so duplicates across candidate folders are still
  /// suppressed without re-querying the database.
  Future<Set<String>> _loadExistingFilenames() async {
    final rows = await (_database.selectOnly(_database.downloads)
          ..addColumns([_database.downloads.filename]))
        .get();
    return {
      for (final row in rows)
        if (row.read(_database.downloads.filename) case final String name)
          name
    };
  }

  /// Strip common old-VidCombo numeric suffixes (e.g. `_3`, `_24`) that the
  /// old app appended for duplicates. Falls back to the raw stem.
  String _titleFromFilename(String stem) {
    // Remove trailing `_<digits>` (e.g. "Title_3" → "Title").
    final cleaned = stem.replaceFirst(RegExp(r'_\d+$'), '');
    return cleaned.trim().isEmpty ? stem : cleaned.trim();
  }

  /// Video extensions eligible for ffmpeg thumbnail extraction.
  static const _videoExts = <String>{
    '.mp4', '.mkv', '.webm', '.mov', '.m4v', '.avi', '.flv', '.ts',
  };

  /// Generate thumbnails for legacy imports that have none.
  /// Call AFTER binaries are downloaded (needs ffmpeg). Runs in background,
  /// never blocks startup. Safe to call multiple times — skips entries that
  /// already have a thumbnail.
  Future<int> generateMissingThumbnails(String ffmpegPath) async {
    if (BrandConfig.current.brand != Brand.vidcombo) return 0;

    final appSupport = await getApplicationSupportDirectory();
    final thumbDir = Directory(p.join(appSupport.path, 'legacy_thumbnails'));
    if (!await thumbDir.exists()) {
      await thumbDir.create(recursive: true);
    }

    // Fetch all legacy imports with no thumbnail
    final query = _database.select(_database.downloads)
      ..where((t) =>
          t.downloadMethod.equals('legacy_import') & t.thumbnail.isNull());
    final rows = await query.get();

    int generated = 0;
    for (final row in rows) {
      final ext = p.extension(row.filename).toLowerCase();
      if (!_videoExts.contains(ext)) continue;

      final filePath = p.join(row.savePath, row.filename);
      if (!await File(filePath).exists()) continue;

      final thumbPath = p.join(thumbDir.path, '${row.id}.jpg');
      try {
        final result = await Process.run(ffmpegPath, [
          '-i', filePath,
          '-ss', '00:00:01',
          '-vframes', '1',
          '-vf', 'scale=320:-2',
          '-y',
          thumbPath,
        ]);

        if (result.exitCode == 0 && await File(thumbPath).exists()) {
          await (_database.update(_database.downloads)
                ..where((t) => t.id.equals(row.id)))
              .write(DownloadsCompanion(thumbnail: Value(thumbPath)));
          generated++;
        }
      } catch (e) {
        // Non-critical — placeholder thumbnail is fine.
        appLogger.debug(
          '[VidComboLegacyImporter] thumb failed for ${row.filename}: $e',
        );
      }
    }

    if (generated > 0) {
      appLogger.info(
        '[VidComboLegacyImporter] generated $generated thumbnail(s)',
      );
    }
    return generated;
  }
}

/// Riverpod provider — wired into the VidCombo startup flow.
final vidComboLegacyImporterProvider =
    Provider<VidComboLegacyImporter>((ref) {
  final db = ref.watch(databaseProvider);
  return VidComboLegacyImporter(
    database: db,
    prefsLoader: SharedPreferences.getInstance,
  );
});
