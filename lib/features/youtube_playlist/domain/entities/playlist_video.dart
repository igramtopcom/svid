import 'package:freezed_annotation/freezed_annotation.dart';

part 'playlist_video.freezed.dart';

/// Video in a YouTube playlist (lightweight, no format info)
@freezed
class PlaylistVideo with _$PlaylistVideo {
  const PlaylistVideo._();

  const factory PlaylistVideo({
    required String id,
    required String title,
    required String url,
    String? thumbnail,
    int? durationSeconds,
    String? channel,
    String? channelId,
    int? viewCount,
    String? uploadDate,
  }) = _PlaylistVideo;

  /// Get duration formatted as "MM:SS" or "HH:MM:SS"
  String get formattedDuration {
    if (durationSeconds == null) return '';
    final duration = Duration(seconds: durationSeconds!);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Get view count formatted (e.g., "1.2M views")
  String get formattedViewCount {
    if (viewCount == null) return '';
    if (viewCount! >= 1000000000) {
      return '${(viewCount! / 1000000000).toStringAsFixed(1)}B views';
    }
    if (viewCount! >= 1000000) {
      return '${(viewCount! / 1000000).toStringAsFixed(1)}M views';
    }
    if (viewCount! >= 1000) {
      return '${(viewCount! / 1000).toStringAsFixed(1)}K views';
    }
    return '$viewCount views';
  }

  /// Get high quality thumbnail URL
  String? get highQualityThumbnail {
    if (thumbnail == null) return null;
    if (thumbnail!.contains('ytimg.com') || thumbnail!.contains('youtube.com')) {
      return 'https://img.youtube.com/vi/$id/hqdefault.jpg';
    }
    return thumbnail;
  }
}
