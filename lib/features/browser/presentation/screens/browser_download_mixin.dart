// Mixin accesses `mounted` via abstract getter — analyzer can't trace it
// ignore_for_file: use_build_context_synchronously
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/core.dart';
import '../../../../core/auth/presentation/widgets/platform_login_dialog.dart';
import '../../../downloads/domain/entities/download_config.dart';
import '../../../settings/domain/enums/audio_codec_preference.dart';
import '../../../settings/domain/enums/container_format_preference.dart';
import '../../../settings/domain/enums/fps_preference.dart';
import '../../../settings/domain/enums/video_codec_preference.dart';
import '../../../settings/domain/entities/platform_quality_preference.dart';
import '../../../downloads/domain/entities/download_error_code.dart';
import '../../../downloads/domain/entities/video_info.dart';
import '../../../downloads/domain/services/download_error_classifier.dart';
import '../../../downloads/domain/services/gallery_default_quality_selector.dart';
import '../../../downloads/domain/services/quality_resolution_parser.dart';
import '../../../downloads/presentation/providers/download_providers.dart';
import '../../../downloads/presentation/providers/extraction_provider.dart';
import '../../../downloads/presentation/providers/extraction_cache_provider.dart';
import '../../../downloads/presentation/providers/download_path_suggestion_provider.dart';
import '../../../downloads/presentation/widgets/download_config_dialog.dart';
import '../../../premium/domain/entities/premium_feature.dart';
import '../../../premium/domain/entities/premium_limits.dart';
import '../../../premium/presentation/providers/premium_providers.dart';
import '../../../premium/presentation/widgets/upgrade_prompt_dialog.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../settings/presentation/providers/platform_preferences_provider.dart';
import '../../domain/services/page_video_scanner_service.dart';
import '../providers/browser_providers.dart';
import '../providers/content_filter_providers.dart';

/// Mixin that provides download-related logic for BrowserScreen.
///
/// Extracted from _BrowserScreenState to reduce file size.
/// Requires the host class to expose certain fields via abstract getters/setters.
mixin BrowserDownloadMixin {
  // ── Required abstract accessors (provided by _BrowserScreenState) ──

  /// Riverpod ref - provided by ConsumerState
  WidgetRef get ref;

  /// Whether this State is currently mounted
  bool get mounted;

  /// The BuildContext of the widget
  BuildContext get context;

  /// Whether a download dialog is currently being shown
  bool get isShowingDialog;
  set isShowingDialog(bool value);

  /// URLs that already triggered login guidance, to avoid infinite retry loops.
  Set<String> get autoLoginAttemptedUrls;

  bool _shouldStopOnLoginRequiredForFirstLogin({
    required String url,
    required String? cookiesFile,
    required String? cookiesFromBrowser,
  }) {
    return Platform.isWindows &&
        PlatformDetector.detectPlatform(url) == VideoPlatform.youtube &&
        cookiesFile == null &&
        cookiesFromBrowser == null;
  }

  /// Detect auth-gated extraction errors, guide the user through platform
  /// login/cookie capture, then retry extraction once with fresh cookies.
  Future<bool> handleBrowserExtractionError(
    String error,
    String? failedUrl,
  ) async {
    final errorCode = DownloadErrorClassifier.classifyMessage(error);
    if (errorCode != DownloadErrorCode.loginRequired || failedUrl == null) {
      if (mounted) {
        AppSnackBar.error(
          context,
          message: AppLocalizations.errorFeedbackHint(errorCode.name),
        );
      }
      return false;
    }

    if (autoLoginAttemptedUrls.contains(failedUrl)) {
      final platform = PlatformDetector.detectPlatform(failedUrl);
      if (platform == VideoPlatform.facebook) {
        // The sniffing engine is always on now; surface what it found by
        // opening the media panel (no premium gate — svid is free/unlimited).
        ref.read(sniffPanelOpenProvider.notifier).state = true;
        if (!mounted) return true;
        if (mounted) {
          AppSnackBar.error(
            context,
            message: AppLocalizations.browserFacebookSniffFallback,
          );
        }
        return true;
      }
      if (mounted) {
        AppSnackBar.error(
          context,
          message: AppLocalizations.errorFeedbackHint('loginRequired'),
        );
      }
      return true;
    }

    final platform = PlatformDetector.detectPlatform(failedUrl);
    final loginUrl = PlatformDetector.getLoginUrl(platform);
    if (loginUrl == null) {
      if (mounted) {
        AppSnackBar.error(
          context,
          message: AppLocalizations.errorFeedbackHint('loginRequired'),
        );
      }
      return true;
    }

    autoLoginAttemptedUrls.add(failedUrl);

    final success = await showPlatformLoginDialog(
      context: context,
      platform: platform.name,
      loginUrl: loginUrl,
    );

    if (!success || !mounted) return true;

    String? cookiesFile;
    try {
      ref.invalidate(cookiesFileForUrlProvider(failedUrl));
      cookiesFile = await ref.read(cookiesFileForUrlProvider(failedUrl).future);
    } catch (e) {
      appLogger.warning('Cookie export failed, retrying without auth: $e');
    }
    if (!mounted) return true;

    final settings = ref.read(settingsProvider);
    ref
        .read(extractionProvider.notifier)
        .startExtraction(
          url: failedUrl,
          engine: settings.downloadEngine,
          cookiesFile: cookiesFile,
          cookiesFromBrowser:
              cookiesFile == null ? ref.read(cookiesFromBrowserProvider) : null,
          cookiesFromBrowserFallback: ref.read(
            cookiesFromBrowserFallbackProvider,
          ),
          cookiesFromBrowserFallbackChain: ref.read(
            cookiesFromBrowserFallbackChainProvider,
          ),
        );
    return true;
  }

  /// Trigger download for detected video URL
  Future<void> onDownloadTapped() async {
    final detection = ref.read(browserVideoDetectionProvider);
    if (detection == null || !detection.isVideoPage) return;

    final url = detection.url;
    final extractionNotifier = ref.read(extractionProvider.notifier);
    final extractionState = ref.read(extractionProvider);

    if (extractionState.isExtracting) {
      if (mounted) {
        AppSnackBar.info(context, message: AppLocalizations.browserDownloading);
      }
      return;
    }

    final cachedInfo = await ref
        .read(extractionHistoryProvider.notifier)
        .getCachedAsync(url);
    if (!mounted) return;
    if (cachedInfo != null) {
      appLogger.info('[Browser] Using cached extraction: ${cachedInfo.title}');
      await handleDownloadDecision(cachedInfo);
      return;
    }

    if (mounted) {
      AppSnackBar.info(context, message: AppLocalizations.browserDownloading);
    }

    String? cookiesFile;
    try {
      cookiesFile = await ref.read(cookiesFileForUrlProvider(url).future);
    } catch (_) {}
    if (!mounted) return;

    final settings = ref.read(settingsProvider);
    final cookiesFromBrowser =
        cookiesFile == null ? ref.read(cookiesFromBrowserProvider) : null;
    extractionNotifier.startExtraction(
      url: url,
      engine: settings.downloadEngine,
      cookiesFile: cookiesFile,
      cookiesFromBrowser: cookiesFromBrowser,
      cookiesFromBrowserFallback: ref.read(cookiesFromBrowserFallbackProvider),
      cookiesFromBrowserFallbackChain: ref.read(
        cookiesFromBrowserFallbackChainProvider,
      ),
      stopOnLoginRequired: _shouldStopOnLoginRequiredForFirstLogin(
        url: url,
        cookiesFile: cookiesFile,
        cookiesFromBrowser: cookiesFromBrowser,
      ),
    );
  }

  /// Handle batch download of selected videos.
  Future<void> onBatchDownload(List<DetectedVideoLink> videos) async {
    for (final video in videos) {
      if (!mounted) return;
      final extractionNotifier = ref.read(extractionProvider.notifier);
      final settings = ref.read(settingsProvider);

      String? cookiesFile;
      try {
        cookiesFile = await ref.read(
          cookiesFileForUrlProvider(video.url).future,
        );
      } catch (_) {}
      if (!mounted) return;

      final cookiesFromBrowser =
          cookiesFile == null ? ref.read(cookiesFromBrowserProvider) : null;
      extractionNotifier.startExtraction(
        url: video.url,
        engine: settings.downloadEngine,
        cookiesFile: cookiesFile,
        cookiesFromBrowser: cookiesFromBrowser,
        cookiesFromBrowserFallback: ref.read(
          cookiesFromBrowserFallbackProvider,
        ),
        cookiesFromBrowserFallbackChain: ref.read(
          cookiesFromBrowserFallbackChainProvider,
        ),
        stopOnLoginRequired: _shouldStopOnLoginRequiredForFirstLogin(
          url: video.url,
          cookiesFile: cookiesFile,
          cookiesFromBrowser: cookiesFromBrowser,
        ),
      );
      // Small delay between extractions to avoid rate limiting
      if (videos.length > 1) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
      }
    }
  }

  /// Fire-and-forget: preload first bytes of the best direct-URL quality.
  /// Only activates for qualities with a literal `https://` URL (non-yt-dlp).
  void triggerPreloadIfDirect(VideoInfo videoInfo) {
    final directQuality = videoInfo.availableQualities.firstWhere(
      (q) => q.encryptedUrl.startsWith('https://'),
      orElse: () => videoInfo.availableQualities.first,
    );
    if (!directQuality.encryptedUrl.startsWith('https://')) return;
    final preloader = ref.read(smartPreloadServiceProvider);
    preloader
        .preload(directQuality.encryptedUrl)
        .ignore(); // best-effort, never throws to caller
  }

  Future<bool> handleDownloadDecision(VideoInfo videoInfo) async {
    if (!mounted || isShowingDialog) return false;

    isShowingDialog = true;
    try {
      final platform = PlatformDetector.detectPlatform(videoInfo.url);

      if (videoInfo.availableQualities.length == 1) {
        await _startDownloadWithQuality(
          videoInfo,
          videoInfo.availableQualities.first,
        );
        if (mounted) {
          AppSnackBar.success(
            context,
            message: AppLocalizations.homeDownloadStarted(videoInfo.title),
          );
        }
        return true;
      }

      final allImagesQuality = GalleryDefaultQualitySelector.allImagesQuality(
        videoInfo,
      );
      if (allImagesQuality != null) {
        await _startDownloadWithQuality(videoInfo, allImagesQuality);
        if (mounted) {
          AppSnackBar.success(
            context,
            message: AppLocalizations.homeDownloadStarted(videoInfo.title),
          );
        }
        return true;
      }

      final savedPref = ref
          .read(platformPreferencesProvider.notifier)
          .getPreference(platform);
      if (savedPref != null && !videoInfo.isCarousel) {
        final matchingQuality = videoInfo.availableQualities.firstWhere(
          (q) =>
              q.qualityText == savedPref.qualityText &&
              q.mediaType == savedPref.mediaType,
          orElse: () => videoInfo.availableQualities.first,
        );
        // Codex audit fix: the saved-pref auto-start used to call
        // _startDownloadWithQuality with no config, which made the
        // use-case fall back to GLOBAL settings.containerFormatPreference
        // instead of the platform-specific override stored in
        // PlatformQualityPreference. That meant a user who picked AVI
        // for TikTok via the dialog + "save as preference" got MKV/MP4
        // on the next auto-pick. Build the same prefConfig the home
        // flow uses so saved container/codec/etc round-trips into the
        // planner.
        final prefConfig = _buildConfigFromPreference(
          savedPref,
          matchingQuality,
        );
        await _startDownloadWithQuality(
          videoInfo,
          matchingQuality,
          config: prefConfig,
        );
        if (mounted) {
          AppSnackBar.success(
            context,
            message: AppLocalizations.homeDownloadStarted(videoInfo.title),
          );
        }
        return true;
      }

      final config = await DownloadConfigDialog.show(
        context,
        videoInfo,
        platform,
      );
      if (!mounted) return false;
      if (config != null && config.selectedQualities.isNotEmpty) {
        // Track whether at least one quality launched successfully. If every
        // quality in the loop threw, hoisted persistence + the success
        // snackbar must NOT fire — otherwise the user sees "Download
        // started for <title>" with zero downloads in flight AND their
        // "save as default" preference gets written from a flow that
        // produced nothing. Codex review caught this regression.
        var anyDownloadStarted = false;
        for (final quality in config.selectedQualities) {
          try {
            await _startDownloadWithQuality(videoInfo, quality, config: config);
            if (!mounted) return false;
            anyDownloadStarted = true;
          } catch (e, stack) {
            appLogger.error(
              'Failed to start download for ${quality.qualityText}',
              e,
              stack,
            );
          }
        }
        if (!anyDownloadStarted) {
          // Every quality blocked or threw — surface failure, do NOT
          // persist preferences derived from a non-event.
          if (mounted) {
            AppSnackBar.error(
              context,
              message: AppLocalizations.homeDownloadFailed(videoInfo.title),
            );
          }
          return false;
        }
        // PR #234 persistence — hoist OUT of the per-quality loop so a
        // multi-quality download writes savePreference + default-selection
        // ONCE rather than N times. Uses the first selected quality as the
        // representative for the platform preference (qualityText only
        // matters for legacy fallback; the portable fields drive new
        // resolution).
        final settings = ref.read(settingsProvider);
        await _persistRememberAndSaveAsDefault(
          config: config,
          quality: config.selectedQualities.first,
          platform: PlatformDetector.detectPlatform(videoInfo.url),
          settings: settings,
        );
        if (mounted) {
          AppSnackBar.success(
            context,
            message: AppLocalizations.homeDownloadStarted(videoInfo.title),
          );
        }
        return true;
      }

      return false;
    } finally {
      isShowingDialog = false;
    }
  }

  /// Convert a saved [PlatformQualityPreference] into a one-shot
  /// [DownloadConfig] so the use-case downstream gets the user's
  /// saved container/codec/etc overrides — same shape as the home
  /// flow's `buildConfigFromPreference`. Returns `null` when the
  /// saved-pref carries no format overrides (the use-case can then
  /// fall back to global settings as before).
  ///
  /// Browser-local mirror of `HomeDownloadMixin.buildConfigFromPreference`.
  /// Codex review caught that the browser saved-pref auto-start
  /// previously dropped these overrides on the floor.
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

  Future<void> _startDownloadWithQuality(
    VideoInfo videoInfo,
    Quality quality, {
    DownloadConfig? config,
  }) async {
    if (!_ensurePremiumBootstrapReady()) return;

    final startUseCase = ref.read(startDownloadUseCaseProvider);
    final settings = ref.read(settingsProvider);
    final isPremium = ref.read(isPremiumProvider);
    final quotaNotifier = ref.read(downloadQuotaNotifierProvider.notifier);

    if (!isPremium) {
      final qualityHeight = QualityResolutionParser.heightForQuality(quality);
      if (qualityHeight != null &&
          qualityHeight > PremiumLimits.freeMaxResolutionP) {
        if (!mounted) return;
        appLogger.info(
          '🚫 [Premium] Browser quality ${qualityHeight}p exceeds free tier limit (${PremiumLimits.freeMaxResolutionP}p)',
        );
        await UpgradePromptDialog.showAndNavigate(
          context,
          ref,
          feature: PremiumFeature.highQuality4K,
        );
        return;
      }
    }

    final pathService = ref.read(downloadPathSuggestionServiceProvider);
    final platform = PlatformDetector.detectPlatform(videoInfo.url);
    final settingsPath = ref.read(downloadPathProvider);
    // PR #234 — dialog save-location picker (config.savePathOverride) wins
    // over settings path.
    final dialogOverride = config?.savePathOverride;
    final basePath =
        (dialogOverride != null && dialogOverride.isNotEmpty)
            ? dialogOverride
            : settingsPath.isNotEmpty
            ? settingsPath
            : (await getDownloadsDirectory())?.path ??
                (await getApplicationDocumentsDirectory()).path;
    if (!mounted) return;
    final subdirectory = pathService.suggestSubdirectory(
      platform,
      quality.mediaType,
    );
    final savePath = await pathService.resolveAndCreate(basePath, subdirectory);
    if (!mounted) return;

    String? cookiesFile;
    try {
      cookiesFile = await ref.read(
        cookiesFileForUrlProvider(videoInfo.url).future,
      );
    } catch (_) {}
    if (!mounted) return;

    if (!quotaNotifier.tryConsume(isPremium: isPremium)) {
      appLogger.info(
        '🚫 [Premium] Browser weekly limit reached (${quotaNotifier.currentPeriodCount()}/${PremiumLimits.freeWeeklyDownloads})',
      );
      AppSnackBar.premium(
        context,
        message: AppLocalizations.premiumGateWeeklyLimitReached(
          PremiumLimits.freeWeeklyDownloads,
        ),
        action: SnackBarAction(
          label: AppLocalizations.premiumUpgrade,
          onPressed:
              () => UpgradePromptDialog.showAndNavigate(
                context,
                ref,
                feature: PremiumFeature.unlimitedDownloads,
              ),
        ),
      );
      return;
    }

    // Cookie precedence parity with extractor flow (see lines 200 +
    // 234). When the in-app captured cookies file is present, do NOT
    // also pass cookies-from-browser — the use-case retry chain would
    // otherwise treat the browser cookies as a viable fallback and
    // hit the Chrome cookie-DB-lock chain even though the file path
    // is already authoritative. Codex audit 2026-05-21 caught this:
    // `commit 65897822` fixed the datasource arg emission but the
    // mixin call-site still passed both, leaving the use-case
    // fallback path exposed to the same DB-lock symptom on Windows.
    final cookiesFromBrowser =
        cookiesFile == null ? ref.read(cookiesFromBrowserProvider) : null;

    await startUseCase(
      videoInfo: videoInfo,
      selectedQuality: quality,
      savePath: savePath,
      isPremium: isPremium,
      quotaAlreadyReserved: true,
      cookiesFile: cookiesFile,
      cookiesFromBrowser: cookiesFromBrowser,
      cookiesFromBrowserFallbackChain: ref.read(
        cookiesFromBrowserFallbackChainProvider,
      ),
      onContainerChangeWarning: (warning) {
        if (!mounted) return;
        AppSnackBar.warning(context, message: warning);
      },
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
      tiktokRemoveWatermark:
          config?.resolveTiktokRemoveWatermark(settings) ??
          settings.tiktokRemoveWatermark,
      // PR #234 — partial-download (time range / chapter ranges) honored
      // through to yt-dlp arg builder, same as home flow.
      sectionStartTime: config?.sectionStartTime,
      sectionEndTime: config?.sectionEndTime,
      selectedChapterRanges: config?.selectedChapterRanges,
    );
    // NOTE: Persistence of "Remember for [platform]" + "Save as default"
    // intentionally lives at the *caller* (outer download loop) so a
    // multi-quality download writes preferences once, not N times. See
    // _persistRememberAndSaveAsDefault invocation above the success
    // snackbar in the dialog flow.
  }

  Future<void> _persistRememberAndSaveAsDefault({
    required DownloadConfig config,
    required Quality quality,
    required VideoPlatform platform,
    required SettingsState settings,
  }) async {
    if (config.rememberForPlatform) {
      try {
        await ref
            .read(platformPreferencesProvider.notifier)
            .savePreference(
              platform: platform,
              qualityText: quality.qualityText,
              mediaType: quality.mediaType,
              fileType: config.fileType,
              qualityIntent: config.qualityIntent,
              qualityTarget: config.qualityTarget,
              videoCodec: config.videoCodecOverride?.toDbString(),
              audioCodec: config.audioCodecOverride?.toDbString(),
              containerFormat: config.containerFormatOverride?.toDbString(),
              fpsPreference: config.fpsOverride?.toDbString(),
              maxResolution: config.maxResolutionOverride,
              subtitlesEnabled: config.subtitlesEnabled,
              subtitlesLanguages: config.subtitlesLanguages,
              subtitlesFormat: config.subtitlesFormat,
              sponsorBlockEnabled: config.sponsorBlockEnabled,
              sponsorBlockAction: config.sponsorBlockAction,
              sponsorBlockCategories: config.sponsorBlockCategories,
              tiktokRemoveWatermark: config.tiktokRemoveWatermark,
              embedThumbnail: config.embedThumbnail,
              embedMetadata: config.embedMetadata,
              embedChapters: config.embedChapters,
            );
      } catch (e, stack) {
        appLogger.error(
          'Failed to save platform preference from browser',
          e,
          stack,
        );
      }
    }

    if (config.saveAsDefault && config.hasOverrides(settings)) {
      final notifier = ref.read(settingsProvider.notifier);
      try {
        if (config.fileType != null &&
            config.qualityIntent != DownloadQualityIntent.technicalStream) {
          await notifier.updateDefaultDownloadSelection(
            fileType: config.fileType!,
            qualityIntent: config.qualityIntent,
            qualityTarget: config.qualityTarget,
          );
        }
        if (config.videoCodecOverride != null) {
          await notifier.updateVideoCodecPreference(config.videoCodecOverride!);
        }
        if (config.audioCodecOverride != null) {
          await notifier.updateAudioCodecPreference(config.audioCodecOverride!);
        }
        if (config.containerFormatOverride != null) {
          await notifier.updateContainerFormatPreference(
            config.containerFormatOverride!,
          );
        }
        if (config.fpsOverride != null) {
          await notifier.updateFpsPreference(config.fpsOverride!);
        }
        if (config.maxResolutionOverride != null) {
          await notifier.updateMaxResolution(config.maxResolutionOverride!);
        }
        appLogger.info(
          '💾 [Browser] Saved format overrides as global defaults',
        );
      } catch (e, stack) {
        appLogger.error(
          'Failed to save default download selection from browser',
          e,
          stack,
        );
      }
    }
  }

  bool _ensurePremiumBootstrapReady() {
    if (ref.read(premiumBootstrapReadyProvider)) return true;
    appLogger.info(
      '⏳ [Premium] Browser download blocked while premium state initializes',
    );
    if (mounted) {
      AppSnackBar.info(
        context,
        message: AppLocalizations.homeCheckingPremiumLicense,
      );
    }
    return false;
  }
}
