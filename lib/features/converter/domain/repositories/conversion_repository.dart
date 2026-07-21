import '../entities/conversion_config.dart';
import '../entities/conversion_job.dart';
import '../entities/hw_accel_info.dart';
import '../entities/media_info.dart';

/// Progress update emitted during a conversion operation.
class ConversionProgress {
  /// Current progress as a fraction (0.0 to 1.0)
  final double progress;

  /// Speed reported by ffmpeg (e.g., "2.5x")
  final String? speed;

  /// Estimated time remaining
  final Duration? eta;

  /// Current output file size in bytes
  final int? outputSize;

  /// Whether this is the final (completion) update
  final bool isComplete;

  /// Error message if conversion failed
  final String? error;

  const ConversionProgress({
    required this.progress,
    this.speed,
    this.eta,
    this.outputSize,
    this.isComplete = false,
    this.error,
  });

  factory ConversionProgress.starting() =>
      const ConversionProgress(progress: 0.0);

  factory ConversionProgress.completed({int? outputSize}) => ConversionProgress(
    progress: 1.0,
    isComplete: true,
    outputSize: outputSize,
  );

  factory ConversionProgress.failed(String error) =>
      ConversionProgress(progress: 0.0, error: error);
}

/// Abstract interface for the conversion repository.
///
/// Implemented by [ConversionRepositoryImpl] in the data layer.
abstract class ConversionRepository {
  /// Start converting a file according to the job's configuration.
  ///
  /// Returns a stream of progress updates. The stream completes when
  /// the conversion finishes (success or failure).
  Stream<ConversionProgress> convertFile(ConversionJob job);

  /// Run video stabilization (two-pass vidstab).
  ///
  /// Returns a stream of progress updates.
  Stream<ConversionProgress> stabilizeFile(ConversionJob job);

  /// Concatenate multiple files into one output.
  ///
  /// Returns a stream of progress updates.
  Stream<ConversionProgress> concatFiles({
    required String jobId,
    required List<String> inputFiles,
    required String outputPath,
    required ConversionConfig config,
    Duration? totalDuration,
  });

  /// Probe a file to get its media information (duration, codecs, etc.)
  Future<MediaInfo> probeFile(String filePath);

  /// Detect available hardware acceleration on this system.
  Future<List<HwAccelInfo>> detectHardwareAccel();

  /// Cancel an in-progress conversion by job ID.
  void cancelConversion(String jobId);

  /// Extract a single frame as an image at the given timestamp.
  Future<String?> extractThumbnail({
    required String inputPath,
    required String outputPath,
    required double timestamp,
    String? jobId,
  });

  /// Get a cached thumbnail for a queue card preview, extracting it on first
  /// call. Cached under the system temp directory and keyed by file path +
  /// size + mtime so it auto-invalidates if the source file changes. Returns
  /// null for audio files or extraction failures — callers should treat null
  /// as "no preview available" and fall back to a status icon.
  Future<String?> getOrExtractInputThumbnail(String inputPath);

  /// Extract embedded subtitles to an .srt file.
  Future<String?> extractSubtitles({
    required String inputPath,
    required String outputPath,
    int trackIndex = 0,
    String? jobId,
  });

  /// Split a video into segments of [intervalSeconds] each.
  Stream<ConversionProgress> splitVideo({
    required String jobId,
    required String inputPath,
    required String outputDir,
    required int intervalSeconds,
    Duration? inputDuration,
  });

  /// Concatenate files with crossfade transitions.
  Stream<ConversionProgress> concatWithTransitions({
    required String jobId,
    required List<String> inputFiles,
    required String outputPath,
    required ConversionConfig config,
    required double transitionDuration,
  });

  /// Return the captured ffmpeg stderr log for [jobId], or null if no log
  /// has been recorded (e.g., job hasn't started or was already cleared).
  ///
  /// Logs are kept in memory only — they survive job completion but are lost
  /// on app restart. Capped at the most recent ~600 lines per job.
  String? getJobLog(String jobId);

  /// Discard the in-memory log buffer for [jobId]. Called when a job is
  /// removed from the queue so logs don't outlive the job they describe.
  void clearJobLog(String jobId);
}
