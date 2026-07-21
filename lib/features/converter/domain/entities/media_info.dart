/// Probed media file information from ffprobe.
///
/// Contains all relevant metadata about a media file:
/// streams (video/audio/subtitle), container format, and file properties.
class MediaInfo {
  final String filePath;
  final String filename;
  final int fileSize; // bytes
  final Duration? duration;
  final String? videoCodec; // "h264", "vp9", etc.
  final String? audioCodec; // "aac", "opus", etc.
  final int? width;
  final int? height;
  final double? fps;
  final int? videoBitrate; // bps
  final int? audioBitrate; // bps
  final int? audioSampleRate;
  final int? audioChannels;
  final String? containerFormat; // "mp4", "webm", etc.
  final bool hasVideo;
  final bool hasAudio;
  final bool hasSubtitles;
  final List<String> subtitleLanguages;

  const MediaInfo({
    required this.filePath,
    required this.filename,
    required this.fileSize,
    this.duration,
    this.videoCodec,
    this.audioCodec,
    this.width,
    this.height,
    this.fps,
    this.videoBitrate,
    this.audioBitrate,
    this.audioSampleRate,
    this.audioChannels,
    this.containerFormat,
    required this.hasVideo,
    required this.hasAudio,
    this.hasSubtitles = false,
    this.subtitleLanguages = const [],
  });

  /// Human-readable resolution string (e.g., "1920x1080")
  String get resolutionLabel {
    if (width != null && height != null) {
      return '${width}x$height';
    }
    return 'N/A';
  }

  /// Human-readable quality label (e.g., "1080p")
  String get qualityLabel {
    if (height == null) return 'N/A';
    if (height! >= 2160) return '4K';
    if (height! >= 1440) return '2K';
    return '${height}p';
  }

  /// Human-readable file size
  String get fileSizeLabel {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Human-readable bitrate
  String get bitrateLabel {
    final total = (videoBitrate ?? 0) + (audioBitrate ?? 0);
    if (total == 0) return 'N/A';
    if (total < 1000) return '$total bps';
    if (total < 1000000) return '${(total / 1000).toStringAsFixed(0)} kbps';
    return '${(total / 1000000).toStringAsFixed(1)} Mbps';
  }

  /// Human-readable duration string (e.g., "01:23:45")
  String get durationLabel {
    if (duration == null) return 'N/A';
    final d = duration!;
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  /// Human-readable FPS string
  String get fpsLabel {
    if (fps == null) return 'N/A';
    if (fps! == fps!.roundToDouble()) return '${fps!.toInt()} fps';
    return '${fps!.toStringAsFixed(2)} fps';
  }

  MediaInfo copyWith({
    String? filePath,
    String? filename,
    int? fileSize,
    Duration? duration,
    String? videoCodec,
    String? audioCodec,
    int? width,
    int? height,
    double? fps,
    int? videoBitrate,
    int? audioBitrate,
    int? audioSampleRate,
    int? audioChannels,
    String? containerFormat,
    bool? hasVideo,
    bool? hasAudio,
    bool? hasSubtitles,
    List<String>? subtitleLanguages,
  }) {
    return MediaInfo(
      filePath: filePath ?? this.filePath,
      filename: filename ?? this.filename,
      fileSize: fileSize ?? this.fileSize,
      duration: duration ?? this.duration,
      videoCodec: videoCodec ?? this.videoCodec,
      audioCodec: audioCodec ?? this.audioCodec,
      width: width ?? this.width,
      height: height ?? this.height,
      fps: fps ?? this.fps,
      videoBitrate: videoBitrate ?? this.videoBitrate,
      audioBitrate: audioBitrate ?? this.audioBitrate,
      audioSampleRate: audioSampleRate ?? this.audioSampleRate,
      audioChannels: audioChannels ?? this.audioChannels,
      containerFormat: containerFormat ?? this.containerFormat,
      hasVideo: hasVideo ?? this.hasVideo,
      hasAudio: hasAudio ?? this.hasAudio,
      hasSubtitles: hasSubtitles ?? this.hasSubtitles,
      subtitleLanguages: subtitleLanguages ?? this.subtitleLanguages,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaInfo &&
          runtimeType == other.runtimeType &&
          filePath == other.filePath &&
          fileSize == other.fileSize;

  @override
  int get hashCode => filePath.hashCode ^ fileSize.hashCode;

  @override
  String toString() =>
      'MediaInfo($filename, ${hasVideo ? videoCodec : "no video"}, '
      '${hasAudio ? audioCodec : "no audio"}, $resolutionLabel, $durationLabel)';
}
