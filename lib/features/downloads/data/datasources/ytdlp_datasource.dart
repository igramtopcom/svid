import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:svid/bridge/api.dart' as native;

import '../../../../core/binaries/binaries.dart';
import '../../../../core/config/brand_config.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/services/circuit_breaker_service.dart';
import '../../../../core/services/user_agent_service.dart';
import '../../../../core/utils/file_utils.dart';
import '../../../../core/utils/platform_detector.dart';
import '../../../../core/utils/process_helper.dart';
import '../../domain/services/container_planner.dart';
import '../../domain/services/download_referer_holder.dart';
import '../../domain/services/resolution_filter_utils.dart';
import '../remote/ytdlp/youtube_pot_provider_service.dart';

/// Error types that can occur during yt-dlp operations
enum YtDlpErrorType {
  notFound,
  geoRestricted,
  loginRequired,
  ageRestricted,
  formatNotAvailable,
  networkError,
  rateLimited,
  binaryNotFound,
  timeout,

  /// App's own circuit breaker is open after consecutive platform-broken
  /// failures. Distinct from [rateLimited] (which is YouTube/platform-side).
  /// UI should show "App đang cooldown — quá nhiều lần fail liên tục"
  /// with countdown, separate from "YouTube đang giới hạn" UX.
  circuitBreakerOpen,

  /// External JS runtime (Deno) is unavailable — bundled binary failed
  /// to download/extract, or yt-dlp itself reports it cannot solve JS
  /// challenges. Distinct from `loginRequired` because the underlying
  /// signal is "this app cannot decrypt YouTube nsig", NOT "user needs
  /// to log in". Surfacing this prevents the auto-login flow from
  /// looping (logging in further does nothing without a JS runtime).
  /// UI should prompt user to retry / report (Settings → Diagnostics)
  /// rather than re-trigger login.
  jsRuntimeUnavailable,
  unknown,
}

/// Exception thrown by yt-dlp operations
class YtDlpException implements Exception {
  final YtDlpErrorType type;
  final String message;
  final Map<String, dynamic> metadata;

  YtDlpException(this.type, this.message, {Map<String, dynamic>? metadata})
    : metadata = Map.unmodifiable(metadata ?? const {});

  /// Check if this error can potentially be fixed by using API fallback
  bool get canFallbackToApi {
    switch (type) {
      case YtDlpErrorType.binaryNotFound:
      case YtDlpErrorType.notFound:
      case YtDlpErrorType.geoRestricted:
      case YtDlpErrorType.loginRequired:
      case YtDlpErrorType.timeout:
      case YtDlpErrorType.rateLimited:
        return true;
      case YtDlpErrorType.ageRestricted:
      case YtDlpErrorType.formatNotAvailable:
      case YtDlpErrorType.networkError:
      case YtDlpErrorType.circuitBreakerOpen:
      case YtDlpErrorType.jsRuntimeUnavailable:
      case YtDlpErrorType.unknown:
        return false;
    }
  }

  @override
  String toString() => 'YtDlpException($type): $message';

  factory YtDlpException.fromErrorType(String? errorType, String? message) {
    final type = switch (errorType) {
      'NotFound' => YtDlpErrorType.notFound,
      'GeoRestricted' => YtDlpErrorType.geoRestricted,
      'LoginRequired' => YtDlpErrorType.loginRequired,
      'AgeRestricted' => YtDlpErrorType.ageRestricted,
      'FormatNotAvailable' => YtDlpErrorType.formatNotAvailable,
      'NetworkError' => YtDlpErrorType.networkError,
      'RateLimited' => YtDlpErrorType.rateLimited,
      'JsRuntimeUnavailable' ||
      'jsRuntimeUnavailable' => YtDlpErrorType.jsRuntimeUnavailable,
      _ => YtDlpErrorType.unknown,
    };
    return YtDlpException(type, message ?? 'Unknown error');
  }
}

/// Format/quality option from yt-dlp
class YtDlpFormat {
  final String formatId;
  final String ext;
  final String? resolution;
  final int? height;
  final int? width;
  final int? filesize;
  final String? vcodec;
  final String? acodec;
  final double? fps;
  final double? tbr;
  final String? formatNote;

  YtDlpFormat({
    required this.formatId,
    required this.ext,
    this.resolution,
    this.height,
    this.width,
    this.filesize,
    this.vcodec,
    this.acodec,
    this.fps,
    this.tbr,
    this.formatNote,
  });

  factory YtDlpFormat.fromDto(native.YtDlpFormatDto dto) {
    return YtDlpFormat(
      formatId: dto.formatId,
      ext: dto.ext,
      resolution: dto.resolution,
      height: dto.height,
      width: dto.width,
      filesize: dto.filesize?.toInt(),
      vcodec: dto.vcodec,
      acodec: dto.acodec,
      fps: dto.fps,
      tbr: dto.tbr,
      formatNote: dto.formatNote,
    );
  }

  /// Check if this is a video-only format (no audio)
  bool get isVideoOnly =>
      acodec == 'none' ||
      (acodec == null && vcodec != null && vcodec != 'none');

  /// Check if this is an audio-only format
  bool get isAudioOnly =>
      vcodec == 'none' ||
      (vcodec == null && acodec != null && acodec != 'none');

  /// Check if this has both video and audio
  bool get hasBoth => !isVideoOnly && !isAudioOnly;

  /// Get quality label (e.g., "2160p", "1080p60")
  String get qualityLabel {
    if (formatNote != null && formatNote!.isNotEmpty) {
      return formatNote!;
    }
    if (height != null) {
      final fpsLabel = fps != null && fps! > 30 ? '${fps!.round()}' : '';
      return '$height'
          'p$fpsLabel';
    }
    return resolution ?? formatId;
  }
}

/// Subtitle track information
class YtDlpSubtitleInfo {
  final String lang;
  final String? langName;
  final String ext;
  final String? url;

  YtDlpSubtitleInfo({
    required this.lang,
    this.langName,
    required this.ext,
    this.url,
  });

  factory YtDlpSubtitleInfo.fromDto(native.SubtitleInfoDto dto) {
    return YtDlpSubtitleInfo(
      lang: dto.lang,
      langName: dto.langName,
      ext: dto.ext,
      url: dto.url,
    );
  }
}

/// Chapter information
class YtDlpChapterInfo {
  final String title;
  final double startTime; // seconds
  final double endTime; // seconds

  YtDlpChapterInfo({
    required this.title,
    required this.startTime,
    required this.endTime,
  });

  factory YtDlpChapterInfo.fromDto(native.ChapterInfoDto dto) {
    return YtDlpChapterInfo(
      title: dto.title,
      startTime: dto.startTime,
      endTime: dto.endTime,
    );
  }

  /// Get chapter duration
  Duration get duration => Duration(seconds: (endTime - startTime).round());

  /// Format start time as HH:MM:SS or MM:SS
  String get formattedStartTime {
    final totalSeconds = startTime.round();
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Video information extracted by yt-dlp
class YtDlpVideoInfo {
  final String id;
  final String title;
  final String? description;
  final String? uploader;
  final String? uploaderId;
  final Duration? duration;
  final int? viewCount;
  final int? likeCount;
  final DateTime? uploadDate;
  final String? thumbnail;
  final String? webpageUrl;
  final String platform;
  final List<YtDlpFormat> formats;
  // P1 features
  final List<YtDlpSubtitleInfo> subtitles;
  final List<YtDlpSubtitleInfo> automaticCaptions;
  final List<YtDlpChapterInfo> chapters;
  final bool isLive;
  final String? liveStatus; // is_live, was_live, is_upcoming

  YtDlpVideoInfo({
    required this.id,
    required this.title,
    this.description,
    this.uploader,
    this.uploaderId,
    this.duration,
    this.viewCount,
    this.likeCount,
    this.uploadDate,
    this.thumbnail,
    this.webpageUrl,
    required this.platform,
    required this.formats,
    this.subtitles = const [],
    this.automaticCaptions = const [],
    this.chapters = const [],
    this.isLive = false,
    this.liveStatus,
  });

  factory YtDlpVideoInfo.fromDto(native.YtDlpVideoInfoDto dto) {
    DateTime? uploadDate;
    if (dto.uploadDate != null && dto.uploadDate!.length == 8) {
      // Parse YYYYMMDD format
      try {
        uploadDate = DateTime(
          int.parse(dto.uploadDate!.substring(0, 4)),
          int.parse(dto.uploadDate!.substring(4, 6)),
          int.parse(dto.uploadDate!.substring(6, 8)),
        );
      } catch (_) {}
    }

    return YtDlpVideoInfo(
      id: dto.id,
      title: dto.title,
      description: dto.description,
      uploader: dto.uploader,
      uploaderId: dto.uploaderId,
      duration:
          dto.duration != null
              ? Duration(seconds: dto.duration!.toInt())
              : null,
      viewCount: dto.viewCount?.toInt(),
      likeCount: dto.likeCount?.toInt(),
      uploadDate: uploadDate,
      thumbnail: dto.thumbnail,
      webpageUrl: dto.webpageUrl,
      platform: _extractPlatform(dto.extractor),
      formats: dto.formats.map((f) => YtDlpFormat.fromDto(f)).toList(),
      // P1 features
      subtitles:
          dto.subtitles.map((s) => YtDlpSubtitleInfo.fromDto(s)).toList(),
      automaticCaptions:
          dto.automaticCaptions
              .map((s) => YtDlpSubtitleInfo.fromDto(s))
              .toList(),
      chapters:
          dto.chapters
              .map((c) => YtDlpChapterInfo.fromDto(c))
              .where((c) => c.endTime > c.startTime)
              .toList(),
      isLive: dto.isLive,
      liveStatus: dto.liveStatus,
    );
  }

  /// Get best video formats grouped by quality (e.g., 2160p, 1080p, 720p)
  List<YtDlpFormat> get videoFormats {
    return formats
        .where((f) => f.height != null && f.height! > 0)
        .where((f) => f.vcodec != null && f.vcodec != 'none')
        .toList()
      ..sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));
  }

  /// Get best audio formats
  List<YtDlpFormat> get audioFormats {
    return formats.where((f) => f.isAudioOnly).toList()
      ..sort((a, b) => (b.tbr ?? 0).compareTo(a.tbr ?? 0));
  }

  static String _extractPlatform(String? extractor) {
    if (extractor == null) return 'unknown';
    final lower = extractor.toLowerCase();
    if (lower.contains('youtube')) return 'youtube';
    if (lower.contains('tiktok')) return 'tiktok';
    if (lower.contains('instagram')) return 'instagram';
    if (lower.contains('facebook')) return 'facebook';
    if (lower.contains('twitter') || lower == 'x') return 'twitter';
    if (lower.contains('reddit')) return 'reddit';
    if (lower.contains('pinterest')) return 'pinterest';
    return lower;
  }
}

/// Download progress information
class YtDlpProgress {
  final double percent;
  final int? downloadedBytes;
  final int? totalBytes;
  final double? speed; // bytes per second
  final Duration? eta;
  final YtDlpDownloadStatus status;

  YtDlpProgress({
    required this.percent,
    this.downloadedBytes,
    this.totalBytes,
    this.speed,
    this.eta,
    required this.status,
  });

  factory YtDlpProgress.fromDto(native.YtDlpProgressDto dto) {
    return YtDlpProgress(
      percent: dto.percent,
      downloadedBytes: dto.downloadedBytes?.toInt(),
      totalBytes: dto.totalBytes?.toInt(),
      speed: dto.speed,
      eta:
          dto.etaSeconds != null
              ? Duration(seconds: dto.etaSeconds!.toInt())
              : null,
      status: YtDlpDownloadStatus.fromString(dto.status),
    );
  }
}

enum YtDlpDownloadStatus {
  downloading,
  postProcessing,

  /// RC10.3 — specific post-process phases detected from yt-dlp
  /// stdout markers. Distinguishing these from generic
  /// [postProcessing] lets the UI show "Merging" / "Remuxing" /
  /// "Converting" instead of a single opaque "Processing".
  merging,
  remuxing,
  converting,
  finished,
  error;

  factory YtDlpDownloadStatus.fromString(String status) {
    return switch (status) {
      'downloading' => YtDlpDownloadStatus.downloading,
      'postprocessing' => YtDlpDownloadStatus.postProcessing,
      'finished' => YtDlpDownloadStatus.finished,
      'error' => YtDlpDownloadStatus.error,
      _ => YtDlpDownloadStatus.downloading,
    };
  }
}

/// Result of [YtDlpDataSource.resolveEmbedCompatibility] — encapsulates
/// the effective output extension and the three `--embed-*` flag
/// permissions. Immutable record-style so it survives test fixture
/// comparison via field accessors.
class EmbedCompatibility {
  /// Lowercased extension that yt-dlp will write the final file with
  /// (post-recode for non-native containers). Useful in error messages.
  final String effectiveExt;
  final bool canEmbedThumbnail;
  final bool canEmbedSubs;
  final bool canEmbedChapters;

  const EmbedCompatibility({
    required this.effectiveExt,
    required this.canEmbedThumbnail,
    required this.canEmbedSubs,
    required this.canEmbedChapters,
  });
}

/// Datasource for yt-dlp operations
/// Uses BinaryManager for binary lifecycle management
/// RC10 Q-round C3 — value type returned by the final-extension
/// guard helper `YtDlpDataSource._detectFinalExtensionMismatch`.
/// Both fields are lowercase, dot-stripped (e.g. `webm`, `mp4`).
/// Public so unit tests can pin the helper's behavior.
class ExtensionMismatch {
  final String expected;
  final String actual;
  const ExtensionMismatch({required this.expected, required this.actual});
}

class ResolutionCapViolation {
  final int expectedMaxShortSide;
  final int actualWidth;
  final int actualHeight;
  final bool dimensionsUnavailable;

  const ResolutionCapViolation({
    required this.expectedMaxShortSide,
    required this.actualWidth,
    required this.actualHeight,
    this.dimensionsUnavailable = false,
  });

  int get actualShortSide => min(actualWidth, actualHeight);
}

class _VideoDimensions {
  final int width;
  final int height;

  const _VideoDimensions({required this.width, required this.height});
}

class YtDlpDataSource {
  final BinaryManager _binaryManager;
  final CircuitBreakerService? _circuitBreaker;
  final UserAgentService _userAgentService;
  final YouTubePotProviderService _youtubePotProviderService;

  String? _binaryPath;
  String? _ffmpegPath;
  String? _version;
  YouTubePotProviderPaths? _youtubePotProviderPaths;

  /// Path to the app-managed Deno binary, retrieved from [BinaryManager]
  /// during [initialize]. yt-dlp 2025.11.12+ requires an external JS
  /// runtime for full YouTube extraction (n-challenge / nsig signature
  /// solving). Without this, logged-in YouTube returns only storyboard
  /// formats — see `feedback_diff_verbose_output_before_speculate.md`.
  ///
  /// Null when Deno is unavailable (download failed, Intel Mac without
  /// arch-specific build, etc). Callers must treat YouTube extraction as
  /// degraded in that case and surface `YtDlpErrorType.jsRuntimeUnavailable`
  /// to the UI instead of pretending login is needed.
  String? _denoPath;

  /// Track process keys that were explicitly cancelled by the user.
  /// This prevents exit code 1 on Windows (TerminateProcess) from being
  /// confused with FFmpeg/yt-dlp errors that also return exit code 1.
  final Set<String> _cancelledProcessKeys = {};

  /// Matches the `time=HH:MM:SS.MS` token in ffmpeg progress lines
  /// (e.g. `frame=  234 fps= 30 q=28.0 size=1024kB time=00:00:07.80 bitrate=...`).
  ///
  /// Used as a fallback progress source when yt-dlp delegates section
  /// downloads to ffmpeg — at that point yt-dlp's own `[download] X% ...`
  /// lines stop and the Rust progress parser sees nothing, so the UI freezes
  /// mid-download. We parse ffmpeg's elapsed time and divide by the section
  /// duration to synthesise a percent value.
  static final RegExp _ffmpegTimeRegex = RegExp(
    r'time=(\d+):(\d+):(\d+)\.(\d+)',
  );

  // Best-effort perf marker. Two concurrent cold-start extracts may both
  // observe true; the signal is for coarse cold/warm log analysis only.
  static bool _isFirstExtractSinceAppStart = true;

  YtDlpDataSource(
    this._binaryManager, {
    CircuitBreakerService? circuitBreaker,
    UserAgentService? userAgentService,
    YouTubePotProviderService? youtubePotProviderService,
  }) : _circuitBreaker = circuitBreaker,
       _userAgentService = userAgentService ?? UserAgentService(),
       _youtubePotProviderService =
           youtubePotProviderService ?? YouTubePotProviderService();

  /// Initialize - get binary paths from BinaryManager
  Future<void> initialize() async {
    await _binaryManager.initialize();

    _binaryPath = await _binaryManager.getBinaryPath(BinaryType.ytDlp);
    _ffmpegPath = await _binaryManager.getBinaryPath(BinaryType.ffmpeg);
    _denoPath = await _binaryManager.getBinaryPath(BinaryType.deno);

    if (_binaryPath != null) {
      debugPrint('✅ [YtDlp] Binary path: $_binaryPath');
      _version = await _binaryManager.getVersion(BinaryType.ytDlp);
      debugPrint('✅ [YtDlp] Version: $_version');
    } else {
      debugPrint('❌ [YtDlp] Binary not available - needs download');
    }
    if (_denoPath != null) {
      debugPrint('✅ [YtDlp] Deno JS runtime: $_denoPath');
    } else {
      debugPrint(
        '⚠️ [YtDlp] Deno JS runtime not available — '
        'YouTube logged-in extraction will degrade to storyboards. '
        'See feedback_diff_verbose_output_before_speculate.md for context.',
      );
    }

    if (_ffmpegPath != null) {
      debugPrint('✅ [YtDlp] FFmpeg path: $_ffmpegPath');
    } else {
      debugPrint(
        '⚠️ [YtDlp] FFmpeg not available - some features may be limited',
      );
    }

    _youtubePotProviderPaths = await _youtubePotProviderService.ensureInstalled(
      downloadIfMissing: false,
    );
    if (_youtubePotProviderPaths != null) {
      appLogger.info(
        '[YtDlp] YouTube POT provider ready: '
        'cli=${_youtubePotProviderPaths!.cliPath} '
        'pluginDir=${_youtubePotProviderPaths!.pluginDir}',
      );
    }

    // Clean up stale temp files from previous sessions (best-effort).
    // Active download temp dirs are not known at init time — the repository
    // calls cleanupTempDownloads(activeTempDirs: ...) after recovery.
    cleanupTempDownloads();
  }

  static final _random = Random();

  /// Create an isolated temp directory for a single download.
  /// Each download gets its own subdir to prevent cross-contamination.
  /// Uses system temp (never cloud-synced) so Dropbox/OneDrive/Google Drive
  /// cannot lock files during download/merge/rename.
  ///
  /// If [existingTempDir] is provided and still exists with .part files,
  /// reuse it so yt-dlp --continue can resume from partial downloads.
  Future<String> _createIsolatedTempDir({
    int? downloadId,
    String? existingTempDir,
  }) async {
    // Resume path: reuse existing temp dir if it has .part files
    if (existingTempDir != null && existingTempDir.isNotEmpty) {
      final dir = Directory(existingTempDir);
      if (await dir.exists()) {
        // Check for .part files (yt-dlp partial downloads)
        final hasPartFiles = await dir.list().any(
          (e) => e is File && e.path.endsWith('.part'),
        );
        if (hasPartFiles) {
          debugPrint(
            '♻️ [YtDlp] Reusing temp dir with .part files: $existingTempDir',
          );
          return existingTempDir;
        }
        // Dir exists but no .part files — still reuse (might have other state)
        debugPrint('♻️ [YtDlp] Reusing existing temp dir: $existingTempDir');
        return existingTempDir;
      }
      // Dir was deleted (e.g., OS cleanup) — fall through to create new one
      debugPrint(
        '⚠️ [YtDlp] Previous temp dir gone, creating new: $existingTempDir',
      );
    }

    final tempBase = path.join(
      Directory.systemTemp.path,
      '${BrandConfig.current.brand.name}_downloads',
    );
    final id = downloadId ?? DateTime.now().millisecondsSinceEpoch;
    final uniqueDir = path.join(tempBase, '${id}_${_random.nextInt(99999)}');
    await Directory(uniqueDir).create(recursive: true);
    return uniqueDir;
  }

  /// Worst-case length proxy for the isolated temp dir [_createIsolatedTempDir]
  /// creates: `<systemTemp>/<brand>_downloads/<id>_<rand>`, with the id and rand
  /// at their maximum widths. `DateTime.now().millisecondsSinceEpoch` is 13
  /// digits (and stays 13 until year 2286); `_random.nextInt(99999)` is at most
  /// 5 digits — so `9999999999999_99999` is a strict UPPER bound on the real
  /// suffix and this proxy never UNDER-estimates the path length. Used by the
  /// WIN-1/DL-007 budget so a download to a SHALLOW save folder still reserves
  /// room for the deep AppData temp path where files are physically written +
  /// merged first. Mirror of the construction above — keep the two in lockstep.
  static String worstCaseIsolatedTempDir() => path.join(
    Directory.systemTemp.path,
    '${BrandConfig.current.brand.name}_downloads',
    '9999999999999_99999',
  );

  /// Clean up stale temp download dirs older than 24 hours.
  /// [activeTempDirs] are paths belonging to in-progress downloads — skip them.
  /// Public so repository can call after recovery with persisted temp dir paths.
  void cleanupTempDownloads({Set<String> activeTempDirs = const {}}) {
    () async {
      try {
        final tempDir = Directory(
          path.join(
            Directory.systemTemp.path,
            '${BrandConfig.current.brand.name}_downloads',
          ),
        );
        if (!await tempDir.exists()) return;
        final cutoff = DateTime.now().subtract(const Duration(hours: 24));
        await for (final entity in tempDir.list()) {
          try {
            // Never delete temp dirs that belong to active/queued downloads
            if (activeTempDirs.contains(entity.path)) continue;
            final stat = await entity.stat();
            if (stat.modified.isBefore(cutoff)) {
              await entity.delete(recursive: true);
            }
          } catch (_) {
            // Skip entries that can't be stat'd or deleted
          }
        }
      } catch (_) {
        // Best-effort cleanup — don't fail initialization
      }
    }();
  }

  /// 2026-05-26 Codex round-2 P1.2 fix — concurrency lock per
  /// normalized output dir. With the duplicate guard removed at
  /// Home + Floating Capture, two parallel downloads of the same
  /// URL can finish at the same time and both compute suffix
  /// against the same disk state — classic TOCTOU race that would
  /// overwrite the first file. Serialize all moves to the same
  /// output dir so the second move sees the first's landed files
  /// and picks the next free suffix.
  ///
  /// Key is normalized absolute path so `/foo/bar` and `/foo/bar/`
  /// and relative paths from different working dirs all collapse
  /// to one lock entry.
  static final Map<String, Future<void>> _outputDirMoveLocks = {};

  /// Move all files from an isolated temp dir to the real output dir.
  /// Returns the path of the main output file in the real dir.
  /// Uses retry with exponential backoff for cloud sync / antivirus interference.
  ///
  /// 2026-05-26 Codex spec — "unique safe filename on final move":
  /// when a destination file already exists in [outputDir], the batch
  /// is renamed with a shared ` (N)` suffix where N is the smallest
  /// positive integer producing a free slot for EVERY sibling in the
  /// batch (round-2 P1.1 fix). Macro pattern:
  ///   `video.mp4` collides → `video (1).mp4`, `video.en.srt` becomes
  ///   `video (1).en.srt`, thumbnail `video.jpg` becomes
  ///   `video (1).jpg`. The shared suffix keeps subtitle / thumbnail
  ///   associations intact with the main file (players match by
  ///   basename prefix).
  ///
  /// This is the FOUNDATION that lets us remove the duplicate
  /// warning at Home + Floating Capture — without unique-rename here,
  /// a re-download of the same URL would overwrite the previous file
  /// silently on macOS (POSIX rename overwrites) or via the copy
  /// fallback on Windows (Dart File.copy overwrites by default).
  Future<String> _moveFilesToOutputDir(
    String tempDir,
    String outputDir,
    String? mainOutputFile,
  ) async {
    // Codex round-2 P1.2 — serialize concurrent moves to the same
    // outputDir to close the check-then-act race window opened by
    // removing the Home/Floating duplicate guard.
    final lockKey = path.normalize(Directory(outputDir).absolute.path);
    final prev = _outputDirMoveLocks[lockKey];
    final completer = Completer<void>();
    _outputDirMoveLocks[lockKey] = completer.future;
    try {
      if (prev != null) {
        // Swallow prev's error — prev's failure is its own caller's
        // concern; current caller's body must still proceed.
        try {
          await prev;
        } catch (_) {}
      }
      return await _doMoveFilesToOutputDir(tempDir, outputDir, mainOutputFile);
    } finally {
      completer.complete();
      // Only clear the map slot if it still points to OUR completer.
      // A later concurrent caller may have replaced the entry with
      // its own future; in that case we leave the chain intact so
      // the next-in-line cleanup wins.
      if (identical(_outputDirMoveLocks[lockKey], completer.future)) {
        _outputDirMoveLocks.remove(lockKey);
      }
    }
  }

  /// Inner implementation — assumes caller has acquired the per-
  /// outputDir serialize lock above. Do NOT call directly; always
  /// go through `_moveFilesToOutputDir`.
  Future<String> _doMoveFilesToOutputDir(
    String tempDir,
    String outputDir,
    String? mainOutputFile,
  ) async {
    final dir = Directory(tempDir);
    if (!await dir.exists()) return mainOutputFile ?? outputDir;

    // DL-FB-FINALPATH-1: never move the internal `.final_path` sidecar into
    // the user's output folder — it is read (consumed) before this move and
    // is not user content.
    final files =
        (await dir.list().where((e) => e is File).cast<File>().toList())
            .where((f) => path.basename(f.path) != '.final_path')
            .toList();
    if (files.isEmpty) return mainOutputFile ?? outputDir;

    // Compute batch-wide unique suffix based on WHOLE-BATCH collision
    // (Codex round-2 P1.1). Auxiliary files (subs/thumbs/etc) share
    // the same suffix so the player-side basename association
    // survives the rename, AND each candidate suffix is rejected if
    // ANY sibling's suffixed destination is already on disk.
    String batchSuffix = '';
    String? mainBasenameNoExt;
    if (mainOutputFile != null) {
      final mainBasename = path.basename(mainOutputFile);
      mainBasenameNoExt = path.basenameWithoutExtension(mainBasename);
      final batchNames = files
          .map((f) => path.basename(f.path))
          .toList(growable: false);
      batchSuffix = await _computeBatchUniqueSuffix(
        outputDir,
        batchNames,
        mainBasenameNoExt,
      );
      if (batchSuffix.isNotEmpty) {
        debugPrint(
          '📁 [YtDlp] Batch destination collision detected — '
          'shared suffix "$batchSuffix" applied to "$mainBasename" + '
          'siblings (${batchNames.length} files).',
        );
      } else {
        // No collision → don't apply suffix in the move loop below.
        mainBasenameNoExt = null;
      }
    }

    String? mainMovedPath;

    for (final file in files) {
      final origName = path.basename(file.path);
      // Apply batch suffix to files sharing the main basename prefix.
      // E.g., `video.mp4` → `video (1).mp4`, `video.en.srt` → `video (1).en.srt`.
      // Files unrelated to the main (rare, but defensive) get per-file
      // collision resolution.
      String destName;
      // Codex round-2 P2 tightening — sibling-prefix match requires
      // the char following the stem to be `.` (extension boundary).
      // Without this, `videoOther.mp4` would inherit the batch
      // suffix when stem is `video`. Matches helper's stricter
      // filter inside `_computeBatchUniqueSuffix`.
      final isSibling =
          mainBasenameNoExt != null &&
          batchSuffix.isNotEmpty &&
          origName.startsWith(mainBasenameNoExt) &&
          (origName.length == mainBasenameNoExt.length ||
              origName[mainBasenameNoExt.length] == '.');
      if (isSibling) {
        final rest = origName.substring(mainBasenameNoExt.length);
        destName = '$mainBasenameNoExt$batchSuffix$rest';
      } else {
        // Per-file fallback collision check (covers no-main-known case
        // and any orphan file that doesn't share the main prefix).
        destName = await _resolveSingleFileUniqueName(outputDir, origName);
      }
      final destPath = path.join(outputDir, destName);

      // Try rename first (atomic, fast — works on same drive)
      var moved = false;
      try {
        await file.rename(destPath);
        moved = true;
      } on FileSystemException {
        // Cross-drive or transient lock — retry with copy
      }

      // Retry with exponential backoff: 500ms, 1s, 2s, 4s, 8s
      if (!moved) {
        for (var attempt = 1; attempt <= 5; attempt++) {
          await Future.delayed(
            Duration(milliseconds: 500 * (1 << (attempt - 1))),
          );
          try {
            await file.copy(destPath);
            await file.delete();
            moved = true;
            break;
          } on FileSystemException catch (e) {
            debugPrint(
              '⚠️ [YtDlp] Move attempt $attempt/5 for $origName: ${e.message}',
            );
          }
        }
      }

      if (moved &&
          mainOutputFile != null &&
          origName == path.basename(mainOutputFile)) {
        mainMovedPath = destPath;
      }
    }

    // Clean up the now-empty temp dir
    try {
      await dir.delete();
    } catch (_) {}

    // If we know the main file, return its new (possibly suffixed) path
    if (mainMovedPath != null) return _ytdlpPath(mainMovedPath);

    // Fallback: construct from mainOutputFile, preserving the suffix
    // applied above so callers stamping `mainOutputFile` as final
    // get the correct on-disk path.
    if (mainOutputFile != null) {
      final mainBasename = path.basename(mainOutputFile);
      String fileName;
      final isSiblingMain =
          mainBasenameNoExt != null &&
          batchSuffix.isNotEmpty &&
          mainBasename.startsWith(mainBasenameNoExt) &&
          (mainBasename.length == mainBasenameNoExt.length ||
              mainBasename[mainBasenameNoExt.length] == '.');
      if (isSiblingMain) {
        final rest = mainBasename.substring(mainBasenameNoExt.length);
        fileName = '$mainBasenameNoExt$batchSuffix$rest';
      } else {
        fileName = mainBasename;
      }
      return _ytdlpPath(path.join(outputDir, fileName));
    }

    return outputDir;
  }

  /// Compute a shared `(N)` suffix for the entire batch of files
  /// moved from a single yt-dlp temp dir into [outputDir].
  ///
  /// 2026-05-26 Codex round-2 P1.1 fix — suffix N is valid ONLY
  /// when every batch sibling's suffixed destination is free.
  /// Pre-fix the helper checked only the main basename collision;
  /// a pre-existing `video (1).en.srt` would not invalidate
  /// suffix ` (1)`, and the subtitle would get overwritten when
  /// the new batch moved its own `video.en.srt` into the slot.
  ///
  /// The helper takes [batchFileNames] = ALL files yt-dlp produced
  /// in the temp dir and [mainBasenameNoExt] = the shared prefix
  /// (e.g. `video` for `video.mp4`+`video.en.srt`+`video.jpg`).
  /// Files matching the prefix participate in the shared suffix;
  /// orphan files (rare) are excluded from the suffix decision
  /// and get their own per-file collision resolution at the move
  /// loop via `_resolveSingleFileUniqueName`.
  ///
  /// Walks N from 1..999; falls back to timestamp suffix in the
  /// pathological case to avoid an infinite loop. Returns empty
  /// string when no collision at any sibling.
  @visibleForTesting
  static Future<String> computeBatchUniqueSuffixForTest({
    required String outputDir,
    required Iterable<String> batchFileNames,
    required String mainBasenameNoExt,
  }) => _computeBatchUniqueSuffix(outputDir, batchFileNames, mainBasenameNoExt);

  static Future<String> _computeBatchUniqueSuffix(
    String outputDir,
    Iterable<String> batchFileNames,
    String mainBasenameNoExt,
  ) async {
    // Only files that share the EXACT main stem participate in the
    // shared suffix. Codex round-2 P2 tightening — bare prefix
    // `startsWith` would also match `videoOther.mp4` when stem is
    // `video`; require the char immediately following the stem to
    // be `.` (extension separator) so unrelated same-prefix files
    // get individual collision resolution via the per-file path
    // instead of inheriting the batch suffix. Orphans drop through
    // to `_resolveSingleFileUniqueName` at the move loop.
    final siblings = batchFileNames
        .where((n) {
          if (!n.startsWith(mainBasenameNoExt)) return false;
          if (n.length == mainBasenameNoExt.length) return true; // exact match
          return n[mainBasenameNoExt.length] == '.';
        })
        .toList(growable: false);
    if (siblings.isEmpty) return '';

    // Try empty suffix first — happy path when no destination
    // exists yet for any sibling.
    if (await _allBatchTargetsClear(
      outputDir,
      siblings,
      '',
      mainBasenameNoExt: mainBasenameNoExt,
    )) {
      return '';
    }

    for (var n = 1; n <= 999; n++) {
      final suffix = ' ($n)';
      if (await _allBatchTargetsClear(
        outputDir,
        siblings,
        suffix,
        mainBasenameNoExt: mainBasenameNoExt,
      )) {
        return suffix;
      }
    }

    // Pathological: 999 collisions. Timestamp suffix — still unique,
    // still `(...)`-shaped, won't overwrite. Caller proceeds with
    // this suffix; very unlikely to ever fire in practice.
    return ' (${DateTime.now().millisecondsSinceEpoch})';
  }

  /// Returns true when every sibling in [siblings], when transformed
  /// with [suffix] inserted after [mainBasenameNoExt], has NO existing
  /// file at the resulting path under [outputDir]. Empty suffix means
  /// "would-be destination names equal source names" — the no-collision
  /// happy path.
  static Future<bool> _allBatchTargetsClear(
    String outputDir,
    List<String> siblings,
    String suffix, {
    required String mainBasenameNoExt,
  }) async {
    for (final sibling in siblings) {
      final rest = sibling.substring(mainBasenameNoExt.length);
      final target = '$mainBasenameNoExt$suffix$rest';
      if (await File(path.join(outputDir, target)).exists()) {
        return false;
      }
    }
    return true;
  }

  /// Per-file unique-name fallback for files in the temp dir that
  /// don't share the main file's basename prefix (rare; defensive).
  /// Uses the same `(N)` suffix scheme as the batch logic.
  @visibleForTesting
  static Future<String> resolveSingleFileUniqueNameForTest({
    required String outputDir,
    required String fileName,
  }) => _resolveSingleFileUniqueName(outputDir, fileName);

  static Future<String> _resolveSingleFileUniqueName(
    String outputDir,
    String fileName,
  ) async {
    final desiredPath = path.join(outputDir, fileName);
    if (!await File(desiredPath).exists()) return fileName;

    final nameNoExt = path.basenameWithoutExtension(fileName);
    final ext = path.extension(fileName);
    for (var n = 1; n <= 999; n++) {
      final candidate = '$nameNoExt ($n)$ext';
      if (!await File(path.join(outputDir, candidate)).exists()) {
        return candidate;
      }
    }
    return '$nameNoExt (${DateTime.now().millisecondsSinceEpoch})$ext';
  }

  /// Check if yt-dlp is available
  Future<bool> isAvailable() async {
    if (_binaryPath == null) {
      await initialize();
    }
    return _binaryPath != null;
  }

  /// Get yt-dlp version
  String? get version => _version;

  /// Get yt-dlp binary path
  String? get binaryPath => _binaryPath;

  /// Get FFmpeg binary path
  String? get ffmpegPath => _ffmpegPath;

  /// Check if FFmpeg is available for video+audio merging
  bool get hasFFmpeg => _ffmpegPath != null;

  /// Normalize path for yt-dlp subprocess arguments.
  /// yt-dlp on Windows handles forward slashes correctly, but backslashes
  /// corrupt %-template parsing in -o arguments.
  static String _ytdlpPath(String p) {
    if (Platform.isWindows) return p.replaceAll(r'\', '/');
    return p;
  }

  /// RC10 Q-round C3 — final container/extension guard helper.
  ///
  /// Compares the final on-disk file extension against the user's
  /// picked container (videoFormat / audioFormat). Returns null when
  /// the extension matches (or no check is applicable); returns a
  /// [ExtensionMismatch] tuple when the file ext does NOT match the
  /// expected ext.
  ///
  /// Scoping rules (preserve happy paths):
  ///   - Empty/null `outputPath` → skip (nothing to check)
  ///   - extractAudio=true: compare against [audioFormat] (mp3/m4a/etc)
  ///   - extractAudio=false: compare against [videoFormat]
  ///     (mp4/mkv/webm/avi/mov/m4v/flv)
  ///   - Empty/null target format → skip (caller didn't enforce a pick)
  ///   - Image files (gallery-dl path) → not reachable here, scoped out
  ///   - .m4v special: yt-dlp emits .mp4, our rename step produces .m4v;
  ///     if the rename ran, the file is already .m4v. If somehow .mp4
  ///     survived to here while videoFormat='m4v', report mismatch.
  /// Public for both the datasource pre-move guard AND the
  /// fresh/retry-path mirror guards in [StartDownloadUseCase] +
  /// [DownloadRepositoryImpl]. Pure function — safe to call anywhere.
  static ExtensionMismatch? detectFinalExtensionMismatch({
    required String outputPath,
    String? videoFormat,
    String? audioFormat,
    bool extractAudio = false,
  }) => _detectFinalExtensionMismatch(
    outputPath: outputPath,
    videoFormat: videoFormat,
    audioFormat: audioFormat,
    extractAudio: extractAudio,
  );

  static ExtensionMismatch? _detectFinalExtensionMismatch({
    required String outputPath,
    String? videoFormat,
    String? audioFormat,
    bool extractAudio = false,
  }) {
    if (outputPath.isEmpty) return null;
    final expected = extractAudio ? audioFormat : videoFormat;
    if (expected == null || expected.isEmpty) return null;
    final normalizedExpected = expected.trim().toLowerCase();
    if (normalizedExpected.isEmpty) return null;
    final actualWithDot = path.extension(outputPath);
    final actual =
        actualWithDot.isEmpty ? '' : actualWithDot.substring(1).toLowerCase();
    if (actual.isEmpty) {
      // No extension on disk — treat as mismatch (suspicious).
      return ExtensionMismatch(expected: normalizedExpected, actual: '');
    }
    if (actual == normalizedExpected) return null;
    return ExtensionMismatch(expected: normalizedExpected, actual: actual);
  }

  static ResolutionCapViolation? detectResolutionCapViolation({
    required int? maxShortSide,
    required int? width,
    required int? height,
    bool extractAudio = false,
  }) => _detectResolutionCapViolation(
    maxShortSide: maxShortSide,
    width: width,
    height: height,
    extractAudio: extractAudio,
  );

  static ResolutionCapViolation? _detectResolutionCapViolation({
    required int? maxShortSide,
    required int? width,
    required int? height,
    bool extractAudio = false,
  }) {
    if (extractAudio) return null;
    if (maxShortSide == null || maxShortSide <= 0) return null;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return ResolutionCapViolation(
        expectedMaxShortSide: maxShortSide,
        actualWidth: width ?? 0,
        actualHeight: height ?? 0,
        dimensionsUnavailable: true,
      );
    }
    final actualShortSide = min(width, height);
    // F1 fix: the cap handed to this guard is a BUCKETED tier anchor
    // (heightForQuality → 480/720/1080/1440/2160/4320), produced by
    // _getStandardQualityLabel which buckets a true height DOWN to its
    // tier (768→"720p", 540→"480p", 1152→"1080p"). Enforcing the anchor
    // as an EXACT short-side cap false-fails every in-tier non-standard
    // height. Round the cap UP to the tier's inclusive upper boundary so
    // an in-tier file passes while a genuine cross-tier overrun (capped
    // 1080 → got 1440) still fails. Non-anchor caps fall back to the raw
    // value (no loosening for callers passing a true measured height).
    final tierCeiling = _tierCeilingShortSide(maxShortSide);
    if (actualShortSide <= tierCeiling) return null;
    return ResolutionCapViolation(
      expectedMaxShortSide: maxShortSide,
      actualWidth: width,
      actualHeight: height,
    );
  }

  /// F1 — map a bucketed tier anchor to the inclusive upper short-side
  /// boundary of that tier's bucket (mirror of
  /// `ExtractVideoInfoUseCase._getStandardQualityLabel`'s tier windows;
  /// each ceiling == next-tier-threshold − 1). Anchors only; any
  /// non-anchor value returns itself so a caller that passes a TRUE
  /// measured height keeps an exact cap.
  static int _tierCeilingShortSide(int anchor) {
    switch (anchor) {
      case 360:
        return 399; // 360p tier: height 300..399
      case 480:
        return 699; // 480p tier: height 400..699
      case 720:
        return 999; // 720p tier: height 700..999
      case 1080:
        return 1439; // 1080p tier: height 1000..1439
      case 1440:
        return 2159; // 1440p/2K tier: height 1440..2159
      case 2160:
        return 4319; // 4K/UHD tier: height 2160..4319
      case 4320:
        return 1 << 30; // 8K tier: no upper bucket — unbounded above
      default:
        return anchor; // true measured height → exact cap
    }
  }

  static bool _isYouTubeUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('youtube.com') || lower.contains('youtu.be');
  }

  static bool _isTikTokUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('tiktok.com') ||
        lower.contains('vm.tiktok') ||
        lower.contains('vt.tiktok');
  }

  static String _cleanUrlForYtDlp(String url) {
    return _cleanTikTokVideoUrlForYtDlp(_cleanYouTubeUrlForExtraction(url));
  }

  static String _cleanTikTokVideoUrlForYtDlp(String url) {
    try {
      final uri = Uri.parse(url.trim());
      final host = uri.host.toLowerCase();
      final isLongTikTokHost =
          host == 'tiktok.com' ||
          host == 'www.tiktok.com' ||
          host == 'm.tiktok.com';
      if (!isLongTikTokHost) return url;

      final segments = uri.pathSegments;
      final isVideoPath =
          segments.length >= 3 &&
          segments[0].startsWith('@') &&
          segments[1] == 'video' &&
          segments[2].isNotEmpty;
      if (!isVideoPath) return url;

      // TikTok's web extractor can fail on browser tracking params such as
      // `is_from_webapp`/`sender_device`, while the canonical video path works.
      return Uri(
        scheme: 'https',
        host: 'www.tiktok.com',
        path: uri.path,
      ).toString();
    } catch (_) {
      return url;
    }
  }

  static bool _usesDefaultNetworkProfileForUrl(String url) => _isTikTokUrl(url);

  static bool _shouldForceIpv4ForUrl(String url) =>
      !_usesDefaultNetworkProfileForUrl(url);

  @visibleForTesting
  static bool usesDefaultNetworkProfileForUrlForTest(String url) =>
      _usesDefaultNetworkProfileForUrl(url);

  @visibleForTesting
  static bool shouldForceIpv4ForUrlForTest(String url) =>
      _shouldForceIpv4ForUrl(url);

  @visibleForTesting
  static String cleanUrlForYtDlpForTest(String url) => _cleanUrlForYtDlp(url);

  Future<YouTubePotProviderPaths?> _ensureYouTubePotProvider({
    required bool isYouTube,
  }) async {
    if (!isYouTube) return null;
    final cached = _youtubePotProviderPaths;
    if (cached != null) return cached;

    final paths = await _youtubePotProviderService.ensureInstalled();
    _youtubePotProviderPaths = paths;
    return paths;
  }

  List<String> _youtubePotArgs(YouTubePotProviderPaths paths) {
    return [
      '--plugin-dirs',
      _ytdlpPath(paths.pluginDir),
      '--extractor-args',
      'youtubepot-bgutilcli:cli_path=${_ytdlpPath(paths.cliPath)}',
    ];
  }

  // RC-1 (2026-06): the MP4 progressive net the FormatSelectorService
  // appends is a MULTI-BRACKET tail, e.g.
  // `/best[ext=mp4][height<=1080]/best[ext=mp4][width<=1080]`. The old
  // `RegExp(r'/best\[[^\]]+\]$')` could not strip it: `[^\]]+` stops at
  // the FIRST inner `]`, so the anchored `]$` never reaches the end of a
  // two-bracket segment — the whole progressive net SURVIVED and YouTube
  // high-res resolved to itag-18 360p (640x320) labelled 1080p. The group
  // `(\[[^\]]*\])*` matches zero-or-more complete bracket groups anchored
  // to end, so it peels `/best`, `/best[ext=mp4]`, and the multi-bracket
  // tail alike. The loop removes every trailing progressive segment
  // (height-axis AND any sibling width-axis), defense-in-depth.
  static final RegExp _youtubeProgressiveBestTail = RegExp(
    r'/best(\[[^\]]*\])*$',
  );

  static String? _stripYouTubeProgressiveBestFallback(String? format) {
    if (format == null || format.isEmpty) return format;
    // On YouTube, `/best[...]` means "fall back to the best pre-muxed
    // progressive stream", which is commonly itag 18 (360p). That made a
    // failed 1080p DASH download look successful while producing a 360p file
    // with a 1080p filename. Keep DASH fallback tiers, but refuse the final
    // progressive safety net for video downloads.
    var stripped = format;
    while (_youtubeProgressiveBestTail.hasMatch(stripped)) {
      stripped = stripped.replaceFirst(_youtubeProgressiveBestTail, '');
    }
    return stripped;
  }

  /// Matches the `*.f<formatId>[v|a].<ext>` naming pattern yt-dlp uses
  /// for DASH stream intermediates that the merger writes BEFORE the
  /// final merged file. If the post-exit final-path logic picks one of
  /// these as the "final" download, the user gets a video-only or
  /// audio-only file labeled as the complete output — exactly the
  /// Wilson Facebook + tester no-audio incidents in production
  /// (`log.md` 2026-05-21 Incident C, file
  /// `[720p].f964607196458600v.mp4`).
  ///
  /// Patterns this regex must match (DASH intermediates):
  ///   - YouTube classic: `.f137.mp4`, `.f140.m4a`
  ///   - YouTube with subformat: `.f251-10.webm`
  ///   - Facebook video-only: `.f964607196458600v.mp4`
  ///   - Facebook audio-only: `.f1350541610457985a.m4a`
  ///   - HLS/DASH/HTTP protocol ids: `.fhls-audio-128000-Audio.mp4`, `.fdash-video.mp4`
  ///
  /// Patterns this regex must NOT match (final files):
  ///   - `Title [720p].mp4` (no `.f<id>` segment)
  ///   - `[720p].mp3` (audio extract)
  ///   - paths with `.f` in title (`A_fact.mp4` — no digits after `.f`)
  ///
  /// The `[va]?` optional suffix is the critical fix for Facebook's
  /// long-form DASH format IDs — yt-dlp's Facebook extractor appends a
  /// single `v` or `a` letter after the numeric ID to disambiguate
  /// video-only vs audio-only DASH streams; Twitter/X emits non-numeric
  /// HLS/DASH/HTTP format ids such as `fhls-audio-128000-Audio`. Pre-fix, these
  /// intermediates were silently classified as "final".
  static final RegExp _intermediateFormatFileRegex = RegExp(
    r'\.(?:f\d+(?:-\d+)?[va]?|f(?:hls|dash|https?)-[^./\\]+)\.[^./\\]+$',
  );

  static bool _isYtDlpIntermediateFormatFile(String filePath) {
    return _intermediateFormatFileRegex.hasMatch(path.basename(filePath));
  }

  @visibleForTesting
  static bool isIntermediateFormatFileForTest(String filePath) =>
      _isYtDlpIntermediateFormatFile(filePath);

  @visibleForTesting
  static String? postProcessorDestinationForTest(String line) =>
      _extractPostProcessorDestination(line);

  @visibleForTesting
  static String? stripYouTubeProgressiveBestFallbackForTest(String? format) =>
      _stripYouTubeProgressiveBestFallback(format);

  /// RC-2-v2 production-path seam — returns the assembled `-f`/`-S` pair
  /// EXACTLY as the default/YouTube download site builds it
  /// (downloadWithProgress: effectiveFormat strip at the `isYouTube &&
  /// !extractAudio` gate + the `-f`/`-S` append at the general branch).
  /// The strip-helper test alone is insufficient (Codex flag): it locks
  /// the transform but NOT the production gate that decides WHEN the
  /// strip is applied to the real `-f`. Mirrors the exact source-of-truth
  /// expressions below; if either moves, this seam must move with it
  /// (grep the verbatim expressions — line numbers intentionally omitted
  /// as they drift on every edit):
  ///   - gate: `isYouTube && !extractAudio ? _stripYouTubeProgressiveBestFallback(format)`
  ///   - YouTube host match: `url.contains('youtube.com') || url.contains('youtu.be')`
  ///   - default -f/-S append: `effectiveFormat` + `sortOptions ?? 'res,ext:mp4:m4a'`
  @visibleForTesting
  static List<String> buildYouTubeFormatArgsForTest({
    required String url,
    required String? format,
    required String? sortOptions,
    bool extractAudio = false,
  }) {
    final isYouTube = url.contains('youtube.com') || url.contains('youtu.be');
    final effectiveFormat =
        isYouTube && !extractAudio
            ? _stripYouTubeProgressiveBestFallback(format)
            : format;
    if (effectiveFormat == null) return const [];
    return ['-f', effectiveFormat, '-S', sortOptions ?? 'res,ext:mp4:m4a'];
  }

  static String? _extractPostProcessorDestination(String line) {
    const marker = 'Destination:';
    final markerIndex = line.indexOf(marker);
    if (markerIndex == -1) return null;
    var destination = line.substring(markerIndex + marker.length).trim();
    if (destination.isEmpty) return null;
    if ((destination.startsWith('"') && destination.endsWith('"')) ||
        (destination.startsWith("'") && destination.endsWith("'"))) {
      destination = destination.substring(1, destination.length - 1);
    }
    if (destination.isEmpty) return null;
    return _ytdlpPath(destination);
  }

  /// Postprocess compatibility for the final on-disk container.
  ///
  /// yt-dlp's embed-* postprocessors each have a baked-in `SUPPORTED_EXTS`
  /// gate; passing the flag with an unsupported container raises (for
  /// embed-thumbnail — hard fail) or silently drops (for embed-subs). The
  /// caller resolves the effective extension and consults this method to
  /// decide which `--embed-*` flags are safe to add to the args list.
  ///
  /// Sources (yt-dlp source pinned 2026.x):
  ///   - postprocessor/embedthumbnail.py:222 — thumbnail
  ///   - postprocessor/ffmpeg.py:582 (FFmpegEmbedSubtitlePP) — subs
  ///   - postprocessor/ffmpeg.py (FFmpegMetadataPP) — no SUPPORTED_EXTS
  ///     gate; metadata is best-effort. Chapters share metadata's path
  ///     but containers without a chapter atom (AVI, FLV) drop them.
  ///
  /// Exposed as `@visibleForTesting` so unit tests can pin the matrix
  /// against upstream yt-dlp drift without spinning up the full
  /// download flow.
  @visibleForTesting
  static EmbedCompatibility resolveEmbedCompatibility({
    required String? recodeVideo,
    required String? videoFormat,
    required String? audioFormat,
    required bool extractAudio,
  }) {
    final effectiveExt =
        (extractAudio && audioFormat != null
                ? audioFormat
                : (recodeVideo ?? videoFormat ?? 'mp4'))
            .toLowerCase();
    const thumbnail = <String>{
      'mp3',
      'mkv',
      'mka',
      'ogg',
      'opus',
      'flac',
      'm4a',
      'mp4',
      'm4v',
      'mov',
    };
    const subs = <String>{'mp4', 'mov', 'm4a', 'webm', 'mkv', 'mka'};
    const chapters = <String>{'mp4', 'm4v', 'mov', 'mkv', 'mka', 'webm'};
    return EmbedCompatibility(
      effectiveExt: effectiveExt,
      canEmbedThumbnail: thumbnail.contains(effectiveExt),
      canEmbedSubs: subs.contains(effectiveExt),
      canEmbedChapters: chapters.contains(effectiveExt),
    );
  }

  /// RC4a of Ultra Plan v3 — yt-dlp recode encoder override.
  ///
  /// yt-dlp's `FFmpegVideoConvertorPP._options(target_ext)` HARDCODES
  /// `'-c:v libxvid -vtag XVID'` for AVI. The bundled ffmpeg from
  /// martin-riedl.de is configured WITHOUT `--enable-libxvid` (verified
  /// via `ffmpeg -encoders` in the audit — no libxvid line), so a
  /// fresh AVI request fails with `Encoder not found` (production log
  /// #403 line 125). The bundled ffmpeg DOES ship `mpeg4` (built-in,
  /// no external lib needed) + `libmp3lame`, which together produce a
  /// valid AVI playable by every standard AVI tool.
  ///
  /// `--postprocessor-args VideoConvertor:<args>` APPENDS to yt-dlp's
  /// internal args, and ffmpeg honors the LAST `-c:v`/`-c:a` it sees,
  /// so this override wins over the upstream libxvid pick. The XVID
  /// FourCC tag is kept for editor compatibility (legacy AVI tooling
  /// reads FourCC, not codec name).
  ///
  /// Returns an empty list for containers that don't need an override
  /// (mp4/mkv/webm/mov/m4v/flv currently let yt-dlp auto-pick an
  /// encoder the bundled ffmpeg has — pending RC4b smoke verification
  /// per Codex direction; don't pre-emptively override what isn't
  /// proven broken).
  static List<String> _recodeEncoderOverrideArgs(String? recodeVideo) {
    if (recodeVideo == 'avi') {
      return [
        '--postprocessor-args',
        'VideoConvertor:-c:v mpeg4 -vtag XVID -c:a libmp3lame',
      ];
    }
    return const [];
  }

  @visibleForTesting
  static List<String> recodeEncoderOverrideArgsForTest(String? recodeVideo) =>
      _recodeEncoderOverrideArgs(recodeVideo);

  static List<String> _containerPostProcessArgs({
    required bool extractAudio,
    required String? videoFormat,
    required String? mergeFormatPriority,
    required String? remuxVideo,
    required String? recodeVideo,
  }) {
    if (extractAudio) return const [];

    final args = <String>[];
    final priority = mergeFormatPriority ?? '${videoFormat ?? 'mp4'}/mkv/webm';
    args.addAll(['--merge-output-format', priority]);

    if (recodeVideo != null) {
      args.addAll(['--recode-video', recodeVideo]);
      args.addAll(_recodeEncoderOverrideArgs(recodeVideo));
    } else if (remuxVideo != null) {
      args.addAll(['--remux-video', remuxVideo]);
    }
    return args;
  }

  @visibleForTesting
  static List<String> containerPostProcessArgsForTest({
    required bool extractAudio,
    required String? videoFormat,
    required String? mergeFormatPriority,
    required String? remuxVideo,
    required String? recodeVideo,
  }) => _containerPostProcessArgs(
    extractAudio: extractAudio,
    videoFormat: videoFormat,
    mergeFormatPriority: mergeFormatPriority,
    remuxVideo: remuxVideo,
    recodeVideo: recodeVideo,
  );

  static List<String> _forceRemuxArgs({
    required bool forceRemux,
    required String? videoFormat,
    required String? recodeVideo,
    required bool extractAudio,
  }) {
    if (!forceRemux ||
        videoFormat == null ||
        extractAudio ||
        recodeVideo != null) {
      return const [];
    }
    return ['--remux-video', videoFormat];
  }

  @visibleForTesting
  static List<String> forceRemuxArgsForTest({
    required bool forceRemux,
    required String? videoFormat,
    required String? recodeVideo,
    required bool extractAudio,
  }) => _forceRemuxArgs(
    forceRemux: forceRemux,
    videoFormat: videoFormat,
    recodeVideo: recodeVideo,
    extractAudio: extractAudio,
  );

  /// RC4b of Ultra Plan v3 — final-path scan extension resolver.
  ///
  /// When the recoded file lands in temp dir, the app scans for a
  /// file matching the user's requested extension to promote it
  /// over the `.mkv` merge intermediate (Pick X → Get X). For most
  /// containers `videoFormat` matches the extension yt-dlp emits.
  ///
  /// M4V is the exception: yt-dlp's FORMAT_RE validator rejects
  /// 'm4v' as a `--recode-video` target. `FormatSelectorService`
  /// therefore maps the user's M4V choice to recodeVideo='mp4', and
  /// the datasource renames `.mp4 → .m4v` AFTER yt-dlp exits. The
  /// scan must look for the extension yt-dlp ACTUALLY produced
  /// (.mp4), not the user's pick (.m4v) — otherwise the scan errors
  /// out before the rename block runs.
  ///
  /// Production log #406 (2026-05-22) made this visible: yt-dlp
  /// completed `mkv→mp4` successfully but the scan demanded `.m4v`,
  /// failed, and the download was marked failed despite a valid
  /// `.mp4` sitting in temp.
  static String _recodeScanExtension({
    required String? videoFormat,
    required String? recodeVideo,
  }) {
    if (videoFormat == 'm4v' && recodeVideo == 'mp4') {
      return 'mp4';
    }
    return (videoFormat ?? recodeVideo ?? '').toLowerCase();
  }

  @visibleForTesting
  static String recodeScanExtensionForTest({
    required String? videoFormat,
    required String? recodeVideo,
  }) =>
      _recodeScanExtension(videoFormat: videoFormat, recodeVideo: recodeVideo);

  /// RC4b.1 of Ultra Plan v3 — shared M4V rename helper.
  ///
  /// yt-dlp emits `.mp4` for M4V requests (FORMAT_RE rejects 'm4v'
  /// as a recode target). We rename `.mp4 → .m4v` in the temp dir
  /// BEFORE moving to the user's output dir so the user sees the
  /// extension they picked. The two formats are structurally
  /// identical MP4 wrappers, so the rename is safe — iTunes /
  /// Apple TV treat `.m4v` as their import extension.
  ///
  /// Returns the renamed path on success or the input path unchanged
  /// when no rename is needed (non-M4V cases) or when the rename
  /// fails (filesystem error — keep .mp4 rather than abort the
  /// download). The exit-code-0 and exit-code-nonzero salvage paths
  /// share this helper so M4V Pick X → Get X holds across both.
  static Future<String> _renameM4vIfApplicable({
    required String filePath,
    required String? videoFormat,
    required String? recodeVideo,
  }) async {
    final isM4vRename =
        recodeVideo == 'mp4' &&
        videoFormat == 'm4v' &&
        filePath.toLowerCase().endsWith('.mp4');
    if (!isM4vRename) return filePath;
    final renamed = filePath.replaceAll(
      RegExp(r'\.mp4$', caseSensitive: false),
      '.m4v',
    );
    try {
      await File(filePath).rename(renamed);
      debugPrint('✅ [YtDlp] m4v post-rename .mp4 → .m4v: $renamed');
      return renamed;
    } catch (e) {
      debugPrint('⚠️ [YtDlp] m4v post-rename failed ($e); keeping .mp4 path.');
      return filePath;
    }
  }

  /// Scan [dir] for the most-recently-modified file whose extension
  /// is `.$expectedExt` (case-insensitive). Used as a belt-and-braces
  /// fallback when `--print-to-file post_process:filepath` did not
  /// emit a path matching the user's recode target.
  ///
  /// Returns `null` when no matching file exists. Skips DASH
  /// intermediates (`.f<id>[va]?.<ext>` per [_isYtDlpIntermediateFormatFile])
  /// so the merge originals never get promoted by mistake. Skips
  /// zero-byte files so partial / failed recode artifacts do not
  /// surface as completed downloads.
  @visibleForTesting
  static Future<String?> findFileWithExtensionForTest(
    String dir,
    String expectedExt,
  ) => _findFileWithExtension(dir, expectedExt);

  static Future<String?> _findFileWithExtension(
    String dir,
    String expectedExt,
  ) async {
    try {
      final directory = Directory(dir);
      if (!await directory.exists()) return null;
      File? best;
      DateTime? bestMtime;
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final base = path.basename(entity.path);
        if (!base.toLowerCase().endsWith('.$expectedExt')) continue;
        if (_isYtDlpIntermediateFormatFile(entity.path)) continue;
        final stat = await entity.stat();
        if (stat.size == 0) continue;
        if (bestMtime == null || stat.modified.isAfter(bestMtime)) {
          best = entity;
          bestMtime = stat.modified;
        }
      }
      return best == null ? null : _ytdlpPath(best.path);
    } catch (e) {
      debugPrint('⚠️ [YtDlp] _findFileWithExtension failed: $e');
      return null;
    }
  }

  /// DL-FB-FINALPATH-1: extensions that are NEVER the primary media output
  /// (subtitle / thumbnail / metadata / partial-download sidecars).
  static const Set<String> _nonPrimaryOutputExtensions = {
    '.srt', '.vtt', '.ass', '.ssa', '.lrc',
    '.json', '.description', '.info',
    '.jpg', '.jpeg', '.png', '.webp', '.gif',
    '.part', '.ytdl', '.temp', '.tmp',
  };

  /// DL-FB-FINALPATH-1: locate the real primary media output in [tempDir]
  /// when the resolved path is not on disk — an empty/stale `.final_path`
  /// sidecar, or a stdout-parsed download-FRAGMENT destination rather than
  /// the merged output (the Facebook multi-stream case). Returns the largest
  /// COMPLETE media file, skipping the `.final_path` sidecar + dotfiles,
  /// subtitle/thumbnail/metadata/partial sidecars, and yt-dlp `.fNNN`/HLS/
  /// DASH format intermediates. "Largest" wins because a merged A+V file
  /// always exceeds any single fragment that might linger. Returns null when
  /// no primary media file is present.
  static Future<String?> _findPrimaryOutputFile(String tempDir) async {
    try {
      final dir = Directory(tempDir);
      if (!await dir.exists()) return null;
      String? bestPath;
      int bestSize = 0;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = path.basename(entity.path);
        if (name.startsWith('.')) continue; // .final_path sidecar + dotfiles
        if (_nonPrimaryOutputExtensions.contains(
          path.extension(name).toLowerCase(),
        )) {
          continue;
        }
        if (_isYtDlpIntermediateFormatFile(entity.path)) continue;
        int size;
        try {
          size = await entity.length();
        } catch (_) {
          continue;
        }
        if (size > bestSize) {
          bestSize = size;
          bestPath = entity.path;
        }
      }
      return bestPath == null ? null : _ytdlpPath(bestPath);
    } catch (e) {
      debugPrint('⚠️ [YtDlp] _findPrimaryOutputFile failed: $e');
      return null;
    }
  }

  @visibleForTesting
  static Future<String?> findPrimaryOutputFileForTest(String tempDir) =>
      _findPrimaryOutputFile(tempDir);

  /// Read the authoritative final path that yt-dlp wrote via
  /// `--print-to-file post_process:filepath`. Returns `null` when the
  /// sidecar is missing, empty, or unreadable — callers fall back to
  /// the stdout-parsed path so a missing sidecar never blocks
  /// completion. Trims trailing newlines that yt-dlp appends.
  ///
  /// Visible for testing through the public download flow only; not
  /// exported as a service helper because the contract is internal
  /// to the yt-dlp subprocess lifecycle.
  Future<String?> _readFinalPathSidecar(String sidecarPath) async {
    try {
      final file = File(sidecarPath);
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      // yt-dlp may emit multiple lines if --print is used multiple
      // times. We registered one entry only (after_move:filepath) so
      // the file is one line, but defensively take the LAST non-empty
      // line — the final post-PP path wins over any prior line.
      final lines =
          trimmed
              .split(RegExp(r'\r?\n'))
              .where((l) => l.trim().isNotEmpty)
              .toList();
      if (lines.isEmpty) return null;
      return _ytdlpPath(lines.last.trim());
    } catch (e) {
      debugPrint('⚠️ [YtDlp] Failed to read final-path sidecar: $e');
      return null;
    }
  }

  @visibleForTesting
  static Future<String?> promoteExpectedExtensionForTest({
    required String isolatedTempDir,
    required String? resolvedOutputFile,
    String? videoFormat,
    String? audioFormat,
    bool extractAudio = false,
  }) => _promoteExpectedExtensionIfNeeded(
    isolatedTempDir: isolatedTempDir,
    resolvedOutputFile: resolvedOutputFile,
    videoFormat: videoFormat,
    audioFormat: audioFormat,
    extractAudio: extractAudio,
  );

  static Future<String?> _promoteExpectedExtensionIfNeeded({
    required String isolatedTempDir,
    required String? resolvedOutputFile,
    String? videoFormat,
    String? audioFormat,
    bool extractAudio = false,
  }) async {
    final expected = extractAudio ? audioFormat : videoFormat;
    final normalizedExpected = expected?.trim().toLowerCase();
    if (normalizedExpected == null || normalizedExpected.isEmpty) {
      return resolvedOutputFile;
    }

    final mismatch =
        resolvedOutputFile == null
            ? ExtensionMismatch(expected: normalizedExpected, actual: '')
            : _detectFinalExtensionMismatch(
              outputPath: resolvedOutputFile,
              videoFormat: videoFormat,
              audioFormat: audioFormat,
              extractAudio: extractAudio,
            );
    if (mismatch == null) return resolvedOutputFile;

    final scanned = await _findFileWithExtension(
      isolatedTempDir,
      mismatch.expected,
    );
    if (scanned == null) return resolvedOutputFile;

    debugPrint(
      '✅ [YtDlp] Final extension scan promoted "$scanned" '
      'over stale path "$resolvedOutputFile" (expected .${mismatch.expected}, '
      'saw .${mismatch.actual})',
    );
    return scanned;
  }

  /// Extract video information without downloading.
  ///
  /// Integrates with [CircuitBreakerService] to protect against repeated
  /// yt-dlp failures per platform (e.g., rate limiting on YouTube).
  /// When the circuit is open, throws [YtDlpException] with
  /// [YtDlpErrorType.circuitBreakerOpen] (distinct from `rateLimited`,
  /// which represents platform-side throttling — different UX in the UI).
  Future<YtDlpVideoInfo> extractInfo(
    String url, {
    String? cookiesFile,
    String? cookiesFromBrowser,
    String? proxyUrl,
    String? extractorClient,
    int? timeoutSecs,
  }) async {
    // Auto-initialize if not yet done
    if (_binaryPath == null) {
      await initialize();
    }

    // Circuit breaker check — per-platform protection. Distinct error
    // type from `rateLimited` so UI can show "app cooldown" UX with
    // countdown instead of "YouTube rate-limit, refresh cookies" UX.
    final platform = PlatformDetector.detectPlatform(url).name;
    if (_circuitBreaker != null &&
        !_circuitBreaker.isRequestAllowed(platform)) {
      final remaining = _circuitBreaker.getRemainingCooldownSeconds(platform);
      debugPrint(
        '🔴 [YtDlp] Circuit breaker OPEN for $platform '
        '(${remaining}s remaining)',
      );
      throw YtDlpException(
        YtDlpErrorType.circuitBreakerOpen,
        'Circuit breaker open for $platform — '
        'cooldown ${remaining}s remaining',
      );
    }

    // Clean platform URL noise before handing the URL to yt-dlp. This keeps
    // identity-sensitive paths intact while removing params known to break or
    // slow extractors (YouTube playlist context, TikTok browser tracking args).
    final cleanedUrl = _cleanUrlForYtDlp(url);
    final isYouTube = platform == 'youtube' || _isYouTubeUrl(cleanedUrl);
    final isTikTok = _isTikTokUrl(cleanedUrl);
    // Browser-sniffed HLS carries the page URL as Referer (see
    // DownloadRefererHolder). Non-stamped downloads (the overwhelming
    // majority) resolve to null and are completely unaffected.
    final sniffReferer =
        DownloadRefererHolder.lookup(cleanedUrl) ??
        DownloadRefererHolder.lookup(url);
    final useDefaultNetworkProfile = _usesDefaultNetworkProfileForUrl(
      cleanedUrl,
    );
    final hasYouTubeCookies =
        isYouTube && (cookiesFile != null || cookiesFromBrowser != null);
    final potProviderPaths =
        Platform.isWindows
            ? null
            : await _ensureYouTubePotProvider(
              isYouTube: isYouTube && hasYouTubeCookies,
            );

    // Build extractor-args (skip HLS/DASH manifests + translated subs)
    final extractorArgs =
        extractorClient != null && extractorClient.isNotEmpty
            ? 'youtube:skip=hls,dash,translated_subs;player_client=$extractorClient'
            : 'youtube:skip=hls,dash,translated_subs';

    final args = <String>[
      '--dump-json',
      '--no-download',
      '--no-warnings',
      '--no-playlist',
      '--no-check-formats',
      '--socket-timeout',
      '15',
      '--extractor-retries',
      isTikTok ? '5' : '2',
      '--retry-sleep',
      isTikTok ? 'extractor:linear=1::1' : '3',
      if (!useDefaultNetworkProfile) '--no-check-certificates',
      // Deno JS runtime — explicit absolute path, never PATH-inherited.
      // yt-dlp 2025.11.12+ mandates external JS runtime for full YouTube
      // support; without this flag the logged-in extraction returns only
      // storyboard formats (no playable video/audio). The `deno:` prefix
      // is yt-dlp's required runtime-name discriminator.
      // Skip the flag when Deno is unavailable so non-YouTube extractors
      // (TikTok, IG, Vimeo, etc) keep working — yt-dlp ignores missing
      // runtimes for paths that don't need them.
      // Also skipped for referer-stamped (browser-HLS) extractions: those are
      // never YouTube, and on Windows they run through Process.run with
      // runInShell, where a Deno path containing spaces can't be quoted safely.
      if (!useDefaultNetworkProfile &&
          _denoPath != null &&
          sniffReferer == null) ...[
        '--js-runtimes',
        'deno:$_denoPath',
      ],
      if (potProviderPaths != null) ..._youtubePotArgs(potProviderPaths),
      if (!isTikTok) ...['--extractor-args', extractorArgs],
      // Cookie precedence: --cookies <file> WINS over --cookies-from-browser.
      // The in-app captured cookies (file path) are an explicit user
      // intent that bypasses the Chrome cookie-DB-lock pitfall on
      // Windows (yt-dlp issue 7271 — Chrome SQLite is locked while
      // Chrome process runs). The legacy precedence treated
      // cookies-from-browser as primary which caused the
      // `Could not copy Chrome cookie database` error chain visible in
      // `log.md` 2026-05-21 Incident A. When BOTH are set, prefer the
      // file — the caller has already promoted the in-app cookie.
      if (cookiesFile != null) ...[
        '--cookies',
        cookiesFile,
      ] else if (cookiesFromBrowser != null) ...[
        '--cookies-from-browser',
        cookiesFromBrowser,
      ],
      if (proxyUrl != null && proxyUrl.isNotEmpty) ...['--proxy', proxyUrl],
      // Referer stamped by the browser media-sniff panel (CDNs like znews.vn
      // reject manifest requests without the article page as Referer). Null
      // for every non-stamped download — no behaviour change.
      if (sniffReferer != null) ...['--referer', sniffReferer],
      cleanedUrl,
    ];

    try {
      final timeout = timeoutSecs ?? 30;
      final stopwatch = Stopwatch()..start();
      final isFirstExtract = _isFirstExtractSinceAppStart;
      _isFirstExtractSinceAppStart = false;
      late final YtDlpVideoInfo parsed;

      // DL-016 — engine gate before spawn (covers BOTH the Rust executor
      // and the Dart Process.run path): a binary that vanished after init
      // (AV quarantine, failed OTA rollback) gets one bounded repair here
      // instead of dying in a misclassified ProcessException.
      final ytdlpBinary = await _ensureYtdlpBinaryReady();
      if (ytdlpBinary == null) {
        throw YtDlpException(YtDlpErrorType.unknown, ytdlpBinaryMissingMessage);
      }

      // The Rust executor's signature has no referer parameter, so the rare
      // referer-stamped extraction (browser-sniffed HLS) takes the Dart
      // Process.run path on every platform — it's a one-off --dump-json call,
      // not a streaming download, so the shell-wrapping concerns don't apply.
      if (Platform.isWindows && sniffReferer == null) {
        // Windows fast path: avoid Process.run(runInShell: true), which wraps
        // every extract in cmd.exe. The Rust executor launches yt-dlp directly
        // with CREATE_NO_WINDOW, avoiding console flashes without shell overhead.
        // Deno path is forwarded so the Rust executor injects
        // `--js-runtimes deno:<path>` exactly as the Dart Process.run path does.
        final dto = await native.ytdlpExtractInfo(
          binaryPath: ytdlpBinary,
          url: cleanedUrl,
          cookiesFile: cookiesFile,
          cookiesFromBrowser: cookiesFromBrowser,
          proxyUrl: proxyUrl,
          extractorClient: extractorClient,
          timeoutSecs: BigInt.from(timeout),
          jsRuntimePath: _denoPath,
        );
        parsed = YtDlpVideoInfo.fromDto(dto);
      } else {
        // Keep Unix on Dart Process.run. Commit e3a0a056 fixed a POSIX-only
        // SIGCHLD/ECHILD race between Rust tokio process handling and
        // Dart-spawned download processes; Windows stays on the Rust path
        // because `Process.run(runInShell:true)` cannot safely quote the
        // app-support path with spaces inside extractor-args. Download uses
        // Process.start without shell wrapping, so PO-provider args are still
        // safe there.
        //
        // Windows lands here only for referer-stamped (browser-HLS)
        // extractions. It MUST use runDirect: the yt-dlp binary lives under
        // the company app-support dir, and when that path contains spaces
        // (VidCombo's "Bui Xuan Mai"; svid pre-SsLabs) runInShell's cmd.exe
        // wrapping truncates the executable at the first space ("'Bui' is not
        // recognized…" — same P0 as the 2026-05-25 ffmpeg failure), which
        // surfaced to users as a bogus "content removed" extraction error.
        final runner =
            Platform.isWindows
                ? ProcessHelper.runDirect(ytdlpBinary, args)
                : ProcessHelper.run(ytdlpBinary, args);
        final result = await runner.timeout(
          Duration(seconds: timeout),
          onTimeout:
              () =>
                  throw YtDlpException(
                    YtDlpErrorType.timeout,
                    'yt-dlp extraction timeout (${timeout}s)',
                    metadata: _buildYouTubeExtractFailureMetadata(
                      isYouTube: isYouTube,
                      hasYouTubeCookies: hasYouTubeCookies,
                      cookiesFile: cookiesFile,
                      cookiesFromBrowser: cookiesFromBrowser,
                      extractorClient: extractorClient,
                      potProviderPaths: potProviderPaths,
                      errorType: YtDlpErrorType.timeout,
                      errorText: 'yt-dlp extraction timeout (${timeout}s)',
                    ),
                  ),
        );

        if (result.exitCode != 0) {
          final stderr = result.stderr.toString();
          final errorType = _parseErrorTypeFromStderr(stderr);
          _maybeTriggerDenoRepair(errorType);
          throw YtDlpException(
            errorType,
            stderr,
            metadata: _buildYouTubeExtractFailureMetadata(
              isYouTube: isYouTube,
              hasYouTubeCookies: hasYouTubeCookies,
              cookiesFile: cookiesFile,
              cookiesFromBrowser: cookiesFromBrowser,
              extractorClient: extractorClient,
              potProviderPaths: potProviderPaths,
              errorType: errorType,
              errorText: stderr,
            ),
          );
        }

        final stdout = result.stdout.toString().trim();
        if (stdout.isEmpty) {
          throw YtDlpException(
            YtDlpErrorType.unknown,
            'yt-dlp returned empty output',
            metadata: _buildYouTubeExtractFailureMetadata(
              isYouTube: isYouTube,
              hasYouTubeCookies: hasYouTubeCookies,
              cookiesFile: cookiesFile,
              cookiesFromBrowser: cookiesFromBrowser,
              extractorClient: extractorClient,
              potProviderPaths: potProviderPaths,
              errorType: YtDlpErrorType.unknown,
              errorText: 'yt-dlp returned empty output',
            ),
          );
        }

        parsed = _parseVideoInfoJson(stdout);
      }

      stopwatch.stop();
      appLogger.info(
        '[yt-dlp extract] platform=$platform '
        'path=${Platform.isWindows ? "native-windows" : "dart-process"} '
        'duration_ms=${stopwatch.elapsedMilliseconds} '
        'first_extract_since_app_start=$isFirstExtract',
      );

      // Circuit breaker outcome is recorded by the orchestrator
      // (`extract_video_info_usecase.dart::_extractWithClientFallback`)
      // ONCE per logical extraction. Recording here would count each
      // fallback-chain client as a separate user request — 4 clients
      // × 3 threshold = circuit trips during the chain itself, not
      // after 3 user retries. See
      // `feedback_circuit_breaker_counter_conflation.md` for context.
      return parsed;
    } on YtDlpException {
      rethrow;
    } catch (e) {
      final errorStr = e.toString();
      final errorType = _parseErrorTypeFromException(errorStr);
      _maybeTriggerDenoRepair(errorType);
      throw YtDlpException(
        errorType,
        errorStr,
        metadata: _buildYouTubeExtractFailureMetadata(
          isYouTube: isYouTube,
          hasYouTubeCookies: hasYouTubeCookies,
          cookiesFile: cookiesFile,
          cookiesFromBrowser: cookiesFromBrowser,
          extractorClient: extractorClient,
          potProviderPaths: potProviderPaths,
          errorType: errorType,
          errorText: errorStr,
        ),
      );
    }
  }

  /// Fire-and-forget background repair for a missing/corrupt Deno
  /// runtime. No-op for any other error type. Idempotent inside
  /// [BinaryManager.triggerRepair] — fan-out from N concurrent failed
  /// extractions collapses to a single download.
  void _maybeTriggerDenoRepair(YtDlpErrorType errorType) {
    if (errorType != YtDlpErrorType.jsRuntimeUnavailable) return;
    unawaited(
      _binaryManager.triggerRepair(BinaryType.deno).then((repaired) async {
        if (!repaired) return;
        // Refresh cached path so the next extraction picks the
        // restored binary up without an app restart.
        _denoPath = await _binaryManager.getBinaryPath(BinaryType.deno);
      }),
    );
  }

  /// DL-016 — pre-spawn engine gate for yt-dlp, mirroring the FFmpeg
  /// repair-or-confirm gate below. The production wave (06-11: 40
  /// rows/day, 94/95 Windows, release-correlated): the binary vanishes
  /// AFTER datasource init (AV retroactive quarantine, failed OTA
  /// rollback), `_binaryPath` goes stale, and the spawn dies with a
  /// ProcessException that the classifier used to misroute to
  /// networkTimeout (retryable) → infinite futile retry while the user
  /// can download nothing.
  ///
  /// Awaited (bounded by [BinaryDownloader]'s own stream timeouts):
  /// verifies the file is on disk via the disk-checking
  /// [BinaryManager.getBinaryPath], attempts ONE idempotent capped
  /// repair when missing, and returns the usable path — or null when
  /// repair is exhausted/failed, in which case the caller surfaces
  /// [ytdlpBinaryMissingMessage] (classifier → ytdlpBinaryMissing,
  /// NOT retryable — the loop stops).
  Future<String?> _ensureYtdlpBinaryReady() async {
    var binaryPath = await _binaryManager.getBinaryPath(BinaryType.ytDlp);
    if (binaryPath == null) {
      appLogger.error(
        '🚨 [DL-016] yt-dlp binary missing at spawn time — '
        'attempting bounded repair',
      );
      final repaired = await _binaryManager.triggerRepair(BinaryType.ytDlp);
      if (repaired) {
        binaryPath = await _binaryManager.getBinaryPath(BinaryType.ytDlp);
      }
    }
    if (binaryPath != null) _binaryPath = binaryPath;
    return binaryPath;
  }

  @visibleForTesting
  Future<String?> ensureYtdlpBinaryReadyForTest() => _ensureYtdlpBinaryReady();

  /// Terminal user-facing message when the yt-dlp binary is missing and
  /// bounded repair did not restore it. The 'Failed to execute yt-dlp'
  /// prefix is what [DownloadErrorClassifier] maps to
  /// [DownloadErrorCode.ytdlpBinaryMissing]; keep them in sync.
  @visibleForTesting
  static const String ytdlpBinaryMissingMessage =
      'Failed to execute yt-dlp: the download engine binary is missing and '
      'automatic repair did not succeed — your antivirus may have '
      'quarantined it. Open Settings → yt-dlp Engine to reinstall, or add '
      'the app to your antivirus exclusions and retry.';

  /// Synchronous repair-or-confirm gate for FFmpeg. Unlike
  /// [_maybeTriggerDenoRepair] this is awaited because the caller
  /// (download orchestrator) needs to make a routing decision —
  /// proceed with a DASH merge format, or fail explicitly — based
  /// on whether FFmpeg is available right now. Pre-fix the caller
  /// silently rewrote a `bestvideo+bestaudio` format string to
  /// `best` (pre-muxed single stream) whenever FFmpeg was missing,
  /// which on YouTube means "best pre-muxed" ≈ 360p — the user
  /// chose "MP4 · Best" and got 360p without any warning. That
  /// silent degrade is the production bug this gate is designed
  /// to remove.
  ///
  /// Returns `true` when FFmpeg is usable after this call
  /// (already cached, or repair download succeeded). Returns
  /// `false` when FFmpeg is unrecoverable in the current
  /// environment (Defender quarantine, disk full, network down) —
  /// the caller is expected to surface an actionable error instead
  /// of falling back to a degraded format.
  ///
  /// Idempotent via [BinaryManager.triggerRepair]'s in-flight
  /// future map: many concurrent downloads hitting this gate
  /// collapse to a single repair download.
  Future<bool> ensureFFmpegOrRepair() async {
    if (_ffmpegPath != null) return true;
    appLogger.warning(
      '🔧 [YtDlp] FFmpeg missing at runtime — triggering background repair '
      'via BinaryManager.triggerRepair(BinaryType.ffmpeg)',
    );
    final repaired = await _binaryManager.triggerRepair(BinaryType.ffmpeg);
    if (repaired) {
      _ffmpegPath = await _binaryManager.getBinaryPath(BinaryType.ffmpeg);
      if (_ffmpegPath != null) {
        appLogger.info(
          '✅ [YtDlp] FFmpeg repair succeeded — path now $_ffmpegPath',
        );
        return true;
      }
    }
    appLogger.error(
      '❌ [YtDlp] FFmpeg repair failed — high-quality DASH merge is not '
      'available. Likely cause on this machine: Defender quarantine, disk '
      'full, network down, or upstream CDN unreachable. The download will '
      'be marked failed with an actionable error rather than silently '
      'falling back to a 360p pre-muxed stream.',
    );
    return false;
  }

  /// Clean YouTube URL for single video extraction
  /// Strips playlist/radio params that slow down extraction
  /// Does NOT affect playlist feature (uses separate get_playlist_info path)
  static String _cleanYouTubeUrlForExtraction(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();

      // Only clean YouTube URLs
      final isYouTube =
          host.contains('youtube.com') || host.contains('youtu.be');
      if (!isYouTube) return url;

      // For youtu.be/XXX?list=YYY - strip playlist params
      if (host.contains('youtu.be')) {
        final params = Map<String, String>.from(uri.queryParameters);
        final hadPlaylist = params.containsKey('list');
        params.remove('list');
        params.remove('start_radio');
        params.remove('index');
        params.remove('si');
        if (hadPlaylist) {
          debugPrint('🧹 [YtDlp] Stripped playlist params from youtu.be URL');
        }
        return uri
            .replace(queryParameters: params.isEmpty ? null : params)
            .toString();
      }

      // For youtube.com/watch, /shorts/XXX, /live/XXX with playlist params
      final stripPaths = ['/watch', '/shorts', '/live'];
      final basePath =
          uri.pathSegments.isNotEmpty ? '/${uri.pathSegments.first}' : '';
      if (stripPaths.contains(basePath) || uri.path == '/watch') {
        final params = Map<String, String>.from(uri.queryParameters);
        final hadPlaylist = params.containsKey('list');
        params.remove('list');
        params.remove('start_radio');
        params.remove('index');
        params.remove('si');
        if (hadPlaylist) {
          debugPrint('🧹 [YtDlp] Stripped playlist params from YouTube URL');
        }
        return uri
            .replace(queryParameters: params.isEmpty ? null : params)
            .toString();
      }

      return url;
    } catch (_) {
      return url;
    }
  }

  /// Parse error type from a generic exception message (fallback for catch blocks).
  ///
  /// Precedence note: JS-runtime detection MUST come first. The Rust executor
  /// stringifies its [YtDlpError] via `anyhow::bail!("yt-dlp error: {:?} - {}", error, stderr)`
  /// in `native/src/ytdlp/executor.rs:321`, so the exception message Dart
  /// observes here can contain BOTH the typed Rust error name AND the full
  /// stderr block. When YouTube fails nsig because Deno is unhealthy, the
  /// stderr typically interleaves "Sign in to confirm…" warnings with
  /// "n challenge solving failed" — without JS-runtime precedence, the
  /// substring `LoginRequired` check below would win and the host app would
  /// drive the user into a cookie-refresh loop that cannot recover Deno.
  /// Mirrors precedence in [_parseErrorTypeFromStderr] and `parse_error`
  /// in `native/src/ytdlp/parser.rs`.
  static YtDlpErrorType _parseErrorTypeFromException(String errorStr) {
    if (_looksLikeJsRuntimeIssue(errorStr) ||
        errorStr.contains('JsRuntimeUnavailable')) {
      return YtDlpErrorType.jsRuntimeUnavailable;
    }
    if (errorStr.contains('FormatNotAvailable') ||
        errorStr.contains('format is not available')) {
      return YtDlpErrorType.formatNotAvailable;
    }
    if (errorStr.contains('NotFound')) return YtDlpErrorType.notFound;
    if (errorStr.contains('GeoRestricted')) return YtDlpErrorType.geoRestricted;
    if (errorStr.contains('LoginRequired')) return YtDlpErrorType.loginRequired;
    if (errorStr.contains('AgeRestricted')) return YtDlpErrorType.ageRestricted;
    if (errorStr.contains('Circuit breaker open')) {
      return YtDlpErrorType.circuitBreakerOpen;
    }
    if (errorStr.contains('RateLimited')) return YtDlpErrorType.rateLimited;
    if (errorStr.contains('NetworkError')) return YtDlpErrorType.networkError;
    if (errorStr.contains('timeout')) return YtDlpErrorType.timeout;
    return YtDlpErrorType.unknown;
  }

  /// Detect yt-dlp errors that indicate the external JS runtime
  /// (Deno) is missing or unhealthy. yt-dlp 2025.11.12+ surfaces these
  /// when it falls back to the deprecated built-in jsinterp:
  ///   - "n challenge solving failed"
  ///   - "Signature solving failed"
  ///   - "External JavaScript runtime not found"
  ///   - "deno: command not found"
  /// We also catch the misleading "could not find any usable JavaScript
  /// runtime" wording used by some yt-dlp versions.
  ///
  /// The classification matters because UI must NOT trigger the
  /// auto-login flow on these errors — re-authenticating cookies does
  /// nothing without a working JS runtime. UI should instead prompt
  /// the user to retry / report (the runtime download is then re-tried
  /// in the background by `BinaryManager`).
  static bool _looksLikeJsRuntimeIssue(String errorStr) {
    final lower = errorStr.toLowerCase();
    return lower.contains('n challenge solving failed') ||
        lower.contains('signature solving failed') ||
        lower.contains('external javascript runtime') ||
        lower.contains('no usable javascript runtime') ||
        lower.contains('could not find any usable javascript') ||
        lower.contains('deno:') &&
            (lower.contains('not found') ||
                lower.contains('command not found') ||
                lower.contains('no such file'));
  }

  /// Parse error type from yt-dlp stderr output (direct process, not via Rust)
  static YtDlpErrorType _parseErrorTypeFromStderr(String stderr) {
    final lower = stderr.toLowerCase();
    // Check JS runtime issues FIRST — yt-dlp's "n challenge solving
    // failed" / "Signature solving failed" stderr lines also contain
    // the word "format" further down, which would otherwise misroute
    // to formatNotAvailable. Routing precedence matters here.
    if (_looksLikeJsRuntimeIssue(stderr)) {
      return YtDlpErrorType.jsRuntimeUnavailable;
    }
    if (lower.contains('is not a valid url') ||
        lower.contains('unsupported url') ||
        lower.contains('unable to extract') ||
        lower.contains('video unavailable') ||
        lower.contains('this video is not available') ||
        lower.contains('not found')) {
      return YtDlpErrorType.notFound;
    }
    if (lower.contains('geo') ||
        lower.contains('not available in your country')) {
      return YtDlpErrorType.geoRestricted;
    }
    if (lower.contains('sign in') ||
        lower.contains('login') ||
        lower.contains('private video')) {
      return YtDlpErrorType.loginRequired;
    }
    if (lower.contains('age') || lower.contains('confirm your age')) {
      return YtDlpErrorType.ageRestricted;
    }
    if (lower.contains('format') && lower.contains('not available')) {
      return YtDlpErrorType.formatNotAvailable;
    }
    if (lower.contains('429') ||
        lower.contains('rate') ||
        lower.contains('too many')) {
      return YtDlpErrorType.rateLimited;
    }
    if (lower.contains('network') ||
        lower.contains('connection') ||
        lower.contains('timed out') ||
        lower.contains('urlopen')) {
      return YtDlpErrorType.networkError;
    }
    if (lower.contains('timeout')) return YtDlpErrorType.timeout;
    return YtDlpErrorType.unknown;
  }

  static bool _looksLikeHttp403(String stderr) {
    final lower = stderr.toLowerCase();
    return lower.contains('http error 403') ||
        lower.contains('403: forbidden') ||
        lower.contains('forbidden');
  }

  /// CUX-1: classify a non-zero-exit recode-contract failure by its REAL
  /// cause. When `--recode-video` produced no target-extension file AND the
  /// download/merge failed upstream (transport/auth/rate/network), the
  /// recode never ran — the honest cause is the upstream one, NOT "Recode
  /// failed, try MP4" (which sends the user chasing a container that will
  /// also fail). Returns the upstream [YtDlpErrorType] to surface, or null
  /// when no high-confidence upstream signal is present — i.e. the recode /
  /// encoder itself is the genuine failure, so the caller keeps the recode
  /// copy (the SAFE default).
  ///
  /// IMPORTANT: `stderr` here is the FULL accumulated process buffer. It
  /// carries (a) ffmpeg's own progress/header output — `rate` ⊂ `bitrate`,
  /// `not found` ⊂ `moov atom not found`, `format`+`not available` ⊂
  /// ffmpeg's "Requested output format … is not available" — and (b) the
  /// arbitrary, user-controlled video TITLE echoed by yt-dlp's
  /// [VideoConvertor] / [Merger] / [download] / ffmpeg-input lines (a video
  /// titled "Top 10 Forbidden Places" or "Connection Refused (Official
  /// Video)" would otherwise read as an HTTP 403 / network failure). So we
  /// (1) do NOT reuse [_parseErrorTypeFromStderr], and (2) match the tight
  /// tokens ONLY over yt-dlp's own `ERROR:`-prefixed diagnostic lines, where
  /// the real upstream failure is reported and the title never appears.
  ///
  /// The auth → [YtDlpErrorType.loginRequired] mapping is gated on YouTube
  /// WITHOUT cookies, so a signed-in user — or a "Sign in to confirm you are
  /// not a bot" line that fires even with cookies — is never looped back to
  /// a login they cannot repeat (it surfaces the generic access message).
  @visibleForTesting
  static YtDlpErrorType? classifyRecodeContractFailure({
    required String stderr,
    required bool isYouTube,
    required bool hasYouTubeCookies,
  }) {
    // Match ONLY yt-dlp's own fatal diagnostic lines (ERROR:-prefixed) so the
    // user-controlled video TITLE — echoed by [VideoConvertor]/[Merger]/
    // [download]/ffmpeg-input lines — can never be read as an upstream
    // signal. A genuine recode failure's only ERROR: line (e.g. "ERROR:
    // Postprocessing: …") carries none of these tokens → null (keep copy).
    final diag = const LineSplitter()
        .convert(stderr)
        .where((l) => l.trimLeft().toLowerCase().startsWith('error:'))
        .join('\n');
    final lower = diag.toLowerCase();
    final forbidden = _looksLikeHttp403(diag) ||
        lower.contains('http error 401') ||
        lower.contains('401: unauthorized');
    final rateLimited = lower.contains('http error 429') ||
        lower.contains('too many requests');
    final authBlocked = lower.contains('sign in to confirm') ||
        lower.contains('sign in to view') ||
        lower.contains('confirm your age') ||
        lower.contains('private video') ||
        lower.contains('this video is private') ||
        lower.contains('login required');
    final networkFail = lower.contains('urlopen error') ||
        lower.contains('unable to download webpage') ||
        lower.contains('connection refused') ||
        lower.contains('connection reset') ||
        lower.contains('getaddrinfo failed') ||
        lower.contains('temporary failure in name resolution');
    // No high-confidence upstream signal ⇒ the recode/encoder is the genuine
    // failure ⇒ keep the recode copy.
    if (!forbidden && !rateLimited && !authBlocked && !networkFail) {
      return null;
    }
    // Auth → login ONLY for YouTube without cookies (never loop a signed-in
    // user, and never push a "sign in" flow we cannot drive on other sites).
    if ((forbidden || authBlocked) && isYouTube && !hasYouTubeCookies) {
      return YtDlpErrorType.loginRequired;
    }
    if (rateLimited) return YtDlpErrorType.rateLimited;
    if (networkFail) return YtDlpErrorType.networkError;
    // Forbidden/auth with cookies present, or on a non-YouTube site: a
    // neutral upstream access denial — surfaced via the generic access
    // message, never a login prompt. `unknown` matches the type the
    // pre-CUX-1 "Recode failed" path already used (no retry-behaviour shift).
    return YtDlpErrorType.unknown;
  }

  /// CUX-1b: derive the terminal download-failure error type, NEVER surfacing
  /// [YtDlpErrorType.loginRequired] to a signed-in user. yt-dlp's "Sign in to
  /// confirm you are not a bot" / "Private video. Sign in" lines parse to
  /// loginRequired and fire even WITH cookies; routing those to a login
  /// prompt loops a user who is already authenticated. loginRequired is
  /// surfaced ONLY for YouTube WITHOUT cookies (where signing in genuinely
  /// helps); otherwise a login-parsed failure downgrades to a neutral
  /// upstream type so the message is the generic one, not "please sign in".
  @visibleForTesting
  static YtDlpErrorType inferDownloadFailureType({
    required String stderr,
    required bool isYouTube,
    required bool hasYouTubeCookies,
  }) {
    final parsed = _parseErrorTypeFromStderr(stderr);
    if (isYouTube &&
        !hasYouTubeCookies &&
        (_looksLikeHttp403(stderr) ||
            parsed == YtDlpErrorType.loginRequired)) {
      return YtDlpErrorType.loginRequired;
    }
    // Cookies present (already signed in) or a site we cannot drive a login
    // for → never loop the user back to a login.
    if (parsed == YtDlpErrorType.loginRequired) return YtDlpErrorType.unknown;
    return parsed;
  }

  /// CUX-1: a PII-safe, classifier-STABLE user/stored message for an upstream
  /// download failure of [type]. CRITICAL: downstream routing classifies on
  /// the MESSAGE string (DownloadErrorClassifier.classifyMessage), NOT on
  /// YtDlpException.type — so the wording IS the contract. Raw stderr is
  /// excluded (it carries filename/path/title/URL, AND prose like "sign in"
  /// would let classifyMessage re-derive loginRequired for a signed-in user
  /// → a login loop). 403/429 use the structured prefixes the classifier
  /// matches FIRST (HTTP_403_FORBIDDEN: → accessDenied, HTTP_429_… →
  /// rateLimited) — the same shape the Rust engine already emits, so prose
  /// substrings can never collapse them into the network bucket.
  @visibleForTesting
  static String upstreamErrorMessage(YtDlpErrorType type) {
    switch (type) {
      case YtDlpErrorType.loginRequired:
        return 'Login required: the site asked you to sign in to download '
            'this video. Sign in and retry.';
      case YtDlpErrorType.rateLimited:
        return 'HTTP_429_TOO_MANY_REQUESTS: the site is rate-limiting '
            'downloads right now — wait a moment and retry.';
      case YtDlpErrorType.networkError:
        return 'A network error interrupted the download before it finished '
            '— check your internet and retry.';
      default:
        return 'HTTP_403_FORBIDDEN: the site refused the download (access '
            'denied) — not a recode problem.';
    }
  }

  static String _firstMeaningfulStderrLine(String stderr) {
    for (final line in const LineSplitter().convert(stderr)) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return 'unknown';
  }

  static String _truncateForTelemetry(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}…';
  }

  static String _youtubeCookieSource({
    required bool hasYouTubeCookies,
    required String? cookiesFile,
    required String? cookiesFromBrowser,
  }) {
    if (!hasYouTubeCookies) return 'none';
    if (cookiesFile != null) return 'file';
    if (cookiesFromBrowser != null) return 'browser:$cookiesFromBrowser';
    return 'unknown';
  }

  Map<String, dynamic> _buildYouTubeExtractFailureMetadata({
    required bool isYouTube,
    required bool hasYouTubeCookies,
    required String? cookiesFile,
    required String? cookiesFromBrowser,
    required String? extractorClient,
    required YouTubePotProviderPaths? potProviderPaths,
    required YtDlpErrorType errorType,
    required String errorText,
  }) {
    return {
      'stage': 'extract',
      'path': Platform.isWindows ? 'native-windows' : 'dart-process',
      'yt_dlp_channel': ytDlpReleaseChannel,
      'yt_dlp_version': _version ?? 'unknown',
      'is_youtube': isYouTube,
      'has_youtube_cookies': hasYouTubeCookies,
      'cookie_source': _youtubeCookieSource(
        hasYouTubeCookies: hasYouTubeCookies,
        cookiesFile: cookiesFile,
        cookiesFromBrowser: cookiesFromBrowser,
      ),
      'pot_provider_enabled': potProviderPaths != null,
      'player_client':
          extractorClient?.isNotEmpty == true ? extractorClient : 'default',
      'deno_present': _denoPath != null,
      'parsed_error_type': errorType.name,
      'looks_like_http_403': _looksLikeHttp403(errorText),
      'stderr_excerpt': _truncateForTelemetry(errorText, 500),
    };
  }

  /// Parse yt-dlp --dump-json output into [YtDlpVideoInfo].
  /// Replicates Rust's parse_video_info() + DTO conversion in pure Dart.
  static YtDlpVideoInfo _parseVideoInfoJson(String jsonStr) {
    final raw = jsonDecode(jsonStr) as Map<String, dynamic>;

    // Parse upload date (YYYYMMDD → DateTime)
    DateTime? uploadDate;
    final udStr = raw['upload_date'] as String?;
    if (udStr != null && udStr.length == 8) {
      try {
        uploadDate = DateTime(
          int.parse(udStr.substring(0, 4)),
          int.parse(udStr.substring(4, 6)),
          int.parse(udStr.substring(6, 8)),
        );
      } catch (_) {}
    }

    // Parse formats
    final rawFormats = raw['formats'] as List<dynamic>? ?? [];
    final formats =
        rawFormats.map((f) => _parseFormat(f as Map<String, dynamic>)).toList();

    // Parse subtitles (HashMap<String, List> → flat list)
    final subtitles = _parseSubtitles(
      raw['subtitles'] as Map<String, dynamic>?,
    );
    final autoCaptions = _parseSubtitles(
      raw['automatic_captions'] as Map<String, dynamic>?,
    );

    // Parse chapters — filter out malformed entries where endTime <= startTime
    // (can happen with non-standard extractors or truncated metadata).
    final rawChapters = raw['chapters'] as List<dynamic>? ?? [];
    final chapters =
        rawChapters
            .map((c) => _parseChapter(c as Map<String, dynamic>))
            .where((c) => c.endTime > c.startTime)
            .toList();

    // Determine live status
    final isLive = raw['is_live'] as bool? ?? false;
    final liveStatus = raw['live_status'] as String?;

    // Helper to clean negative counts (yt-dlp sometimes returns -1)
    int? cleanCount(dynamic v) {
      if (v == null) return null;
      final n = (v as num).toInt();
      return n >= 0 ? n : null;
    }

    final extractor =
        raw['extractor'] as String? ?? raw['extractor_key'] as String?;

    return YtDlpVideoInfo(
      id: (raw['id'] as String?) ?? '',
      title: (raw['title'] as String?) ?? '',
      description: raw['description'] as String?,
      uploader: (raw['uploader'] as String?) ?? (raw['channel'] as String?),
      uploaderId:
          (raw['uploader_id'] as String?) ?? (raw['channel_id'] as String?),
      duration:
          raw['duration'] != null
              ? Duration(
                seconds: (raw['duration'] as num).toInt().clamp(0, 999999),
              )
              : null,
      viewCount: cleanCount(raw['view_count']),
      likeCount: cleanCount(raw['like_count']),
      uploadDate: uploadDate,
      thumbnail: raw['thumbnail'] as String?,
      webpageUrl: raw['webpage_url'] as String?,
      platform: YtDlpVideoInfo._extractPlatform(extractor),
      formats: formats,
      subtitles: subtitles,
      automaticCaptions: autoCaptions,
      chapters: chapters,
      isLive: isLive,
      liveStatus: liveStatus,
    );
  }

  static YtDlpFormat _parseFormat(Map<String, dynamic> f) {
    int? cleanDim(dynamic v) {
      if (v == null) return null;
      final n = (v as num).toInt();
      return n > 0 ? n : null;
    }

    int? cleanSize(dynamic v) {
      if (v == null) return null;
      final n = (v as num).toInt();
      return n > 0 ? n : null;
    }

    return YtDlpFormat(
      formatId: (f['format_id'] as String?) ?? '',
      ext: (f['ext'] as String?) ?? '',
      resolution: f['resolution'] as String?,
      height: cleanDim(f['height']),
      width: cleanDim(f['width']),
      filesize: cleanSize(f['filesize']) ?? cleanSize(f['filesize_approx']),
      vcodec: f['vcodec'] as String?,
      acodec: f['acodec'] as String?,
      fps: (f['fps'] as num?)?.toDouble(),
      tbr: (f['tbr'] as num?)?.toDouble(),
      formatNote: f['format_note'] as String?,
    );
  }

  static List<YtDlpSubtitleInfo> _parseSubtitles(
    Map<String, dynamic>? subsMap,
  ) {
    if (subsMap == null) return [];
    final result = <YtDlpSubtitleInfo>[];
    for (final entry in subsMap.entries) {
      final lang = entry.key;
      final subs = entry.value as List<dynamic>? ?? [];
      for (final s in subs) {
        final sub = s as Map<String, dynamic>;
        result.add(
          YtDlpSubtitleInfo(
            lang: lang,
            langName: sub['name'] as String?,
            ext: (sub['ext'] as String?) ?? 'vtt',
            url: sub['url'] as String?,
          ),
        );
      }
    }
    return result;
  }

  static YtDlpChapterInfo _parseChapter(Map<String, dynamic> c) {
    return YtDlpChapterInfo(
      title: (c['title'] as String?) ?? 'Untitled',
      startTime: (c['start_time'] as num?)?.toDouble() ?? 0.0,
      endTime: (c['end_time'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Parse a progress line from yt-dlp output
  Future<YtDlpProgress?> parseProgress(String line) async {
    final dto = await native.ytdlpParseProgress(line: line);
    if (dto == null) return null;
    return YtDlpProgress.fromDto(dto);
  }

  /// Active download processes for cancellation support
  final Map<String, Process> _activeProcesses = {};

  /// Maps download ID → process key for per-download cancellation.
  /// Without this, cancelling by URL kills ALL qualities for that URL.
  final Map<int, String> _downloadIdToProcessKey = {};

  /// Cancel a single download by its database ID.
  /// Only kills the specific process for this download, leaving other
  /// qualities of the same URL untouched.
  Future<void> cancelByDownloadId(int downloadId) async {
    final processKey = _downloadIdToProcessKey.remove(downloadId);
    if (processKey == null) return;
    await _cancelProcess(processKey);
  }

  /// Cancel ALL active download(s) by URL.
  /// Used for bulk cancellation (e.g., "cancel all" or URL removal).
  Future<void> cancelDownload(String url) async {
    // Find all process keys that start with this URL
    final matchingKeys =
        _activeProcesses.keys
            .where((key) => key.startsWith('$url\x00') || key == url)
            .toList();

    for (final key in matchingKeys) {
      await _cancelProcess(key);
    }
    // Clean up ID mappings for this URL
    _downloadIdToProcessKey.removeWhere(
      (_, key) => key.startsWith('$url\x00') || key == url,
    );
  }

  /// Kill a single process by its composite key.
  Future<void> _cancelProcess(String processKey) async {
    final process = _activeProcesses[processKey];
    if (process == null) {
      _activeProcesses.remove(processKey);
      return;
    }

    debugPrint('🛑 [YtDlp] Terminating download process: $processKey');
    _cancelledProcessKeys.add(processKey);

    try {
      // Try graceful termination first (SIGTERM)
      process.kill(ProcessSignal.sigterm);

      // Wait up to 5 seconds for process to terminate
      await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('⚠️ [YtDlp] Process did not terminate, force killing...');
          // SIGKILL only on Unix — Windows only supports SIGTERM (maps to TerminateProcess)
          if (!Platform.isWindows) {
            process.kill(ProcessSignal.sigkill);
          }
          return -1; // Return dummy exit code
        },
      );

      debugPrint('✅ [YtDlp] Process terminated successfully');
    } catch (e) {
      debugPrint('❌ [YtDlp] Error during cancellation: $e');
      // Force kill as last resort (Unix only)
      if (!Platform.isWindows) {
        try {
          process.kill(ProcessSignal.sigkill);
        } catch (_) {}
      }
    } finally {
      _activeProcesses.remove(processKey);
    }
  }

  /// Check if a process was cancelled by the user.
  /// Uses explicit tracking (not exit codes) to avoid Windows exit code 1
  /// collision: TerminateProcess returns 1, but FFmpeg errors also return 1.
  /// Without this, any FFmpeg failure on Windows was misclassified as "cancelled",
  /// skipping the file-existence safety net and retry logic.
  bool _wasUserCancelled(String processKey, int exitCode) {
    // Explicit user cancellation (tracked in _cancelProcess)
    if (_cancelledProcessKeys.remove(processKey)) return true;
    // Unix SIGTERM signals (unambiguous — no collision with normal errors)
    if (exitCode == -15 || exitCode == 143) return true;
    return false;
  }

  @visibleForTesting
  static String audioQualityArgForTest(int? bitrateKbps) =>
      _audioQualityArg(bitrateKbps);

  @visibleForTesting
  static bool shouldEnforceAudioBitrateForTest({
    required String? audioFormat,
    required int? audioBitrateKbps,
  }) => _shouldEnforceAudioBitrate(
    audioFormat: audioFormat,
    audioBitrateKbps: audioBitrateKbps,
  );

  @visibleForTesting
  static bool audioBitrateCloseEnoughForTest({
    required int actualKbps,
    required int targetKbps,
  }) => _audioBitrateCloseEnough(actualKbps, targetKbps);

  @visibleForTesting
  static List<String> audioBitrateRecodeArgsForTest({
    required String inputPath,
    required String outputPath,
    required String audioFormat,
    required int bitrateKbps,
  }) => _audioBitrateRecodeArgs(
    inputPath: inputPath,
    outputPath: outputPath,
    audioFormat: audioFormat,
    bitrateKbps: bitrateKbps,
  );

  @visibleForTesting
  static bool shouldRecodeAudioBitrateForTest({
    required String? audioFormat,
    required int? audioBitrateKbps,
    required int? actualBitrateKbps,
  }) => _shouldRecodeAudioBitrate(
    audioFormat: audioFormat,
    audioBitrateKbps: audioBitrateKbps,
    actualBitrateKbps: actualBitrateKbps,
  );

  static String _audioQualityArg(int? bitrateKbps) {
    if (bitrateKbps == null || bitrateKbps <= 0) return '0';
    return '${bitrateKbps}K';
  }

  static String? _normalizeAudioOutputFormat(String? audioFormat) {
    final normalized = audioFormat?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    if (normalized == 'aac') return 'm4a';
    return normalized;
  }

  static String? _audioScanExtension(String? audioFormat) =>
      _normalizeAudioOutputFormat(audioFormat);

  @visibleForTesting
  static String? audioScanExtensionForTest(String? audioFormat) =>
      _audioScanExtension(audioFormat);

  static bool _isLosslessAudioOutputFormat(String? audioFormat) {
    switch (_normalizeAudioOutputFormat(audioFormat)) {
      case 'wav':
      case 'flac':
        return true;
      default:
        return false;
    }
  }

  static bool _shouldEnforceAudioBitrate({
    required String? audioFormat,
    required int? audioBitrateKbps,
  }) {
    if (audioBitrateKbps == null || audioBitrateKbps <= 0) return false;
    final normalized = _normalizeAudioOutputFormat(audioFormat);
    if (normalized == null) return false;
    return !_isLosslessAudioOutputFormat(normalized);
  }

  static bool _audioBitrateCloseEnough(int actualKbps, int targetKbps) {
    final tolerance = max(6, (targetKbps * 0.08).round());
    return (actualKbps - targetKbps).abs() <= tolerance;
  }

  static bool _shouldRecodeAudioBitrate({
    required String? audioFormat,
    required int? audioBitrateKbps,
    required int? actualBitrateKbps,
  }) {
    if (!_shouldEnforceAudioBitrate(
      audioFormat: audioFormat,
      audioBitrateKbps: audioBitrateKbps,
    )) {
      return false;
    }
    // Wave B (AUD-4) — the bitrate setting is a size CEILING, not a
    // synthesis target. yt-dlp's ExtractAudio stream-copies when the
    // source codec already matches the target (m4a-from-AAC,
    // mp3-from-mp3); the old |actual−target| check then re-encoded
    // that perfect copy UP toward the dialog default of 320k
    // (YouTube AAC is ~131k) — generation loss + ~2.4× file bloat +
    // a fabricated bitrate, with zero quality gain. The code even
    // logged "cannot improve source quality" and proceeded anyway.
    // Only recode DOWN when the actual bitrate exceeds the requested
    // ceiling beyond tolerance.
    //
    // Probe failure (null) fails OPEN: never burn a full re-encode
    // on an unknown — a 15s ffprobe timeout used to trigger exactly
    // that.
    if (actualBitrateKbps == null) return false;
    final tolerance = max(6, (audioBitrateKbps! * 0.08).round());
    return actualBitrateKbps > audioBitrateKbps + tolerance;
  }

  static String? _audioEncoderForOutputFormat(String? audioFormat) {
    switch (_normalizeAudioOutputFormat(audioFormat)) {
      case 'm4a':
        return 'aac';
      case 'mp3':
        return 'libmp3lame';
      case 'opus':
        return 'libopus';
      default:
        return null;
    }
  }

  static List<String> _audioBitrateRecodeArgs({
    required String inputPath,
    required String outputPath,
    required String audioFormat,
    required int bitrateKbps,
  }) {
    final encoder = _audioEncoderForOutputFormat(audioFormat);
    if (encoder == null) return const [];
    return [
      '-y',
      '-i',
      inputPath,
      '-vn',
      '-c:a',
      encoder,
      '-b:a',
      '${bitrateKbps}k',
      if (_normalizeAudioOutputFormat(audioFormat) == 'm4a') ...[
        '-movflags',
        '+faststart',
      ],
      outputPath,
    ];
  }

  String _ffprobePathForFfmpeg(String ffmpegPath) {
    return ffmpegPath.replaceAll(
      RegExp(r'ffmpeg(\.exe)?$'),
      ffmpegPath.endsWith('.exe') ? 'ffprobe.exe' : 'ffprobe',
    );
  }

  Future<bool> _hasFfprobe() async {
    final ffmpegPath = _ffmpegPath;
    if (ffmpegPath == null) return false;
    return File(_ffprobePathForFfmpeg(ffmpegPath)).exists();
  }

  Future<int?> _probeAudioBitrateKbps(String filePath) async {
    final ffmpegPath = _ffmpegPath;
    if (ffmpegPath == null) return null;
    final ffprobePath = _ffprobePathForFfmpeg(ffmpegPath);
    if (!await File(ffprobePath).exists()) return null;

    try {
      // P0 (2026-05-25 Windows audio recode bug): ffprobe path resolves
      // under `%APPDATA%\Bui Xuan Mai\<ProductName>\bin\ffprobe.exe`
      // which has spaces. Going through `ProcessHelper.run` (which
      // shells via cmd.exe on Windows) truncates the path at the
      // first space. `runDirect` bypasses the shell so the executable
      // path with spaces is passed verbatim to CreateProcessW.
      final result = await ProcessHelper.runDirect(ffprobePath, [
        '-v',
        'error',
        '-select_streams',
        'a:0',
        '-show_entries',
        'stream=bit_rate:format=bit_rate',
        '-of',
        'json',
        filePath,
      ]).timeout(const Duration(seconds: 15));
      if (result.exitCode != 0) return null;
      final stdout = (result.stdout as String).trim();
      if (stdout.isEmpty) return null;
      final decoded = jsonDecode(stdout);
      if (decoded is! Map<String, dynamic>) return null;

      final streams = decoded['streams'];
      if (streams is List && streams.isNotEmpty) {
        final first = streams.first;
        if (first is Map) {
          final bps = int.tryParse('${first['bit_rate'] ?? ''}');
          if (bps != null && bps > 0) return (bps / 1000).round();
        }
      }

      final format = decoded['format'];
      if (format is Map) {
        final bps = int.tryParse('${format['bit_rate'] ?? ''}');
        if (bps != null && bps > 0) return (bps / 1000).round();
      }
    } catch (e) {
      appLogger.debug('[YtDlp] Audio bitrate probe skipped: $e');
    }
    return null;
  }

  Future<_VideoDimensions?> _probeVideoDimensions(String filePath) async {
    final ffmpegPath = _ffmpegPath;
    if (ffmpegPath == null) return null;
    final ffprobePath = _ffprobePathForFfmpeg(ffmpegPath);
    if (!await File(ffprobePath).exists()) return null;

    try {
      final result = await ProcessHelper.runDirect(ffprobePath, [
        '-v',
        'error',
        '-select_streams',
        'v:0',
        '-show_entries',
        'stream=width,height',
        '-of',
        'json',
        filePath,
      ]).timeout(const Duration(seconds: 30));
      if (result.exitCode != 0) return null;
      final stdout = (result.stdout as String).trim();
      if (stdout.isEmpty) return null;
      final decoded = jsonDecode(stdout);
      if (decoded is! Map<String, dynamic>) return null;

      final streams = decoded['streams'];
      if (streams is! List || streams.isEmpty) return null;
      final first = streams.first;
      if (first is! Map) return null;
      final width = int.tryParse('${first['width'] ?? ''}');
      final height = int.tryParse('${first['height'] ?? ''}');
      if (width == null || height == null || width <= 0 || height <= 0) {
        return null;
      }
      return _VideoDimensions(width: width, height: height);
    } catch (e) {
      appLogger.debug('[YtDlp] Video dimension probe skipped: $e');
    }
    return null;
  }

  Future<String> _forceAudioBitrateRecode({
    required String inputPath,
    required String audioFormat,
    required int bitrateKbps,
  }) async {
    final ffmpegPath = _ffmpegPath;
    if (ffmpegPath == null) {
      throw YtDlpException(
        YtDlpErrorType.binaryNotFound,
        'FFmpeg is required to encode audio at ${bitrateKbps}kbps.',
      );
    }

    final argsProbe = _audioBitrateRecodeArgs(
      inputPath: inputPath,
      outputPath: inputPath,
      audioFormat: audioFormat,
      bitrateKbps: bitrateKbps,
    );
    if (argsProbe.isEmpty) return inputPath;

    final ext = path.extension(inputPath);
    final basename = path.basenameWithoutExtension(inputPath);
    final tempPath = path.join(
      path.dirname(inputPath),
      '.$basename.audio-${bitrateKbps}k.tmp$ext',
    );
    try {
      final tempFile = File(tempPath);
      if (await tempFile.exists()) await tempFile.delete();

      final args = _audioBitrateRecodeArgs(
        inputPath: inputPath,
        outputPath: tempPath,
        audioFormat: audioFormat,
        bitrateKbps: bitrateKbps,
      );
      appLogger.info(
        '[YtDlp] Enforcing audio bitrate: ${path.basename(inputPath)} -> '
        '${bitrateKbps}kbps ($audioFormat)',
      );
      // P0 (2026-05-25 Windows audio recode bug): exact production
      // failure path. ffmpeg path = `%APPDATA%\Bui Xuan Mai\
      // VidCombo Desktop\bin\ffmpeg.exe` (space in CompanyName). The
      // previous `ProcessHelper.run` wrapped this in `cmd /c
      // <ffmpeg-path> <args>` and cmd.exe truncated at the first
      // space → "'C:\Users\<u>\AppData\Roaming\Bui' is not recognized
      // as an internal or external command". `runDirect` bypasses
      // the shell so the path-with-spaces is passed verbatim.
      final result = await ProcessHelper.runDirect(
        ffmpegPath,
        args,
      ).timeout(const Duration(hours: 2));
      final recoded = File(tempPath);
      if (result.exitCode != 0 ||
          !await recoded.exists() ||
          await recoded.length() == 0) {
        if (await recoded.exists()) await recoded.delete();
        throw YtDlpException(
          YtDlpErrorType.unknown,
          'Could not encode audio to ${bitrateKbps}kbps. '
          '${(result.stderr as String).trim()}',
        );
      }

      final original = File(inputPath);
      final backupPath = path.join(
        path.dirname(inputPath),
        '.${path.basename(inputPath)}.before-audio-bitrate-recode',
      );
      final backup = File(backupPath);
      if (await backup.exists()) await backup.delete();

      await original.rename(backupPath);
      try {
        await recoded.rename(inputPath);
        await backup.delete();
      } catch (e) {
        if (!await original.exists() && await backup.exists()) {
          await backup.rename(inputPath);
        }
        rethrow;
      }
      return inputPath;
    } on YtDlpException {
      rethrow;
    } catch (e) {
      try {
        final tempFile = File(tempPath);
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
      throw YtDlpException(
        YtDlpErrorType.unknown,
        'Could not encode audio to ${bitrateKbps}kbps: $e',
      );
    }
  }

  /// N4 salvage — transcode a VP9-in-MKV (the PO-Token/SABR fallback the
  /// C3 guard catches) into a real H.264/AAC `.mp4`. One controlled ffmpeg
  /// pass, modeled on [_forceAudioBitrateRecode]'s atomic temp+rename
  /// discipline so a failed pass leaves the original `.mkv` untouched and
  /// the caller falls through to the C3 hard-fail. Returns the new `.mp4`
  /// path on success, null on any failure.
  Future<String?> _salvageVp9Mp4Recode(String inputPath) async {
    final ffmpegPath = _ffmpegPath;
    if (ffmpegPath == null) return null;
    if (!await File(inputPath).exists()) return null;

    final basename = path.basenameWithoutExtension(inputPath);
    final outputPath = path.join(path.dirname(inputPath), '$basename.mp4');
    final tempPath = path.join(
      path.dirname(inputPath),
      '.$basename.vp9-mp4-recode.tmp.mp4',
    );
    try {
      final tempFile = File(tempPath);
      if (await tempFile.exists()) await tempFile.delete();

      appLogger.info(
        '[YtDlp] VP9→MP4 salvage recode: ${path.basename(inputPath)} → '
        '${path.basename(outputPath)}',
      );
      final result = await ProcessHelper.runDirect(ffmpegPath, [
        '-y',
        '-i',
        inputPath,
        '-c:v',
        'libx264',
        '-c:a',
        'aac',
        '-movflags',
        '+faststart',
        tempPath,
      ]).timeout(const Duration(hours: 2));
      final recoded = File(tempPath);
      if (result.exitCode != 0 ||
          !await recoded.exists() ||
          await recoded.length() == 0) {
        if (await recoded.exists()) await recoded.delete();
        appLogger.error(
          '[YtDlp] VP9→MP4 salvage failed (exit ${result.exitCode}): '
          '${(result.stderr as String).trim()}',
        );
        return null;
      }

      final out = File(outputPath);
      if (await out.exists() &&
          path.normalize(outputPath) != path.normalize(inputPath)) {
        await out.delete();
      }
      await recoded.rename(outputPath);
      if (path.normalize(inputPath) != path.normalize(outputPath)) {
        try {
          await File(inputPath).delete();
        } catch (_) {}
      }
      return _ytdlpPath(outputPath);
    } catch (e) {
      try {
        final tempFile = File(tempPath);
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
      appLogger.error('[YtDlp] VP9→MP4 salvage threw: $e');
      return null;
    }
  }

  Future<String?> _resolveAudioOutputFile({
    required String isolatedTempDir,
    required String? resolvedOutputFile,
    required String? audioFormat,
  }) async {
    final expectedExt = _audioScanExtension(audioFormat);
    if (resolvedOutputFile != null && await File(resolvedOutputFile).exists()) {
      if (expectedExt == null ||
          resolvedOutputFile.toLowerCase().endsWith('.$expectedExt')) {
        return resolvedOutputFile;
      }
    }
    if (expectedExt == null) return resolvedOutputFile;
    final scanned = await _findFileWithExtension(isolatedTempDir, expectedExt);
    if (scanned != null) {
      debugPrint(
        '✅ [YtDlp] Audio final-path scan promoted "$scanned" '
        'over stale path "$resolvedOutputFile"',
      );
      return scanned;
    }
    return resolvedOutputFile;
  }

  Future<String> _enforceAudioBitrateIfNeeded({
    required String filePath,
    required String? audioFormat,
    required int? audioBitrateKbps,
  }) async {
    if (!_shouldEnforceAudioBitrate(
      audioFormat: audioFormat,
      audioBitrateKbps: audioBitrateKbps,
    )) {
      return filePath;
    }

    final targetKbps = audioBitrateKbps!;
    final actualKbps = await _probeAudioBitrateKbps(filePath);
    if (!_shouldRecodeAudioBitrate(
      audioFormat: audioFormat,
      audioBitrateKbps: audioBitrateKbps,
      actualBitrateKbps: actualKbps,
    )) {
      appLogger.debug(
        '[YtDlp] Audio bitrate within ceiling — keeping the original '
        'stream: actual=${actualKbps}kbps, requested=${targetKbps}kbps '
        '(Wave B: never up-convert a stream-copy; recode only when the '
        'actual bitrate EXCEEDS the ceiling)',
      );
      return filePath;
    }

    return _forceAudioBitrateRecode(
      inputPath: filePath,
      audioFormat: audioFormat!,
      bitrateKbps: targetKbps,
    );
  }

  /// Download video with real-time progress streaming
  /// Uses Dart subprocess directly for better progress control
  ///
  /// NO extractor-args = ALL formats available (31+ for YouTube)
  /// This MUST match Rust extraction for consistent format availability.
  /// If 403 error occurs, user should provide cookies for authentication.
  ///
  /// The stream supports cancellation - when the subscription is cancelled,
  /// the yt-dlp process will be terminated.
  Stream<YtDlpProgressEvent> downloadWithProgress({
    required String url,
    required String outputDir,
    int? downloadId,
    String? outputTemplate,
    String? format,
    String? sortOptions,
    String? cookiesFile,
    String? cookiesFromBrowser,
    bool extractAudio = false,
    String? audioFormat,
    int? audioBitrateKbps,
    String? videoFormat,
    String? mergeFormatPriority,

    /// When non-null, yt-dlp stream-copies the merged output into the
    /// target container via `--remux-video <ext>` (no re-encode, fast,
    /// lossless). Used by ContainerPlanner's "pick X → get X" fast
    /// path — e.g. TikTok source MP4 + user picks MKV → remux to MKV.
    /// Mutually exclusive with [recodeVideo]; the planner emits at
    /// most one.
    String? remuxVideo,

    /// When non-null, yt-dlp post-processes the merged output via
    /// `--recode-video <ext>` (full ffmpeg re-encode). Used when the
    /// user-chosen container cannot hold the source codecs (e.g.
    /// YouTube ≥1440p VP9/Opus + user picks MP4) OR for the recoded
    /// container tier (avi/mov/m4v/flv). Native containers in the
    /// happy path pass `null` and use [remuxVideo] instead.
    String? recodeVideo,
    int? maxVideoHeight,
    int? targetVideoHeight,
    // === P0 Features ===
    bool subtitlesEnabled = false,
    List<String> subtitlesLanguages = const ['en'],
    String subtitlesFormat = 'srt',
    bool embedSubtitles = false,
    bool includeAutoSubs = false,
    bool writeThumbnail = false,
    bool embedThumbnail = false,
    bool embedMetadata = false,
    bool embedChapters = false,
    bool sponsorBlockEnabled = false,
    String sponsorBlockAction = 'skip',
    List<String> sponsorBlockCategories = const ['sponsor'],
    // === P1 Features ===
    bool splitChapters = false,
    bool liveFromStart = false,
    bool forceRemux = false,
    // === P2 Features ===
    bool tiktokRemoveWatermark = true,
    // === P3 Features ===
    String? proxyUrl,
    bool geoBypass = false,
    String? geoBypassCountry,
    bool archiveEnabled = false,
    String? archiveFile,
    String? dateAfter,
    String? dateBefore,
    int? minDuration,
    int? maxDuration,
    // === Network Tuning ===
    int socketTimeout = 30,
    int maxRetries = 3,
    int httpChunkSizeMb = 10,
    int? speedLimitBytes,
    // === Custom Postprocessor Args ===
    String customPostprocessorArgs = '',
    // === Section download ===
    Duration? sectionStartTime,
    Duration? sectionEndTime,
    // Per-chapter selection — list of (start, end) time ranges. yt-dlp emits
    // one --download-sections flag per entry and concatenates the matching
    // segments into a single output file. Ignored when sectionStartTime is set
    // (explicit time-range slider takes precedence).
    List<(Duration, Duration)>? selectedChapterRanges,
    // === Subtitle-only download ===
    bool skipDownload = false,
    // === Post-processing robustness ===
    bool keepVideo = false,
    // === Resume support ===
    String? existingTempDir, // Reuse persisted temp dir for --continue resume
    void Function(String tempDirPath)?
    onTempDirCreated, // Callback to persist temp dir path
  }) async* {
    // Auto-initialize if not yet done (e.g., user downloads from cached extraction)
    if (_binaryPath == null) {
      await initialize();
    }

    final template = outputTemplate ?? '%(title)s.%(ext)s';

    // Download to isolated temp dir, then move final file(s) to outputDir.
    // Prevents cloud sync services (Dropbox, OneDrive, Google Drive, iCloud)
    // from locking intermediate files (.temp.mp4, .part) during download/merge,
    // which causes WinError 5/32 rename failures on Windows.
    final isolatedTempDir = await _createIsolatedTempDir(
      downloadId: downloadId,
      existingTempDir: existingTempDir,
    );
    // Notify caller of the temp dir path so it can persist it in DB for resume
    onTempDirCreated?.call(isolatedTempDir);
    final outputPath = _ytdlpPath(path.join(isolatedTempDir, template));

    // Authoritative final-path sidecar. yt-dlp writes the post-PP final
    // filepath here AFTER --recode-video, --embed-*, AND --move-files
    // have all run. Reading stdout's [Merger] / [download] Destination
    // lines was the legacy path-tracking strategy, but it misses the
    // [VideoConvertor] step — so when a user chose AVI/MOV the Dart
    // side still recorded the .mkv merge intermediate as "the output"
    // and the actual recoded .avi got orphaned in the temp dir.
    // Routing the path through a dedicated sidecar file (not stdout)
    // bypasses the JSON-progress parser and gives a single, ordered
    // post-exit read for the authoritative path.
    final finalPathSidecar = path.join(isolatedTempDir, '.final_path');

    // Unique process key: include download ID to prevent collision when
    // same URL + same template run concurrently (e.g. two video qualities
    // that got the same filename before yt-dlp created the file).
    // URL prefix preserved so cancelDownload(url) bulk-cancel still works.
    final processKey =
        downloadId != null
            ? '$url\x00$template\x00$downloadId'
            : '$url\x00$template';

    // Build command arguments - MUST match Rust executor.rs config
    // Refresh Deno path — user may have completed binary setup after init.
    _denoPath = await _binaryManager.getBinaryPath(BinaryType.deno);
    final ytdlpUrl = _cleanUrlForYtDlp(url);
    final useDefaultNetworkProfile = _usesDefaultNetworkProfileForUrl(ytdlpUrl);
    // Referer stamped by the browser media-sniff panel — some CDNs (znews.vn)
    // reject segment requests without the article page as Referer. Null for
    // all non-stamped downloads; see DownloadRefererHolder.
    final sniffReferer =
        DownloadRefererHolder.lookup(ytdlpUrl) ??
        DownloadRefererHolder.lookup(url);

    final args = <String>[
      '--newline', // Progress on each line
      '--progress', // Show progress
      '--continue', // Resume partial .part files if they exist
      '--no-warnings',
      '--no-playlist',
      if (!useDefaultNetworkProfile) '--no-check-certificates',
      // Deno JS runtime — required for YouTube downloads to receive real
      // streaming URLs (n-challenge / nsig signature solving). Without it
      // the download path would silently fail on YouTube, surfacing
      // misleading "format not available" errors in production. Same flag
      // shape as the extract path — see args list at the top of
      // `extractInfo` for the full rationale.
      if (!useDefaultNetworkProfile && _denoPath != null) ...[
        '--js-runtimes',
        'deno:$_denoPath',
      ],
      if (!useDefaultNetworkProfile) ...[
        '--http-chunk-size',
        '${httpChunkSizeMb}M',
      ],
      // NO extractor-args = ALL formats available (same as Rust extraction)
      // If 403 error occurs, user should provide cookies for authentication
      if (!useDefaultNetworkProfile) ...[
        '--user-agent',
        _userAgentService.getRandomUserAgent(),
      ],
      // Keep the legacy network tuning for most sites, but let TikTok use
      // yt-dlp's default request fingerprint. Runtime A/B on a playable
      // landscape TikTok showed selector+postprocess succeeds with the default
      // profile, while the app network profile can fail extraction with
      // "universal data for rehydration".
      if (_shouldForceIpv4ForUrl(ytdlpUrl)) '--force-ipv4',
      if (sniffReferer != null) ...['--referer', sniffReferer],
      '-o', outputPath,
      // WIN-1b: for a custom user `filenameTemplate` the app cannot literal-
      // bound (yt-dlp expands `%(title)s` etc. after launch), cap the expanded
      // stem so the produced path fits Windows MAX_PATH. Computed from the
      // user's outputDir + the WORST-CASE temp dir (stable across retry/resume,
      // unlike the live temp dir) so the trimmed name never shifts and orphans
      // a `.part`. A no-op for the default already-bounded literal path
      // (N ≥ the app-side bound) and on POSIX.
      ...FileUtils.windowsTrimFilenamesArgs(
        candidateDirs: [outputDir, worstCaseIsolatedTempDir()],
        windows: Platform.isWindows,
      ),
      // Authoritative final-path capture — see comment above the sidecar
      // `post_process:filepath` fires after EACH postprocessor and
      // appends the current `info['filepath']` value. After the
      // recode-video PP completes, this captures the .avi/.mov/etc
      // path. We use `post_process` instead of `after_move` because
      // the app uses direct `-o <path>` (no `-P paths`), so yt-dlp's
      // move postprocessor is NOT in the PP chain — `after_move`
      // would never fire and the sidecar would stay empty. Multiple
      // PPs each write one line; `_readFinalPathSidecar` keeps the
      // LAST line so the post-recode path wins.
      '--print-to-file', 'post_process:filepath',
      _ytdlpPath(finalPathSidecar),
    ];

    // Speed throttle to avoid 429/rate-limiting
    if (speedLimitBytes != null && speedLimitBytes > 0) {
      args.addAll(['--limit-rate', '$speedLimitBytes']);
    }

    // Refresh FFmpeg path — user may have downloaded it after initialization
    _ffmpegPath = await _binaryManager.getBinaryPath(BinaryType.ffmpeg);
    // Add FFmpeg location if available (required for merging video+audio)
    if (_ffmpegPath != null) {
      args.addAll(['--ffmpeg-location', _ytdlpPath(_ffmpegPath!)]);
    } else if (format != null && format.contains('+')) {
      // Belt-and-braces backstop for the FFmpeg merge case. The
      // primary gate now lives upstream in
      // `StartDownloadUseCase` — it awaits `ensureFFmpegOrRepair`
      // and returns an explicit failure when repair fails, so by
      // the time we reach this site FFmpeg should already be
      // available. Reaching this branch means either the primary
      // gate was bypassed (test path, future caller) or a race
      // between binary cache and the repair completion.
      //
      // Pre-Codex-round-4 this branch silently rewrote `format =
      // 'best'` — the same 360p degrade the primary gate was
      // designed to remove. Keeping the silent rewrite here let
      // future callers re-introduce the regression at a different
      // layer without anyone noticing. Now we refuse loudly: throw
      // a typed `YtDlpException` so the caller marks the download
      // failed with the exact reason instead of producing a 360p
      // file under a "Best" label.
      appLogger.error(
        '⛔ [YtDlp] FFmpeg STILL not available at download-args time — '
        'the upstream auto-repair gate in StartDownloadUseCase was either '
        'bypassed (test path? legacy caller? race?) or its repair attempt '
        'reported success but the binary disappeared again. Refusing to '
        'rewrite format "$format" → "best" — a silent degrade to ~360p '
        'on YouTube is the bug this gate exists to prevent.',
      );
      throw YtDlpException(
        YtDlpErrorType.binaryNotFound,
        'FFmpeg is required to merge the requested format ("$format") but '
        'is unavailable. Open Settings → yt-dlp Engine to reinstall, then '
        'retry. Picking a lower quality that does not require merging is '
        'also a valid workaround.',
      );
    }
    if (!extractAudio &&
        targetVideoHeight != null &&
        format != null &&
        format.contains('+') &&
        !await _hasFfprobe()) {
      appLogger.warning(
        '🔧 [YtDlp] ffprobe missing for resolution guard '
        '(${targetVideoHeight}p cap) — attempting binary repair before '
        'starting download...',
      );
      final repaired = await ensureFFmpegOrRepair();
      _ffmpegPath = await _binaryManager.getBinaryPath(BinaryType.ffmpeg);
      if (!repaired || !await _hasFfprobe()) {
        yield YtDlpProgressEvent.error(
          YtDlpException(
            YtDlpErrorType.binaryNotFound,
            'FFprobe is required to verify the ${targetVideoHeight}p '
            'resolution cap before completing this download. Open Settings '
            '→ yt-dlp Engine to reinstall FFmpeg/FFprobe, then retry.',
          ),
        );
        try {
          await Directory(isolatedTempDir).delete(recursive: true);
        } catch (_) {}
        return;
      }
      if (!args.contains('--ffmpeg-location')) {
        args.addAll(['--ffmpeg-location', _ytdlpPath(_ffmpegPath!)]);
      }
    }

    // RC10 Q-round C2 — platform-fallback WebM-target swap shadows.
    // When a platform-specific selector override below forces the
    // selector to a non-WebM source (TikTok watermark-free branch is
    // the active case), the planner-emitted `remuxVideo == 'webm'`
    // becomes wrong because the downloaded MP4/H.264/AAC stream can
    // never be muxed into WebM. Shadow the params so the override
    // block can promote remux → recode without mutating the function
    // signature. See `ContainerPlanner.promoteWebMRemuxToRecodeFor
    // PlatformFallback` for the source-of-truth detection (Codex
    // condition 1: NEVER use `format.contains('[ext=webm]')`).
    var effectiveRemuxVideo = remuxVideo;
    var effectiveRecodeVideo = recodeVideo;

    // === P2: Platform Detection ===
    final isTikTok = _isTikTokUrl(ytdlpUrl);
    final isInstagram =
        ytdlpUrl.contains('instagram.com') || ytdlpUrl.contains('instagr.am');
    final isTwitter =
        ytdlpUrl.contains('twitter.com') || ytdlpUrl.contains('x.com');
    final isTwitch =
        ytdlpUrl.contains('twitch.tv') || ytdlpUrl.contains('clips.twitch.tv');
    final isYouTube =
        ytdlpUrl.contains('youtube.com') || ytdlpUrl.contains('youtu.be');
    final isReddit =
        ytdlpUrl.contains('reddit.com') || ytdlpUrl.contains('redd.it');
    final isPinterest =
        ytdlpUrl.contains('pinterest.com') || ytdlpUrl.contains('pin.it');
    final hasYouTubeCookies =
        isYouTube && (cookiesFile != null || cookiesFromBrowser != null);
    final potProviderPaths = await _ensureYouTubePotProvider(
      isYouTube: isYouTube && hasYouTubeCookies,
    );
    final youtubePlayerClientLabel = hasYouTubeCookies ? 'tv,mweb' : 'default';
    final effectiveFormat =
        isYouTube && !extractAudio
            ? _stripYouTubeProgressiveBestFallback(format)
            : format;

    // ── Compute effective network values (platform overrides) ──
    // Each arg appears exactly once — no duplicate flags.
    var effectiveSocketTimeout = socketTimeout;
    var effectiveRetries = maxRetries;
    var effectiveFragmentRetries = maxRetries;
    var effectiveSleepRequests = '0.3';

    if (isInstagram) {
      effectiveSocketTimeout = socketTimeout > 10 ? 10 : socketTimeout;
      effectiveRetries = maxRetries < 5 ? 5 : maxRetries;
      effectiveFragmentRetries = maxRetries < 5 ? 5 : maxRetries;
      effectiveSleepRequests = '1';
      debugPrint('📸 [YtDlp] Instagram: Using optimized settings');
    } else if (isTwitter) {
      effectiveRetries = maxRetries < 5 ? 5 : maxRetries;
    } else if (isTwitch) {
      effectiveRetries = maxRetries < 5 ? 5 : maxRetries;
      effectiveFragmentRetries = maxRetries < 10 ? 10 : maxRetries;
    } else if (isReddit || isPinterest) {
      effectiveRetries = maxRetries < 5 ? 5 : maxRetries;
      effectiveFragmentRetries = 10;
    } else if (isTikTok) {
      // TikTok uses yt-dlp's default request profile below. Do not precompute
      // app network overrides that would never be emitted and would mislead
      // runtime logs.
    }

    if (!useDefaultNetworkProfile) {
      args.addAll(['--socket-timeout', '$effectiveSocketTimeout']);
      args.addAll(['--retries', '$effectiveRetries']);
      args.addAll(['--fragment-retries', '$effectiveFragmentRetries']);
      args.addAll(['--sleep-requests', effectiveSleepRequests]);
    } else {
      args.addAll([
        '--extractor-retries',
        '5',
        '--retry-sleep',
        'extractor:linear=1::1',
      ]);
      debugPrint('🎵 [YtDlp] TikTok: Using yt-dlp default network profile');
    }

    // === P2: Twitter/X Optimization ===
    // Use GraphQL API for better video extraction
    if (isTwitter) {
      args.addAll(['--extractor-args', 'twitter:api=graphql']);
      debugPrint('🐦 [YtDlp] Twitter/X: Using GraphQL API');
    }

    // === P2: YouTube ===
    if (isYouTube) {
      if (hasYouTubeCookies && potProviderPaths != null) {
        args.addAll(_youtubePotArgs(potProviderPaths));
        appLogger.info(
          '[YtDlp] YouTube POT provider enabled: '
          'cli=${potProviderPaths.cliPath} '
          'pluginDir=${potProviderPaths.pluginDir}',
        );
      } else if (hasYouTubeCookies) {
        appLogger.warning(
          '[YtDlp] YouTube POT provider unavailable; authenticated '
          'high-quality DASH downloads may fail instead of silently '
          'degrading.',
        );
      }

      final extractorArgs =
          hasYouTubeCookies
              ? 'youtube:skip=hls,dash,translated_subs;player_client=tv,mweb'
              : 'youtube:skip=hls,dash,translated_subs';
      args.addAll(['--extractor-args', extractorArgs]);
      appLogger.info(
        '[YtDlp] YouTube extractor args: player_client=$youtubePlayerClientLabel '
        'cookies=$hasYouTubeCookies skip=hls,dash,translated_subs',
      );
    }

    // === P2: Twitch Optimization ===
    if (isTwitch) {
      args.addAll(['--concurrent-fragments', '4']);
      debugPrint('🟣 [YtDlp] Twitch: Using VOD/clip optimized settings');
    }

    // === P1: Reddit/Pinterest CDN Fix ===
    if (isReddit || isPinterest) {
      // --downloader ffmpeg requires FFmpeg binary — skip if unavailable
      if (_ffmpegPath != null) {
        args.addAll(['--downloader', 'ffmpeg']);
      }
      if (effectiveFormat != null) {
        args.addAll(['-f', effectiveFormat]);
        args.addAll(['-S', sortOptions ?? 'res,ext:mp4:m4a']);
      }
      debugPrint(
        '🤖 [YtDlp] ${isReddit ? "Reddit" : "Pinterest"}: Using ${_ffmpegPath != null ? "ffmpeg downloader (CDN fix)" : "default downloader (no FFmpeg)"}',
      );
    }
    // === P2: TikTok Format Selection ===
    else if (isTikTok) {
      if (tiktokRemoveWatermark) {
        // Prefer watermark-free, fall back to best available
        // When FFmpeg is unavailable, skip DASH formats requiring merge
        if (_ffmpegPath != null) {
          final fallback =
              maxVideoHeight != null
                  ? '${ResolutionFilterUtils.joinVideoAudioVariants(videoSelector: 'bestvideo', audioSelector: 'bestaudio', resolution: maxVideoHeight)}/${ResolutionFilterUtils.joinSingleFileVariants(selector: 'best', resolution: maxVideoHeight)}'
                  : 'bestvideo+bestaudio/best';
          final watermarkFreeDash =
              ResolutionFilterUtils.joinVideoAudioVariants(
                videoSelector: 'bestvideo[format_note!=watermarked]',
                audioSelector: 'bestaudio',
                resolution: maxVideoHeight,
              );
          final watermarkFreeBest =
              ResolutionFilterUtils.joinSingleFileVariants(
                selector: 'best[format_note!=watermarked]',
                resolution: maxVideoHeight,
              );
          args.addAll([
            '-f',
            '$watermarkFreeDash/$watermarkFreeBest/$fallback',
          ]);
        } else {
          final fallback =
              maxVideoHeight != null
                  ? ResolutionFilterUtils.joinSingleFileVariants(
                    selector: 'best',
                    resolution: maxVideoHeight,
                  )
                  : 'best';
          final watermarkFreeBest =
              ResolutionFilterUtils.joinSingleFileVariants(
                selector: 'best[format_note!=watermarked]',
                resolution: maxVideoHeight,
              );
          args.addAll(['-f', '$watermarkFreeBest/$fallback']);
        }
        // RC10 Q-round C2: this branch OVERRODE the user's format
        // selector to force a non-watermarked progressive MP4. If the
        // user picked WebM as the output target, the planner's
        // null-permissive `remuxVideo='webm'` would now blow up at
        // the post-remux step because TikTok progressive is
        // H.264/AAC. Promote remux → recode so yt-dlp transcodes to
        // VP9/Opus and the user gets a real .webm file. Preserves
        // BOTH intents (watermark removal AND WebM output).
        final webmSwap =
            ContainerPlanner.promoteWebMRemuxToRecodeForPlatformFallback(
              videoFormat: videoFormat,
              recodeVideo: effectiveRecodeVideo,
              remuxVideo: effectiveRemuxVideo,
            );
        effectiveRecodeVideo = webmSwap.recodeVideo;
        effectiveRemuxVideo = webmSwap.remuxVideo;
      } else if (format != null) {
        args.addAll(['-f', format]);
      }
      // Always add sort for TikTok to prefer high quality mp4
      args.addAll(['-S', sortOptions ?? 'res,ext:mp4:m4a']);
      debugPrint(
        '🎵 [YtDlp] TikTok: Using ${tiktokRemoveWatermark ? "watermark-free" : "standard"} format selector'
        '${effectiveRecodeVideo == 'webm' && recodeVideo != 'webm' ? ' (Q-round C2: promoted remux=webm → recode=webm)' : ''}',
      );
    } else if (effectiveFormat != null) {
      // Add format selection with codec/resolution priority
      args.addAll(['-f', effectiveFormat]);
      final sort = sortOptions ?? 'res,ext:mp4:m4a';
      args.addAll(['-S', sort]);
    }

    // Cookie precedence: --cookies <file> WINS over --cookies-from-browser
    // (Codex 2026-05-21 audit fix). The in-app captured cookies file is
    // an explicit user intent that bypasses the Chrome cookie-DB-lock
    // pitfall on Windows (yt-dlp issue 7271 — Chrome SQLite locked
    // while Chrome runs). The legacy precedence treated
    // cookies-from-browser as primary, causing the
    // `Could not copy Chrome cookie database` chain in
    // `log.md` 2026-05-21 Incident A. When BOTH are set, prefer the
    // file — the caller has already promoted the in-app cookie.
    if (cookiesFile != null) {
      args.addAll(['--cookies', _ytdlpPath(cookiesFile)]);
    } else if (cookiesFromBrowser != null) {
      args.addAll(['--cookies-from-browser', cookiesFromBrowser]);
    }

    // Merge output format priority — `--merge-output-format` is a `/`-joined
    // list yt-dlp consults when reconciling DASH video+audio streams.
    //
    // [mergeFormatPriority] is supplied by [FormatSelectorService] which
    // knows when the user-preferred container cannot honestly hold the
    // codecs available at the requested height (e.g. MP4 at YouTube
    // ≥1440p where the streams are VP9/AV1+Opus and MP4 has no native
    // Opus support — putting MKV first there avoids producing a corrupt
    // MP4 with a silent or re-encoded audio track).
    //
    // Fallback: when no priority is supplied, build the legacy
    // `${videoFormat}/mkv/webm` chain that the original implementation
    // used. This keeps non-format-selector callers (audio-only paths,
    // best-effort downloads) on their previous contract.
    // ContainerPlanner remux/recode step. The helper is shared with a
    // snapshot test so the MP4+VP9 recode contract is pinned at the arg layer.
    args.addAll(
      _containerPostProcessArgs(
        extractAudio: extractAudio,
        videoFormat: videoFormat,
        mergeFormatPriority: mergeFormatPriority,
        remuxVideo: effectiveRemuxVideo,
        recodeVideo: effectiveRecodeVideo,
      ),
    );

    // Keep DASH original files after merge for retry capability
    // yt-dlp normally deletes video.f{id}.ext + audio.f{id}.ext after merging
    // With --keep-video, originals survive → enables FFmpeg retry if merge fails
    if (keepVideo && !extractAudio) {
      args.add('--keep-video');
    }

    // Audio extraction
    if (extractAudio) {
      args.add('-x');
      if (audioFormat != null) {
        args.addAll(['--audio-format', audioFormat]);
      }
      // Dialog audio quality is a target bitrate (320/256/192 kbps, etc.).
      // When no explicit bitrate is selected, keep yt-dlp's best-quality mode.
      args.addAll(['--audio-quality', _audioQualityArg(audioBitrateKbps)]);
    }

    // === Subtitle-only download (--skip-download) ===
    if (skipDownload) {
      args.add('--skip-download');
    }

    // === Postprocess compatibility resolver ===
    //
    // yt-dlp's PP chain runs in this order: --recode-video FIRST (mutates
    // info['ext'] to the target), then embed-subs / metadata / chapters,
    // then embed-thumbnail LAST. Each PP has its own SUPPORTED_EXTS gate
    // baked into upstream source — when the container is unsupported,
    // EmbedThumbnailPP RAISES (hard fail, non-zero exit), while
    // EmbedSubtitlePP just skips silently. Hard fail is what bites us on
    // Windows when a user picks AVI + leaves the default
    // `embedThumbnail=true` setting on.
    //
    // The effective extension is what the FINAL file will have. For
    // recoded targets that's `recodeVideo`. For native targets it's
    // `videoFormat` from FormatSelectorService. For audio extraction
    // it's `audioFormat`. The matrix below mirrors the SUPPORTED_EXTS
    // sets in yt-dlp's postprocessor/embedthumbnail.py + ffmpeg.py so a
    // user-chosen container that yt-dlp's PP cannot honor never reaches
    // the PP — we either skip the embed (with a sidecar fallback for
    // thumbnails/subs so the user does not lose the artifact) or, for
    // chapters/metadata, just drop the flag.
    //
    // Sources (yt-dlp 2026.x):
    //   embedthumbnail.py:222
    //     "Supported filetypes for thumbnail embedding are: mp3,
    //      mkv/mka, ogg/opus/flac, m4a/mp4/m4v/mov"
    //   ffmpeg.py:582 (FFmpegEmbedSubtitlePP)
    //     SUPPORTED_EXTS = ('mp4', 'mov', 'm4a', 'webm', 'mkv', 'mka')
    //   ffmpeg.py:662+ (FFmpegMetadataPP) — no SUPPORTED_EXTS gate
    //     but FLV drops almost every tag; AVI accepts a limited subset
    //     and has no chapter atom so chapter writes are unreliable.
    final embedCompat = YtDlpDataSource.resolveEmbedCompatibility(
      recodeVideo: recodeVideo,
      videoFormat: videoFormat,
      audioFormat: audioFormat,
      extractAudio: extractAudio,
    );
    final effectiveExt = embedCompat.effectiveExt;
    final canEmbedThumbnail = embedCompat.canEmbedThumbnail;
    final canEmbedSubs = embedCompat.canEmbedSubs;
    final canEmbedChapters = embedCompat.canEmbedChapters;

    // === P0: Subtitles ===
    // Skip subtitles entirely for audio-only downloads (no container to embed into)
    if (subtitlesEnabled && !extractAudio) {
      args.add('--write-subs');
      if (includeAutoSubs) {
        args.add('--write-auto-subs'); // Include auto-generated captions
      }
      if (subtitlesLanguages.isNotEmpty) {
        args.addAll(['--sub-langs', subtitlesLanguages.join(',')]);
      }
      args.addAll(['--sub-format', subtitlesFormat]);
      if (embedSubtitles && !skipDownload) {
        if (canEmbedSubs) {
          args.add('--embed-subs');
        } else {
          // Container cannot hold subs as a stream; --write-subs above
          // already keeps the .srt sidecar so the user does not lose
          // the captions. yt-dlp's own behavior is to silently drop
          // here, so we mirror that with a breadcrumb only.
          debugPrint(
            '⚠️ [YtDlp] Skipping --embed-subs (unsupported for '
            '$effectiveExt container); subs kept as sidecar file.',
          );
        }
      }
    }

    // === P0: Thumbnails ===
    if (writeThumbnail) {
      args.add('--write-thumbnail');
      args.addAll(['--convert-thumbnails', 'jpg']); // Convert webp to jpg
    }
    if (embedThumbnail) {
      if (canEmbedThumbnail) {
        args.add('--embed-thumbnail');
      } else {
        // EmbedThumbnailPP raises on unsupported containers — see
        // upstream embedthumbnail.py:222 — so we MUST not pass the
        // flag here or the entire download exits non-zero. Save as a
        // sidecar instead so the user still gets the artwork.
        if (!writeThumbnail) {
          args.add('--write-thumbnail');
          args.addAll(['--convert-thumbnails', 'jpg']);
        }
        debugPrint(
          '⚠️ [YtDlp] Skipping --embed-thumbnail (unsupported for '
          '$effectiveExt container); written as sidecar file.',
        );
      }
    }

    // === P0: Metadata ===
    if (embedMetadata) {
      // FFmpegMetadataPP has no SUPPORTED_EXTS gate upstream — ffmpeg
      // will silently drop tags for containers that don't carry them
      // (most flags on FLV, some on AVI). Safe to always emit; the
      // user gets best-effort tag write without a hard fail.
      args.add('--embed-metadata');
    }
    if (embedChapters) {
      if (canEmbedChapters) {
        args.add('--embed-chapters');
      } else {
        debugPrint(
          '⚠️ [YtDlp] Skipping --embed-chapters (unsupported for '
          '$effectiveExt container).',
        );
      }
    }

    // === P0: SponsorBlock ===
    if (sponsorBlockEnabled && sponsorBlockCategories.isNotEmpty) {
      final categories = sponsorBlockCategories.join(',');
      switch (sponsorBlockAction) {
        case 'remove':
          // Cut out sponsor segments from video
          args.addAll(['--sponsorblock-remove', categories]);
          break;
        case 'chapter':
          // Mark segments as chapters only
          args.addAll(['--sponsorblock-mark', categories]);
          break;
        default:
          // 'skip' - Mark as chapters (default behavior)
          args.addAll(['--sponsorblock-mark', categories]);
      }
    }

    // === P1: Split by Chapters ===
    if (splitChapters) {
      args.add('--split-chapters');
      // Use chapter title in output filename (override template)
      args.addAll([
        '-o',
        'chapter:${_ytdlpPath(outputDir)}/%(title)s - %(section_title)s.%(ext)s',
      ]);
    }

    // === P1: Live Stream Support ===
    if (liveFromStart) {
      args.add('--live-from-start');
      args.addAll([
        '--wait-for-video',
        '30',
      ]); // Wait up to 30s for live to start
    }

    // === P1: Force Remux ===
    // Remux video to preferred container format for compatibility
    // --remux-video remuxes ANY video to the specified format (not just merged ones)
    // Skip for audio-only downloads (--remux-video is video-only flag)
    args.addAll(
      _forceRemuxArgs(
        forceRemux: forceRemux,
        videoFormat: videoFormat,
        recodeVideo: effectiveRecodeVideo,
        extractAudio: extractAudio,
      ),
    );

    // === Section download ===
    // Two flavors with deliberately different keyframe handling:
    //
    // 1. Time-range slider (sectionStartTime/EndTime) — stream copy, no
    //    re-encode. Fast, but cuts can drift to the previous keyframe
    //    (1-30s depending on the source GOP). Trade-off chosen earlier
    //    because the slider is a precision tool and users expect speed.
    //
    // 2. Chapter selection (selectedChapterRanges) — adds
    //    --force-keyframes-at-cuts so the cut lands EXACTLY on the chapter
    //    boundary the user picked. This re-encodes a small window around
    //    each cut (typically a few seconds) and is the difference between
    //    "the chapter I asked for" and "the tail of the previous chapter
    //    plus my chapter". Users opting into chapter selection are
    //    asking for accuracy; the small encode latency is acceptable.
    if (sectionStartTime != null && sectionEndTime != null) {
      final startStr = _formatSectionTimestamp(sectionStartTime);
      final endStr = _formatSectionTimestamp(sectionEndTime);
      args.addAll(['--download-sections', '*$startStr-$endStr']);
      debugPrint('✂️ [YtDlp] Download section: $startStr → $endStr');
    } else if (selectedChapterRanges != null &&
        selectedChapterRanges.isNotEmpty) {
      // Per-chapter selection: emit one --download-sections per range.
      // _resolveSelectedChapterRanges in the UI coalesces to a single span,
      // but the loop is kept for forward-compat if we ever ship a multi-pass
      // strategy.
      for (final (start, end) in selectedChapterRanges) {
        final startStr = _formatSectionTimestamp(start);
        final endStr = _formatSectionTimestamp(end);
        args.addAll(['--download-sections', '*$startStr-$endStr']);
      }
      // Force precise cuts at the chapter boundary (small re-encode window).
      args.add('--force-keyframes-at-cuts');
      final rangeDesc = selectedChapterRanges
          .map(
            (r) =>
                '${_formatSectionTimestamp(r.$1)}→${_formatSectionTimestamp(r.$2)}',
          )
          .join(', ');
      debugPrint('✂️ [YtDlp] Chapter selection: $rangeDesc (precise cuts)');
    }

    // === P3: Proxy ===
    if (proxyUrl != null && proxyUrl.isNotEmpty) {
      args.addAll(['--proxy', proxyUrl]);
      debugPrint('🌐 [YtDlp] Using proxy: $proxyUrl');
    }

    // === P3: Geo-bypass ===
    if (geoBypass) {
      if (geoBypassCountry != null && geoBypassCountry.isNotEmpty) {
        args.addAll(['--geo-bypass-country', geoBypassCountry]);
        debugPrint('🌍 [YtDlp] Geo-bypass country: $geoBypassCountry');
      } else {
        args.add('--geo-bypass');
        debugPrint('🌍 [YtDlp] Geo-bypass enabled (auto)');
      }
    }

    // === P3: Archive Mode ===
    if (archiveEnabled && archiveFile != null && archiveFile.isNotEmpty) {
      args.addAll(['--download-archive', _ytdlpPath(archiveFile)]);
      debugPrint('📚 [YtDlp] Using archive file: $archiveFile');
    }

    // === P3: Date Filters ===
    if (dateAfter != null && dateAfter.isNotEmpty) {
      args.addAll(['--dateafter', dateAfter]);
      debugPrint('📅 [YtDlp] Date filter: after $dateAfter');
    }
    if (dateBefore != null && dateBefore.isNotEmpty) {
      args.addAll(['--datebefore', dateBefore]);
      debugPrint('📅 [YtDlp] Date filter: before $dateBefore');
    }

    // === P3: Duration Filters ===
    if (minDuration != null && minDuration > 0) {
      args.addAll(['--match-filter', 'duration>=$minDuration']);
      debugPrint('⏱️ [YtDlp] Duration filter: min ${minDuration}s');
    }
    if (maxDuration != null && maxDuration > 0) {
      args.addAll(['--match-filter', 'duration<=$maxDuration']);
      debugPrint('⏱️ [YtDlp] Duration filter: max ${maxDuration}s');
    }

    // === Custom FFmpeg Postprocessor Args ===
    if (customPostprocessorArgs.isNotEmpty) {
      args.addAll(['--postprocessor-args', 'ffmpeg:$customPostprocessorArgs']);
      debugPrint(
        '🔧 [YtDlp] Custom postprocessor args: $customPostprocessorArgs',
      );
    }

    // Add URL last
    args.add(ytdlpUrl);

    // Total span of the section(s) being downloaded — non-null only when
    // yt-dlp is going to delegate to ffmpeg (time-range slider OR per-chapter
    // selection). Used by the ffmpeg-progress fallback below.
    Duration? sectionDuration;
    if (sectionStartTime != null && sectionEndTime != null) {
      sectionDuration = sectionEndTime - sectionStartTime;
    } else if (selectedChapterRanges != null &&
        selectedChapterRanges.isNotEmpty) {
      sectionDuration = selectedChapterRanges.fold<Duration>(
        Duration.zero,
        (acc, range) => acc + (range.$2 - range.$1),
      );
    }

    Process? process;
    String? lastOutputFile;
    bool wasCancelled = false;
    // Throttle ffmpeg-derived progress emissions to ~4 Hz so we don't
    // flood the Riverpod stream / DB writer with one event per frame.
    DateTime? lastFfmpegEmit;

    // DL-016 — engine gate before spawn; yields a terminal
    // ytdlpBinaryMissing-classified error instead of crashing into the
    // generic catch below with a command-line-poisoned ProcessException.
    final ytdlpBinary = await _ensureYtdlpBinaryReady();
    if (ytdlpBinary == null) {
      yield YtDlpProgressEvent.error(
        YtDlpException(YtDlpErrorType.unknown, ytdlpBinaryMissingMessage),
      );
      return;
    }

    try {
      debugPrint('🚀 [YtDlp] Starting download subprocess...');
      debugPrint('🔧 [YtDlp] Command: $ytdlpBinary ${args.join(' ')}');

      // Force Python (yt-dlp) to use UTF-8 for stdout/stderr on Windows.
      // Without this, Python outputs using system codepage (cp1252/Windows-1252),
      // corrupting Vietnamese/Unicode filenames in progress output.
      process = await ProcessHelper.start(
        ytdlpBinary,
        args,
        environment:
            Platform.isWindows
                ? const {'PYTHONUTF8': '1', 'PYTHONIOENCODING': 'utf-8'}
                : null,
      );

      // Track active process for cancellation (keyed by processKey, not URL)
      _activeProcesses[processKey] = process;
      if (downloadId != null) _downloadIdToProcessKey[downloadId] = processKey;

      // === Stream merging: stdout + stderr ===
      //
      // For normal downloads, only stdout matters (yt-dlp progress lines).
      // For section/chapter downloads (--download-sections + --force-keyframes-at-cuts),
      // yt-dlp delegates to ffmpeg, which outputs progress (time=HH:MM:SS.MS) to
      // stderr. Without merging, the UI freezes at 0% during the entire ffmpeg phase.
      //
      // We always merge both streams — the parsing logic handles both formats:
      // - yt-dlp progress from stdout: parsed by native.ytdlpParseProgress
      // - ffmpeg progress from stderr: parsed by _ffmpegTimeRegex fallback
      final stderrBuffer = StringBuffer();
      final stdoutStream = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter());
      final stderrStream = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .map((line) {
            // Buffer every stderr line for error reporting after process exits.
            stderrBuffer.writeln(line);
            return line;
          });

      final mergedStream = _mergeLineStreams(stdoutStream, stderrStream);

      await for (final line in mergedStream) {
        // Check if cancelled
        if (!_activeProcesses.containsKey(processKey)) {
          wasCancelled = true;
          break;
        }

        debugPrint('📤 [YtDlp] output: $line');

        // Parse progress using Rust parser (handles yt-dlp download format)
        final progressDto = await native.ytdlpParseProgress(line: line);
        if (progressDto != null) {
          yield YtDlpProgressEvent.progress(YtDlpProgress.fromDto(progressDto));
        } else if (sectionDuration != null) {
          // Fallback: yt-dlp is delegating to ffmpeg for a section download.
          // Parse ffmpeg's `time=HH:MM:SS.MS` (appears on stderr, now merged)
          // and synthesise progress so the UI keeps moving.
          final match = _ffmpegTimeRegex.firstMatch(line);
          if (match != null) {
            final h = int.tryParse(match.group(1)!) ?? 0;
            final m = int.tryParse(match.group(2)!) ?? 0;
            final s = int.tryParse(match.group(3)!) ?? 0;
            // Fractional seconds — pad/truncate to milliseconds.
            final fracStr = match.group(4)!;
            final msStr =
                fracStr.length >= 3
                    ? fracStr.substring(0, 3)
                    : fracStr.padRight(3, '0');
            final ms = int.tryParse(msStr) ?? 0;
            final elapsed = Duration(
              hours: h,
              minutes: m,
              seconds: s,
              milliseconds: ms,
            );

            final totalMs = sectionDuration.inMilliseconds;
            if (totalMs > 0) {
              // Cap at 99.5 — leave the final 100% emit for postprocessing.
              final percent = (elapsed.inMilliseconds / totalMs * 100).clamp(
                0.0,
                99.5,
              );

              final now = DateTime.now();
              if (lastFfmpegEmit == null ||
                  now.difference(lastFfmpegEmit).inMilliseconds >= 250) {
                lastFfmpegEmit = now;
                yield YtDlpProgressEvent.progress(
                  YtDlpProgress(
                    percent: percent,
                    status: YtDlpDownloadStatus.downloading,
                  ),
                );
              }
            }
          }
        }

        // Capture destination file (normalize backslashes on Windows)
        if (line.contains('[download] Destination:')) {
          final destMatch =
              line.replaceFirst('[download] Destination:', '').trim();
          if (destMatch.isNotEmpty) {
            lastOutputFile = _ytdlpPath(destMatch);
          }
        }

        // Check for merger output (normalize backslashes on Windows)
        if (line.contains('[Merger]') || line.contains('Merging formats')) {
          final intoIndex = line.indexOf('into');
          if (intoIndex != -1) {
            final afterInto = line.substring(intoIndex + 4).trim();
            lastOutputFile = _ytdlpPath(afterInto.replaceAll('"', ''));
          }
          // RC10.3: emit MERGING sub-state so UI shows "Merging" not
          // generic "Processing". Fast operation (1-2s typical for
          // stream-copy DASH merge).
          yield YtDlpProgressEvent.progress(
            YtDlpProgress(percent: 100, status: YtDlpDownloadStatus.merging),
          );
        }
        // RC10.3 — VideoRemuxer: stream-copy container change.
        // Fast (1-2s) — distinguish from converting which is full
        // re-encode taking minutes.
        if (line.contains('[VideoRemuxer]')) {
          final remuxDestination = _extractPostProcessorDestination(line);
          if (remuxDestination != null) {
            lastOutputFile = remuxDestination;
          }
          yield YtDlpProgressEvent.progress(
            YtDlpProgress(percent: 100, status: YtDlpDownloadStatus.remuxing),
          );
        }
        // RC10.3 — VideoConvertor: full transcode (audio + video
        // re-encode). SLOW — can be many minutes for 1080p. UI must
        // distinguish so user doesn't think app hung.
        if (line.contains('[VideoConvertor]')) {
          final convertDestination = _extractPostProcessorDestination(line);
          if (convertDestination != null) {
            lastOutputFile = convertDestination;
          }
          yield YtDlpProgressEvent.progress(
            YtDlpProgress(percent: 100, status: YtDlpDownloadStatus.converting),
          );
        }

        // Capture "already been downloaded" path (normalize backslashes on Windows)
        if (line.contains('has already been downloaded')) {
          final alreadyMatch = line.replaceFirst('[download]', '').trim();
          final alreadyPath = alreadyMatch.replaceFirst(
            ' has already been downloaded',
            '',
          );
          if (alreadyPath.isNotEmpty) {
            lastOutputFile = _ytdlpPath(alreadyPath);
          }
        }

        // Capture ExtractAudio destination (normalize backslashes on Windows)
        if (line.contains('[ExtractAudio] Destination:')) {
          final audioDestMatch =
              line.replaceFirst('[ExtractAudio] Destination:', '').trim();
          if (audioDestMatch.isNotEmpty) {
            lastOutputFile = _ytdlpPath(audioDestMatch);
          }
        }
      }

      // Handle cancellation
      if (wasCancelled) {
        debugPrint('🛑 [YtDlp] Download was cancelled');
        // Clean up temp dir on cancel
        try {
          await Directory(isolatedTempDir).delete(recursive: true);
        } catch (_) {}
        yield YtDlpProgressEvent.cancelled();
        return;
      }

      // Wait for process to exit. stderr was already captured in stderrBuffer
      // by the merged stream above — no separate stderr collection needed.
      final exitCode = await process.exitCode;
      final stderr = stderrBuffer.toString();

      debugPrint('✅ [YtDlp] Process exited with code: $exitCode');

      // Clean up active process tracking
      _activeProcesses.remove(processKey);
      if (downloadId != null) _downloadIdToProcessKey.remove(downloadId);

      // ALWAYS emit completion if exitCode is 0 (even if stderr had issues)
      // This ensures MP3 downloads get marked as completed when file exists
      if (exitCode == 0) {
        // Promote the authoritative final path sidecar over the stdout-
        // parsed `lastOutputFile`. `--print-to-file after_move:filepath`
        // wrote ONE line — the final on-disk path after recode/move —
        // which is the post-recode .avi/.mov/.flv that the legacy
        // parser missed. `lastOutputFile` remains the fallback so the
        // contract on native containers (no --recode-video) stays
        // bit-for-bit identical to the pre-Phase-1b behavior.
        final authoritativePath = await _readFinalPathSidecar(finalPathSidecar);
        var resolvedOutputFile = authoritativePath ?? lastOutputFile;

        // RECODE FALLBACK SCAN — closes the runtime bug where the
        // `.mkv` merge intermediate gets surfaced as final when the
        // user picked a recoded container (AVI/MOV/M4V/FLV). When
        // `recodeVideo` is set, the final file's extension MUST
        // match the user's pick. If the sidecar was empty (yt-dlp's
        // print-to-file did not fire for our setup) AND `lastOutputFile`
        // points to a different extension (typically the merge MKV
        // intermediate), scan the temp dir for the latest file with
        // the expected extension. This is robust against any
        // upstream change to yt-dlp's print/move PP semantics — if
        // the recoded file exists, we find it.
        if (recodeVideo != null && !extractAudio) {
          // RC4b: M4V special case — yt-dlp's `--recode-video` rejects
          // 'm4v' as a target (FORMAT_RE validator). FormatSelectorService
          // maps M4V → MP4 recode, and we rename .mp4 → .m4v AFTER
          // process exit (block ~50 lines below). The scan therefore
          // must look for the extension yt-dlp ACTUALLY emitted (.mp4),
          // not the user's pick (.m4v). Pre-RC4b the scan demanded
          // .m4v, found nothing, errored out, and the rename block
          // was never reached. Production log #406 (2026-05-22).
          final expectedExt = _recodeScanExtension(
            videoFormat: videoFormat,
            recodeVideo: recodeVideo,
          );
          final hasMatchingExt =
              resolvedOutputFile != null &&
              resolvedOutputFile.toLowerCase().endsWith('.$expectedExt');
          if (!hasMatchingExt) {
            final scanned = await _findFileWithExtension(
              isolatedTempDir,
              expectedExt,
            );
            if (scanned != null) {
              debugPrint(
                '✅ [YtDlp] Recode fallback scan promoted "$scanned" '
                'over "$resolvedOutputFile" (user picked .$expectedExt, '
                'sidecar / parser returned a non-matching extension)',
              );
              resolvedOutputFile = scanned;
            } else {
              // Recode failed — yt-dlp exited 0 but the file with
              // the user's chosen extension is not on disk. Mark
              // failed instead of silently surfacing the merge
              // intermediate. The "pick X → get X" contract trumps
              // the salvage-MKV legacy behavior.
              debugPrint(
                '❌ [YtDlp] Recode appears to have failed: no .'
                '$expectedExt file in temp dir even though yt-dlp '
                'exited 0. Last seen: "$resolvedOutputFile". '
                'Marking as failure.',
              );
              yield YtDlpProgressEvent.error(
                YtDlpException(
                  YtDlpErrorType.unknown,
                  'Could not produce .$expectedExt file. The video '
                  'codec may not be compatible with the chosen '
                  'container — try MKV or MP4 for the same video.',
                ),
              );
              try {
                await Directory(isolatedTempDir).delete(recursive: true);
              } catch (_) {}
              return;
            }
          }
        }

        // M4V special case: yt-dlp does NOT accept 'm4v' as a
        // --recode-video target (FORMAT_RE validator in
        // yt-dlp/__init__.py:260). The shared helper
        // `_renameM4vIfApplicable` renames .mp4 → .m4v when the
        // remap is active; otherwise pass-through.
        if (resolvedOutputFile != null) {
          resolvedOutputFile = await _renameM4vIfApplicable(
            filePath: resolvedOutputFile,
            videoFormat: videoFormat,
            recodeVideo: recodeVideo,
          );
        }

        resolvedOutputFile = await _promoteExpectedExtensionIfNeeded(
          isolatedTempDir: isolatedTempDir,
          resolvedOutputFile: resolvedOutputFile,
          videoFormat: videoFormat,
          audioFormat: audioFormat,
          extractAudio: extractAudio,
        );

        // yt-dlp's ExtractAudio postprocessor stream-copies when the
        // source codec already matches the target (e.g. YouTube AAC →
        // M4A/AAC). In that case `--audio-quality 320K/128K` is ignored
        // upstream and two different bitrate selections can produce
        // byte-identical files. After yt-dlp exits, probe the actual
        // audio bitrate; when it does not match the explicit user target,
        // run one controlled ffmpeg recode so the output contract is real.
        if (extractAudio) {
          resolvedOutputFile = await _resolveAudioOutputFile(
            isolatedTempDir: isolatedTempDir,
            resolvedOutputFile: resolvedOutputFile,
            audioFormat: audioFormat,
          );
          if (resolvedOutputFile != null) {
            try {
              yield YtDlpProgressEvent.progress(
                YtDlpProgress(
                  percent: 100,
                  status: YtDlpDownloadStatus.postProcessing,
                ),
              );
              resolvedOutputFile = await _enforceAudioBitrateIfNeeded(
                filePath: resolvedOutputFile,
                audioFormat: audioFormat,
                audioBitrateKbps: audioBitrateKbps,
              );
            } on YtDlpException catch (e) {
              yield YtDlpProgressEvent.error(e);
              try {
                await Directory(isolatedTempDir).delete(recursive: true);
              } catch (_) {}
              return;
            }
          }
        }

        // DL-FB-FINALPATH-1: native (non-recode) downloads have no fallback
        // scan — the recode scan + ext-promote above are gated on
        // recodeVideo / extension mismatch only. When the `.final_path`
        // sidecar was empty/stale and the stdout-parsed path is a download-
        // FRAGMENT destination rather than the merged output (the Facebook
        // multi-stream merge case), the resolved path is not on disk; the
        // move would otherwise return a constructed predicted path and the
        // download completes as pathNotFound even though the file IS present.
        // Promote the real produced file HERE — BEFORE the resolution-cap
        // and C3 container guards below — so the promoted file is still
        // validated/salvaged/failed by C3 (a promoted .mkv for an MP4 pick
        // is recoded or hard-failed, never silently completed with the wrong
        // container). No-op when the resolved path exists, so YouTube/
        // TikTok/Instagram are unaffected.
        if (!extractAudio &&
            (resolvedOutputFile == null ||
                !await File(resolvedOutputFile).exists())) {
          final promoted = await _findPrimaryOutputFile(isolatedTempDir);
          if (promoted != null) {
            debugPrint(
              '✅ [YtDlp DL-FB-FINALPATH-1] Resolved path '
              '"${resolvedOutputFile ?? '<null>'}" not on disk — promoting '
              'real output "$promoted" (still validated by the C3 container '
              'guard below).',
            );
            resolvedOutputFile = promoted;
          }
        }

        // Resolution cap guard. `-S res:H` is deliberately used by the
        // selector to avoid yt-dlp's slash-fallback first-match trap for
        // portrait videos, but `res:H` is a soft target: if no format exists
        // at or below H, yt-dlp chooses the smallest format above H. Enforce
        // the app-level selected-height/free-tier hard cap before the file is
        // moved into the user's Downloads folder.
        if (!extractAudio &&
            resolvedOutputFile != null &&
            targetVideoHeight != null) {
          var dimensions = await _probeVideoDimensions(resolvedOutputFile);
          var capViolation = _detectResolutionCapViolation(
            maxShortSide: targetVideoHeight,
            width: dimensions?.width,
            height: dimensions?.height,
          );
          // F2: re-probe ONCE when dimensions were unmeasurable. A single
          // ffprobe miss (transient I/O, slow-disk timeout, odd first
          // stream) must not condemn a finished file.
          if (capViolation != null && capViolation.dimensionsUnavailable) {
            dimensions = await _probeVideoDimensions(resolvedOutputFile);
            capViolation = _detectResolutionCapViolation(
              maxShortSide: targetVideoHeight,
              width: dimensions?.width,
              height: dimensions?.height,
            );
          }
          // F2: fail-OPEN on UNMEASURABLE — never delete a finished,
          // correct download just because ffprobe could not read it.
          // Only a MEASURED OVERRUN (real dimensions above the tier
          // ceiling) fails closed below.
          if (capViolation != null && capViolation.dimensionsUnavailable) {
            appLogger.warning(
              '⚠️ [YtDlp resolution guard] Could not measure output '
              'dimensions for the ${capViolation.expectedMaxShortSide}p cap '
              'after re-probe — accepting the finished file (fail-open). '
              'File: "$resolvedOutputFile".',
            );
            capViolation = null;
          }
          if (capViolation != null) {
            appLogger.error(
              '❌ [YtDlp resolution guard] Output exceeds target cap — '
              'expected short-side <= ${capViolation.expectedMaxShortSide}px '
              'but got ${capViolation.actualWidth}x'
              '${capViolation.actualHeight} at "$resolvedOutputFile".',
            );
            yield YtDlpProgressEvent.error(
              YtDlpException(
                YtDlpErrorType.unknown,
                'Resolution mismatch — expected at most '
                '${capViolation.expectedMaxShortSide}p but output is '
                '${capViolation.actualWidth}x'
                '${capViolation.actualHeight}.',
              ),
            );
            try {
              await Directory(isolatedTempDir).delete(recursive: true);
            } catch (_) {}
            return;
          }
        }

        // RC10 Q-round C3 — final container/extension guard BEFORE
        // the move. The existing recode-contract guard above only
        // fires when yt-dlp exits non-zero or the recoded extension
        // missing from temp dir; it does NOT cover the case where
        // yt-dlp exits zero with a NATIVE container (mp4/mkv/webm)
        // but the output extension doesn't match the user's pick —
        // e.g., a selector override forced MP4 selection AND C1/C2's
        // promote-to-recode missed it, so the user picked WebM but
        // the file landing in their Downloads is .mp4.
        //
        // Block the move when ext mismatch detected; ensures the
        // contract `pick X → get X` holds at the datasource layer
        // BEFORE wrong-extension file ever reaches user space.
        // Fresh + retry paths still get defense-in-depth checks in
        // their own scopes (start_download_usecase.dart +
        // download_repository_impl.dart) per mirror discipline.
        if (resolvedOutputFile != null) {
          final extMismatch = _detectFinalExtensionMismatch(
            outputPath: resolvedOutputFile,
            videoFormat: videoFormat,
            audioFormat: audioFormat,
            extractAudio: extractAudio,
          );
          if (extMismatch != null) {
            // N4 salvage (2026-06): the PO-Token/SABR reality — extraction
            // advertised avc1 so the planner emitted --remux-video mp4, but
            // the source actually delivered VP9 (avc1 gated behind
            // PO-Token), so yt-dlp's remux fell back to a `.mkv` on disk.
            // Before hard-failing the user's MP4 pick, attempt ONE
            // controlled --recode-video-equivalent ffmpeg pass to produce a
            // real .mp4. Gated to exactly expected=mp4 / actual=mkv so every
            // OTHER mismatch shape still hits the hard-fail below unchanged.
            //
            // NOTE: keyed on the RAW recode/remux/videoFormat params, not
            // the effective* shadows. The WebM platform-fallback swap only
            // promotes remux=webm→recode=webm; it never fires for an MP4
            // signature, so effectiveRemuxVideo==remuxVideo here. If that
            // swap ever learns MP4 cases, revisit this gate.
            if (!extractAudio &&
                extMismatch.expected == 'mp4' &&
                extMismatch.actual == 'mkv' &&
                _ffmpegPath != null) {
              yield YtDlpProgressEvent.progress(
                YtDlpProgress(
                  percent: 100,
                  status: YtDlpDownloadStatus.postProcessing,
                ),
              );
              final salvaged = await _salvageVp9Mp4Recode(resolvedOutputFile);
              if (salvaged != null) {
                appLogger.info(
                  '✅ [YtDlp C3 salvage] Recoded VP9-in-MKV → real .mp4 at '
                  '"$salvaged" (source delivered VP9 despite avc1 extraction).',
                );
                resolvedOutputFile = salvaged;
              } else {
                appLogger.error(
                  '❌ [YtDlp C3 salvage] --recode-video mp4 pass failed for '
                  '"$resolvedOutputFile"; falling through to hard-fail.',
                );
              }
            }
            final stillMismatched = _detectFinalExtensionMismatch(
              outputPath: resolvedOutputFile,
              videoFormat: videoFormat,
              audioFormat: audioFormat,
              extractAudio: extractAudio,
            );
            if (stillMismatched != null) {
              appLogger.error(
                '❌ [YtDlp C3 guard] Extension mismatch — expected .'
                '${stillMismatched.expected} but yt-dlp produced .'
                '${stillMismatched.actual} at "$resolvedOutputFile". '
                'Refusing to move wrong-extension file into user Downloads.',
              );
              yield YtDlpProgressEvent.error(
                YtDlpException(
                  YtDlpErrorType.unknown,
                  'Container mismatch — expected .${stillMismatched.expected} '
                  'but output is .${stillMismatched.actual}. The source may '
                  'not provide a ${stillMismatched.expected}-native stream '
                  'and conversion did not run. Try MKV or MP4 for wide '
                  'codec support.',
                ),
              );
              try {
                await Directory(isolatedTempDir).delete(recursive: true);
              } catch (_) {}
              return;
            }
          }
        }

        // Move downloaded file(s) from isolated temp dir to real output dir.
        // This is the moment files first appear in the user's folder —
        // cloud sync sees only complete files, never locked intermediates.
        final finalPath = await _moveFilesToOutputDir(
          isolatedTempDir,
          outputDir,
          resolvedOutputFile,
        );
        yield YtDlpProgressEvent.completed(finalPath);
      } else if (_wasUserCancelled(processKey, exitCode)) {
        yield YtDlpProgressEvent.cancelled();
      } else {
        // yt-dlp failed — but the file might still be usable in the temp dir.
        // Try to salvage only when the candidate is a real final file.
        // DASH intermediates such as `.f251-10.webm` can be audio-only or
        // video-only; treating them as completed hides the real yt-dlp error.
        final checkPath = lastOutputFile ?? outputPath;
        final tempFile = File(checkPath);
        final isIntermediateFormatFile =
            lastOutputFile != null &&
            _isYtDlpIntermediateFormatFile(lastOutputFile);
        if (isIntermediateFormatFile) {
          appLogger.warning(
            '⚠️ [YtDlp] Exit code $exitCode left an intermediate DASH file '
            '($lastOutputFile); not salvaging it as a completed download.',
          );
        }

        // RECODE-CONTRACT GUARD — when the user asked for a recoded
        // container (AVI/MOV/M4V/FLV) and yt-dlp's recode PP failed
        // (typically because the bundled ffmpeg lacks the encoder
        // for that container — `Encoder not found` is the canonical
        // stderr signature), salvaging the merge intermediate would
        // surface the WRONG file: user picked .avi, gets .mkv. That
        // is the exact bug Chairman runtime-reproduced 2026-05-21.
        //
        // Honor the pick-X-get-X contract: if the recoded extension
        // is not on disk, mark the download FAILED with an actionable
        // error message instead of salvaging. The user explicitly
        // chose this container; silently surfacing a different file
        // is data-integrity-class wrong.
        final recodeContractViolated =
            recodeVideo != null &&
            !extractAudio &&
            lastOutputFile != null &&
            !lastOutputFile.toLowerCase().endsWith(
              '.${(videoFormat ?? recodeVideo).toLowerCase()}',
            );
        if (recodeContractViolated) {
          // The USER's intended extension — what the contract check
          // compared against and what the error message surfaces.
          // Distinct from the SCAN ext, which is what yt-dlp actually
          // emitted on disk (.mp4 in the M4V remap case).
          // The guard above promotes recodeVideo to non-null in this
          // branch, so the `??` fallback is non-null without a bang.
          final userExt = (videoFormat ?? recodeVideo).toLowerCase();
          // Scan the temp dir as a last attempt — recode may have
          // produced the file even though yt-dlp exited non-zero
          // (e.g. an embed PP downstream failed). If found, salvage
          // that. If not, fail loudly.
          //
          // RC4b.1: use `_recodeScanExtension` so the M4V remap path
          // (videoFormat=m4v + recodeVideo=mp4) scans for `.mp4`
          // (yt-dlp's actual output) rather than `.m4v` (user's
          // pick). After salvage, `_renameM4vIfApplicable` converts
          // `.mp4 → .m4v` so the final output honors Pick X → Get X
          // across BOTH the exit_code==0 and exit_code!=0 paths.
          final scanExt = _recodeScanExtension(
            videoFormat: videoFormat,
            recodeVideo: recodeVideo,
          );
          var scanned = await _findFileWithExtension(isolatedTempDir, scanExt);
          if (scanned != null) {
            scanned = await _renameM4vIfApplicable(
              filePath: scanned,
              videoFormat: videoFormat,
              recodeVideo: recodeVideo,
            );
            debugPrint(
              '⚠️ [YtDlp] Exit $exitCode but recoded .$userExt file '
              'found via temp-dir scan — salvaging "$scanned" instead '
              'of merge intermediate "$lastOutputFile"',
            );
            final finalPath = await _moveFilesToOutputDir(
              isolatedTempDir,
              outputDir,
              scanned,
            );
            yield YtDlpProgressEvent.completed(finalPath);
            return;
          }
          appLogger.error(
            '❌ [YtDlp] Exit $exitCode + recode .$userExt did NOT '
            'produce target extension (scanned for .$scanExt). '
            'Refusing to salvage merge intermediate "$lastOutputFile" '
            '— would violate pick-X-get-X contract. stderr-excerpt: '
            '${_firstMeaningfulStderrLine(stderr)}',
          );
          try {
            await Directory(isolatedTempDir).delete(recursive: true);
          } catch (_) {}
          // CUX-1: consult stderr for the REAL upstream cause before
          // blaming the recode. A 403/login/rate/network/extraction
          // failure means the download/merge never completed and the
          // recode never ran — "Recode failed, try MP4/MKV" would send the
          // user chasing a container that will also fail. Surface the
          // honest access/login/network cause (raw error one tap away);
          // fall through to the recode/encoder copy only for a genuine
          // post-process failure.
          final upstreamType = classifyRecodeContractFailure(
            stderr: stderr,
            isYouTube: isYouTube,
            hasYouTubeCookies: hasYouTubeCookies,
          );
          if (upstreamType != null) {
            // CUX-1: emit a PII-safe, classifier-STABLE message. Downstream
            // routes on the message (classifyMessage), not on .type, so the
            // wording is the contract: 403→accessDenied, 429→rateLimited,
            // network→networkOffline, login→loginRequired (login only for
            // YouTube w/o cookies, so a signed-in user is never looped).
            yield YtDlpProgressEvent.error(
              YtDlpException(upstreamType, upstreamErrorMessage(upstreamType)),
            );
            return;
          }
          // Genuine post-process failure — the recode (or its encoder) is
          // the real cause. Detect the common ffmpeg "Encoder not found"
          // case so the UX message hints at the real fix (switch container).
          final encoderMissing = stderr.toLowerCase().contains(
            'encoder not found',
          );
          yield YtDlpProgressEvent.error(
            YtDlpException(
              YtDlpErrorType.unknown,
              encoderMissing
                  ? 'Could not encode to .$userExt: the bundled '
                      'ffmpeg lacks an encoder for this container. '
                      'Try MP4 or MKV — same video, no encoder gap.'
                  : 'Recode to .$userExt failed. Try MP4 or MKV '
                      'for the same video.',
            ),
          );
          return;
        }

        if (!isIntermediateFormatFile &&
            await tempFile.exists() &&
            await tempFile.length() > 0) {
          debugPrint(
            '⚠️ [YtDlp] Exit code $exitCode but output file exists in temp — moving to output',
          );
          final finalPath = await _moveFilesToOutputDir(
            isolatedTempDir,
            outputDir,
            lastOutputFile,
          );
          yield YtDlpProgressEvent.completed(finalPath);
        } else {
          if (!isIntermediateFormatFile) {
            // Clean up empty temp dir. When a DASH intermediate exists, keep
            // the temp dir so retry can resume from the partial/original file.
            try {
              await Directory(isolatedTempDir).delete(recursive: true);
            } catch (_) {}
          }
          final parsedErrorType = _parseErrorTypeFromStderr(stderr);
          // CUX-1b: login-safe inference — a signed-in user (cookies present)
          // hitting yt-dlp's "Sign in to confirm you are not a bot" bot-check
          // must NOT be routed to loginRequired (an endless re-login). The
          // old ternary's else returned parsedErrorType, which was itself
          // loginRequired in that case. parsed_error_type telemetry below
          // still records the ORIGINAL parse for dashboard comparison.
          final inferredErrorType = inferDownloadFailureType(
            stderr: stderr,
            isYouTube: isYouTube,
            hasYouTubeCookies: hasYouTubeCookies,
          );
          final firstErrorLine = _firstMeaningfulStderrLine(stderr);
          if (isYouTube) {
            appLogger.error(
              '[YtDlp] YouTube download failed: exit=$exitCode '
              'ytDlpChannel=$ytDlpReleaseChannel '
              'ytDlp=${_version ?? "unknown"} '
              'pot=${potProviderPaths != null} '
              'player_client=$youtubePlayerClientLabel '
              'cookies=$hasYouTubeCookies '
              'format=${effectiveFormat ?? "auto"} '
              'error=$firstErrorLine',
            );
          }
          final String message;
          if (inferredErrorType == YtDlpErrorType.loginRequired) {
            // YouTube without cookies — signing in genuinely helps.
            message = upstreamErrorMessage(YtDlpErrorType.loginRequired);
          } else if (parsedErrorType == YtDlpErrorType.loginRequired) {
            // CUX-1b: a signed-in user (cookies present) hit a sign-in /
            // bot-check line. Surface access-denied so classifyMessage cannot
            // re-derive loginRequired from the raw 'sign in' prose and loop
            // them through a login they have already completed.
            message = upstreamErrorMessage(YtDlpErrorType.unknown);
          } else {
            // Pre-existing generic catch-all: classifyMessage parses the raw
            // stderr to find the real code (network/geo/format/etc.).
            message = 'Download failed: $stderr';
          }
          yield YtDlpProgressEvent.error(
            YtDlpException(
              inferredErrorType,
              message,
              metadata: {
                'source': 'ytdlp_download',
                'exit_code': exitCode,
                'yt_dlp_channel': ytDlpReleaseChannel,
                'yt_dlp_version': _version ?? 'unknown',
                'is_youtube': isYouTube,
                'has_youtube_cookies': hasYouTubeCookies,
                'cookie_source': _youtubeCookieSource(
                  hasYouTubeCookies: hasYouTubeCookies,
                  cookiesFile: cookiesFile,
                  cookiesFromBrowser: cookiesFromBrowser,
                ),
                'pot_provider_enabled': potProviderPaths != null,
                'player_client': youtubePlayerClientLabel,
                'deno_present': _denoPath != null,
                'format': effectiveFormat ?? 'auto',
                'extract_audio': extractAudio,
                'looks_like_http_403': _looksLikeHttp403(stderr),
                'parsed_error_type': parsedErrorType.name,
                'inferred_error_type': inferredErrorType.name,
                'first_error_line': firstErrorLine,
                'stderr_excerpt': _truncateForTelemetry(stderr, 500),
              },
            ),
          );
        }
      }
    } catch (e) {
      // Clean up on error
      _activeProcesses.remove(processKey);
      _cancelledProcessKeys.remove(processKey);
      if (downloadId != null) _downloadIdToProcessKey.remove(downloadId);
      try {
        await Directory(isolatedTempDir).delete(recursive: true);
      } catch (_) {}

      debugPrint('❌ [YtDlp] Download error: $e');
      // DL-017 — spawn failure: ProcessException.toString() embeds the
      // full command line, whose literal `--socket-timeout` flag text
      // used to satisfy the classifier's bare 'timeout' pattern →
      // networkTimeout (retryable) → futile auto-retry with no engine.
      // Surface a command-free message (classifier → ytdlpBinaryMissing,
      // locale-independent) and kick the idempotent capped repair for
      // the race where the binary vanished between the pre-spawn gate
      // and exec.
      if (e is ProcessException) {
        unawaited(_binaryManager.triggerRepair(BinaryType.ytDlp));
        yield YtDlpProgressEvent.error(
          YtDlpException(
            YtDlpErrorType.unknown,
            'Failed to execute yt-dlp: ${e.message}',
          ),
        );
        return;
      }
      yield YtDlpProgressEvent.error(
        YtDlpException(YtDlpErrorType.unknown, e.toString()),
      );
    }
  }

  /// Format Duration as `HH:MM:SS.mmm` for yt-dlp `--download-sections`.
  /// yt-dlp accepts `HH:MM:SS.mmm`, `MM:SS.mmm`, or raw seconds.
  /// Fractional seconds are critical — without them, `--force-keyframes-at-cuts`
  /// re-encodes at the wrong frame boundary (up to ±1s per cut point).
  static String _formatSectionTimestamp(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final ms = d.inMilliseconds.remainder(1000);
    if (ms > 0) {
      return '$hours:$minutes:$seconds.${ms.toString().padLeft(3, '0')}';
    }
    return '$hours:$minutes:$seconds';
  }

  /// Merge two line streams into one. Used to interleave stdout + stderr
  /// so the download progress loop can parse both yt-dlp and ffmpeg output.
  static Stream<String> _mergeLineStreams(Stream<String> a, Stream<String> b) {
    final controller = StreamController<String>();
    var remaining = 2;
    void onDone() {
      if (--remaining == 0) controller.close();
    }

    a.listen(controller.add, onError: controller.addError, onDone: onDone);
    b.listen(controller.add, onError: controller.addError, onDone: onDone);
    return controller.stream;
  }
}

/// Event types for download progress stream
sealed class YtDlpProgressEvent {
  const YtDlpProgressEvent();

  factory YtDlpProgressEvent.progress(YtDlpProgress progress) =
      YtDlpProgressUpdate;
  factory YtDlpProgressEvent.completed(String outputPath) =
      YtDlpDownloadComplete;
  factory YtDlpProgressEvent.error(YtDlpException error) = YtDlpDownloadError;
  factory YtDlpProgressEvent.cancelled() = YtDlpDownloadCancelled;
}

class YtDlpProgressUpdate extends YtDlpProgressEvent {
  final YtDlpProgress progress;
  const YtDlpProgressUpdate(this.progress);
}

class YtDlpDownloadComplete extends YtDlpProgressEvent {
  final String outputPath;
  const YtDlpDownloadComplete(this.outputPath);
}

class YtDlpDownloadError extends YtDlpProgressEvent {
  final YtDlpException error;
  const YtDlpDownloadError(this.error);
}

class YtDlpDownloadCancelled extends YtDlpProgressEvent {
  const YtDlpDownloadCancelled();
}
