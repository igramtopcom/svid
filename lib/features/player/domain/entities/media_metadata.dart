import 'package:freezed_annotation/freezed_annotation.dart';

part 'media_metadata.freezed.dart';

/// Media metadata information extracted from file
@freezed
class MediaMetadata with _$MediaMetadata {
  const MediaMetadata._();

  const factory MediaMetadata({
    /// File path
    required String filePath,

    /// Media duration in milliseconds
    required Duration duration,

    /// Media title (from metadata or filename)
    required String title,

    /// Media type (video/audio/image)
    required MediaType mediaType,

    /// Video width (null for audio)
    int? width,

    /// Video height (null for audio)
    int? height,

    /// Frame rate (null for audio)
    double? frameRate,

    /// Video codec (e.g., "h264", "vp9")
    String? videoCodec,

    /// Audio codec (e.g., "aac", "mp3")
    String? audioCodec,

    /// Bitrate in bits per second
    int? bitrate,

    /// File size in bytes
    int? fileSize,

    /// Artist name (for audio)
    String? artist,

    /// Album name (for audio)
    String? album,

    /// Thumbnail path or URL
    String? thumbnail,
  }) = _MediaMetadata;

  /// Get formatted duration (e.g., "1:23:45")
  String get formattedDuration {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
  }

  /// Get resolution string (e.g., "1920x1080")
  String? get resolution {
    if (width != null && height != null) {
      return '${width}x$height';
    }
    return null;
  }

  /// Get quality label (e.g., "1080p", "720p")
  String? get qualityLabel {
    if (height == null) return null;

    if (height! >= 2160) return '4K';
    if (height! >= 1440) return '1440p';
    if (height! >= 1080) return '1080p';
    if (height! >= 720) return '720p';
    if (height! >= 480) return '480p';
    return '${height}p';
  }

  /// Check if video is HD (720p or higher)
  bool get isHD => height != null && height! >= 720;

  /// Check if video is 4K
  bool get is4K => height != null && height! >= 2160;
}

/// Media type enumeration
enum MediaType {
  video,
  audio,
  image,
  unknown;

  /// Get display label
  String get label {
    switch (this) {
      case MediaType.video:
        return 'Video';
      case MediaType.audio:
        return 'Audio';
      case MediaType.image:
        return 'Image';
      case MediaType.unknown:
        return 'Unknown';
    }
  }

  /// Get icon
  String get icon {
    switch (this) {
      case MediaType.video:
        return '🎬';
      case MediaType.audio:
        return '🎵';
      case MediaType.image:
        return '🖼️';
      case MediaType.unknown:
        return '📄';
    }
  }
}
