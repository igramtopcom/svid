import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../../core/binaries/binary_manager.dart';
import '../../../../core/binaries/binary_type.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/process_helper.dart';
import '../../domain/entities/conversion_config.dart';
import '../../domain/entities/hw_accel_info.dart';
import '../../domain/entities/media_info.dart';
import '../../domain/entities/output_format.dart';
import '../../domain/repositories/conversion_repository.dart';
import '../../domain/services/ffmpeg_command_builder.dart';
import '../../domain/services/hw_accel_detector.dart';

class _TextProcessResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const _TextProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}

class _CancelledProcessException implements Exception {
  const _CancelledProcessException();
}

/// FFmpeg/ffprobe process management for media conversion.
///
/// Handles:
/// - Probing files with ffprobe (JSON output parsing)
/// - Running ffmpeg conversions with real-time progress parsing
/// - Two-pass encoding (sequential pass 1 → pass 2)
/// - Video stabilization (two-pass vidstab)
/// - File concatenation (concat demuxer or filter_complex)
/// - Cancellation (process kill + partial output cleanup)
/// - Hardware acceleration detection
class ConversionDatasource {
  final BinaryManager _binaryManager;
  final FFmpegCommandBuilder _commandBuilder;
  final HwAccelDetector _hwAccelDetector;

  /// Active conversion processes keyed by job ID.
  final Map<String, Process> _activeProcesses = {};

  /// Captured ffmpeg stderr lines per job (last [_maxLogLines] lines).
  /// Persists past completion so users can inspect logs of completed/failed jobs.
  final Map<String, List<String>> _jobLogs = {};

  /// In-flight thumbnail extraction futures keyed by content cache key.
  ///
  /// The converter UI can ask for the same input thumbnail from multiple
  /// surfaces at once (selected file card, editor preview, queue card). If we
  /// spawn ffmpeg for each request, a single user action can fan out into
  /// redundant subprocesses and add avoidable CPU/IO pressure during convert.
  final Map<String, Future<String?>> _thumbnailExtractions = {};

  /// Serialize thumbnail extraction globally to keep non-critical ffmpeg work
  /// from stampeding the machine while the main conversion pipeline is active.
  Future<void> _thumbnailExtractionBarrier = Future<void>.value();

  /// Cap log buffer size to avoid memory leaks for very long encodes.
  static const int _maxLogLines = 600;
  static const Duration _probeTimeout = Duration(seconds: 20);
  static const Duration _thumbnailTimeout = Duration(seconds: 15);
  static const Duration _shortExtractTimeout = Duration(seconds: 30);

  ConversionDatasource(
    this._binaryManager,
    this._commandBuilder,
    this._hwAccelDetector,
  );

  /// Return the captured ffmpeg log for [jobId], or null if no log was recorded.
  String? getJobLog(String jobId) {
    final lines = _jobLogs[jobId];
    if (lines == null || lines.isEmpty) return null;
    return lines.join('\n');
  }

  /// Discard the log buffer for [jobId]. Called when a job is removed.
  void clearJobLog(String jobId) {
    _jobLogs.remove(jobId);
  }

  /// Append a line to the log buffer for [jobId], evicting the oldest line
  /// if the buffer exceeds [_maxLogLines].
  void _appendJobLog(String jobId, String line) {
    final buffer = _jobLogs.putIfAbsent(jobId, () => <String>[]);
    if (buffer.length >= _maxLogLines) {
      buffer.removeAt(0);
    }
    buffer.add(line);
  }

  /// Probe a media file with ffprobe and return parsed [MediaInfo].
  Future<MediaInfo> probeMediaInfo(String filePath) async {
    final ffmpegPath = await _binaryManager.getBinaryPath(BinaryType.ffmpeg);
    if (ffmpegPath == null) {
      throw Exception('FFmpeg binary not found. Please install FFmpeg.');
    }

    // ffprobe is in the same directory as ffmpeg
    final ffprobePath = _getFfprobePath(ffmpegPath);

    final args = [
      '-v',
      'quiet',
      '-print_format',
      'json',
      '-show_format',
      '-show_streams',
      filePath,
    ];

    appLogger.debug('[ConversionDS] Probing: $filePath');

    _TextProcessResult result;
    try {
      result = await _runTextProcess(
        executable: ffprobePath,
        args: args,
        timeout: _probeTimeout,
        operation: 'ffprobe probe',
      );
    } on TimeoutException {
      throw Exception(
        'Media analysis timed out — the file may be too large, corrupt, or unsupported',
      );
    }

    if (result.exitCode != 0) {
      final stderr = result.stderr;
      appLogger.error('[ConversionDS] ffprobe failed: $stderr');
      throw Exception('Failed to probe file: ${stderr.trim()}');
    }

    final stdout = result.stdout;
    if (stdout.trim().isEmpty) {
      throw Exception('ffprobe returned empty output');
    }

    final json = jsonDecode(stdout) as Map<String, dynamic>;
    return _parseProbeResult(json, filePath);
  }

  /// Run a conversion with progress reporting.
  ///
  /// For two-pass encoding, runs pass 1 then pass 2 sequentially,
  /// reporting pass 1 progress as 0-50% and pass 2 as 50-100%.
  Stream<ConversionProgress> convert({
    required String jobId,
    required String inputPath,
    required String outputPath,
    required ConversionConfig config,
    Duration? inputDuration,
  }) async* {
    final ffmpegPath = await _binaryManager.getBinaryPath(BinaryType.ffmpeg);
    if (ffmpegPath == null) {
      yield ConversionProgress.failed('FFmpeg binary not found');
      return;
    }

    yield ConversionProgress.starting();

    // Reset log buffer for this job (in case of retry)
    _jobLogs.remove(jobId);

    // Probe input duration if not provided (needed for progress %)
    if (inputDuration == null) {
      try {
        final info = await probeMediaInfo(inputPath);
        inputDuration = info.duration;
      } catch (e) {
        appLogger.debug('[ConversionDS] Could not probe duration: $e');
      }
    }

    final totalDurationMs = inputDuration?.inMilliseconds ?? 0;

    try {
      if (config.twoPass && !config.isAudioOnly && !config.isStreamCopy) {
        // Two-pass encoding
        final passes = _commandBuilder.buildTwoPassArgs(
          inputPath: inputPath,
          outputPath: outputPath,
          config: config,
        );

        final outputDir = p.dirname(outputPath);

        // Pass 1 (0% → 50%)
        appLogger.info('[ConversionDS] Starting pass 1 for job $jobId');
        appLogger.debug(
          '[ConversionDS] Pass 1 args: $ffmpegPath ${passes[0].join(' ')}',
        );

        await for (final progress in _runFfmpeg(
          ffmpegPath: ffmpegPath,
          args: passes[0],
          jobId: jobId,
          totalDurationMs: totalDurationMs,
          workingDirectory: outputDir,
        )) {
          if (progress.error != null) {
            yield progress;
            return;
          }
          // Scale pass 1 to 0-50%
          yield ConversionProgress(
            progress: progress.progress * 0.5,
            speed: progress.speed,
            eta:
                progress.eta != null
                    ? Duration(milliseconds: progress.eta!.inMilliseconds * 2)
                    : null,
          );
        }

        // Pass 2 (50% → 100%)
        appLogger.info('[ConversionDS] Starting pass 2 for job $jobId');
        appLogger.debug(
          '[ConversionDS] Pass 2 args: $ffmpegPath ${passes[1].join(' ')}',
        );

        await for (final progress in _runFfmpeg(
          ffmpegPath: ffmpegPath,
          args: passes[1],
          jobId: jobId,
          totalDurationMs: totalDurationMs,
          workingDirectory: outputDir,
        )) {
          if (progress.error != null) {
            yield progress;
            return;
          }
          // Scale pass 2 to 50-100%
          yield ConversionProgress(
            progress: 0.5 + progress.progress * 0.5,
            speed: progress.speed,
            eta: progress.eta,
          );
        }
      } else {
        // Single-pass encoding
        final args = _commandBuilder.buildArgs(
          inputPath: inputPath,
          outputPath: outputPath,
          config: config,
          inputDuration: inputDuration,
        );

        appLogger.info('[ConversionDS] Starting conversion for job $jobId');
        appLogger.debug('[ConversionDS] Args: $ffmpegPath ${args.join(' ')}');

        await for (final progress in _runFfmpeg(
          ffmpegPath: ffmpegPath,
          args: args,
          jobId: jobId,
          totalDurationMs: totalDurationMs,
        )) {
          yield progress;
          if (progress.error != null) return;
        }
      }

      // Verify output
      final outputFile = File(outputPath);
      if (await outputFile.exists()) {
        final outputSize = await outputFile.length();
        appLogger.info(
          '[ConversionDS] Conversion completed: $outputPath ($outputSize bytes)',
        );
        yield ConversionProgress.completed(outputSize: outputSize);
      } else {
        yield ConversionProgress.failed('Output file was not created');
      }
    } catch (e) {
      appLogger.error('[ConversionDS] Conversion error for job $jobId', e);
      yield ConversionProgress.failed('Conversion error: $e');
    } finally {
      _activeProcesses.remove(jobId);
      // Clean up two-pass log files
      _cleanupPassLogFiles(outputPath);
    }
  }

  /// Run video stabilization (two-pass vidstab).
  ///
  /// Pass 1: detect motion → transforms file (progress 0-50%)
  /// Pass 2: apply transforms → output file (progress 50-100%)
  Stream<ConversionProgress> stabilize({
    required String jobId,
    required String inputPath,
    required String outputPath,
    required ConversionConfig config,
    Duration? inputDuration,
  }) async* {
    final ffmpegPath = await _binaryManager.getBinaryPath(BinaryType.ffmpeg);
    if (ffmpegPath == null) {
      yield ConversionProgress.failed('FFmpeg binary not found');
      return;
    }

    yield ConversionProgress.starting();

    // Reset log buffer for this job
    _jobLogs.remove(jobId);

    // Probe input duration if not provided
    if (inputDuration == null) {
      try {
        final info = await probeMediaInfo(inputPath);
        inputDuration = info.duration;
      } catch (e) {
        appLogger.debug('[ConversionDS] Could not probe duration: $e');
      }
    }

    final totalDurationMs = inputDuration?.inMilliseconds ?? 0;
    final outputDir = p.dirname(outputPath);
    final transformsPath = p.join(
      outputDir,
      'transforms_${jobId.substring(0, 8)}.trf',
    );

    try {
      final passes = _commandBuilder.buildStabilizationArgs(
        inputPath: inputPath,
        outputPath: outputPath,
        config: config,
        transformsPath: transformsPath,
      );

      // Pass 1: detect motion (0% → 50%)
      appLogger.info('[ConversionDS] Stabilization pass 1 for job $jobId');
      appLogger.debug(
        '[ConversionDS] Pass 1 args: $ffmpegPath ${passes[0].join(' ')}',
      );

      await for (final progress in _runFfmpeg(
        ffmpegPath: ffmpegPath,
        args: passes[0],
        jobId: jobId,
        totalDurationMs: totalDurationMs,
        workingDirectory: outputDir,
      )) {
        if (progress.error != null) {
          yield progress;
          return;
        }
        yield ConversionProgress(
          progress: progress.progress * 0.5,
          speed: progress.speed,
          eta:
              progress.eta != null
                  ? Duration(milliseconds: progress.eta!.inMilliseconds * 2)
                  : null,
        );
      }

      // Pass 2: apply transforms (50% → 100%)
      appLogger.info('[ConversionDS] Stabilization pass 2 for job $jobId');
      appLogger.debug(
        '[ConversionDS] Pass 2 args: $ffmpegPath ${passes[1].join(' ')}',
      );

      await for (final progress in _runFfmpeg(
        ffmpegPath: ffmpegPath,
        args: passes[1],
        jobId: jobId,
        totalDurationMs: totalDurationMs,
        workingDirectory: outputDir,
      )) {
        if (progress.error != null) {
          yield progress;
          return;
        }
        yield ConversionProgress(
          progress: 0.5 + progress.progress * 0.5,
          speed: progress.speed,
          eta: progress.eta,
        );
      }

      // Verify output
      final outputFile = File(outputPath);
      if (await outputFile.exists()) {
        final outputSize = await outputFile.length();
        appLogger.info(
          '[ConversionDS] Stabilization completed: $outputPath ($outputSize bytes)',
        );
        yield ConversionProgress.completed(outputSize: outputSize);
      } else {
        yield ConversionProgress.failed('Output file was not created');
      }
    } catch (e) {
      appLogger.error('[ConversionDS] Stabilization error for job $jobId', e);
      yield ConversionProgress.failed('Stabilization error: $e');
    } finally {
      _activeProcesses.remove(jobId);
      // Cleanup transforms file
      try {
        final trfFile = File(transformsPath);
        if (trfFile.existsSync()) trfFile.deleteSync();
      } catch (e) {
        appLogger.debug(
          '[ConversionDS] Could not clean up transforms file: $e',
        );
      }
    }
  }

  /// Run a concat operation (join multiple files into one).
  ///
  /// Uses concat demuxer (fast, stream copy) when possible,
  /// falls back to filter_complex (re-encode) when codecs differ.
  Stream<ConversionProgress> concat({
    required String jobId,
    required List<String> inputFiles,
    required String outputPath,
    required ConversionConfig config,
    Duration? totalDuration,
  }) async* {
    final ffmpegPath = await _binaryManager.getBinaryPath(BinaryType.ffmpeg);
    if (ffmpegPath == null) {
      yield ConversionProgress.failed('FFmpeg binary not found');
      return;
    }

    if (inputFiles.length < 2) {
      yield ConversionProgress.failed('Need at least 2 files to concatenate');
      return;
    }

    yield ConversionProgress.starting();

    // Reset log buffer for this job
    _jobLogs.remove(jobId);

    // Calculate total duration for progress tracking
    if (totalDuration == null) {
      int totalMs = 0;
      for (final file in inputFiles) {
        try {
          final info = await probeMediaInfo(file);
          totalMs += info.duration?.inMilliseconds ?? 0;
        } catch (e) {
          appLogger.debug('[ConversionDS] Could not probe concat file: $e');
        }
      }
      if (totalMs > 0) totalDuration = Duration(milliseconds: totalMs);
    }

    final totalDurationMs = totalDuration?.inMilliseconds ?? 0;
    final outputDir = p.dirname(outputPath);

    try {
      // Try concat demuxer first (fast, stream copy)
      if (config.videoCodec == VideoCodecOption.copy &&
          (config.audioCodec == AudioCodecOption.copy ||
              config.audioCodec == null)) {
        // Create concat list file
        final concatListPath = p.join(
          outputDir,
          'concat_${jobId.substring(0, 8)}.txt',
        );
        final listContent = inputFiles
            .map((f) => "file '${f.replaceAll("'", "'\\''")}'")
            .join('\n');
        await File(concatListPath).writeAsString(listContent);

        try {
          final args = _commandBuilder.buildConcatDemuxerArgs(
            outputPath: outputPath,
            concatListPath: concatListPath,
          );

          appLogger.info(
            '[ConversionDS] Starting concat (demuxer) for job $jobId',
          );
          appLogger.debug('[ConversionDS] Args: $ffmpegPath ${args.join(' ')}');

          await for (final progress in _runFfmpeg(
            ffmpegPath: ffmpegPath,
            args: args,
            jobId: jobId,
            totalDurationMs: totalDurationMs,
            workingDirectory: outputDir,
          )) {
            yield progress;
            if (progress.error != null) return;
          }
        } finally {
          // Cleanup concat list file
          try {
            final listFile = File(concatListPath);
            if (listFile.existsSync()) listFile.deleteSync();
          } catch (_) {}
        }
      } else {
        // Re-encode with filter_complex
        final args = _commandBuilder.buildConcatFilterArgs(
          inputFiles: inputFiles,
          outputPath: outputPath,
          config: config,
        );

        appLogger.info(
          '[ConversionDS] Starting concat (filter) for job $jobId',
        );
        appLogger.debug('[ConversionDS] Args: $ffmpegPath ${args.join(' ')}');

        await for (final progress in _runFfmpeg(
          ffmpegPath: ffmpegPath,
          args: args,
          jobId: jobId,
          totalDurationMs: totalDurationMs,
          workingDirectory: outputDir,
        )) {
          yield progress;
          if (progress.error != null) return;
        }
      }

      // Verify output
      final outputFile = File(outputPath);
      if (await outputFile.exists()) {
        final outputSize = await outputFile.length();
        appLogger.info(
          '[ConversionDS] Concat completed: $outputPath ($outputSize bytes)',
        );
        yield ConversionProgress.completed(outputSize: outputSize);
      } else {
        yield ConversionProgress.failed('Output file was not created');
      }
    } catch (e) {
      appLogger.error('[ConversionDS] Concat error for job $jobId', e);
      yield ConversionProgress.failed('Concat error: $e');
    } finally {
      _activeProcesses.remove(jobId);
    }
  }

  /// Cancel an active conversion by killing its process.
  void cancelConversion(String jobId) {
    final process = _activeProcesses.remove(jobId);
    if (process != null) {
      appLogger.info('[ConversionDS] Cancelling conversion $jobId');
      try {
        process.kill(ProcessSignal.sigterm);
      } catch (e) {
        appLogger.debug('[ConversionDS] Process kill error: $e');
        try {
          process.kill(ProcessSignal.sigkill);
        } catch (_) {}
      }
    }
  }

  /// Detect available hardware acceleration.
  Future<List<HwAccelInfo>> detectHwAccel() async {
    return _hwAccelDetector.detect();
  }

  // ── Private helpers ──────────────────────────────────────────

  /// Run ffmpeg and parse progress from stderr.
  Stream<ConversionProgress> _runFfmpeg({
    required String ffmpegPath,
    required List<String> args,
    required String jobId,
    required int totalDurationMs,
    String? workingDirectory,
  }) async* {
    final process = await ProcessHelper.start(
      ffmpegPath,
      args,
      workingDirectory: workingDirectory,
    );
    _activeProcesses[jobId] = process;
    final stdoutDrain = process.stdout.drain<void>();

    // Record the command line as the first log entry — gives users context
    // when they later view the log.
    _appendJobLog(jobId, '\$ $ffmpegPath ${args.join(' ')}');

    // FFmpeg outputs progress to stderr
    final stderrLines = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());

    await for (final line in stderrLines) {
      // Capture every stderr line into the per-job log buffer
      _appendJobLog(jobId, line);

      if (!_activeProcesses.containsKey(jobId)) {
        // Process was cancelled
        yield ConversionProgress.failed('Cancelled');
        return;
      }

      final progress = _parseProgress(line, totalDurationMs);
      if (progress != null) {
        yield progress;
      }
    }

    final exitCode = await process.exitCode;
    await stdoutDrain;
    _activeProcesses.remove(jobId);
    _appendJobLog(jobId, '[exit code: $exitCode]');

    if (exitCode != 0 && exitCode != 255) {
      // 255 can occur on cancellation
      yield ConversionProgress.failed('FFmpeg exited with code $exitCode');
    }
  }

  /// Parse ffmpeg progress from a stderr line.
  ///
  /// Looks for: `time=HH:MM:SS.mm speed=Nx`
  ConversionProgress? _parseProgress(String line, int totalDurationMs) {
    final timeMatch = RegExp(
      r'time=(\d{2}):(\d{2}):(\d{2})\.(\d{2,3})',
    ).firstMatch(line);
    if (timeMatch == null) return null;

    final hours = int.parse(timeMatch.group(1)!);
    final minutes = int.parse(timeMatch.group(2)!);
    final seconds = int.parse(timeMatch.group(3)!);
    final fraction = timeMatch.group(4)!;
    final milliseconds =
        fraction.length == 2 ? int.parse(fraction) * 10 : int.parse(fraction);

    final processedMs =
        hours * 3600000 + minutes * 60000 + seconds * 1000 + milliseconds;

    final progress =
        totalDurationMs > 0
            ? (processedMs / totalDurationMs).clamp(0.0, 1.0)
            : 0.0;

    // Parse speed
    String? speed;
    final speedMatch = RegExp(r'speed=\s*(\d+\.?\d*)x').firstMatch(line);
    if (speedMatch != null) {
      speed = '${speedMatch.group(1)}x';
    }

    // Calculate ETA
    Duration? eta;
    if (totalDurationMs > 0 && speedMatch != null) {
      final speedValue = double.tryParse(speedMatch.group(1)!);
      if (speedValue != null && speedValue > 0) {
        final remainingMs = totalDurationMs - processedMs;
        final etaMs = (remainingMs / speedValue).round();
        if (etaMs > 0) {
          eta = Duration(milliseconds: etaMs);
        }
      }
    }

    // Parse current output size
    int? outputSize;
    final sizeMatch = RegExp(r'size=\s*(\d+)kB').firstMatch(line);
    if (sizeMatch != null) {
      outputSize = int.parse(sizeMatch.group(1)!) * 1024;
    }

    return ConversionProgress(
      progress: progress,
      speed: speed,
      eta: eta,
      outputSize: outputSize,
    );
  }

  /// Parse ffprobe JSON output into [MediaInfo].
  MediaInfo _parseProbeResult(Map<String, dynamic> json, String filePath) {
    final format = json['format'] as Map<String, dynamic>? ?? {};
    final streams = json['streams'] as List<dynamic>? ?? [];

    final filename =
        (format['filename'] as String?)?.split('/').last ??
        (format['filename'] as String?)?.split('\\').last ??
        filePath.split('/').last;

    final fileSize = int.tryParse(format['size']?.toString() ?? '0') ?? 0;

    final durationSec = double.tryParse(format['duration']?.toString() ?? '');
    final duration =
        durationSec != null
            ? Duration(milliseconds: (durationSec * 1000).round())
            : null;

    // Find video stream
    Map<String, dynamic>? videoStream;
    Map<String, dynamic>? audioStream;
    final subtitleLangs = <String>[];
    bool hasSubtitles = false;

    for (final stream in streams) {
      final s = stream as Map<String, dynamic>;
      final codecType = s['codec_type'] as String?;

      if (codecType == 'video' && videoStream == null) {
        // Skip attached pictures (album art)
        final disposition = s['disposition'] as Map<String, dynamic>?;
        if (disposition != null && disposition['attached_pic'] == 1) continue;
        videoStream = s;
      } else if (codecType == 'audio' && audioStream == null) {
        audioStream = s;
      } else if (codecType == 'subtitle') {
        hasSubtitles = true;
        final tags = s['tags'] as Map<String, dynamic>?;
        final lang = tags?['language'] as String?;
        if (lang != null) subtitleLangs.add(lang);
      }
    }

    // Parse video info
    final videoCodec = videoStream?['codec_name'] as String?;
    final width = videoStream?['width'] as int?;
    final height = videoStream?['height'] as int?;
    final videoBitrate = int.tryParse(
      videoStream?['bit_rate']?.toString() ?? '',
    );

    // Parse FPS from avg_frame_rate (e.g., "30000/1001" or "30/1")
    double? fps;
    final fpsStr = videoStream?['avg_frame_rate'] as String?;
    if (fpsStr != null && fpsStr.contains('/')) {
      final parts = fpsStr.split('/');
      final num = double.tryParse(parts[0]);
      final den = double.tryParse(parts[1]);
      if (num != null && den != null && den > 0) {
        fps = num / den;
      }
    }

    // Parse audio info
    final audioCodec = audioStream?['codec_name'] as String?;
    final audioBitrate = int.tryParse(
      audioStream?['bit_rate']?.toString() ?? '',
    );
    final audioSampleRate = int.tryParse(
      audioStream?['sample_rate']?.toString() ?? '',
    );
    final audioChannels = audioStream?['channels'] as int?;

    // Container format
    final containerFormat = format['format_name'] as String?;

    return MediaInfo(
      filePath: filePath,
      filename: filename,
      fileSize: fileSize,
      duration: duration,
      videoCodec: videoCodec,
      audioCodec: audioCodec,
      width: width,
      height: height,
      fps: fps,
      videoBitrate: videoBitrate,
      audioBitrate: audioBitrate,
      audioSampleRate: audioSampleRate,
      audioChannels: audioChannels,
      containerFormat: containerFormat?.split(',').first,
      hasVideo: videoStream != null,
      hasAudio: audioStream != null,
      hasSubtitles: hasSubtitles,
      subtitleLanguages: subtitleLangs,
    );
  }

  /// Get ffprobe path from ffmpeg path.
  /// ffprobe is in the same directory as ffmpeg.
  String _getFfprobePath(String ffmpegPath) {
    final dir = p.dirname(ffmpegPath);
    if (Platform.isWindows) {
      return p.join(dir, 'ffprobe.exe');
    }
    return p.join(dir, 'ffprobe');
  }

  /// Extract or fetch a cached thumbnail for [inputPath] for use in queue UI.
  ///
  /// Caches under the system temp directory keyed by an md5 hash of the
  /// absolute path + file size + mtime, so re-runs return instantly and the
  /// cache automatically invalidates when the source file is replaced.
  /// Returns null for audio-only inputs or on extraction failure.
  Future<String?> getOrExtractInputThumbnail(String inputPath) async {
    try {
      final inputFile = File(inputPath);
      if (!await inputFile.exists()) return null;

      final stat = await inputFile.stat();
      final cacheKey =
          md5
              .convert(
                utf8.encode(
                  '$inputPath:${stat.size}:${stat.modified.millisecondsSinceEpoch}',
                ),
              )
              .toString();

      final cacheDir = Directory(
        p.join(Directory.systemTemp.path, 'snakeloader_thumbs'),
      );
      if (!await cacheDir.exists()) await cacheDir.create(recursive: true);

      final cachedPath = p.join(cacheDir.path, '$cacheKey.jpg');
      if (await File(cachedPath).exists()) return cachedPath;

      final existing = _thumbnailExtractions[cacheKey];
      if (existing != null) {
        return existing;
      }

      final extraction = _serializeThumbnailExtraction(
        () => _extractAndCacheInputThumbnail(
          inputPath: inputPath,
          cachedPath: cachedPath,
        ),
      );
      _thumbnailExtractions[cacheKey] = extraction;
      try {
        return await extraction;
      } finally {
        if (identical(_thumbnailExtractions[cacheKey], extraction)) {
          _thumbnailExtractions.remove(cacheKey);
        }
      }
    } catch (e) {
      appLogger.debug('[ConversionDS] Thumbnail extraction failed: $e');
      return null;
    }
  }

  Future<String?> _extractAndCacheInputThumbnail({
    required String inputPath,
    required String cachedPath,
  }) async {
    // Extract a frame near 1s in (or 0 if shorter). Quality scaled to width
    // 160px to keep cache small — they're only used for tiny UI thumbnails.
    final ffmpegPath = await _binaryManager.getBinaryPath(BinaryType.ffmpeg);
    if (ffmpegPath == null) return null;

    final args = <String>[
      '-y',
      '-ss',
      '1',
      '-i',
      inputPath,
      '-vframes',
      '1',
      '-vf',
      'scale=160:-1',
      '-q:v',
      '5',
      cachedPath,
    ];

    final result = await _runTextProcess(
      executable: ffmpegPath,
      args: args,
      timeout: _thumbnailTimeout,
      operation: 'thumbnail extraction',
    );
    if (result.exitCode != 0) {
      // Some files don't have a frame at 1s — retry from 0.
      final retryArgs = <String>[
        '-y',
        '-ss',
        '0',
        '-i',
        inputPath,
        '-vframes',
        '1',
        '-vf',
        'scale=160:-1',
        '-q:v',
        '5',
        cachedPath,
      ];
      final retry = await _runTextProcess(
        executable: ffmpegPath,
        args: retryArgs,
        timeout: _thumbnailTimeout,
        operation: 'thumbnail extraction retry',
      );
      if (retry.exitCode != 0) return null;
    }

    return await File(cachedPath).exists() ? cachedPath : null;
  }

  /// Extract a single frame as an image (JPEG/PNG).
  Future<String?> extractThumbnail({
    required String inputPath,
    required String outputPath,
    required double timestamp,
    String? jobId,
  }) async {
    final ffmpegPath = await _binaryManager.getBinaryPath(BinaryType.ffmpeg);
    if (ffmpegPath == null) return null;

    final args = _commandBuilder.buildThumbnailArgs(
      inputPath: inputPath,
      outputPath: outputPath,
      timestamp: timestamp,
    );

    appLogger.info('[ConversionDS] Extracting thumbnail at ${timestamp}s');

    _TextProcessResult result;
    try {
      result = await _runTextProcess(
        executable: ffmpegPath,
        args: args,
        timeout: _shortExtractTimeout,
        operation: 'thumbnail export',
        jobId: jobId,
      );
    } on TimeoutException {
      appLogger.error('[ConversionDS] Thumbnail extraction timed out');
      return null;
    } on _CancelledProcessException {
      appLogger.info('[ConversionDS] Thumbnail extraction cancelled');
      return null;
    }
    if (result.exitCode != 0) {
      final stderr = result.stderr;
      appLogger.error('[ConversionDS] Thumbnail extraction failed: $stderr');
      return null;
    }

    return File(outputPath).existsSync() ? outputPath : null;
  }

  /// Extract embedded subtitles to an .srt file.
  Future<String?> extractSubtitles({
    required String inputPath,
    required String outputPath,
    int trackIndex = 0,
    String? jobId,
  }) async {
    final ffmpegPath = await _binaryManager.getBinaryPath(BinaryType.ffmpeg);
    if (ffmpegPath == null) return null;

    final args = _commandBuilder.buildSubtitleExtractArgs(
      inputPath: inputPath,
      outputPath: outputPath,
      trackIndex: trackIndex,
    );

    appLogger.info('[ConversionDS] Extracting subtitle track $trackIndex');

    _TextProcessResult result;
    try {
      result = await _runTextProcess(
        executable: ffmpegPath,
        args: args,
        timeout: _shortExtractTimeout,
        operation: 'subtitle extraction',
        jobId: jobId,
      );
    } on TimeoutException {
      appLogger.error('[ConversionDS] Subtitle extraction timed out');
      return null;
    } on _CancelledProcessException {
      appLogger.info('[ConversionDS] Subtitle extraction cancelled');
      return null;
    }
    if (result.exitCode != 0) {
      final stderr = result.stderr;
      appLogger.error('[ConversionDS] Subtitle extraction failed: $stderr');
      return null;
    }

    return File(outputPath).existsSync() ? outputPath : null;
  }

  /// Split a video into segments of [intervalSeconds] each.
  ///
  /// Returns the directory containing the segments.
  Stream<ConversionProgress> splitVideo({
    required String jobId,
    required String inputPath,
    required String outputDir,
    required int intervalSeconds,
    Duration? inputDuration,
  }) async* {
    final ffmpegPath = await _binaryManager.getBinaryPath(BinaryType.ffmpeg);
    if (ffmpegPath == null) {
      yield ConversionProgress.failed('FFmpeg binary not found');
      return;
    }

    yield ConversionProgress.starting();

    _jobLogs.remove(jobId);

    if (inputDuration == null) {
      try {
        final info = await probeMediaInfo(inputPath);
        inputDuration = info.duration;
      } catch (e) {
        appLogger.debug('[ConversionDS] Could not probe split duration: $e');
      }
    }

    final totalDurationMs = inputDuration?.inMilliseconds ?? 0;

    // Create output directory
    final dir = Directory(outputDir);
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      await dir.create(recursive: true);
    } catch (e) {
      yield ConversionProgress.failed(
        'Could not prepare split output folder: $e',
      );
      return;
    }

    final ext = p.extension(inputPath);
    final baseName = p.basenameWithoutExtension(inputPath);
    final outputPattern = p.join(outputDir, '${baseName}_segment_%03d$ext');

    final args = _commandBuilder.buildSplitArgs(
      inputPath: inputPath,
      outputPattern: outputPattern,
      intervalSeconds: intervalSeconds,
    );

    appLogger.info(
      '[ConversionDS] Splitting video into ${intervalSeconds}s segments',
    );
    appLogger.debug('[ConversionDS] Args: $ffmpegPath ${args.join(' ')}');

    try {
      await for (final progress in _runFfmpeg(
        ffmpegPath: ffmpegPath,
        args: args,
        jobId: jobId,
        totalDurationMs: totalDurationMs,
        workingDirectory: outputDir,
      )) {
        yield progress;
        if (progress.error != null) return;
      }
    } catch (e) {
      appLogger.error('[ConversionDS] Video split error for job $jobId', e);
      yield ConversionProgress.failed('Video split error: $e');
      return;
    }

    final entries = await dir.list().toList();
    var segmentCount = 0;
    var totalSize = 0;
    for (final entry in entries) {
      if (entry is! File) continue;
      final size = await entry.length();
      if (size <= 0) continue;
      segmentCount++;
      totalSize += size;
    }

    if (segmentCount == 0) {
      yield ConversionProgress.failed('No output segments were created');
      return;
    }

    _appendJobLog(jobId, '[segments: $segmentCount, total bytes: $totalSize]');
    yield ConversionProgress.completed(outputSize: totalSize);
  }

  /// Concatenate files with crossfade transitions.
  Stream<ConversionProgress> concatWithTransitions({
    required String jobId,
    required List<String> inputFiles,
    required String outputPath,
    required ConversionConfig config,
    required double transitionDuration,
  }) async* {
    final ffmpegPath = await _binaryManager.getBinaryPath(BinaryType.ffmpeg);
    if (ffmpegPath == null) {
      yield ConversionProgress.failed('FFmpeg binary not found');
      return;
    }

    yield ConversionProgress.starting();

    final args = _commandBuilder.buildConcatWithTransitionArgs(
      inputFiles: inputFiles,
      outputPath: outputPath,
      config: config,
      transitionDuration: transitionDuration,
    );

    appLogger.info('[ConversionDS] Concat with transitions for job $jobId');
    appLogger.debug('[ConversionDS] Args: $ffmpegPath ${args.join(' ')}');

    // Reset log buffer for this job
    _jobLogs.remove(jobId);

    // Estimate total duration (sum of all clips)
    int totalDurationMs = 0;
    for (final file in inputFiles) {
      try {
        final info = await probeMediaInfo(file);
        totalDurationMs += info.duration?.inMilliseconds ?? 0;
      } catch (_) {}
    }

    await for (final progress in _runFfmpeg(
      ffmpegPath: ffmpegPath,
      args: args,
      jobId: jobId,
      totalDurationMs: totalDurationMs,
    )) {
      yield progress;
    }
  }

  /// Clean up two-pass log files (ffmpeg2pass-0.log, ffmpeg2pass-0.log.mbtree)
  void _cleanupPassLogFiles(String outputPath) {
    try {
      final dir = File(outputPath).parent.path;
      final logFile = File('$dir/ffmpeg2pass-0.log');
      final mbtreeFile = File('$dir/ffmpeg2pass-0.log.mbtree');
      if (logFile.existsSync()) logFile.deleteSync();
      if (mbtreeFile.existsSync()) mbtreeFile.deleteSync();
    } catch (e) {
      appLogger.debug('[ConversionDS] Could not clean up pass log files: $e');
    }
  }

  Future<String?> _serializeThumbnailExtraction(
    Future<String?> Function() task,
  ) async {
    final previous = _thumbnailExtractionBarrier;
    final completer = Completer<void>();
    _thumbnailExtractionBarrier = completer.future;
    await previous;
    try {
      return await task();
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  Future<_TextProcessResult> _runTextProcess({
    required String executable,
    required List<String> args,
    String? workingDirectory,
    Duration? timeout,
    required String operation,
    String? jobId,
  }) async {
    final process = await ProcessHelper.start(
      executable,
      args,
      workingDirectory: workingDirectory,
    );
    if (jobId != null) {
      _activeProcesses[jobId] = process;
      _appendJobLog(jobId, '\$ $executable ${args.join(' ')}');
    }
    final stdoutFuture = process.stdout.transform(const Utf8Decoder(allowMalformed: true)).join();
    final stderrFuture = process.stderr.transform(const Utf8Decoder(allowMalformed: true)).join();

    try {
      final exitCode =
          timeout == null
              ? await process.exitCode
              : await process.exitCode.timeout(timeout);
      if (jobId != null && !_activeProcesses.containsKey(jobId)) {
        throw const _CancelledProcessException();
      }
      final stderr = await stderrFuture;
      if (jobId != null && stderr.trim().isNotEmpty) {
        for (final line in const LineSplitter().convert(stderr)) {
          _appendJobLog(jobId, line);
        }
      }
      return _TextProcessResult(
        exitCode: exitCode,
        stdout: await stdoutFuture,
        stderr: stderr,
      );
    } on TimeoutException {
      await _terminateProcess(process);
      throw TimeoutException(
        '$operation timed out after ${timeout?.inSeconds ?? 0}s',
      );
    } finally {
      if (jobId != null && identical(_activeProcesses[jobId], process)) {
        _activeProcesses.remove(jobId);
      }
    }
  }

  Future<void> _terminateProcess(Process process) async {
    try {
      process.kill(ProcessSignal.sigterm);
    } catch (_) {}

    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
      return;
    } on TimeoutException {
      try {
        process.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }

    try {
      await process.exitCode.timeout(const Duration(seconds: 1));
    } catch (_) {}
  }
}
