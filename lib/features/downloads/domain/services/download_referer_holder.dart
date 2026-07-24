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
class DownloadRefererHolder {
  DownloadRefererHolder._();

  static const int _maxEntries = 32;
  static final Map<String, String> _byUrl = {};

  /// Register [referer] for [url] (and its yt-dlp-cleaned variant, which the
  /// datasource may use as the lookup key).
  static void stamp(String url, String referer) {
    if (url.isEmpty || referer.isEmpty) return;
    // FIFO cap — Maps preserve insertion order.
    while (_byUrl.length >= _maxEntries) {
      _byUrl.remove(_byUrl.keys.first);
    }
    _byUrl[url] = referer;
  }

  /// Referer for [url], or null when this download was never stamped.
  /// Falls back to a host+path match so URL normalisation (stripped query /
  /// fragment) between stamp- and lookup-time doesn't lose the entry.
  static String? lookup(String url) {
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
