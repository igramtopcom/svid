import 'dart:convert';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'download_error_code.dart';
import 'download_status.dart';
import 'recurrence_rule.dart';
import 'video_info.dart';

part 'download_entity.freezed.dart';

/// Domain entity for a download
@freezed
class DownloadEntity with _$DownloadEntity {
  const DownloadEntity._();

  const factory DownloadEntity({
    required int id,
    required String url,
    required String filename,
    required String savePath,
    required DownloadStatus status,
    required int totalBytes,
    required int downloadedBytes,
    required int speed,
    String? thumbnail,
    @Default('unknown') String platform,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? errorMessage,
    @Default(0) int retryCount,

    // Rich metadata (added for yt-dlp integration)
    String? title, // Video title
    String? description, // Video description
    String? uploader, // Channel/uploader name
    int? duration, // Duration in seconds
    int? viewCount, // View count
    String? uploadDate, // Upload date (YYYYMMDD format)
    @Default('unknown') String downloadMethod, // 'ytdlp', 'api', 'unknown'
    String? qualityLabel, // e.g., "1080p", "720p", "Audio Only"
    String? chaptersJson, // Serialized List<{title, startTime, endTime}>
    @Default('') String userNote, // Personal note on this download
    @Default(false) bool isWatched, // True when ≥90% (or ≥80% for short clips) watched
    DateTime? scheduledAt, // Scheduled start time (null = not scheduled)
    int? queuePosition, // D&D queue position (null = unordered, sorts after positioned items)
    @Default('') String sourceUrl, // Original page URL for Rust downloads (empty for ytdlp/unknown)
    @Default(0) int priority, // User-set priority: 1=high, 0=normal, -1=low
    String? recurrenceRuleJson, // Serialized RecurrenceRule (null = no recurrence)
    String? tempDirPath, // Isolated temp dir for yt-dlp resume (null = not applicable)
    // Playlist context (v19) — when this download was queued from a
    // YouTube playlist (or equivalent collection), these fields tag
    // it with a shared playlistId so the download manager can group
    // and filter by playlist. Null for ad-hoc single-URL downloads.
    String? playlistId,
    String? playlistTitle,
    int? playlistIndex,
  }) = _DownloadEntity;

  /// Calculate download progress (0.0 to 1.0)
  double get progress {
    if (totalBytes <= 0) return 0.0;
    return (downloadedBytes / totalBytes).clamp(0.0, 1.0);
  }

  /// Calculate progress percentage (0 to 100)
  double get progressPercentage => progress * 100;

  /// Check if download is active (downloading, pending, or any
  /// post-processing phase). RC10 Blocker 2 — `merging` / `remuxing`
  /// / `converting` are sub-states of post-processing introduced in
  /// RC10.3; all three count as active because yt-dlp/ffmpeg is
  /// still running and the row holds a queue slot.
  bool get isActive =>
      status == DownloadStatus.downloading ||
      status == DownloadStatus.pending ||
      status.isPostProcessingPhase;

  /// Check if download is completed
  bool get isCompleted => status == DownloadStatus.completed;

  /// Check if download is paused
  bool get isPaused => status == DownloadStatus.paused;

  /// Check if download has failed
  bool get isFailed => status == DownloadStatus.failed;

  /// Check if download was cancelled
  bool get isCancelled => status == DownloadStatus.cancelled;

  /// Check if download can be resumed (paused, failed, or stuck pending)
  bool get canResume => status == DownloadStatus.paused ||
      status == DownloadStatus.failed ||
      status == DownloadStatus.pending;

  /// Whether this download is waiting for its scheduled start time
  bool get isScheduled => scheduledAt != null && status == DownloadStatus.pending;

  /// Parsed error code from structured errorMessage (format: `errorCode:rawMessage`)
  DownloadErrorCode? get errorCode => DownloadErrorCodeX.fromStoredMessage(errorMessage);

  /// Raw error detail extracted from structured errorMessage
  String? get errorDetail => DownloadErrorCodeX.detailFromStoredMessage(errorMessage);

  /// Whether this download is waiting for network reconnect
  bool get isWaitingForNetwork => status == DownloadStatus.waitingForNetwork;

  /// Check if download can be paused.
  ///
  /// RC10 Blocker 2 — only the bytes-download phase is pausable.
  /// Post-process phases (merging/remuxing/converting) are NOT
  /// pausable because ffmpeg has no resume semantics for partial
  /// merge/recode work — pausing during conversion would corrupt
  /// the intermediate. Surfacing the pause button only during
  /// `downloading` aligns the action with what's actually safe.
  bool get canPause => status == DownloadStatus.downloading;

  /// Check if download can be cancelled.
  ///
  /// RC10 Blocker 2 — post-process sub-states (merging/remuxing/
  /// converting) MUST allow cancel because:
  ///   1. Transcode can take many minutes; user needs an escape hatch.
  ///   2. The ffmpeg process is alive and responds to SIGTERM —
  ///      cancellation is safe.
  ///   3. Without this, the row appears uncancellable during the
  ///      slowest phase exactly when users want to bail.
  bool get canCancel =>
      status == DownloadStatus.pending ||
      status == DownloadStatus.queued ||
      status == DownloadStatus.downloading ||
      status.isPostProcessingPhase ||
      status == DownloadStatus.paused ||
      status == DownloadStatus.waitingForNetwork;

  /// Check if download can be retried
  bool get canRetry => status == DownloadStatus.failed || status == DownloadStatus.waitingForNetwork;

  /// Check if download can be deleted.
  ///
  /// RC10 Blocker 2 — block delete during ALL live phases, not just
  /// `downloading`. Deleting a row while merging/remuxing/converting
  /// would leave orphaned ffmpeg processes + partial temp files.
  /// User must cancel first (which terminates the process cleanly),
  /// then delete.
  bool get canDelete =>
      status != DownloadStatus.downloading &&
      !status.isPostProcessingPhase;

  /// Get remaining bytes to download
  int get remainingBytes => totalBytes - downloadedBytes;

  /// Estimate remaining time based on current speed (in seconds)
  int? get estimatedRemainingSeconds {
    if (speed <= 0 || remainingBytes <= 0) return null;
    return remainingBytes ~/ speed;
  }

  /// Get file extension
  String get fileExtension {
    final parts = filename.split('.');
    return parts.length > 1 ? '.${parts.last.toLowerCase()}' : '';
  }

  /// Get filename without extension
  String get filenameWithoutExtension {
    final parts = filename.split('.');
    return parts.length > 1 ? parts.sublist(0, parts.length - 1).join('.') : filename;
  }

  // ==================== RICH METADATA HELPERS ====================

  /// Get display title (use title if available, otherwise filename)
  String get displayTitle => title ?? filenameWithoutExtension;

  /// Get formatted duration string (e.g., "12:34" or "1:23:45")
  String? get formattedDuration {
    if (duration == null || duration! <= 0) return null;
    final hours = duration! ~/ 3600;
    final minutes = (duration! % 3600) ~/ 60;
    final seconds = duration! % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Get formatted view count (e.g., "1.2M views", "500K views")
  String? get formattedViewCount {
    if (viewCount == null || viewCount! <= 0) return null;
    if (viewCount! >= 1000000000) {
      return '${(viewCount! / 1000000000).toStringAsFixed(1)}B views';
    }
    if (viewCount! >= 1000000) {
      return '${(viewCount! / 1000000).toStringAsFixed(1)}M views';
    }
    if (viewCount! >= 1000) {
      return '${(viewCount! / 1000).toStringAsFixed(1)}K views';
    }
    return '$viewCount views';
  }

  /// Get formatted upload date
  DateTime? get parsedUploadDate {
    if (uploadDate == null || uploadDate!.length != 8) return null;
    try {
      return DateTime(
        int.parse(uploadDate!.substring(0, 4)),
        int.parse(uploadDate!.substring(4, 6)),
        int.parse(uploadDate!.substring(6, 8)),
      );
    } catch (_) {
      return null;
    }
  }

  /// Check if downloaded via yt-dlp
  bool get isYtdlpDownload => downloadMethod == 'ytdlp';

  /// Check if downloaded via gallery-dl
  bool get isGalleryDlDownload => downloadMethod == 'gallerydl';

  // ==================== CHAPTER HELPERS ====================

  /// Parse chapters from JSON string
  List<ChapterInfo> get chapters {
    if (chaptersJson == null || chaptersJson!.isEmpty) return [];
    try {
      final list = jsonDecode(chaptersJson!) as List;
      return list.map((e) => ChapterInfo(
        title: e['title'] as String? ?? '',
        startTime: (e['startTime'] as num?)?.toDouble() ?? 0.0,
        endTime: (e['endTime'] as num?)?.toDouble() ?? 0.0,
      )).toList();
    } catch (_) {
      return [];
    }
  }

  /// Check if download has chapter data
  bool get hasChapters => chaptersJson != null && chaptersJson!.isNotEmpty;

  // ==================== RECURRENCE HELPERS ====================

  /// Parsed recurrence rule (null = not a recurring download)
  RecurrenceRule? get recurrenceRule {
    if (recurrenceRuleJson == null || recurrenceRuleJson!.isEmpty) return null;
    try {
      return RecurrenceRule.fromJson(recurrenceRuleJson!);
    } catch (_) {
      return null;
    }
  }

  /// Whether this download recurs after firing
  bool get isRecurring => recurrenceRule?.isRecurring ?? false;
}
