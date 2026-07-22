import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../../../core/database/app_database.dart';

/// Result of a bulk file operation.
class BatchResult {
  final int succeeded;
  final int failed;
  final List<String> errors;

  const BatchResult({
    required this.succeeded,
    required this.failed,
    required this.errors,
  });

  bool get allSucceeded => failed == 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BatchResult &&
          succeeded == other.succeeded &&
          failed == other.failed;

  @override
  int get hashCode => Object.hash(succeeded, failed);

  @override
  String toString() =>
      'BatchResult(succeeded: $succeeded, failed: $failed)';
}

/// Pure-Dart service for bulk file operations (delete / move / rename).
///
/// All methods return a [BatchResult] — they never throw.
/// An empty [ids] list returns immediately with all-zero counts.
class BatchFileOperationsService {
  /// Delete DB records and optionally the files on disk.
  Future<BatchResult> deleteFiles(
    List<int> ids, {
    required AppDatabase db,
    bool deleteFromDisk = true,
  }) async {
    int succeeded = 0;
    int failed = 0;
    final errors = <String>[];

    for (final id in ids) {
      try {
        final row = await (db.select(db.downloads)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();

        if (row == null) {
          failed++;
          errors.add('Download #$id not found');
          continue;
        }

        if (deleteFromDisk && row.status == 'completed') {
          final filePath = p.join(row.savePath, row.filename);
          final file = File(filePath);
          if (file.existsSync()) {
            await file.delete();
          }
        }

        await (db.delete(db.downloads)..where((t) => t.id.equals(id))).go();
        succeeded++;
      } catch (e) {
        failed++;
        errors.add('Delete #$id: $e');
      }
    }

    return BatchResult(succeeded: succeeded, failed: failed, errors: errors);
  }

  /// Move completed files to [targetPath] and update `savePath` in DB.
  Future<BatchResult> moveFiles(
    List<int> ids,
    String targetPath, {
    required AppDatabase db,
  }) async {
    int succeeded = 0;
    int failed = 0;
    final errors = <String>[];

    try {
      await Directory(targetPath).create(recursive: true);
    } catch (_) {}

    for (final id in ids) {
      try {
        final row = await (db.select(db.downloads)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();

        if (row == null) {
          failed++;
          errors.add('Download #$id not found');
          continue;
        }

        var finalName = row.filename;
        if (row.status == 'completed') {
          final srcPath = p.join(row.savePath, row.filename);
          final src = File(srcPath);
          if (src.existsSync() &&
              srcPath != p.join(targetPath, row.filename)) {
            // Don't clobber an existing file at the destination.
            final stem = _stemOf(row.filename);
            final ext = _extensionOf(row.filename);
            var destPath = p.join(targetPath, finalName);
            var counter = 2;
            while (File(destPath).existsSync()) {
              finalName = '$stem ($counter)$ext';
              destPath = p.join(targetPath, finalName);
              counter++;
            }
            try {
              await src.rename(destPath);
            } on FileSystemException {
              // Cross-volume move (e.g. C: → D:): rename can't cross drives,
              // so copy then delete the source.
              await src.copy(destPath);
              await src.delete();
            }
          }
        }

        await (db.update(db.downloads)..where((t) => t.id.equals(id)))
            .write(
              DownloadsCompanion(
                savePath: Value(targetPath),
                filename: Value(finalName),
              ),
            );
        succeeded++;
      } catch (e) {
        failed++;
        errors.add('Move #$id: $e');
      }
    }

    return BatchResult(succeeded: succeeded, failed: failed, errors: errors);
  }

  /// Rename files using [pattern] tokens and update `filename` in DB.
  ///
  /// Pattern tokens: `{title}`, `{uploader}`, `{date}`, `{index}`
  Future<BatchResult> renameFiles(
    List<int> ids,
    String pattern, {
    required AppDatabase db,
  }) async {
    int succeeded = 0;
    int failed = 0;
    final errors = <String>[];
    // Full destination paths already claimed in THIS batch — used to guarantee
    // every renamed file gets a unique name (never clobber a sibling).
    final usedPaths = <String>{};

    for (int i = 0; i < ids.length; i++) {
      final id = ids[i];
      try {
        final row = await (db.select(db.downloads)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();

        if (row == null) {
          failed++;
          errors.add('Download #$id not found');
          continue;
        }

        final newBase = applyPattern(
          pattern,
          filename: row.filename,
          title: row.title,
          uploader: row.uploader,
          uploadDate: row.uploadDate,
          index: i + 1,
        );

        if (newBase.isEmpty) {
          failed++;
          errors.add('Rename #$id: pattern produced empty filename');
          continue;
        }

        final ext = _extensionOf(row.filename);
        final stem = _sanitizeFilename(newBase);
        final selfPath = p.join(row.savePath, row.filename);
        var newFilename = stem + ext;
        var newPath = p.join(row.savePath, newFilename);
        // Guarantee uniqueness: never overwrite another selected file (batch
        // dedupe) or an unrelated file already on disk. A pattern without
        // {index} that resolves to the same name for several files now yields
        // "name.ext", "name (2).ext", "name (3).ext" instead of clobbering.
        var counter = 2;
        while ((usedPaths.contains(newPath) || File(newPath).existsSync()) &&
            newPath != selfPath) {
          newFilename = '$stem ($counter)$ext';
          newPath = p.join(row.savePath, newFilename);
          counter++;
        }
        usedPaths.add(newPath);

        if (newFilename == row.filename) {
          succeeded++;
          continue;
        }

        if (row.status == 'completed') {
          final src = File(selfPath);
          if (src.existsSync()) {
            await src.rename(newPath);
          }
        }

        await (db.update(db.downloads)..where((t) => t.id.equals(id)))
            .write(DownloadsCompanion(filename: Value(newFilename)));
        succeeded++;
      } catch (e) {
        failed++;
        errors.add('Rename #$id: $e');
      }
    }

    return BatchResult(succeeded: succeeded, failed: failed, errors: errors);
  }

  /// Apply [pattern] tokens to produce a new filename stem (no extension).
  ///
  /// Exposed as @visibleForTesting equivalent for unit tests.
  String applyPattern(
    String pattern, {
    required String filename,
    String? title,
    String? uploader,
    String? uploadDate,
    required int index,
  }) {
    final stem = _stemOf(filename);
    final t = title?.isNotEmpty == true ? title! : stem;
    final u = uploader?.isNotEmpty == true ? uploader! : 'unknown';

    String date = '';
    if (uploadDate != null && uploadDate.length == 8) {
      date =
          '${uploadDate.substring(0, 4)}-${uploadDate.substring(4, 6)}-${uploadDate.substring(6)}';
    }

    return pattern
        .replaceAll('{title}', t)
        .replaceAll('{uploader}', u)
        .replaceAll('{date}', date)
        .replaceAll('{index}', index.toString());
  }

  String _stemOf(String filename) {
    final parts = filename.split('.');
    return parts.length > 1 ? parts.sublist(0, parts.length - 1).join('.') : filename;
  }

  String _extensionOf(String filename) {
    final parts = filename.split('.');
    return parts.length > 1 ? '.${parts.last}' : '';
  }

  String _sanitizeFilename(String name) =>
      name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').replaceAll(RegExp(r'\s+'), ' ').trim();
}
