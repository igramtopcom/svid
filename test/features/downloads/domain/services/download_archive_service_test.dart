import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:svid/features/downloads/domain/services/download_archive_service.dart';

void main() {
  late DownloadArchiveService service;

  setUp(() {
    service = DownloadArchiveService();
  });

  // ==================== extractVideoId ====================

  group('extractVideoId', () {
    test('extracts YouTube watch ID', () {
      expect(
        DownloadArchiveService.extractVideoId(
            'https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
    });

    test('extracts YouTube shorts ID', () {
      expect(
        DownloadArchiveService.extractVideoId(
            'https://youtube.com/shorts/abc123def'),
        'abc123def',
      );
    });

    test('extracts youtu.be ID', () {
      expect(
        DownloadArchiveService.extractVideoId(
            'https://youtu.be/dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
    });

    test('extracts TikTok video ID', () {
      expect(
        DownloadArchiveService.extractVideoId(
            'https://www.tiktok.com/@user/video/7123456789'),
        '7123456789',
      );
    });

    test('extracts Vimeo ID', () {
      expect(
        DownloadArchiveService.extractVideoId('https://vimeo.com/123456789'),
        '123456789',
      );
    });

    test('extracts Instagram reel ID', () {
      expect(
        DownloadArchiveService.extractVideoId(
            'https://www.instagram.com/reel/C1234567890/'),
        'C1234567890',
      );
    });

    test('extracts Instagram post ID', () {
      expect(
        DownloadArchiveService.extractVideoId(
            'https://www.instagram.com/p/CxYz1234/'),
        'CxYz1234',
      );
    });

    test('extracts Twitter status ID', () {
      expect(
        DownloadArchiveService.extractVideoId(
            'https://twitter.com/user/status/1234567890'),
        '1234567890',
      );
    });

    test('extracts X.com status ID', () {
      expect(
        DownloadArchiveService.extractVideoId(
            'https://x.com/user/status/9876543210'),
        '9876543210',
      );
    });

    test('extracts Facebook video ID', () {
      expect(
        DownloadArchiveService.extractVideoId(
            'https://www.facebook.com/user/videos/123456'),
        '123456',
      );
    });

    test('extracts Bilibili video ID', () {
      expect(
        DownloadArchiveService.extractVideoId(
            'https://www.bilibili.com/video/BV1xx411c7mD'),
        'BV1xx411c7mD',
      );
    });

    test('extracts Dailymotion video ID', () {
      expect(
        DownloadArchiveService.extractVideoId(
            'https://www.dailymotion.com/video/x8abc12'),
        'x8abc12',
      );
    });

    test('returns null for unsupported URL', () {
      expect(
        DownloadArchiveService.extractVideoId('https://example.com/some-page'),
        isNull,
      );
    });

    test('returns null for empty string', () {
      expect(DownloadArchiveService.extractVideoId(''), isNull);
    });

    test('returns null for malformed URL', () {
      expect(DownloadArchiveService.extractVideoId('not a url'), isNull);
    });
  });

  // ==================== checkDatabase ====================

  group('checkDatabase', () {
    test('returns isDuplicate=true for matching URL', () {
      final completed = [
        (
          url: 'https://youtube.com/watch?v=abc123',
          title: 'Test Video',
          updatedAt: DateTime(2026, 2, 28),
        ),
      ];

      final result = service.checkDatabase(
          'https://youtube.com/watch?v=abc123', completed);
      expect(result.isDuplicate, isTrue);
      expect(result.title, 'Test Video');
      expect(result.completedAt, DateTime(2026, 2, 28));
    });

    test('returns isDuplicate=true with URL normalization', () {
      final completed = [
        (
          url: 'https://youtube.com/watch?v=abc123',
          title: 'Test Video',
          updatedAt: DateTime(2026, 2, 28),
        ),
      ];

      // Same URL with tracking params should match
      final result = service.checkDatabase(
          'https://youtube.com/watch?v=abc123&utm_source=twitter', completed);
      expect(result.isDuplicate, isTrue);
    });

    test('returns isDuplicate=false for different URL', () {
      final completed = [
        (
          url: 'https://youtube.com/watch?v=abc123',
          title: 'Test Video',
          updatedAt: DateTime(2026, 2, 28),
        ),
      ];

      final result = service.checkDatabase(
          'https://youtube.com/watch?v=xyz789', completed);
      expect(result.isDuplicate, isFalse);
      expect(result.title, isNull);
      expect(result.reason, isNull);
    });

    test('returns isDuplicate=false for empty list', () {
      final result = service.checkDatabase(
          'https://youtube.com/watch?v=abc123', []);
      expect(result.isDuplicate, isFalse);
    });

    test('handles case-insensitive host matching', () {
      final completed = [
        (
          url: 'https://YouTube.COM/watch?v=abc123',
          title: 'Video',
          updatedAt: DateTime(2026, 2, 28),
        ),
      ];

      final result = service.checkDatabase(
          'https://youtube.com/watch?v=abc123', completed);
      expect(result.isDuplicate, isTrue);
    });

    test('handles trailing slash normalization', () {
      final completed = [
        (
          url: 'https://vimeo.com/123456/',
          title: 'Vimeo Video',
          updatedAt: DateTime(2026, 2, 28),
        ),
      ];

      final result = service.checkDatabase(
          'https://vimeo.com/123456', completed);
      expect(result.isDuplicate, isTrue);
    });
  });

  // ==================== checkArchiveFile ====================

  group('checkArchiveFile', () {
    late Directory tempDir;

    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('download_archive_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('returns isDuplicate=true when ID is in archive file', () async {
      final archivePath = '${tempDir.path}/.svid_archive.txt';
      await File(archivePath).writeAsString(
        'youtube dQw4w9WgXcQ\nyoutube abc123\n',
      );

      final result = await service.checkArchiveFile(
        'https://youtube.com/watch?v=dQw4w9WgXcQ',
        archivePath,
      );
      expect(result.isDuplicate, isTrue);
      expect(result.reason, contains('dQw4w9WgXcQ'));
    });

    test('returns isDuplicate=false when ID is not in archive', () async {
      final archivePath = '${tempDir.path}/.svid_archive.txt';
      await File(archivePath).writeAsString(
        'youtube abc123\nyoutube xyz789\n',
      );

      final result = await service.checkArchiveFile(
        'https://youtube.com/watch?v=notInArchive',
        archivePath,
      );
      expect(result.isDuplicate, isFalse);
    });

    test('returns notFound when archive file does not exist', () async {
      final result = await service.checkArchiveFile(
        'https://youtube.com/watch?v=abc123',
        '${tempDir.path}/nonexistent.txt',
      );
      expect(result.isDuplicate, isFalse);
    });

    test('returns notFound when video ID cannot be extracted', () async {
      final archivePath = '${tempDir.path}/.svid_archive.txt';
      await File(archivePath).writeAsString('youtube abc123\n');

      final result = await service.checkArchiveFile(
        'https://example.com/not-a-video',
        archivePath,
      );
      expect(result.isDuplicate, isFalse);
    });

    test('handles empty archive file gracefully', () async {
      final archivePath = '${tempDir.path}/.svid_archive.txt';
      await File(archivePath).writeAsString('');

      final result = await service.checkArchiveFile(
        'https://youtube.com/watch?v=abc123',
        archivePath,
      );
      expect(result.isDuplicate, isFalse);
    });

    test('handles archive with blank lines', () async {
      final archivePath = '${tempDir.path}/.svid_archive.txt';
      await File(archivePath).writeAsString(
        '\nyoutube abc123\n\n\nyoutube xyz789\n\n',
      );

      final result = await service.checkArchiveFile(
        'https://youtube.com/watch?v=xyz789',
        archivePath,
      );
      expect(result.isDuplicate, isTrue);
    });

    test('matches TikTok ID in archive', () async {
      final archivePath = '${tempDir.path}/.svid_archive.txt';
      await File(archivePath).writeAsString('tiktok 7123456789\n');

      final result = await service.checkArchiveFile(
        'https://www.tiktok.com/@user/video/7123456789',
        archivePath,
      );
      expect(result.isDuplicate, isTrue);
    });
  });

  // ==================== hashUrl ====================

  group('hashUrl', () {
    test('produces consistent hash for same URL', () {
      final hash1 = DownloadArchiveService.hashUrl(
          'https://youtube.com/watch?v=abc');
      final hash2 = DownloadArchiveService.hashUrl(
          'https://youtube.com/watch?v=abc');
      expect(hash1, hash2);
    });

    test('ignores tracking params in hash', () {
      final hash1 = DownloadArchiveService.hashUrl(
          'https://youtube.com/watch?v=abc');
      final hash2 = DownloadArchiveService.hashUrl(
          'https://youtube.com/watch?v=abc&utm_source=twitter');
      expect(hash1, hash2);
    });

    test('produces different hash for different URLs', () {
      final hash1 = DownloadArchiveService.hashUrl(
          'https://youtube.com/watch?v=abc');
      final hash2 = DownloadArchiveService.hashUrl(
          'https://youtube.com/watch?v=xyz');
      expect(hash1, isNot(hash2));
    });
  });

  // ==================== addToArchive ====================

  group('addToArchive', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('archive_write_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('creates file and appends entry', () async {
      final path = '${tempDir.path}/archive.txt';
      await service.addToArchive('youtube', 'abc123', path);

      final content = await File(path).readAsString();
      expect(content, contains('youtube abc123'));
    });

    test('appends multiple entries', () async {
      final path = '${tempDir.path}/archive.txt';
      await service.addToArchive('youtube', 'abc123', path);
      await service.addToArchive('tiktok', '9876543', path);

      final lines = await File(path).readAsLines();
      final nonEmpty = lines.where((l) => l.trim().isNotEmpty).toList();
      expect(nonEmpty.length, 2);
      expect(nonEmpty[0], 'youtube abc123');
      expect(nonEmpty[1], 'tiktok 9876543');
    });

    test('normalizes platform to lowercase', () async {
      final path = '${tempDir.path}/archive.txt';
      await service.addToArchive('YouTube', 'abc123', path);

      final content = await File(path).readAsString();
      expect(content, contains('youtube abc123'));
    });
  });

  // ==================== removeFromArchive ====================

  group('removeFromArchive', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('archive_remove_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('removes matching entry', () async {
      final path = '${tempDir.path}/archive.txt';
      await File(path).writeAsString('youtube abc123\nyoutube xyz789\n');

      await service.removeFromArchive('abc123', path);

      final lines = await File(path).readAsLines();
      final nonEmpty = lines.where((l) => l.trim().isNotEmpty).toList();
      expect(nonEmpty, hasLength(1));
      expect(nonEmpty.first, 'youtube xyz789');
    });

    test('does nothing when file does not exist', () async {
      final path = '${tempDir.path}/nonexistent.txt';
      // Should not throw
      await service.removeFromArchive('abc123', path);
      expect(await File(path).exists(), isFalse);
    });

    test('handles removing last entry', () async {
      final path = '${tempDir.path}/archive.txt';
      await File(path).writeAsString('youtube abc123\n');

      await service.removeFromArchive('abc123', path);

      final content = await File(path).readAsString();
      expect(content.trim(), isEmpty);
    });
  });

  // ==================== getArchiveCount ====================

  group('getArchiveCount', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('archive_count_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('returns 0 for nonexistent file', () async {
      final count =
          await service.getArchiveCount('${tempDir.path}/nonexistent.txt');
      expect(count, 0);
    });

    test('returns 0 for empty file', () async {
      final path = '${tempDir.path}/archive.txt';
      await File(path).writeAsString('');
      expect(await service.getArchiveCount(path), 0);
    });

    test('counts entries correctly', () async {
      final path = '${tempDir.path}/archive.txt';
      await File(path).writeAsString('youtube abc\nyoutube xyz\ntiktok 123\n');
      expect(await service.getArchiveCount(path), 3);
    });

    test('ignores blank lines', () async {
      final path = '${tempDir.path}/archive.txt';
      await File(path).writeAsString('\nyoutube abc\n\nyoutube xyz\n\n');
      expect(await service.getArchiveCount(path), 2);
    });
  });

  // ==================== clearArchive ====================

  group('clearArchive', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('archive_clear_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('empties the file', () async {
      final path = '${tempDir.path}/archive.txt';
      await File(path).writeAsString('youtube abc123\nyoutube xyz789\n');

      await service.clearArchive(path);

      final content = await File(path).readAsString();
      expect(content, isEmpty);
    });

    test('does nothing when file does not exist', () async {
      final path = '${tempDir.path}/nonexistent.txt';
      await service.clearArchive(path);
      expect(await File(path).exists(), isFalse);
    });
  });

  // ==================== importArchive ====================

  group('importArchive', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('archive_import_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('imports entries into empty target', () async {
      final source = File('${tempDir.path}/source.txt');
      await source.writeAsString('youtube abc123\nyoutube xyz789\n');
      final targetPath = '${tempDir.path}/target.txt';

      await service.importArchive(source, targetPath);

      final lines = await File(targetPath).readAsLines();
      final nonEmpty = lines.where((l) => l.trim().isNotEmpty).toList();
      expect(nonEmpty.length, 2);
    });

    test('merges without duplicates', () async {
      final source = File('${tempDir.path}/source.txt');
      await source.writeAsString('youtube abc123\nyoutube new999\n');
      final targetPath = '${tempDir.path}/target.txt';
      await File(targetPath).writeAsString('youtube abc123\n');

      await service.importArchive(source, targetPath);

      final lines = await File(targetPath).readAsLines();
      final nonEmpty = lines.where((l) => l.trim().isNotEmpty).toList();
      // Only "youtube new999" should be added (abc123 is duplicate)
      expect(nonEmpty.length, 2);
    });

    test('does nothing if source does not exist', () async {
      final source = File('${tempDir.path}/nonexistent.txt');
      final targetPath = '${tempDir.path}/target.txt';
      await service.importArchive(source, targetPath);
      expect(await File(targetPath).exists(), isFalse);
    });
  });

  // ==================== exportArchive ====================

  group('exportArchive', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('archive_export_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('returns file when it exists', () async {
      final path = '${tempDir.path}/archive.txt';
      await File(path).writeAsString('youtube abc123\n');

      final result = await service.exportArchive(path);
      expect(result, isNotNull);
      expect(await result!.exists(), isTrue);
    });

    test('returns null when file does not exist', () async {
      final result = await service.exportArchive(
          '${tempDir.path}/nonexistent.txt');
      expect(result, isNull);
    });
  });
}
