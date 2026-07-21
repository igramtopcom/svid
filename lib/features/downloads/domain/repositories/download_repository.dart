import '../../../../core/errors/result.dart';
import '../entities/download_entity.dart';
import '../entities/download_status.dart';
import '../entities/user_playlist_membership.dart';
import '../entities/user_playlist_summary.dart';

/// Repository interface for download operations
abstract class DownloadRepository {
  /// Get all downloads
  Future<Result<List<DownloadEntity>>> getAllDownloads();

  /// Get downloads by status
  Future<Result<List<DownloadEntity>>> getDownloadsByStatus(
    DownloadStatus status,
  );

  /// Get active downloads (downloading or pending)
  Future<Result<List<DownloadEntity>>> getActiveDownloads();

  /// Get a download by ID
  Future<Result<DownloadEntity>> getDownloadById(int id);

  /// Get a download by URL
  Future<Result<DownloadEntity?>> getDownloadByUrl(String url);

  /// Create a new download
  Future<Result<DownloadEntity>> createDownload({
    required String url,
    required String filename,
    required String savePath,
    String? thumbnail,
    String? platform,
    String? downloadMethod,
    // Rich metadata
    String? title,
    String? uploader,
    int? duration,
    int? viewCount,
    String? uploadDate,
    String? qualityLabel,
    String? chaptersJson,
    String sourceUrl,
  });

  /// Update the download URL (used for CDN URL refresh on 403/410 errors).
  Future<Result<void>> updateUrl(int id, String newUrl);

  /// Update playlist context (source-grouped via [PlaylistContextHolder]
  /// or user-curated via "Add to playlist" UI). Pass null fields to
  /// clear the tag — used when removing a download from its collection.
  Future<Result<void>> updatePlaylistContext(
    int id, {
    String? playlistId,
    String? playlistTitle,
    int? playlistIndex,
  });

  /// List user-curated playlists (v20 C-lite — backed by the
  /// `user_playlists` + `user_playlist_items` tables). Most-recently-
  /// touched first. Empty playlists ARE returned (unlike the v0 derived
  /// model where playlists existed only as long as they had members).
  Future<Result<List<UserPlaylistSummary>>> getUserPlaylists();

  /// All membership rows ordered for `FilterTab.playlist` rendering.
  /// Lightweight tuples — caller hydrates `Download` from the in-memory
  /// list cached by `downloadsNotifierProvider`.
  Future<Result<List<UserPlaylistMembership>>> getUserPlaylistMemberships();

  /// Live stream that ticks whenever user_playlist_items changes —
  /// drives reactive updates of the playlist tab without polling.
  Stream<void> watchUserPlaylistChanges();

  /// Add [downloadIds] to a user playlist. If [playlistId] is null a
  /// new `user_<uuid>` is minted from [newPlaylistTitle] (which must
  /// be non-empty). Re-adding an existing membership is a no-op.
  /// Source `yt_*` tags on `downloads.playlistId` are NOT touched —
  /// a download can simultaneously belong to its source playlist and
  /// any number of user playlists.
  ///
  /// Returns the destination playlist's id and display title so
  /// callers can show a confirmation toast.
  Future<Result<({String playlistId, String title})>> addToUserPlaylist({
    required List<int> downloadIds,
    String? playlistId,
    String? newPlaylistTitle,
  });

  /// Create an empty user-curated playlist. Empty playlists are
  /// first-class library folders and can receive items later.
  Future<Result<({String playlistId, String title})>> createUserPlaylist(
    String title,
  );

  /// Rename a user-curated playlist. Source playlists (`yt_*`) are
  /// derived from download metadata and must not be passed here.
  Future<Result<void>> renameUserPlaylist({
    required String playlistId,
    required String title,
  });

  /// Delete a user-curated playlist and its memberships. Downloads
  /// themselves are preserved.
  Future<Result<void>> deleteUserPlaylist(String playlistId);

  /// Remove a single membership. The playlist row itself is
  /// preserved even if it becomes empty.
  Future<Result<void>> removeFromUserPlaylist({
    required String playlistId,
    required int downloadId,
  });

  /// Rewrite membership positions in a user-curated playlist.
  Future<Result<void>> reorderUserPlaylist({
    required String playlistId,
    required List<int> orderedDownloadIds,
  });

  /// Playlists a download currently belongs to. Drives the
  /// "Remove from playlist" submenu when there's > 1 membership.
  Future<Result<List<({String playlistId, String title})>>>
  getPlaylistsForDownload(int downloadId);

  /// Start a download. [numSegments] controls multi-segment parallel download (1=single, 2-16=segmented).
  /// [maxSpeedBytes] optional per-download bandwidth cap in bytes/s (0 = unlimited).
  /// [proxyUrl] optional proxy URL routed to Rust HTTP engine (null = no proxy).
  /// [headersJson] optional JSON-encoded custom HTTP headers (IDM mode).
  /// [cookiesString] optional raw cookie string (IDM mode).
  Future<Result<void>> startDownload(
    int id, {
    int? numSegments,
    int? maxSpeedBytes,
    String? proxyUrl,
    String? headersJson,
    String? cookiesString,
  });

  /// Pause a download
  Future<Result<void>> pauseDownload(int id);

  /// Resume a download
  Future<Result<void>> resumeDownload(int id);

  /// Cancel a download
  Future<Result<void>> cancelDownload(int id);

  /// Retry a failed download.
  ///
  /// [retryPlan] carries the planner-derived yt-dlp args (mergeFormat,
  /// remuxVideo, recodeVideo, etc.) so the retry preserves the user's
  /// chosen container instead of letting yt-dlp pick a default. When
  /// null the retry falls back to bare-bones args (legacy behavior);
  /// callers SHOULD always supply a plan when the download is yt-dlp.
  /// See `RetryDownloadPlan` for field semantics.
  Future<Result<void>> retryDownload(
    int id, {
    RetryDownloadPlan? retryPlan,
    bool manualRetry = false,
  });

  /// Delete a download
  Future<Result<void>> deleteDownload(int id, {bool deleteFile = false});

  /// Delete all completed downloads
  Future<Result<int>> deleteCompletedDownloads({bool deleteFiles = false});

  /// Delete all failed downloads
  Future<Result<int>> deleteFailedDownloads({bool deleteFiles = false});

  /// Delete all downloads
  Future<Result<int>> deleteAllDownloads({bool deleteFiles = false});

  /// Watch download progress (stream of updates for a specific download)
  Stream<DownloadEntity> watchDownload(int id);

  /// Watch all downloads (stream of all downloads list)
  Stream<List<DownloadEntity>> watchAllDownloads();

  /// Update watch status for a download
  Future<Result<void>> updateIsWatched(int id, {required bool isWatched});

  /// Update scheduled start time (null clears the schedule)
  Future<Result<void>> updateScheduledAt(int id, DateTime? scheduledAt);

  /// Update recurrence rule JSON (null clears the recurrence)
  Future<Result<void>> updateRecurrenceRuleJson(int id, String? json);

  /// Update download status
  Future<Result<void>> updateDownloadStatus(
    int id,
    DownloadStatus status, {
    String? errorMessage,
  });

  /// Update download progress
  Future<Result<void>> updateDownloadProgress({
    required int id,
    required int downloadedBytes,
    required int totalBytes,
    required int speed,
  });

  /// Complete download atomically - update status and final progress
  /// Uses transaction to ensure consistency
  Future<Result<void>> completeDownload({
    required int id,
    required int totalBytes,
    required int downloadedBytes,
    String? filename,
  });

  /// Fail download atomically - update status with error message
  /// Uses transaction to ensure consistency
  Future<Result<void>> failDownload({
    required int id,
    required String errorMessage,
  });

  /// Save a user note on a download
  Future<Result<void>> saveUserNote(int id, String note);

  /// Update the save path of a download (used after sorting rules move a file).
  Future<Result<void>> updateSavePath(int id, String newSavePath);

  /// Atomically update both directory and filename after a file
  /// move/rename so [savePath] always holds a directory and [filename]
  /// always holds a basename.
  Future<Result<void>> updateLocation(
    int id, {
    required String savePath,
    required String filename,
  });

  /// Recover stale downloads on app startup.
  /// Resets downloading/pending/queued → pending (for re-queue),
  /// postProcessing → failed (FFmpeg state lost).
  /// Returns count of recovered downloads.
  Future<Result<int>> recoverDownloadsOnStartup();

  /// Batch-update queue positions after a D&D reorder.
  /// [orderedIds] is the new order of visible download IDs (position 0 = first).
  Future<Result<void>> updateQueuePositions(List<int> orderedIds);

  /// Update the manual priority for a single download.
  /// [priority] is the raw DB value: -1 = low, 0 = normal, 1 = high.
  Future<Result<void>> updatePriority(int id, int priority);

  /// Update the temp dir path for a download (for yt-dlp resume support).
  /// Set to null when download completes or is cancelled (temp dir cleaned up).
  Future<Result<void>> updateTempDirPath(int id, String? tempDirPath);
}

/// Args the planner produced for the original download, replayed on
/// retry so the new yt-dlp invocation honors the user's container
/// pick. None of these are persisted — they are re-computed at retry
/// time from current global settings + (optionally) a fresh extract.
///
/// Codex audit fix: previous retry path called yt-dlp with no format
/// args, so a failed AVI download would retry as MKV (yt-dlp default).
/// Threading the plan through retry closes that hole.
class RetryDownloadPlan {
  final String? format;
  final String? sortOptions;
  final String? videoFormat;
  final String? audioFormat;
  final int? audioBitrateKbps;
  final String? mergeFormatPriority;
  final String? remuxVideo;
  final String? recodeVideo;
  final bool extractAudio;
  final int? maxVideoHeight;
  final int? targetVideoHeight;

  /// Path to a Netscape-format cookies file (in-app captured login).
  /// Takes precedence over [cookiesFromBrowser]; when this is set the
  /// retry yt-dlp invocation does NOT also pass `--cookies-from-browser`
  /// — that combo can deadlock against a running Chrome on Windows
  /// (yt-dlp issue 7271 "Could not copy Chrome cookie database").
  /// Codex Blocker #3 from Ultra Plan v3.
  final String? cookiesFile;

  /// Browser name for `--cookies-from-browser` (chrome/firefox/edge/…).
  /// Used as the fallback when no [cookiesFile] is set, NOT in
  /// parallel with one — the caller must enforce precedence by
  /// nulling this field when [cookiesFile] is non-null.
  final String? cookiesFromBrowser;

  const RetryDownloadPlan({
    this.format,
    this.sortOptions,
    this.videoFormat,
    this.audioFormat,
    this.audioBitrateKbps,
    this.mergeFormatPriority,
    this.remuxVideo,
    this.recodeVideo,
    this.extractAudio = false,
    this.maxVideoHeight,
    this.targetVideoHeight,
    this.cookiesFile,
    this.cookiesFromBrowser,
  });
}
