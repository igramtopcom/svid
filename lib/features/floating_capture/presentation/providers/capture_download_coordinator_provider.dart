import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/config/brand_config.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/providers/proxy_rotation_provider.dart';
import '../../../../core/utils/file_utils.dart';
import '../../../../core/utils/platform_detector.dart';
import '../../../../core/utils/validators.dart';
import '../../../downloads/domain/entities/download_config.dart';
import '../../../downloads/domain/entities/download_entity.dart';
import '../../../downloads/domain/entities/download_error_code.dart';
import '../../../downloads/domain/entities/download_status.dart';
import '../../../downloads/domain/entities/video_info.dart';
import '../../../downloads/domain/services/adaptive_segment_service.dart';
import '../../../downloads/domain/services/download_error_classifier.dart';
import '../../../downloads/domain/services/download_intent_key.dart';
import '../../../downloads/domain/services/gallery_default_quality_selector.dart';
import '../../../downloads/domain/services/network_throughput_monitor.dart';
import '../../../downloads/presentation/providers/download_path_suggestion_provider.dart';
import '../../../downloads/presentation/providers/download_providers.dart';
import '../../../downloads/presentation/providers/downloads_notifier.dart';
import '../../../downloads/presentation/providers/extraction_cache_provider.dart';
import '../../../premium/presentation/providers/premium_providers.dart';
import '../../../settings/domain/entities/format_preset_extended.dart';
import '../../../settings/domain/entities/platform_quality_preference.dart';
import '../../../settings/domain/enums/audio_codec_preference.dart';
import '../../../settings/domain/enums/container_format_preference.dart';
import '../../../settings/domain/enums/fps_preference.dart';
import '../../../settings/domain/enums/video_codec_preference.dart';
import '../../../settings/domain/services/preset_quality_matcher.dart';
import '../../../settings/presentation/providers/active_preset_provider.dart';
import '../../../settings/presentation/providers/platform_preferences_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/capture_download_request.dart';
import '../../domain/entities/popup_action_result.dart';
import 'floating_capture_providers.dart';

final captureDownloadCoordinatorProvider = Provider<CaptureDownloadCoordinator>(
  CaptureDownloadCoordinator.new,
);

class CaptureDownloadCoordinator {
  CaptureDownloadCoordinator(this._ref);

  final Ref _ref;
  final Map<int, DateTime> _popupOriginatedDownloadIds = {};
  bool _startingDirectDownload = false;

  static const Duration _popupCompletionTtl = Duration(minutes: 30);

  /// Starts a popup primary-action download without depending on HomeScreen.
  ///
  /// Returns false when the request needs UI fallback (advanced dialog /
  /// manual-mode path). In that case the root scaffold restores the app and
  /// delegates to HomeScreen.
  Future<bool> tryStartDirectDownload(CaptureDownloadRequest request) async {
    if (_startingDirectDownload) {
      await _emitActionResult(
        const PopupActionFailed('Another download is already starting.'),
      );
      return true;
    }

    final url = request.preview.rawUrl.trim();
    if (!Validators.isDownloadableUrl(url)) {
      await _emitActionResult(const PopupActionFailed('Invalid download URL.'));
      return true;
    }

    _startingDirectDownload = true;
    try {
      appLogger.info('[Capture] background direct download requested: $url');

      final videoInfoResult = await _resolveVideoInfo(url);
      final videoInfo = videoInfoResult.dataOrNull;
      if (videoInfo == null) {
        await _emitFailure(videoInfoResult.exceptionOrNull);
        return true;
      }

      final selection = _selectDownload(videoInfo);
      if (selection == null) {
        appLogger.info(
          '[Capture] direct download needs UI fallback: ${videoInfo.url}',
        );
        return false;
      }

      final startTuple = await _startSelectedDownload(videoInfo, selection);
      final download = startTuple.result.dataOrNull;
      if (download == null) {
        await _emitFailure(startTuple.result.exceptionOrNull);
        return true;
      }

      _popupOriginatedDownloadIds[download.id] = DateTime.now();
      // Codex audit fix: surface the container-recode notice that the
      // planner emitted (e.g. "MP4 at 4K — Opus audio will be
      // re-encoded to AAC"). Previously this was logged but never
      // shown to the user; now the popup's State 6 carries it.
      await _emitActionResult(
        PopupActionStarted(
          filename: download.filename,
          containerRecodeNotice: startTuple.containerRecodeNotice,
        ),
      );
      return true;
    } catch (e, s) {
      appLogger.error('[Capture] background direct download failed', e, s);
      await _emitActionResult(
        PopupActionFailed(AppExceptionX.readableMessage(e)),
      );
      return true;
    } finally {
      _startingDirectDownload = false;
    }
  }

  void handleDownloadsStateChange(
    DownloadsState? previous,
    DownloadsState next,
  ) {
    final now = DateTime.now();
    _popupOriginatedDownloadIds.removeWhere(
      (_, startedAt) => now.difference(startedAt) > _popupCompletionTtl,
    );
    if (_popupOriginatedDownloadIds.isEmpty) return;

    final previousById = <int, DownloadEntity>{
      for (final download in previous?.downloads ?? const <DownloadEntity>[])
        download.id: download,
    };

    for (final download in next.downloads) {
      if (!_popupOriginatedDownloadIds.containsKey(download.id)) continue;
      final previousDownload = previousById[download.id];

      if (download.status == DownloadStatus.completed &&
          previousDownload?.status != DownloadStatus.completed) {
        _popupOriginatedDownloadIds.remove(download.id);
        final savedFullPath = p.join(download.savePath, download.filename);
        unawaited(
          _emitActionResult(
            PopupActionCompleted(
              filename: download.filename,
              savedPath: savedFullPath,
            ),
          ),
        );
      }

      if (download.status == DownloadStatus.failed &&
          previousDownload?.status != DownloadStatus.failed) {
        _popupOriginatedDownloadIds.remove(download.id);
        final error = download.errorMessage ?? 'Download failed.';
        final code =
            download.errorCode ??
            DownloadErrorClassifier.classifyMessage(error);
        // RC8.5 of Ultra Plan v3 — carry the error code name into the
        // floating popup so it can render per-class CTA (retry /
        // cookies / open-app) instead of collapsing every non-auth
        // failure into a single "Open app for details" button.
        unawaited(
          _emitActionResult(
            code == DownloadErrorCode.loginRequired
                ? const PopupActionAuthRequired()
                : PopupActionFailed(
                  AppExceptionX.readableMessage(error),
                  errorCode: code.name,
                ),
          ),
        );
      }
    }
  }

  Future<Result<VideoInfo>> _resolveVideoInfo(String url) async {
    final cached = await _ref
        .read(extractionHistoryProvider.notifier)
        .getCachedAsync(url);
    if (cached != null) {
      appLogger.info('[Capture] using cached extraction for: ${cached.title}');
      return Result.success(cached);
    }

    final settings = _ref.read(settingsProvider);
    String? cookiesFile;
    try {
      cookiesFile = await _ref.read(cookiesFileForUrlProvider(url).future);
      if (cookiesFile != null) {
        appLogger.info('[Capture] cookies found for background extraction');
      }
    } catch (e) {
      appLogger.debug('[Capture] no cookies for background extraction: $e');
    }

    final result = await _ref.read(extractVideoInfoUseCaseProvider)(
      url,
      engine: settings.downloadEngine,
      cookiesFile: cookiesFile,
      cookiesFromBrowser:
          cookiesFile == null ? _ref.read(cookiesFromBrowserProvider) : null,
      cookiesFromBrowserFallback: _ref.read(cookiesFromBrowserFallbackProvider),
      cookiesFromBrowserFallbackChain: _ref.read(
        cookiesFromBrowserFallbackChainProvider,
      ),
      proxyUrl: _resolveActiveProxy(),
    );

    final videoInfo = result.dataOrNull;
    if (videoInfo != null) {
      await _ref
          .read(extractionHistoryProvider.notifier)
          .addExtraction(videoInfo.url, videoInfo);
    }
    return result;
  }

  _CaptureSelection? _selectDownload(VideoInfo videoInfo) {
    if (videoInfo.availableQualities.isEmpty) return null;

    if (videoInfo.availableQualities.length == 1) {
      return _CaptureSelection(videoInfo.availableQualities.first);
    }

    final allImagesQuality = GalleryDefaultQualitySelector.allImagesQuality(
      videoInfo,
    );
    if (allImagesQuality != null) return _CaptureSelection(allImagesQuality);

    final activePreset = _ref.read(activePresetProvider);
    final canAutoPick =
        !activePreset.useManualMode && _canApplySavedChoice(videoInfo);
    final platform = PlatformDetector.detectPlatform(videoInfo.url);

    if (canAutoPick) {
      final preset = activePreset.currentConfig;
      final outcome = PresetQualityMatcher.match(
        preset: preset,
        available: videoInfo.availableQualities,
        videoPlatform: platform,
        isPremium: _ref.read(isPremiumProvider),
      );
      switch (outcome) {
        case PresetMatched(quality: final matched):
          appLogger.info(
            '[Capture] background auto-pick via active preset '
            '"${activePreset.activePreset.name}" -> ${matched.qualityText}',
          );
          return _CaptureSelection(
            matched,
            config: _buildConfigFromPreset(preset, matched),
            basePathOverride: preset.saveLocation,
          );
        case PresetBlocked():
          return null;
        case PresetScopeMismatch():
        case PresetNoCandidate():
          break;
      }
    }

    final savedPref =
        canAutoPick
            ? _ref
                .read(platformPreferencesProvider.notifier)
                .getPreference(platform)
            : null;
    if (savedPref == null) return null;

    final matchingQuality = videoInfo.availableQualities.firstWhere(
      (q) =>
          q.qualityText == savedPref.qualityText &&
          q.mediaType == savedPref.mediaType,
      orElse: () => videoInfo.availableQualities.first,
    );
    return _CaptureSelection(
      matchingQuality,
      config: _buildConfigFromPreference(savedPref, matchingQuality),
    );
  }

  Future<({Result<DownloadEntity> result, String? containerRecodeNotice})>
  _startSelectedDownload(
    VideoInfo videoInfo,
    _CaptureSelection selection,
  ) async {
    final settings = _ref.read(settingsProvider);
    final quality = selection.quality;

    // 2026-05-26 Codex spec — duplicate hard-fail removed from
    // Floating Capture path to match the Home behavior. Previously
    // a duplicate intent threw `AppException.download` with a "đã
    // tải rồi" message, blocking the user mid-popup. New contract:
    // floating capture proceeds with the download; the datasource's
    // `_moveFilesToOutputDir` applies a shared ` (N)` suffix when
    // the destination exists, so no file gets overwritten and no
    // duplicate is silently skipped. The `_findQualityDuplicate`
    // helper was also removed (no caller left after the gate was
    // dropped); see deletion below. Archive Mode is still an
    // explicit opt-in via `settings.archiveEnabled` (yt-dlp's own
    // `--download-archive`).
    //
    // Note on capture-layer anti-spam: the upstream clipboard /
    // popup pipeline in `default_capture_service.dart` keeps its
    // own per-URL cooldown to dedupe rapid clipboard polls. That
    // anti-spam is independent of the duplicate-download gate
    // removed here — rapid copies of the same URL may still be
    // collapsed by the capture layer before reaching this
    // coordinator. Comment is honest about scope.

    final pathService = _ref.read(downloadPathSuggestionServiceProvider);
    final platform = PlatformDetector.detectPlatform(videoInfo.url);
    final settingsPath = _ref.read(downloadPathProvider);
    final basePath =
        (selection.basePathOverride != null &&
                selection.basePathOverride!.isNotEmpty)
            ? selection.basePathOverride!
            : (settingsPath.isNotEmpty
                ? settingsPath
                : (await getDownloadsDirectory())?.path ??
                    (await getApplicationDocumentsDirectory()).path);
    final savePath = await pathService.resolveAndCreate(
      basePath,
      pathService.suggestSubdirectory(platform, quality.mediaType),
    );

    final requiredBytes = quality.filesizeBytes ?? 0;
    if (requiredBytes > 0 &&
        !await FileUtils.hasEnoughSpace(savePath, requiredBytes)) {
      return (
        result: Result<DownloadEntity>.failure(
          AppException.storage(
            message: AppLocalizations.floatingCaptureErrorInsufficientDiskSpace,
          ),
        ),
        containerRecodeNotice: null,
      );
    }

    String? cookiesFile;
    try {
      cookiesFile = await _ref.read(
        cookiesFileForUrlProvider(videoInfo.url).future,
      );
    } catch (e) {
      appLogger.debug('[Capture] no cookies for background download: $e');
    }

    String? capturedContainerWarning;
    final config = selection.config;
    final result = await _ref.read(startDownloadUseCaseProvider)(
      videoInfo: videoInfo,
      selectedQuality: quality,
      savePath: savePath,
      isPremium: _ref.read(isPremiumProvider),
      cookiesFile: cookiesFile,
      cookiesFromBrowser:
          cookiesFile == null ? _ref.read(cookiesFromBrowserProvider) : null,
      cookiesFromBrowserFallbackChain: _ref.read(
        cookiesFromBrowserFallbackChainProvider,
      ),
      onContainerChangeWarning: (warning) => capturedContainerWarning = warning,
      videoCodecPreference:
          config?.resolveVideoCodec(settings) ?? settings.videoCodecPreference,
      audioCodecPreference:
          config?.resolveAudioCodec(settings) ?? settings.audioCodecPreference,
      audioBitrateKbps: config?.audioBitrateKbpsFor(quality),
      containerFormatPreference:
          config?.resolveContainerFormat(settings) ??
          settings.containerFormatPreference,
      fpsPreference: config?.resolveFps(settings) ?? settings.fpsPreference,
      subtitlesEnabled:
          config?.resolveSubtitlesEnabled(settings) ??
          settings.subtitlesEnabled,
      subtitlesLanguages:
          config?.resolveSubtitlesLanguages(settings) ??
          settings.subtitlesLanguages,
      subtitlesFormat:
          config?.resolveSubtitlesFormat(settings) ?? settings.subtitlesFormat,
      embedSubtitles:
          config?.resolveEmbedSubtitles(settings) ?? settings.embedSubtitles,
      includeAutoSubs:
          config?.resolveIncludeAutoSubs(settings) ?? settings.includeAutoSubs,
      writeThumbnail:
          config?.resolveWriteThumbnail(settings) ?? settings.writeThumbnail,
      embedThumbnail:
          config?.resolveEmbedThumbnail(settings) ?? settings.embedThumbnail,
      embedMetadata:
          config?.resolveEmbedMetadata(settings) ?? settings.embedMetadata,
      embedChapters:
          config?.resolveEmbedChapters(settings) ?? settings.embedChapters,
      sponsorBlockEnabled:
          config?.resolveSponsorBlockEnabled(settings) ??
          settings.sponsorBlockEnabled,
      sponsorBlockAction:
          config?.resolveSponsorBlockAction(settings) ??
          settings.sponsorBlockAction,
      sponsorBlockCategories:
          config?.resolveSponsorBlockCategories(settings) ??
          settings.sponsorBlockCategories,
      forceRemux: config?.resolveForceRemux(settings) ?? settings.forceRemux,
      tiktokRemoveWatermark:
          config?.resolveTiktokRemoveWatermark(settings) ??
          settings.tiktokRemoveWatermark,
      proxyUrl: _resolveActiveProxy(),
      geoBypass: settings.geoBypass,
      geoBypassCountry: settings.geoBypassCountry,
      archiveEnabled: settings.archiveEnabled,
      // RC10 Codex-round-5 — same derive-from-intent-key pattern as
      // home_download_mixin so floating-capture archive scoping
      // includes the section/chapter dimension and stays in sync
      // with duplicate detection.
      archiveFile:
          settings.archiveEnabled
              ? '$savePath/.${BrandConfig.current.brand.name}_archive'
                  '${DownloadIntentKey.fromRequest(
                    videoInfo: videoInfo,
                    quality: quality,
                    config: selection.config,
                    fallbackContainer: settings.containerFormatPreference,
                    fallbackAudioCodec: settings.audioCodecPreference,
                  ).archiveSuffix()}.txt'
              : null,
      dateAfter: settings.dateAfter,
      dateBefore: settings.dateBefore,
      minDuration: settings.minDuration,
      maxDuration: settings.maxDuration,
      socketTimeout: settings.socketTimeout,
      maxRetries: settings.maxRetries,
      httpChunkSizeMb: settings.httpChunkSizeMb,
      numSegments: _resolveNumSegments(settings),
      filenameTemplate: settings.filenameTemplate,
      customPostprocessorArgs: settings.customPostprocessorArgs,
      sectionStartTime: config?.sectionStartTime,
      sectionEndTime: config?.sectionEndTime,
      selectedChapterRanges: config?.selectedChapterRanges,
    );

    if (capturedContainerWarning != null) {
      appLogger.warning('[Capture] $capturedContainerWarning');
    }
    return (result: result, containerRecodeNotice: capturedContainerWarning);
  }

  // 2026-05-26 Codex spec — `_findQualityDuplicate` removed.
  // Floating Capture no longer hard-fails on duplicate intent; the
  // datasource's `_moveFilesToOutputDir` applies a shared ` (N)`
  // suffix when the destination exists. Helper deletion is the
  // intended end-state per "không hard-fail duplicate nữa" — Home
  // got the same treatment in the same commit. Re-add this helper
  // only if a power-user-facing duplicate AUDIT surface is added
  // later (different concern from the download-gate it used to be).

  bool _canApplySavedChoice(VideoInfo videoInfo) {
    if (videoInfo.isCarousel) return false;
    final hasImages = videoInfo.availableQualities.any(
      (q) => q.mediaType == MediaType.image,
    );
    final hasVideos = videoInfo.availableQualities.any(
      (q) => q.mediaType == MediaType.video,
    );
    return !(hasImages && hasVideos);
  }

  DownloadConfig? _buildConfigFromPreference(
    PlatformQualityPreference pref,
    Quality quality,
  ) {
    if (!pref.hasFormatOverrides && !pref.hasPrimaryIntent) return null;
    return DownloadConfig(
      selectedQualities: [quality],
      fileType: pref.fileType ?? DownloadFileType.fromMediaType(pref.mediaType),
      qualityIntent: pref.qualityIntent ?? DownloadQualityIntent.recommended,
      qualityTarget: pref.qualityTarget,
      videoCodecOverride:
          pref.videoCodec != null
              ? VideoCodecPreference.fromDbString(pref.videoCodec!)
              : null,
      audioCodecOverride:
          pref.audioCodec != null
              ? AudioCodecPreference.fromDbString(pref.audioCodec!)
              : null,
      containerFormatOverride:
          pref.containerFormat != null
              ? ContainerFormatPreference.fromDbString(pref.containerFormat!)
              : null,
      fpsOverride:
          pref.fpsPreference != null
              ? FpsPreference.fromDbString(pref.fpsPreference!)
              : null,
      maxResolutionOverride: pref.maxResolution,
      subtitlesEnabled: pref.subtitlesEnabled,
      subtitlesLanguages: pref.subtitlesLanguages,
      subtitlesFormat: pref.subtitlesFormat,
      sponsorBlockEnabled: pref.sponsorBlockEnabled,
      sponsorBlockAction: pref.sponsorBlockAction,
      sponsorBlockCategories: pref.sponsorBlockCategories,
      tiktokRemoveWatermark: pref.tiktokRemoveWatermark,
      embedThumbnail: pref.embedThumbnail,
      embedMetadata: pref.embedMetadata,
      embedChapters: pref.embedChapters,
    );
  }

  DownloadConfig _buildConfigFromPreset(
    FormatPresetExtended preset,
    Quality quality,
  ) {
    String? overrideOrNull(String value) =>
        (value.isEmpty || value == 'auto') ? null : value;

    final videoCodecValue = overrideOrNull(preset.videoCodec);
    final audioCodecValue = overrideOrNull(preset.audioCodec);
    final containerValue = overrideOrNull(preset.containerFormat);
    final fpsValue = overrideOrNull(preset.fpsPreference);
    final audioTargetFormat = containerValue ?? 'mp3';

    return DownloadConfig(
      selectedQualities: [quality],
      fileType: preset.audioOnly ? DownloadFileType.audio : null,
      qualityIntent:
          preset.audioOnly
              ? DownloadQualityIntent.specific
              : DownloadQualityIntent.recommended,
      qualityTarget:
          preset.audioOnly
              ? PortableQualityTarget.audio(
                outputFormat: audioTargetFormat,
                targetBitrateKbps: preset.audioBitrate,
              )
              : null,
      videoCodecOverride:
          videoCodecValue == null
              ? null
              : VideoCodecPreference.fromDbString(videoCodecValue),
      audioCodecOverride:
          audioCodecValue == null
              ? null
              : AudioCodecPreference.fromDbString(audioCodecValue),
      containerFormatOverride:
          containerValue == null
              ? null
              : ContainerFormatPreference.fromDbString(containerValue),
      fpsOverride:
          fpsValue == null ? null : FpsPreference.fromDbString(fpsValue),
      maxResolutionOverride:
          preset.maxResolution > 0 ? preset.maxResolution : null,
      subtitlesEnabled: preset.subtitlesEnabled,
      embedThumbnail: preset.embedThumbnail,
      embedMetadata: preset.embedMetadata,
      embedChapters: preset.embedChapters,
    );
  }

  int _resolveNumSegments(SettingsState settings) {
    if (!settings.adaptiveSegments) return settings.maxSegments;
    final downloads = _ref.read(downloadsNotifierProvider).downloads;
    final bps = NetworkThroughputMonitor.aggregateThroughput(downloads);
    final segments =
        bps > 0
            ? AdaptiveSegmentService.computeOptimalSegments(bps)
            : settings.maxSegments;
    appLogger.info(AdaptiveSegmentService.logMessage(segments, bps));
    return segments;
  }

  String? _resolveActiveProxy() {
    final settings = _ref.read(settingsProvider);
    if (settings.proxyList.isNotEmpty) {
      return _ref.read(proxyRotationServiceProvider).nextProxy();
    }
    return settings.proxyUrl;
  }

  Future<void> _emitFailure(Exception? exception) {
    final message =
        exception == null
            ? 'Download failed.'
            : AppExceptionX.readableMessage(exception);
    final code = DownloadErrorClassifier.classifyMessage(message);
    return _emitActionResult(
      code == DownloadErrorCode.loginRequired
          ? const PopupActionAuthRequired()
          : PopupActionFailed(message),
    );
  }

  Future<void> _emitActionResult(PopupActionResult result) async {
    try {
      await _ref.read(floatingWindowProvider).setActionResult(result);
    } catch (e, s) {
      appLogger.warning(
        '[Capture] setActionResult from coordinator failed',
        e,
        s,
      );
    }
  }
}

class _CaptureSelection {
  const _CaptureSelection(this.quality, {this.config, this.basePathOverride});

  final Quality quality;
  final DownloadConfig? config;
  final String? basePathOverride;
}
