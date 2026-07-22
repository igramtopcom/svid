import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../../core/binaries/binary_info.dart';
import '../../../../core/binaries/binary_manager.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/services/disk_space_service.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/utils/file_utils.dart';
import '../../../../core/utils/platform_detector.dart';
import '../../../../core/utils/process_helper.dart';
import '../../../settings/domain/enums/audio_codec_preference.dart';
import '../../../settings/domain/enums/container_format_preference.dart';
import '../../../settings/domain/enums/fps_preference.dart';
import '../../../settings/domain/enums/video_codec_preference.dart';
import '../../../premium/domain/entities/premium_limits.dart';
import '../../../premium/domain/services/download_quota_reserver.dart';
import '../../data/datasources/gallerydl_datasource.dart';
import '../../data/datasources/ytdlp_datasource.dart';
import '../entities/download_entity.dart';
import '../entities/download_error_code.dart';
import '../entities/download_status.dart';
import '../entities/video_info.dart';
import '../repositories/download_repository.dart';
import '../services/download_error_classifier.dart';
import '../services/file_integrity_service.dart';
import '../services/container_planner.dart';
import '../services/format_selector_service.dart';
import '../services/quality_resolution_parser.dart';
import '../services/resolution_filter_utils.dart';
import '../services/telemetry_metadata_keys.dart';

typedef DownloadFailureTelemetrySink =
    void Function({
      required DownloadEntity download,
      required DownloadErrorCode errorCode,
      required String errorPhase,
      required String errorMessage,
      required Map<String, dynamic> metadata,
    });

/// Use case for starting a new download (yt-dlp only)
class StartDownloadUseCase {
  final DownloadRepository _repository;
  final YtDlpDataSource _ytdlpDataSource;
  final GalleryDlDataSource _galleryDlDataSource;
  final FileIntegrityService? _fileIntegrityService;
  final DownloadQuotaReserver? _quotaReserver;
  final DownloadFailureTelemetrySink? _downloadFailureTelemetrySink;

  StartDownloadUseCase(
    this._repository,
    this._ytdlpDataSource,
    this._galleryDlDataSource, [
    this._fileIntegrityService,
    this._quotaReserver,
    this._downloadFailureTelemetrySink,
  ]);

  Future<Result<DownloadEntity>> call({
    required VideoInfo videoInfo,
    required Quality selectedQuality,
    required String savePath,
    required bool isPremium,
    bool quotaAlreadyReserved = false,
    int quotaCount = 1,
    String? cookiesFile,
    String? cookiesFromBrowser,
    int? audioBitrateKbps,

    /// Ordered browser candidate chain for the cookie-retry path.
    /// Empty list (default) preserves legacy single-shot behaviour.
    /// Callers should pass `cookiesFromBrowserFallbackChainProvider`.
    List<String> cookiesFromBrowserFallbackChain = const [],
    // Format preferences
    VideoCodecPreference videoCodecPreference = VideoCodecPreference.h264,
    AudioCodecPreference audioCodecPreference = AudioCodecPreference.aac,
    ContainerFormatPreference containerFormatPreference =
        ContainerFormatPreference.mp4,
    FpsPreference fpsPreference = FpsPreference.auto,
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
    // === Multi-Segment Download ===
    int numSegments = 1,
    // === Output Filename Template ===
    String filenameTemplate = '%(title)s.%(ext)s',
    // === Custom Postprocessor Args ===
    String customPostprocessorArgs = '',
    // === Section download ===
    Duration? sectionStartTime,
    Duration? sectionEndTime,
    List<(Duration, Duration)>? selectedChapterRanges,
    // === Out-of-band signals to caller ===
    /// Invoked synchronously when the format selector decides the
    /// user-preferred container has to be auto-promoted (e.g. MP4 →
    /// MKV at YouTube ≥1440p where the only audio is Opus). The
    /// callback fires BEFORE yt-dlp is launched so a UI snackbar can
    /// disclose the swap up front rather than springing it on the
    /// user when the file lands. Domain layer stays UI-agnostic — the
    /// callback is passed in by the presentation layer.
    void Function(String warning)? onContainerChangeWarning,
  }) async {
    try {
      appLogger.info('🚀 Starting download for: ${videoInfo.title}');
      appLogger.debug('🔧 Quality: ${selectedQuality.qualityText}');
      appLogger.debug(
        '🔧 Codec: ${videoCodecPreference.displayName}, Container: ${containerFormatPreference.extension}',
      );

      // Validate save path
      if (!Validators.isValidPath(savePath)) {
        return Result.failure(
          const AppException.validation(message: 'Invalid save path'),
        );
      }

      // Preflight free disk space. Returns null when the platform check
      // cannot run (UNC paths, unsupported OS) — we treat that as "unknown,
      // proceed" because preflight is opportunistic, not a hard gate.
      // Returns false only when we definitively know the disk cannot hold
      // the download + muxing/scratch headroom. Surfaces the same
      // user-facing diskFull error code as a runtime ENOSPC, so the UI
      // recovery copy is consistent and the retry-loop guard already in
      // DownloadsNotifier short-circuits the auto-retry path that would
      // otherwise burn through bandwidth.
      //
      // Production checklist evidence: rolling 24h diskFull = 6, rolling
      // 168h = 47. A meaningful fraction includes retry-loop burn after
      // the first ENOSPC, which preflight prevents end-to-end.
      final requiredBytes = selectedQuality.filesizeBytes ?? 0;
      final hasSpace = await DiskSpaceService.hasEnoughSpace(
        savePath,
        requiredBytes: requiredBytes,
      );
      if (hasSpace == false) {
        appLogger.warning(
          '🛑 Preflight: not enough disk space for download. '
          'savePath=$savePath, required=$requiredBytes bytes + '
          'headroom=${DiskSpaceService.defaultHeadroomBytes} bytes',
        );
        return Result.failure(
          const AppException.download(
            message: 'Not enough disk space to start this download',
          ),
        );
      }

      // Warn if save path is inside a cloud sync folder.
      // Downloads still work (temp dir isolation protects against file locking),
      // but user should be aware of potential sync overhead.
      final cloudService = _detectCloudSyncFolder(savePath);
      if (cloudService != null) {
        appLogger.warning(
          '⚠️ Download folder is inside $cloudService. '
          'Downloads are protected via temp dir isolation, but consider '
          'using a local folder for best performance.',
        );
      }

      // Detect platform
      final detectedPlatform = PlatformDetector.detectPlatform(videoInfo.url);
      final platformString = detectedPlatform.toDbString();
      appLogger.debug('Platform: $platformString');

      // Check quality type
      final isYtdlpQuality = selectedQuality.encryptedUrl.startsWith('ytdlp:');
      final isGalleryDlQuality = selectedQuality.encryptedUrl.startsWith(
        'gallerydl:',
      );
      final isSubtitleOnly = selectedQuality.encryptedUrl.startsWith(
        'ytdlp:subtitle:',
      );

      // Subtitle-only downloads are handled via yt-dlp --write-sub --skip-download
      if (isSubtitleOnly) {
        final quotaFailure = _reserveQuotaIfNeeded(
          isPremium: isPremium,
          quotaAlreadyReserved: quotaAlreadyReserved,
          quotaCount: quotaCount,
        );
        if (quotaFailure != null) return quotaFailure;

        appLogger.info('📝 [Download] Subtitle-only download');
        return _downloadSubtitleOnly(
          url: videoInfo.url,
          savePath: savePath,
          videoTitle: videoInfo.title,
          thumbnail: videoInfo.thumbnail,
          qualityKey: selectedQuality.encryptedUrl,
          qualityLabel: selectedQuality.qualityText,
          cookiesFile: cookiesFile,
          cookiesFromBrowser: cookiesFromBrowser,
          uploader: videoInfo.effectiveUploader,
          subtitlesFormat: subtitlesFormat,
        );
      }

      // Gallery-dl qualities are handled the same way in all engine modes
      if (isGalleryDlQuality) {
        // gallery-dl_macos is ARM64-only — Intel Macs can't run it
        if (!BinaryManager.isGalleryDlSupported) {
          return Result.failure(
            const AppException.download(
              message:
                  'Image downloads are not available on Intel Macs. '
                  'gallery-dl requires Apple Silicon (M1/M2/M3/M4).',
            ),
          );
        }
        final quotaFailure = _reserveQuotaIfNeeded(
          isPremium: isPremium,
          quotaAlreadyReserved: quotaAlreadyReserved,
          quotaCount: quotaCount,
        );
        if (quotaFailure != null) return quotaFailure;

        appLogger.info('🖼️ [Download] Gallery-dl image download');
        return _downloadWithGalleryDl(
          url: videoInfo.url,
          savePath: savePath,
          videoTitle: videoInfo.title,
          thumbnail: videoInfo.thumbnail,
          range: _parseGalleryDlRange(selectedQuality.encryptedUrl),
          cookiesFile: cookiesFile,
          uploader: videoInfo.effectiveUploader,
          qualityLabel: selectedQuality.qualityText,
          platform: PlatformDetector.detectPlatform(videoInfo.url).toDbString(),
          qualityKey: selectedQuality.encryptedUrl,
        );
      }

      // Reject legacy API qualities — only yt-dlp qualities are supported
      if (!isYtdlpQuality) {
        appLogger.error('❌ Legacy API quality selected — no longer supported');
        return Result.failure(
          const AppException.download(
            message:
                'Legacy API qualities are no longer supported. '
                'Please re-extract the video to get updated quality options.',
          ),
        );
      }

      final resolutionFailure = _rejectHighResolutionIfNeeded(
        selectedQuality: selectedQuality,
        isPremium: isPremium,
      );
      if (resolutionFailure != null) return resolutionFailure;

      final quotaFailure = _reserveQuotaIfNeeded(
        isPremium: isPremium,
        quotaAlreadyReserved: quotaAlreadyReserved,
        quotaCount: quotaCount,
      );
      if (quotaFailure != null) return quotaFailure;

      final selectedQualityHeight = QualityResolutionParser.heightForQuality(
        selectedQuality,
      );

      // Smart container for high-res (Chairman 2026-07). A 1440p+ MP4 pick on
      // YouTube almost always lands VP9/AV1 (no avc1 above 1080p), which MP4
      // can only hold via an expensive, fragile full transcode to H.264 — the
      // root cause of slow "Converting" states and mass post-processing
      // failures on 4K playlist downloads. Deliver MKV instead (holds
      // VP9/AV1/Opus natively → fast, lossless remux). Reassigned BEFORE the
      // format parse + planner so the whole pipeline (selector, merge target,
      // naming, extension guard) derives from MKV → a coherent .mkv. Shared
      // rule with the picker UI via ContainerPlanner.resolveSmartContainer.
      containerFormatPreference = ContainerPlanner.resolveSmartContainer(
        picked: containerFormatPreference,
        platform: detectedPlatform,
        height: selectedQualityHeight,
      );

      var (
        ytdlpFormat,
        audioFormat,
        videoFormat,
        sortOptions,
        splitChapters,
        mergeFormatPriority,
        containerChangeWarning,
      ) = _parseYtdlpFormat(
        selectedQuality.encryptedUrl,
        videoCodec: videoCodecPreference,
        audioCodec: audioCodecPreference,
        container: containerFormatPreference,
        fps: fpsPreference,
        maxVideoHeight: isPremium ? null : PremiumLimits.freeMaxResolutionP,
        selectedQualityHeight: selectedQualityHeight,
      );
      // Legacy buildSelection warning is now always null after the
      // pick-X-get-X refactor; we keep the variable + plumbing wire so
      // call sites compile unchanged, but the new authoritative source
      // is the planner-driven recode notice below.
      if (containerChangeWarning != null && onContainerChangeWarning != null) {
        onContainerChangeWarning(containerChangeWarning);
      }
      if (selectedQuality.isAudioOnly &&
          selectedQuality.encryptedUrl.startsWith('ytdlp:raw:')) {
        audioFormat ??= StartDownloadUseCase.inferRawAudioFormat(
          selectedQuality,
        );
      }

      // ContainerPlanner — pick-X-get-X enforcement.
      //
      // Compute the authoritative yt-dlp arg plan from (container,
      // sourceVcodec, sourceAcodec). When codecs fit the picked
      // container the planner emits --remux-video <pick> (fast,
      // stream-copy, lossless). Native containers (mp4/mkv/webm) never
      // request hidden full conversion; only explicit conversion
      // containers (avi/mov/m4v/flv) emit --recode-video. The user's
      // chosen extension is always honored. For audio-only downloads
      // the plan is null — the existing audio extraction path keeps
      // its contract.
      ContainerPlan? containerPlan;
      String? remuxVideo;
      String? recodeVideo;
      if (selectedQuality.mediaType != MediaType.audio) {
        // Unbounded "best available" with no concrete height — the
        // selector may resolve to any codec yt-dlp serves, so the
        // planner cannot promise remux works and forces the recode
        // path. Mirror the parser's `isUnbounded` detection.
        final isUnbounded =
            ytdlpFormat != null &&
            ytdlpFormat.contains('bestvideo+bestaudio') &&
            QualityResolutionParser.heightForQuality(selectedQuality) == null;
        containerPlan = _containerPlanner.plan(
          pickedContainer: containerFormatPreference,
          sourceVcodec: selectedQuality.vcodec,
          sourceAcodec: selectedQuality.acodec,
          isUnboundedQuality: isUnbounded,
        );
        // OVERRIDE selector's merge priority with planner's. For the
        // happy path (codecs fit) this is identical; for the recode
        // path the planner routes through universal MKV intermediate
        // even though the user's pick is non-MKV.
        mergeFormatPriority = containerPlan.mergeFormat;
        remuxVideo = containerPlan.remuxVideo;
        recodeVideo = containerPlan.recodeVideo;

        // Q+1: WebM is an output target, not a source-stream filter.
        // Facebook / Instagram / Reddit can expose only MP4/H.264/AAC
        // sources; a WebM-native selector fails before FFmpeg can
        // convert ("Requested format is not available", vidcombo
        // log.md 2026-05-25 #427 Facebook + #430 Instagram). When
        // WebM needs conversion (recode already decided OR non-YouTube
        // source not proven WebM-native), choose a broad source at
        // the requested height and let the visible converting phase
        // produce the requested .webm. Helper lives in
        // [ContainerPlanner] so the retry path
        // (`DownloadsNotifier._buildRetryPlanFromSettings`) shares
        // the SAME decision logic — per mirror discipline
        // [[feedback_mirror_path_diff_line_by_line]].
        if (ContainerPlanner.shouldForceWebmOutputRecode(
          platform: detectedPlatform,
          videoFormat: videoFormat,
          recodeVideo: recodeVideo,
          remuxVideo: remuxVideo,
          sourceVcodec: selectedQuality.vcodec,
          sourceAcodec: selectedQuality.acodec,
        )) {
          recodeVideo = 'webm';
          remuxVideo = null;
          mergeFormatPriority = ContainerPlanner.webmRecodeMergeFormatPriority;
        }
        if (recodeVideo?.toLowerCase() == 'webm') {
          ytdlpFormat = ContainerPlanner.buildWebmRecodeSourceSelector(
            targetHeight: selectedQualityHeight,
            maxVideoHeight: isPremium ? null : PremiumLimits.freeMaxResolutionP,
          );
          // Wave A (AUD-2) — keep the webm-native bias on the forced
          // arm. The bare 'res:H' override picked AAC audio over
          // available Opus, which alone defeats the webm-first merge
          // prover (AAC is not webm-compatible → merge falls to mkv →
          // full libvpx re-encode of a webm-native VIDEO stream
          // because of an avoidable AUDIO pick). `ext:webm:opus` is
          // the same soft bias buildSortOptions emits for every other
          // webm path.
          sortOptions =
              selectedQualityHeight != null
                  ? 'res:$selectedQualityHeight,ext:webm:opus'
                  : 'res,ext:webm:opus';
        }
        // N2/N4 mirror (2026-06): same MP4 decision on the fresh path per
        // mirror discipline. A proven avc1/h264/hevc/av1 source returns
        // false here (fast remux preserved); only the YouTube
        // can't-prove-native edge (PO-Token/SABR avc1-advertised-but-
        // unprovable) forces recode so a 1080p+ MP4 pick that lands VP9
        // still produces a real .mp4. The datasource C3 salvage covers the
        // avc1-advertised-but-vp9-delivered surprise this check can't see.
        if (ContainerPlanner.shouldForceMp4OutputRecode(
          platform: detectedPlatform,
          videoFormat: videoFormat,
          recodeVideo: recodeVideo,
          remuxVideo: remuxVideo,
          sourceVcodec: selectedQuality.vcodec,
        )) {
          recodeVideo = 'mp4';
          remuxVideo = null;
          mergeFormatPriority = ContainerPlanner.mp4RecodeMergeFormatPriority;
        }
      }

      // FFmpeg gate for DASH merge formats. A `bestvideo+bestaudio`
      // format string needs FFmpeg to mux the two streams. The
      // pre-fix behavior was to silently rewrite to plain `best`
      // when FFmpeg was missing, which on YouTube degrades to the
      // pre-muxed single stream — typically 360p — and the user
      // who picked "MP4 · Best" had no idea their download was
      // capped. This block replaces that silent degrade with three
      // ordered steps the production-grade contract requires:
      //
      //   1. Detect the FFmpeg-required-but-missing case.
      //   2. Auto-repair: `BinaryManager.triggerRepair(BinaryType.ffmpeg)`
      //      via `YtDlpDataSource.ensureFFmpegOrRepair()`. Idempotent,
      //      collapses fan-out from concurrent downloads to a single
      //      re-download. Reuses the same pattern shipped for Deno
      //      in Phase B.
      //   3. If repair fails, surface an actionable error and bail
      //      out — DO NOT fall back to 360p. The user can retry
      //      after fixing the underlying cause (Defender whitelist,
      //      disk space, network) or pick a lower quality.
      //
      // Diagnostic log carries the fields Codex's audit asked for
      // (selected quality label, encrypted URL, ytdlp format
      // before/after the gate, FFmpeg state before/after) so a
      // future "MP4 · Best → 360p" report can pinpoint the root
      // case (Case A FFmpeg gate vs Case B preset matcher) from
      // the log without code changes.
      if (ytdlpFormat != null &&
          ytdlpFormat.contains('+') &&
          !_ytdlpDataSource.hasFFmpeg) {
        appLogger.warning(
          '🔧 [Download] FFmpeg missing for DASH format "$ytdlpFormat" — '
          'attempting auto-repair before user-visible failure...',
        );
        final repaired = await _ytdlpDataSource.ensureFFmpegOrRepair();
        appLogger.info(
          '[Download] FFmpeg gate diagnostic: '
          'selectedEncryptedUrl=${selectedQuality.encryptedUrl}, '
          'qualityLabel=${selectedQuality.qualityText}, '
          'ytdlpFormat_preGate=$ytdlpFormat, '
          'hasFFmpeg_preGate=false, '
          'repairAttempted=true, '
          'repairSucceeded=$repaired, '
          'hasFFmpeg_postGate=${_ytdlpDataSource.hasFFmpeg}',
        );
        if (!repaired) {
          // Explicit failure with actionable message — replaces the
          // pre-fix silent fallback to `best` / 360p.
          return Result.failure(
            const AppException.download(
              message:
                  'Media tools (FFmpeg) unavailable on this machine. '
                  'High-quality download needs FFmpeg to merge the video '
                  'and audio streams YouTube serves separately at 1080p+. '
                  'Open Settings → yt-dlp Engine to reinstall, then retry. '
                  'You can also pick a lower quality that does not need '
                  'merging.',
            ),
          );
        }
        // Repair succeeded — proceed with the original DASH format
        // string. No fallback needed.
      }

      // Serialize chapters for DB persistence
      final chaptersJson =
          videoInfo.hasChapters
              ? jsonEncode(
                videoInfo.chapters
                    .map(
                      (c) => {
                        'title': c.title,
                        'startTime': c.startTime,
                        'endTime': c.endTime,
                      },
                    )
                    .toList(),
              )
              : null;

      return _downloadWithYtdlp(
        url: videoInfo.url,
        savePath: savePath,
        videoTitle: videoInfo.title,
        thumbnail: videoInfo.thumbnail,
        format: ytdlpFormat,
        sortOptions: sortOptions,
        extractAudio: selectedQuality.mediaType == MediaType.audio,
        audioFormat: audioFormat,
        audioBitrateKbps:
            selectedQuality.mediaType == MediaType.audio
                ? audioBitrateKbps
                : null,
        videoFormat: videoFormat,
        mergeFormatPriority: mergeFormatPriority,
        remuxVideo: remuxVideo,
        recodeVideo: recodeVideo,
        cookiesFile: cookiesFile,
        cookiesFromBrowser: cookiesFromBrowser,
        cookiesFromBrowserFallbackChain: cookiesFromBrowserFallbackChain,
        requireAudioStream: !selectedQuality.isVideoOnly,
        // Rich metadata
        uploader: videoInfo.effectiveUploader,
        durationSeconds: videoInfo.duration?.inSeconds,
        viewCount: videoInfo.viewCount,
        uploadDate:
            videoInfo.uploadDate != null
                ? '${videoInfo.uploadDate!.year}${videoInfo.uploadDate!.month.toString().padLeft(2, '0')}${videoInfo.uploadDate!.day.toString().padLeft(2, '0')}'
                : null,
        qualityLabel: selectedQuality.qualityText,
        maxVideoHeight: isPremium ? null : PremiumLimits.freeMaxResolutionP,
        targetVideoHeight:
            selectedQuality.mediaType == MediaType.audio
                ? null
                : selectedQualityHeight ??
                    (isPremium ? null : PremiumLimits.freeMaxResolutionP),
        chaptersJson: chaptersJson,
        // === P0 Features ===
        subtitlesEnabled: subtitlesEnabled,
        subtitlesLanguages: subtitlesLanguages,
        subtitlesFormat: subtitlesFormat,
        embedSubtitles: embedSubtitles,
        includeAutoSubs: includeAutoSubs,
        writeThumbnail: writeThumbnail,
        embedThumbnail: embedThumbnail,
        embedMetadata: embedMetadata,
        embedChapters: embedChapters,
        sponsorBlockEnabled: sponsorBlockEnabled,
        sponsorBlockAction: sponsorBlockAction,
        sponsorBlockCategories: sponsorBlockCategories,
        // === P1 Features ===
        splitChapters: splitChapters,
        liveFromStart: videoInfo.isLive,
        forceRemux: forceRemux,
        // === P2 Features ===
        tiktokRemoveWatermark: tiktokRemoveWatermark,
        // === P3 Features ===
        proxyUrl: proxyUrl,
        geoBypass: geoBypass,
        geoBypassCountry: geoBypassCountry,
        archiveEnabled: archiveEnabled,
        archiveFile: archiveFile,
        dateAfter: dateAfter,
        dateBefore: dateBefore,
        minDuration: minDuration,
        maxDuration: maxDuration,
        // === Network Tuning ===
        socketTimeout: socketTimeout,
        maxRetries: maxRetries,
        httpChunkSizeMb: httpChunkSizeMb,
        // === Output Filename Template ===
        filenameTemplate: filenameTemplate,
        // === Custom Postprocessor Args ===
        customPostprocessorArgs: customPostprocessorArgs,
        // === Section download ===
        sectionStartTime: sectionStartTime,
        sectionEndTime: sectionEndTime,
        selectedChapterRanges: selectedChapterRanges,
      );
    } catch (e, stack) {
      appLogger.error('❌ Download failed', e, stack);
      return Result.failure(
        AppException.download(
          message: 'Download failed: ${AppExceptionX.readableMessage(e)}',
        ),
      );
    }
  }

  static const _formatSelector = FormatSelectorService();
  static const _containerPlanner = ContainerPlanner();

  Result<DownloadEntity>? _reserveQuotaIfNeeded({
    required bool isPremium,
    required bool quotaAlreadyReserved,
    required int quotaCount,
  }) {
    if (quotaAlreadyReserved) return null;
    final quotaReserver = _quotaReserver;
    if (quotaReserver == null) {
      appLogger.warning(
        '⚠️ [Quota] StartDownloadUseCase has no quota reserver; '
        'allowing download for backward compatibility',
      );
      return null;
    }

    if (!quotaReserver.tryConsume(isPremium: isPremium, count: quotaCount)) {
      appLogger.info(
        '🚫 [Quota] Domain gate blocked download '
        '(${quotaReserver.currentPeriodCount()} consumed this week)',
      );
      return Result.failure(
        const AppException.download(
          message:
              'Weekly free download limit reached — upgrade for unlimited downloads.',
        ),
      );
    }

    appLogger.info('📊 [Quota] Domain gate reserved $quotaCount slot(s)');
    return null;
  }

  void _emitDownloadFailureTelemetry({
    required DownloadEntity download,
    required DownloadErrorCode errorCode,
    required String errorMessage,
    required Map<String, dynamic> ytdlpMetadata,
    required String? cookiesFile,
    required String? cookiesFromBrowser,
    required int fallbackChainCursor,
    required int fallbackChainLength,
    required bool cookieRetryAttempted,
    required int appRetryCount,
  }) {
    final sink = _downloadFailureTelemetrySink;
    if (sink == null) return;

    try {
      sink(
        download: download,
        errorCode: errorCode,
        // This hook is emitted only from the yt-dlp download stream terminal
        // path. Keep the top-level phase truthful even when the semantic error
        // code is accessDenied/loginRequired; extraction has its own telemetry
        // sink in ExtractVideoInfoUseCase.
        errorPhase: 'download',
        errorMessage: '${errorCode.name}:$errorMessage',
        metadata: {
          ...ytdlpMetadata,
          'download_method': download.downloadMethod,
          'yt_dlp_channel': ytDlpReleaseChannel,
          if (!ytdlpMetadata.containsKey('yt_dlp_version'))
            'yt_dlp_version': _ytdlpDataSource.version ?? 'unknown',
          'quality_label': download.qualityLabel,
          'platform': download.platform,
          'local_cookies_file_present': cookiesFile != null,
          'local_cookies_from_browser': cookiesFromBrowser,
          'fallback_chain_cursor': fallbackChainCursor,
          'fallback_chain_length': fallbackChainLength,
          'cookie_retry_attempted': cookieRetryAttempted,
          'app_retry_count': appRetryCount,
          // C5 telemetry schema (see TelemetryMetadataKeys). Backward-
          // compat key `terminal_error_code` kept alongside the schema
          // names so existing dashboards stay green during migration.
          TelemetryMetadataKeys.terminalErrorCode: errorCode.name,
          TelemetryMetadataKeys.effectiveErrorCode: errorCode.name,
          TelemetryMetadataKeys.attemptIndex: appRetryCount,
          if (TelemetryMetadataKeys.extractHttpStatusCode(errorMessage) != null)
            TelemetryMetadataKeys.httpStatusCode:
                TelemetryMetadataKeys.extractHttpStatusCode(errorMessage),
          if (TelemetryMetadataKeys.extractFormatProtocol(errorMessage) != null)
            TelemetryMetadataKeys.formatProtocol:
                TelemetryMetadataKeys.extractFormatProtocol(errorMessage),
        },
      );
    } catch (_) {
      // Telemetry must never affect the download state machine.
    }
  }

  Result<DownloadEntity>? _rejectHighResolutionIfNeeded({
    required Quality selectedQuality,
    required bool isPremium,
  }) {
    if (isPremium) return null;

    final height = QualityResolutionParser.heightForQuality(selectedQuality);
    if (height == null || height <= PremiumLimits.freeMaxResolutionP) {
      return null;
    }

    appLogger.info(
      '🚫 [Premium] Domain gate blocked ${height}p quality '
      'for free tier (${PremiumLimits.freeMaxResolutionP}p max)',
    );
    return Result.failure(
      AppException.download(
        message:
            'Premium required for video qualities above ${PremiumLimits.freeMaxResolutionP}p.',
      ),
    );
  }

  /// Parse yt-dlp format from quality string with codec preferences.
  /// Returns (format, audioFormat, videoFormat, sortOptions, splitChapters,
  /// mergeFormatPriority, containerChangeWarning) tuple.
  ///
  /// `mergeFormatPriority` is the `/`-joined priority list passed to
  /// yt-dlp's `--merge-output-format`. It diverges from the literal
  /// `videoFormat` / container preference when the user-preferred
  /// container cannot honestly hold the codecs likely to be served at
  /// the requested height — most notably MP4 at YouTube heights ≥1440p,
  /// where only VP9/AV1+Opus DASH streams exist and MP4 has no native
  /// Opus support. Premium "best available" with no upper height cap
  /// is treated the same way (unbounded → can resolve to 4K → likely
  /// Opus territory). The auto-promotion lives in
  /// [FormatSelectorService.resolveMergeFormatPriority]; the returned
  /// `videoFormat` is the effective container extension so the on-disk
  /// file truthfully matches its content; `sortOptions` is built
  /// against the effective container so the `-S` flag does not
  /// contradict the merge priority; `containerChangeWarning` is a
  /// short user-facing string set when the swap happened (null
  /// otherwise) so the orchestrator can surface a snackbar.
  (String?, String?, String?, String?, bool, String?, String?)
  _parseYtdlpFormat(
    String qualityKey, {
    VideoCodecPreference videoCodec = VideoCodecPreference.h264,
    AudioCodecPreference audioCodec = AudioCodecPreference.aac,
    ContainerFormatPreference container = ContainerFormatPreference.mp4,
    FpsPreference fps = FpsPreference.auto,
    int? maxVideoHeight,
    int? selectedQualityHeight,
  }) {
    final parts = qualityKey.split(':');
    if (parts.length < 2) return (null, null, null, null, false, null, null);

    final format = parts[1].toLowerCase();

    // Check for split_chapters flag (e.g., ytdlp:best:mp4:split_chapters)
    final splitChapters = parts.any((p) => p == 'split_chapters');

    // Best quality with video format: ytdlp:best:mp4, ytdlp:best:mkv, etc.
    if (format == 'best') {
      // `ytdlp:best:mp4` can represent two different user intents:
      //
      // * an extracted concrete row such as "Best (1080p)", where the
      //   quality label already tells us the highest real stream height;
      // * a true unbounded "best available" preset, where the stream may
      //   resolve to 1440p/4K and must keep the MKV safety net.
      //
      // Prefer the extracted height when present so a concrete 1080p row
      // does not get treated as unknown 4K and saved as MKV unnecessarily.
      final targetHeight = _effectiveBestTargetHeight(
        selectedQualityHeight: selectedQualityHeight,
        maxVideoHeight: maxVideoHeight,
      );
      final isUnbounded = targetHeight == null;
      final effectiveContainer = _formatSelector.resolveEffectiveContainer(
        container: container,
        targetHeight: targetHeight,
        isUnboundedQuality: isUnbounded,
      );
      // RC10 Codex-round-3 — normalize codec preferences against the
      // EFFECTIVE container BEFORE handing them to the low-level
      // builder. Pre-fix, an explicit `audioCodec=Opus` + MP4
      // container would emit `bestaudio[acodec^=opus]` against an
      // MP4 picker, leaving MP4+Opus to slip through ContainerPlanner
      // as a forced recode or wrong-codec stream. The normalizers
      // demote any container-incompatible codec back to `.auto`,
      // matching what `buildSelection()` already does internally.
      final normalizedVideoCodec = _formatSelector
          .normalizeVideoCodecForContainer(videoCodec, effectiveContainer);
      final normalizedAudioCodec = _formatSelector
          .normalizeAudioCodecForContainer(audioCodec, effectiveContainer);
      final mergePriority = _formatSelector.resolveMergeFormatPriority(
        container: container,
        targetHeight: targetHeight,
        videoCodec: normalizedVideoCodec,
        isUnboundedQuality: isUnbounded,
      );
      final sortOptions = _formatSelector.buildSortOptions(
        videoCodec: normalizedVideoCodec,
        audioCodec: normalizedAudioCodec,
        fps: fps,
        container: effectiveContainer,
        targetHeight: targetHeight,
      );
      final formatSelector = _formatSelector.buildBestFormatSelector(
        videoCodec: normalizedVideoCodec,
        audioCodec: normalizedAudioCodec,
        fps: fps,
        maxHeight: targetHeight,
        // RC10 Codex-round-2 catch 1 — thread effective container so
        // the selector's fallback chain stays codec-compatible
        // (`[ext=mp4]+[ext=m4a]` for MP4, etc.) instead of falling
        // through to any-codec `/best` which RC10.2 ContainerPlanner
        // would then refuse to hidden-recode.
        container: effectiveContainer,
      );
      final warning = _buildContainerChangeWarning(
        requested: container,
        resolved: effectiveContainer,
      );
      return (
        formatSelector,
        null,
        effectiveContainer.extension,
        sortOptions,
        splitChapters,
        mergePriority,
        warning,
      );
    }

    // Audio format: ytdlp:audio:mp3, ytdlp:audio:m4a, etc.
    if (format == 'audio') {
      final audioFormat = parts.length >= 3 ? parts[2].toLowerCase() : 'mp3';
      // DL-003 defense C: `[acodec!=none]` keeps yt-dlp from ever picking a
      // storyboard (vcodec=none/acodec=none, e.g. `sb0`) for an audio
      // extract, which would emit `.mhtml` instead of the requested audio.
      //
      // Wave A (AUD-3) — opus target gets a soft `acodec:opus` sort so
      // the pick is the NATIVE opus stream and FFmpegExtractAudioPP
      // stream-copies it. With a null sort the datasource default
      // (`res,ext:mp4:m4a`) biased the pick to AAC, turning every
      // opus extraction into an avoidable double-lossy AAC→opus
      // transcode. Other targets keep the null sort: m4a is already
      // biased to the copy path by the default; mp3/wav/flac
      // transcode regardless of the source pick.
      return (
        'bestaudio[acodec!=none]/best[acodec!=none]',
        audioFormat,
        null,
        audioFormat == 'opus' ? 'acodec:opus' : null,
        false,
        null,
        null,
      );
    }

    // Raw format ID: ytdlp:raw:FORMAT_ID (direct stream selection)
    if (format == 'raw' && parts.length >= 3) {
      final formatId = parts[2];
      return (formatId, null, container.extension, null, false, null, null);
    }

    // Parse resolution format (e.g., 2160p, 1440p, 1080p, 720p, 480p)
    final heightMatch = RegExp(r'^(\d+)p').firstMatch(format);
    if (heightMatch != null) {
      final height = int.parse(heightMatch.group(1)!);
      final effectiveHeight =
          maxVideoHeight != null && height > maxVideoHeight
              ? maxVideoHeight
              : height;
      final effectiveContainer = _formatSelector.resolveEffectiveContainer(
        container: container,
        targetHeight: effectiveHeight,
      );
      // RC10 Codex-round-3 — same codec-vs-container normalization as
      // the unbounded path. Stops MP4+Opus / WebM+AAC slipping through
      // when settings/preset codec doesn't match container.
      final normalizedVideoCodec = _formatSelector
          .normalizeVideoCodecForContainer(videoCodec, effectiveContainer);
      final normalizedAudioCodec = _formatSelector
          .normalizeAudioCodecForContainer(audioCodec, effectiveContainer);
      final mergePriority = _formatSelector.resolveMergeFormatPriority(
        container: container,
        targetHeight: effectiveHeight,
        videoCodec: normalizedVideoCodec,
      );
      final sortOptions = _formatSelector.buildSortOptions(
        videoCodec: normalizedVideoCodec,
        audioCodec: normalizedAudioCodec,
        fps: fps,
        container: effectiveContainer,
        targetHeight: effectiveHeight,
      );
      final formatSelector = _formatSelector.buildResolutionFormatSelector(
        height: effectiveHeight,
        videoCodec: normalizedVideoCodec,
        audioCodec: normalizedAudioCodec,
        fps: fps,
        // RC10 Codex-round-2 catch 1 — same container-threading rule
        // as the unbounded path above. Resolution selector also needs
        // it so the height-bounded fallback chain stays codec-
        // compatible (no surprise VP9 in an MP4 picker).
        container: effectiveContainer,
      );
      final warning = _buildContainerChangeWarning(
        requested: container,
        resolved: effectiveContainer,
      );
      return (
        formatSelector,
        null,
        effectiveContainer.extension,
        sortOptions,
        splitChapters,
        mergePriority,
        warning,
      );
    }

    return (null, null, null, null, false, null, null);
  }

  int? _effectiveBestTargetHeight({
    required int? selectedQualityHeight,
    required int? maxVideoHeight,
  }) {
    if (selectedQualityHeight == null) return maxVideoHeight;
    if (maxVideoHeight == null) return selectedQualityHeight;
    return selectedQualityHeight < maxVideoHeight
        ? selectedQualityHeight
        : maxVideoHeight;
  }

  /// Compose the user-facing snackbar text emitted when MP4 was
  /// auto-promoted to MKV. Returns null when no swap happened.
  /// The text deliberately stays short and platform-agnostic — the
  /// long-form i18n version (`configDialog.containerChangedWarning`)
  /// is handled by call sites that have an [AppLocalizations] context;
  /// the legacy use-case path here just emits a plain string for the
  /// snackbar surface.
  String? _buildContainerChangeWarning({
    required ContainerFormatPreference requested,
    required ContainerFormatPreference resolved,
  }) {
    if (requested == resolved) return null;
    return 'Saved as ${resolved.extension.toUpperCase()} instead of '
        '${requested.extension.toUpperCase()}: the requested container '
        "can't hold the audio codec served at this resolution.";
  }

  /// Infer the best yt-dlp/ffmpeg audio output format for a raw audio stream.
  ///
  /// Raw audio items in the quality list already expose the source codec
  /// (e.g. Opus 132kbps, AAC 129kbps). Without this mapping, the audio-only
  /// path falls back to MP3, so selecting a raw Opus/AAC stream still produces
  /// an `.mp3` file in Finder.
  @visibleForTesting
  static String? inferRawAudioFormat(Quality quality) {
    if (!quality.isAudioOnly) return null;

    final codec = quality.acodec?.toLowerCase();
    if (codec == null || codec.isEmpty || codec == 'none') return null;

    if (codec.startsWith('opus')) return 'opus';
    if (codec.startsWith('mp4a') ||
        codec.startsWith('aac') ||
        codec.startsWith('alac')) {
      return 'm4a';
    }
    if (codec.startsWith('mp3')) return 'mp3';
    if (codec.startsWith('flac')) return 'flac';
    if (codec.contains('vorbis')) return 'ogg';
    if (codec.startsWith('wav') || codec.startsWith('pcm')) return 'wav';

    return null;
  }

  @visibleForTesting
  static Duration postProcessingTimeoutForTest({
    required String? recodeVideo,
    required int? selectedHeight,
    required Duration? videoDuration,
    bool extractAudio = false,
  }) => resolvePostProcessingTimeout(
    recodeVideo: recodeVideo,
    selectedHeight: selectedHeight,
    videoDuration: videoDuration,
    extractAudio: extractAudio,
  );

  /// RC10 round-5 — promoted from `_resolvePostProcessingTimeout` so
  /// the retry path in `DownloadRepositoryImpl._retryYtdlpDownload`
  /// can share the same dynamic FFmpeg timeout policy. Pre-fix, the
  /// retry path had no post-process timeout and could hang forever
  /// on a stuck ffmpeg; this single source of truth keeps fresh
  /// download + retry behavior in sync.
  static Duration resolvePostProcessingTimeout({
    required String? recodeVideo,
    required int? selectedHeight,
    required Duration? videoDuration,
    bool extractAudio = false,
  }) {
    // Merge/remux/post-metadata should finish quickly. Keep the legacy
    // 5-minute guard for these paths so a stuck FFmpeg process does not
    // hang the queue forever.
    //
    // Wave B (AUD-5) — extract-audio is EXEMPT from the 5m guard: a
    // lossy `-x --audio-format mp3/opus` from a mismatched source is a
    // full-duration transcode (same workload class as --recode-video),
    // and the app's bitrate-enforcement second pass shares the same
    // watchdog window. The fixed 5m wall killed long content
    // (podcasts, mixes) mid-conversion on weak machines and destroyed
    // completed download work — the standing 74 audio-MP3-timeout
    // telemetry rows. Retries inherited the same wall = unrecoverable.
    // Note: HW-accel (DL-013) can never fix this arm — there is no
    // hardware MP3 encoder; the duration-aware budget is the lever.
    // Copy-path extractions (m4a-from-AAC) finish in seconds and are
    // unaffected by a generous ceiling — the watchdog is a safety
    // net, not a pacer.
    if (recodeVideo == null && !extractAudio) {
      return const Duration(minutes: 5);
    }

    // `--recode-video` is a full transcode for explicit conversion
    // containers (AVI/MOV/M4V/FLV). A fixed 300s timeout can kill valid
    // high-resolution conversion work and misroute the item to
    // waiting-for-network. Use a conservative dynamic timeout; users can
    // still cancel manually if they decide the conversion is too slow.
    final height = selectedHeight ?? 0;
    final baseTimeout = switch (height) {
      >= 4320 => const Duration(minutes: 90),
      >= 2160 => const Duration(minutes: 45),
      >= 1440 => const Duration(minutes: 30),
      _ => const Duration(minutes: 15),
    };
    final durationMultiplier = switch (height) {
      >= 4320 => 12,
      >= 2160 => 8,
      >= 1440 => 6,
      _ => 4,
    };

    var timeout = baseTimeout;
    final contentDuration = videoDuration;
    if (contentDuration != null && contentDuration > Duration.zero) {
      final durationBased = Duration(
        seconds: contentDuration.inSeconds * durationMultiplier,
      );
      timeout = _maxDuration(timeout, durationBased);
    }

    return _minDuration(timeout, const Duration(hours: 4));
  }

  static Duration _maxDuration(Duration a, Duration b) => a >= b ? a : b;

  static Duration _minDuration(Duration a, Duration b) => a <= b ? a : b;

  static String _formatDurationForLog(Duration duration) {
    if (duration.inHours > 0) {
      final minutes = duration.inMinutes.remainder(60);
      return minutes == 0
          ? '${duration.inHours}h'
          : '${duration.inHours}h ${minutes}m';
    }
    if (duration.inMinutes > 0) return '${duration.inMinutes}m';
    return '${duration.inSeconds}s';
  }

  // Q+1 (2026-05-25 retry-mirror fix): the WebM-output-target
  // decision helpers (shouldForceWebmOutputRecode +
  // buildWebmRecodeSourceSelector) used to live here as private
  // statics on `StartDownloadUseCase`. They are now public methods
  // on `ContainerPlanner` so the retry path in
  // `DownloadsNotifier._buildRetryPlanFromSettings` can call the
  // SAME logic — single source of truth, no drift. Original test
  // seams (`webmRecodeSourceSelectorForTest`,
  // `shouldForceWebmOutputRecodeForTest`) updated to forward to
  // the shared methods so existing tests keep passing without
  // duplication.
  @visibleForTesting
  static String webmRecodeSourceSelectorForTest({
    int? targetHeight,
    int? maxVideoHeight,
  }) => ContainerPlanner.buildWebmRecodeSourceSelector(
    targetHeight: targetHeight,
    maxVideoHeight: maxVideoHeight,
  );

  @visibleForTesting
  static bool shouldForceWebmOutputRecodeForTest({
    required VideoPlatform platform,
    String? videoFormat,
    String? recodeVideo,
    String? remuxVideo,
    String? sourceVcodec,
    String? sourceAcodec,
  }) => ContainerPlanner.shouldForceWebmOutputRecode(
    platform: platform,
    videoFormat: videoFormat,
    recodeVideo: recodeVideo,
    remuxVideo: remuxVideo,
    sourceVcodec: sourceVcodec,
    sourceAcodec: sourceAcodec,
  );

  /// RC2 of Ultra Plan v3 — Facebook progressive fallback transform.
  ///
  /// When the Facebook DASH merge produces a no-audio file the
  /// download loop retries ONCE with yt-dlp's progressive
  /// single-file selector `best[ext=mp4]/best`. Pre-RC2 that
  /// transform also nulled `mergeFormatPriority`, `remuxVideo`, and
  /// `recodeVideo`, which broke Pick X → Get X — a user who picked
  /// AVI got an MP4 because the recode post-process was dropped.
  ///
  /// RC2 keeps those three args. The merge-format-priority is moot
  /// in progressive mode but yt-dlp ignores it harmlessly. Remux/
  /// recode apply to the single progressive MP4 as a post-process,
  /// so the user's container pick survives the fallback. Only the
  /// format selector changes; sort options pair with the format
  /// selector so they go away too.
  static FacebookProgressiveFallbackResult _applyFacebookProgressiveFallback({
    required String? mergeFormatPriority,
    required String? remuxVideo,
    required String? recodeVideo,
  }) {
    return FacebookProgressiveFallbackResult(
      format: 'best[ext=mp4]/best',
      sortOptions: null,
      mergeFormatPriority: mergeFormatPriority,
      remuxVideo: remuxVideo,
      recodeVideo: recodeVideo,
    );
  }

  @visibleForTesting
  static FacebookProgressiveFallbackResult
  applyFacebookProgressiveFallbackForTest({
    required String? format,
    required String? sortOptions,
    required String? mergeFormatPriority,
    required String? remuxVideo,
    required String? recodeVideo,
  }) => _applyFacebookProgressiveFallback(
    mergeFormatPriority: mergeFormatPriority,
    remuxVideo: remuxVideo,
    recodeVideo: recodeVideo,
  );

  @visibleForTesting
  static bool shouldRetryWithoutCookiesAfterDownloadErrorForTest({
    required DownloadErrorCode errorCode,
    required String platformString,
  }) => _shouldRetryWithoutCookiesAfterDownloadError(
    errorCode: errorCode,
    platformString: platformString,
  );

  static bool _shouldRetryWithoutCookiesAfterDownloadError({
    required DownloadErrorCode errorCode,
    required String platformString,
  }) {
    if (errorCode == DownloadErrorCode.formatUnavailable) return true;

    // YouTube can reject signed GVS media URLs with HTTP 403 when a cookie
    // session is stale or bound to a problematic client/IP. One no-cookie
    // retry restores the main-compatible public path for public videos; if
    // the video really needs auth, the retry returns loginRequired and the
    // existing login flow handles it.
    return platformString == 'youtube' &&
        errorCode == DownloadErrorCode.accessDenied;
  }

  @visibleForTesting
  static bool shouldPreserveCookieRetryOriginalErrorForTest({
    required DownloadErrorCode originalErrorCode,
    required DownloadErrorCode retryErrorCode,
  }) => _shouldPreserveCookieRetryOriginalError(
    originalErrorCode: originalErrorCode,
    retryErrorCode: retryErrorCode,
  );

  static bool _shouldPreserveCookieRetryOriginalError({
    required DownloadErrorCode originalErrorCode,
    required DownloadErrorCode retryErrorCode,
  }) {
    // Removing cookies from a session-bound YouTube media request commonly
    // turns a GVS 403 into "Sign in to confirm" on the retry. That loginRequired
    // is a retry artifact, not proof that another login will fix the original
    // cookie-bound 403. Preserve the original accessDenied so the UI doesn't
    // bounce users into a repeated login loop.
    return originalErrorCode == DownloadErrorCode.accessDenied &&
        retryErrorCode == DownloadErrorCode.loginRequired;
  }

  /// Download using yt-dlp with real-time progress streaming
  Future<Result<DownloadEntity>> _downloadWithYtdlp({
    required String url,
    required String savePath,
    required String videoTitle,
    String? thumbnail,
    String? format,
    String? sortOptions,
    bool extractAudio = false,
    String? audioFormat,
    int? audioBitrateKbps,
    String? videoFormat,
    String? mergeFormatPriority,
    String? remuxVideo,
    String? recodeVideo,
    String? cookiesFile,
    String? cookiesFromBrowser,
    List<String> cookiesFromBrowserFallbackChain = const [],
    bool requireAudioStream = true,
    // Rich metadata from VideoInfo
    String? uploader,
    int? durationSeconds,
    int? viewCount,
    String? uploadDate,
    String? qualityLabel,
    int? maxVideoHeight,
    int? targetVideoHeight,
    String? chaptersJson,
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
    // === Output Filename Template ===
    String filenameTemplate = '%(title)s.%(ext)s',
    // === Custom Postprocessor Args ===
    String customPostprocessorArgs = '',
    // === Section download ===
    Duration? sectionStartTime,
    Duration? sectionEndTime,
    List<(Duration, Duration)>? selectedChapterRanges,
  }) async {
    try {
      appLogger.info('🔍 [yt-dlp] Starting download...');

      // Determine file extension based on content type
      final extension =
          extractAudio ? (audioFormat ?? 'mp3') : (videoFormat ?? 'mp4');
      var filename = FileUtils.sanitizeFilename(videoTitle);
      // Quality label (e.g. " [MP3 · 320 kbps]") prevents collisions between
      // concurrent same-video qualities. It is passed to the path-limit bound
      // as a preserved suffix (below), so a long title is shortened but the
      // tag is never mangled into "[MP" — the extension + tag stay intact.
      final labelSuffix =
          (qualityLabel != null && qualityLabel.isNotEmpty)
              ? ' [${FileUtils.sanitizeFilename(qualityLabel)}]'
              : '';
      if (!filename.endsWith('.$extension')) {
        filename = '$filename.$extension';
      }
      // WIN-1/DL-007: bound the FULL output path to the platform limit BEFORE
      // dedup, so both `savePath/filename` and the worst-case temp write path
      // fit Windows MAX_PATH (260 UTF-16 units). A long Facebook/CJK title in a
      // deep folder otherwise overflows and surfaces as a late, generic
      // pathNotFound. No-op on POSIX (sanitizeFilename's component cap suffices)
      // and a no-op here when the name already fits — only the stem is trimmed,
      // the extension and (after this) the dedup counter are preserved.
      final boundedFilename = FileUtils.boundFilenameToPathLimit(
        fileName: filename,
        preserveSuffix: labelSuffix,
        candidateDirs: [savePath, YtDlpDataSource.worstCaseIsolatedTempDir()],
        maxPathUnits: Platform.isWindows ? FileUtils.windowsMaxPathUnits : null,
      );
      if (boundedFilename == null) {
        appLogger.warning(
          '🛑 Preflight: save folder path is too long for the OS limit. '
          'savePath=$savePath (len=${savePath.length})',
        );
        return Result.failure(
          const AppException.download(
            message:
                'The save folder path is too long for Windows (260-character '
                'limit). Choose a shorter folder, or move it closer to the '
                'drive root, then try again.',
          ),
        );
      }
      filename = boundedFilename;
      filename = await FileUtils.getUniqueFilename(savePath, filename);

      // Detect platform
      final detectedPlatform = PlatformDetector.detectPlatform(url);
      final platformString = detectedPlatform.toDbString();

      // Reddit: prefer HLS to avoid DASH "Conflicting range" CDN failures.
      // Reddit CDN returns invalid Content-Range headers for DASH segments,
      // causing "start > end" errors. HLS uses per-segment downloads without
      // byte-range requests, avoiding the issue entirely.
      if (detectedPlatform == VideoPlatform.reddit && !extractAudio) {
        // Prefer HLS format IDs (Reddit uses hls-* for HLS, dash-* for DASH)
        final hlsFirst = ResolutionFilterUtils.joinVideoAudioVariants(
          videoSelector: 'bestvideo[format_id^=hls]',
          audioSelector: 'bestaudio[format_id^=hls]',
          resolution: maxVideoHeight,
        );
        final safeBest =
            maxVideoHeight != null
                ? ResolutionFilterUtils.joinSingleFileVariants(
                  selector: 'best',
                  resolution: maxVideoHeight,
                )
                : 'bestvideo+bestaudio/best';
        format = format != null ? '$hlsFirst/$format' : '$hlsFirst/$safeBest';
        // Also sort by protocol preference so fallback still prefers HLS
        sortOptions = 'proto:m3u8_native,${sortOptions ?? "res,ext:mp4:m4a"}';
        // RC10 Q-round C2: HLS streams on Reddit are typically MP4
        // chunks (H.264/AAC). If user picked WebM output, planner's
        // null-permissive `remuxVideo='webm'` would blow up at post-
        // remux step. Promote remux → recode so the MP4 chunks are
        // transcoded to VP9/Opus. Reddit + WebM is rare but the swap
        // costs nothing for the common Reddit + MP4 case (no-op).
        final webmSwap =
            ContainerPlanner.promoteWebMRemuxToRecodeForPlatformFallback(
              videoFormat: videoFormat,
              recodeVideo: recodeVideo,
              remuxVideo: remuxVideo,
            );
        recodeVideo = webmSwap.recodeVideo;
        remuxVideo = webmSwap.remuxVideo;
      }

      // Create download record (status: pending) with rich metadata
      final createResult = await _repository.createDownload(
        url: url,
        filename: filename,
        savePath: savePath,
        thumbnail: thumbnail,
        platform: platformString,
        downloadMethod: 'ytdlp',
        title: videoTitle,
        uploader: uploader,
        duration: durationSeconds,
        viewCount: viewCount,
        uploadDate: uploadDate,
        qualityLabel: qualityLabel,
        chaptersJson: chaptersJson,
      );

      if (createResult.isFailure) {
        return createResult;
      }

      final download = createResult.dataOrThrow;

      // Update status to downloading
      await _repository.updateDownloadStatus(
        download.id,
        DownloadStatus.downloading,
      );

      // Capture shared state into locals — prevents race conditions when
      // multiple concurrent calls overwrite instance fields while background
      // monitoring futures are still reading them.
      //
      // Mutable so the cookie-retry branch (mirroring extraction's
      // `_retryWithoutCookies` in [ExtractVideoInfoUseCase]) can drop
      // bad cookies for the next retry pass without re-fetching them.
      String? localCookiesFile = cookiesFile;
      String? localCookiesFromBrowser = cookiesFromBrowser;
      final localCookiesFromBrowserFallbackChain = List<String>.unmodifiable(
        cookiesFromBrowserFallbackChain,
      );

      // Fire-and-forget: monitoring runs in background, caller returns immediately
      unawaited(() async {
        // Sentinel: flipped to `true` AFTER a terminal repository
        // commit (completeDownload / cancelled). Declared OUTSIDE
        // the try so the catch handler below can read it — Dart
        // does NOT leak `try` block locals into the matching
        // `catch` block. Without this flag a single post-commit
        // throw (e.g. TCC denial inside `_cleanupDashOriginals`)
        // silently flips a successfully-downloaded file's status
        // to `permissionDenied` on the user's surface (cf. log.md
        // 2026-05-12 §517).
        var downloadCommitted = false;
        try {
          // App-level retry loop for yt-dlp process failures
          const maxAppRetries = 3;
          var appRetryCount = 0;
          // One-shot cookie-retry guard. Mirrors extraction's pattern:
          // formatNotAvailable + cookies present → likely YouTube SABR
          // format / expired cookies → retry once without cookies before
          // giving up. Without this branch the download path's hardcoded
          // `isRetryable` set treats formatUnavailable as terminal even
          // though dropping cookies would have recovered (cf. log line
          // 451-457 vs 569 — extraction recovers, download dies).
          var cookieRetryAttempted = false;
          DownloadErrorCode? cookieRetryOriginalErrorCode;
          String? cookieRetryOriginalErrorMessage;
          Map<String, dynamic>? cookieRetryOriginalMetadata;
          // Phase 2 (Codex review 2026-05-13): browser fallback chain
          // cursor for the download path. When the primary cookies are
          // null AND yt-dlp surfaces a recoverable auth/format error,
          // we advance through the platform-aware chain (Edge → Firefox
          // → … on Windows, etc.) one candidate per pass. Pre-fix the
          // download path had NO fallback at all — extract would
          // recover via fallback browser but download would re-run
          // yt-dlp with the empty cookies and die with loginRequired.
          var fallbackChainCursor = 0;
          var lastProgressWrite = DateTime(0); // Throttle DB writes
          const progressThrottleMs = 250; // Max 4 writes/sec per download

          // Facebook progressive fallback guard. yt-dlp's Facebook
          // extractor offers both DASH (bestvideo+bestaudio merge) AND
          // progressive (`hd`/`sd` single-file). The DASH merge path
          // has been failing in production (Wilson Rubio support
          // ticket + tester `.f964607196458600v.mp4` no-audio incident)
          // — likely a Facebook-side change to the DASH stream format
          // or the bundled ffmpeg's handling of it. When the integrity
          // check finds the merged output has no audio AND we haven't
          // already tried the progressive single-file path, retry
          // ONCE with `-f best[ext=mp4]/best`. yt-dlp's `best` selector
          // picks the highest-quality progressive stream when one is
          // available, which is exactly the path CLI users confirm
          // works for Wilson's URL. After one retry the flag flips so
          // we don't loop forever — a genuinely broken URL still
          // surfaces a single "Download Failed" instead of an
          // infinite retry.
          var progressiveFallbackAttempted = false;

          // Track temp dir across retries so the next attempt can --continue from
          // .part files instead of re-downloading from 0%. Updated on first
          // creation via onTempDirCreated; reused on every subsequent retry.
          String? persistedTempDir;
          // Monotonic byte guard — prevents progress from visually jumping
          // backward when yt-dlp transitions between streams (video → audio) or
          // hands off to ffmpeg for section cutting.
          int lastDownloadedBytes = 0;

          while (true) {
            // Start yt-dlp download with progress streaming
            final progressStream = _ytdlpDataSource.downloadWithProgress(
              url: url,
              outputDir: savePath,
              downloadId: download.id,
              outputTemplate:
                  filenameTemplate != '%(title)s.%(ext)s'
                      ? filenameTemplate
                      : filename.replaceAll('.$extension', '.%(ext)s'),
              format: format,
              sortOptions: sortOptions,
              cookiesFile: localCookiesFile,
              cookiesFromBrowser: localCookiesFromBrowser,
              extractAudio: extractAudio,
              audioFormat: extractAudio ? (audioFormat ?? 'mp3') : null,
              audioBitrateKbps: extractAudio ? audioBitrateKbps : null,
              videoFormat: !extractAudio ? (videoFormat ?? 'mp4') : null,
              mergeFormatPriority: !extractAudio ? mergeFormatPriority : null,
              remuxVideo: !extractAudio ? remuxVideo : null,
              recodeVideo: !extractAudio ? recodeVideo : null,
              maxVideoHeight: maxVideoHeight,
              targetVideoHeight: targetVideoHeight,
              // === P0 Features ===
              subtitlesEnabled: subtitlesEnabled,
              subtitlesLanguages: subtitlesLanguages,
              subtitlesFormat: subtitlesFormat,
              embedSubtitles: embedSubtitles,
              includeAutoSubs: includeAutoSubs,
              writeThumbnail: writeThumbnail,
              embedThumbnail: embedThumbnail,
              embedMetadata: embedMetadata,
              embedChapters: embedChapters,
              sponsorBlockEnabled: sponsorBlockEnabled,
              sponsorBlockAction: sponsorBlockAction,
              sponsorBlockCategories: sponsorBlockCategories,
              // === P1 Features ===
              splitChapters: splitChapters,
              liveFromStart: liveFromStart,
              forceRemux: forceRemux,
              // === P2 Features ===
              tiktokRemoveWatermark: tiktokRemoveWatermark,
              // === P3 Features ===
              proxyUrl: proxyUrl,
              geoBypass: geoBypass,
              geoBypassCountry: geoBypassCountry,
              archiveEnabled: archiveEnabled,
              archiveFile: archiveFile,
              dateAfter: dateAfter,
              dateBefore: dateBefore,
              minDuration: minDuration,
              maxDuration: maxDuration,
              // === Network Tuning ===
              socketTimeout: socketTimeout,
              maxRetries: maxRetries,
              httpChunkSizeMb: httpChunkSizeMb,
              // === Custom Postprocessor Args ===
              customPostprocessorArgs: customPostprocessorArgs,
              // === Section download ===
              sectionStartTime: sectionStartTime,
              sectionEndTime: sectionEndTime,
              selectedChapterRanges: selectedChapterRanges,
              // === Post-processing robustness ===
              keepVideo: !extractAudio, // Keep DASH originals for merge retry
              // === Resume support ===
              // On retry, hand back the temp dir from the previous attempt so
              // yt-dlp's --continue picks up the .part files instead of starting
              // a fresh download (otherwise every failed retry burns full
              // bandwidth and leaves orphaned temp files behind).
              existingTempDir: persistedTempDir,
              onTempDirCreated: (tempDir) {
                persistedTempDir = tempDir;
                // Persist temp dir path so app-restart recovery can also resume.
                _repository.updateTempDirPath(download.id, tempDir);
              },
            );

            final postProcessingTimeoutDuration = resolvePostProcessingTimeout(
              recodeVideo: recodeVideo,
              selectedHeight:
                  QualityResolutionParser.parseHeight(qualityLabel ?? '') ??
                  maxVideoHeight,
              videoDuration:
                  durationSeconds != null
                      ? Duration(seconds: durationSeconds)
                      : null,
              extractAudio: extractAudio,
            );

            // Track state
            int estimatedTotalBytes = 0;
            String? finalOutputPath;
            YtDlpException? downloadError;
            bool wasCancelled = false;
            bool postProcessingTimedOut = false;
            Timer? postProcessingTimeout;

            // Listen to progress stream
            await for (final event in progressStream) {
              switch (event) {
                case YtDlpProgressUpdate(:final progress):
                  if (progress.totalBytes != null && progress.totalBytes! > 0) {
                    estimatedTotalBytes = progress.totalBytes!;
                  }

                  final rawDownloadedBytes =
                      progress.downloadedBytes ??
                      (estimatedTotalBytes > 0
                          ? (progress.percent * estimatedTotalBytes / 100)
                              .round()
                          : 0);

                  // Monotonic byte guard. yt-dlp emits progress per *current
                  // operation* (video stream, then audio stream, then ffmpeg cut),
                  // so the raw byte count can drop between phases — visually
                  // looks like the download is restarting. Hold the high-water
                  // mark instead.
                  final downloadedBytes =
                      rawDownloadedBytes > lastDownloadedBytes
                          ? rawDownloadedBytes
                          : lastDownloadedBytes;
                  lastDownloadedBytes = downloadedBytes;

                  // Throttle DB writes to max 4/sec — reduces UI rebuilds and SQLite contention
                  final now = DateTime.now();
                  if (now.difference(lastProgressWrite).inMilliseconds >=
                          progressThrottleMs ||
                      progress.percent >= 99.5) {
                    lastProgressWrite = now;
                    await _repository.updateDownloadProgress(
                      id: download.id,
                      downloadedBytes: downloadedBytes,
                      totalBytes: estimatedTotalBytes,
                      speed: progress.speed?.round() ?? 0,
                    );
                  }

                  // Detect FFmpeg errors from Rust parser (e.g. "[ffmpeg] Error...")
                  if (progress.status == YtDlpDownloadStatus.error) {
                    appLogger.error(
                      '❌ [yt-dlp] FFmpeg/Merger error detected in stdout',
                    );
                    // Don't set postProcessing status — this is an error, not success
                  }
                  // Update status if post-processing (FFmpeg converting/merging)
                  else if (progress.status ==
                          YtDlpDownloadStatus.postProcessing ||
                      progress.status == YtDlpDownloadStatus.merging ||
                      progress.status == YtDlpDownloadStatus.remuxing ||
                      progress.status == YtDlpDownloadStatus.converting) {
                    // Start FFmpeg timeout on first postProcessing event
                    postProcessingTimeout ??= Timer(
                      postProcessingTimeoutDuration,
                      () {
                        postProcessingTimedOut = true;
                        appLogger.error(
                          '⏰ [FFmpeg] Post-processing timeout '
                          '(${_formatDurationForLog(postProcessingTimeoutDuration)}) '
                          '— killing process',
                        );
                        _ytdlpDataSource.cancelByDownloadId(download.id);
                      },
                    );
                    // RC10.3: map the new yt-dlp sub-states (merging /
                    // remuxing / converting) to the matching
                    // DownloadStatus values so the UI shows the actual
                    // phase instead of generic "Processing". Legacy
                    // generic `postProcessing` event still maps to the
                    // legacy DownloadStatus.postProcessing value (used
                    // when yt-dlp emits the JSON status field rather
                    // than a `[Merger]` / `[VideoRemuxer]` /
                    // `[VideoConvertor]` stdout marker).
                    final ds = switch (progress.status) {
                      YtDlpDownloadStatus.merging => DownloadStatus.merging,
                      YtDlpDownloadStatus.remuxing => DownloadStatus.remuxing,
                      YtDlpDownloadStatus.converting =>
                        DownloadStatus.converting,
                      _ => DownloadStatus.postProcessing,
                    };
                    await _repository.updateDownloadStatus(download.id, ds);
                    appLogger.info('🔄 [yt-dlp] Post-processing (${ds.name})');
                  }

                  appLogger.debug(
                    '[yt-dlp] ${progress.percent.toStringAsFixed(1)}% | '
                    '${_formatSpeed(progress.speed)} | ETA: ${progress.eta?.inSeconds ?? 0}s',
                  );

                case YtDlpDownloadComplete(:final outputPath):
                  postProcessingTimeout?.cancel();
                  finalOutputPath = outputPath;
                  appLogger.info('✅ [yt-dlp] Completed: $outputPath');

                case YtDlpDownloadError(:final error):
                  postProcessingTimeout?.cancel();
                  downloadError = error;
                  appLogger.error('❌ [yt-dlp] Error: ${error.message}');

                case YtDlpDownloadCancelled():
                  postProcessingTimeout?.cancel();
                  wasCancelled = true;
                  appLogger.warning('🛑 [yt-dlp] Cancelled');
              }
            }
            postProcessingTimeout?.cancel(); // Safety cleanup

            // Handle FFmpeg timeout.
            if (postProcessingTimedOut && !extractAudio) {
              // `--recode-video` is a full transcode, not a stream-copy
              // merge. Retrying the DASH merge cannot recover this path
              // (there may be no kept originals by the time yt-dlp is in
              // VideoConvertor, and even if there are, the failing step is
              // the conversion). Surface it as an FFmpeg error instead of
              // misclassifying as a network timeout / waiting-for-network.
              if (recodeVideo != null) {
                final timeoutLabel = _formatDurationForLog(
                  postProcessingTimeoutDuration,
                );
                final targetFormat = videoFormat ?? recodeVideo ?? 'video';
                appLogger.info(
                  '⏰ [FFmpeg] Recode exceeded $timeoutLabel — '
                  'not attempting merge retry.',
                );
                await _repository.failDownload(
                  id: download.id,
                  errorMessage:
                      'ffmpegError:FFmpeg post-processing exceeded '
                      '$timeoutLabel while converting to '
                      '${targetFormat.toUpperCase()}. '
                      'Try MKV/WebM for high-resolution YouTube videos '
                      'to avoid a slow full conversion.',
                );
                return;
              }
              appLogger.info(
                '⏰ [FFmpeg] Timeout detected — attempting merge retry...',
              );
              final retryResult = await _retryMergeWithFFmpeg(
                outputDir: savePath,
                filenameWithoutExt: p.basenameWithoutExtension(
                  filename.replaceAll('.%(ext)s', ''),
                ),
                targetExt: videoFormat ?? 'mp4',
                downloadId: download.id,
              );
              if (retryResult != null) return;
              // Retry failed — fall through to error handling
              await _repository.failDownload(
                id: download.id,
                errorMessage:
                    'ffmpegError:FFmpeg merge exceeded '
                    '${_formatDurationForLog(postProcessingTimeoutDuration)}',
              );
              return;
            }

            // Handle final result
            if (finalOutputPath != null) {
              // Validate output file exists and is non-empty (DASH merge may fail silently)
              var outputFile = File(finalOutputPath);
              var fileExists = await outputFile.exists();
              var fileSize = fileExists ? await outputFile.length() : 0;

              // Fallback: if file not found, scan output directory for recent matching files.
              // This handles Windows encoding mismatch where yt-dlp stdout filename is corrupted
              // (e.g., cp1252 vs UTF-8) but the actual file on disk has the correct name.
              if (!fileExists || fileSize == 0) {
                final expectedExt = p.extension(finalOutputPath).toLowerCase();
                final fallback = await _findRecentOutputFile(
                  savePath,
                  expectedExt,
                );
                if (fallback != null) {
                  appLogger.info(
                    '🔄 [yt-dlp] Output file not found at parsed path, '
                    'but found recent file: ${fallback.path}',
                  );
                  finalOutputPath = fallback.path;
                  outputFile = fallback;
                  fileExists = true;
                  fileSize = await fallback.length();
                }
              }

              if (!fileExists || fileSize == 0) {
                appLogger.error(
                  '❌ [yt-dlp] Output file missing or empty! '
                  'Path: $finalOutputPath, exists: $fileExists, size: $fileSize',
                );

                // Attempt merge retry with DASH originals if available
                if (!extractAudio) {
                  final retryResult = await _retryMergeWithFFmpeg(
                    outputDir: savePath,
                    filenameWithoutExt: p.basenameWithoutExtension(
                      finalOutputPath,
                    ),
                    targetExt: p
                        .extension(finalOutputPath)
                        .replaceFirst('.', ''),
                    downloadId: download.id,
                  );
                  if (retryResult != null) return;
                }

                final errorMsg =
                    fileExists
                        ? 'Download produced an empty file (merge may have failed)'
                        : 'Output file not found after download (merge may have failed)';
                await _repository.failDownload(
                  id: download.id,
                  errorMessage: errorMsg,
                );
                return;
              }

              // F1.1: File integrity check (container / stream /
              // magic-byte validation). Runs BEFORE cleanup so a
              // fatal integrity failure preserves the DASH
              // originals — the user can debug or re-merge with the
              // raw video+audio streams still on disk. Two failure
              // modes are possible — non-fatal (FFprobe complained
              // but file likely intact, e.g. exotic codec metadata
              // that confuses the parser) and fatal (the file's
              // structural shape is provably broken — most notably
              // the "video file with no audio stream" symptom of a
              // silent merge fail when MP4 was asked to hold Opus).
              // The non-fatal path stays a log-only warning so a
              // monitoring quirk does not sink a working file. The
              // fatal path is converted to a real download failure
              // so the user sees an actionable error instead of a
              // "Completed" record pointing at a silent file.
              final integrityResult = await _fileIntegrityService?.verifyFile(
                finalOutputPath,
                requireAudioStream: requireAudioStream,
              );
              if (integrityResult != null && !integrityResult.isValid) {
                if (integrityResult.isFatal) {
                  // Facebook DASH merge → progressive fallback. The
                  // "no audio" fatal is the exact production symptom
                  // for Wilson + the tester `.f<id>v.mp4` incident:
                  // yt-dlp downloaded the DASH video-only stream and
                  // the merge with the audio stream either failed
                  // silently or wrote the wrong file. yt-dlp's
                  // progressive `best` (single-file `hd`/`sd`) works
                  // on the same URLs per CLI verification, so a
                  // one-shot retry with the progressive selector
                  // recovers Wilson's flow without changing
                  // happy-path behavior for any other platform.
                  final reasonLower =
                      (integrityResult.reason ?? '').toLowerCase();
                  final isNoAudio = reasonLower.contains('no audio');
                  final isFacebook = detectedPlatform == VideoPlatform.facebook;
                  if (isFacebook &&
                      isNoAudio &&
                      !progressiveFallbackAttempted &&
                      !extractAudio) {
                    progressiveFallbackAttempted = true;
                    appLogger.warning(
                      '⚠️ [Facebook] DASH merge produced no-audio file '
                      '— falling back to progressive single-file '
                      'download (`best[ext=mp4]/best`) and retrying. '
                      'File: $finalOutputPath',
                    );
                    // Delete the orphan video-only file so the retry
                    // does not see it as an existing partial.
                    try {
                      final orphan = File(finalOutputPath);
                      if (await orphan.exists()) await orphan.delete();
                    } catch (e) {
                      appLogger.warning(
                        '⚠️ [Facebook] Could not delete orphan '
                        'video-only file ($e); retry may overwrite.',
                      );
                    }
                    // RC2 of Ultra Plan v3 — preserve Pick X → Get X
                    // across the fallback. Switch the format selector
                    // to progressive single-file, but KEEP the
                    // container-enforcement post-processing args
                    // (`mergeFormatPriority`, `remuxVideo`,
                    // `recodeVideo`). Without this preservation, a
                    // user who picked AVI/MOV/MKV silently got an MP4
                    // because the progressive fallback dropped the
                    // recode step. Merge-format-priority is moot in
                    // progressive mode (no streams to merge), but
                    // yt-dlp ignores it harmlessly so keeping it is
                    // safe. Recode/remux apply to the single
                    // progressive MP4 as a post-process so the user's
                    // container pick survives the fallback.
                    final fb = _applyFacebookProgressiveFallback(
                      mergeFormatPriority: mergeFormatPriority,
                      remuxVideo: remuxVideo,
                      recodeVideo: recodeVideo,
                    );
                    format = fb.format;
                    sortOptions = fb.sortOptions;
                    mergeFormatPriority = fb.mergeFormatPriority;
                    remuxVideo = fb.remuxVideo;
                    recodeVideo = fb.recodeVideo;
                    // RC10 Q-round C2: Facebook progressive fallback
                    // forces `format = 'best[ext=mp4]/best'`. If the
                    // user picked WebM output, the planner-emitted
                    // `remuxVideo = 'webm'` would now blow up at the
                    // post-remux step (H.264/AAC into WebM). Promote
                    // remux → recode so the progressive MP4 is
                    // transcoded to VP9/Opus. Source-of-truth detection
                    // via `videoFormat` arg below — empty here, but the
                    // helper also checks recodeVideo/remuxVideo.
                    final webmSwap =
                        ContainerPlanner.promoteWebMRemuxToRecodeForPlatformFallback(
                          videoFormat: videoFormat,
                          recodeVideo: recodeVideo,
                          remuxVideo: remuxVideo,
                        );
                    recodeVideo = webmSwap.recodeVideo;
                    remuxVideo = webmSwap.remuxVideo;
                    // Re-loop with the new format. The outer `while
                    // (true)` will spawn a fresh yt-dlp process; the
                    // flag prevents infinite retries.
                    continue;
                  }
                  appLogger.error(
                    '❌ [FileIntegrity] yt-dlp output failed FATAL integrity '
                    'check: ${integrityResult.reason} — marking download '
                    'failed (file: $fileSize bytes at $finalOutputPath)',
                  );
                  // DL-012: delete the orphan final-folder file. The fatal
                  // result already proved it is broken (no video / no audio /
                  // truncated tiny stub); a FAILED download must NOT leave a
                  // few-dozen-KB "file" in the user's Downloads that they
                  // mistake for a successful download.
                  try {
                    final orphan = File(finalOutputPath);
                    if (await orphan.exists()) await orphan.delete();
                  } catch (e) {
                    appLogger.warning(
                      '⚠️ [FileIntegrity] Could not delete orphan failed '
                      'file ($e) at $finalOutputPath',
                    );
                  }
                  await _repository.updateTempDirPath(download.id, null);
                  await _repository.failDownload(
                    id: download.id,
                    errorMessage:
                        integrityResult.reason ??
                        'Downloaded file failed integrity check',
                  );
                  return;
                }
                appLogger.warning(
                  '⚠️ [FileIntegrity] yt-dlp output has integrity warning: ${integrityResult.reason} '
                  '— completing download anyway (file: $fileSize bytes)',
                );
              }

              appLogger.info(
                '✅ [yt-dlp] Output validated: $finalOutputPath ($fileSize bytes)',
              );

              // RC10 Q-round C3 — final-extension guard, fresh path
              // mirror of the datasource pre-move guard (defense in
              // depth per mirror discipline). If somehow a wrong-
              // extension file slipped past the datasource layer
              // (selector override escaped C2 promote, planner +
              // platform fallback race condition, future regression),
              // fail the download instead of marking completed with
              // wrong on-disk format. Scope: video native containers
              // + audio. Skip recoded-tier (existing recode-contract
              // guard handles those at datasource).
              final extMismatch = YtDlpDataSource.detectFinalExtensionMismatch(
                outputPath: finalOutputPath,
                videoFormat: videoFormat,
                audioFormat: audioFormat,
                extractAudio: extractAudio,
              );
              if (extMismatch != null) {
                appLogger.error(
                  '❌ [C3 fresh-path guard] expected .${extMismatch.expected} '
                  'but got .${extMismatch.actual} at $finalOutputPath. '
                  'Marking download failed instead of completing with '
                  'wrong container.',
                );
                await _repository.updateTempDirPath(download.id, null);
                await _repository.failDownload(
                  id: download.id,
                  errorMessage:
                      'Container mismatch — expected .${extMismatch.expected} '
                      'but output is .${extMismatch.actual}. The source may '
                      'not provide a ${extMismatch.expected}-native stream.',
                );
                return;
              }

              final actualFilename = p.basename(finalOutputPath);
              // Clear temp dir path — files have been moved to final location
              await _repository.updateTempDirPath(download.id, null);
              await _repository.completeDownload(
                id: download.id,
                totalBytes: fileSize,
                downloadedBytes: fileSize,
                filename:
                    actualFilename != download.filename ? actualFilename : null,
              );
              // Terminal commit reached — sentinel must flip BEFORE
              // the post-completion cleanup runs. After this point
              // the catch-all below will refuse to override status
              // even if the cleanup (or any future housekeeping
              // step) throws.
              downloadCommitted = true;

              // Post-success cleanup — DASH originals kept by
              // `--keep-video`. Wrapped here as defense-in-depth on
              // top of `_cleanupDashOriginals`'s own internal try/
              // catch: even if a future change to that helper drops
              // its swallow-error contract, this wrap guarantees a
              // completed download cannot be flipped to failed by a
              // cleanup throw.
              if (!extractAudio) {
                try {
                  await _cleanupDashOriginals(finalOutputPath);
                } catch (e) {
                  appLogger.debug(
                    '⚠️ DASH cleanup post-completion failure '
                    '(status already completed, ignoring): $e',
                  );
                }
              }
              return;
            } else if (wasCancelled) {
              // Clear temp dir path — temp dir deleted by datasource
              await _repository.updateTempDirPath(download.id, null);
              // An FFmpeg post-process timeout cancels the yt-dlp process via
              // cancelByDownloadId (above), surfacing as YtDlpDownloadCancelled
              // → wasCancelled=true. For VIDEO this is caught by the
              // `postProcessingTimedOut && !extractAudio` block above and
              // recorded as failed. For AUDIO extraction that block is skipped,
              // so without this guard an audio post-process timeout is
              // mislabelled "Cancelled" instead of "Failed" (the user-reported
              // "why is my failed download labelled Cancelled?"). Mirror the
              // retry-path fix (caff6f48): a timeout is a failure, not a cancel.
              if (postProcessingTimedOut) {
                await _repository.failDownload(
                  id: download.id,
                  errorMessage:
                      'ffmpegError:FFmpeg post-processing exceeded '
                      '${_formatDurationForLog(postProcessingTimeoutDuration)} '
                      'during audio extraction.',
                );
              } else {
                await _repository.updateDownloadStatus(
                  download.id,
                  DownloadStatus.cancelled,
                );
              }
              // Cancel is also a terminal commit — block the
              // catch-all from overriding it with `permissionDenied`
              // if a post-cancel housekeeping step throws.
              downloadCommitted = true;
              return;
            } else if (downloadError != null) {
              // Check if error is retryable
              final errorCode = DownloadErrorClassifier.classifyMessage(
                downloadError.message,
              );

              // Phase 2 fallback browser chain — Codex review
              // 2026-05-13. When the primary cookies are null AND
              // yt-dlp comes back with a recoverable auth/lock error,
              // iterate the chain (`localCookiesFromBrowserFallbackChain`)
              // before the older "drop cookies" branch. This closes the
              // gap where extract recovers via fallback browser X but
              // download was re-running with empty cookies and hard-
              // failing with loginRequired (production Windows log
              // 2026-05-12 §138 caught exactly this). cookieDbLocked
              // is the canonical signal to advance — the named browser
              // could not be read (yt-dlp issue 7271, Chrome running).
              final isCookieRecoverable =
                  errorCode == DownloadErrorCode.loginRequired ||
                  errorCode == DownloadErrorCode.cookieDbLocked ||
                  errorCode == DownloadErrorCode.formatUnavailable;

              // Codex review round 2: the original guard
              // (`localCookiesFromBrowser == null`) would only fire
              // for the FIRST chain attempt, because after we set
              // `localCookiesFromBrowser = candidate` the next
              // failure pass saw a non-null value and bailed out of
              // the chain. Gate on "either Settings hasn't supplied
              // explicit cookies OR we're already in chain mode
              // (cursor > 0)" so a locked Chrome → Edge advance
              // → Edge logged-out → Firefox advance actually
              // happens.
              final isStillExploringChain =
                  fallbackChainCursor <
                  localCookiesFromBrowserFallbackChain.length;
              final canEnterOrContinueChain =
                  cookiesFromBrowser == null || fallbackChainCursor > 0;
              if (isCookieRecoverable &&
                  isStillExploringChain &&
                  canEnterOrContinueChain) {
                final candidate =
                    localCookiesFromBrowserFallbackChain[fallbackChainCursor];
                fallbackChainCursor++;
                appLogger.warning(
                  '⚠️ [yt-dlp] Download ${errorCode.name} — '
                  'retrying with cookies-from-browser=$candidate '
                  '(chain $fallbackChainCursor/'
                  '${localCookiesFromBrowserFallbackChain.length}).',
                );
                localCookiesFromBrowser = candidate;
                await _repository.updateDownloadStatus(
                  download.id,
                  DownloadStatus.downloading,
                );
                continue; // Restart loop with new browser cookies.
              }

              // Cookie-retry path. This intentionally diverges from
              // extraction's retry-without-cookies policy: download-stage
              // YouTube 403 can be a mid-session GVS/cookie-binding problem,
              // not an extract-stage auth gate. Drop cookies once to restore
              // the main-compatible public path. If that retry only produces
              // a loginRequired artifact, preserve the original 403 below so
              // the UI does not enter a useless re-login loop.
              final hasCookies =
                  localCookiesFile != null ||
                  (localCookiesFromBrowser != null &&
                      localCookiesFromBrowser!.isNotEmpty);
              if (_shouldRetryWithoutCookiesAfterDownloadError(
                    errorCode: errorCode,
                    platformString: platformString,
                  ) &&
                  hasCookies &&
                  !cookieRetryAttempted) {
                appLogger.warning(
                  '⚠️ [yt-dlp] Download failed with ${errorCode.name} + '
                  'cookies present. Cookies may be bad/expired — '
                  'retrying WITHOUT cookies once.',
                );
                cookieRetryAttempted = true;
                cookieRetryOriginalErrorCode = errorCode;
                cookieRetryOriginalErrorMessage = downloadError.message;
                cookieRetryOriginalMetadata = downloadError.metadata;
                localCookiesFile = null;
                localCookiesFromBrowser = null;
                await _repository.updateDownloadStatus(
                  download.id,
                  DownloadStatus.downloading,
                );
                continue; // Restart the stream loop without cookies.
              }

              appRetryCount++;

              if (errorCode.isRetryable && appRetryCount <= maxAppRetries) {
                // Exponential backoff: 2s, 4s, 8s
                final backoffSeconds = 1 << appRetryCount; // 2, 4, 8
                appLogger.info(
                  '🔄 [yt-dlp] Retryable error (${errorCode.name}) — '
                  'retrying in ${backoffSeconds}s (attempt $appRetryCount/$maxAppRetries)',
                );
                await Future.delayed(Duration(seconds: backoffSeconds));
                // Reset status to downloading for retry
                await _repository.updateDownloadStatus(
                  download.id,
                  DownloadStatus.downloading,
                );
                continue; // Restart the stream loop
              }

              // Non-retryable or retries exhausted
              final preserveCookieRetryOriginal =
                  cookieRetryOriginalErrorCode != null &&
                  _shouldPreserveCookieRetryOriginalError(
                    originalErrorCode: cookieRetryOriginalErrorCode,
                    retryErrorCode: errorCode,
                  );
              final effectiveErrorCode =
                  preserveCookieRetryOriginal
                      ? cookieRetryOriginalErrorCode
                      : errorCode;
              final effectiveErrorMessage =
                  preserveCookieRetryOriginal
                      ? cookieRetryOriginalErrorMessage ?? downloadError.message
                      : downloadError.message;
              final effectiveYtdlpMetadata =
                  preserveCookieRetryOriginal
                      ? cookieRetryOriginalMetadata ?? downloadError.metadata
                      : downloadError.metadata;
              if (preserveCookieRetryOriginal) {
                appLogger.info(
                  '📌 [yt-dlp] Cookie-drop retry escalated '
                  '${cookieRetryOriginalErrorCode.name} → ${errorCode.name}. '
                  'Surfacing original ${effectiveErrorCode.name} to avoid '
                  'login-loop artifact.',
                );
              }
              _emitDownloadFailureTelemetry(
                download: download,
                errorCode: effectiveErrorCode,
                errorMessage: effectiveErrorMessage,
                ytdlpMetadata: effectiveYtdlpMetadata,
                cookiesFile: localCookiesFile,
                cookiesFromBrowser: localCookiesFromBrowser,
                fallbackChainCursor: fallbackChainCursor,
                fallbackChainLength:
                    localCookiesFromBrowserFallbackChain.length,
                cookieRetryAttempted: cookieRetryAttempted,
                appRetryCount: appRetryCount,
              );
              await _repository.failDownload(
                id: download.id,
                errorMessage: effectiveErrorMessage,
              );
              return;
            } else {
              await _repository.failDownload(
                id: download.id,
                errorMessage: 'Download ended unexpectedly',
              );
              return;
            }
          }
        } catch (e, stack) {
          // Sentinel gate: if a terminal repository commit
          // (completeDownload / cancelled) already ran, the user's
          // status is already correct. A post-commit throw — from
          // best-effort cleanup, a stale stream subscription, a
          // logger sink, etc. — must NOT be allowed to flip that
          // status to `permissionDenied` / `failDownload`. Pre-fix
          // a single `Directory.list()` TCC denial in DASH cleanup
          // was enough to mark a successfully-downloaded file as
          // failed on the user's screen (log.md 2026-05-12 §517).
          if (downloadCommitted) {
            appLogger.warning(
              '⚠️ [yt-dlp] Post-completion error after terminal '
              'commit — keeping committed status: $e',
            );
            return;
          }
          appLogger.error('❌ [yt-dlp] Background monitoring failed', e, stack);
          await _repository.failDownload(
            id: download.id,
            errorMessage:
                'yt-dlp download failed: ${AppExceptionX.readableMessage(e)}',
          );
        }
      }());

      return Result.success(download);
    } catch (e, stack) {
      appLogger.error('❌ [yt-dlp] Download failed', e, stack);
      return Result.failure(
        AppException.download(
          message:
              'yt-dlp download failed: ${AppExceptionX.readableMessage(e)}',
        ),
      );
    }
  }

  /// Find DASH original files kept by --keep-video flag.
  ///
  /// yt-dlp names intermediates as: `{title}.f{formatId}.{ext}`
  /// e.g. "My Video.f137.mp4" (video), "My Video.f140.m4a" (audio)
  ///
  /// Exposed for testing via [findDashOriginalsForTest].
  static Future<List<File>> findDashOriginalsForTest(
    String outputDir,
    String filenameWithoutExt,
  ) => StartDownloadUseCase._findDashOriginalsStatic(
    outputDir,
    filenameWithoutExt,
  );

  Future<List<File>> _findDashOriginals(
    String outputDir,
    String filenameWithoutExt,
  ) => _findDashOriginalsStatic(outputDir, filenameWithoutExt);

  static Future<List<File>> _findDashOriginalsStatic(
    String outputDir,
    String filenameWithoutExt,
  ) async {
    final dir = Directory(outputDir);
    if (!await dir.exists()) return [];

    final originals = <File>[];
    // Match yt-dlp's DASH intermediate filenames per the canonical
    // pattern (mirrors `ytdlp_datasource._intermediateFormatFileRegex`).
    // The legacy `\.f\d+\.\w+\$` only matched YouTube classic
    // (`.f137.mp4`) and missed Facebook's `[va]?` suffix
    // (`.f<id>v.mp4`, `.f<id>a.m4a`) and Twitter/X HLS ids
    // (`.fhls-audio-128000-Audio.mp4`, `.fdash-video.mp4`), so orphan video-only /
    // audio-only intermediates could leak or be picked as final output.
    // Update keeps backwards-compat with YouTube + closes Facebook/Twitter/Reddit-style protocol ids.
    final pattern = RegExp(
      '^${RegExp.escape(filenameWithoutExt)}'
      r'\.(?:f\d+(?:-\d+)?[va]?|f(?:hls|dash|https?)-[^./\\]+)\.\w+$',
    );

    await for (final entity in dir.list()) {
      if (entity is File && pattern.hasMatch(p.basename(entity.path))) {
        originals.add(entity);
      }
    }
    return originals;
  }

  /// Scan output directory for the most recently modified file matching [extension].
  /// Used as fallback when yt-dlp stdout filename is corrupted by encoding mismatch
  /// (Windows cp1252 vs UTF-8) but the actual file on disk has the correct name.
  /// Excludes DASH originals (.f{id}[v|a].ext pattern) to avoid false matches.
  static Future<File?> _findRecentOutputFile(
    String outputDir,
    String extension,
  ) async {
    final dir = Directory(outputDir);
    if (!await dir.exists()) return null;

    final now = DateTime.now();
    final dashPattern = RegExp(
      r'\.(?:f\d+(?:-\d+)?[va]?|f(?:hls|dash|https?)-[^./\\]+)\.[^./\\]+$',
    );
    File? bestMatch;
    DateTime? bestTime;

    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      // Skip DASH/HLS originals (e.g., "Video.f137.mp4",
      // "Video.f123v.mp4", "Video.fhls-audio-128000-Audio.mp4").
      if (dashPattern.hasMatch(name)) continue;
      // Match extension
      if (p.extension(name).toLowerCase() != extension) continue;
      final stat = await entity.stat();
      // Only consider files modified within the last 5 minutes
      if (now.difference(stat.modified).inMinutes > 5) continue;
      if (stat.size == 0) continue;
      if (bestTime == null || stat.modified.isAfter(bestTime)) {
        bestMatch = entity;
        bestTime = stat.modified;
      }
    }
    return bestMatch;
  }

  /// Retry DASH merge using FFmpeg directly with stream copy (-c copy).
  ///
  /// Called when yt-dlp's merge fails (empty/missing output) but originals
  /// still exist (thanks to --keep-video). Max 1 retry attempt.
  /// Returns null if retry is not possible (no originals, no FFmpeg).
  Future<Result<DownloadEntity>?> _retryMergeWithFFmpeg({
    required String outputDir,
    required String filenameWithoutExt,
    required String targetExt,
    required int downloadId,
  }) async {
    final originals = await _findDashOriginals(outputDir, filenameWithoutExt);
    if (originals.length < 2) {
      appLogger.info(
        '⚠️ [FFmpeg] Cannot retry merge — found ${originals.length} original(s)',
      );
      return null;
    }

    final ffmpegPath = _ytdlpDataSource.ffmpegPath;
    if (ffmpegPath == null) {
      appLogger.info('⚠️ [FFmpeg] Cannot retry merge — FFmpeg not available');
      return null;
    }

    appLogger.info(
      '🔄 [FFmpeg] Retrying merge with ${originals.length} originals...',
    );

    final outputPath = p.join(outputDir, '$filenameWithoutExt.$targetExt');

    // Delete failed output if it exists
    final failedOutput = File(outputPath);
    if (await failedOutput.exists()) {
      await failedOutput.delete();
    }

    // Build FFmpeg command: -i video -i audio -c copy -y output
    final args = <String>[];
    for (final original in originals) {
      args.addAll(['-i', original.path]);
    }
    args.addAll(['-c', 'copy', '-y', outputPath]);

    try {
      final process = await ProcessHelper.start(ffmpegPath, args);
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 300),
        onTimeout: () {
          process.kill(ProcessSignal.sigterm);
          return -1;
        },
      );

      if (exitCode == 0) {
        final mergedFile = File(outputPath);
        final mergedSize =
            await mergedFile.exists() ? await mergedFile.length() : 0;

        if (mergedSize > 0) {
          appLogger.info(
            '✅ [FFmpeg] Retry merge succeeded! ($mergedSize bytes)',
          );

          // Cleanup originals
          for (final original in originals) {
            try {
              await original.delete();
            } catch (_) {}
          }

          // F1.1: integrity check on merged output
          final integrityResult = await _fileIntegrityService?.verifyFile(
            outputPath,
          );
          if (integrityResult != null && !integrityResult.isValid) {
            appLogger.error(
              '❌ [FileIntegrity] Merged output failed integrity: ${integrityResult.reason}',
            );
            await _repository.failDownload(
              id: downloadId,
              errorMessage:
                  integrityResult.reason ?? 'File integrity check failed',
            );
            return Result.failure(
              AppException.download(
                message:
                    integrityResult.reason ?? 'File integrity check failed',
              ),
            );
          }

          await _repository.completeDownload(
            id: downloadId,
            totalBytes: mergedSize,
            downloadedBytes: mergedSize,
          );
          return _repository.getDownloadById(downloadId);
        }
      }

      appLogger.error('❌ [FFmpeg] Retry merge failed (exit code: $exitCode)');
      return null;
    } catch (e) {
      appLogger.error('❌ [FFmpeg] Retry merge exception: $e');
      return null;
    }
  }

  /// Cleanup DASH original files after successful merge validation.
  /// Test-only shim around the private `_cleanupDashOriginals` so
  /// regression tests can pin the "never throws on filesystem
  /// failure" contract without going through the full stream-flow
  /// orchestration.
  @visibleForTesting
  Future<void> cleanupDashOriginalsForTesting(String outputPath) =>
      _cleanupDashOriginals(outputPath);

  /// Post-success housekeeping — best-effort delete of the DASH
  /// originals kept by `--keep-video`. Must NEVER throw: this runs
  /// after the file is on disk and the user's status is already
  /// "completed", so any filesystem hiccup (TCC permission denied
  /// on `~/Downloads` in dev builds, antivirus lock, mounted
  /// network drive disconnect) must NOT bubble up to the
  /// background-monitoring catch-all and flip the status to
  /// `permissionDenied`. Pre-fix this method's `_findDashOriginals`
  /// call would throw `PathAccessException` from `Directory.list()`
  /// → catch-all wrapping the whole stream loop would stamp
  /// `failDownload` on top of a successfully-downloaded file
  /// (cf. log.md 2026-05-12 line 517–522: yt-dlp exit 0 + Completed
  /// log + permissionDenied stamp on the same file).
  Future<void> _cleanupDashOriginals(String outputPath) async {
    final dir = p.dirname(outputPath);
    final baseName = p.basenameWithoutExtension(outputPath);
    List<File> originals;
    try {
      originals = await _findDashOriginals(dir, baseName);
    } catch (e) {
      // Directory listing failure (TCC, antivirus, disconnected
      // drive) — cleanup is best-effort, so swallow.
      appLogger.debug('⚠️ DASH originals scan skipped (non-fatal): $e');
      return;
    }
    for (final original in originals) {
      try {
        await original.delete();
        appLogger.debug(
          '🗑️ Cleaned up DASH original: ${p.basename(original.path)}',
        );
      } catch (e) {
        appLogger.debug(
          '⚠️ Failed to cleanup: ${p.basename(original.path)} — $e',
        );
      }
    }
  }

  /// Download subtitle file only using yt-dlp --write-sub --skip-download.
  ///
  /// Handles both original and auto-generated subtitles:
  /// - 'ytdlp:subtitle:en' → original English subtitle
  /// - 'ytdlp:subtitle:auto:vi' → auto-generated Vietnamese subtitle
  Future<Result<DownloadEntity>> _downloadSubtitleOnly({
    required String url,
    required String savePath,
    required String videoTitle,
    String? thumbnail,
    required String qualityKey,
    required String qualityLabel,
    String? cookiesFile,
    String? cookiesFromBrowser,
    String? uploader,
    String subtitlesFormat = 'srt',
  }) async {
    try {
      appLogger.info('📝 [yt-dlp] Starting subtitle-only download...');

      // Parse language from key: 'ytdlp:subtitle:en' or 'ytdlp:subtitle:auto:vi'
      final parts = qualityKey.split(':');
      final isAuto = parts.length >= 4 && parts[2] == 'auto';
      final lang = isAuto ? parts[3] : parts[2];

      final extension = subtitlesFormat;
      var filename = FileUtils.sanitizeFilename('$videoTitle.$lang');
      if (!filename.endsWith('.$extension')) {
        filename = '$filename.$extension';
      }
      // WIN-1/DL-007: same full-path budget as the main download path — a long
      // title + `.<lang>.srt` in a deep folder otherwise overflows MAX_PATH.
      final boundedSubFilename = FileUtils.boundFilenameToPathLimit(
        fileName: filename,
        candidateDirs: [savePath, YtDlpDataSource.worstCaseIsolatedTempDir()],
        maxPathUnits: Platform.isWindows ? FileUtils.windowsMaxPathUnits : null,
      );
      if (boundedSubFilename == null) {
        return Result.failure(
          const AppException.download(
            message:
                'The save folder path is too long for Windows (260-character '
                'limit). Choose a shorter folder, or move it closer to the '
                'drive root, then try again.',
          ),
        );
      }
      filename = boundedSubFilename;
      filename = await FileUtils.getUniqueFilename(savePath, filename);

      final detectedPlatform = PlatformDetector.detectPlatform(url);
      final platformString = detectedPlatform.toDbString();

      // Create download record
      final createResult = await _repository.createDownload(
        url: url,
        filename: filename,
        savePath: savePath,
        thumbnail: thumbnail,
        platform: platformString,
        downloadMethod: 'ytdlp',
        title: '$videoTitle ($lang subtitle)',
        uploader: uploader,
        qualityLabel: qualityLabel,
      );

      if (createResult.isFailure) return createResult;
      final download = createResult.dataOrThrow;

      await _repository.updateDownloadStatus(
        download.id,
        DownloadStatus.downloading,
      );

      // Capture shared state into local
      final localCookiesFromBrowser = cookiesFromBrowser;

      // Fire-and-forget: monitoring runs in background
      unawaited(() async {
        try {
          // Use yt-dlp to download subtitle only
          final progressStream = _ytdlpDataSource.downloadWithProgress(
            url: url,
            outputDir: savePath,
            downloadId: download.id,
            outputTemplate: filename.replaceAll('.$extension', '.%(ext)s'),
            cookiesFromBrowser: localCookiesFromBrowser,
            subtitlesEnabled: true,
            subtitlesLanguages: [lang],
            subtitlesFormat: subtitlesFormat,
            includeAutoSubs: isAuto,
            skipDownload: true,
            onTempDirCreated: (tempDir) {
              _repository.updateTempDirPath(download.id, tempDir);
            },
          );

          String? finalOutputPath;
          YtDlpException? downloadError;
          bool wasCancelled = false;

          await for (final event in progressStream) {
            switch (event) {
              case YtDlpProgressUpdate():
                break; // Subtitle downloads have minimal progress
              case YtDlpDownloadComplete(:final outputPath):
                finalOutputPath = outputPath;
                appLogger.info('✅ [yt-dlp] Subtitle downloaded: $outputPath');
              case YtDlpDownloadError(:final error):
                downloadError = error;
                appLogger.error('❌ [yt-dlp] Subtitle error: ${error.message}');
              case YtDlpDownloadCancelled():
                wasCancelled = true;
            }
          }

          if (finalOutputPath != null) {
            final outputFile = File(finalOutputPath);
            final fileExists = await outputFile.exists();
            final fileSize = fileExists ? await outputFile.length() : 0;

            if (!fileExists || fileSize == 0) {
              // Try to find the subtitle file in the output directory
              final dir = Directory(savePath);
              final subtitleFiles =
                  await dir
                      .list()
                      .where(
                        (f) =>
                            f.path.contains(lang) &&
                            f.path.endsWith('.$extension'),
                      )
                      .toList();
              if (subtitleFiles.isNotEmpty) {
                finalOutputPath = subtitleFiles.first.path;
                final size = await File(finalOutputPath).length();
                await _repository.completeDownload(
                  id: download.id,
                  totalBytes: size,
                  downloadedBytes: size,
                );
                return;
              }

              await _repository.failDownload(
                id: download.id,
                errorMessage: 'Subtitle file not found after download',
              );
              return;
            }

            await _repository.completeDownload(
              id: download.id,
              totalBytes: fileSize,
              downloadedBytes: fileSize,
            );
            return;
          } else if (wasCancelled) {
            await _repository.updateDownloadStatus(
              download.id,
              DownloadStatus.cancelled,
            );
            return;
          } else if (downloadError != null) {
            await _repository.failDownload(
              id: download.id,
              errorMessage: downloadError.message,
            );
            return;
          } else {
            await _repository.failDownload(
              id: download.id,
              errorMessage: 'Subtitle download ended unexpectedly',
            );
            return;
          }
        } catch (e, stack) {
          appLogger.error(
            '❌ [yt-dlp] Subtitle background monitoring failed',
            e,
            stack,
          );
          await _repository.failDownload(
            id: download.id,
            errorMessage:
                'Subtitle download failed: ${AppExceptionX.readableMessage(e)}',
          );
        }
      }());

      return Result.success(download);
    } catch (e, stack) {
      appLogger.error('❌ [yt-dlp] Subtitle download failed', e, stack);
      return Result.failure(
        AppException.download(
          message:
              'Subtitle download failed: ${AppExceptionX.readableMessage(e)}',
        ),
      );
    }
  }

  String _formatSpeed(double? bytesPerSecond) {
    if (bytesPerSecond == null || bytesPerSecond <= 0) return '0 B/s';
    if (bytesPerSecond < 1024) return '${bytesPerSecond.round()} B/s';
    if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  // ==================== Gallery-dl Download ====================

  /// Parse gallery-dl range from quality key.
  /// 'gallerydl:1' → '1', 'gallerydl:all:7' → null (download everything)
  String? _parseGalleryDlRange(String qualityKey) {
    final parts = qualityKey.split(':');
    if (parts.length < 2) return null;
    return (parts[1] == 'all' || parts[1] == 'all_videos') ? null : parts[1];
  }

  /// Check if quality key is "All N videos" mode
  bool _isGalleryDlAllVideos(String qualityKey) {
    return qualityKey.startsWith('gallerydl:all_videos:');
  }

  /// Build descriptive filename base for gallery-dl downloads.
  /// Uses platform_uploader_postId pattern instead of generic "Image".
  String _buildGalleryDlFilenameBase(
    String url,
    String? uploader,
    String platform,
  ) {
    final postId = _extractPostId(url);
    final user = uploader ?? platform;
    final base = '${platform}_$user${postId.isNotEmpty ? '_$postId' : ''}';
    final sanitized = FileUtils.sanitizeFilename(base);
    return sanitized.isEmpty ? 'image' : sanitized;
  }

  /// Extract post ID from URL (last path segment, truncated if too long).
  String _extractPostId(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return '';
    final lastSegment = segments.last;
    // Truncate very long IDs (TikTok IDs can be 19+ digits)
    return lastSegment.length > 20 ? lastSegment.substring(0, 20) : lastSegment;
  }

  /// Download images using gallery-dl subprocess.
  ///
  /// Key design: gallery-dl runs ONCE (efficient single subprocess), then
  /// we create N separate download records from the output files.
  /// Each file = 1 DB record = proper file tracking + existence validation.
  Future<Result<DownloadEntity>> _downloadWithGalleryDl({
    required String url,
    required String savePath,
    required String videoTitle,
    String? thumbnail,
    String? range,
    String? cookiesFile,
    String? uploader,
    String? qualityLabel,
    String? platform,
    String? qualityKey,
  }) async {
    try {
      appLogger.info('🖼️ [gallery-dl] Starting image download...');

      final platformString =
          platform ?? PlatformDetector.detectPlatform(url).toDbString();
      final filenameBase = _buildGalleryDlFilenameBase(
        url,
        uploader,
        platformString,
      );
      // Append range index to avoid filename collision when downloading multiple items from same URL
      final effectiveFilename =
          range != null ? '${filenameBase}_v$range' : filenameBase;
      final isAllMode = range == null; // null range = download all items

      // Create placeholder record (shows "downloading" in UI)
      final placeholderFilename = '$effectiveFilename.jpg';
      final createResult = await _repository.createDownload(
        url: url,
        filename: placeholderFilename,
        savePath: savePath,
        thumbnail: thumbnail,
        platform: platformString,
        downloadMethod: 'gallerydl',
        title: videoTitle,
        uploader: uploader,
        qualityLabel: qualityLabel,
      );

      if (createResult.isFailure) return createResult;
      final placeholder = createResult.dataOrThrow;

      await _repository.updateDownloadStatus(
        placeholder.id,
        DownloadStatus.downloading,
      );

      // Fire-and-forget: monitoring runs in background
      unawaited(() async {
        try {
          // Determine expected item count from quality key for filename numbering
          final expectedCount =
              isAllMode ? 2 : 1; // 2+ triggers numbered naming in datasource

          // Run gallery-dl subprocess
          final progressStream = _galleryDlDataSource.downloadWithProgress(
            url: url,
            outputDir: savePath,
            outputFilename: effectiveFilename,
            range: range,
            cookiesFile: cookiesFile,
            expectedItemCount: expectedCount,
            imageOnly:
                isAllMode &&
                !(qualityKey != null && _isGalleryDlAllVideos(qualityKey)),
            videoOnly: qualityKey != null && _isGalleryDlAllVideos(qualityKey),
            ffmpegPath: _ytdlpDataSource.ffmpegPath,
          );

          String? lastError;
          List<String>? completedPaths;
          bool wasCancelled = false;

          await for (final event in progressStream) {
            switch (event) {
              case GalleryDlProgressUpdate(:final percent, :final currentFile):
                appLogger.debug(
                  '[gallery-dl] Progress: ${(percent * 100).round()}% ${currentFile ?? ''}',
                );
              case GalleryDlDownloadComplete(:final outputPaths):
                completedPaths = outputPaths;
              case GalleryDlDownloadError(:final message):
                lastError = message;
              case GalleryDlDownloadCancelled():
                wasCancelled = true;
            }
          }

          // Handle errors and cancellation
          if (wasCancelled) {
            await _repository.updateDownloadStatus(
              placeholder.id,
              DownloadStatus.cancelled,
            );
            return;
          }

          if (completedPaths == null || completedPaths.isEmpty) {
            await _repository.failDownload(
              id: placeholder.id,
              errorMessage: lastError ?? 'No files downloaded',
            );
            return;
          }

          // Validate downloaded files
          final validFiles = <({String path, int size})>[];
          for (final filePath in completedPaths) {
            final file = File(filePath);
            if (await file.exists()) {
              final size = await file.length();
              if (size > 0) {
                validFiles.add((path: filePath, size: size));
              }
            }
          }

          if (validFiles.isEmpty) {
            await _repository.failDownload(
              id: placeholder.id,
              errorMessage: 'Downloaded files missing or empty',
            );
            return;
          }

          appLogger.info(
            '✅ [gallery-dl] Downloaded ${validFiles.length} files '
            '(${FileUtils.formatBytes(validFiles.fold(0, (sum, f) => sum + f.size))})',
          );

          // Single file — just update the placeholder record
          if (validFiles.length == 1) {
            final actualFilename = p.basename(validFiles.first.path);
            final fileSize = validFiles.first.size;

            // Delete placeholder, create final record with correct filename
            await _repository.deleteDownload(placeholder.id);

            final finalResult = await _repository.createDownload(
              url: url,
              filename: actualFilename,
              savePath: savePath,
              thumbnail: thumbnail,
              platform: platformString,
              downloadMethod: 'gallerydl',
              title: videoTitle,
              uploader: uploader,
              qualityLabel: qualityLabel,
            );

            if (finalResult.isFailure) return;
            final finalRecord = finalResult.dataOrThrow;

            await _repository.completeDownload(
              id: finalRecord.id,
              totalBytes: fileSize,
              downloadedBytes: fileSize,
            );
            return;
          }

          // Multiple files — delete placeholder, create N separate records
          await _repository.deleteDownload(placeholder.id);

          for (var i = 0; i < validFiles.length; i++) {
            final file = validFiles[i];
            final actualFilename = p.basename(file.path);
            final itemTitle = '$videoTitle (${i + 1}/${validFiles.length})';

            final recordResult = await _repository.createDownload(
              url: url,
              filename: actualFilename,
              savePath: savePath,
              thumbnail: thumbnail,
              platform: platformString,
              downloadMethod: 'gallerydl',
              title: itemTitle,
              uploader: uploader,
              qualityLabel: '${i + 1}/${validFiles.length}',
            );

            if (recordResult.isFailure) continue;
            final record = recordResult.dataOrThrow;

            await _repository.completeDownload(
              id: record.id,
              totalBytes: file.size,
              downloadedBytes: file.size,
            );
          }
        } catch (e, stack) {
          appLogger.error(
            '❌ [gallery-dl] Background monitoring failed',
            e,
            stack,
          );
          await _repository.failDownload(
            id: placeholder.id,
            errorMessage:
                'Image download failed: ${AppExceptionX.readableMessage(e)}',
          );
        }
      }());

      return Result.success(placeholder);
    } catch (e, stack) {
      appLogger.error('❌ [gallery-dl] Download failed', e, stack);
      return Result.failure(
        AppException.download(
          message: 'Image download failed: ${AppExceptionX.readableMessage(e)}',
        ),
      );
    }
  }

  /// Detect if a path is inside a cloud sync folder.
  /// Returns the service name if detected, null otherwise.
  static String? _detectCloudSyncFolder(String folderPath) {
    final lower = folderPath.toLowerCase().replaceAll(r'\', '/');
    if (lower.contains('/dropbox/')) return 'Dropbox';
    if (lower.contains('/onedrive/') || lower.contains('/onedrive -')) {
      return 'OneDrive';
    }
    if (lower.contains('/google drive/') || lower.contains('/my drive/')) {
      return 'Google Drive';
    }
    if (lower.contains('/icloud drive/') ||
        lower.contains('/mobile documents/')) {
      return 'iCloud Drive';
    }
    if (lower.contains('/mega/')) return 'MEGA';
    if (lower.contains('/box sync/') || lower.contains('/box/')) return 'Box';
    return null;
  }
}

/// Result shape for the Facebook progressive single-file fallback.
/// Pure value type (no behavior) so the fallback transform is
/// testable in isolation without spinning up the full download
/// usecase. Defined at library level so it's importable from tests.
class FacebookProgressiveFallbackResult {
  final String format;
  final String? sortOptions;
  final String? mergeFormatPriority;
  final String? remuxVideo;
  final String? recodeVideo;

  const FacebookProgressiveFallbackResult({
    required this.format,
    required this.sortOptions,
    required this.mergeFormatPriority,
    required this.remuxVideo,
    required this.recodeVideo,
  });
}
