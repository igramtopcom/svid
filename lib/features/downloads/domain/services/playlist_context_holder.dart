/// Bridge service that propagates playlist context from
/// [HomeBatchDownloadMixin.handleBatchDownload] (where the user
/// picks videos from a `YouTubePlaylistSheet`) to
/// [DownloadRepositoryImpl.createDownload] (where the download
/// record is materialised).
///
/// The alternative — threading 3 optional named params through 5
/// layers (mixin → batch decision → start-with-quality → use case →
/// repository → datasource) — adds pure-noise plumbing across half
/// the download module. The holder collapses that to a single
/// stamp/consume pair: handleBatchDownload stamps URL→context once
/// before extraction, the repository consumes by URL right after
/// the row is inserted, and tagged downloads light up the
/// `FilterTab.playlist` + `GroupedItem` paths in the UI without
/// further ceremony.
///
/// Single per-app instance via [playlistContextHolderProvider]. The
/// holder is map-backed and intentionally unsynchronised: stamps +
/// consumes happen on the UI isolate within the same micro-task
/// frame as the createDownload call, so concurrent batches that
/// could theoretically race share a URL key are bounded by
/// `pendingUrls.toSet()` dedup before stamping.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Captured playlist context for a single video URL.
class PlaylistContextEntry {
  /// Stable id — convention: `yt_<youtube_list_id>` for source-derived,
  /// `user_<uuid>` for user-curated collections.
  final String playlistId;

  /// Human-readable title shown in the popover row label + grouped
  /// header. Null when extraction couldn't fetch (e.g. private
  /// playlist URL).
  final String? playlistTitle;

  /// Position within the playlist (0-based). Drives the sort order
  /// inside [GroupedItem] so a 50-song playlist plays back in the
  /// same order the user picked.
  final int playlistIndex;

  const PlaylistContextEntry({
    required this.playlistId,
    required this.playlistTitle,
    required this.playlistIndex,
  });
}

class PlaylistContextHolder {
  PlaylistContextHolder();

  final Map<String, PlaylistContextEntry> _byUrl = {};

  /// Stamp [urls] in order with a shared [playlistId] / [playlistTitle].
  /// Each URL gets its 0-based [PlaylistContextEntry.playlistIndex] so
  /// the eventual UI groups preserve the playlist's track order.
  void stampBatch(
    List<String> urls, {
    required String playlistId,
    String? playlistTitle,
  }) {
    for (var i = 0; i < urls.length; i++) {
      _byUrl[urls[i]] = PlaylistContextEntry(
        playlistId: playlistId,
        playlistTitle: playlistTitle,
        playlistIndex: i,
      );
    }
  }

  /// Read + remove the entry for [url]. Idempotent — re-consuming
  /// after success returns null. Repository calls this exactly once
  /// per createDownload.
  PlaylistContextEntry? consume(String url) => _byUrl.remove(url);

  /// Drop entries for the given URLs. Used when a batch aborts
  /// (premium gate, no-pending-urls) and the stamps would otherwise
  /// linger and mis-tag a future ad-hoc download of the same URL.
  void clearForUrls(List<String> urls) {
    for (final url in urls) {
      _byUrl.remove(url);
    }
  }

  /// Diagnostic — surface size for telemetry / debug logs.
  int get pendingCount => _byUrl.length;
}

/// Provider — single instance per [ProviderContainer]. Repository +
/// home batch mixin both read this; both run on the UI isolate so no
/// concurrent map-mutation surface.
final playlistContextHolderProvider = Provider<PlaylistContextHolder>(
  (_) => PlaylistContextHolder(),
);
