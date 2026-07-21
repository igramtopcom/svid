import 'dart:io';

import 'package:path/path.dart' as path;

import '../../../../core/binaries/binary_manager.dart';
import '../../../../core/binaries/binary_type.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/file_utils.dart';
import '../../../downloads/domain/entities/download_entity.dart';
import '../../data/datasources/ffmpeg_datasource.dart';

/// Use case for trimming a video to a selected time range
class TrimVideoUseCase {
  final FFmpegDatasource _datasource;
  final BinaryManager _binaryManager;

  TrimVideoUseCase(this._datasource, this._binaryManager);

  /// Execute the trim operation
  ///
  /// Validates inputs, generates output path, then delegates to FFmpegDatasource.
  /// Returns a stream of [TrimProgress] updates.
  Stream<TrimProgress> call({
    required DownloadEntity video,
    required Duration startTime,
    required Duration endTime,
    required TrimMode mode,
  }) async* {
    // --- Validation ---

    // 1. FFmpeg available
    final ffmpegPath = await _binaryManager.getBinaryPath(BinaryType.ffmpeg);
    if (ffmpegPath == null) {
      yield TrimProgress.error(
        'FFmpeg is not installed. Go to Settings → Binaries to download it.',
      );
      return;
    }

    // 2. Input file exists
    final inputPath = '${video.savePath}/${video.filename}';
    final inputFile = File(inputPath);
    if (!await inputFile.exists()) {
      yield TrimProgress.error('Source file not found: ${video.filename}');
      return;
    }

    // 3. Time range valid
    if (startTime < Duration.zero) {
      yield TrimProgress.error('Start time cannot be negative');
      return;
    }
    if (endTime <= startTime) {
      yield TrimProgress.error('End time must be after start time');
      return;
    }
    final trimDuration = endTime - startTime;
    if (trimDuration.inSeconds < 1) {
      yield TrimProgress.error('Trim duration must be at least 1 second');
      return;
    }

    // 4. Generate output filename
    final ext = path.extension(video.filename); // .mp4
    final baseName = path.basenameWithoutExtension(video.filename);
    final rawOutputName = '$baseName (trimmed)$ext';
    final outputName = await FileUtils.getUniqueFilename(
      video.savePath,
      rawOutputName,
    );
    final outputPath = '${video.savePath}/$outputName';

    // 5. Ensure output directory is writable
    final canWrite = await FileUtils.canWriteToDirectory(video.savePath);
    if (!canWrite) {
      yield TrimProgress.error('Cannot write to directory: ${video.savePath}');
      return;
    }

    appLogger.info(
      '[Trim] Starting: ${video.filename} '
      '(${_formatDur(startTime)} → ${_formatDur(endTime)}) '
      'mode=${mode.name} → $outputName',
    );

    // --- Execute ---
    yield* _datasource.trimVideo(
      inputPath: inputPath,
      outputPath: outputPath,
      startTime: startTime,
      endTime: endTime,
      mode: mode,
    );
  }

  /// Cancel the active trim operation
  void cancel() => _datasource.cancel();

  static String _formatDur(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$m:$s';
    }
    return '$m:$s';
  }
}
