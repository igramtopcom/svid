import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/intercepted_media.dart';
import '../../domain/services/media_head_probe_service.dart';

/// Detected media items from the browser's network interceptor (IDM mode).
///
/// JS interception scripts report media URLs via message channels.
/// This provider maintains the deduplicated list for the current page.
final interceptedMediaProvider =
    StateNotifierProvider<InterceptedMediaNotifier, List<InterceptedMedia>>(
        (ref) {
  return InterceptedMediaNotifier();
});

class InterceptedMediaNotifier extends StateNotifier<List<InterceptedMedia>> {
  InterceptedMediaNotifier() : super(const []);

  final Set<String> _seenKeys = {};

  /// Hard cap on stored items per page. Heavy pages (infinite-scroll homepages
  /// like a news site) can flood the interceptor with hundreds of resources;
  /// without a bound the list grows unbounded, each add is an O(n) copy, and
  /// every item fires a background HEAD probe — enough to exhaust memory/threads
  /// and crash the app. The first N downloadable items are more than enough.
  static const int _maxItems = 40;

  /// Process a raw message from the JS interceptor.
  /// Returns the parsed [InterceptedMedia] if new, null if duplicate or invalid.
  InterceptedMedia? processMessage(dynamic rawMessage) {
    final data = _parseMessage(rawMessage);
    if (data == null) return null;

    // Drop HLS/DASH segments as early and cheaply as possible: they are the
    // single biggest source of flood on streaming sites and are never an
    // independently downloadable file (the .m3u8 manifest is the real item).
    if (data['type'] == 'segment') return null;

    // Bound memory/work on flood-heavy pages — once we've collected enough
    // real media, stop ingesting (segments above are dropped for free and do
    // not count toward this cap).
    if (state.length >= _maxItems) return null;

    final url = data['url'] as String?;
    // MediaSource reports may have no URL (just mimeType)
    if (url == null && data['source'] != 'mediasource') return null;

    final pageTitle = data['pageTitle'] as String?;
    final pageUrl = data['pageUrl'] as String?;
    final pageThumb = data['pageThumb'] as String?;

    final media = InterceptedMedia(
      url: url ?? '',
      contentType: data['mimeType'] as String?,
      estimatedSize: _parseSize(data['size']),
      source: _parseSource(data['source'] as String?),
      category: _parseCategory(
        data['type'] as String?,
        data['mimeType'] as String?,
      ),
      domain: url != null ? InterceptedMedia.extractDomain(url) : '',
      filename: url != null ? InterceptedMedia.extractFilename(url) : null,
      pageTitle: pageTitle != null && pageTitle.isNotEmpty ? pageTitle : null,
      pageUrl: pageUrl,
      pageThumb: pageThumb != null && pageThumb.isNotEmpty ? pageThumb : null,
      detectedAt: DateTime.now(),
    );

    // Skip empty URLs (MediaSource without URL — useful as signal but not downloadable)
    if (media.url.isEmpty) return null;

    // Deduplicate
    final key = media.deduplicationKey;
    if (_seenKeys.contains(key)) return null;
    _seenKeys.add(key);

    state = [...state, media];

    // Fire background HEAD probe to enrich metadata (size, range support)
    _probeInBackground(media);

    return media;
  }

  /// Background HEAD probe — enriches a detected media item with server metadata.
  Future<void> _probeInBackground(InterceptedMedia media) async {
    try {
      final enriched = await MediaHeadProbeService.enrich(media);
      if (!mounted) return;
      // Only update if probe returned new info
      if (enriched.estimatedSize != media.estimatedSize ||
          enriched.supportsRange != media.supportsRange ||
          enriched.contentType != media.contentType ||
          enriched.category != media.category) {
        state = [
          for (final m in state)
            m.deduplicationKey == media.deduplicationKey ? enriched : m,
        ];
      }
    } catch (_) {
      // Non-fatal: probe is best-effort
    }
  }

  /// Clear all detected media (called on page navigation).
  void clear() {
    _seenKeys.clear();
    state = const [];
  }

  /// Remove a single item by URL.
  void remove(String url) {
    state = state.where((m) => m.url != url).toList();
  }

  // ── Parsing helpers ──

  static Map<String, dynamic>? _parseMessage(dynamic message) {
    if (message is Map<String, dynamic>) return message;
    if (message is String) {
      try {
        final decoded = jsonDecode(message);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return null;
  }

  static int? _parseSize(dynamic size) {
    if (size is int) return size > 0 ? size : null;
    if (size is double) return size > 0 ? size.toInt() : null;
    return null;
  }

  static InterceptionSource _parseSource(String? source) {
    switch (source) {
      case 'performance':
        return InterceptionSource.performance;
      case 'fetch':
        return InterceptionSource.fetch;
      case 'xhr':
        return InterceptionSource.xhr;
      case 'dom':
        return InterceptionSource.dom;
      case 'mediasource':
        return InterceptionSource.mediaSource;
      default:
        return InterceptionSource.performance;
    }
  }

  static MediaCategory _parseCategory(String? type, String? mimeType) {
    // Check explicit type from JS classifier
    switch (type) {
      case 'video':
        return MediaCategory.video;
      case 'audio':
        return MediaCategory.audio;
      case 'stream':
        // Distinguish HLS vs DASH from mimeType if available
        if (mimeType != null && mimeType.contains('dash')) {
          return MediaCategory.dashStream;
        }
        return MediaCategory.hlsStream;
      case 'segment':
        return MediaCategory.streamSegment;
    }
    // Fallback: check mimeType
    if (mimeType != null) {
      if (mimeType.startsWith('video/')) return MediaCategory.video;
      if (mimeType.startsWith('audio/')) return MediaCategory.audio;
      if (mimeType.contains('mpegurl')) return MediaCategory.hlsStream;
      if (mimeType.contains('dash')) return MediaCategory.dashStream;
    }
    return MediaCategory.unknown;
  }
}
