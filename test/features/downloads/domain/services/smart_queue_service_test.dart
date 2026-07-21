import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/domain/entities/download_entity.dart';
import 'package:svid/features/downloads/domain/entities/download_priority.dart';
import 'package:svid/features/downloads/domain/entities/download_status.dart';
import 'package:svid/features/downloads/domain/services/smart_queue_service.dart';

void main() {
  late SmartQueueService service;

  setUp(() {
    service = SmartQueueService();
  });

  group('suggestPriority', () {
    test('returns high when platform count >= 5', () {
      final history = {'youtube': 5};
      expect(
        service.suggestPriority('youtube', '', history),
        DownloadPriority.high,
      );
    });

    test('returns high when platform count > 5', () {
      final history = {'youtube': 10};
      expect(
        service.suggestPriority('youtube', '', history),
        DownloadPriority.high,
      );
    });

    test('returns normal when platform count >= 2 and < 5', () {
      final history = {'tiktok': 3};
      expect(
        service.suggestPriority('tiktok', '', history),
        DownloadPriority.normal,
      );
    });

    test('returns normal when platform count == 2', () {
      final history = {'tiktok': 2};
      expect(
        service.suggestPriority('tiktok', '', history),
        DownloadPriority.normal,
      );
    });

    test('returns low when platform count < 2', () {
      final history = {'instagram': 1};
      expect(
        service.suggestPriority('instagram', '', history),
        DownloadPriority.low,
      );
    });

    test('returns low when platform not in history', () {
      final history = {'youtube': 10};
      expect(
        service.suggestPriority('vimeo', '', history),
        DownloadPriority.low,
      );
    });

    test('returns low when history is empty', () {
      expect(
        service.suggestPriority('youtube', '', {}),
        DownloadPriority.low,
      );
    });

    test('mediaType parameter is accepted but unused', () {
      final history = {'youtube': 5};
      expect(
        service.suggestPriority('youtube', 'video', history),
        DownloadPriority.high,
      );
      expect(
        service.suggestPriority('youtube', 'audio', history),
        DownloadPriority.high,
      );
    });
  });

  group('computePlatformFrequency', () {
    DownloadEntity makeDownload({
      required int id,
      required String platform,
      required DownloadStatus status,
    }) {
      return DownloadEntity(
        id: id,
        url: 'https://example.com/$id',
        filename: 'file_$id.mp4',
        savePath: '/tmp',
        status: status,
        totalBytes: 1000,
        downloadedBytes: 1000,
        speed: 0,
        platform: platform,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
    }

    test('counts only completed downloads', () {
      final downloads = [
        makeDownload(id: 1, platform: 'youtube', status: DownloadStatus.completed),
        makeDownload(id: 2, platform: 'youtube', status: DownloadStatus.failed),
        makeDownload(id: 3, platform: 'youtube', status: DownloadStatus.downloading),
      ];
      final freq = service.computePlatformFrequency(downloads);
      expect(freq['youtube'], 1);
    });

    test('counts per platform correctly', () {
      final downloads = [
        makeDownload(id: 1, platform: 'youtube', status: DownloadStatus.completed),
        makeDownload(id: 2, platform: 'youtube', status: DownloadStatus.completed),
        makeDownload(id: 3, platform: 'tiktok', status: DownloadStatus.completed),
      ];
      final freq = service.computePlatformFrequency(downloads);
      expect(freq['youtube'], 2);
      expect(freq['tiktok'], 1);
    });

    test('returns empty map for empty list', () {
      expect(service.computePlatformFrequency([]), isEmpty);
    });

    test('skips downloads with empty platform', () {
      final downloads = [
        makeDownload(id: 1, platform: '', status: DownloadStatus.completed),
      ];
      final freq = service.computePlatformFrequency(downloads);
      expect(freq, isEmpty);
    });

    test('skips non-completed downloads entirely', () {
      final downloads = [
        makeDownload(id: 1, platform: 'youtube', status: DownloadStatus.pending),
        makeDownload(id: 2, platform: 'youtube', status: DownloadStatus.paused),
        makeDownload(id: 3, platform: 'youtube', status: DownloadStatus.cancelled),
      ];
      final freq = service.computePlatformFrequency(downloads);
      expect(freq, isEmpty);
    });
  });
}
