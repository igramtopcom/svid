import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../core/errors/result.dart';
import '../../../../core/logging/app_logger.dart';
import '../entities/download_status.dart';
import '../repositories/download_repository.dart';

/// Result of a single orphaned-file cleanup run.
class OrphanedFileCleanupResult {
  final int filesFound;
  final int filesDeleted;
  final int bytesFreed;
  final List<String> errors;

  const OrphanedFileCleanupResult({
    required this.filesFound,
    required this.filesDeleted,
    required this.bytesFreed,
    required this.errors,
  });

  const OrphanedFileCleanupResult.empty()
      : filesFound = 0,
        filesDeleted = 0,
        bytesFreed = 0,
        errors = const [];
}

/// Detects and removes leftover temp files from cancelled / crashed downloads.
///
/// **Temp file patterns** (yt-dlp):
///   - `filename.ext.part`          — direct download in progress
///   - `filename.f<id>.ext.part`    — DASH fragment in progress
///   - `filename.ext.ytdl`          — yt-dlp metadata file
///
/// A temp file is **orphaned** when no download with status
/// `{pending, downloading, paused, queued}` has a matching base filename in
/// the same directory.
///
/// All I/O errors are caught and collected in [OrphanedFileCleanupResult.errors]
/// so the caller is never thrown at.
class OrphanedFileCleanupService {
  final DownloadRepository _repository;

  static const _tempExtensions = {'.part', '.ytdl'};

  /// Active statuses — temp files belonging to these downloads are protected.
  static const _activeStatuses = [
    DownloadStatus.pending,
    DownloadStatus.downloading,
    DownloadStatus.paused,
    DownloadStatus.queued,
  ];

  OrphanedFileCleanupService(this._repository);

  /// Scans [downloadDir] and returns all orphaned temp files.
  ///
  /// Returns an empty list if [downloadDir] does not exist or any error occurs.
  Future<List<File>> findOrphanedFiles(String downloadDir) async {
    final dir = Directory(downloadDir);
    if (!await dir.exists()) return [];

    try {
      final activeBaseNames = await _activeBaseNames(downloadDir);
      final orphaned = <File>[];

      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!_isTempFile(name)) continue;
        if (!_isOrphaned(name, activeBaseNames)) continue;
        orphaned.add(entity);
      }

      return orphaned;
    } catch (e) {
      appLogger.error('[OrphanCleanup] Error scanning $downloadDir: $e');
      return [];
    }
  }

  /// Deletes all orphaned temp files in [downloadDir].
  ///
  /// Never throws — errors are collected in the result.
  Future<OrphanedFileCleanupResult> cleanup(String downloadDir) async {
    final orphaned = await findOrphanedFiles(downloadDir);
    if (orphaned.isEmpty) return const OrphanedFileCleanupResult.empty();

    int deleted = 0;
    int bytesFreed = 0;
    final errors = <String>[];

    for (final file in orphaned) {
      try {
        final size = await file.length();
        await file.delete();
        deleted++;
        bytesFreed += size;
      } catch (e) {
        final name = p.basename(file.path);
        errors.add('$name: $e');
        appLogger.warning('[OrphanCleanup] Could not delete $name: $e');
      }
    }

    return OrphanedFileCleanupResult(
      filesFound: orphaned.length,
      filesDeleted: deleted,
      bytesFreed: bytesFreed,
      errors: errors,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────

  /// Returns the normalised base filenames of all active downloads in [dir].
  Future<Set<String>> _activeBaseNames(String dir) async {
    final names = <String>{};

    for (final status in _activeStatuses) {
      final result = await _repository.getDownloadsByStatus(status);
      for (final download in result.dataOrNull ?? []) {
        if (download.savePath == dir) {
          names.add(download.filename.toLowerCase());
        }
      }
    }

    return names;
  }

  /// Returns true if [filename] ends with a recognised temp extension.
  static bool _isTempFile(String filename) {
    return _tempExtensions.any((ext) => filename.endsWith(ext));
  }

  /// Returns true if the temp [filename] is NOT associated with any active
  /// download in [activeBaseNames].
  ///
  /// Derivation rules:
  ///   1. Strip `.part` or `.ytdl` suffix.
  ///   2. Strip optional yt-dlp DASH suffix: `.f<digits>.<ext>` → `.<ext>`.
  static bool _isOrphaned(String filename, Set<String> activeBaseNames) {
    String base = filename.toLowerCase();

    // Strip temp extension
    for (final ext in _tempExtensions) {
      if (base.endsWith(ext)) {
        base = base.substring(0, base.length - ext.length);
        break;
      }
    }

    // Strip DASH format suffix if present: e.g. "foo.f137.mp4" → "foo.mp4"
    base = base.replaceFirstMapped(
      RegExp(r'\.(f\d+)(\.[^.]+)$'),
      (m) => m.group(2)!,
    );

    return !activeBaseNames.contains(base);
  }
}
