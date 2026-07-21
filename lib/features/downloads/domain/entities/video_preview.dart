import '../../../../core/utils/platform_detector.dart';

/// Lightweight video metadata for fast preview display.
///
/// Subset of [VideoInfo] populated via lightweight APIs (oEmbed) instead of
/// full yt-dlp extraction. Used to render thumbnail + title + uploader in
/// the floating capture popup < 500ms after URL copy, before full extraction
/// completes.
///
/// Per spec v2.1 §3.3 (IPC architecture): instances of this class travel over
/// MethodChannel `svid.floating_capture` between main and floating Flutter
/// engines. [toJson] / [fromJson] are required for serialization.
///
/// See `docs/SSvid_v2_1_FloatingCapture_Spec.md` for full context.
class VideoPreview {
  /// Original URL as pasted by user (preserve query params for downstream use).
  final String rawUrl;

  /// Detected platform (regex-based, instant).
  final VideoPlatform platform;

  /// Detected URL type (video/playlist/channel/etc.). Determines whether
  /// preview is applicable.
  final UrlType urlType;

  /// Platform-specific identifier extracted from URL (video ID for YouTube,
  /// status ID for Twitter, etc.). Null when URL type isn't a single item.
  final String? itemId;

  /// Video title (from oEmbed `title` field). Null when fetch failed or
  /// platform doesn't support oEmbed.
  final String? title;

  /// Uploader / channel name (from oEmbed `author_name` field).
  final String? uploader;

  /// Thumbnail URL — derived from CDN pattern (YouTube) or oEmbed response.
  /// Image widget should fall back to `hqdefault.jpg` if `maxresdefault.jpg`
  /// returns 404.
  final String? thumbnailUrl;

  /// Optional start timestamp parsed from `?t=Ns` query param. Used by
  /// Section trim feature when downloading.
  final Duration? startTimestamp;

  /// Optional playlist ID parsed from `&list=` query param. When present,
  /// the URL points to a video within a playlist context.
  final String? playlistId;

  /// True when at least title+uploader were fetched. Pure URL parse without
  /// network fetch will have `false`.
  final bool hasFetchedMetadata;

  const VideoPreview({
    required this.rawUrl,
    required this.platform,
    required this.urlType,
    this.itemId,
    this.title,
    this.uploader,
    this.thumbnailUrl,
    this.startTimestamp,
    this.playlistId,
    this.hasFetchedMetadata = false,
  });

  /// Whether the URL is suitable for lightweight preview (single video item).
  /// Channel/playlist/search URLs require dialogs, not preview cards.
  bool get isPreviewable => urlType == UrlType.video;

  /// True when we have enough metadata to render a card.
  /// Even without title (oEmbed failed), platform + thumbnail can show a
  /// minimal preview.
  bool get hasMinimalDisplay =>
      platform != VideoPlatform.unknown && thumbnailUrl != null;

  VideoPreview copyWith({
    String? rawUrl,
    VideoPlatform? platform,
    UrlType? urlType,
    String? itemId,
    String? title,
    String? uploader,
    String? thumbnailUrl,
    Duration? startTimestamp,
    String? playlistId,
    bool? hasFetchedMetadata,
  }) {
    return VideoPreview(
      rawUrl: rawUrl ?? this.rawUrl,
      platform: platform ?? this.platform,
      urlType: urlType ?? this.urlType,
      itemId: itemId ?? this.itemId,
      title: title ?? this.title,
      uploader: uploader ?? this.uploader,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      startTimestamp: startTimestamp ?? this.startTimestamp,
      playlistId: playlistId ?? this.playlistId,
      hasFetchedMetadata: hasFetchedMetadata ?? this.hasFetchedMetadata,
    );
  }

  // ============================================================================
  // JSON serialization (required for MethodChannel IPC per spec v2.1 §3.3)
  // ============================================================================

  /// Serialize to JSON-encodable map for IPC transport.
  ///
  /// Encoding choices:
  /// - `platform` and `urlType` as enum `name` strings (stable across versions)
  /// - `startTimestamp` as int microseconds (null preserved as null)
  Map<String, dynamic> toJson() => {
        'rawUrl': rawUrl,
        'platform': platform.name,
        'urlType': urlType.name,
        'itemId': itemId,
        'title': title,
        'uploader': uploader,
        'thumbnailUrl': thumbnailUrl,
        'startTimestampMicros': startTimestamp?.inMicroseconds,
        'playlistId': playlistId,
        'hasFetchedMetadata': hasFetchedMetadata,
      };

  /// Deserialize from JSON map. Throws if required fields missing or wrong type.
  ///
  /// Unknown enum values (e.g., from newer producer) fall back to safe defaults
  /// — `VideoPlatform.unknown` and `UrlType.unknown` — to keep IPC robust
  /// across version skew.
  factory VideoPreview.fromJson(Map<String, dynamic> json) {
    return VideoPreview(
      rawUrl: json['rawUrl'] as String,
      platform: VideoPlatform.values.firstWhere(
        (p) => p.name == json['platform'],
        orElse: () => VideoPlatform.unknown,
      ),
      urlType: UrlType.values.firstWhere(
        (t) => t.name == json['urlType'],
        orElse: () => UrlType.unknown,
      ),
      itemId: json['itemId'] as String?,
      title: json['title'] as String?,
      uploader: json['uploader'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      startTimestamp: json['startTimestampMicros'] != null
          ? Duration(microseconds: json['startTimestampMicros'] as int)
          : null,
      playlistId: json['playlistId'] as String?,
      hasFetchedMetadata: (json['hasFetchedMetadata'] as bool?) ?? false,
    );
  }

  // ============================================================================
  // Equality (required for Riverpod state comparison — avoid unnecessary rebuilds)
  // ============================================================================

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VideoPreview &&
        other.rawUrl == rawUrl &&
        other.platform == platform &&
        other.urlType == urlType &&
        other.itemId == itemId &&
        other.title == title &&
        other.uploader == uploader &&
        other.thumbnailUrl == thumbnailUrl &&
        other.startTimestamp == startTimestamp &&
        other.playlistId == playlistId &&
        other.hasFetchedMetadata == hasFetchedMetadata;
  }

  @override
  int get hashCode => Object.hash(
        rawUrl,
        platform,
        urlType,
        itemId,
        title,
        uploader,
        thumbnailUrl,
        startTimestamp,
        playlistId,
        hasFetchedMetadata,
      );

  @override
  String toString() =>
      'VideoPreview(${platform.name}/$urlType, id=$itemId, title=$title, '
      'thumb=${thumbnailUrl != null}, fetched=$hasFetchedMetadata)';
}

/// Categorical type of a URL for routing decisions.
///
/// Determines whether the URL → single video preview vs. channel/playlist
/// browse dialog vs. search keyword vs. unsupported.
enum UrlType {
  /// Single video URL → eligible for lightweight preview.
  video,

  /// Playlist URL → opens playlist sheet with video list.
  playlist,

  /// Channel/profile URL → opens channel sheet.
  channel,

  /// Live stream URL.
  live,

  /// Search query URL (e.g. youtube.com/results?search_query=...).
  search,

  /// HTTPS URL on supported platform but doesn't match any known pattern
  /// (could be community post, embed, etc.).
  unknown,

  /// Not a URL — treat as search keyword.
  notUrl,
}
