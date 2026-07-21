import '../../../../core/database/app_database.dart';
import '../../domain/entities/download_status.dart';
import 'package:drift/drift.dart';

/// Local data source for download persistence using Drift
class DownloadLocalDataSource {
  final AppDatabase _database;

  DownloadLocalDataSource(this._database);

  /// Execute multiple database operations in a transaction
  /// Ensures ACID guarantees - either all operations succeed or all fail
  Future<T> transaction<T>(Future<T> Function() action) async {
    return await _database.transaction(() async => await action());
  }

  /// Get all downloads
  Future<List<Download>> getAllDownloads() async {
    return await _database.getAllDownloads();
  }

  /// Get downloads by status
  Future<List<Download>> getDownloadsByStatus(DownloadStatus status) async {
    return await _database.getDownloadsByStatus(status.toDbString());
  }

  /// Get downloads matching any of the given statuses
  Future<List<Download>> getDownloadsByStatuses(
    List<DownloadStatus> statuses,
  ) async {
    final statusStrings = statuses.map((s) => s.toDbString()).toList();
    return (_database.select(_database.downloads)
      ..where((t) => t.status.isIn(statusStrings))).get();
  }

  /// Get active downloads
  Future<List<Download>> getActiveDownloads() async {
    return await _database.getActiveDownloads();
  }

  /// Get download by ID
  Future<Download?> getDownloadById(int id) async {
    return await _database.getDownloadById(id);
  }

  /// Get download by URL
  Future<Download?> getDownloadByUrl(String url) async {
    return await _database.getDownloadByUrl(url);
  }

  /// Insert a new download
  Future<int> insertDownload({
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
    String sourceUrl = '',
  }) async {
    return await _database.insertDownload(
      DownloadsCompanion.insert(
        url: url,
        filename: filename,
        savePath: savePath,
        status: DownloadStatus.pending.toDbString(),
        thumbnail: Value(thumbnail),
        platform: Value(platform ?? 'unknown'),
        downloadMethod: Value(downloadMethod ?? 'unknown'),
        title: Value(title),
        uploader: Value(uploader),
        duration: Value(duration),
        viewCount: Value(viewCount),
        uploadDate: Value(uploadDate),
        qualityLabel: Value(qualityLabel),
        chaptersJson: Value(chaptersJson),
        sourceUrl: Value(sourceUrl),
      ),
    );
  }

  /// Update the download URL (used for CDN URL refresh on 403/410 errors).
  Future<void> updateUrl(int id, String newUrl) async {
    await _database.updateUrl(id, newUrl);
  }

  /// Update is_watched flag
  Future<void> updateIsWatched(int id, {required bool isWatched}) async {
    await _database.updateIsWatched(id, isWatched: isWatched);
  }

  /// Update scheduled start time (null clears the schedule)
  Future<void> updateScheduledAt(int id, DateTime? scheduledAt) async {
    await _database.updateScheduledAt(id, scheduledAt);
  }

  /// Update recurrence rule JSON (null clears the recurrence)
  Future<void> updateRecurrenceRuleJson(int id, String? json) async {
    await _database.updateRecurrenceRuleJson(id, json);
  }

  /// Update playlist context (id + title + index). Pass null to clear
  /// — used when the user removes a download from a user-curated
  /// collection or detaches a source-grouped video.
  Future<void> updatePlaylistContext(
    int id, {
    String? playlistId,
    String? playlistTitle,
    int? playlistIndex,
  }) async {
    await _database.updatePlaylistContext(
      id,
      playlistId: playlistId,
      playlistTitle: playlistTitle,
      playlistIndex: playlistIndex,
    );
  }

  /// User playlist summaries (v20+ C-lite) — backed by `user_playlists`
  /// table with member counts joined from `user_playlist_items`.
  Future<List<({String playlistId, String title, int count})>>
  getUserPlaylistSummaries() => _database.getUserPlaylistSummaries();

  /// Membership tuples (downloadId, playlistId, playlistTitle, position)
  /// ordered for FilterTab.playlist consumption.
  Future<
    List<
      ({int downloadId, String playlistId, String playlistTitle, int position})
    >
  >
  getUserPlaylistMemberships() => _database.getUserPlaylistMemberships();

  /// Insert or update a user playlist row (idempotent on id).
  Future<void> upsertUserPlaylist({
    required String id,
    required String title,
  }) => _database.upsertUserPlaylist(id: id, title: title);

  /// Rename a user playlist without touching memberships.
  Future<int> renameUserPlaylist({
    required String playlistId,
    required String title,
  }) => _database.renameUserPlaylist(playlistId: playlistId, title: title);

  /// Delete a user playlist. Membership rows cascade via FK.
  Future<int> deleteUserPlaylist(String playlistId) =>
      _database.deleteUserPlaylist(playlistId);

  /// Append [downloadIds] to [playlistId]; reuses existing positions.
  Future<void> addDownloadsToUserPlaylist({
    required String playlistId,
    required List<int> downloadIds,
  }) => _database.addDownloadsToUserPlaylist(
    playlistId: playlistId,
    downloadIds: downloadIds,
  );

  /// Remove a single membership. Idempotent.
  Future<int> removeDownloadFromUserPlaylist({
    required String playlistId,
    required int downloadId,
  }) => _database.removeDownloadFromUserPlaylist(
    playlistId: playlistId,
    downloadId: downloadId,
  );

  /// Rewrite user playlist item order.
  Future<void> reorderUserPlaylist({
    required String playlistId,
    required List<int> orderedDownloadIds,
  }) => _database.reorderUserPlaylist(
    playlistId: playlistId,
    orderedDownloadIds: orderedDownloadIds,
  );

  /// Playlists a download belongs to (for context-menu state).
  Future<List<({String playlistId, String title})>> getPlaylistsForDownload(
    int downloadId,
  ) => _database.getPlaylistsForDownload(downloadId);

  /// Stream that emits whenever user_playlist_items changes — used by
  /// the FilterTab.playlist provider to repaint memberships live.
  Stream<void> watchUserPlaylistChanges() =>
      _database.watchUserPlaylistChanges();

  /// Batch-update queue positions for D&D reorder
  Future<void> updateQueuePositions(List<int> orderedIds) async {
    await _database.updateQueuePositions(orderedIds);
  }

  /// Update the manual priority column for a single download.
  Future<void> updatePriority(int id, int priority) async {
    await (_database.update(_database.downloads)..where(
      (t) => t.id.equals(id),
    )).write(DownloadsCompanion(priority: Value(priority)));
  }

  /// Update download status
  Future<void> updateDownloadStatus(
    int id,
    DownloadStatus status, {
    String? errorMessage,
  }) async {
    await _database.updateDownloadStatus(
      id,
      status.toDbString(),
      errorMessage: errorMessage,
    );
  }

  /// Update download progress
  Future<void> updateDownloadProgress({
    required int id,
    required int downloadedBytes,
    required int speed,
  }) async {
    await _database.updateDownloadProgress(
      id: id,
      downloadedBytes: downloadedBytes,
      speed: speed,
    );
  }

  /// Update total bytes (when we get the file size from server)
  Future<void> updateTotalBytes(int id, int totalBytes) async {
    await (_database.update(_database.downloads)
      ..where((t) => t.id.equals(id))).write(
      DownloadsCompanion(
        totalBytes: Value(totalBytes),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Delete a download
  Future<int> deleteDownload(int id) async {
    return await _database.deleteDownload(id);
  }

  /// Delete completed downloads
  Future<int> deleteCompletedDownloads() async {
    return await _database.deleteCompletedDownloads();
  }

  /// Delete failed downloads
  Future<int> deleteFailedDownloads() async {
    return await _database.deleteFailedDownloads();
  }

  /// Delete all downloads
  Future<int> deleteAllDownloads() async {
    return await _database.deleteAllDownloads();
  }

  /// Increment retry count
  Future<void> incrementRetryCount(int id) async {
    await _database.incrementRetryCount(id);
  }

  /// Reset retry count after an explicit user retry.
  Future<void> resetRetryCount(int id) async {
    await _database.resetRetryCount(id);
  }

  /// Save user note on a download
  Future<void> saveUserNote(int id, String note) async {
    await _database.saveUserNote(id, note);
  }

  /// Update the temp dir path (for yt-dlp resume after app restart).
  Future<void> updateTempDirPath(int id, String? tempDirPath) async {
    await _database.updateTempDirPath(id, tempDirPath);
  }

  /// Update the save path (used after sorting rules move a file).
  Future<void> updateSavePath(int id, String newSavePath) async {
    await (_database.update(_database.downloads)..where(
      (t) => t.id.equals(id),
    )).write(DownloadsCompanion(savePath: Value(newSavePath)));
  }

  /// Atomically update both savePath (directory) and filename after a
  /// file move/rename. Single DB write avoids a window where savePath
  /// points to the new directory but filename still holds the old name.
  Future<void> updateLocation(
    int id, {
    required String savePath,
    required String filename,
  }) async {
    await (_database.update(_database.downloads)
      ..where((t) => t.id.equals(id))).write(
      DownloadsCompanion(
        savePath: Value(savePath),
        filename: Value(filename),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Watch download by ID
  Stream<Download?> watchDownload(int id) {
    return (_database.select(_database.downloads)
      ..where((t) => t.id.equals(id))).watchSingleOrNull();
  }

  /// Watch all downloads (queuePosition ASC NULLS LAST, then createdAt DESC)
  Stream<List<Download>> watchAllDownloads() {
    return (_database.select(_database.downloads)..orderBy([
      (t) => OrderingTerm(
        expression: t.queuePosition,
        mode: OrderingMode.asc,
        nulls: NullsOrder.last,
      ),
      (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
    ])).watch();
  }

  // ==================== TRANSACTIONAL OPERATIONS ====================

  /// Update download progress and total bytes atomically
  /// Ensures both updates succeed or fail together
  /// Only updates totalBytes if it has changed (optimization)
  Future<void> updateDownloadProgressWithTotal({
    required int id,
    required int downloadedBytes,
    required int totalBytes,
    required int speed,
  }) async {
    await transaction(() async {
      // Check if total bytes changed
      final download = await getDownloadById(id);
      if (download != null &&
          download.totalBytes != totalBytes &&
          totalBytes > 0) {
        await updateTotalBytes(id, totalBytes);
      }

      await updateDownloadProgress(
        id: id,
        downloadedBytes: downloadedBytes,
        speed: speed,
      );
    });
  }

  /// Complete download atomically - update status and final progress
  /// Ensures consistent state if any step fails
  Future<void> completeDownload({
    required int id,
    required int totalBytes,
    required int downloadedBytes,
    String? filename,
  }) async {
    await transaction(() async {
      await updateDownloadStatus(id, DownloadStatus.completed);
      await updateDownloadProgress(
        id: id,
        downloadedBytes: downloadedBytes,
        speed: 0,
      );
      if (totalBytes > 0) {
        await updateTotalBytes(id, totalBytes);
      }
      if (filename != null) {
        await _database.updateFilename(id, filename);
      }
    });
  }

  /// Fail download atomically - update status and set error message
  /// Ensures error state is consistent
  Future<void> failDownload({
    required int id,
    required String errorMessage,
  }) async {
    await transaction(() async {
      await updateDownloadStatus(
        id,
        DownloadStatus.failed,
        errorMessage: errorMessage,
      );
    });
  }
}
