/// V2 Smart Input — URL Classifier
///
/// Pure function that maps a raw input string to a [SmartInputType] per
/// UI Spec v1.1 §4.1 detection rules. No I/O, no async, no Riverpod —
/// safe to call from any layer.
///
/// Detection order (first match wins):
///   1. empty / whitespace-only          → [SmartInputType.empty]
///   2. ≥2 URLs (newline / whitespace / comma separated)
///                                       → [SmartInputType.multipleUrls]
///   3. single channel URL               → [SmartInputType.channel]
///   4. single playlist URL              → [SmartInputType.playlist]
///   5. single supported video URL       → [SmartInputType.singleVideo]
///   6. unsupported HTTP(S) URL          → [SmartInputType.unsupportedUrl]
///   7. plain text keyword               → [SmartInputType.searchKeyword]
///
/// The classifier is intentionally tolerant: it never throws and falls
/// back to [SmartInputType.searchKeyword] when nothing else matches.
library;

import '../../../../core/utils/platform_detector.dart';

/// Smart input intent — drives the adaptive CTA label and submit handler.
enum SmartInputType {
  /// Empty / whitespace-only input.
  empty,

  /// 2+ valid URLs separated by whitespace, comma or newline.
  multipleUrls,

  /// A platform channel URL (`youtube.com/@`, `tiktok.com/@`, etc.).
  channel,

  /// A platform playlist URL (`youtube.com/playlist?list=`,
  /// `youtube.com/watch?v=...&list=...`, etc.).
  playlist,

  /// A single supported video URL.
  singleVideo,

  /// HTTP(S) URL with valid host but no platform support (mockup
  /// case: open in browser tab).
  unsupportedUrl,

  /// Free-text search keyword (no URL, no whitespace-only).
  searchKeyword,
}

// v2.2 Phase 2D.0: removed the narrow `_PlatformHint` enum — em was
// duplicating platform detection logic with floating capture's
// `UrlPatternService` and only knew 5 platforms while floating capture
// handled 14. Now both call the shared `PlatformDetector.detectPlatform`
// so a Vimeo / Dailymotion / SoundCloud / Reddit / Bilibili etc. paste
// goes the same `singleVideo` smart path here as in the popup.

/// Classifies a raw input string into a [SmartInputType]. Pure / sync.
class UrlClassifierService {
  /// Optional injected detector for tests. Production path uses the
  /// const default which delegates to [PlatformDetector.detectPlatform].
  final VideoPlatform Function(String url) _detectPlatform;

  const UrlClassifierService({
    VideoPlatform Function(String url) detectPlatform = _defaultDetectPlatform,
  }) : _detectPlatform = detectPlatform;

  static VideoPlatform _defaultDetectPlatform(String url) =>
      PlatformDetector.detectPlatform(url);

  /// Per Spec §4.1 step 2 — token splitting on whitespace, comma,
  /// newline. Used for multi-URL detection.
  static final _multiSeparator = RegExp(r'[\s,]+');

  /// Permissive URL shape — protocol + host + optional path. Tighter
  /// than `Uri.parse` so we don't accidentally classify `c:\foo` as URL.
  static final _urlShape =
      RegExp(r'^https?://[^\s/$.?#][^\s]*$', caseSensitive: false);

  /// Channel handle pattern — works for YouTube `/@handle`, TikTok
  /// `/@handle`. Bare `youtube.com/c/Name` and `/user/Name` fall back
  /// to channel via the platform substring check.
  static final _handleChannelPath = RegExp(r'/@[^/?#\s]+');

  /// YouTube channel-style legacy paths (`/c/`, `/user/`, `/channel/`).
  static final _legacyChannelPath =
      RegExp(r'/(c|user|channel)/[^/?#\s]+', caseSensitive: false);

  /// Recognises playlist context — covers YouTube `?list=` and similar.
  static final _playlistQuery =
      RegExp(r'[?&]list=', caseSensitive: false);

  /// `/video/{id}` segment marks a TikTok-style video URL even when the
  /// path also contains a `/@handle` prefix. Without this guard we would
  /// classify `tiktok.com/@scout/video/7100` as a channel.
  static final _videoSegment =
      RegExp(r'/video/\d+', caseSensitive: false);

  SmartInputType classify(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return SmartInputType.empty;

    final tokens = trimmed
        .split(_multiSeparator)
        .where((t) => t.isNotEmpty)
        .toList(growable: false);

    final urlTokens =
        tokens.where(_isHttpUrlShape).toList(growable: false);

    // Rule 2 — ≥2 valid URLs → batch.
    if (urlTokens.length >= 2) return SmartInputType.multipleUrls;

    // Rule 3-6 — single URL with platform/category detection.
    if (urlTokens.length == 1 && tokens.length == 1) {
      final url = urlTokens.single;

      if (_isChannelUrl(url)) return SmartInputType.channel;
      if (_isPlaylistUrl(url)) return SmartInputType.playlist;
      // v2.2 Phase 2D.0: shared PlatformDetector — recognises every
      // platform the floating capture popup supports (Vimeo, Reddit,
      // Dailymotion, SoundCloud, Pinterest, Threads, LinkedIn, Bilibili,
      // Douyin in addition to the original YouTube/TikTok/IG/FB/Twitter).
      final platform = _detectPlatform(url);
      if (platform != VideoPlatform.unknown) return SmartInputType.singleVideo;
      return SmartInputType.unsupportedUrl;
    }

    // Rule 6 fallback — text mixed with one URL is treated as keyword.
    return SmartInputType.searchKeyword;
  }

  /// Splits the input into URL-shaped tokens using the same separator
  /// rules as [classify] (whitespace, comma, newline). Returns only
  /// tokens that match the HTTP URL shape — keyword text and other
  /// non-URL fragments are dropped. Caller is responsible for handling
  /// the empty-list case (e.g. classifier inconsistency).
  ///
  /// Used by smart-routing in `HomeDownloadMixin.startDownload` when
  /// [classify] returned [SmartInputType.multipleUrls] so the same
  /// regex governs detection and dispatch — no risk of "classifier
  /// counted 3 URLs but dispatcher split into 1".
  List<String> extractUrlTokens(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return const [];
    return trimmed
        .split(_multiSeparator)
        .where((t) => t.isNotEmpty && _isHttpUrlShape(t))
        .toList(growable: false);
  }

  bool _isHttpUrlShape(String token) => _urlShape.hasMatch(token);

  bool _isChannelUrl(String url) {
    // A `/video/{id}` segment unambiguously marks the URL as a single
    // video — even if the path also contains a `/@handle` prefix
    // (TikTok pattern). Skip the channel branch in that case.
    if (_videoSegment.hasMatch(url)) return false;
    return _handleChannelPath.hasMatch(url) || _legacyChannelPath.hasMatch(url);
  }

  bool _isPlaylistUrl(String url) => _playlistQuery.hasMatch(url);
}
