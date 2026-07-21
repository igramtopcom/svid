import 'dart:io';

import '../../domain/entities/conversion_config.dart';
import '../../domain/entities/conversion_job.dart';
import '../../domain/entities/hw_accel_info.dart';
import '../../domain/entities/media_info.dart';
import '../../domain/repositories/conversion_repository.dart';
import '../datasources/conversion_datasource.dart';

/// Concrete implementation of [ConversionRepository].
///
/// Delegates all operations to [ConversionDatasource] and handles
/// cleanup of partial output files on cancellation/failure.
class ConversionRepositoryImpl implements ConversionRepository {
  final ConversionDatasource _datasource;

  ConversionRepositoryImpl(this._datasource);

  @override
  Stream<ConversionProgress> convertFile(ConversionJob job) async* {
    await for (final progress in _datasource.convert(
      jobId: job.id,
      inputPath: job.inputPath,
      outputPath: job.outputPath,
      config: job.config,
      inputDuration: job.inputDuration,
    )) {
      yield progress;

      // On error, clean up partial output
      if (progress.error != null) {
        _cleanupPartialOutput(job.outputPath);
      }
    }
  }

  @override
  Stream<ConversionProgress> stabilizeFile(ConversionJob job) async* {
    await for (final progress in _datasource.stabilize(
      jobId: job.id,
      inputPath: job.inputPath,
      outputPath: job.outputPath,
      config: job.config,
      inputDuration: job.inputDuration,
    )) {
      yield progress;

      if (progress.error != null) {
        _cleanupPartialOutput(job.outputPath);
      }
    }
  }

  @override
  Stream<ConversionProgress> concatFiles({
    required String jobId,
    required List<String> inputFiles,
    required String outputPath,
    required ConversionConfig config,
    Duration? totalDuration,
  }) async* {
    await for (final progress in _datasource.concat(
      jobId: jobId,
      inputFiles: inputFiles,
      outputPath: outputPath,
      config: config,
      totalDuration: totalDuration,
    )) {
      yield progress;

      if (progress.error != null) {
        _cleanupPartialOutput(outputPath);
      }
    }
  }

  @override
  Future<MediaInfo> probeFile(String filePath) {
    return _datasource.probeMediaInfo(filePath);
  }

  @override
  Future<List<HwAccelInfo>> detectHardwareAccel() {
    return _datasource.detectHwAccel();
  }

  @override
  void cancelConversion(String jobId) {
    _datasource.cancelConversion(jobId);
  }

  @override
  Future<String?> extractThumbnail({
    required String inputPath,
    required String outputPath,
    required double timestamp,
    String? jobId,
  }) {
    return _datasource.extractThumbnail(
      inputPath: inputPath,
      outputPath: outputPath,
      timestamp: timestamp,
      jobId: jobId,
    );
  }

  @override
  Future<String?> getOrExtractInputThumbnail(String inputPath) {
    return _datasource.getOrExtractInputThumbnail(inputPath);
  }

  @override
  Future<String?> extractSubtitles({
    required String inputPath,
    required String outputPath,
    int trackIndex = 0,
    String? jobId,
  }) {
    return _datasource.extractSubtitles(
      inputPath: inputPath,
      outputPath: outputPath,
      trackIndex: trackIndex,
      jobId: jobId,
    );
  }

  @override
  Stream<ConversionProgress> splitVideo({
    required String jobId,
    required String inputPath,
    required String outputDir,
    required int intervalSeconds,
    Duration? inputDuration,
  }) async* {
    await for (final progress in _datasource.splitVideo(
      jobId: jobId,
      inputPath: inputPath,
      outputDir: outputDir,
      intervalSeconds: intervalSeconds,
      inputDuration: inputDuration,
    )) {
      yield progress;
    }
  }

  @override
  Stream<ConversionProgress> concatWithTransitions({
    required String jobId,
    required List<String> inputFiles,
    required String outputPath,
    required ConversionConfig config,
    required double transitionDuration,
  }) async* {
    await for (final progress in _datasource.concatWithTransitions(
      jobId: jobId,
      inputFiles: inputFiles,
      outputPath: outputPath,
      config: config,
      transitionDuration: transitionDuration,
    )) {
      yield progress;

      if (progress.error != null) {
        _cleanupPartialOutput(outputPath);
      }
    }
  }

  @override
  String? getJobLog(String jobId) => _datasource.getJobLog(jobId);

  @override
  void clearJobLog(String jobId) => _datasource.clearJobLog(jobId);

  /// Delete partial output file on cancel/failure.
  void _cleanupPartialOutput(String outputPath) {
    try {
      final file = File(outputPath);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {
      // Best-effort cleanup
    }
  }
}
