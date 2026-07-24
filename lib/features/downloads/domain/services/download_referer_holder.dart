/// Bridge that carries an HTTP Referer from the browser's media-sniff panel
/// to the yt-dlp invocations, without threading an optional param through the
/// whole extraction/download call chain (same rationale as
/// `playlist_context_holder.dart`).
///
/// Some CDNs (e.g. znews.vn) reject HLS manifest/segment requests that lack
/// the article page as `Referer`. The panel stamps `manifest URL → page URL`
/// once before starting extraction; `YtDlpDataSource` peeks the map when it
/// builds BOTH the extract (`--dump-json`) and download command lines — yt-dlp
/// runs twice and each run needs `--referer`.
///
/// Lookups are non-consuming: extract, download, and any retries all need the
/// same entry, and a stale entry is harmless (same site → same page referer).
/// The map is capped FIFO so it can't grow unbounded over a long session.
/// Downloads that were never stamped (Home tab, YouTube, playlists…) get no
/// referer — behaviour is unchanged for every existing path.
class SniffContext {
  /// Page URL sent as `--referer` on both yt-dlp runs.
  final String referer;

  /// Human page/video title from the sniff card. Raw-manifest extraction can
  /// only derive a junk title from the playlist filename ("master", "index"),
  /// so the known-good title is carried along and applied to the result.
  final String? pageTitle;

  const SniffContext({required this.referer, this.pageTitle});
}

class DownloadRefererHolder {
  DownloadRefererHolder._();

  static const int _maxEntries = 32;
  static final Map<String, SniffContext> _byUrl = {};

  /// Register the sniff context for [url].
  static void stamp(String url, String referer, {String? pageTitle}) {
    if (url.isEmpty || referer.isEmpty) return;
    // FIFO cap — Maps preserve insertion order.
    while (_byUrl.length >= _maxEntries) {
      _byUrl.remove(_byUrl.keys.first);
    }
    _byUrl[url] = SniffContext(referer: referer, pageTitle: pageTitle);
  }

  /// Referer for [url], or null when this download was never stamped.
  static String? lookup(String url) => _entryFor(url)?.referer;

  /// Stamped page title for [url], or null.
  static String? lookupTitle(String url) => _entryFor(url)?.pageTitle;

  /// Falls back to a host+path match so URL normalisation (stripped query /
  /// fragment) between stamp- and lookup-time doesn't lose the entry.
  static SniffContext? _entryFor(String url) {
    final exact = _byUrl[url];
    if (exact != null) return exact;

    final target = Uri.tryParse(url);
    if (target == null || target.host.isEmpty) return null;
    for (final entry in _byUrl.entries) {
      final candidate = Uri.tryParse(entry.key);
      if (candidate != null &&
          candidate.host == target.host &&
          candidate.path == target.path) {
        return entry.value;
      }
    }
    return null;
  }
}
