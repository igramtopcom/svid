import 'package:freezed_annotation/freezed_annotation.dart';

part 'playlist_info.freezed.dart';

/// YouTube playlist entity
@freezed
class PlaylistInfo with _$PlaylistInfo {
  const PlaylistInfo._();

  const factory PlaylistInfo({
    required String id,
    required String title,
    String? uploader,
    String? uploaderId,
    String? thumbnail,
    String? description,
    int? videoCount,
    required String webpageUrl,
  }) = _PlaylistInfo;

  /// Get formatted video count (e.g., "50 videos")
  String get formattedVideoCount {
    if (videoCount == null) return '';
    return videoCount == 1 ? '1 video' : '$videoCount videos';
  }

  /// Get high quality thumbnail URL
  String? get highQualityThumbnail {
    if (thumbnail == null) return null;
    // YouTube playlist thumbnails - upgrade to higher quality
    if (thumbnail!.contains('ytimg.com') || thumbnail!.contains('youtube.com')) {
      // Try to get hqdefault (better quality)
      return thumbnail!.replaceAll('/default.', '/hqdefault.');
    }
    return thumbnail;
  }
}
