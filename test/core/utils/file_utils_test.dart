import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/utils/file_utils.dart';

void main() {
  group('FileUtils.sanitizeFilename', () {
    test('removes invalid filesystem characters', () {
      expect(FileUtils.sanitizeFilename('file<>:"/\\|?*name'), 'file_________name');
    });

    test('strips null bytes', () {
      expect(FileUtils.sanitizeFilename('file\x00name'), 'filename');
    });

    test('trims trailing dots (Windows restriction)', () {
      expect(FileUtils.sanitizeFilename('filename.'), 'filename');
      expect(FileUtils.sanitizeFilename('filename...'), 'filename');
    });

    test('trims trailing spaces (Windows restriction)', () {
      expect(FileUtils.sanitizeFilename('filename   '), 'filename');
    });

    test('trims trailing mix of dots and spaces', () {
      expect(FileUtils.sanitizeFilename('filename. . .'), 'filename');
    });

    test('preserves dots within filename', () {
      expect(FileUtils.sanitizeFilename('my.video.file'), 'my.video.file');
    });

    test('replaces control characters with space', () {
      expect(FileUtils.sanitizeFilename('file\nname'), 'file name');
      expect(FileUtils.sanitizeFilename('file\tname'), 'file name');
    });

    test('collapses multiple spaces', () {
      expect(FileUtils.sanitizeFilename('file   name'), 'file name');
    });

    test('returns fallback for empty/whitespace-only input', () {
      expect(FileUtils.sanitizeFilename('   '), 'download');
    });

    test('handles real-world problematic title', () {
      // Q&A: "Best Setup?" 2024/25 [4K] — the / : " should become _
      final result = FileUtils.sanitizeFilename('Q&A: "Best Setup?" 2024/25 [4K]');
      expect(result, 'Q&A_ _Best Setup__ 2024_25 [4K]');
    });
  });

  group('FileUtils.normalizeUrlForDuplicateCheck', () {
    test('strips utm_source parameter', () {
      final url = 'https://www.youtube.com/watch?v=ABC&utm_source=share';
      expect(FileUtils.normalizeUrlForDuplicateCheck(url),
          'https://www.youtube.com/watch?v=ABC');
    });

    test('strips YouTube si= tracking parameter', () {
      final url = 'https://www.youtube.com/watch?v=ABC&si=xyz123';
      expect(FileUtils.normalizeUrlForDuplicateCheck(url),
          'https://www.youtube.com/watch?v=ABC');
    });

    test('strips feature= parameter', () {
      final url = 'https://www.youtube.com/watch?v=ABC&feature=shared';
      expect(FileUtils.normalizeUrlForDuplicateCheck(url),
          'https://www.youtube.com/watch?v=ABC');
    });

    test('strips fragment (#) from URL', () {
      final url = 'https://example.com/video?v=123#timestamp';
      expect(FileUtils.normalizeUrlForDuplicateCheck(url),
          'https://example.com/video?v=123');
    });

    test('strips multiple tracking params at once', () {
      final url = 'https://www.youtube.com/watch?v=ABC&si=x&utm_source=share&feature=shared';
      expect(FileUtils.normalizeUrlForDuplicateCheck(url),
          'https://www.youtube.com/watch?v=ABC');
    });

    test('preserves non-tracking query params', () {
      final url = 'https://www.youtube.com/watch?v=ABC&list=PL123';
      expect(FileUtils.normalizeUrlForDuplicateCheck(url),
          'https://www.youtube.com/watch?v=ABC&list=PL123');
    });

    test('returns original URL unchanged for invalid URLs', () {
      expect(FileUtils.normalizeUrlForDuplicateCheck('not-a-url'), 'not-a-url');
    });

    test('handles URL with no query params', () {
      final url = 'https://example.com/video';
      expect(FileUtils.normalizeUrlForDuplicateCheck(url), 'https://example.com/video');
    });
  });

  group('FileUtils.moveFile', () {
    test('moves an existing file and removes the source', () async {
      final dir = await Directory.systemTemp.createTemp('svid_file_move_');
      try {
        final source = File('${dir.path}/source.txt');
        final destination = File('${dir.path}/destination.txt');
        await source.writeAsString('payload');

        final moved = await FileUtils.moveFile(source.path, destination.path);

        expect(moved, isTrue);
        expect(await source.exists(), isFalse);
        expect(await destination.readAsString(), 'payload');
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('returns false when the source file is missing', () async {
      final dir = await Directory.systemTemp.createTemp('svid_file_move_');
      try {
        final moved = await FileUtils.moveFile(
          '${dir.path}/missing.txt',
          '${dir.path}/destination.txt',
        );

        expect(moved, isFalse);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
