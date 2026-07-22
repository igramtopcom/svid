import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../../core/errors/result.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/providers/notification_center_provider.dart';
import '../../../../core/providers/proxy_rotation_provider.dart';
import '../../../../core/services/notification_center_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../settings/domain/enums/audio_codec_preference.dart';
import '../../../settings/domain/enums/container_format_preference.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/repositories/download_repository.dart';
import '../../domain/services/container_planner.dart';
import '../../domain/services/format_selector_service.dart';
import '../../domain/services/quality_resolution_parser.dart';
import '../../domain/entities/download_entity.dart';
import '../../domain/entities/download_error_code.dart';
import '../../domain/entities/download_status.dart';
import '../../domain/services/playlist_download_service.dart';
import '../../domain/services/download_error_classifier.dart';

import '../../../../core/utils/platform_detector.dart';
import '../../domain/services/retry_scheduler_service.dart';
import '../../domain/services/post_download_action_service.dart';
import '../../domain/entities/post_download_action.dart';
import '../../domain/services/sorting_rule_service.dart';
import '../../domain/services/bandwidth_rate_limiter.dart';
import '../../domain/services/quiet_hours_service.dart';
import '../../domain/entities/download_priority.dart';
import '../../domain/entities/recurrence_rule.dart';
import '../../domain/services/batch_file_operations_service.dart';
import '../../../../core/utils/queue_reorder_utils.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/services/error_reporter_service.dart';
import '../../../../core/services/instrumentation.dart';
import '../../../../core/providers/backend_providers.dart';
import 'dart:math' show min;
import '../../../premium/domain/entities/premium_limits.dart';
import '../../../premium/presentation/providers/premium_providers.dart';
import 'download_providers.dart';
import 'smart_queue_provider.dart';
import 'sorting_rule_providers.dart';

/// State for downloads list
class DownloadsState {
  final List<DownloadEntity> downloads;
  final bool isLoading;
  final String? error;

  /// IDs of completed downloads whose files no longer exist on disk
  final Set<int> fileMissingIds;

  /// IDs of downloads that were auto-boosted by smart queue
  final Set<int> smartBoostedIds;

  /// Non-null while a playlist / batch download session is in progress.
  final PlaylistSession? activePlaylist;

  const DownloadsState({
    this.downloads = const [],
    this.isLoading = false,
    this.error,
    this.fileMissingIds = const {},
    this.smartBoostedIds = const {},
    this.activePlaylist,
  });

  DownloadsState copyWith({
    List<DownloadEntity>? downloads,
    bool? isLoading,
    String? error,
    Set<int>? fileMissingIds,
    Set<int>? smartBoostedIds,
    PlaylistSession? activePlaylist,
    bool clearActivePlaylist = false,
  }) {
    return DownloadsState(
      downloads: downloads ?? this.downloads,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      fileMissingIds: fileMissingIds ?? this.fileMissingIds,
      smartBoostedIds: smartBoostedIds ?? this.smartBoostedIds,
      activePlaylist:
          clearActivePlaylist ? null : (activePlaylist ?? this.activePlaylist),
    );
  }

  /// Check if a download's file is missing from disk
  bool isFileMissing(int downloadId) => fileMissingIds.contains(downloadId);

  /// Check if a download was auto-boosted by smart queue
  bool isSmartBoosted(int downloadId) => smartBoostedIds.contains(downloadId);
}

/// Notifier for managing downloads list
class DownloadsNotifier extends StateNotifier<DownloadsState> {
  final Ref _ref;
  final Connectivity _connectivity;

  bool _startupValidationDone = false;
  bool _isDisposed = false;
  StreamSubscription<List<DownloadEntity>>? _downloadsSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _networkRetryDebounce;
  Timer? _fileValidationDebounce;
  // MEAS-1: per-download wall-clock timing for the download_complete event.
  // Keyed by download id; set on the →downloading transition and the first
  // →post-processing transition, read+cleared on the terminal transition.
  // In-memory only (no DB column) — a restart simply re-times the next attempt.
  final Map<int, DateTime> _downloadStartTimes = {};
  final Map<int, DateTime> _postProcessStartTimes = {};

  /// MEAS-1 (test-only): count of live timing entries, so a lifecycle test
  /// can assert the maps stay bounded (no leak when a started download is
  /// deleted while non-terminal).
  @visibleForTesting
  int get pendingTimingEntryCount =>
      _downloadStartTimes.length + _postProcessStartTimes.length;
  // Keep the UI auto-retry scheduler aligned with the repository retry budget.
  // User-triggered retry may reset an exhausted budget; auto retry must not.
  final RetrySchedulerService _retryScheduler = RetrySchedulerService(
    maxRetries: 3,
  );

  /// Safe premium status read — defaults to false if provider chain isn't available (tests).
  bool _tryReadIsPremium() {
    try {
      return _ref.read(isPremiumProvider);
    } catch (_) {
      return false;
    }
  }

  /// Tracks downloads that have already had a CDN URL refresh attempt.
  /// Prevents infinite refresh loops (max 1 refresh per download per session).
  final Set<int> _urlRefreshAttempted = {};
  final PostDownloadActionService _postDownloadService =
      PostDownloadActionService();
  final SortingRuleService _sortingRuleService = SortingRuleService();
  bool _isProcessingQueue = false; // Prevent re-entrant queue processing
  Timer? _queueProcessDebounce;

  DownloadsNotifier(this._ref, [Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity(),
      super(const DownloadsState()) {
    _init();
  }

  void _init() {
    // Watch all downloads and update state
    final repository = _ref.read(downloadRepositoryProvider);
    _downloadsSub = repository.watchAllDownloads().listen(
      (downloads) {
        // Check for status changes and trigger notifications
        _handleDownloadStatusChanges(state.downloads, downloads);

        state = state.copyWith(downloads: downloads, error: null);

        // Run startup validation once after first data load
        if (!_startupValidationDone) {
          _startupValidationDone = true;
          _validateOnStartup(downloads);
        }

        // Debounce continuous file-existence checks (expensive with 1000+ files)
        _fileValidationDebounce?.cancel();
        _fileValidationDebounce = Timer(const Duration(seconds: 30), () {
          _validateFileExistence(state.downloads);
        });
      },
      onError: (error) {
        appLogger.error('Error watching downloads', error);
        state = state.copyWith(error: error.toString());
      },
    );

    // Listen for network connectivity changes to auto-retry waitingForNetwork downloads
    _connectivitySub = _connectivity.onConnectivityChanged.listen(
      (results) {
        final hasConnection = results.any((r) => r != ConnectivityResult.none);
        final isWifi = results.any((r) => r == ConnectivityResult.wifi);
        final wifiOnlyMode = _ref.read(settingsProvider).wifiOnlyMode;
        // When wifiOnlyMode is on, only retry on WiFi; otherwise retry on any connection
        final shouldRetry = hasConnection && (!wifiOnlyMode || isWifi);
        if (shouldRetry) {
          // Debounce 3s to avoid rapid reconnect/disconnect cycles
          _networkRetryDebounce?.cancel();
          _networkRetryDebounce = Timer(const Duration(seconds: 3), () {
            _retryWaitingForNetworkDownloads();
          });
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        appLogger.warning(
          'Connectivity monitor failed; auto-retry is degraded: $error',
        );
        appLogger.debug(stackTrace.toString());
      },
    );
  }

  /// Validate downloads on app startup:
  /// 1. Recover stale downloads (resume/retry instead of marking failed)
  /// 2. Check completed downloads for file existence → populate fileMissingIds
  Future<void> _validateOnStartup(List<DownloadEntity> downloads) async {
    if (_isDisposed) return;
    final repository = _ref.read(downloadRepositoryProvider);

    // 1. Recover stale downloads — reset to queued so _processQueue picks them up
    final result = await repository.recoverDownloadsOnStartup();
    int recoveredCount = 0;
    result.fold(
      onSuccess: (count) {
        recoveredCount = count;
        if (count > 0) {
          appLogger.warning(
            '♻️ Recovered $count interrupted downloads on startup',
          );
        }
      },
      onFailure: (e) {
        appLogger.error('Failed to recover downloads on startup', e);
      },
    );

    // Trigger queue processing after recovery to auto-start recovered downloads
    if (recoveredCount > 0) {
      _queueProcessDebounce?.cancel();
      _queueProcessDebounce = Timer(const Duration(milliseconds: 500), () {
        _processQueue();
      });
    }

    // 2. Check file existence for completed downloads
    final missingIds = <int>{};
    for (final download in downloads) {
      if (download.status == DownloadStatus.completed) {
        final filePath = p.join(download.savePath, download.filename);
        if (!File(filePath).existsSync()) {
          missingIds.add(download.id);
        }
      }
    }

    if (missingIds.isNotEmpty) {
      // Not a warning — the UI surfaces these via fileMissingIds (grey tile,
      // "file missing" badge). Drift is expected when users delete files in
      // Finder/Explorer without removing the library row. Noise at WARN
      // masks real warnings during boot triage.
      appLogger.debug(
        'Found ${missingIds.length} completed downloads with missing files',
      );
      state = state.copyWith(fileMissingIds: missingIds);
    }
  }

  /// Continuously validate file existence for completed downloads
  /// Called on every stream emission to detect files deleted from Finder
  void _validateFileExistence(List<DownloadEntity> downloads) {
    if (_isDisposed) return;
    final currentMissing = Set<int>.from(state.fileMissingIds);
    bool changed = false;

    for (final download in downloads) {
      if (download.status == DownloadStatus.completed) {
        final filePath = p.join(download.savePath, download.filename);
        final exists = File(filePath).existsSync();

        if (!exists && !currentMissing.contains(download.id)) {
          currentMissing.add(download.id);
          changed = true;
        } else if (exists && currentMissing.contains(download.id)) {
          // File was restored (e.g., re-downloaded)
          currentMissing.remove(download.id);
          changed = true;
        }
      }
    }

    if (changed) {
      state = state.copyWith(fileMissingIds: currentMissing);
    }
  }

  /// Re-validate file existence (can be called after user actions)
  void revalidateFile(int downloadId, String savePath, String filename) {
    final filePath = p.join(savePath, filename);
    final exists = File(filePath).existsSync();
    final currentMissing = Set<int>.from(state.fileMissingIds);

    if (!exists && !currentMissing.contains(downloadId)) {
      currentMissing.add(downloadId);
      state = state.copyWith(fileMissingIds: currentMissing);
    } else if (exists && currentMissing.contains(downloadId)) {
      currentMissing.remove(downloadId);
      state = state.copyWith(fileMissingIds: currentMissing);
    }
  }

  /// Handle download status changes and trigger notifications / auto-recovery.
  ///
  /// Notification calls (showDownloadCompleted, showDownloadFailed, in-app
  /// notifications) are gated by [SettingsState.notificationsEnabled].
  /// Auto-recovery actions (smart queue priority, CDN refresh, retry scheduler)
  /// always run regardless of notification settings.
  void _handleDownloadStatusChanges(
    List<DownloadEntity> oldDownloads,
    List<DownloadEntity> newDownloads,
  ) {
    if (_isDisposed) return;
    final notificationsEnabled =
        _ref.read(settingsProvider).notificationsEnabled;

    // Create map of old downloads by ID for quick lookup
    final oldDownloadsMap = {for (var d in oldDownloads) d.id: d};

    for (var newDownload in newDownloads) {
      final oldDownload = oldDownloadsMap[newDownload.id];

      // Apply smart queue priority to newly added downloads (always)
      if (oldDownload == null) {
        applySmartQueuePriority(newDownload);
        _ref
            .read(errorReporterServiceProvider)
            .addBreadcrumb(
              'Download added',
              data: {
                'status': newDownload.status.name,
                'method': newDownload.downloadMethod,
              },
            );
        // Enforce concurrency limit — queue overflow downloads.
        // Only gate downloads still in PENDING state. Downloads already in
        // DOWNLOADING have a fire-and-forget monitor running — demoting them
        // to QUEUED races with the monitor's status writes and causes
        // _processQueue to restart already-active downloads (duplicate processes).
        if (newDownload.status == DownloadStatus.pending) {
          final isPremium = _tryReadIsPremium();
          final settingsConcurrent =
              _ref.read(settingsProvider).maxConcurrentDownloads;
          final maxConcurrent = min(
            settingsConcurrent,
            PremiumLimits.maxConcurrentDownloads(isPremium),
          );
          final activeCount =
              newDownloads
                  .where(
                    (d) =>
                        d.id != newDownload.id &&
                        (d.status == DownloadStatus.downloading ||
                            // RC10.3: include the new sub-states
                            // (merging/remuxing/converting) — all 4
                            // count as "actively occupying a slot".
                            d.status.isPostProcessingPhase),
                  )
                  .length;
          if (activeCount >= maxConcurrent) {
            appLogger.info(
              '⏳ [Queue] Concurrency limit ($maxConcurrent) reached, queuing: ${newDownload.filename}',
            );
            final repository = _ref.read(downloadRepositoryProvider);
            unawaited(
              repository.updateDownloadStatus(
                newDownload.id,
                DownloadStatus.queued,
              ),
            );
          }
        }
        continue;
      }

      // Check for download start
      if (oldDownload.status != DownloadStatus.downloading &&
          newDownload.status == DownloadStatus.downloading) {
        _downloadStartTimes[newDownload.id] = DateTime.now(); // MEAS-1
        _ref.read(analyticsServiceProvider).track('download_start', {
          'method': newDownload.downloadMethod,
          'platform': newDownload.platform,
        });
      }

      // MEAS-1: mark the first post-process (merge/recode) transition so
      // download_complete can split bytes-time vs post-process-time. A native
      // no-op merge never enters this phase → post_process_ms stays null.
      if (!oldDownload.status.isPostProcessingPhase &&
          newDownload.status.isPostProcessingPhase) {
        _postProcessStartTimes.putIfAbsent(
          newDownload.id,
          () => DateTime.now(),
        );
      }

      // MEAS-1: release timing entries on any non-completed terminal end
      // (failed/cancelled) so the maps stay bounded. Completed reads then
      // clears them below.
      if (!oldDownload.status.isTerminal &&
          newDownload.status.isTerminal &&
          newDownload.status != DownloadStatus.completed) {
        _downloadStartTimes.remove(newDownload.id);
        _postProcessStartTimes.remove(newDownload.id);
      }

      // Check for completion
      if (oldDownload.status != DownloadStatus.completed &&
          newDownload.status == DownloadStatus.completed) {
        _ref
            .read(errorReporterServiceProvider)
            .addBreadcrumb(
              'Download completed',
              data: {
                'bytes': newDownload.totalBytes,
                'method': newDownload.downloadMethod,
              },
            );
        // MEAS-1: thread wall-clock + phase split + attempt index onto the
        // completion event so every speed change ships with a before/after
        // number. All keys content-blind (no URL/title/path). duration_ms
        // spans the LAST →downloading…→completed attempt (the start stamp is
        // re-set on every re-entry into downloading, so pause idle and prior
        // attempts are excluded; includes post-process). Subtract
        // post_process_ms for the pure bytes phase. encoder_used lands with
        // DL-013 (HW-accel recode); null until then.
        _ref.read(analyticsServiceProvider).track(
              'download_complete',
              buildDownloadCompleteEvent(
                method: newDownload.downloadMethod,
                sizeBytes: newDownload.totalBytes,
                platform: newDownload.platform,
                startedAt: _downloadStartTimes.remove(newDownload.id),
                postProcessStartedAt:
                    _postProcessStartTimes.remove(newDownload.id),
                completedAt: DateTime.now(),
                attemptIndex: newDownload.retryCount,
              ),
            );
        if (notificationsEnabled) {
          notificationService.showDownloadCompleted(
            filename: newDownload.filename,
            savePath: newDownload.savePath,
          );
          _addInAppNotification(
            AppNotificationType.downloadComplete,
            'Download complete',
            newDownload.filename,
          );
        }

        // Post-download action → sorting rule, serialized to avoid
        // race conditions when both want to move the same file.
        _applyPostCompletionRules(newDownload);

        // Auto-trigger rating prompt after 10 successful downloads (once)
        _checkRatingTrigger();
      }

      // Check for failure
      if (oldDownload.status != DownloadStatus.failed &&
          newDownload.status == DownloadStatus.failed) {
        _ref
            .read(errorReporterServiceProvider)
            .addBreadcrumb(
              'Download failed',
              data: {
                'error': newDownload.errorMessage ?? 'unknown',
                'method': newDownload.downloadMethod,
              },
            );
        _ref.read(analyticsServiceProvider).track('download_error', {
          'method': newDownload.downloadMethod,
          'error': newDownload.errorMessage ?? 'unknown',
          'platform': newDownload.platform,
        });
        // Submit structured download error for detailed admin analytics
        _submitDownloadError(newDownload);
        if (notificationsEnabled) {
          notificationService.showDownloadFailed(
            filename: newDownload.filename,
            error: newDownload.errorMessage ?? 'Unknown error',
          );
          _addInAppNotification(
            AppNotificationType.downloadFailed,
            'Download failed',
            newDownload.filename,
          );
        }

        // Auto-retry if enabled in settings AND the error is retryable (always).
        // Non-retryable errors (e.g. HTTP 403 access denied, 410 gone) are not
        // scheduled for automatic retry — repeating with the same URL will fail.
        if (!_isDisposed) {
          final autoRetryEnabled = _ref.read(settingsProvider).autoRetryEnabled;
          final errorCode = DownloadErrorClassifier.classifyMessage(
            newDownload.errorMessage ?? '',
          );
          if (autoRetryEnabled && errorCode.isRetryable) {
            _retryScheduler.scheduleRetry(
              downloadId: newDownload.id,
              currentRetryCount: newDownload.retryCount,
              onRetry: (id) => _autoRetryDownload(id),
            );
          } else if (errorCode == DownloadErrorCode.accessDenied &&
              newDownload.downloadMethod == 'rust' &&
              newDownload.sourceUrl.isNotEmpty &&
              !_urlRefreshAttempted.contains(newDownload.id)) {
            // CDN URL expired (HTTP 403/410) — attempt a one-time URL refresh via
            // re-extraction before giving up (always, not gated by notifications).
            _urlRefreshAttempted.add(newDownload.id);
            unawaited(_refreshCdnUrlAndRetry(newDownload));
          }
        }
      }
    }

    // MEAS-1: prune timing entries for downloads that left the table. A
    // started download deleted while non-terminal (paused / waitingForNetwork
    // / queued are all deletable per DownloadEntity.canDelete) would otherwise
    // orphan its start stamp, since the terminal-transition cleanup above
    // never fires for it. Retain only ids still present in the live list.
    if (_downloadStartTimes.isNotEmpty || _postProcessStartTimes.isNotEmpty) {
      final liveIds = newDownloads.map((d) => d.id).toSet();
      _downloadStartTimes.removeWhere((id, _) => !liveIds.contains(id));
      _postProcessStartTimes.removeWhere((id, _) => !liveIds.contains(id));
    }

    // Debounce queue processing to avoid re-entrant state mutations.
    // Status changes from queue enforcement itself trigger this handler again;
    // debouncing collapses cascading calls into a single queue pass.
    _queueProcessDebounce?.cancel();
    _queueProcessDebounce = Timer(const Duration(milliseconds: 100), () {
      _processQueue();
    });
  }

  /// Start queued downloads when slots are available.
  /// Respects maxConcurrentDownloads setting.
  /// Guarded against re-entrance via [_isProcessingQueue].
  Future<void> _processQueue() async {
    if (_isProcessingQueue || _isDisposed) return;
    _isProcessingQueue = true;

    try {
      final isPremium = _tryReadIsPremium();
      final settingsConcurrent =
          _ref.read(settingsProvider).maxConcurrentDownloads;
      final maxConcurrent = min(
        settingsConcurrent,
        PremiumLimits.maxConcurrentDownloads(isPremium),
      );
      final activeCount =
          state.downloads
              .where(
                (d) =>
                    d.status == DownloadStatus.downloading ||
                    // RC10.3: include new merging/remuxing/converting
                    // sub-states as "actively occupying a slot".
                    d.status.isPostProcessingPhase,
              )
              .length;

      if (activeCount >= maxConcurrent) return;

      final availableSlots = maxConcurrent - activeCount;
      final queuedDownloads =
          state.downloads
              .where((d) => d.status == DownloadStatus.queued)
              .take(availableSlots)
              .toList();

      final repository = _ref.read(downloadRepositoryProvider);
      for (final download in queuedDownloads) {
        if (_isDisposed) return;
        // Re-verify status from DB — fire-and-forget may have already
        // completed or failed this download since we read the cached state.
        final freshResult = await repository.getDownloadById(download.id);
        final fresh = freshResult.dataOrNull;
        if (fresh == null || fresh.status != DownloadStatus.queued) continue;
        appLogger.info(
          '🚀 [Queue] Starting queued download: ${download.filename} (${activeCount + 1}/$maxConcurrent)',
        );
        await _startQueuedDownload(download);
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  /// Start a single queued download via repository retry mechanism.
  ///
  /// Codex Blocker #1 (RC1 of Ultra Plan v3) — this is the path
  /// queued/resumed/auto-retried downloads take. The legacy code
  /// called `repository.retryDownload(id)` with NO retry plan,
  /// which meant the user's chosen container, format, cookies, and
  /// codec preferences were ALL dropped on the queued retry. A
  /// failed AVI download would re-spawn from the queue as the
  /// yt-dlp default container; an age-gated video that needed
  /// cookies would re-fail with `loginRequired`. Mirror the manual
  /// `retryDownload` path so queued/resumed downloads carry the
  /// same plan a manual click would produce.
  Future<void> _startQueuedDownload(DownloadEntity download) async {
    final repository = _ref.read(downloadRepositoryProvider);
    final plan = await _buildRetryPlanFromSettings(download);
    final result = await repository.retryDownload(download.id, retryPlan: plan);
    result.fold(
      onSuccess: (_) {
        appLogger.info(
          '✅ [Queue] Queued download ${download.id} started '
          '(container=${plan?.videoFormat ?? plan?.audioFormat ?? "default"})',
        );
      },
      onFailure: (e) {
        appLogger.error(
          '❌ [Queue] Failed to start queued download ${download.id}',
          e,
        );
      },
    );
  }

  /// Load all downloads
  Future<void> loadDownloads() async {
    state = state.copyWith(isLoading: true);

    final useCase = _ref.read(getDownloadsUseCaseProvider);
    final result = await useCase();

    result.fold(
      onSuccess: (downloads) {
        state = state.copyWith(
          downloads: downloads,
          isLoading: false,
          error: null,
        );
      },
      onFailure: (exception) {
        appLogger.error('Failed to load downloads', exception);
        state = state.copyWith(isLoading: false, error: exception.toString());
      },
    );
  }

  /// Pause a download
  Future<void> pauseDownload(int id) async {
    final useCase = _ref.read(pauseDownloadUseCaseProvider);
    final result = await useCase(id);

    result.fold(
      onSuccess: (_) {
        appLogger.info('Download $id paused');
        _ref.read(analyticsServiceProvider).track('download_pause');
      },
      onFailure: (exception) {
        appLogger.error('Failed to pause download $id', exception);
        state = state.copyWith(error: exception.toString());
      },
    );
  }

  /// Resume a download
  Future<void> resumeDownload(int id) async {
    final useCase = _ref.read(resumeDownloadUseCaseProvider);
    final result = await useCase(id);

    result.fold(
      onSuccess: (_) {
        appLogger.info('Download $id resumed');
        _ref.read(analyticsServiceProvider).track('download_resume');
      },
      onFailure: (exception) {
        appLogger.error('Failed to resume download $id', exception);
        state = state.copyWith(error: exception.toString());
      },
    );
  }

  /// Cancel a download
  Future<void> cancelDownload(int id) async {
    _retryScheduler.cancelRetry(id);
    final useCase = _ref.read(cancelDownloadUseCaseProvider);
    final result = await useCase(id);

    result.fold(
      onSuccess: (_) {
        appLogger.info('Download $id cancelled');
      },
      onFailure: (exception) {
        appLogger.error('Failed to cancel download $id', exception);
        state = state.copyWith(error: exception.toString());
      },
    );
  }

  /// Delete a download
  Future<void> deleteDownload(int id, {bool deleteFile = false}) async {
    _retryScheduler.cancelRetry(id);
    final useCase = _ref.read(deleteDownloadUseCaseProvider);
    final result = await useCase(id, deleteFile: deleteFile);

    result.fold(
      onSuccess: (_) {
        appLogger.info('Download $id deleted');
      },
      onFailure: (exception) {
        appLogger.error('Failed to delete download $id', exception);
        state = state.copyWith(error: exception.toString());
      },
    );
  }

  /// Delete all completed downloads
  Future<void> deleteCompletedDownloads({bool deleteFiles = false}) async {
    final repository = _ref.read(downloadRepositoryProvider);
    final result = await repository.deleteCompletedDownloads(
      deleteFiles: deleteFiles,
    );

    result.fold(
      onSuccess: (count) {
        appLogger.info('Deleted $count completed downloads');
      },
      onFailure: (exception) {
        appLogger.error('Failed to delete completed downloads', exception);
        state = state.copyWith(error: exception.toString());
      },
    );
  }

  /// Delete all completed downloads whose files are missing from disk.
  /// Returns the number of entries removed.
  Future<int> deleteOrphanedDownloads() async {
    final ids = state.fileMissingIds.toList();
    if (ids.isEmpty) return 0;
    for (final id in ids) {
      await deleteDownload(id); // file already missing, no need to deleteFile
    }
    appLogger.info('Cleaned up ${ids.length} orphaned downloads');
    return ids.length;
  }

  /// Delete all failed downloads
  Future<void> deleteFailedDownloads({bool deleteFiles = false}) async {
    final repository = _ref.read(downloadRepositoryProvider);
    final result = await repository.deleteFailedDownloads(
      deleteFiles: deleteFiles,
    );

    result.fold(
      onSuccess: (count) {
        appLogger.info('Deleted $count failed downloads');
      },
      onFailure: (exception) {
        appLogger.error('Failed to delete failed downloads', exception);
        state = state.copyWith(error: exception.toString());
      },
    );
  }

  /// Pause all active downloads
  Future<void> pauseAllDownloads() async {
    final activeDownloads = state.downloads.where((d) => d.canPause).toList();
    for (final d in activeDownloads) {
      await pauseDownload(d.id);
    }
    appLogger.info('Paused ${activeDownloads.length} downloads');
  }

  /// Resume all paused downloads
  Future<void> resumeAllDownloads() async {
    final pausedDownloads = state.downloads.where((d) => d.canResume).toList();
    for (final d in pausedDownloads) {
      await resumeDownload(d.id);
    }
    appLogger.info('Resumed ${pausedDownloads.length} downloads');
  }

  /// Retry a failed download using repository's exponential backoff.
  /// Rate-limited downloads get a 30s delay before retrying.
  /// Does not consume another free-tier quota slot: quota is reserved when the
  /// download record is first created, and retry resumes that same record.
  Future<void> retryDownload(int id) async {
    await _retryDownload(id, manualRetry: true);
  }

  Future<void> _autoRetryDownload(int id) async {
    await _retryDownload(id, manualRetry: false);
  }

  Future<void> _retryDownload(int id, {required bool manualRetry}) async {
    final repository = _ref.read(downloadRepositoryProvider);
    final result = await repository.getDownloadById(id);
    // Await the fold so the inner async callback (which itself awaits
    // `_buildRetryPlanFromSettings` and `repository.retryDownload`)
    // completes before this method returns. The legacy code did not
    // await fold — pre-RC1 the inner `_buildRetryPlanFromSettings`
    // was synchronous so the test by chance saw the call land, but
    // making it async (Codex Blocker #2 cookie source) widened the
    // window past mocktail's verify(). Defensive: every async fold
    // result is awaited.
    await result.fold(
      onSuccess: (download) async {
        // Codex audit fix: previously this path called retryDownload(id)
        // with no plan, so the yt-dlp invocation got bare-bones args
        // and a failed AVI download retried as the yt-dlp default
        // (usually MKV). Compute a RetryDownloadPlan from current
        // global settings — for the COMMON case (user did not override
        // per-download via dialog) this is the same plan the original
        // download used. For per-download overrides the saved value is
        // not persisted in DB, so retry falls back to global container
        // pref — still NOT a silent fallback to MP4/MKV because the
        // user's global pick wins.
        final plan = await _buildRetryPlanFromSettings(download);
        final retryResult = await repository.retryDownload(
          id,
          retryPlan: plan,
          manualRetry: manualRetry,
        );
        retryResult.fold(
          onSuccess: (_) {
            appLogger.info(
              '🔄 Download $id retry started '
              '(container=${plan?.videoFormat ?? plan?.audioFormat ?? "default"})',
            );
          },
          onFailure: (exception) {
            appLogger.error('Failed to retry download $id', exception);
            state = state.copyWith(error: exception.toString());
          },
        );
      },
      onFailure: (_) async {
        // Fallback: try retryDownload directly (no plan since we
        // could not read the download record). The repository will
        // emit a warning log so this silent-fallback case is
        // observable. This branch is rare — implies the DB read
        // itself failed.
        final retryResult = await repository.retryDownload(
          id,
          manualRetry: manualRetry,
        );
        retryResult.fold(
          onSuccess: (_) {
            appLogger.info('🔄 Download $id retry started');
          },
          onFailure: (exception) {
            appLogger.error('Failed to retry download $id', exception);
            state = state.copyWith(error: exception.toString());
          },
        );
      },
    );
  }

  /// Build a [RetryDownloadPlan] from the current global settings +
  /// the persisted download record. This is the "recompute on retry"
  /// strategy Codex recommended over a Drift schema migration: rather
  /// than persist plan args per-download, we re-derive them from
  /// current settings, which honors the user's global container pick.
  /// Returns null for non-yt-dlp downloads (the legacy retry path).
  ///
  /// Ultra Plan v3 RC1 (Codex Blockers #1-3):
  ///   - #1 plan now fills `format` (yt-dlp `-f` selector) so retry
  ///     does NOT inherit yt-dlp's default selector (which often
  ///     resolves to a different quality than the original
  ///     download). Height is re-parsed from `qualityLabel`; unbounded
  ///     "Best" falls back to `buildBestFormatSelector`.
  ///   - #2 plan now fills `cookiesFile` + `cookiesFromBrowser` so
  ///     private/age-gated/cookie-bound videos do not fail again on
  ///     the first retry attempt. Sourced from
  ///     `cookiesFileForUrlProvider` (in-app captured) +
  ///     `cookiesFromBrowserProvider` (user Settings choice).
  ///   - #3 cookies precedence: file WINS over browser, mirroring
  ///     the data-source fix in commit 65897822. When both are
  ///     available we deliberately null `cookiesFromBrowser` to
  ///     avoid yt-dlp falling back to the Chrome cookie-DB path
  ///     while Chrome is running (Windows DB-lock crash class).
  ///
  /// Method is now async because cookie sourcing reads a
  /// `FutureProvider`. Caller `retryDownload` already awaits the
  /// repository call so the extra await is free.
  ///
  /// Resume / queue flow: `resumeDownload` flips the row to `queued`,
  /// then `_handleDownloadStatusChanges` debounces `_processQueue`,
  /// which calls `_startQueuedDownload` → `repository.retryDownload(id,
  /// retryPlan: _buildRetryPlanFromSettings(download))`. The queued
  /// retry therefore goes through this SAME method (no
  /// `StartDownloadUseCase` round-trip — that legacy comment was
  /// pre-RC1). Plan is re-derived from current settings each time, so
  /// a resume picks up the user's current global container pick
  /// rather than the original download's. Worth a follow-up audit if
  /// a user reports a resume-after-settings-change regression.
  Future<RetryDownloadPlan?> _buildRetryPlanFromSettings(
    DownloadEntity download,
  ) async {
    if (download.downloadMethod != 'ytdlp') return null;

    final settings = _ref.read(settingsProvider);
    final isPremium = _tryReadIsPremium();
    final isAudio = _isAudioOnlyDownload(download);

    // RC3 of Ultra Plan v3 — recover the user's ORIGINAL container
    // choice from `download.filename` extension before falling back
    // to the global `settings.containerFormatPreference`. The
    // filename is set on the first yt-dlp invocation (e.g.
    // "Cologne Cathedral song [Best (1080p)].avi") and persists in
    // the DB across retries. The global preference may have drifted
    // in the meantime (user changed default to MKV after creating
    // the AVI row), and retry MUST honor the original choice.
    //
    // Limitation surfaced by Codex: if a prior retry already
    // completed the download with the wrong extension (e.g., #402
    // got rewritten to .mkv), the filename column is now MKV and
    // this derivation can't recover the original AVI intent. RC3
    // therefore protects retries from THIS commit forward; rows
    // already corrupted by the pre-RC1 retry drift are not
    // recoverable without a separate import/repair tool.
    final derivedContainer = ContainerFormatPreference.fromExtension(
      download.filename,
    );
    var container = derivedContainer ?? settings.containerFormatPreference;

    // Mirror StartDownloadUseCase's smart-container-for-high-res (Chairman
    // 2026-07): a 1440p+ MP4 retry on YouTube would force a full VP9/AV1 →
    // H.264 transcode (slow + failure-prone). Switch to MKV (native remux)
    // before the plan/selector below so the whole retry derives from MKV.
    // New downloads already carry a .mkv filename (fresh-path fix) so this is
    // belt-and-suspenders; it also upgrades retries of pre-fix .mp4 rows.
    final retryHeightForContainer = QualityResolutionParser.parseHeight(
      download.qualityLabel ?? '',
    );
    if (container == ContainerFormatPreference.mp4 &&
        PlatformDetector.detectPlatform(download.url) ==
            VideoPlatform.youtube &&
        (retryHeightForContainer ?? 0) >= 1440) {
      container = ContainerFormatPreference.mkv;
    }

    // Source cookies BEFORE branching audio vs video so both paths
    // get the same cookie precedence treatment. Timeout protects
    // both production (a hung cookies service should not freeze
    // retry forever) and test isolation (FutureProvider has no
    // resolution in a stub scope so a bare `await .future` hangs
    // the test until the global timeout).
    String? cookiesFile;
    try {
      // RC8.4 of Ultra Plan v3 — invalidate the auto-dispose family
      // provider BEFORE the read so the retry never picks up a stale
      // cached future. Without this, a manual retry click that races
      // with a cookies-export refresh would read the previous
      // (possibly null or expired) value. Costs one extra cookie file
      // export per manual retry — trivial vs the wrong-cookies retry
      // failure pre-RC8.4. Auto-login retry path already invalidates
      // via `_readFreshCookiesFileForUrl`, so RC8.4 specifically
      // closes the manual-retry-button gap.
      // RC10 Codex-round-2 catch 5 — yt-dlp engine rows commonly
      // persist the resolved URL on `download.url` with `sourceUrl`
      // blank. Reading sourceUrl-only meant the cookies-by-url
      // provider got an empty string → returned null cookies →
      // retry fell back to browser DB → cookieDbLocked recurred.
      // Pick whichever field is non-empty (sourceUrl preferred when
      // present because it's the user's pasted URL).
      final cookieLookupUrl =
          download.sourceUrl.isNotEmpty ? download.sourceUrl : download.url;
      _ref.invalidate(cookiesFileForUrlProvider(cookieLookupUrl));
      cookiesFile = await _ref
          .read(cookiesFileForUrlProvider(cookieLookupUrl).future)
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
    } catch (e) {
      appLogger.debug('[Retry] cookiesFile lookup failed: $e');
    }
    String? cookiesFromBrowser;
    try {
      cookiesFromBrowser =
          cookiesFile == null ? _ref.read(cookiesFromBrowserProvider) : null;
    } catch (e) {
      // Defensive: a stub provider scope (tests) may not have the
      // browser-cookies provider wired. Treat as "no browser
      // cookies available" — caller falls back to no-cookies retry.
      appLogger.debug('[Retry] cookiesFromBrowser read failed: $e');
    }

    if (isAudio) {
      // RC5 of Ultra Plan v3 — derive audio format same way RC3
      // derives video container: filename extension first, then
      // qualityLabel hint, then settings, then mp3 fallback. Pre-RC5
      // this branch hardcoded `'mp3'` so an Opus or AAC extract
      // silently converted to MP3 on retry (same fault class as the
      // pre-RC3 video container drift).
      final audioFormat = _resolveRetryAudioFormat(
        filename: download.filename,
        qualityLabel: download.qualityLabel,
        settingsCodec: settings.audioCodecPreference,
      );
      final audioBitrateKbps = _resolveRetryAudioBitrateKbps(
        filename: download.filename,
        qualityLabel: download.qualityLabel,
      );
      return RetryDownloadPlan(
        extractAudio: true,
        audioFormat: audioFormat,
        audioBitrateKbps: audioBitrateKbps,
        cookiesFile: cookiesFile,
        cookiesFromBrowser: cookiesFromBrowser,
      );
    }

    // Source codec info is not persisted in the DB row. Native
    // containers (mp4/mkv/webm) still retry via merge/remux, not hidden
    // full conversion; explicit conversion containers keep recode.
    final plan = const ContainerPlanner().plan(
      pickedContainer: container,
      sourceVcodec: null,
      sourceAcodec: null,
    );
    final selector = const FormatSelectorService();
    final maxHeight = isPremium ? null : PremiumLimits.freeMaxResolutionP;

    // Compute the yt-dlp `-f` selector from the persisted qualityLabel.
    // Parseable height ("1080p" / "Best (1440p)" / "8K 60fps" /
    // "4K" / "UHD" / "2K" / "QHD") → resolution selector. Else
    // ("Best" with no height, "Audio Only" already handled) →
    // best-quality selector. This closes Codex Blocker #1 (retry
    // sending NO format selector → yt-dlp picks default, surfacing
    // a wrong quality file).
    //
    // Use the project's canonical parser
    // ([QualityResolutionParser.parseHeight]) instead of a regex
    // local to this method — it normalizes 8K/4K/UHD/QHD tokens
    // that production label strings actually emit. Production has
    // labels like "Best (8K 60fps)" that the previous local regex
    // missed, defaulting the retry to "Best" without a height cap.
    final qualityHeight = QualityResolutionParser.parseHeight(
      download.qualityLabel ?? '',
    );
    final cappedHeight =
        qualityHeight != null && maxHeight != null
            ? (qualityHeight > maxHeight ? maxHeight : qualityHeight)
            : qualityHeight;
    // RC10 Codex-round-3 — normalize retry-path codec preferences
    // against the retry container BEFORE building the selector.
    // Without this, settings.videoCodecPreference=Hevc + container=WebM
    // (legitimate state: user changed default codec after picking WebM
    // for a download) would emit `bestvideo[vcodec^=hev1]` against a
    // WebM selector, silently producing a wrong-codec stream or a
    // hidden recode. Mirrors the use-case-level fix at the initial
    // download path.
    final normalizedRetryVideoCodec = selector.normalizeVideoCodecForContainer(
      settings.videoCodecPreference,
      container,
    );
    final normalizedRetryAudioCodec = selector.normalizeAudioCodecForContainer(
      settings.audioCodecPreference,
      container,
    );
    String format =
        cappedHeight != null
            ? selector.buildResolutionFormatSelector(
              height: cappedHeight,
              videoCodec: normalizedRetryVideoCodec,
              audioCodec: normalizedRetryAudioCodec,
              fps: settings.fpsPreference,
              // RC10 Blocker 4: pass container so the retry's
              // format selector biases toward codec-compatible
              // streams (avc1+aac for MP4, vp9+opus for WebM)
              // when user hasn't explicitly chosen a codec. Keeps
              // ContainerPlanner's "no hidden conversion" policy
              // honest on retry.
              container: container,
            )
            : selector.buildBestFormatSelector(
              videoCodec: normalizedRetryVideoCodec,
              audioCodec: normalizedRetryAudioCodec,
              fps: settings.fpsPreference,
              maxHeight: maxHeight,
              container: container,
            );
    String? sortOptionsOverride;

    // Q+1 (2026-05-25 retry-mirror fix): mirror StartDownloadUseCase's
    // WebM-output-target policy so Facebook / Instagram / Reddit
    // retry to WebM no longer fails "Requested format is not
    // available". The fresh path was patched (call site uses
    // ContainerPlanner.shouldForceWebmOutputRecode +
    // buildWebmRecodeSourceSelector); without mirroring here, retry
    // built the WebM-native-strict selector and re-emitted the same
    // broken command (vidcombo log.md 2026-05-25 #427/#430).
    //
    // Source codecs are not persisted on the DB row, so the helper
    // sees null/null — for non-YouTube platforms this means "can't
    // prove WebM-native" → force recode. YouTube stays on fast path
    // because the helper short-circuits on platform == youtube.
    final retryPlatform = PlatformDetector.detectPlatform(download.url);
    var retryRecodeVideo = plan.recodeVideo;
    var retryRemuxVideo = plan.remuxVideo;
    var retryMergeFormat = plan.mergeFormat;
    if (ContainerPlanner.shouldForceWebmOutputRecode(
      platform: retryPlatform,
      videoFormat: plan.finalExtension,
      recodeVideo: retryRecodeVideo,
      remuxVideo: retryRemuxVideo,
      sourceVcodec: null,
      sourceAcodec: null,
    )) {
      retryRecodeVideo = 'webm';
      retryRemuxVideo = null;
      retryMergeFormat = ContainerPlanner.webmRecodeMergeFormatPriority;
    }
    // N2 (2026-06 MP4 retry mirror): source codecs are NOT persisted on
    // the DB row, so the WebM helper above got sourceVcodec:null and a
    // VP9-only MP4 pick would remux → .mkv → C3 hard-fail. The MP4 mirror
    // forces recode='mp4' on YouTube when the source can't be proven
    // MP4-native (exactly the null-vcodec retry case). Non-YouTube /
    // proven-native sources stay on the fast remux path via the helper's
    // own platform + codec gating. Placed AFTER the WebM block; the
    // targetsMp4 guard makes it a no-op when WebM already claimed recode.
    if (ContainerPlanner.shouldForceMp4OutputRecode(
      platform: retryPlatform,
      videoFormat: plan.finalExtension,
      recodeVideo: retryRecodeVideo,
      remuxVideo: retryRemuxVideo,
      sourceVcodec: null,
    )) {
      retryRecodeVideo = 'mp4';
      retryRemuxVideo = null;
      retryMergeFormat = ContainerPlanner.mp4RecodeMergeFormatPriority;
    }
    if (retryRecodeVideo?.toLowerCase() == 'webm') {
      format = ContainerPlanner.buildWebmRecodeSourceSelector(
        targetHeight: cappedHeight,
        maxVideoHeight: maxHeight,
      );
      // Wave A (AUD-2) — mirror of the fresh path: keep the
      // webm-native bias so the forced arm doesn't pick AAC and defeat
      // the webm-first merge prover. Mirror discipline per Q+1.
      sortOptionsOverride =
          cappedHeight != null
              ? 'res:$cappedHeight,ext:webm:opus'
              : 'res,ext:webm:opus';
    }

    return RetryDownloadPlan(
      format: format,
      videoFormat: plan.finalExtension,
      mergeFormatPriority: retryMergeFormat,
      remuxVideo: retryRemuxVideo,
      recodeVideo: retryRecodeVideo,
      sortOptions:
          sortOptionsOverride ??
          selector.buildSortOptions(
            videoCodec: normalizedRetryVideoCodec,
            audioCodec: normalizedRetryAudioCodec,
            fps: settings.fpsPreference,
            container: container,
            targetHeight: cappedHeight ?? maxHeight,
          ),
      maxVideoHeight: maxHeight,
      targetVideoHeight: cappedHeight ?? maxHeight,
      extractAudio: false,
      cookiesFile: cookiesFile,
      cookiesFromBrowser: cookiesFromBrowser,
    );
  }

  /// Reserved for follow-up: parse a height from qualityLabel ("1080p"
  // _heightFromQualityLabel was removed; height parsing now goes
  // through `QualityResolutionParser.parseHeight` which already
  // normalizes 8K/4K/UHD/QHD tokens. Keeping a local regex here was
  // the Codex-caught gap that left production labels (e.g.
  // "Best (8K 60fps)") missing a height cap on retry.

  /// Heuristic: detect audio-only downloads by qualityLabel keyword.
  /// Persisted qualityLabel values include "Audio Only" / "MP3" /
  /// "M4A" — when none match we fall back to video flow.
  bool _isAudioOnlyDownload(DownloadEntity download) {
    final label = (download.qualityLabel ?? '').toLowerCase();
    if (label.contains('audio')) return true;
    const audioMarkers = ['mp3', 'm4a', 'aac', 'opus', 'flac', 'wav'];
    for (final m in audioMarkers) {
      if (label.contains(m)) return true;
    }
    return false;
  }

  /// MEAS-1: builds the content-blind `download_complete` telemetry payload.
  /// Pure so the 7-key contract + null semantics are unit-locked without the
  /// notifier wiring. `duration_ms` spans the last →downloading…→completed
  /// attempt (null when the start was not observed, e.g. a download in flight
  /// across an app restart); `post_process_ms` is the merge/recode sub-span
  /// (null when a
  /// native no-op merge never entered a post-processing phase, so
  /// `duration_ms − post_process_ms` ≈ the pure bytes phase). `encoder_used`
  /// is reserved for DL-013 (HW-accel recode) and stays null until then.
  @visibleForTesting
  static Map<String, dynamic> buildDownloadCompleteEvent({
    required String method,
    required int sizeBytes,
    required String platform,
    required DateTime? startedAt,
    required DateTime? postProcessStartedAt,
    required DateTime completedAt,
    required int attemptIndex,
    String? encoderUsed,
  }) {
    return {
      'method': method,
      'size_bytes': sizeBytes,
      'platform': platform,
      'duration_ms': startedAt != null
          ? completedAt.difference(startedAt).inMilliseconds
          : null,
      'post_process_ms': postProcessStartedAt != null
          ? completedAt.difference(postProcessStartedAt).inMilliseconds
          : null,
      'attempt_index': attemptIndex,
      'encoder_used': encoderUsed,
    };
  }

  /// RC5 of Ultra Plan v3 — derive the retry `--audio-format` value.
  ///
  /// Pre-RC5 the audio retry branch hardcoded `audioFormat: 'mp3'`,
  /// so an Opus or AAC extract would silently convert to MP3 on
  /// retry (same fault class as the pre-RC3 video container drift).
  /// This helper mirrors RC3's filename-first derivation:
  ///
  ///   1. `download.filename` extension wins (set on first yt-dlp
  ///      invocation, persists across retries).
  ///   2. `download.qualityLabel` codec hint (e.g., "Audio Only
  ///      (Opus)") as a fallback for rows whose filename extension
  ///      was stripped or normalized.
  ///   3. `settings.audioCodecPreference` global current (Auto →
  ///      no mapping, falls through to mp3 since yt-dlp needs a
  ///      concrete `--audio-format` value).
  ///   4. `'mp3'` last-resort fallback so the retry never sends
  ///      an empty `--audio-format` arg.
  ///
  /// Returned values match yt-dlp's `--audio-format` validator
  /// (mp3/aac/m4a/opus/flac/wav/vorbis/alac). `.ogg` filenames map
  /// to `vorbis` since OGG containers conventionally hold Vorbis
  /// audio in this app's YouTube/SoundCloud flow.
  @visibleForTesting
  static String resolveRetryAudioFormatForTest({
    required String? filename,
    required String? qualityLabel,
    required AudioCodecPreference? settingsCodec,
  }) => _resolveRetryAudioFormat(
    filename: filename,
    qualityLabel: qualityLabel,
    settingsCodec: settingsCodec,
  );

  static String _resolveRetryAudioFormat({
    required String? filename,
    required String? qualityLabel,
    required AudioCodecPreference? settingsCodec,
  }) {
    final fromExt = _audioFormatFromFilename(filename);
    if (fromExt != null) return fromExt;
    final fromLabel = _audioFormatFromQualityLabel(qualityLabel);
    if (fromLabel != null) return fromLabel;
    if (settingsCodec != null) {
      switch (settingsCodec) {
        case AudioCodecPreference.aac:
          return 'aac';
        case AudioCodecPreference.opus:
          return 'opus';
        case AudioCodecPreference.mp3:
          return 'mp3';
        case AudioCodecPreference.auto:
          break;
      }
    }
    return 'mp3';
  }

  static String? _audioFormatFromFilename(String? filename) {
    if (filename == null || filename.isEmpty) return null;
    final dot = filename.lastIndexOf('.');
    final raw = dot >= 0 ? filename.substring(dot + 1) : filename;
    final ext = raw.trim().toLowerCase();
    if (ext.isEmpty) return null;
    const direct = {'mp3', 'aac', 'm4a', 'opus', 'flac', 'wav', 'alac'};
    if (direct.contains(ext)) return ext;
    if (ext == 'ogg') return 'vorbis';
    return null;
  }

  static String? _audioFormatFromQualityLabel(String? label) {
    if (label == null || label.isEmpty) return null;
    final lower = label.toLowerCase();
    // Order matters: check most-specific tokens first so e.g.
    // "Audio Only (M4A/AAC)" picks m4a over aac.
    if (lower.contains('opus')) return 'opus';
    if (lower.contains('m4a')) return 'm4a';
    if (lower.contains('flac')) return 'flac';
    if (lower.contains('aac')) return 'aac';
    if (lower.contains('mp3')) return 'mp3';
    return null;
  }

  @visibleForTesting
  static int? resolveRetryAudioBitrateKbpsForTest({
    required String? filename,
    required String? qualityLabel,
  }) => _resolveRetryAudioBitrateKbps(
    filename: filename,
    qualityLabel: qualityLabel,
  );

  static int? _resolveRetryAudioBitrateKbps({
    required String? filename,
    required String? qualityLabel,
  }) {
    return _audioBitrateFromText(filename) ??
        _audioBitrateFromText(qualityLabel);
  }

  static int? _audioBitrateFromText(String? text) {
    if (text == null || text.isEmpty) return null;
    final match = RegExp(
      r'(\d{2,4})\s*k(?:bps|b/s)?',
      caseSensitive: false,
    ).firstMatch(text);
    final value = match == null ? null : int.tryParse(match.group(1)!);
    if (value == null || value <= 0) return null;
    return value;
  }

  /// Auto-retry all downloads waiting for network when connectivity is restored
  Future<void> _retryWaitingForNetworkDownloads() async {
    if (_isDisposed) return;
    final waiting =
        state.downloads
            .where((d) => d.status == DownloadStatus.waitingForNetwork)
            .toList();

    if (waiting.isEmpty) return;

    appLogger.info(
      '📶 Network restored — retrying ${waiting.length} download(s)',
    );
    final repository = _ref.read(downloadRepositoryProvider);

    for (final download in waiting) {
      await repository.updateDownloadStatus(
        download.id,
        DownloadStatus.pending,
      );
    }
  }

  /// Re-extracts the video info from the original page URL to obtain a fresh
  /// CDN URL, then updates the download record and restarts.
  ///
  /// Only called once per download per session (guarded by [_urlRefreshAttempted]).
  /// Only applicable to `downloadMethod == 'rust'` downloads where a direct
  /// HTTPS URL can be obtained from re-extraction.
  Future<void> _refreshCdnUrlAndRetry(DownloadEntity download) async {
    if (_isDisposed) return;
    appLogger.info(
      '🔄 CDN URL expired for #${download.id} — re-extracting from ${download.sourceUrl}',
    );
    final extractUseCase = _ref.read(extractVideoInfoUseCaseProvider);
    String? cookiesFile;
    try {
      cookiesFile = await _ref.read(
        cookiesFileForUrlProvider(download.sourceUrl).future,
      );
    } catch (_) {}
    if (_isDisposed) return;
    final cookiesFromBrowser =
        cookiesFile == null ? _ref.read(cookiesFromBrowserProvider) : null;
    final result = await extractUseCase(
      download.sourceUrl,
      cookiesFile: cookiesFile,
      cookiesFromBrowser: cookiesFromBrowser,
      cookiesFromBrowserFallback: _ref.read(cookiesFromBrowserFallbackProvider),
      cookiesFromBrowserFallbackChain: _ref.read(
        cookiesFromBrowserFallbackChainProvider,
      ),
    );
    if (_isDisposed) return;

    result.fold(
      onSuccess: (videoInfo) async {
        // Find quality matching the original label; fall back to best available.
        final matched =
            videoInfo.availableQualities
                .where((q) => q.qualityText == download.qualityLabel)
                .firstOrNull ??
            videoInfo.availableQualities.firstOrNull;

        if (matched == null) {
          appLogger.error('CDN refresh #${download.id}: no qualities found');
          return;
        }

        final freshUrl = matched.encryptedUrl;
        if (!PlatformDetector.isDirectUrl(freshUrl)) {
          // yt-dlp or encoded URL — not usable as a direct Rust download URL.
          appLogger.warning(
            'CDN refresh #${download.id}: URL is not a direct HTTPS URL (${freshUrl.length > 15 ? "${freshUrl.substring(0, 15)}…" : freshUrl}) — skipping',
          );
          return;
        }

        appLogger.info(
          '✅ CDN URL refreshed for #${download.id} — updating DB and retrying',
        );
        final repository = _ref.read(downloadRepositoryProvider);
        final updateResult = await repository.updateUrl(download.id, freshUrl);
        updateResult.fold(
          onSuccess: (_) async => retryDownload(download.id),
          onFailure:
              (e) => appLogger.error(
                'CDN refresh #${download.id}: updateUrl failed',
                e,
              ),
        );
      },
      onFailure: (exception) {
        appLogger.error(
          'CDN refresh #${download.id}: re-extraction failed',
          exception,
        );
      },
    );
  }

  /// Add an in-app notification via NotificationCenterService
  void _addInAppNotification(
    AppNotificationType type,
    String title,
    String body,
  ) {
    try {
      final service = _ref.read(notificationCenterServiceProvider);
      service.add(type, title, body);
    } catch (e) {
      appLogger.debug('NotificationCenterService not available: $e');
    }
  }

  /// Save a user note on a download (clamp to 200 chars, trimRight)
  Future<void> saveUserNote(int id, String note) async {
    final clamped = note.length > 200 ? note.substring(0, 200) : note;
    final trimmed = clamped.trimRight();
    final repository = _ref.read(downloadRepositoryProvider);
    final result = await repository.saveUserNote(id, trimmed);
    result.fold(
      onSuccess: (_) {
        appLogger.info('Note saved for download $id');
      },
      onFailure: (exception) {
        appLogger.error('Failed to save note for download $id', exception);
      },
    );
  }

  /// Clear error message
  void clearError() {
    state = state.copyWith(error: null);
  }

  // ==================== SCHEDULING ====================

  /// Schedule [id] to start at [scheduledAt], optionally with a [recurrence] rule.
  Future<void> scheduleFor(
    int id,
    DateTime scheduledAt, {
    RecurrenceRule? recurrence,
  }) async {
    final repository = _ref.read(downloadRepositoryProvider);
    final result = await repository.updateScheduledAt(id, scheduledAt);
    result.fold(
      onSuccess:
          (_) => appLogger.info('📅 Scheduled download $id for $scheduledAt'),
      onFailure: (e) => appLogger.error('Failed to schedule download $id', e),
    );
    // Persist recurrence rule (or clear it if none)
    final rrJson =
        (recurrence != null && recurrence.isRecurring)
            ? recurrence.toJson()
            : null;
    final rrResult = await repository.updateRecurrenceRuleJson(id, rrJson);
    rrResult.fold(
      onSuccess: (_) {
        if (rrJson != null) {
          appLogger.info(
            '🔁 Recurrence set for download $id: ${recurrence?.type.name}',
          );
        }
      },
      onFailure:
          (e) =>
              appLogger.error('Failed to set recurrence for download $id', e),
    );
  }

  /// Clear the schedule for [id] (download will start when auto-start fires).
  Future<void> cancelSchedule(int id) async {
    final repository = _ref.read(downloadRepositoryProvider);
    final result = await repository.updateScheduledAt(id, null);
    result.fold(
      onSuccess: (_) => appLogger.info('🗑 Cleared schedule for download $id'),
      onFailure:
          (e) =>
              appLogger.error('Failed to clear schedule for download $id', e),
    );
  }

  /// Called by [DownloadSchedulerService] every 60 s.
  /// Finds pending downloads whose [scheduledAt] has elapsed and starts them,
  /// applying quiet-hours throttle and priority-weighted bandwidth allocation.
  Future<void> checkAndStartScheduledDownloads() async {
    if (_isDisposed) return;
    final now = DateTime.now();
    final due =
        state.downloads
            .where(
              (d) =>
                  d.status == DownloadStatus.pending &&
                  d.scheduledAt != null &&
                  d.scheduledAt!.isBefore(now),
            )
            .toList();

    if (due.isEmpty) return;

    final settings = _ref.read(settingsProvider);

    // Resolve effective bandwidth limit (quiet hours override if active).
    final effectiveLimitKbps = const QuietHoursService().getEffectiveLimitKbps(
      now: now,
      enabled: settings.quietHoursEnabled,
      startHour: settings.quietHoursStart,
      endHour: settings.quietHoursEnd,
      quietKbps: settings.quietHoursBandwidthKbps,
      normalKbps: settings.globalBandwidthLimit,
    );
    if (settings.quietHoursEnabled &&
        const QuietHoursService().isQuietHour(
          now: now,
          startHour: settings.quietHoursStart,
          endHour: settings.quietHoursEnd,
        )) {
      appLogger.info(
        '🌙 Quiet hours active — capping at $effectiveLimitKbps KB/s',
      );
    }

    // Compute priority-weighted bandwidth per download.
    final allActive =
        state.downloads
            .where((d) => d.status == DownloadStatus.downloading)
            .toList();
    final allPriorities = [
      ...allActive.map((d) => d.priority),
      ...due.map((d) => d.priority),
    ];
    final weightSum = BandwidthRateLimiter.totalWeightSum(allPriorities);

    for (final d in due) {
      final perDownloadLimit = BandwidthRateLimiter.computeWeightedLimit(
        globalLimitKbps: effectiveLimitKbps,
        downloadPriority: d.priority,
        activeWeightSum: weightSum,
      );
      appLogger.info(
        '📅 Scheduled start: download ${d.id}'
        '${perDownloadLimit > 0 ? " (limit: ${perDownloadLimit}B/s, weight: ${BandwidthRateLimiter.weightFor(d.priority)}×)" : ""}',
      );

      final rule = d.recurrenceRule;
      if (rule != null && rule.isRecurring) {
        // Recurring: schedule the next occurrence instead of clearing
        final next = rule.nextOccurrence(d.scheduledAt!);
        appLogger.info(
          '🔁 Recurring download ${d.id}: next scheduled for $next',
        );
        await scheduleFor(d.id, next, recurrence: rule);
      } else {
        // One-time: clear the schedule so we don't re-trigger
        await cancelSchedule(d.id);
      }

      if (_isDisposed) return;

      // Start with bandwidth cap if set.
      final repository = _ref.read(downloadRepositoryProvider);
      await repository.startDownload(
        d.id,
        maxSpeedBytes: perDownloadLimit > 0 ? perDownloadLimit : null,
        proxyUrl:
            _ref.read(proxyRotationServiceProvider).nextProxy() ??
            _ref.read(settingsProvider).proxyUrl,
      );
    }
  }

  /// Apply smart queue priority to a new download based on usage patterns.
  /// If the platform has been frequently downloaded, marks it as smart-boosted.
  void applySmartQueuePriority(DownloadEntity download) {
    instrumentedSync<void>(
      'downloads.smart_queue_priority',
      () {
        final service = _ref.read(smartQueueServiceProvider);
        final frequency = service.computePlatformFrequency(state.downloads);
        final priority = service.suggestPriority(
          download.platform,
          '',
          frequency,
        );

        if (priority == DownloadPriority.high) {
          state = state.copyWith(
            smartBoostedIds: {...state.smartBoostedIds, download.id},
          );
          appLogger.info(
            '⚡ Smart Queue: boosted download ${download.id} (platform: ${download.platform})',
          );
        }
      },
      attributes: {'platform': download.platform},
      rethrowAfterReport: false,
      onError: (e, _) {
        // Non-critical — don't break download flow.
        appLogger.debug('Smart queue priority check skipped: $e');
      },
      reporter: _ref.read(errorReporterServiceProvider),
    );
  }

  /// Set manual priority for a download.
  ///
  /// Optimistically updates in-memory state, then persists to DB.
  /// No-op if [id] is not found.
  Future<void> setPriority(int id, DownloadPriority priority) async {
    final idx = state.downloads.indexWhere((d) => d.id == id);
    if (idx == -1) return;

    // Optimistic update
    final updated = List<DownloadEntity>.from(state.downloads);
    updated[idx] = updated[idx].copyWith(priority: priority.value);
    state = state.copyWith(downloads: updated);

    final result = await _ref
        .read(downloadRepositoryProvider)
        .updatePriority(id, priority.value);
    result.when(
      success: (_) {},
      failure:
          (e) => appLogger.error('Failed to persist priority update', e, null),
    );
  }

  /// Returns pending downloads reordered for network conditions.
  ///
  /// When [networkAwareQueueReorder] is enabled and bandwidth is slow,
  /// smaller files are promoted within each priority group.
  List<DownloadEntity> getPendingReordered({
    required bool networkAwareEnabled,
  }) {
    final pending =
        state.downloads
            .where(
              (d) =>
                  d.status == DownloadStatus.pending ||
                  d.status == DownloadStatus.queued,
            )
            .toList();
    if (!networkAwareEnabled) return pending;
    // Aggregate speed of all currently active downloads
    final aggregateBps = state.downloads
        .where((d) => d.status == DownloadStatus.downloading)
        .fold<int>(0, (sum, d) => sum + d.speed);
    return reorderForBandwidth(pending, aggregateBps);
  }

  /// Reorder downloads via drag-and-drop.
  ///
  /// [orderedIds] is the complete list of visible download IDs in the new order.
  /// Optimistically updates in-memory state, then persists to DB.
  Future<void> reorderDownloads(List<int> orderedIds) async {
    // Assign positions 0..N-1 to each visible download
    final positionMap = {
      for (int i = 0; i < orderedIds.length; i++) orderedIds[i]: i,
    };

    // Optimistic update
    final updated =
        state.downloads.map((d) {
          final pos = positionMap[d.id];
          return pos != null ? d.copyWith(queuePosition: pos) : d;
        }).toList();
    state = state.copyWith(downloads: updated);

    // Persist
    final result = await _ref
        .read(downloadRepositoryProvider)
        .updateQueuePositions(orderedIds);
    result.when(
      success: (_) {},
      failure:
          (e) => appLogger.error('Failed to persist queue reorder', e, null),
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    _downloadsSub?.cancel();
    _connectivitySub?.cancel();
    _networkRetryDebounce?.cancel();
    _fileValidationDebounce?.cancel();
    _queueProcessDebounce?.cancel();
    _retryScheduler.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Playlist / batch session management
  // -------------------------------------------------------------------------

  /// Starts a new playlist download session with [total] expected videos.
  void startPlaylistSession(
    String sessionId,
    int total, {
    PlaylistSessionPhase phase = PlaylistSessionPhase.extracting,
  }) {
    state = state.copyWith(
      activePlaylist: PlaylistSession(
        id: sessionId,
        total: total,
        phase: phase,
      ),
    );
    _ref.read(analyticsServiceProvider).track('batch_download_started', {
      'total': total,
    });
  }

  /// Updates the active batch phase without resetting progress counters.
  void updatePlaylistPhase(PlaylistSessionPhase phase) {
    final session = state.activePlaylist;
    if (session == null) return;
    state = state.copyWith(activePlaylist: session.copyWith(phase: phase));
  }

  /// Records one successfully started download for the active session.
  void incrementPlaylistCompleted() {
    final session = state.activePlaylist;
    if (session == null) return;
    state = state.copyWith(
      activePlaylist: session.copyWith(completed: session.completed + 1),
    );
  }

  /// Records one failed extraction / download for the active session.
  void incrementPlaylistFailed() {
    final session = state.activePlaylist;
    if (session == null) return;
    state = state.copyWith(
      activePlaylist: session.copyWith(failed: session.failed + 1),
    );
  }

  /// Records one URL skipped because it was already downloaded.
  void incrementPlaylistSkipped() {
    final session = state.activePlaylist;
    if (session == null) return;
    state = state.copyWith(
      activePlaylist: session.copyWith(skipped: session.skipped + 1),
    );
  }

  /// Marks the active session as finished (sets isActive = false).
  void endPlaylistSession() {
    final session = state.activePlaylist;
    if (session == null) return;
    state = state.copyWith(
      activePlaylist: session.copyWith(
        phase: PlaylistSessionPhase.finished,
        isActive: false,
      ),
    );
  }

  // ── Batch file operations ──────────────────────────────────────────────────

  /// Delete a batch of downloads (and optionally their files from disk).
  Future<void> bulkDelete(List<int> ids, {bool deleteFiles = true}) async {
    final db = _ref.read(databaseProvider);
    final svc = BatchFileOperationsService();
    final result = await svc.deleteFiles(
      ids,
      db: db,
      deleteFromDisk: deleteFiles,
    );
    appLogger.info(
      'Bulk delete: ${result.succeeded} ok, ${result.failed} failed',
    );
    if (result.failed > 0) {
      state = state.copyWith(error: result.errors.join('; '));
    }
  }

  /// Move a batch of downloads to [targetPath].
  Future<void> bulkMove(List<int> ids, String targetPath) async {
    final db = _ref.read(databaseProvider);
    final svc = BatchFileOperationsService();
    final result = await svc.moveFiles(ids, targetPath, db: db);
    appLogger.info(
      'Bulk move: ${result.succeeded} ok, ${result.failed} failed',
    );
    if (result.failed > 0) {
      state = state.copyWith(error: result.errors.join('; '));
    }
  }

  /// Rename a batch of downloads using [pattern] tokens.
  Future<void> bulkRename(List<int> ids, String pattern) async {
    final db = _ref.read(databaseProvider);
    final svc = BatchFileOperationsService();
    final result = await svc.renameFiles(ids, pattern, db: db);
    appLogger.info(
      'Bulk rename: ${result.succeeded} ok, ${result.failed} failed',
    );
    if (result.failed > 0) {
      state = state.copyWith(error: result.errors.join('; '));
    }
  }

  /// Retry a batch of failed/waitingForNetwork downloads.
  /// Returns (succeeded, failed) counts.
  Future<(int, int)> bulkRetry(List<int> ids) async {
    final retryable =
        state.downloads.where((d) => ids.contains(d.id) && d.canRetry).toList();

    int succeeded = 0;
    int failed = 0;

    for (final download in retryable) {
      try {
        await retryDownload(download.id);
        succeeded++;
      } catch (e) {
        failed++;
        appLogger.error('Bulk retry failed for ${download.id}', e);
      }
    }

    appLogger.info('Bulk retry: $succeeded ok, $failed failed');
    return (succeeded, failed);
  }

  // ── Rating Trigger ──

  static const _ratingCountKey = 'rating_completed_count';
  static const _ratingShownKey = 'rating_prompt_shown';
  static const _ratingThreshold = 10;

  /// Serialized post-download pipeline: move → sort → open.
  ///
  /// Order matters: file-move and sorting-rule run first so DB
  /// reflects the final location, THEN open-file/open-folder acts
  /// on that final path. This guarantees the opened folder/file
  /// matches what the DB records.
  void _applyPostCompletionRules(DownloadEntity download) {
    () async {
      final repository = _ref.read(downloadRepositoryProvider);
      var currentDir = download.savePath;
      var currentFilename = download.filename;

      final settings = _ref.read(settingsProvider);
      final action = settings.postDownloadAction;
      final targetFolder =
          settings.postDownloadTargetFolder.isEmpty
              ? null
              : settings.postDownloadTargetFolder;

      // 1. File move (if configured)
      if (targetFolder != null &&
          (action == PostDownloadAction.moveToFolder ||
              action == PostDownloadAction.deleteAfterMove)) {
        final result = await _postDownloadService.executeAction(
          download,
          action,
          targetFolder: targetFolder,
        );
        if (_isDisposed) return;
        if (result.isFailure) {
          appLogger.warning(
            'Post-download move failed: ${result.exceptionOrNull}',
          );
        } else {
          currentDir = targetFolder;
          final locResult = await repository.updateLocation(
            download.id,
            savePath: currentDir,
            filename: currentFilename,
          );
          if (locResult.isFailure) {
            appLogger.warning(
              'DB updateLocation after move failed: '
              '${locResult.exceptionOrNull}',
            );
          }
        }
      }
      if (_isDisposed) return;

      // 2. Sorting rule on the (possibly moved) file
      final rules = _ref.read(sortingRulesProvider);
      final effective = download.copyWith(
        savePath: currentDir,
        filename: currentFilename,
      );
      final matchingRule = _sortingRuleService.findMatchingRule(
        effective,
        rules,
      );
      if (matchingRule != null) {
        final newPath = await _sortingRuleService.applyRule(
          effective,
          matchingRule,
        );
        if (_isDisposed) return;
        final currentPath = p.join(currentDir, currentFilename);
        if (newPath != currentPath) {
          currentDir = p.dirname(newPath);
          currentFilename = p.basename(newPath);
          final locResult = await repository.updateLocation(
            download.id,
            savePath: currentDir,
            filename: currentFilename,
          );
          if (locResult.isFailure) {
            appLogger.warning(
              'DB updateLocation after sorting failed: '
              '${locResult.exceptionOrNull}',
            );
          }
        }
      }
      if (_isDisposed) return;

      // 3. Open file/folder AFTER move+sort so it opens the final path
      if (action == PostDownloadAction.openFile ||
          action == PostDownloadAction.openFolder) {
        final finalDownload = download.copyWith(
          savePath: currentDir,
          filename: currentFilename,
        );
        final result = await _postDownloadService.executeAction(
          finalDownload,
          action,
        );
        if (result.isFailure) {
          appLogger.warning(
            'Post-download open failed: ${result.exceptionOrNull}',
          );
        }
      }
    }();
  }

  void _checkRatingTrigger() {
    try {
      final prefs = _ref.read(sharedPreferencesProvider);
      if (prefs.getBool(_ratingShownKey) == true) return;

      final count = (prefs.getInt(_ratingCountKey) ?? 0) + 1;
      prefs.setInt(_ratingCountKey, count);

      if (count >= _ratingThreshold) {
        prefs.setBool(_ratingShownKey, true);
        _ref.read(ratingTriggerProvider.notifier).state = true;
      }
    } catch (_) {
      // SharedPreferences not available (tests), skip
    }
  }

  /// Submit structured download error to backend for detailed analytics.
  void _submitDownloadError(DownloadEntity download) {
    try {
      final errorCode = DownloadErrorClassifier.classifyMessage(
        download.errorMessage ?? 'unknown',
      );
      _ref
          .read(backendServiceProvider)
          .submitDownloadError(
            url: download.url,
            platform: download.platform,
            errorCode: errorCode.name,
            errorPhase: _classifyDownloadErrorPhase(download, errorCode),
            errorMessage: download.errorMessage ?? 'unknown',
            metadata: _buildDownloadErrorMetadata(download, errorCode),
          );
    } catch (_) {
      // Fire-and-forget — never block download flow
    }
  }

  static String _buildDownloadErrorMetadata(
    DownloadEntity download,
    DownloadErrorCode errorCode,
  ) {
    final storedMessage = download.errorMessage ?? '';
    final detail =
        DownloadErrorCodeX.detailFromStoredMessage(storedMessage) ??
        storedMessage;
    final lower = detail.toLowerCase();

    return jsonEncode({
      'download_method': download.downloadMethod,
      'quality_label': download.qualityLabel,
      'is_ytdlp': download.isYtdlpDownload,
      'is_youtube':
          download.platform == 'youtube' ||
          download.url.contains('youtube.com') ||
          download.url.contains('youtu.be'),
      'has_source_url': download.sourceUrl.isNotEmpty,
      'has_playlist_context': download.playlistId != null,
      'looks_like_http_403': _containsAny(lower, const [
        'http error 403',
        '403: forbidden',
        'http_403_forbidden',
        'status 403',
      ]),
      'looks_like_login_required': _containsAny(lower, const [
        'login required',
        'sign in to confirm',
        'requested authentication',
      ]),
      'looks_like_cookie_db_locked': _containsAny(lower, const [
        'cookie database',
        'could not copy chrome cookie',
        'failed to decrypt with dpapi',
        'cookies.sqlite',
      ]),
      'looks_like_js_runtime_issue': _containsAny(lower, const [
        'n challenge solving failed',
        'signature solving failed',
        'external javascript runtime',
        'no usable javascript runtime',
        'deno:',
      ]),
      'looks_like_format_unavailable': _containsAny(lower, const [
        'format is not available',
        'requested format is not available',
      ]),
      'has_raw_ytdlp_error': lower.contains('raw yt-dlp error'),
      'error_detail_excerpt': _truncateForTelemetry(detail, 500),
      'error_phase': _classifyDownloadErrorPhase(download, errorCode),
      'error_code': errorCode.name,
    });
  }

  static bool _containsAny(String value, List<String> needles) {
    return needles.any(value.contains);
  }

  static String _truncateForTelemetry(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}…';
  }

  static String _classifyDownloadErrorPhase(
    DownloadEntity download,
    DownloadErrorCode code,
  ) {
    // This notifier observes failed DownloadEntity records. For yt-dlp records,
    // auth/403/format errors can surface from the download subprocess after
    // extraction already succeeded, so keep structured telemetry aligned with
    // StartDownloadUseCase's direct download-stage sink. Extraction failures
    // have a separate ExtractVideoInfoUseCase telemetry path.
    if (download.isYtdlpDownload) {
      return switch (code) {
        DownloadErrorCode.loginRequired ||
        DownloadErrorCode.accessDenied ||
        DownloadErrorCode.formatUnavailable ||
        DownloadErrorCode.cookieDbLocked ||
        DownloadErrorCode.jsRuntimeUnavailable => 'download',
        _ => _classifyErrorPhase(code),
      };
    }
    return _classifyErrorPhase(code);
  }

  /// Map error code to error phase for backend structured tracking.
  static String _classifyErrorPhase(DownloadErrorCode code) {
    return switch (code) {
      DownloadErrorCode.videoNotFound ||
      DownloadErrorCode.geoRestricted ||
      DownloadErrorCode.loginRequired ||
      DownloadErrorCode.ageRestricted ||
      DownloadErrorCode.formatUnavailable ||
      DownloadErrorCode.accessDenied ||
      DownloadErrorCode.contentUnavailable ||
      DownloadErrorCode.rateLimited ||
      DownloadErrorCode.ytdlpBinaryMissing ||
      DownloadErrorCode.binaryNotAvailable ||
      DownloadErrorCode.jsRuntimeUnavailable ||
      DownloadErrorCode.cookieDbLocked => 'extraction',
      DownloadErrorCode.networkOffline ||
      DownloadErrorCode.networkTimeout ||
      DownloadErrorCode.serverError ||
      DownloadErrorCode.connectionRefused ||
      DownloadErrorCode.sslError => 'download',
      DownloadErrorCode.ffmpegError => 'conversion',
      DownloadErrorCode.diskFull ||
      DownloadErrorCode.permissionDenied ||
      DownloadErrorCode.pathNotFound => 'post_process',
      DownloadErrorCode.unknown => 'unknown',
    };
  }
}

/// Provider for downloads notifier
final downloadsNotifierProvider =
    StateNotifierProvider<DownloadsNotifier, DownloadsState>((ref) {
      return DownloadsNotifier(ref);
    });
