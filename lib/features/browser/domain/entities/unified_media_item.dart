import '../../../../core/utils/platform_detector.dart';
import 'intercepted_media.dart';

/// How a download should be routed based on detection type.
enum MediaItemType {
  /// DOM-scanned video page URL — route to yt-dlp extraction for quality selection.
  videoPageLink,

  /// Complete downloadable media file on unknown site — route to Rust engine.
  directMediaFile,

  /// HLS manifest (.m3u8) — route to Rust HLS engine.
  hlsManifest,

  /// CDN activity detected on a known platform — route to yt-dlp via page URL.
  streamingSignal,

  /// DASH fragment, tiny segment, or otherwise not independently downloadable.
  undownloadable,
}

/// Where the item was originally detected.
enum MediaItemSource {
  /// Found by DOM scanning (PageVideoScannerService).
  dom,

  /// Found by network interception (MediaInterceptorService).
  network,

  /// Merged from both sources.
  both,
}

/// A unified media item merging DOM-scanned video links and network-intercepted
/// media into a single model with smart download routing.
class UnifiedMediaItem {
  /// URL shown in the UI (page URL for DOM links, CDN URL for network items).
  final String displayUrl;

  /// Actual URL to download (null for undownloadable/streaming signals).
  final String? downloadUrl;

  /// Page URL for yt-dlp extraction (set for videoPageLink and streamingSignal).
  final String? pageUrl;

  /// How this item should be downloaded.
  final MediaItemType type;

  /// Display title (from DOM link text, filename, or domain).
  final String? title;

  /// Suggested filename for direct downloads.
  final String? filename;

  /// Detected platform name (e.g. "youtube", "instagram").
  final VideoPlatform platform;

  /// Estimated file size in bytes (from HEAD probe or PerformanceObserver).
  final int? estimatedSize;

  /// MIME content type if known.
  final String? contentType;

  /// Domain serving the resource.
  final String domain;

  /// When this item was first detected.
  final DateTime detectedAt;

  /// Where the detection originated.
  final MediaItemSource source;

  /// Whether the server supports HTTP Range requests.
  final bool? supportsRange;

  /// Original media category (for network-intercepted items).
  final MediaCategory? originalCategory;

  const UnifiedMediaItem({
    required this.displayUrl,
    this.downloadUrl,
    this.pageUrl,
    required this.type,
    this.title,
    this.filename,
    this.platform = VideoPlatform.unknown,
    this.estimatedSize,
    this.contentType,
    required this.domain,
    required this.detectedAt,
    required this.source,
    this.supportsRange,
    this.originalCategory,
  });

  /// Whether this item can be downloaded (has a valid route).
  bool get isDownloadable =>
      type == MediaItemType.videoPageLink ||
      type == MediaItemType.directMediaFile ||
      type == MediaItemType.hlsManifest ||
      type == MediaItemType.streamingSignal;

  /// Whether this item routes through yt-dlp.
  bool get usesYtdlp =>
      type == MediaItemType.videoPageLink ||
      type == MediaItemType.streamingSignal;

  /// Whether this item uses direct Rust engine download.
  bool get usesRustEngine =>
      type == MediaItemType.directMediaFile ||
      type == MediaItemType.hlsManifest;

  /// Deduplication key — combines source type with URL for uniqueness.
  String get deduplicationKey {
    if (pageUrl != null) return 'page:$pageUrl';
    return 'url:$displayUrl';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnifiedMediaItem &&
          deduplicationKey == other.deduplicationKey;

  @override
  int get hashCode => deduplicationKey.hashCode;
}
