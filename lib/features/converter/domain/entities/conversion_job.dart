import 'conversion_config.dart';
import 'conversion_status.dart';

/// A single conversion job tracking the full lifecycle from queue to completion.
///
/// Persisted in the ConversionJobs database table.
/// Updated in real-time during conversion with progress, speed, and ETA.
class ConversionJob {
  final String id; // UUID
  final String inputPath;
  final String outputPath;
  final String inputFilename; // Display name
  final String outputFilename;
  final ConversionStatus status;
  final double progress; // 0.0 to 1.0
  final String? speed; // "2.5x" from ffmpeg
  final Duration? eta;
  final int inputSize; // bytes
  final int? outputSize; // bytes, after completion
  final Duration? inputDuration;
  final String? presetName;
  final ConversionConfig config;
  final int? downloadId; // FK to downloads table, null if external file
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

  const ConversionJob({
    required this.id,
    required this.inputPath,
    required this.outputPath,
    required this.inputFilename,
    required this.outputFilename,
    required this.status,
    this.progress = 0.0,
    this.speed,
    this.eta,
    required this.inputSize,
    this.outputSize,
    this.inputDuration,
    this.presetName,
    required this.config,
    this.downloadId,
    this.errorMessage,
    required this.createdAt,
    this.startedAt,
    this.completedAt,
  });

  /// Human-readable input file size
  String get inputSizeLabel => _formatBytes(inputSize);

  /// Human-readable output file size
  String get outputSizeLabel =>
      outputSize != null ? _formatBytes(outputSize!) : '';

  /// Compression ratio (output/input), e.g., "0.65x"
  String get compressionRatio {
    if (outputSize == null || inputSize == 0) return '';
    final ratio = outputSize! / inputSize;
    return '${ratio.toStringAsFixed(2)}x';
  }

  /// Whether the output size is effectively unchanged (<1% delta).
  bool get isSameSize {
    if (outputSize == null || inputSize == 0) return false;
    final delta = ((outputSize! - inputSize).abs() / inputSize) * 100;
    return delta < 1.0;
  }

  /// Space saved as percentage, e.g., "35% smaller"
  String get spaceSaved {
    if (outputSize == null || inputSize == 0) return '';
    if (isSameSize) return 'Same size';
    final saved = 1.0 - (outputSize! / inputSize);
    if (saved > 0) {
      return '${(saved * 100).toStringAsFixed(0)}% smaller';
    } else {
      return '${((-saved) * 100).toStringAsFixed(0)}% larger';
    }
  }

  /// Progress as percentage string
  String get progressPercent => '${(progress * 100).toStringAsFixed(1)}%';

  /// ETA as human-readable string
  String get etaLabel {
    if (eta == null) return '';
    final d = eta!;
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes % 60}m left';
    }
    if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds % 60}s left';
    }
    return '${d.inSeconds}s left';
  }

  ConversionJob copyWith({
    String? id,
    String? inputPath,
    String? outputPath,
    String? inputFilename,
    String? outputFilename,
    ConversionStatus? status,
    double? progress,
    String? speed,
    Duration? eta,
    int? inputSize,
    int? outputSize,
    Duration? inputDuration,
    String? presetName,
    ConversionConfig? config,
    int? downloadId,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? completedAt,
    bool clearSpeed = false,
    bool clearEta = false,
    bool clearOutputSize = false,
    bool clearInputDuration = false,
    bool clearPresetName = false,
    bool clearDownloadId = false,
    bool clearErrorMessage = false,
    bool clearStartedAt = false,
    bool clearCompletedAt = false,
  }) {
    return ConversionJob(
      id: id ?? this.id,
      inputPath: inputPath ?? this.inputPath,
      outputPath: outputPath ?? this.outputPath,
      inputFilename: inputFilename ?? this.inputFilename,
      outputFilename: outputFilename ?? this.outputFilename,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      speed: clearSpeed ? null : (speed ?? this.speed),
      eta: clearEta ? null : (eta ?? this.eta),
      inputSize: inputSize ?? this.inputSize,
      outputSize: clearOutputSize ? null : (outputSize ?? this.outputSize),
      inputDuration:
          clearInputDuration ? null : (inputDuration ?? this.inputDuration),
      presetName: clearPresetName ? null : (presetName ?? this.presetName),
      config: config ?? this.config,
      downloadId: clearDownloadId ? null : (downloadId ?? this.downloadId),
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      createdAt: createdAt ?? this.createdAt,
      startedAt: clearStartedAt ? null : (startedAt ?? this.startedAt),
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ConversionJob && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'ConversionJob($id, $inputFilename → $outputFilename, $status)';
}
