import 'package:freezed_annotation/freezed_annotation.dart';

part 'youtube_search_result.freezed.dart';

/// YouTube search result entity
@freezed
class YouTubeSearchResult with _$YouTubeSearchResult {
  const YouTubeSearchResult._();

  const factory YouTubeSearchResult({
    required String id,
    required String title,
    String? channel,
    String? channelId,
    String? thumbnail,
    int? durationSeconds,
    int? viewCount,
    String? uploadDate,
    required String url,
    String? description,
  }) = _YouTubeSearchResult;

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

  /// Get formatted upload date (e.g., "2 days ago")
  String get formattedUploadDate {
    if (uploadDate == null || uploadDate!.isEmpty) return '';

    // If already in relative format, return as is
    if (uploadDate!.contains('ago') ||
        uploadDate!.contains('day') ||
        uploadDate!.contains('week') ||
        uploadDate!.contains('month') ||
        uploadDate!.contains('year') ||
        uploadDate!.contains('hour')) {
      return uploadDate!;
    }

    // Try to parse YYYYMMDD format
    if (uploadDate!.length == 8) {
      try {
        final year = int.parse(uploadDate!.substring(0, 4));
        final month = int.parse(uploadDate!.substring(4, 6));
        final day = int.parse(uploadDate!.substring(6, 8));
        final date = DateTime(year, month, day);
        final diff = DateTime.now().difference(date);

        if (diff.inDays == 0) return 'Today';
        if (diff.inDays == 1) return '1 day ago';
        if (diff.inDays < 7) return '${diff.inDays} days ago';
        if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} weeks ago';
        if (diff.inDays < 365) {
          return '${(diff.inDays / 30).floor()} months ago';
        }
        return '${(diff.inDays / 365).floor()} years ago';
      } catch (_) {
        return uploadDate!;
      }
    }

    return uploadDate!;
  }

  /// Whether this result is a channel (not a video).
  /// Channels have no duration, and their URL contains /channel/ or /@.
  bool get isChannel {
    if (durationSeconds != null && durationSeconds! > 0) return false;
    return url.contains('/channel/') ||
        url.contains('/@') ||
        url.contains('/user/') ||
        url.contains('/c/');
  }

  /// 16:9 thumbnail (320×180) — for list items (160×90 display).
  /// Avoid `hqdefault.jpg` here because it is 4:3 and crops poorly in lists.
  String? get highQualityThumbnail {
    if (thumbnail == null || thumbnail!.isEmpty) return null;
    if (isChannel) return thumbnail;
    if (id.isNotEmpty &&
        (thumbnail!.contains('ytimg.com') ||
            thumbnail!.contains('youtube.com'))) {
      return 'https://img.youtube.com/vi/$id/mqdefault.jpg';
    }
    return thumbnail;
  }

  /// Max resolution thumbnail (1280×720) — for featured cards and large displays
  String? get maxResThumbnail {
    if (thumbnail == null || thumbnail!.isEmpty) return null;
    if (isChannel) return thumbnail;
    if (id.isNotEmpty &&
        (thumbnail!.contains('ytimg.com') ||
            thumbnail!.contains('youtube.com'))) {
      return 'https://img.youtube.com/vi/$id/maxresdefault.jpg';
    }
    return thumbnail;
  }
}
