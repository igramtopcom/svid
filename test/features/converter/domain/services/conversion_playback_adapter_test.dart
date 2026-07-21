import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/converter/domain/entities/conversion_config.dart';
import 'package:svid/features/converter/domain/entities/conversion_job.dart';
import 'package:svid/features/converter/domain/entities/conversion_status.dart';
import 'package:svid/features/converter/domain/entities/output_format.dart';
import 'package:svid/features/converter/domain/services/conversion_playback_adapter.dart';
import 'package:svid/features/downloads/domain/entities/download_status.dart';

void main() {
  group('ConversionPlaybackAdapter', () {
    test('builds a completed download-shaped playback item', () {
      final createdAt = DateTime(2026, 1, 1);
      final completedAt = DateTime(2026, 1, 2);
      final job = ConversionJob(
        id: 'job-123',
        inputPath: '/tmp/input.mov',
        outputPath: '/tmp/output.mp4',
        inputFilename: 'input.mov',
        outputFilename: 'output.mp4',
        status: ConversionStatus.completed,
        inputSize: 100,
        outputSize: 42,
        inputDuration: const Duration(seconds: 12),
        presetName: 'Mobile MP4',
        config: const ConversionConfig(outputFormat: OutputFormat.mp4),
        createdAt: createdAt,
        completedAt: completedAt,
      );

      final item = ConversionPlaybackAdapter.toDownloadEntity(job);

      expect(item.id, isNegative);
      expect(item.url, 'file:///tmp/output.mp4');
      expect(item.filename, 'output.mp4');
      expect(item.savePath, '/tmp');
      expect(item.status, DownloadStatus.completed);
      expect(item.totalBytes, 42);
      expect(item.downloadedBytes, 42);
      expect(item.platform, 'converter');
      expect(item.downloadMethod, 'converter');
      expect(item.qualityLabel, 'Mobile MP4');
      expect(item.duration, 12);
    });

    test('stablePlaybackId is deterministic and negative', () {
      final a = ConversionPlaybackAdapter.stablePlaybackId('same-job');
      final b = ConversionPlaybackAdapter.stablePlaybackId('same-job');

      expect(a, b);
      expect(a, isNegative);
    });
  });
}
