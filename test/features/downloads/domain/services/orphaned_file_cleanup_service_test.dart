import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/core/errors/result.dart';
import 'package:ssvid/features/downloads/domain/entities/download_entity.dart';
import 'package:ssvid/features/downloads/domain/entities/download_status.dart';
import 'package:ssvid/features/downloads/domain/repositories/download_repository.dart';
import 'package:ssvid/features/downloads/domain/services/orphaned_file_cleanup_service.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Minimal fake repository — only getDownloadsByStatus needs to work
// ──────────────────────────────────────────────────────────────────────────────

class _FakeDownloadRepository extends Fake implements DownloadRepository {
  final List<DownloadEntity> activeDownloads;

  _FakeDownloadRepository([this.activeDownloads = const []]);

  @override
  Future<Result<List<DownloadEntity>>> getDownloadsByStatus(
      DownloadStatus status) async {
    return Result.success(
      activeDownloads.where((d) => d.status == status).toList(),
    );
  }
}

DownloadEntity _makeDownload({
  required String filename,
  required String savePath,
  required DownloadStatus status,
}) {
  return DownloadEntity(
    id: 1,
    url: 'https://example.com/video',
    filename: filename,
    savePath: savePath,
    status: status,
    downloadedBytes: 0,
    totalBytes: 1000,
    speed: 0,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    priority: 0,
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('orphan_test_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<File> createFile(String name) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes([0x00, 0x01, 0x02, 0x03]); // 4 bytes
    return file;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // findOrphanedFiles
  // ──────────────────────────────────────────────────────────────────────────

  group('findOrphanedFiles', () {
    test('returns empty list when directory does not exist', () async {
      final svc = OrphanedFileCleanupService(_FakeDownloadRepository());
      final result = await svc.findOrphanedFiles('/nonexistent/path/xyz');
      expect(result, isEmpty);
    });

    test('returns empty list when directory has no temp files', () async {
      await createFile('video.mp4');
      await createFile('audio.mp3');
      final svc = OrphanedFileCleanupService(_FakeDownloadRepository());
      final result = await svc.findOrphanedFiles(tempDir.path);
      expect(result, isEmpty);
    });

    test('detects .part file when no active download matches', () async {
      await createFile('video.mp4.part');
      final svc = OrphanedFileCleanupService(_FakeDownloadRepository());
      final files = await svc.findOrphanedFiles(tempDir.path);
      expect(files.length, 1);
      expect(files.first.path, endsWith('video.mp4.part'));
    });

    test('detects .ytdl file when no active download matches', () async {
      await createFile('video.mp4.ytdl');
      final svc = OrphanedFileCleanupService(_FakeDownloadRepository());
      final files = await svc.findOrphanedFiles(tempDir.path);
      expect(files.length, 1);
    });

    test('detects DASH fragment .part file (foo.f137.mp4.part)', () async {
      await createFile('myvideo.f137.mp4.part');
      final svc = OrphanedFileCleanupService(_FakeDownloadRepository());
      final files = await svc.findOrphanedFiles(tempDir.path);
      expect(files.length, 1);
    });

    test('protects .part file when matching active download exists', () async {
      final partFile = await createFile('video.mp4.part');

      final repo = _FakeDownloadRepository([
        _makeDownload(
          filename: 'video.mp4',
          savePath: tempDir.path,
          status: DownloadStatus.downloading,
        ),
      ]);
      final svc = OrphanedFileCleanupService(repo);
      final files = await svc.findOrphanedFiles(tempDir.path);
      expect(files, isEmpty);
      expect(await partFile.exists(), isTrue); // Not deleted
    });

    test('protects DASH .part file when matching active download exists', () async {
      await createFile('myvideo.f137.mp4.part');

      final repo = _FakeDownloadRepository([
        _makeDownload(
          filename: 'myvideo.mp4',
          savePath: tempDir.path,
          status: DownloadStatus.paused,
        ),
      ]);
      final svc = OrphanedFileCleanupService(repo);
      final files = await svc.findOrphanedFiles(tempDir.path);
      expect(files, isEmpty);
    });

    test('protects file for pending download', () async {
      await createFile('queued.mp4.part');

      final repo = _FakeDownloadRepository([
        _makeDownload(
          filename: 'queued.mp4',
          savePath: tempDir.path,
          status: DownloadStatus.pending,
        ),
      ]);
      final svc = OrphanedFileCleanupService(repo);
      expect(await svc.findOrphanedFiles(tempDir.path), isEmpty);
    });

    test('protects file for queued download', () async {
      await createFile('q.mp4.part');

      final repo = _FakeDownloadRepository([
        _makeDownload(
          filename: 'q.mp4',
          savePath: tempDir.path,
          status: DownloadStatus.queued,
        ),
      ]);
      final svc = OrphanedFileCleanupService(repo);
      expect(await svc.findOrphanedFiles(tempDir.path), isEmpty);
    });

    test('active download in different directory does NOT protect .part file', () async {
      await createFile('video.mp4.part');

      final repo = _FakeDownloadRepository([
        _makeDownload(
          filename: 'video.mp4',
          savePath: '/other/path', // different directory
          status: DownloadStatus.downloading,
        ),
      ]);
      final svc = OrphanedFileCleanupService(repo);
      final files = await svc.findOrphanedFiles(tempDir.path);
      expect(files.length, 1); // orphaned — different dir
    });

    test('mix: one protected, one orphaned', () async {
      await createFile('active.mp4.part');
      await createFile('orphan.mp4.part');

      final repo = _FakeDownloadRepository([
        _makeDownload(
          filename: 'active.mp4',
          savePath: tempDir.path,
          status: DownloadStatus.downloading,
        ),
      ]);
      final svc = OrphanedFileCleanupService(repo);
      final files = await svc.findOrphanedFiles(tempDir.path);
      expect(files.length, 1);
      expect(files.first.path, endsWith('orphan.mp4.part'));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // cleanup
  // ──────────────────────────────────────────────────────────────────────────

  group('cleanup', () {
    test('returns empty result when no orphaned files', () async {
      await createFile('video.mp4'); // not a temp file
      final svc = OrphanedFileCleanupService(_FakeDownloadRepository());
      final result = await svc.cleanup(tempDir.path);
      expect(result.filesFound, 0);
      expect(result.filesDeleted, 0);
      expect(result.bytesFreed, 0);
    });

    test('deletes orphaned .part file and reports correct counts', () async {
      final partFile = await createFile('orphan.mp4.part');
      final size = await partFile.length();

      final svc = OrphanedFileCleanupService(_FakeDownloadRepository());
      final result = await svc.cleanup(tempDir.path);

      expect(result.filesFound, 1);
      expect(result.filesDeleted, 1);
      expect(result.bytesFreed, size);
      expect(result.errors, isEmpty);
      expect(await partFile.exists(), isFalse);
    });

    test('deletes multiple orphaned files and sums bytes', () async {
      await createFile('a.mp4.part');
      await createFile('b.mp4.ytdl');

      final svc = OrphanedFileCleanupService(_FakeDownloadRepository());
      final result = await svc.cleanup(tempDir.path);

      expect(result.filesFound, 2);
      expect(result.filesDeleted, 2);
      expect(result.bytesFreed, 8); // 4 bytes per file × 2
    });

    test('does not delete protected file alongside orphaned file', () async {
      final active = await createFile('active.mp4.part');
      await createFile('orphan.mp4.part');

      final repo = _FakeDownloadRepository([
        _makeDownload(
          filename: 'active.mp4',
          savePath: tempDir.path,
          status: DownloadStatus.downloading,
        ),
      ]);
      final svc = OrphanedFileCleanupService(repo);
      final result = await svc.cleanup(tempDir.path);

      expect(result.filesDeleted, 1);
      expect(await active.exists(), isTrue); // protected file survives
    });

    test('returns empty result for nonexistent directory', () async {
      final svc = OrphanedFileCleanupService(_FakeDownloadRepository());
      final result = await svc.cleanup('/nonexistent/dir/xyz');
      expect(result.filesFound, 0);
      expect(result.filesDeleted, 0);
    });
  });
}
