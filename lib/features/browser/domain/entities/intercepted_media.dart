/// A media resource detected by the browser's network interceptor (IDM mode).
///
/// Represents a downloadable media URL captured from one of the interception
/// layers: PerformanceObserver, fetch/XHR monkey-patch, DOM MutationObserver,
/// or MediaSource monitoring.
class InterceptedMedia {
  /// The media resource URL.
  final String url;

  /// MIME type from Content-Type header or extension inference (nullable).
  final String? contentType;

  /// Estimated file size in bytes (from Content-Length or PerformanceObserver transferSize).
  final int? estimatedSize;

  /// How this media was detected.
  final InterceptionSource source;

  /// Classified media type after detection pipeline.
  final MediaCategory category;

  /// The domain serving this resource (extracted from URL).
  final String domain;

  /// Optional filename hint (from URL path or Content-Disposition).
  final String? filename;

  /// Whether the server supports HTTP Range requests (from HEAD probe).
  final bool? supportsRange;

  /// Page title at time of interception (from `document.title`).
  final String? pageTitle;

  /// Page URL at time of interception (from `location.href`).
  final String? pageUrl;

  /// When this media was first intercepted.
  final DateTime detectedAt;

  const InterceptedMedia({
    required this.url,
    this.contentType,
    this.estimatedSize,
    required this.source,
    required this.category,
    required this.domain,
    this.filename,
    this.supportsRange,
    this.pageTitle,
    this.pageUrl,
    required this.detectedAt,
  });

  /// Extract domain from a URL.
  static String extractDomain(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return '';
    }
  }

  /// Extract filename from URL path.
  static String? extractFilename(String url) {
    try {
      final path = Uri.parse(url).path;
      final lastSlash = path.lastIndexOf('/');
      if (lastSlash < 0 || lastSlash == path.length - 1) return null;
      final name = path.substring(lastSlash + 1);
      // Strip common query-like suffixes that sneak into path
      final cleaned = name.split('?').first;
      return cleaned.isNotEmpty ? cleaned : null;
    } catch (_) {
      return null;
    }
  }

  /// Unique key for deduplication (normalized URL without tracking params).
  String get deduplicationKey {
    try {
      final uri = Uri.parse(url);
      // Keep only essential query params, strip tracking
      final essentialParams = <String, String>{};
      for (final entry in uri.queryParameters.entries) {
        // Keep params that affect content (itag, quality, etc.)
        if (_essentialParams.contains(entry.key.toLowerCase())) {
          essentialParams[entry.key] = entry.value;
        }
      }
      return Uri(
        scheme: uri.scheme,
        host: uri.host,
        path: uri.path,
        queryParameters: essentialParams.isEmpty ? null : essentialParams,
      ).toString();
    } catch (_) {
      return url;
    }
  }

  static const _essentialParams = {
    'itag', 'mime', 'quality', 'res', 'format', 'type', 'range',
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InterceptedMedia && deduplicationKey == other.deduplicationKey;

  @override
  int get hashCode => deduplicationKey.hashCode;
}

/// How the media was detected.
enum InterceptionSource {
  /// PerformanceObserver resource entry.
  performance,

  /// fetch() API monkey-patch.
  fetch,

  /// XMLHttpRequest monkey-patch.
  xhr,

  /// DOM MutationObserver (video/audio/source element).
  dom,

  /// MediaSource.addSourceBuffer monitoring.
  mediaSource,

  /// Native WebView hook (Windows shouldInterceptAjaxRequest/FetchRequest).
  nativeHook,
}

/// Broad classification of the media resource.
enum MediaCategory {
  /// Progressive video file (.mp4, .webm, .mkv, etc.)
  video,

  /// Audio file (.mp3, .m4a, .aac, etc.)
  audio,

  /// HLS streaming manifest (.m3u8)
  hlsStream,

  /// DASH streaming manifest (.mpd)
  dashStream,

  /// HLS/DASH segment (.ts, .m4s)
  streamSegment,

  /// Unknown media type
  unknown,
}
