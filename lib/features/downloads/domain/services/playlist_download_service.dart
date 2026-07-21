import '../entities/download_entity.dart';
import '../entities/download_status.dart';

// ---------------------------------------------------------------------------
// PlaylistSession
// ---------------------------------------------------------------------------

enum PlaylistSessionPhase { extracting, selecting, queueing, finished }

/// Tracks the state of an in-progress playlist / batch download.
///
/// Stored in [DownloadsState.activePlaylist].  Non-null only while a
/// multi-URL batch is being processed.
class PlaylistSession {
  final String id;
  final int total;
  final int completed;
  final int failed;
  final int skipped;
  final PlaylistSessionPhase phase;

  /// False after [endPlaylistSession] is called (batch has finished).
  final bool isActive;

  const PlaylistSession({
    required this.id,
    required this.total,
    this.completed = 0,
    this.failed = 0,
    this.skipped = 0,
    this.phase = PlaylistSessionPhase.extracting,
    this.isActive = true,
  });

  /// Items counted toward final progress (completed + failed + skipped).
  int get processed => completed + failed + skipped;

  /// Progress fraction in the range [0.0, 1.0].
  double get progress => total > 0 ? (processed / total).clamp(0.0, 1.0) : 0.0;

  PlaylistSession copyWith({
    int? total,
    int? completed,
    int? failed,
    int? skipped,
    PlaylistSessionPhase? phase,
    bool? isActive,
  }) {
    return PlaylistSession(
      id: id,
      total: total ?? this.total,
      completed: completed ?? this.completed,
      failed: failed ?? this.failed,
      skipped: skipped ?? this.skipped,
      phase: phase ?? this.phase,
      isActive: isActive ?? this.isActive,
    );
  }
}

// ---------------------------------------------------------------------------
// PlaylistDownloadService
// ---------------------------------------------------------------------------

/// Pure-Dart service for large playlist / channel downloads.
///
/// Responsibilities:
/// - **Resume support**: filter already-completed URLs so restarts skip them.
/// - **Batch splitting**: split URL lists into rate-limit-safe sub-batches.
///
/// Stateless and `const`-constructible — safe to keep as a `static const`.
class PlaylistDownloadService {
  const PlaylistDownloadService();

  // -------------------------------------------------------------------------
  // URL detection
  // -------------------------------------------------------------------------

  /// Returns `true` for YouTube playlist URLs (contain the `list=` query param).
  bool isPlaylistUrl(String url) {
    try {
      final uri = Uri.parse(url.trim());
      return (uri.host.contains('youtube.com') ||
              uri.host.contains('youtu.be')) &&
          uri.queryParameters.containsKey('list');
    } catch (_) {
      return false;
    }
  }

  /// Returns `true` for YouTube channel / user URLs.
  bool isChannelUrl(String url) {
    try {
      final uri = Uri.parse(url.trim());
      if (!uri.host.contains('youtube.com')) return false;
      final path = uri.path;
      return path.startsWith('/@') ||
          path.startsWith('/channel/') ||
          path.startsWith('/c/') ||
          path.startsWith('/user/');
    } catch (_) {
      return false;
    }
  }

  /// Returns `true` if the URL needs playlist-aware handling.
  bool isPlaylistOrChannelUrl(String url) =>
      isPlaylistUrl(url) || isChannelUrl(url);

  // -------------------------------------------------------------------------
  // Resume support
  // -------------------------------------------------------------------------

  /// Returns the subset of [urls] that have **not** been successfully
  /// downloaded yet.
  ///
  /// A URL is considered done when there is a matching [DownloadEntity] in
  /// [completedDownloads] (`status == completed`) after URL normalisation.
  List<String> filterPendingUrls(
    List<String> urls,
    List<DownloadEntity> completedDownloads,
  ) {
    final completedNormalised =
        completedDownloads
            .where((d) => d.status == DownloadStatus.completed)
            .map((d) => _normaliseUrl(d.url))
            .toSet();

    return urls
        .where((url) => !completedNormalised.contains(_normaliseUrl(url)))
        .toList();
  }

  /// Returns `true` if [url] already has a completed download in
  /// [completedDownloads].
  bool isAlreadyDownloaded(
    String url,
    List<DownloadEntity> completedDownloads,
  ) {
    final normalised = _normaliseUrl(url);
    return completedDownloads.any(
      (d) =>
          d.status == DownloadStatus.completed &&
          _normaliseUrl(d.url) == normalised,
    );
  }

  // -------------------------------------------------------------------------
  // Batch splitting
  // -------------------------------------------------------------------------

  /// Splits [urls] into sub-lists of at most [batchSize] entries.
  ///
  /// Defaults to 2 — the safe concurrency ceiling for YouTube as per the
  /// Phase 73 lessons in CLAUDE.md (>2 triggers bot-detection / throttling).
  List<List<String>> splitIntoBatches(List<String> urls, {int batchSize = 2}) {
    assert(batchSize > 0, 'batchSize must be a positive integer');
    if (urls.isEmpty) return [];

    final batches = <List<String>>[];
    for (int i = 0; i < urls.length; i += batchSize) {
      final end = (i + batchSize).clamp(0, urls.length);
      batches.add(urls.sublist(i, end));
    }
    return batches;
  }

  // -------------------------------------------------------------------------
  // URL normalisation (package-private for tests)
  // -------------------------------------------------------------------------

  /// Strips session-specific and tracking query parameters so that the same
  /// video appearing under slightly different URLs is treated identically.
  static String normaliseUrlForTest(String url) => _normaliseUrl(url);

  static String _normaliseUrl(String url) {
    try {
      final uri = Uri.parse(url.trim());
      // YouTube: canonical form keeps only the `v` parameter.
      if (uri.host.contains('youtube.com') || uri.host.contains('youtu.be')) {
        final v = uri.queryParameters['v'];
        if (v != null) {
          return 'https://www.youtube.com/watch?v=$v';
        }
      }
      // All other platforms: strip common tracking parameters.
      final stripped = uri.replace(
        queryParameters: Map.fromEntries(
          uri.queryParameters.entries.where(
            (e) => !_kTrackingParams.contains(e.key.toLowerCase()),
          ),
        ),
        fragment: '',
      );
      return stripped.toString().toLowerCase();
    } catch (_) {
      return url.toLowerCase().trim();
    }
  }

  static const _kTrackingParams = {
    'si',
    'pp',
    'feature',
    'utm_source',
    'utm_medium',
    'utm_campaign',
    'utm_content',
    'utm_term',
    'ref',
    'source',
    'fbclid',
    'igshid',
  };
}
