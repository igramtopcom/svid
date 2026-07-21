import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/domain/entities/download_entity.dart';
import 'package:ssvid/features/downloads/domain/entities/download_status.dart';
import 'package:ssvid/features/downloads/domain/services/download_history_export_service.dart';

DownloadEntity _makeEntity({
  int id = 1,
  String filename = 'video.mp4',
  String url = 'https://example.com/video',
  String platform = 'youtube',
  DownloadStatus status = DownloadStatus.completed,
  String savePath = '/tmp',
  int totalBytes = 1000,
  int downloadedBytes = 1000,
  String? errorMessage,
}) =>
    DownloadEntity(
      id: id,
      url: url,
      filename: filename,
      savePath: savePath,
      status: status,
      totalBytes: totalBytes,
      downloadedBytes: downloadedBytes,
      speed: 0,
      platform: platform,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 2),
      errorMessage: errorMessage,
    );

void main() {
  const service = DownloadHistoryExportService();

  group('DownloadHistoryExportService', () {
    group('generateCsv', () {
      test('empty list produces header row only', () {
        final csv = service.generateCsv([]);
        final lines = csv.trim().split('\n');
        expect(lines.length, 1);
        expect(
          lines[0],
          'id,filename,url,platform,status,savePath,totalBytes,downloadedBytes,createdAt,updatedAt,errorMessage',
        );
      });

      test('single download produces header + 1 data row', () {
        final csv = service.generateCsv([_makeEntity()]);
        final lines = csv.trim().split('\n');
        expect(lines.length, 2);
        expect(lines[1], contains('video.mp4'));
        expect(lines[1], contains('youtube'));
        expect(lines[1], contains('completed'));
      });

      test('multiple downloads produce correct row count', () {
        final csv = service.generateCsv([
          _makeEntity(id: 1, filename: 'a.mp4'),
          _makeEntity(id: 2, filename: 'b.mp4'),
          _makeEntity(id: 3, filename: 'c.mp4'),
        ]);
        final lines = csv.trim().split('\n');
        expect(lines.length, 4); // header + 3 rows
      });

      test('includes error message when present', () {
        final csv = service.generateCsv([
          _makeEntity(
            status: DownloadStatus.failed,
            errorMessage: 'Network error',
          ),
        ]);
        expect(csv, contains('Network error'));
      });

      test('null error message produces empty trailing field', () {
        final csv = service.generateCsv([_makeEntity(errorMessage: null)]);
        final lines = csv.trim().split('\n');
        // Last field is empty string → row ends with comma
        expect(lines[1].endsWith(','), isTrue);
      });

      test('dates are ISO 8601 formatted', () {
        final csv = service.generateCsv([_makeEntity()]);
        expect(csv, contains('2026-01-01'));
        expect(csv, contains('2026-01-02'));
      });
    });

    group('escapeCsv', () {
      test('plain string passes through unchanged', () {
        expect(service.escapeCsv('hello'), 'hello');
      });

      test('value with comma is wrapped in double-quotes', () {
        expect(service.escapeCsv('hello,world'), '"hello,world"');
      });

      test('value with double-quote is escaped and wrapped', () {
        expect(service.escapeCsv('say "hi"'), '"say ""hi"""');
      });

      test('value with newline is wrapped in double-quotes', () {
        expect(service.escapeCsv('line1\nline2'), '"line1\nline2"');
      });

      test('value with carriage return is wrapped', () {
        expect(service.escapeCsv('line1\rline2'), '"line1\rline2"');
      });

      test('empty string passes through unchanged', () {
        expect(service.escapeCsv(''), '');
      });

      test('value with comma and double-quote is properly escaped', () {
        expect(service.escapeCsv('a,"b"'), '"a,""b"""');
      });
    });
  });
}
