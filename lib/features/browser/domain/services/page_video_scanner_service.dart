import 'dart:convert';

import '../../../../core/utils/platform_detector.dart';

/// Type of source where a video link was found on the page.
enum VideoSourceType { link, embed, meta }

/// A video link detected on a web page by DOM scanning.
class DetectedVideoLink {
  final String url;
  final String title;
  final VideoPlatform platform;
  final VideoSourceType sourceType;

  const DetectedVideoLink({
    required this.url,
    required this.title,
    required this.platform,
    required this.sourceType,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DetectedVideoLink &&
          runtimeType == other.runtimeType &&
          url == other.url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() =>
      'DetectedVideoLink(url: $url, title: $title, platform: ${platform.name})';
}

/// Service that generates JavaScript to scan a web page's DOM for video links.
///
/// Scans `<a href>`, `<video src>`, `<source src>`, `<iframe src>`,
/// and `<meta property="og:video">` for URLs matching known video platforms.
class PageVideoScannerService {
  /// URL patterns per platform that indicate a video page.
  /// Each pattern is tested against the full URL (case-insensitive).
  static const _platformPatterns = {
    'youtube': [
      r'youtube\.com/watch\?',
      r'youtube\.com/shorts/',
      r'youtu\.be/',
      r'youtube\.com/embed/',
    ],
    'tiktok': [
      r'tiktok\.com/@[^/]+/video/',
      r'vt\.tiktok\.com/',
      r'tiktok\.com/t/',
    ],
    'instagram': [
      r'instagram\.com/(p|reel|tv)/',
    ],
    'facebook': [
      r'facebook\.com/.*/videos/',
      r'facebook\.com/watch',
      r'facebook\.com/reel/',
      r'fb\.watch/',
    ],
    'twitter': [
      r'(twitter\.com|x\.com)/[^/]+/status/',
    ],
    'vimeo': [
      r'vimeo\.com/\d+',
      r'player\.vimeo\.com/video/',
    ],
    'dailymotion': [
      r'dailymotion\.com/video/',
      r'dai\.ly/',
    ],
    'reddit': [
      r'reddit\.com/.*/comments/',
    ],
    'soundcloud': [
      r'soundcloud\.com/[^/]+/[^/]+',
    ],
    'bilibili': [
      r'bilibili\.com/video/(BV|av)',
    ],
  };

  /// Map platform string key to VideoPlatform enum.
  static VideoPlatform _toPlatform(String key) {
    switch (key) {
      case 'youtube':
        return VideoPlatform.youtube;
      case 'tiktok':
        return VideoPlatform.tiktok;
      case 'instagram':
        return VideoPlatform.instagram;
      case 'facebook':
        return VideoPlatform.facebook;
      case 'twitter':
        return VideoPlatform.twitter;
      case 'vimeo':
        return VideoPlatform.vimeo;
      case 'dailymotion':
        return VideoPlatform.dailymotion;
      case 'reddit':
        return VideoPlatform.reddit;
      case 'soundcloud':
        return VideoPlatform.soundcloud;
      case 'bilibili':
        return VideoPlatform.bilibili;
      default:
        return VideoPlatform.unknown;
    }
  }

  /// Generate JavaScript that scans the DOM and returns a JSON array of
  /// detected video links. Each entry: `{url, title, sourceType}`.
  ///
  /// The script is a self-executing function returning a JSON string.
  String generateScanScript() {
    // Build regex patterns string for JS
    final allPatterns = <String>[];
    for (final entry in _platformPatterns.entries) {
      for (final p in entry.value) {
        allPatterns.add(p);
      }
    }
    final combinedPattern = allPatterns.join('|');

    return '(function() {\n'
        '  var results = [];\n'
        '  var seen = {};\n'
        "  var videoPattern = new RegExp('$combinedPattern', 'i');\n"
        '\n'
        '  function addResult(url, title, sourceType) {\n'
        '    if (!url || typeof url !== "string") return;\n'
        '    url = url.trim();\n'
        '    if (url.length === 0 || url === "#") return;\n'
        '    if (!url.startsWith("http")) return;\n'
        '    var normalized = url.split("?")[0].split("#")[0].replace(/\\/+\$/, "").toLowerCase();\n'
        '    if (seen[normalized]) return;\n'
        '    if (!videoPattern.test(url)) return;\n'
        '    seen[normalized] = true;\n'
        '    results.push({url: url, title: title || "", sourceType: sourceType});\n'
        '  }\n'
        '\n'
        '  // Scan <a href> links\n'
        "  var links = document.querySelectorAll('a[href]');\n"
        '  for (var i = 0; i < links.length; i++) {\n'
        '    var a = links[i];\n'
        "    addResult(a.href, a.textContent.trim().substring(0, 200), 'link');\n"
        '  }\n'
        '\n'
        '  // Scan <video src> and <source src>\n'
        "  var videos = document.querySelectorAll('video[src], video source[src]');\n"
        '  for (var i = 0; i < videos.length; i++) {\n'
        "    addResult(videos[i].src || videos[i].getAttribute('src'), '', 'embed');\n"
        '  }\n'
        '\n'
        '  // Scan <iframe src> for video embeds\n'
        "  var iframes = document.querySelectorAll('iframe[src]');\n"
        '  for (var i = 0; i < iframes.length; i++) {\n'
        "    addResult(iframes[i].src, '', 'embed');\n"
        '  }\n'
        '\n'
        '  // Scan og:video meta tags\n'
        "  var metas = document.querySelectorAll('meta[property=\"og:video\"], meta[property=\"og:video:url\"]');\n"
        '  for (var i = 0; i < metas.length; i++) {\n'
        "    addResult(metas[i].getAttribute('content'), document.title, 'meta');\n"
        '  }\n'
        '\n'
        '  return JSON.stringify(results);\n'
        '})()';
  }

  /// Parse the JSON string returned by the scan script into a list of
  /// [DetectedVideoLink] entities. Deduplicates by normalized URL.
  List<DetectedVideoLink> parseResults(String jsonString) {
    // Clean up the JSON string — WebView may wrap in quotes
    var cleaned = jsonString.trim();
    if (cleaned.startsWith("'") && cleaned.endsWith("'")) {
      cleaned = cleaned.substring(1, cleaned.length - 1);
    }
    if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
      cleaned = cleaned.substring(1, cleaned.length - 1);
      // Unescape inner quotes
      cleaned = cleaned
          .replaceAll(r'\"', '"')
          .replaceAll(r'\\', r'\');
    }

    if (cleaned.isEmpty || cleaned == '[]') return [];

    try {
      final List<dynamic> items =
          _parseJsonArray(cleaned);
      final results = <DetectedVideoLink>[];
      final seen = <String>{};

      for (final item in items) {
        if (item is! Map) continue;
        final url = (item['url'] as String?)?.trim() ?? '';
        if (url.isEmpty) continue;

        final normalized = _normalizeUrl(url);
        if (seen.contains(normalized)) continue;
        seen.add(normalized);

        final platform = _detectPlatform(url);
        if (platform == VideoPlatform.unknown) continue;

        final sourceTypeStr = (item['sourceType'] as String?) ?? 'link';
        final sourceType = _parseSourceType(sourceTypeStr);
        final title = (item['title'] as String?)?.trim() ?? '';

        results.add(DetectedVideoLink(
          url: url,
          title: title.isNotEmpty ? title : _titleFromUrl(url),
          platform: platform,
          sourceType: sourceType,
        ));
      }

      return results;
    } catch (_) {
      return [];
    }
  }

  /// Detect which video platform a URL belongs to.
  static VideoPlatform _detectPlatform(String url) {
    final lowerUrl = url.toLowerCase();
    for (final entry in _platformPatterns.entries) {
      for (final pattern in entry.value) {
        if (RegExp(pattern, caseSensitive: false).hasMatch(lowerUrl)) {
          return _toPlatform(entry.key);
        }
      }
    }
    return VideoPlatform.unknown;
  }

  /// Normalize URL for deduplication: strip query, fragment, trailing slashes.
  static String _normalizeUrl(String url) {
    return url
        .split('?')[0]
        .split('#')[0]
        .replaceAll(RegExp(r'/+$'), '')
        .toLowerCase();
  }

  static VideoSourceType _parseSourceType(String s) {
    switch (s) {
      case 'embed':
        return VideoSourceType.embed;
      case 'meta':
        return VideoSourceType.meta;
      default:
        return VideoSourceType.link;
    }
  }

  /// Generate a title from the URL when no text is available.
  static String _titleFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final path = uri.path;
    if (path.isEmpty || path == '/') return uri.host;
    // Take the last non-empty path segment
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return uri.host;
    return Uri.decodeComponent(segments.last);
  }

  /// Simple JSON array parser that handles the common case.
  static List<dynamic> _parseJsonArray(String json) {
    // Use dart:convert
    return _jsonDecode(json);
  }

  static List<dynamic> _jsonDecode(String json) {
    return const JsonDecoder().convert(json) as List<dynamic>;
  }
}
