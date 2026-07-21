import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../../core/logging/app_logger.dart';
import '../entities/intercepted_media.dart';

/// Lightweight HEAD probe to enrich intercepted media with server metadata.
///
/// Sends a HEAD request to determine:
/// - Content-Length (accurate file size)
/// - Content-Type (MIME verification)
/// - Accept-Ranges support (enables multi-segment download)
///
/// Non-blocking, timeout-protected, never throws to caller.
class MediaHeadProbeService {
  static final _client = http.Client();

  /// CDN domains that always reject or timeout on HEAD probes.
  /// Skip these to avoid 5s timeout per intercepted item.
  static const _skipDomains = {
    'fbcdn.net',
    'cdninstagram.com',
    'video.twimg.com',
    'tiktokcdn.com',
    'tiktokv.com',
    'tiktokcdn-us.com',
    'googlevideo.com',
    'googleusercontent.com',
  };

  /// Probe a media URL and return enriched metadata.
  /// Returns null on any failure (timeout, network error, 4xx/5xx).
  static Future<HeadProbeResult?> probe(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      // Skip known CDN domains that always reject HEAD probes
      final host = Uri.tryParse(url)?.host ?? '';
      if (_skipDomains.any((domain) => host.endsWith(domain))) {
        appLogger.debug('[HeadProbe] Skipped: $host (CDN skip list)');
        return null;
      }

      final request = http.Request('HEAD', Uri.parse(url));
      if (headers != null) {
        request.headers.addAll(headers);
      }
      // Add a generic user-agent to avoid bot detection
      request.headers.putIfAbsent(
        'User-Agent',
        () =>
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15',
      );

      final response = await _client.send(request).timeout(timeout);
      // Drain the response body (should be empty for HEAD)
      await response.stream.drain<void>();

      if (response.statusCode >= 400) return null;

      final contentLength = response.contentLength;
      final contentType = response.headers['content-type'];
      final acceptRanges = response.headers['accept-ranges'];
      final supportsRange =
          acceptRanges != null && acceptRanges.toLowerCase() != 'none';

      return HeadProbeResult(
        contentLength: contentLength,
        contentType: contentType,
        supportsRange: supportsRange,
      );
    } catch (e) {
      appLogger.debug('[HeadProbe] Failed for $url: $e');
      return null;
    }
  }

  /// Probe and enrich an InterceptedMedia instance.
  /// Returns a new InterceptedMedia with updated size/type/range info.
  ///
  /// Automatically adds Referer and Origin headers derived from the media's
  /// domain to avoid CDN 403 rejections on CORS-protected resources.
  static Future<InterceptedMedia> enrich(
    InterceptedMedia media, {
    Map<String, String>? headers,
  }) async {
    // Build default headers with Referer/Origin from media domain
    final probeHeaders = <String, String>{};
    if (media.domain.isNotEmpty) {
      final referer = 'https://${media.domain}/';
      probeHeaders['Referer'] = referer;
      probeHeaders['Origin'] = 'https://${media.domain}';
    }
    if (headers != null) {
      probeHeaders.addAll(headers); // Caller overrides take precedence
    }
    final result = await probe(media.url, headers: probeHeaders);
    if (result == null) return media;

    return InterceptedMedia(
      url: media.url,
      contentType: result.contentType ?? media.contentType,
      estimatedSize: result.contentLength ?? media.estimatedSize,
      source: media.source,
      category: _refineCategory(media.category, result.contentType),
      domain: media.domain,
      filename: media.filename,
      supportsRange: result.supportsRange,
      pageTitle: media.pageTitle,
      pageUrl: media.pageUrl,
      detectedAt: media.detectedAt,
    );
  }

  /// Refine category based on actual Content-Type from HEAD response.
  static MediaCategory _refineCategory(
    MediaCategory current,
    String? contentType,
  ) {
    if (contentType == null) return current;
    final ct = contentType.toLowerCase();

    if (ct.contains('mpegurl') || ct.contains('x-mpegurl')) {
      return MediaCategory.hlsStream;
    }
    if (ct.contains('dash+xml')) return MediaCategory.dashStream;
    if (ct.startsWith('video/')) return MediaCategory.video;
    if (ct.startsWith('audio/')) return MediaCategory.audio;

    return current;
  }
}

/// Result of a HEAD probe request.
class HeadProbeResult {
  final int? contentLength;
  final String? contentType;
  final bool supportsRange;

  const HeadProbeResult({
    this.contentLength,
    this.contentType,
    required this.supportsRange,
  });
}
