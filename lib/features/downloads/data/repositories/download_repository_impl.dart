import 'dart:async';
import 'dart:io';
import 'dart:math' show pow, Random;
import 'package:path/path.dart' as p;

import '../../../../core/errors/result.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/services/user_agent_service.dart';
import '../../../../core/utils/file_utils.dart';
import '../../domain/entities/download_entity.dart';
import '../../domain/entities/download_error_code.dart';
import '../../domain/entities/download_status.dart';
import '../../domain/entities/user_playlist_membership.dart';
import '../../domain/entities/user_playlist_summary.dart';
import '../../domain/repositories/download_repository.dart';
import '../../domain/services/download_error_classifier.dart';
import '../../domain/services/file_integrity_service.dart';
import '../../domain/services/playlist_context_holder.dart';
import '../../domain/services/quality_resolution_parser.dart';
import '../../domain/usecases/start_download_usecase.dart'
    show StartDownloadUseCase;
import '../datasources/download_local_datasource.dart';
import '../datasources/download_native_datasource.dart';
import '../datasources/gallerydl_datasource.dart';
import '../datasources/ytdlp_datasource.dart';
import '../mappers/download_mapper.dart';

Future<T> _withTransientSqliteRetry<T>(
  String operation,
  Future<T> Function() action,
) async {
  const delays = [
    Duration(milliseconds: 150),
    Duration(milliseconds: 300),
    Duration(milliseconds: 600),
    Duration(milliseconds: 1000),
  ];

  for (var attempt = 0; attempt <= delays.length; attempt++) {
    try {
      return await action();
    } catch (error, stack) {
      final lastAttempt = attempt == delays.length;
      if (!_isTransientSqliteOpenOrLockError(error) || lastAttempt) {
        rethrow;
      }
      final delay = delays[attempt];
      appLogger.warning(
        'SQLite transient failure during $operation; retrying in '
        '${delay.inMilliseconds}ms (attempt ${attempt + 1}/${delays.length}). '
        'Error: $error',
        error,
        stack,
      );
      await Future<void>.delayed(delay);
    }
  }

  throw StateError('unreachable sqlite retry state');
}

bool _isTransientSqliteOpenOrLockError(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('sqliteexception(14)') ||
      message.contains('sqliteexception(5)') ||
      message.contains('sqliteexception(517)') ||
      message.contains('unable to open database file') ||
      message.contains('database is locked') ||
      message.contains('database table is locked');
}

/// Download repository implementation
/// NOTE: This repository manages database operations and queue management.
/// Actual download execution is handled by:
/// - yt-dlp: start_download_usecase.dart calls ytdlpDataSource directly
/// - gallery-dl: For image/carousel downloads (Instagram, etc.)
/// - Rust engine: For direct HTTP downloads (pause/resume/cancel support)
class DownloadRepositoryImpl implements DownloadRepository {
  static const int _maxRetryAttempts = 3;

  final DownloadLocalDataSource _localDataSource;
  final YtDlpDataSource? _ytdlpDataSource;
  final DownloadNativeDataSource? _nativeDataSource;
  final GalleryDlDataSource? _galleryDlDataSource;
  final UserAgentService _userAgentService;
  final PlaylistContextHolder? _playlistHolder;

  /// RC10 round-5 — injected for retry parity with the fresh download
  /// path. When non-null, `_retryYtdlpDownload` validates the output
  /// file at completion and fails the download on fatal integrity
  /// failure (e.g., the Facebook "no-audio video" symptom). Null in
  /// tests / legacy bootstraps keeps the retry path running without
  /// validation (matches pre-RC10 behavior).
  final FileIntegrityService? _fileIntegrityService;

  DownloadRepositoryImpl(
    this._localDataSource, [
    this._ytdlpDataSource,
    this._nativeDataSource,
    this._galleryDlDataSource,
    UserAgentService? userAgentService,
    this._playlistHolder,
    this._fileIntegrityService,
  ]) : _userAgentService = userAgentService ?? UserAgentService();

  @override
  Future<Result<List<DownloadEntity>>> getAllDownloads() async {
    return runCatching(() async {
      final downloads = await _localDataSource.getAllDownloads();
      return DownloadMapper.toDomainList(downloads);
    });
  }

  @override
  Future<Result<List<DownloadEntity>>> getDownloadsByStatus(
    DownloadStatus status,
  ) async {
    return runCatching(() async {
      final downloads = await _localDataSource.getDownloadsByStatus(status);
      return DownloadMapper.toDomainList(downloads);
    });
  }

  @override
  Future<Result<List<DownloadEntity>>> getActiveDownloads() async {
    return runCatching(() async {
      final downloads = await _localDataSource.getActiveDownloads();
      return DownloadMapper.toDomainList(downloads);
    });
  }

  @override
  Future<Result<DownloadEntity>> getDownloadById(int id) async {
    return runCatching(() async {
      final download = await _localDataSource.getDownloadById(id);
      if (download == null) {
        throw const AppException.download(message: 'Download not found');
      }
      return DownloadMapper.toDomain(download);
    });
  }

  @override
  Future<Result<DownloadEntity?>> getDownloadByUrl(String url) async {
    return runCatching(() async {
      final download = await _localDataSource.getDownloadByUrl(url);
      return download != null ? DownloadMapper.toDomain(download) : null;
    });
  }

  @override
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
    String sourceUrl = '',
  }) async {
    return runCatching(() async {
      // Ensure save directory exists and is writable
      try {
        await FileUtils.ensureDirectoryExists(savePath);
      } on FileSystemException catch (e) {
        throw AppException.permission(
          message: 'Cannot access download folder: ${e.message}',
          resource: savePath,
        );
      }

      if (!await FileUtils.canWriteToDirectory(savePath)) {
        throw AppException.permission(
          message: 'No write permission to download folder',
          resource: savePath,
        );
      }

      // Insert into database. A short retry handles transient Windows SQLite
      // open/lock races seen during forced-update sessions without hiding
      // persistent permission/corruption errors.
      final id = await _withTransientSqliteRetry(
        'insert download row',
        () => _localDataSource.insertDownload(
          url: url,
          filename: filename,
          savePath: savePath,
          thumbnail: thumbnail,
          platform: platform,
          downloadMethod: downloadMethod,
          title: title,
          uploader: uploader,
          duration: duration,
          viewCount: viewCount,
          uploadDate: uploadDate,
          qualityLabel: qualityLabel,
          chaptersJson: chaptersJson,
          sourceUrl: sourceUrl,
        ),
      );

      // Apply playlist context if a YouTubePlaylistSheet stamped this URL
      // upstream. Stamp is removed on consume, so re-creating the same URL
      // ad-hoc later won't inherit a stale tag.
      final playlistEntry = _playlistHolder?.consume(url);
      if (playlistEntry != null) {
        await _localDataSource.updatePlaylistContext(
          id,
          playlistId: playlistEntry.playlistId,
          playlistTitle: playlistEntry.playlistTitle,
          playlistIndex: playlistEntry.playlistIndex,
        );
      }

      // Get the created download
      final download = await _withTransientSqliteRetry(
        'read created download row',
        () => _localDataSource.getDownloadById(id),
      );
      if (download == null) {
        throw const AppException.download(message: 'Failed to create download');
      }

      appLogger.info(
        'Download created: $id - $filename (method: ${downloadMethod ?? 'unknown'})',
      );
      return DownloadMapper.toDomain(download);
    });
  }

  @override
  Future<Result<void>> updatePlaylistContext(
    int id, {
    String? playlistId,
    String? playlistTitle,
    int? playlistIndex,
  }) async {
    return runCatching(() async {
      await _localDataSource.updatePlaylistContext(
        id,
        playlistId: playlistId,
        playlistTitle: playlistTitle,
        playlistIndex: playlistIndex,
      );
    });
  }

  @override
  Future<Result<List<UserPlaylistSummary>>> getUserPlaylists() async {
    return runCatching(() async {
      final rows = await _localDataSource.getUserPlaylistSummaries();
      return rows
          .map(
            (r) => UserPlaylistSummary(
              playlistId: r.playlistId,
              title: r.title,
              count: r.count,
            ),
          )
          .toList(growable: false);
    });
  }

  @override
  Future<Result<List<UserPlaylistMembership>>>
  getUserPlaylistMemberships() async {
    return runCatching(() async {
      final rows = await _localDataSource.getUserPlaylistMemberships();
      return rows
          .map(
            (r) => UserPlaylistMembership(
              downloadId: r.downloadId,
              playlistId: r.playlistId,
              playlistTitle: r.playlistTitle,
              position: r.position,
            ),
          )
          .toList(growable: false);
    });
  }

  @override
  Stream<void> watchUserPlaylistChanges() =>
      _localDataSource.watchUserPlaylistChanges();

  @override
  Future<Result<({String playlistId, String title})>> addToUserPlaylist({
    required List<int> downloadIds,
    String? playlistId,
    String? newPlaylistTitle,
  }) async {
    return runCatching(() async {
      if (downloadIds.isEmpty) {
        throw const AppException.validation(
          message: 'addToUserPlaylist called with no downloadIds',
        );
      }

      // Resolve the destination playlist:
      //   - existing id → fetch its current title (so the toast +
      //     return contract carry the persisted name)
      //   - new playlist → mint user_<uuid>, upsert the row
      String resolvedId;
      String resolvedTitle;

      if (playlistId != null) {
        resolvedId = playlistId;
        // Look up title from the playlists list — small N (user has
        // a handful of playlists, not thousands) so a full scan is
        // fine; saves a dedicated single-row query path.
        final all = await _localDataSource.getUserPlaylistSummaries();
        final match = all.where((p) => p.playlistId == resolvedId).firstOrNull;
        if (match == null) {
          throw AppException.validation(
            message: 'Playlist $resolvedId no longer exists',
          );
        }
        resolvedTitle = match.title;
      } else {
        final title = newPlaylistTitle?.trim() ?? '';
        if (title.isEmpty) {
          throw const AppException.validation(
            message: 'New playlist requires a non-empty title',
          );
        }
        resolvedId = 'user_${_uuidV4()}';
        resolvedTitle = title;
        await _localDataSource.upsertUserPlaylist(
          id: resolvedId,
          title: resolvedTitle,
        );
      }

      await _localDataSource.addDownloadsToUserPlaylist(
        playlistId: resolvedId,
        downloadIds: downloadIds,
      );

      appLogger.info(
        '📝 [Playlist] Added ${downloadIds.length} downloads to '
        '$resolvedId ("$resolvedTitle")',
      );
      return (playlistId: resolvedId, title: resolvedTitle);
    });
  }

  @override
  Future<Result<({String playlistId, String title})>> createUserPlaylist(
    String title,
  ) async {
    return runCatching(() async {
      final trimmed = title.trim();
      if (trimmed.isEmpty) {
        throw const AppException.validation(
          message: 'Playlist title cannot be empty',
        );
      }

      final playlistId = 'user_${_uuidV4()}';
      await _localDataSource.upsertUserPlaylist(id: playlistId, title: trimmed);
      appLogger.info(
        '📝 [Playlist] Created empty user playlist $playlistId ("$trimmed")',
      );
      return (playlistId: playlistId, title: trimmed);
    });
  }

  @override
  Future<Result<void>> renameUserPlaylist({
    required String playlistId,
    required String title,
  }) async {
    return runCatching(() async {
      _validateUserPlaylistId(playlistId);
      final trimmed = title.trim();
      if (trimmed.isEmpty) {
        throw const AppException.validation(
          message: 'Playlist title cannot be empty',
        );
      }

      final updated = await _localDataSource.renameUserPlaylist(
        playlistId: playlistId,
        title: trimmed,
      );
      if (updated == 0) {
        throw AppException.validation(
          message: 'Playlist $playlistId no longer exists',
        );
      }
    });
  }

  @override
  Future<Result<void>> deleteUserPlaylist(String playlistId) async {
    return runCatching(() async {
      _validateUserPlaylistId(playlistId);
      await _localDataSource.deleteUserPlaylist(playlistId);
    });
  }

  @override
  Future<Result<void>> removeFromUserPlaylist({
    required String playlistId,
    required int downloadId,
  }) async {
    return runCatching(() async {
      _validateUserPlaylistId(playlistId);
      await _localDataSource.removeDownloadFromUserPlaylist(
        playlistId: playlistId,
        downloadId: downloadId,
      );
    });
  }

  @override
  Future<Result<void>> reorderUserPlaylist({
    required String playlistId,
    required List<int> orderedDownloadIds,
  }) async {
    return runCatching(() async {
      _validateUserPlaylistId(playlistId);
      if (orderedDownloadIds.isEmpty) return;
      await _localDataSource.reorderUserPlaylist(
        playlistId: playlistId,
        orderedDownloadIds: orderedDownloadIds,
      );
    });
  }

  @override
  Future<Result<List<({String playlistId, String title})>>>
  getPlaylistsForDownload(int downloadId) async {
    return runCatching(() async {
      return _localDataSource.getPlaylistsForDownload(downloadId);
    });
  }

  /// Lightweight v4 UUID generator — avoids dragging the `uuid`
  /// package into this layer when only one call site needs it.
  String _uuidV4() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3F) | 0x80; // variant 10
    String hex(int i) => bytes[i].toRadixString(16).padLeft(2, '0');
    return '${hex(0)}${hex(1)}${hex(2)}${hex(3)}-'
        '${hex(4)}${hex(5)}-'
        '${hex(6)}${hex(7)}-'
        '${hex(8)}${hex(9)}-'
        '${hex(10)}${hex(11)}${hex(12)}${hex(13)}${hex(14)}${hex(15)}';
  }

  void _validateUserPlaylistId(String playlistId) {
    if (!playlistId.startsWith('user_')) {
      throw AppException.validation(
        message: 'Expected user playlist id, got $playlistId',
      );
    }
  }

  @override
  Future<Result<void>> startDownload(
    int id, {
    int? numSegments,
    int? maxSpeedBytes,
    String? proxyUrl,
    String? headersJson,
    String? cookiesString,
  }) async {
    return runCatching(() async {
      final download = await _localDataSource.getDownloadById(id);
      if (download == null) {
        throw const AppException.download(message: 'Download not found');
      }

      // yt-dlp downloads are handled directly by start_download_usecase.dart
      if (download.downloadMethod == 'ytdlp') {
        appLogger.warning(
          '⚠️ Download $id uses yt-dlp but startDownload() was called.',
        );
        throw const AppException.download(
          message: 'yt-dlp downloads are handled by usecase, not repository',
        );
      }

      // Rust engine downloads
      if (download.downloadMethod == 'rust') {
        final nds = _nativeDataSource;
        if (nds == null) {
          throw const AppException.download(
            message: 'Rust download engine not available',
          );
        }

        final nativeId = DownloadNativeDataSource.generateNativeId(
          download.url,
          download.filename,
        );

        await _localDataSource.updateDownloadStatus(
          id,
          DownloadStatus.downloading,
        );

        // Pass downloadedBytes as resume offset for interrupted downloads
        final resumeOffset =
            download.downloadedBytes > 0 ? download.downloadedBytes : null;

        await nds.startDownload(
          nativeId: nativeId,
          url: download.url,
          outputPath: p.join(download.savePath, download.filename),
          resumeOffset: resumeOffset,
          maxSpeedBytes: maxSpeedBytes,
          numSegments: numSegments,
          userAgent: _userAgentService.getRandomUserAgent(),
          proxyUrl: proxyUrl,
          headersJson: headersJson,
          cookiesString: cookiesString,
        );

        appLogger.info(
          '🚀 Download $id started via Rust engine (uuid: $nativeId)'
          '${resumeOffset != null ? " (resuming from $resumeOffset bytes)" : ""}'
          '${numSegments != null && numSegments > 1 ? " (segments: $numSegments)" : ""}',
        );

        // Start background progress polling so the DB stays updated
        _pollNativeProgress(id, nativeId);
        return;
      }

      // Unsupported download method
      appLogger.error(
        '❌ Unsupported download method: ${download.downloadMethod}',
      );
      await _localDataSource.updateDownloadStatus(
        id,
        DownloadStatus.failed,
        errorMessage: 'Unsupported download method: ${download.downloadMethod}',
      );
      throw AppException.download(
        message: 'Unsupported download method: ${download.downloadMethod}',
      );
    });
  }

  /// Fire-and-forget background progress polling for Rust engine downloads.
  /// Updates the database with progress, and marks completed/failed/cancelled.
  void _pollNativeProgress(int downloadId, String nativeId) {
    final nds = _nativeDataSource;
    if (nds == null) return;

    () async {
      try {
        var lastWrite = DateTime(0);
        const throttleMs = 250;

        await for (final progress in nds.watchProgress(nativeId)) {
          if (progress.status == 'downloading') {
            final now = DateTime.now();
            if (now.difference(lastWrite).inMilliseconds >= throttleMs) {
              lastWrite = now;
              await _localDataSource.updateDownloadProgressWithTotal(
                id: downloadId,
                downloadedBytes: progress.downloadedBytes,
                totalBytes: progress.totalBytes,
                speed: 0,
              );
            }
          } else if (progress.status == 'completed') {
            // Verify file on disk before marking complete
            final download = await _localDataSource.getDownloadById(downloadId);
            if (download != null) {
              final outputPath = p.join(download.savePath, download.filename);
              final outputFile = File(outputPath);
              final fileExists = await outputFile.exists();
              final fileSize = fileExists ? await outputFile.length() : 0;

              if (!fileExists || fileSize == 0) {
                appLogger.error(
                  '❌ [Rust] Output file missing or empty: $outputPath',
                );
                await _localDataSource.failDownload(
                  id: downloadId,
                  errorMessage:
                      'Download completed but output file is missing or empty',
                );
                await nds.cleanupDownload(nativeId);
                return;
              }

              await _localDataSource.completeDownload(
                id: downloadId,
                totalBytes: fileSize,
                downloadedBytes: fileSize,
              );
            } else {
              await _localDataSource.completeDownload(
                id: downloadId,
                totalBytes: progress.totalBytes,
                downloadedBytes: progress.downloadedBytes,
              );
            }
            await nds.cleanupDownload(nativeId);
            appLogger.info('✅ Rust download $downloadId completed');
            return;
          } else if (progress.status == 'failed') {
            await _localDataSource.failDownload(
              id: downloadId,
              errorMessage: 'Download failed',
            );
            await nds.cleanupDownload(nativeId);
            return;
          } else if (progress.status == 'cancelled') {
            await _localDataSource.updateDownloadStatus(
              downloadId,
              DownloadStatus.cancelled,
            );
            await nds.cleanupDownload(nativeId);
            return;
          }
        }
      } catch (e) {
        appLogger.error(
          '❌ Progress poll error for Rust download $downloadId',
          e,
        );
        try {
          await _localDataSource.failDownload(
            id: downloadId,
            errorMessage: 'Progress monitoring failed: $e',
          );
        } catch (_) {}
      }
    }();
  }

  @override
  Future<Result<void>> pauseDownload(int id) async {
    return runCatching(() async {
      final download = await _localDataSource.getDownloadById(id);
      if (download == null) {
        throw const AppException.download(message: 'Download not found');
      }

      // Rust engine: native pause via atomic flag
      if (download.downloadMethod == 'rust' && _nativeDataSource != null) {
        final nativeId = DownloadNativeDataSource.generateNativeId(
          download.url,
          download.filename,
        );
        await _nativeDataSource.pauseDownload(nativeId);
        appLogger.info('⏸️ Download $id paused via Rust engine');
      }

      await _localDataSource.updateDownloadStatus(id, DownloadStatus.paused);
      appLogger.info('⏸️ Download $id paused');
    });
  }

  @override
  Future<Result<void>> resumeDownload(int id) async {
    return runCatching(() async {
      final download = await _localDataSource.getDownloadById(id);
      if (download == null) {
        throw const AppException.download(message: 'Download not found');
      }

      // Rust engine: native resume via atomic flag
      if (download.downloadMethod == 'rust' && _nativeDataSource != null) {
        final nativeId = DownloadNativeDataSource.generateNativeId(
          download.url,
          download.filename,
        );
        await _nativeDataSource.resumeDownload(nativeId);
        await _localDataSource.updateDownloadStatus(
          id,
          DownloadStatus.downloading,
        );
        appLogger.info('▶️ Download $id resumed via Rust engine');
        return;
      }

      // yt-dlp: set to queued — _processQueue will pick it up and pass
      // the persisted tempDirPath so --continue can resume from .part files.
      if (download.retryCount >= _maxRetryAttempts) {
        await _localDataSource.resetRetryCount(id);
        appLogger.info(
          '🔄 Resume reset retry budget for download $id '
          '(was ${download.retryCount}/$_maxRetryAttempts)',
        );
      }
      await _localDataSource.updateDownloadStatus(id, DownloadStatus.queued);
      appLogger.info(
        '▶️ Download $id resumed (queued for retry with resume support)',
      );
    });
  }

  @override
  Future<Result<void>> cancelDownload(int id) async {
    return runCatching(() async {
      final download = await _localDataSource.getDownloadById(id);

      if (download != null) {
        // RC10.3: merging/remuxing/converting all count as
        // "live process" — they're sub-phases of post-processing
        // where yt-dlp/ffmpeg is still running.
        final hasLiveProcess =
            download.status == DownloadStatus.downloading.name ||
            download.status == DownloadStatus.postProcessing.name ||
            download.status == DownloadStatus.merging.name ||
            download.status == DownloadStatus.remuxing.name ||
            download.status == DownloadStatus.converting.name ||
            download.status == DownloadStatus.paused.name;

        // Rust engine: native cancel + cleanup
        if (hasLiveProcess &&
            download.downloadMethod == 'rust' &&
            _nativeDataSource != null) {
          final nativeId = DownloadNativeDataSource.generateNativeId(
            download.url,
            download.filename,
          );
          await _nativeDataSource.cancelDownload(nativeId);
          await _nativeDataSource.cleanupDownload(nativeId);
          appLogger.info('❌ Download $id cancelled via Rust engine');
        }

        // yt-dlp: kill only this download's process (not all qualities)
        if (hasLiveProcess &&
            download.downloadMethod == 'ytdlp' &&
            _ytdlpDataSource != null) {
          await _ytdlpDataSource.cancelByDownloadId(id);
          appLogger.info('❌ Download $id cancelled (yt-dlp process killed)');
        }

        // gallery-dl: kill subprocess
        if (hasLiveProcess &&
            download.downloadMethod == 'gallerydl' &&
            _galleryDlDataSource != null) {
          await _galleryDlDataSource.cancelDownload(download.url);
          appLogger.info(
            '❌ Download $id cancelled (gallery-dl process killed)',
          );
        }
      }

      await _localDataSource.updateDownloadStatus(id, DownloadStatus.cancelled);
      appLogger.info('Download $id cancelled');
    });
  }

  @override
  Future<Result<void>> retryDownload(
    int id, {
    RetryDownloadPlan? retryPlan,
    bool manualRetry = false,
  }) async {
    return runCatching(() async {
      final download = await _localDataSource.getDownloadById(id);
      if (download == null) {
        throw const AppException.download(message: 'Download not found');
      }

      var retryCount = download.retryCount;
      if (retryCount >= _maxRetryAttempts && manualRetry) {
        await _localDataSource.resetRetryCount(id);
        retryCount = 0;
        appLogger.info(
          '🔄 Manual retry reset retry budget for download $id '
          '(was ${download.retryCount}/$_maxRetryAttempts)',
        );
      }

      if (retryCount >= _maxRetryAttempts) {
        appLogger.warning(
          'Download $id exceeded max retries ($_maxRetryAttempts)',
        );
        await _localDataSource.updateDownloadStatus(
          id,
          DownloadStatus.failed,
          errorMessage: 'Maximum retry attempts reached',
        );
        throw const AppException.download(
          message: 'Maximum retry attempts reached',
        );
      }

      // Exponential backoff: 2^attempt seconds + random jitter (0-1000ms)
      // Attempt 1: ~2s, Attempt 2: ~4s, Attempt 3: ~8s
      final baseDelay = pow(2, retryCount).toInt();
      final jitter = Random().nextInt(1000); // 0-999ms
      final delayMs = (baseDelay * 1000) + jitter;

      appLogger.info(
        '⏳ Retrying download $id in ${baseDelay}s '
        '(attempt ${retryCount + 1}/$_maxRetryAttempts)',
      );

      // Wait before retrying (exponential backoff)
      await Future.delayed(Duration(milliseconds: delayMs));

      // Increment retry count
      await _localDataSource.incrementRetryCount(id);

      // Start download again — route yt-dlp through its own path
      // Fire-and-forget: unblocks _processQueue() so queued downloads start
      // without waiting for previous retry to complete.
      if (download.downloadMethod == 'ytdlp') {
        if (retryPlan == null) {
          // Caller did not supply a plan. Log telemetry to surface the
          // silent-fallback hole; yt-dlp will pick its default container
          // which may not match what the user originally chose. New
          // callers MUST supply a plan per the pick-X-get-X contract.
          appLogger.warning(
            '⚠️ Retry $id without RetryDownloadPlan — container fidelity '
            'cannot be guaranteed (will fall back to yt-dlp defaults).',
          );
        }
        unawaited(
          _retryYtdlpDownload(
            id: id,
            url: download.url,
            savePath: download.savePath,
            filename: download.filename,
            existingTempDir: download.tempDirPath,
            retryPlan: retryPlan,
          ).catchError((e) {
            appLogger.error('yt-dlp retry monitoring failed: $e');
          }),
        );
      } else {
        await startDownload(id);
      }
    });
  }

  /// Re-launch a yt-dlp download for an existing entity.
  ///
  /// Unlike [startDownload] (which only handles Rust engine), this method
  /// starts a yt-dlp process and streams progress updates to the database.
  /// If [existingTempDir] is provided (from DB), yt-dlp --continue can
  /// resume from .part files left by a previous session.
  Future<void> _retryYtdlpDownload({
    required int id,
    required String url,
    required String savePath,
    required String filename,
    String? existingTempDir,
    RetryDownloadPlan? retryPlan,
  }) async {
    final ytdlp = _ytdlpDataSource;
    if (ytdlp == null) {
      throw const AppException.download(message: 'yt-dlp not available');
    }

    // DL-001 — save-folder guard. Stale-row retries (the user deleted or
    // moved the destination folder out from under a long-idle row) used to
    // run yt-dlp against a missing outputDir, producing a "complete" event
    // whose final file never landed → PathNotFoundException at the finalize
    // .length() below, surfaced as the opaque "yt-dlp retry monitoring
    // failed". Recreate the folder if it is safely re-creatable; otherwise
    // fail early with a clear filesystem error and no exception.
    try {
      await FileUtils.ensureDirectoryExists(savePath);
    } on FileSystemException catch (e) {
      appLogger.error(
        '❌ [DL-001 retry-folder] Save folder unavailable for retry #$id: '
        '${e.message} at $savePath',
      );
      await _localDataSource.updateDownloadStatus(
        id,
        DownloadStatus.failed,
        errorMessage:
            'Cannot save the download — the destination folder is missing '
            'and could not be recreated. Choose a new download folder and '
            'try again.',
      );
      return;
    }
    if (!await FileUtils.canWriteToDirectory(savePath)) {
      appLogger.error(
        '❌ [DL-001 retry-folder] Save folder not writable for retry #$id '
        'at $savePath',
      );
      await _localDataSource.updateDownloadStatus(
        id,
        DownloadStatus.failed,
        errorMessage:
            'Cannot save the download — no write permission to the '
            'destination folder. Choose a new download folder and try again.',
      );
      return;
    }

    await _localDataSource.updateDownloadStatus(id, DownloadStatus.downloading);

    int estimatedTotalBytes = 0;

    // RC10 round-5 retry parity — match the fresh-download path's
    // post-process discipline (status sub-states + dynamic FFmpeg
    // timeout + integrity validation). Without these, retry's stuck-
    // ffmpeg state hung forever, retry's UI stayed at "Downloading"
    // through the entire merge/remux phase, and a corrupt retry
    // output (e.g., Facebook no-audio) silently landed as Completed.
    //
    // Dynamic timeout uses the same resolver as the fresh path so
    // a 4K AVI recode gets a 45-minute budget while a simple MP4
    // remux keeps the 5-minute guard.
    final retryEntity = await _localDataSource.getDownloadById(id);
    final retrySelectedHeight = QualityResolutionParser.parseHeight(
      retryEntity?.qualityLabel ?? '',
    );
    final retryVideoDuration =
        (retryEntity?.duration != null && retryEntity!.duration! > 0)
            ? Duration(seconds: retryEntity.duration!)
            : null;
    final postProcessingTimeoutDuration =
        StartDownloadUseCase.resolvePostProcessingTimeout(
          recodeVideo: retryPlan?.recodeVideo,
          selectedHeight: retrySelectedHeight,
          videoDuration: retryVideoDuration,
          // Wave B (AUD-5) — retry mirror: audio extraction gets the
          // same duration-aware budget as the fresh path, otherwise
          // retries of long audio content die at the same 5m wall.
          extractAudio: retryPlan?.extractAudio ?? false,
        );
    Timer? postProcessingTimeout;
    bool postProcessingTimedOut = false;
    // RC10.9 Codex-round-6 catch #2 — fresh-download path passes
    // `requireAudioStream: !selectedQuality.isVideoOnly`. Retry has
    // no Quality object, so derive from the persisted qualityLabel
    // ("video only" substring is what the extractor stamps onto
    // video-only Quality.qualityText — see
    // extract_video_info_usecase.dart "$qualityLabel Video Only").
    // Without this, retrying a legitimately video-only download
    // fatally fails the integrity check on the (correctly) audio-
    // less output.
    final retryRequireAudioStream =
        !(retryEntity?.qualityLabel ?? '').toLowerCase().contains('video only');

    // Use %(ext)s so yt-dlp writes the correct extension for the actual format
    final outputTemplate = filename.replaceAll(RegExp(r'\.[^.]+$'), '.%(ext)s');

    await for (final event in ytdlp.downloadWithProgress(
      url: url,
      outputDir: savePath,
      downloadId: id,
      outputTemplate: outputTemplate,
      existingTempDir: existingTempDir,
      // Codex audit fix: thread the planner-derived args through
      // retry so the user's chosen container survives the failure
      // → retry round-trip. Null retryPlan = legacy path (yt-dlp
      // default container), with a warning emitted at the caller
      // site so the silent fallback is observable.
      format: retryPlan?.format,
      sortOptions: retryPlan?.sortOptions,
      videoFormat: retryPlan?.videoFormat,
      audioFormat: retryPlan?.audioFormat,
      audioBitrateKbps: retryPlan?.audioBitrateKbps,
      mergeFormatPriority: retryPlan?.mergeFormatPriority,
      remuxVideo: retryPlan?.remuxVideo,
      recodeVideo: retryPlan?.recodeVideo,
      extractAudio: retryPlan?.extractAudio ?? false,
      maxVideoHeight: retryPlan?.maxVideoHeight,
      targetVideoHeight: retryPlan?.targetVideoHeight,
      // Codex Blocker #3 — RC1 of Ultra Plan v3: retry must carry
      // the cookies the original download used, otherwise
      // private/age-gated/cookie-bound videos fail again on the
      // first retry attempt. The plan enforces file > browser
      // precedence so cookieDbLocked (Chrome SQLite) cannot
      // re-emerge through the retry path.
      cookiesFile: retryPlan?.cookiesFile,
      cookiesFromBrowser: retryPlan?.cookiesFromBrowser,
      onTempDirCreated: (tempDir) {
        // Persist temp dir path so next recovery can resume from .part files
        _localDataSource.updateTempDirPath(id, tempDir);
      },
    )) {
      switch (event) {
        case YtDlpProgressUpdate(:final progress):
          if (progress.totalBytes != null && progress.totalBytes! > 0) {
            estimatedTotalBytes = progress.totalBytes!;
          }
          final downloadedBytes =
              progress.downloadedBytes ??
              (estimatedTotalBytes > 0
                  ? (progress.percent * estimatedTotalBytes / 100).round()
                  : 0);
          await _localDataSource.updateDownloadProgressWithTotal(
            id: id,
            downloadedBytes: downloadedBytes,
            totalBytes: estimatedTotalBytes,
            speed: progress.speed?.round() ?? 0,
          );

          // RC10 round-5 retry parity — map post-process sub-states to
          // DownloadStatus so retry UX shows merging/remuxing/converting
          // instead of staying at "Downloading" through ffmpeg, AND start
          // the dynamic FFmpeg timeout on the first post-process event
          // so a stuck ffmpeg gets killed instead of hanging forever.
          if (progress.status == YtDlpDownloadStatus.postProcessing ||
              progress.status == YtDlpDownloadStatus.merging ||
              progress.status == YtDlpDownloadStatus.remuxing ||
              progress.status == YtDlpDownloadStatus.converting) {
            postProcessingTimeout ??= Timer(postProcessingTimeoutDuration, () {
              postProcessingTimedOut = true;
              appLogger.error(
                '⏰ [FFmpeg retry] Post-processing timeout '
                '— killing process for #$id',
              );
              ytdlp.cancelByDownloadId(id);
            });
            final ds = switch (progress.status) {
              YtDlpDownloadStatus.merging => DownloadStatus.merging,
              YtDlpDownloadStatus.remuxing => DownloadStatus.remuxing,
              YtDlpDownloadStatus.converting => DownloadStatus.converting,
              _ => DownloadStatus.postProcessing,
            };
            await _localDataSource.updateDownloadStatus(id, ds);
          }

        case YtDlpDownloadComplete(:final outputPath):
          postProcessingTimeout?.cancel();
          // RC10 round-5 retry parity — run the same integrity
          // validation the fresh-download path runs. A retry that
          // produces a video-with-no-audio file (Facebook DASH merge
          // symptom) previously landed as Completed; now it surfaces
          // as a failure so the user sees an actionable error. The
          // Facebook progressive-fallback recovery loop intentionally
          // stays in the fresh path — retry already IS a recovery
          // context, so a second auto-fallback inside it would be
          // hard to bound. Integrity-fail without fallback is the
          // pragmatic parity floor for this commit.
          // DL-001 — finalize guard. yt-dlp reported the retry complete, but
          // verify the final file is actually present before we call
          // .length() on it. A stale row whose output was moved/deleted
          // mid-flight previously threw PathNotFoundException here, which
          // bubbled up as the opaque "yt-dlp retry monitoring failed". Mark a
          // clear finalization failure instead — no exception, no monitor throw.
          final completedFile = File(outputPath);
          if (!await completedFile.exists()) {
            appLogger.error(
              '❌ [DL-001 retry-finalize] yt-dlp reported complete but the '
              'output file is missing at $outputPath for #$id — marking failed '
              '(no monitor throw).',
            );
            await _localDataSource.updateTempDirPath(id, null);
            await _localDataSource.updateDownloadStatus(
              id,
              DownloadStatus.failed,
              errorMessage:
                  'Download could not be finalized — the saved file is missing. '
                  'It may have been moved or deleted during the download. '
                  'Please try again.',
            );
            break;
          }
          final fileSize = await completedFile.length();
          final integrityResult = await _fileIntegrityService?.verifyFile(
            outputPath,
            requireAudioStream: retryRequireAudioStream,
          );
          if (integrityResult != null &&
              !integrityResult.isValid &&
              integrityResult.isFatal) {
            appLogger.error(
              '❌ [FileIntegrity retry] yt-dlp retry output failed FATAL '
              'integrity check: ${integrityResult.reason} '
              '(file: $fileSize bytes at $outputPath)',
            );
            // DL-012 (retry mirror): delete the orphan final-folder file so
            // a fatal retry does not leave a tiny/corrupt stub in Downloads
            // the user mistakes for success. Mirrors the fresh-path cleanup
            // in StartDownloadUseCase per [[feedback_mirror_path_diff_line_by_line]].
            try {
              final orphan = File(outputPath);
              if (await orphan.exists()) await orphan.delete();
            } catch (e) {
              appLogger.warning(
                '⚠️ [FileIntegrity retry] Could not delete orphan failed '
                'file ($e) at $outputPath',
              );
            }
            await _localDataSource.updateTempDirPath(id, null);
            await _localDataSource.updateDownloadStatus(
              id,
              DownloadStatus.failed,
              errorMessage:
                  integrityResult.reason ??
                  'Downloaded file failed integrity check',
            );
            break;
          }
          if (integrityResult != null && !integrityResult.isValid) {
            appLogger.warning(
              '⚠️ [FileIntegrity retry] yt-dlp retry output has integrity '
              'warning: ${integrityResult.reason} — completing anyway '
              '(file: $fileSize bytes)',
            );
          }

          // RC10 Q-round C3 — retry-path mirror of the final-extension
          // guard. The datasource pre-move guard catches most cases,
          // and the fresh-path use case guard catches the rest, but
          // retry must also stand on its own (mirror discipline per
          // [[feedback_mirror_path_diff_line_by_line]]). Expected ext
          // here comes from retryPlan.videoFormat (or audioFormat for
          // audio retries — retry plan carries audioFormat too).
          final retryExtMismatch = YtDlpDataSource.detectFinalExtensionMismatch(
            outputPath: outputPath,
            videoFormat: retryPlan?.videoFormat,
            audioFormat: retryPlan?.audioFormat,
            extractAudio: retryPlan?.extractAudio ?? false,
          );
          if (retryExtMismatch != null) {
            appLogger.error(
              '❌ [C3 retry-path guard] expected .${retryExtMismatch.expected} '
              'but got .${retryExtMismatch.actual} at $outputPath for #$id. '
              'Marking retry failed instead of completing wrong container.',
            );
            await _localDataSource.updateTempDirPath(id, null);
            await _localDataSource.updateDownloadStatus(
              id,
              DownloadStatus.failed,
              errorMessage:
                  'Container mismatch on retry — expected '
                  '.${retryExtMismatch.expected} but output is '
                  '.${retryExtMismatch.actual}.',
            );
            break;
          }

          final finalBytes = fileSize > 0 ? fileSize : estimatedTotalBytes;
          final actualFilename = p.basename(outputPath);
          // Clear temp dir path — files have been moved to final location
          await _localDataSource.updateTempDirPath(id, null);
          await _localDataSource.completeDownload(
            id: id,
            totalBytes: finalBytes,
            downloadedBytes: finalBytes,
            filename: actualFilename != filename ? actualFilename : null,
          );
          appLogger.info('✅ yt-dlp retry completed for #$id: $outputPath');

        case YtDlpDownloadError(:final error):
          postProcessingTimeout?.cancel();
          final errorCode = DownloadErrorClassifier.classifyMessage(
            error.message,
          );
          final storedMessage = '${errorCode.name}:${error.message}';
          // Keep temp dir path on failure — retry can resume from .part files
          await _localDataSource.updateDownloadStatus(
            id,
            DownloadStatus.failed,
            errorMessage: storedMessage,
          );
          if (postProcessingTimedOut) {
            appLogger.error(
              '❌ yt-dlp retry failed for #$id (post-process timeout): '
              '${error.message}',
            );
          } else {
            appLogger.error('❌ yt-dlp retry failed for #$id: ${error.message}');
          }

        case YtDlpDownloadCancelled():
          postProcessingTimeout?.cancel();
          await _localDataSource.updateTempDirPath(id, null);
          // RC10.9 Codex-round-6 catch #1 — when our own post-process
          // timeout fires it calls cancelByDownloadId(), which makes
          // the datasource emit YtDlpDownloadCancelled. Treating that
          // as a user cancel hides the timeout from the failure UX
          // and routes the row to `cancelled` instead of `failed`.
          // Fresh-download path classifies this as an FFmpeg timeout
          // failure (see start_download_usecase post-loop block);
          // mirror that here. Real user cancels (no timeout flag)
          // still mark cancelled.
          if (postProcessingTimedOut) {
            final timeoutLabel = _formatDurationForLog(
              postProcessingTimeoutDuration,
            );
            final targetFormat =
                retryPlan?.recodeVideo ?? retryPlan?.videoFormat ?? 'video';
            await _localDataSource.updateDownloadStatus(
              id,
              DownloadStatus.failed,
              errorMessage:
                  'ffmpegError:FFmpeg post-processing exceeded '
                  '$timeoutLabel while converting to '
                  '${targetFormat.toUpperCase()} (retry).',
            );
            appLogger.error(
              '❌ yt-dlp retry timed out for #$id (FFmpeg post-process '
              'exceeded $timeoutLabel)',
            );
          } else {
            await _localDataSource.updateDownloadStatus(
              id,
              DownloadStatus.cancelled,
            );
            appLogger.info('🚫 yt-dlp retry cancelled for #$id');
          }
      }
    }
    postProcessingTimeout?.cancel();
  }

  /// RC10.9 — local duration formatter mirroring the fresh path's
  /// `_formatDurationForLog` (kept private in StartDownloadUseCase).
  /// Duplicating one tiny helper is cheaper than exposing the use
  /// case's private logger formatting just to satisfy the retry path.
  String _formatDurationForLog(Duration d) {
    if (d.inMinutes >= 1) {
      final minutes = d.inMinutes;
      return minutes == 1 ? '1 minute' : '$minutes minutes';
    }
    return '${d.inSeconds}s';
  }

  @override
  Future<Result<void>> deleteDownload(int id, {bool deleteFile = false}) async {
    return runCatching(() async {
      final download = await _localDataSource.getDownloadById(id);
      if (download != null) {
        if (deleteFile) {
          final fullPath = p.join(download.savePath, download.filename);
          await FileUtils.deleteFile(fullPath);
          appLogger.info('Deleted file: $fullPath');
        }
        // Clean up temp dir if it exists (leftover from interrupted download)
        final tempDir = download.tempDirPath;
        if (tempDir != null && tempDir.isNotEmpty) {
          try {
            final dir = Directory(tempDir);
            if (await dir.exists()) {
              await dir.delete(recursive: true);
              appLogger.info('🧹 Cleaned up temp dir for #$id: $tempDir');
            }
          } catch (_) {}
        }
      }

      await _localDataSource.deleteDownload(id);
      appLogger.info('Download $id deleted');
    });
  }

  @override
  Future<Result<int>> deleteCompletedDownloads({
    bool deleteFiles = false,
  }) async {
    return runCatching(() async {
      if (deleteFiles) {
        final downloads = await _localDataSource.getDownloadsByStatus(
          DownloadStatus.completed,
        );
        for (final download in downloads) {
          final fullPath = p.join(download.savePath, download.filename);
          await FileUtils.deleteFile(fullPath);
        }
      }

      final count = await _localDataSource.deleteCompletedDownloads();
      appLogger.info('Deleted $count completed downloads');
      return count;
    });
  }

  @override
  Future<Result<int>> deleteFailedDownloads({bool deleteFiles = false}) async {
    return runCatching(() async {
      if (deleteFiles) {
        final downloads = await _localDataSource.getDownloadsByStatus(
          DownloadStatus.failed,
        );
        for (final download in downloads) {
          final fullPath = p.join(download.savePath, download.filename);
          await FileUtils.deleteFile(fullPath);
        }
      }

      final count = await _localDataSource.deleteFailedDownloads();
      appLogger.info('Deleted $count failed downloads');
      return count;
    });
  }

  @override
  Future<Result<int>> deleteAllDownloads({bool deleteFiles = false}) async {
    return runCatching(() async {
      if (deleteFiles) {
        final downloads = await _localDataSource.getAllDownloads();
        for (final download in downloads) {
          final fullPath = p.join(download.savePath, download.filename);
          await FileUtils.deleteFile(fullPath);
        }
      }

      final count = await _localDataSource.deleteAllDownloads();
      appLogger.info('Deleted all $count downloads');
      return count;
    });
  }

  @override
  Stream<DownloadEntity> watchDownload(int id) {
    return _localDataSource.watchDownload(id).map((download) {
      if (download == null) {
        throw const AppException.download(message: 'Download not found');
      }
      return DownloadMapper.toDomain(download);
    });
  }

  @override
  Stream<List<DownloadEntity>> watchAllDownloads() {
    return _localDataSource.watchAllDownloads().map((downloads) {
      return DownloadMapper.toDomainList(downloads);
    });
  }

  @override
  Future<Result<void>> updateIsWatched(
    int id, {
    required bool isWatched,
  }) async {
    return runCatching(() async {
      await _localDataSource.updateIsWatched(id, isWatched: isWatched);
    });
  }

  @override
  Future<Result<void>> updateScheduledAt(int id, DateTime? scheduledAt) async {
    return runCatching(() async {
      await _localDataSource.updateScheduledAt(id, scheduledAt);
    });
  }

  @override
  Future<Result<void>> updateRecurrenceRuleJson(int id, String? json) async {
    return runCatching(() async {
      await _localDataSource.updateRecurrenceRuleJson(id, json);
    });
  }

  @override
  Future<Result<void>> updateDownloadStatus(
    int id,
    DownloadStatus status, {
    String? errorMessage,
  }) async {
    return runCatching(() async {
      await _localDataSource.updateDownloadStatus(
        id,
        status,
        errorMessage: errorMessage,
      );
    });
  }

  @override
  Future<Result<void>> updateDownloadProgress({
    required int id,
    required int downloadedBytes,
    required int totalBytes,
    required int speed,
  }) async {
    return runCatching(() async {
      // Use transactional update to ensure atomicity
      await _localDataSource.updateDownloadProgressWithTotal(
        id: id,
        downloadedBytes: downloadedBytes,
        totalBytes: totalBytes,
        speed: speed,
      );
    });
  }

  @override
  Future<Result<void>> completeDownload({
    required int id,
    required int totalBytes,
    required int downloadedBytes,
    String? filename,
  }) async {
    return runCatching(() async {
      await _localDataSource.completeDownload(
        id: id,
        totalBytes: totalBytes,
        downloadedBytes: downloadedBytes,
        filename: filename,
      );
    });
  }

  @override
  Future<Result<void>> failDownload({
    required int id,
    required String errorMessage,
  }) async {
    return runCatching(() async {
      final errorCode = DownloadErrorClassifier.classifyMessage(errorMessage);
      final storedMessage = '${errorCode.name}:$errorMessage';

      if (errorCode.isNetworkError) {
        // Network errors → waitingForNetwork (auto-retry when online)
        await _localDataSource.updateDownloadStatus(
          id,
          DownloadStatus.waitingForNetwork,
          errorMessage: storedMessage,
        );
        appLogger.info(
          '📶 Download $id waiting for network (${errorCode.name})',
        );
      } else {
        await _localDataSource.failDownload(
          id: id,
          errorMessage: storedMessage,
        );
        appLogger.info('❌ Download $id failed (${errorCode.name})');
      }
    });
  }

  @override
  Future<Result<void>> saveUserNote(int id, String note) async {
    return runCatching(() async {
      await _localDataSource.saveUserNote(id, note);
    });
  }

  @override
  Future<Result<void>> updateSavePath(int id, String newSavePath) async {
    return runCatching(() async {
      await _localDataSource.updateSavePath(id, newSavePath);
    });
  }

  @override
  Future<Result<void>> updateLocation(
    int id, {
    required String savePath,
    required String filename,
  }) async {
    return runCatching(() async {
      await _localDataSource.updateLocation(
        id,
        savePath: savePath,
        filename: filename,
      );
    });
  }

  @override
  Future<Result<int>> recoverDownloadsOnStartup() async {
    return runCatching(() async {
      final staleDownloads = await _localDataSource.getDownloadsByStatuses([
        DownloadStatus.downloading,
        DownloadStatus.pending,
        DownloadStatus.queued,
        // RC10.3: include the new post-process sub-states so a
        // crash mid-merge/remux/convert is recoverable (marked
        // failed since FFmpeg state can't resume).
        DownloadStatus.postProcessing,
        DownloadStatus.merging,
        DownloadStatus.remuxing,
        DownloadStatus.converting,
      ]);

      int recoveredCount = 0;
      for (final download in staleDownloads) {
        final entity = DownloadMapper.toDomain(download);

        if (entity.status.isPostProcessingPhase) {
          // FFmpeg state is lost — mark failed
          await _localDataSource.updateDownloadStatus(
            download.id,
            DownloadStatus.failed,
            errorMessage: 'App was interrupted during conversion',
          );
          continue;
        }

        if (download.retryCount >= _maxRetryAttempts) {
          await _localDataSource.updateDownloadStatus(
            download.id,
            DownloadStatus.failed,
            errorMessage: 'Maximum retry attempts reached',
          );
          appLogger.warning(
            '♻️ Download #${download.id} was stale but already exceeded '
            'max retries ($_maxRetryAttempts); marking failed instead of '
            're-queueing.',
          );
          continue;
        }

        // Check if we have a persisted temp dir with .part files for resume
        final tempDir = download.tempDirPath;
        final canResume =
            tempDir != null &&
            tempDir.isNotEmpty &&
            await Directory(tempDir).exists() &&
            await Directory(
              tempDir,
            ).list().any((e) => e is File && e.path.endsWith('.part'));

        // Reset stale downloads to queued so _processQueue picks them up.
        await _localDataSource.updateDownloadStatus(
          download.id,
          DownloadStatus.queued,
        );

        if (canResume) {
          // Keep existing progress — yt-dlp --continue will resume from .part files.
          // Only reset speed (process is dead, speed is stale).
          await _localDataSource.updateDownloadProgress(
            id: download.id,
            downloadedBytes: download.downloadedBytes,
            speed: 0,
          );
          appLogger.info(
            '♻️ Download #${download.id} recovered with resume support (temp dir has .part files)',
          );
        } else {
          // No .part files — reset progress, yt-dlp will start fresh.
          // Clear stale temp dir path if the dir no longer exists.
          if (tempDir != null && tempDir.isNotEmpty) {
            await _localDataSource.updateTempDirPath(download.id, null);
          }
          await _localDataSource.updateDownloadProgress(
            id: download.id,
            downloadedBytes: 0,
            speed: 0,
          );
        }
        recoveredCount++;
      }

      // Tell yt-dlp datasource to skip active temp dirs during cleanup
      final activeTempDirs =
          staleDownloads
              .where((d) => d.tempDirPath != null && d.tempDirPath!.isNotEmpty)
              .map((d) => d.tempDirPath!)
              .toSet();
      if (activeTempDirs.isNotEmpty) {
        _ytdlpDataSource?.cleanupTempDownloads(activeTempDirs: activeTempDirs);
      }

      return recoveredCount;
    });
  }

  @override
  Future<Result<void>> updateQueuePositions(List<int> orderedIds) async {
    return runCatching(() async {
      await _localDataSource.updateQueuePositions(orderedIds);
    });
  }

  @override
  Future<Result<void>> updateUrl(int id, String newUrl) async {
    return runCatching(() async {
      await _localDataSource.updateUrl(id, newUrl);
    });
  }

  @override
  Future<Result<void>> updatePriority(int id, int priority) async {
    return runCatching(() async {
      await _localDataSource.updatePriority(id, priority);
    });
  }

  @override
  Future<Result<void>> updateTempDirPath(int id, String? tempDirPath) async {
    return runCatching(() async {
      await _localDataSource.updateTempDirPath(id, tempDirPath);
    });
  }
}
