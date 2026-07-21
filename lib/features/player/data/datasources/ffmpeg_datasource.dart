import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../../core/binaries/binary_manager.dart';
import '../../../../core/binaries/binary_type.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/process_helper.dart';

/// Trim mode: fast (stream copy) vs precise (re-encode)
enum TrimMode {
  /// Stream copy — instant, no quality loss, but may include extra frames at boundaries
  fast,

  /// Re-encode — slower, frame-accurate cuts
  precise,
}

/// Status of a trim operation
enum TrimStatus { starting, processing, completed, error, cancelled }

/// Progress of an FFmpeg trim operation
class TrimProgress {
  final double percent; // 0.0 to 1.0
  final Duration processed;
  final TrimStatus status;
  final String? error;
  final String? outputPath;

  const TrimProgress({
    required this.percent,
    required this.processed,
    required this.status,
    this.error,
    this.outputPath,
  });

  factory TrimProgress.starting() => const TrimProgress(
        percent: 0,
        processed: Duration.zero,
        status: TrimStatus.starting,
      );

  factory TrimProgress.completed(String outputPath) => TrimProgress(
        percent: 1.0,
        processed: Duration.zero,
        status: TrimStatus.completed,
        outputPath: outputPath,
      );

  factory TrimProgress.error(String message) => TrimProgress(
        percent: 0,
        processed: Duration.zero,
        status: TrimStatus.error,
        error: message,
      );

  factory TrimProgress.cancelled() => const TrimProgress(
        percent: 0,
        processed: Duration.zero,
        status: TrimStatus.cancelled,
      );
}

/// Direct FFmpeg subprocess wrapper for video trimming
class FFmpegDatasource {
  final BinaryManager _binaryManager;
  Process? _activeProcess;

  FFmpegDatasource(this._binaryManager);

  /// Trim a video file using FFmpeg
  ///
  /// [inputPath] - Full path to the source video
  /// [outputPath] - Full path for the trimmed output
  /// [startTime] - Trim start point
  /// [endTime] - Trim end point
  /// [mode] - Fast (stream copy) or Precise (re-encode)
  Stream<TrimProgress> trimVideo({
    required String inputPath,
    required String outputPath,
    required Duration startTime,
    required Duration endTime,
    required TrimMode mode,
  }) async* {
    yield TrimProgress.starting();

    final ffmpegPath = await _binaryManager.getBinaryPath(BinaryType.ffmpeg);
    if (ffmpegPath == null) {
      yield TrimProgress.error('FFmpeg binary not found. Please install FFmpeg.');
      return;
    }

    final trimDuration = endTime - startTime;
    final args = _buildArgs(
      inputPath: inputPath,
      outputPath: outputPath,
      startTime: startTime,
      endTime: endTime,
      trimDuration: trimDuration,
      mode: mode,
    );

    appLogger.info(
      '[FFmpeg] Trim: ${_formatDuration(startTime)} → ${_formatDuration(endTime)} '
      '(${_formatDuration(trimDuration)}) mode=${mode.name}',
    );
    appLogger.debug('[FFmpeg] Command: $ffmpegPath ${args.join(' ')}');

    try {
      final process = await ProcessHelper.start(ffmpegPath, args);
      _activeProcess = process;

      // FFmpeg outputs progress to stderr
      final stderrLines = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter());

      await for (final line in stderrLines) {
        if (_activeProcess == null) {
          // Cancelled
          yield TrimProgress.cancelled();
          return;
        }

        final progress = _parseProgress(line, trimDuration);
        if (progress != null) {
          yield progress;
        }
      }

      final exitCode = await process.exitCode;
      _activeProcess = null;

      if (exitCode == 0) {
        // Verify output file exists
        final outputFile = File(outputPath);
        if (await outputFile.exists()) {
          final size = await outputFile.length();
          appLogger.info('[FFmpeg] Trim completed: $outputPath ($size bytes)');
          yield TrimProgress.completed(outputPath);
        } else {
          yield TrimProgress.error('Output file was not created');
        }
      } else {
        appLogger.error('[FFmpeg] Trim failed with exit code $exitCode');
        yield TrimProgress.error('FFmpeg exited with code $exitCode');
      }
    } catch (e) {
      _activeProcess = null;
      appLogger.error('[FFmpeg] Trim error', e);
      yield TrimProgress.error('FFmpeg error: $e');
    }
  }

  /// Cancel the active trim operation
  void cancel() {
    final process = _activeProcess;
    if (process != null) {
      appLogger.info('[FFmpeg] Cancelling trim operation');
      try {
        process.kill(ProcessSignal.sigterm);
      } catch (e) {
        appLogger.debug('[FFmpeg] Process already terminated: $e');
      }
      _activeProcess = null;
    }
  }

  /// Build FFmpeg arguments based on trim mode
  List<String> _buildArgs({
    required String inputPath,
    required String outputPath,
    required Duration startTime,
    required Duration endTime,
    required Duration trimDuration,
    required TrimMode mode,
  }) {
    final startStr = _formatDuration(startTime);

    switch (mode) {
      case TrimMode.fast:
        // Stream copy: -ss before -i for fast seek, -to is relative duration
        final durationStr = _formatDuration(trimDuration);
        return [
          '-y', // Overwrite output
          '-ss', startStr,
          '-i', inputPath,
          '-to', durationStr,
          '-c', 'copy',
          '-avoid_negative_ts', 'make_zero',
          '-movflags', '+faststart', // Web-optimized MP4
          outputPath,
        ];

      case TrimMode.precise:
        // Re-encode: -ss after -i for frame-accurate seek, -to is absolute time
        final endStr = _formatDuration(endTime);
        return [
          '-y',
          '-i', inputPath,
          '-ss', startStr,
          '-to', endStr,
          '-c:v', 'libx264',
          '-preset', 'fast',
          '-crf', '18',
          '-c:a', 'aac',
          '-b:a', '192k',
          '-movflags', '+faststart',
          outputPath,
        ];
    }
  }

  /// Parse FFmpeg progress from a stderr line
  /// Returns null if the line doesn't contain progress info
  TrimProgress? _parseProgress(String line, Duration totalDuration) {
    // FFmpeg progress format: time=HH:MM:SS.mm or time=HH:MM:SS.mmm
    final timeMatch = RegExp(r'time=(\d{2}):(\d{2}):(\d{2})\.(\d{2,3})').firstMatch(line);
    if (timeMatch == null) return null;

    final hours = int.parse(timeMatch.group(1)!);
    final minutes = int.parse(timeMatch.group(2)!);
    final seconds = int.parse(timeMatch.group(3)!);
    final fraction = timeMatch.group(4)!;
    final milliseconds = fraction.length == 2
        ? int.parse(fraction) * 10
        : int.parse(fraction);

    final processed = Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );

    final totalMs = totalDuration.inMilliseconds;
    final percent = totalMs > 0
        ? (processed.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 0.0;

    return TrimProgress(
      percent: percent,
      processed: processed,
      status: TrimStatus.processing,
    );
  }

  /// Extract a single video frame at [position] as a 160px-wide JPEG.
  ///
  /// Returns null if FFmpeg is unavailable, the file is unreadable,
  /// or the operation exceeds [timeout].
  /// Windows gets a longer default (5s) due to slower I/O.
  Future<Uint8List?> extractFrameAt(
    String filePath,
    Duration position, {
    Duration? timeout,
  }) async {
    timeout ??= Duration(milliseconds: Platform.isWindows ? 5000 : 3000);
    final ffmpegPath = await _binaryManager.getBinaryPath(BinaryType.ffmpeg);
    if (ffmpegPath == null) return null;

    final timeStr = _formatDuration(position);
    final args = [
      '-ss', timeStr,
      '-i', filePath,
      '-vframes', '1',
      '-vf', 'scale=160:-1',
      '-f', 'image2pipe',
      '-vcodec', 'mjpeg',
      'pipe:1',
    ];

    try {
      final process = await ProcessHelper.start(ffmpegPath, args).timeout(timeout);
      final stdoutFuture = process.stdout
          .fold<List<int>>([], (acc, chunk) => acc..addAll(chunk));
      final stderrFuture = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .join();
      final exitFuture = process.exitCode;

      final results = await Future.wait([stdoutFuture, stderrFuture, exitFuture])
          .timeout(timeout, onTimeout: () {
        process.kill();
        return [<int>[], '', -1];
      });

      final bytes = results[0] as List<int>;
      final stderr = results[1] as String;
      final exitCode = results[2] as int;

      if (exitCode != 0 || bytes.isEmpty) {
        appLogger.debug(
          '[FFmpeg] extractFrameAt exitCode=$exitCode bytes=${bytes.length}'
          '${stderr.isNotEmpty ? " stderr=${stderr.trim()}" : ""}',
        );
        return null;
      }
      return Uint8List.fromList(bytes);
    } catch (e) {
      appLogger.debug('[FFmpeg] extractFrameAt error: $e');
      return null;
    }
  }

  /// Extract a full-resolution video frame at [position] and save to [outputPath].
  ///
  /// Returns the output path on success, null on failure.
  /// Used for screenshot capture (unlike extractFrameAt which is 160px for thumbnails).
  Future<String?> captureScreenshot(
    String filePath,
    Duration position,
    String outputPath, {
    Duration? timeout,
  }) async {
    timeout ??= const Duration(seconds: 10);
    final ffmpegPath = await _binaryManager.getBinaryPath(BinaryType.ffmpeg);
    if (ffmpegPath == null) return null;

    final timeStr = _formatDuration(position);
    final args = [
      '-ss', timeStr,
      '-i', filePath,
      '-vframes', '1',
      '-q:v', '2', // High quality JPEG
      '-y', // Overwrite
      outputPath,
    ];

    try {
      final process = await ProcessHelper.start(ffmpegPath, args).timeout(timeout);
      final exitCode = await process.exitCode.timeout(timeout, onTimeout: () {
        process.kill();
        return -1;
      });

      if (exitCode != 0) {
        appLogger.debug('[FFmpeg] captureScreenshot exitCode=$exitCode');
        return null;
      }

      final file = File(outputPath);
      if (await file.exists() && await file.length() > 0) {
        return outputPath;
      }
      return null;
    } catch (e) {
      appLogger.debug('[FFmpeg] captureScreenshot error: $e');
      return null;
    }
  }

  /// Format Duration to FFmpeg time string: HH:MM:SS.mmm
  static String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    final millis = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '$hours:$minutes:$seconds.$millis';
  }
}
