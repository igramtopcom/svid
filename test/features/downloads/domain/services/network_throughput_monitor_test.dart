import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/domain/entities/download_entity.dart';
import 'package:ssvid/features/downloads/domain/entities/download_status.dart';
import 'package:ssvid/features/downloads/domain/services/network_throughput_monitor.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  DownloadEntity makeDownload({
    required int id,
    required DownloadStatus status,
    int speed = 0,
  }) {
    return DownloadEntity(
      id: id,
      url: 'https://example.com/$id',
      filename: 'file_$id.mp4',
      savePath: '/tmp',
      status: status,
      totalBytes: 10 * 1024 * 1024,
      downloadedBytes: 0,
      speed: speed,
      platform: 'youtube',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
  }

  // ---------------------------------------------------------------------------
  // aggregateThroughput
  // ---------------------------------------------------------------------------

  group('NetworkThroughputMonitor.aggregateThroughput', () {
    test('returns 0 for empty list', () {
      expect(NetworkThroughputMonitor.aggregateThroughput([]), 0);
    });

    test('sums speed of all downloading items', () {
      final downloads = [
        makeDownload(id: 1, status: DownloadStatus.downloading, speed: 500000),
        makeDownload(id: 2, status: DownloadStatus.downloading, speed: 700000),
      ];
      expect(NetworkThroughputMonitor.aggregateThroughput(downloads), 1200000);
    });

    test('ignores paused downloads', () {
      final downloads = [
        makeDownload(id: 1, status: DownloadStatus.paused, speed: 999999),
        makeDownload(id: 2, status: DownloadStatus.downloading, speed: 300000),
      ];
      expect(NetworkThroughputMonitor.aggregateThroughput(downloads), 300000);
    });

    test('ignores completed downloads', () {
      final downloads = [
        makeDownload(id: 1, status: DownloadStatus.completed, speed: 5000000),
        makeDownload(id: 2, status: DownloadStatus.downloading, speed: 200000),
      ];
      expect(NetworkThroughputMonitor.aggregateThroughput(downloads), 200000);
    });

    test('ignores failed downloads', () {
      final downloads = [
        makeDownload(id: 1, status: DownloadStatus.failed, speed: 100000),
        makeDownload(id: 2, status: DownloadStatus.downloading, speed: 400000),
      ];
      expect(NetworkThroughputMonitor.aggregateThroughput(downloads), 400000);
    });

    test('returns 0 when all downloads are non-active', () {
      final downloads = [
        makeDownload(id: 1, status: DownloadStatus.paused, speed: 100000),
        makeDownload(id: 2, status: DownloadStatus.queued, speed: 200000),
        makeDownload(id: 3, status: DownloadStatus.completed, speed: 300000),
      ];
      expect(NetworkThroughputMonitor.aggregateThroughput(downloads), 0);
    });

    test('sums three concurrent downloads correctly', () {
      final downloads = [
        makeDownload(id: 1, status: DownloadStatus.downloading, speed: 1 * 1024 * 1024),
        makeDownload(id: 2, status: DownloadStatus.downloading, speed: 2 * 1024 * 1024),
        makeDownload(id: 3, status: DownloadStatus.downloading, speed: 3 * 1024 * 1024),
      ];
      expect(
        NetworkThroughputMonitor.aggregateThroughput(downloads),
        6 * 1024 * 1024,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // computeEffectiveConcurrencyLimit
  // ---------------------------------------------------------------------------

  group('NetworkThroughputMonitor.computeEffectiveConcurrencyLimit', () {
    const userMax = 5;

    test('returns userMax when aggregate == 0 (no active downloads)', () {
      expect(
        NetworkThroughputMonitor.computeEffectiveConcurrencyLimit(
          aggregateSpeedBps: 0,
          userConfiguredMax: userMax,
        ),
        userMax,
      );
    });

    test('returns 1 when aggregate < 1 MB/s (512 KB/s)', () {
      expect(
        NetworkThroughputMonitor.computeEffectiveConcurrencyLimit(
          aggregateSpeedBps: 512 * 1024, // 512 KB/s
          userConfiguredMax: userMax,
        ),
        1,
      );
    });

    test('returns 1 when aggregate is just below 1 MB/s (1048575 bps)', () {
      expect(
        NetworkThroughputMonitor.computeEffectiveConcurrencyLimit(
          aggregateSpeedBps: 1048575,
          userConfiguredMax: userMax,
        ),
        1,
      );
    });

    test('returns 2 when aggregate == exactly 1 MB/s (boundary: not < 1 MB/s)', () {
      // 1 MB/s is NOT < _kLowThresholdBps → falls to mid-tier
      expect(
        NetworkThroughputMonitor.computeEffectiveConcurrencyLimit(
          aggregateSpeedBps: 1 * 1024 * 1024,
          userConfiguredMax: userMax,
        ),
        2,
      );
    });

    test('returns 2 when aggregate is mid-tier (2 MB/s)', () {
      expect(
        NetworkThroughputMonitor.computeEffectiveConcurrencyLimit(
          aggregateSpeedBps: 2 * 1024 * 1024,
          userConfiguredMax: userMax,
        ),
        2,
      );
    });

    test('returns 2 when aggregate is just below 5 MB/s (5242879 bps)', () {
      expect(
        NetworkThroughputMonitor.computeEffectiveConcurrencyLimit(
          aggregateSpeedBps: 5 * 1024 * 1024 - 1,
          userConfiguredMax: userMax,
        ),
        2,
      );
    });

    test('clamps mid-tier to userMax when userMax == 1', () {
      expect(
        NetworkThroughputMonitor.computeEffectiveConcurrencyLimit(
          aggregateSpeedBps: 2 * 1024 * 1024,
          userConfiguredMax: 1,
        ),
        1,
      );
    });

    test('returns userMax when aggregate == exactly 5 MB/s (boundary: not < 5 MB/s)', () {
      // 5 MB/s is NOT < _kMidThresholdBps → top tier
      expect(
        NetworkThroughputMonitor.computeEffectiveConcurrencyLimit(
          aggregateSpeedBps: 5 * 1024 * 1024,
          userConfiguredMax: userMax,
        ),
        userMax,
      );
    });

    test('returns userMax when aggregate > 5 MB/s (10 MB/s)', () {
      expect(
        NetworkThroughputMonitor.computeEffectiveConcurrencyLimit(
          aggregateSpeedBps: 10 * 1024 * 1024,
          userConfiguredMax: userMax,
        ),
        userMax,
      );
    });

    test('respects userMax of 1 in top tier', () {
      expect(
        NetworkThroughputMonitor.computeEffectiveConcurrencyLimit(
          aggregateSpeedBps: 10 * 1024 * 1024,
          userConfiguredMax: 1,
        ),
        1,
      );
    });

    test('respects userMax of 2 in top tier', () {
      expect(
        NetworkThroughputMonitor.computeEffectiveConcurrencyLimit(
          aggregateSpeedBps: 10 * 1024 * 1024,
          userConfiguredMax: 2,
        ),
        2,
      );
    });
  });
}
