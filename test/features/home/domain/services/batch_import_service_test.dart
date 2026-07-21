import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/home/domain/services/batch_import_service.dart';

void main() {
  const service = BatchImportService();

  group('BatchImportService', () {
    group('parseUrls', () {
      test('returns empty result for empty string', () {
        final result = service.parseUrls('');
        expect(result.validUrls, isEmpty);
        expect(result.skippedLines, isEmpty);
        expect(result.duplicateCount, 0);
        expect(result.hasValidUrls, false);
        expect(result.totalLines, 0);
      });

      test('returns empty result for whitespace-only string', () {
        final result = service.parseUrls('   \n  \n   ');
        expect(result.validUrls, isEmpty);
        expect(result.skippedLines, isEmpty);
        expect(result.duplicateCount, 0);
        expect(result.hasValidUrls, false);
      });

      test('parses single valid URL', () {
        final result = service.parseUrls('https://youtube.com/watch?v=abc');
        expect(result.validUrls, ['https://youtube.com/watch?v=abc']);
        expect(result.skippedLines, isEmpty);
        expect(result.duplicateCount, 0);
        expect(result.hasValidUrls, true);
        expect(result.totalLines, 1);
      });

      test('parses multiple valid URLs', () {
        final result = service.parseUrls(
          'https://youtube.com/watch?v=abc\n'
          'https://tiktok.com/@user/video/123\n'
          'https://instagram.com/p/xyz',
        );
        expect(result.validUrls.length, 3);
        expect(result.skippedLines, isEmpty);
        expect(result.duplicateCount, 0);
        expect(result.totalLines, 3);
      });

      test('skips invalid URLs', () {
        final result = service.parseUrls(
          'https://youtube.com/watch?v=abc\n'
          'not a url\n'
          'ftp://invalid.com',
        );
        expect(result.validUrls, ['https://youtube.com/watch?v=abc']);
        expect(result.skippedLines, ['not a url', 'ftp://invalid.com']);
        expect(result.duplicateCount, 0);
        expect(result.totalLines, 3);
      });

      test('deduplicates URLs (case-sensitive)', () {
        final result = service.parseUrls(
          'https://youtube.com/watch?v=abc\n'
          'https://youtube.com/watch?v=abc\n'
          'https://youtube.com/watch?v=ABC',
        );
        expect(result.validUrls.length, 2);
        expect(result.validUrls[0], 'https://youtube.com/watch?v=abc');
        expect(result.validUrls[1], 'https://youtube.com/watch?v=ABC');
        expect(result.duplicateCount, 1);
      });

      test('ignores blank lines (not counted as skipped)', () {
        final result = service.parseUrls(
          'https://youtube.com/watch?v=abc\n'
          '\n'
          '   \n'
          'https://tiktok.com/@user/video/123',
        );
        expect(result.validUrls.length, 2);
        expect(result.skippedLines, isEmpty);
        expect(result.duplicateCount, 0);
        expect(result.totalLines, 2);
      });

      test('trims whitespace from URLs', () {
        final result = service.parseUrls(
          '  https://youtube.com/watch?v=abc  \n'
          '   https://tiktok.com/@user/video/123   ',
        );
        expect(result.validUrls, [
          'https://youtube.com/watch?v=abc',
          'https://tiktok.com/@user/video/123',
        ]);
      });

      test('handles mixed valid, invalid, and duplicate URLs', () {
        final result = service.parseUrls(
          'https://youtube.com/watch?v=abc\n'
          'not valid\n'
          'https://tiktok.com/@user/video/123\n'
          'https://youtube.com/watch?v=abc\n'
          'also not valid\n'
          'https://instagram.com/p/xyz',
        );
        expect(result.validUrls.length, 3);
        expect(result.skippedLines.length, 2);
        expect(result.duplicateCount, 1);
        expect(result.totalLines, 6);
        expect(result.hasValidUrls, true);
      });

      test('handles URLs without path', () {
        final result = service.parseUrls('https://example.com');
        expect(result.validUrls, ['https://example.com']);
        expect(result.hasValidUrls, true);
      });

      test('rejects URLs without scheme', () {
        final result = service.parseUrls('youtube.com/watch?v=abc');
        expect(result.validUrls, isEmpty);
        expect(result.skippedLines, ['youtube.com/watch?v=abc']);
      });

      test('rejects URLs without host', () {
        final result = service.parseUrls('https://');
        expect(result.validUrls, isEmpty);
        expect(result.skippedLines, ['https://']);
      });

      test('preserves first occurrence when deduplicating', () {
        final result = service.parseUrls(
          'https://youtube.com/watch?v=first\n'
          'https://youtube.com/watch?v=second\n'
          'https://youtube.com/watch?v=first',
        );
        expect(result.validUrls, [
          'https://youtube.com/watch?v=first',
          'https://youtube.com/watch?v=second',
        ]);
        expect(result.duplicateCount, 1);
      });

      test('handles http URLs', () {
        final result = service.parseUrls('http://example.com/video');
        expect(result.validUrls, ['http://example.com/video']);
        expect(result.hasValidUrls, true);
      });

      test('multiple duplicates counted correctly', () {
        final result = service.parseUrls(
          'https://youtube.com/watch?v=abc\n'
          'https://youtube.com/watch?v=abc\n'
          'https://youtube.com/watch?v=abc\n'
          'https://youtube.com/watch?v=abc',
        );
        expect(result.validUrls.length, 1);
        expect(result.duplicateCount, 3);
        expect(result.totalLines, 4);
      });
    });

    group('BatchImportResult', () {
      test('hasValidUrls returns true when validUrls is not empty', () {
        const result = BatchImportResult(
          validUrls: ['https://example.com'],
          skippedLines: [],
          duplicateCount: 0,
        );
        expect(result.hasValidUrls, true);
      });

      test('hasValidUrls returns false when validUrls is empty', () {
        const result = BatchImportResult(
          validUrls: [],
          skippedLines: ['bad url'],
          duplicateCount: 0,
        );
        expect(result.hasValidUrls, false);
      });

      test('totalLines sums valid + skipped + duplicates (excl. blank)', () {
        const result = BatchImportResult(
          validUrls: ['https://a.com', 'https://b.com'],
          skippedLines: ['bad'],
          duplicateCount: 1,
        );
        expect(result.totalLines, 4); // 2 valid + 1 skipped + 1 duplicate
      });
    });
  });
}
