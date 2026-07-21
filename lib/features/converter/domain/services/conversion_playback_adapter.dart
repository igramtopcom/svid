import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../downloads/domain/entities/download_entity.dart';
import '../../../downloads/domain/entities/download_status.dart';
import '../entities/conversion_job.dart';

/// Builds a download-shaped playback item for completed converter outputs.
///
/// Player screens still operate on DownloadEntity. Keeping this adapter at the
/// converter boundary lets converted files reuse the mature player path without
/// pretending they are persisted downloads.
class ConversionPlaybackAdapter {
  ConversionPlaybackAdapter._();

  static DownloadEntity toDownloadEntity(ConversionJob job, {int? fileSize}) {
    final size = fileSize ?? job.outputSize ?? _safeFileSize(job.outputPath);
    final filename = p.basename(job.outputPath);
    final now = DateTime.now();

    return DownloadEntity(
      id: stablePlaybackId(job.id),
      url: 'file://${job.outputPath}',
      filename: filename,
      savePath: p.dirname(job.outputPath),
      status: DownloadStatus.completed,
      totalBytes: size,
      downloadedBytes: size,
      speed: 0,
      platform: 'converter',
      createdAt: job.completedAt ?? job.createdAt,
      updatedAt: job.completedAt ?? now,
      title: p.basenameWithoutExtension(filename),
      duration: job.inputDuration?.inSeconds,
      downloadMethod: 'converter',
      qualityLabel: job.presetName ?? job.config.outputFormat.displayName,
    );
  }

  static int stablePlaybackId(String jobId) {
    var hash = 0x811c9dc5; // FNV-1a 32-bit offset basis
    for (final unit in jobId.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    if (hash == 0) return -1;
    return -hash;
  }

  static int _safeFileSize(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) return file.lengthSync();
    } catch (_) {
      // Size is non-critical for playback launch.
    }
    return 0;
  }
}
