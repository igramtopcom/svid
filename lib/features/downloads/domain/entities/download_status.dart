import '../../../../core/l10n/app_localizations.dart';

/// Download status enum
enum DownloadStatus {
  /// Download is waiting to start
  pending,

  /// Download is queued (waiting for available slot)
  queued,

  /// Download is in progress
  downloading,

  /// Post-processing (FFmpeg converting/merging) — generic catch-all
  /// kept for backwards compatibility with rows persisted before
  /// RC10.3. Newer code uses [merging] / [remuxing] / [converting]
  /// for the specific phase.
  postProcessing,

  /// RC10.3 of Ultra Plan v3 — FFmpeg merging video + audio streams
  /// (stream-copy combine, typically 1-2 seconds). Emitted when
  /// yt-dlp stdout shows `[Merger] Merging formats into ...`.
  merging,

  /// RC10.3 of Ultra Plan v3 — FFmpeg remuxing (changing container
  /// without re-encoding, fast — 1-2 seconds). Emitted when yt-dlp
  /// stdout shows `[VideoRemuxer] Remuxing video into ...`.
  remuxing,

  /// RC10.3 of Ultra Plan v3 — FFmpeg full transcode (re-encoding
  /// video / audio codec, slow — minutes for 1080p). Emitted when
  /// yt-dlp stdout shows `[VideoConvertor] Converting video from
  /// ... to ...`. Distinguishing this from merge/remux closes the
  /// "Processing tưởng treo" UX gap where user couldn't tell if
  /// app was hung vs running a long-but-correct transcode.
  converting,

  /// Download is paused
  paused,

  /// Download completed successfully
  completed,

  /// Download failed with error
  failed,

  /// Download was cancelled by user
  cancelled,

  /// Download failed due to network error, will auto-retry when online
  waitingForNetwork;

  /// Convert status to string for database storage
  String toDbString() => name;

  /// Parse status from database string
  static DownloadStatus fromDbString(String value) {
    return DownloadStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => DownloadStatus.pending,
    );
  }

  /// Check if status is terminal (completed, failed, or cancelled)
  /// Note: waitingForNetwork is NOT terminal — it will auto-resume.
  bool get isTerminal => this == DownloadStatus.completed ||
                         this == DownloadStatus.failed ||
                         this == DownloadStatus.cancelled;

  /// Check if status is active (pending, queued, downloading, or any
  /// post-processing phase). RC10.3 added [merging] / [remuxing] /
  /// [converting] as specific phases of [postProcessing] — all 4 are
  /// "active" from the lifecycle perspective (download row should
  /// not be auto-cancelled or marked failed during these states).
  bool get isActive => this == DownloadStatus.pending ||
                       this == DownloadStatus.queued ||
                       this == DownloadStatus.downloading ||
                       this == DownloadStatus.postProcessing ||
                       this == DownloadStatus.merging ||
                       this == DownloadStatus.remuxing ||
                       this == DownloadStatus.converting;

  /// True when status is any post-processing phase (legacy generic
  /// [postProcessing] OR specific [merging] / [remuxing] /
  /// [converting]). Used by recovery / queue logic that previously
  /// matched only `postProcessing` — now needs to recognize the new
  /// sub-states too.
  bool get isPostProcessingPhase =>
      this == DownloadStatus.postProcessing ||
      this == DownloadStatus.merging ||
      this == DownloadStatus.remuxing ||
      this == DownloadStatus.converting;

  /// Get display label for UI (localized via AppLocalizations).
  String get displayLabel {
    switch (this) {
      case DownloadStatus.pending:
        return AppLocalizations.statusPending;
      case DownloadStatus.queued:
        return AppLocalizations.statusQueued;
      case DownloadStatus.downloading:
        return AppLocalizations.statusActive;
      case DownloadStatus.postProcessing:
        return AppLocalizations.statusPostProcessing;
      case DownloadStatus.merging:
        return AppLocalizations.statusMerging;
      case DownloadStatus.remuxing:
        return AppLocalizations.statusRemuxing;
      case DownloadStatus.converting:
        return AppLocalizations.statusConverting;
      case DownloadStatus.paused:
        return AppLocalizations.statusPaused;
      case DownloadStatus.completed:
        return AppLocalizations.statusCompleted;
      case DownloadStatus.failed:
        return AppLocalizations.statusFailed;
      case DownloadStatus.cancelled:
        return AppLocalizations.statusCancelled;
      case DownloadStatus.waitingForNetwork:
        return AppLocalizations.statusWaitingForNetwork;
    }
  }
}
