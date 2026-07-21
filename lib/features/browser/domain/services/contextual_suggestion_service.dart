/// Type of batch-download suggestion detected from URL context.
enum SuggestionType {
  youtubePlaylist,
  youtubeChannel,
  vimeoShowcase,
  genericSeries,
}

/// A contextual download suggestion inferred from the current browser URL.
class DownloadSuggestion {
  final SuggestionType type;
  final String detectedUrl;

  const DownloadSuggestion({
    required this.type,
    required this.detectedUrl,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadSuggestion &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          detectedUrl == other.detectedUrl;

  @override
  int get hashCode => Object.hash(type, detectedUrl);
}

/// Rule-based service that detects playlist/series/channel pages from URL.
///
/// No LLM — uses URL pattern matching only. Fast, offline, deterministic.
class ContextualSuggestionService {
  ContextualSuggestionService._();

  /// Analyze [url] and return a [DownloadSuggestion] if a batch-download
  /// opportunity is detected, or null otherwise.
  static DownloadSuggestion? analyze(String url) {
    if (url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return null;

    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    final query = uri.query.toLowerCase();

    // ── YouTube ──────────────────────────────────────────────────────────────
    if (host.contains('youtube.com') || host.contains('youtu.be')) {
      // Explicit playlist: ?list= query param (and not a /watch individual video
      // that happens to have a list param — we only suggest when the user is ON
      // the playlist page, i.e. path == /playlist)
      if (path == '/playlist' && query.contains('list=')) {
        return DownloadSuggestion(
            type: SuggestionType.youtubePlaylist, detectedUrl: url);
      }
      // Channel pages
      if (_isYouTubeChannelPath(path)) {
        return DownloadSuggestion(
            type: SuggestionType.youtubeChannel, detectedUrl: url);
      }
    }

    // ── Vimeo ─────────────────────────────────────────────────────────────────
    if (host.contains('vimeo.com')) {
      if (path.contains('/showcase/') || path.contains('/album/')) {
        return DownloadSuggestion(
            type: SuggestionType.vimeoShowcase, detectedUrl: url);
      }
    }

    // ── Generic series/season/episode patterns ────────────────────────────────
    if (_isGenericSeriesUrl(path)) {
      return DownloadSuggestion(
          type: SuggestionType.genericSeries, detectedUrl: url);
    }

    return null;
  }

  static bool _isYouTubeChannelPath(String path) {
    // /@handle, /@handle/videos, /@handle/playlists
    if (RegExp(r'^/@[^/]+(/videos|/playlists|/streams)?$').hasMatch(path)) {
      return true;
    }
    // /channel/<id>, /channel/<id>/videos
    if (RegExp(r'^/channel/[^/]+(/videos|/playlists|/streams)?$')
        .hasMatch(path)) {
      return true;
    }
    // /c/<customUrl>
    if (RegExp(r'^/c/[^/]+(/videos|/playlists)?$').hasMatch(path)) {
      return true;
    }
    // /user/<username>
    if (RegExp(r'^/user/[^/]+(/videos|/playlists)?$').hasMatch(path)) {
      return true;
    }
    return false;
  }

  static bool _isGenericSeriesUrl(String path) {
    final patterns = [
      RegExp(r'/series/'),
      RegExp(r'/season-\d+'),
      RegExp(r'/s\d+e\d+'),      // s01e03 style
      RegExp(r'/episode-\d+'),
      RegExp(r'/eps-\d+'),
      RegExp(r'/episodes?/'),
      RegExp(r'/playlist/'),
    ];
    return patterns.any((p) => p.hasMatch(path));
  }
}
