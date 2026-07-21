// Mixin accesses `mounted` via abstract getter — analyzer can't trace it
// ignore_for_file: use_build_context_synchronously
import '../../../../core/core.dart';
import '../../../downloads/presentation/providers/downloads_notifier.dart';
import '../../../downloads/presentation/providers/download_providers.dart';
import '../../../downloads/presentation/providers/extraction_cache_provider.dart';
import '../../../settings/presentation/providers/platform_preferences_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../downloads/domain/entities/download_status.dart';
import '../../../downloads/domain/entities/video_info.dart';
import '../../../downloads/domain/entities/download_config.dart';
import '../../../../core/providers/notification_center_provider.dart';
import '../../../../core/providers/proxy_rotation_provider.dart';
import '../../../../core/services/notification_center_service.dart';
import '../../../downloads/domain/services/playlist_context_holder.dart';
import '../../../downloads/domain/services/playlist_download_service.dart';
import '../../../premium/domain/entities/premium_feature.dart';
import '../../../premium/presentation/providers/premium_providers.dart';
import '../../../premium/presentation/widgets/upgrade_prompt_dialog.dart';
import 'home_download_mixin.dart';

/// Mixin that provides batch (multi-URL) download logic for HomeScreen.
///
/// Depends on [HomeDownloadMixin] for single-URL download execution
/// (startDownloadWithQuality, handleBatchDownloadDecision, etc.).
mixin HomeBatchDownloadMixin on HomeDownloadMixin {
  /// Handle batch downloads from playlist/channel (bypass global extraction state).
  /// OPTIMIZED: Extract ALL videos in parallel first (5x faster!), then process downloads sequentially.
  /// Supports "Apply to all" option for batch quality selection.
  @override
  Future<void> handleBatchDownload(
    List<String> urls, {
    String? playlistId,
    String? playlistTitle,
  }) async {
    if (urls.isEmpty || !mounted) return;
    if (!ensurePremiumBootstrapReady()) return;

    // Premium gate: batch playlist/channel downloads require premium
    if (urls.length > 1) {
      final isPremium = ref.read(isPremiumProvider);
      if (!isPremium) {
        await UpgradePromptDialog.showAndNavigate(
          context,
          ref,
          feature: PremiumFeature.batchDownload,
        );
        return;
      }
    }

    // Deduplicate URLs (YouTube Mix/Radio playlists can return duplicates)
    final uniqueUrls = urls.toSet().toList();
    if (uniqueUrls.length < urls.length) {
      appLogger.warning(
        '⚠️ [Batch] Removed ${urls.length - uniqueUrls.length} duplicate URLs (${urls.length} → ${uniqueUrls.length})',
      );
    }
    urls = uniqueUrls;

    // === RESUME SUPPORT: skip already-completed URLs ===
    const playlistService = PlaylistDownloadService();
    final allDownloads = ref.read(downloadsNotifierProvider).downloads;
    final completedDownloads =
        allDownloads
            .where((d) => d.status == DownloadStatus.completed)
            .toList();
    final pendingUrls = playlistService.filterPendingUrls(
      urls,
      completedDownloads,
    );
    final skippedCount = urls.length - pendingUrls.length;

    if (skippedCount > 0) {
      appLogger.info(
        '⏭️ [Batch] Skipping $skippedCount already-downloaded URLs',
      );
    }

    if (pendingUrls.isEmpty) {
      if (mounted) {
        AppSnackBar.success(
          context,
          message: AppLocalizations.playlistAllSkipped(urls.length),
        );
      }
      return;
    }

    urls = pendingUrls;

    // Stamp playlist context AFTER pendingUrls is computed — earlier
    // stamping (on uniqueUrls) leaked stale entries for URLs that the
    // resume-support filter had already excluded, because the trailing
    // `clearForUrls` below only evicts the local `urls` (= pendingUrls)
    // not the original deduped list. Stamping on pendingUrls keeps
    // holder lifetime tight: stamps exist exactly for the URLs that
    // will reach `createDownload`.
    final holder = ref.read(playlistContextHolderProvider);
    if (playlistId != null) {
      holder.stampBatch(
        urls,
        playlistId: playlistId,
        playlistTitle: playlistTitle,
      );
    }

    // Start playlist session for progress tracking (2+ videos)
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    final notifier = ref.read(downloadsNotifierProvider.notifier);
    // total = pending + already-skipped so the indicator shows true overall progress
    notifier.startPlaylistSession(
      sessionId,
      uniqueUrls.length,
      phase: PlaylistSessionPhase.extracting,
    );
    final progressToastId = 'batch_download_$sessionId';
    // Count skipped items immediately
    for (int s = 0; s < skippedCount; s++) {
      notifier.incrementPlaylistSkipped();
    }

    final extractUseCase = ref.read(extractVideoInfoUseCaseProvider);
    final settings = ref.read(settingsProvider);
    final batchCookiesFromBrowser = ref.read(cookiesFromBrowserProvider);
    final batchCookiesFromBrowserFallback =
        ref.read(cookiesFromBrowserFallbackProvider);
    final batchCookiesFromBrowserFallbackChain =
        ref.read(cookiesFromBrowserFallbackChainProvider);

    appLogger.info(
      '🎬 [Batch] Starting parallel extraction for ${urls.length} videos',
    );

    // Show persistent progress indicator for extraction phase
    if (mounted) {
      AppSnackBar.progress(
        context,
        id: progressToastId,
        message: AppLocalizations.homePreparingBatch(urls.length),
        value: 0,
      );
    }

    // === PHASE 1: BATCHED PARALLEL EXTRACTION ===
    // Extract videos in batches (max 2 concurrent) to avoid rate limiting
    const maxConcurrent = 2; // YouTube rate limit: max 2 concurrent extractions
    final extractionResults = <({String url, Result<VideoInfo> result})>[];

    for (
      int batchStart = 0;
      batchStart < urls.length;
      batchStart += maxConcurrent
    ) {
      if (!mounted) break;
      final batchEnd = (batchStart + maxConcurrent).clamp(0, urls.length);
      final batchUrls = urls.sublist(batchStart, batchEnd);

      appLogger.info(
        '🎬 [Batch] Extracting batch ${batchStart ~/ maxConcurrent + 1}: ${batchUrls.length} videos',
      );

      // Extract this batch in parallel
      final batchFutures =
          batchUrls.map((url) {
            // Resolve before the first async gap. This preserves per-URL proxy
            // rotation without touching WidgetRef after disposal.
            final proxyUrl = resolveActiveProxy(ref);
            return () async {
              try {
                // Get cookies for this URL
                String? cookiesFile;
                try {
                  cookiesFile = await ref.read(
                    cookiesFileForUrlProvider(url).future,
                  );
                } catch (e) {
                  appLogger.debug('🍪 [Batch] No cookies for URL: $url');
                }

                // Extract video info (pass active proxy for extraction too)
                final result = await extractUseCase(
                  url,
                  engine: settings.downloadEngine,
                  cookiesFile: cookiesFile,
                  cookiesFromBrowser: batchCookiesFromBrowser,
                  cookiesFromBrowserFallback: batchCookiesFromBrowserFallback,
                  cookiesFromBrowserFallbackChain:
                      batchCookiesFromBrowserFallbackChain,
                  proxyUrl: proxyUrl,
                );

                return (url: url, result: result);
              } catch (e, stack) {
                appLogger.error(
                  '❌ [Batch] Exception during extraction: $url',
                  e,
                  stack,
                );
                return (
                  url: url,
                  result: Result<VideoInfo>.failure(
                    AppException.download(
                      message:
                          'Extraction failed: ${AppExceptionX.readableMessage(e)}',
                    ),
                  ),
                );
              }
            }();
          }).toList();

      // Wait for this batch to complete before starting next batch
      final batchResults = await Future.wait(batchFutures);
      extractionResults.addAll(batchResults);
      if (!mounted) break;

      if (mounted) {
        AppSnackBar.progress(
          context,
          id: progressToastId,
          message: AppLocalizations.homeStartingBatchProgress(
            extractionResults.length,
            urls.length,
          ),
          value: (extractionResults.length / urls.length) * 0.45,
        );
      }

      // Small delay between batches to avoid rate limiting (optional)
      if (batchEnd < urls.length) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) break;
      }
    }

    appLogger.info(
      '✅ [Batch] Extraction complete: ${extractionResults.length} results',
    );

    // === PHASE 2: SEQUENTIAL DOWNLOAD PROCESSING ===
    // Process downloads one-by-one for "Apply to all" UX
    int successCount = 0;
    int failCount = 0;
    Quality? savedQuality;
    DownloadConfig? savedConfig;
    bool applyToAll = false;

    if (mounted) {
      notifier.updatePlaylistPhase(PlaylistSessionPhase.queueing);
      AppSnackBar.progress(
        context,
        id: progressToastId,
        message: AppLocalizations.homeStartingBatchProgress(
          0,
          extractionResults.length,
        ),
        value: 0.5,
      );
    }

    for (int i = 0; i < extractionResults.length; i++) {
      if (!mounted) break;

      final (url: url, result: result) = extractionResults[i];

      await result.when(
        success: (videoInfo) async {
          appLogger.info(
            '✅ [Batch] Processing ${i + 1}/${urls.length}: ${videoInfo.title}',
          );

          // Save to cache
          ref
              .read(extractionHistoryProvider.notifier)
              .addExtraction(url, videoInfo);

          // Check if "Apply to all" is active and we have a saved quality
          if (applyToAll && savedQuality != null) {
            // Use QualityFallbackService for smart matching
            final fallbackEnabled = ref.read(qualityFallbackEnabledProvider);
            final fallbackService = ref.read(qualityFallbackServiceProvider);
            final fallbackResult =
                fallbackEnabled
                    ? fallbackService.findBestMatch(
                      savedQuality!,
                      videoInfo.availableQualities,
                    )
                    : null;

            // If fallback disabled, try exact match only
            final matchingQuality =
                fallbackEnabled
                    ? fallbackResult?.quality
                    : videoInfo.availableQualities
                        .where(
                          (q) =>
                              q.qualityText == savedQuality!.qualityText &&
                              q.mediaType == savedQuality!.mediaType,
                        )
                        .firstOrNull;

            if (matchingQuality != null) {
              // Notify user if fallback was applied
              if (fallbackResult != null && fallbackResult.isFallback) {
                ref
                    .read(notificationCenterServiceProvider)
                    .add(
                      AppNotificationType.qualityFallbackApplied,
                      AppLocalizations.qualityFallbackNotificationTitle,
                      AppLocalizations.qualityFallbackNotificationBody(
                        videoInfo.title,
                        fallbackResult.reason ?? '',
                      ),
                    );
                appLogger.info(
                  '🔄 [Batch] Quality fallback: ${fallbackResult.reason}',
                );
              }

              // Use matched quality + format overrides, skip dialog.
              // CRITICAL: chapter selection is per-video — strip it before
              // reusing savedConfig for a different video, otherwise time
              // ranges from video A would leak into video B's download.
              final reusedConfig = savedConfig?.copyWith(
                selectedChapterRanges: () => null,
              );
              await startDownloadWithQuality(
                videoInfo,
                matchingQuality,
                config: reusedConfig,
              );
              if (!mounted) return;
              successCount++;
              notifier.incrementPlaylistCompleted();
              appLogger.info(
                '🔄 [Batch] Applied quality: ${matchingQuality.qualityText}',
              );
            } else {
              // No matching quality found for this video -- show dialog but keep saved state
              // so subsequent videos can still try the original quality
              appLogger.warning(
                '⚠️ [Batch] Saved quality not available for this video, showing dialog',
              );

              final downloadStarted = await handleBatchDownloadDecision(
                videoInfo,
                remainingCount: urls.length - i,
              );
              if (!mounted) return;

              if (downloadStarted.started) {
                successCount++;
                notifier.incrementPlaylistCompleted();
                // If user set a new "Apply to all", update saved state
                if (downloadStarted.applyToAll &&
                    downloadStarted.quality != null) {
                  savedQuality = downloadStarted.quality;
                  savedConfig = downloadStarted.config;
                }
                // Keep applyToAll = true -- next video will try savedQuality again
              } else {
                notifier.incrementPlaylistFailed();
              }
            }
          } else {
            // Rule 2 for batch: Check saved platform preference before showing dialog
            final batchPlatform = PlatformDetector.detectPlatform(
              videoInfo.url,
            );
            final batchSavedPref = ref
                .read(platformPreferencesProvider.notifier)
                .getPreference(batchPlatform);

            if (batchSavedPref != null && canApplySavedChoice(videoInfo)) {
              // Auto-apply saved preference (same as single-URL Rule 2)
              final matchingQuality = videoInfo.availableQualities.firstWhere(
                (q) =>
                    q.qualityText == batchSavedPref.qualityText &&
                    q.mediaType == batchSavedPref.mediaType,
                orElse: () => videoInfo.availableQualities.first,
              );

              final prefConfig = buildConfigFromPreference(
                batchSavedPref,
                matchingQuality,
              );

              await startDownloadWithQuality(
                videoInfo,
                matchingQuality,
                config: prefConfig,
              );
              if (!mounted) return;
              successCount++;
              notifier.incrementPlaylistCompleted();
              appLogger.info(
                '🔄 [Batch] Auto-applied saved ${batchPlatform.displayName} preference: ${matchingQuality.qualityText}',
              );
            } else {
              // No saved preference -- show quality selection dialog
              final downloadStarted = await handleBatchDownloadDecision(
                videoInfo,
                remainingCount: urls.length - i,
              );
              if (!mounted) return;

              if (downloadStarted.started) {
                successCount++;
                notifier.incrementPlaylistCompleted();
                // Save quality + config if "Apply to all" was checked
                if (downloadStarted.applyToAll &&
                    downloadStarted.quality != null) {
                  applyToAll = true;
                  savedQuality = downloadStarted.quality;
                  savedConfig = downloadStarted.config;
                  appLogger.info(
                    '💾 [Batch] Saved quality for remaining videos: ${savedQuality!.qualityText}',
                  );
                }
              } else {
                notifier.incrementPlaylistFailed();
              }
            }
          }
        },
        failure: (exception) async {
          failCount++;
          notifier.incrementPlaylistFailed();
          final errorMsg = AppExceptionX.readableMessage(exception);
          appLogger.error(
            '❌ [Batch] Failed ${i + 1}/${urls.length}: $errorMsg',
          );
        },
      );

      if (mounted) {
        final processed = i + 1;
        AppSnackBar.progress(
          context,
          id: progressToastId,
          message: AppLocalizations.homeStartingBatchProgress(
            processed,
            extractionResults.length,
          ),
          value: 0.5 + (processed / extractionResults.length) * 0.5,
        );
      }
    }

    // Evict any URLs that were stamped but never consumed (extraction
    // failure or aborted dialog). Without this a stale tag would
    // mis-attribute a future ad-hoc download of the same URL to the
    // playlist this batch came from.
    if (playlistId != null) {
      holder.clearForUrls(urls);
    }

    // End session and hide progress indicator
    notifier.endPlaylistSession();

    // Hide progress indicator and show final summary
    if (mounted) {
      final totalOriginal = uniqueUrls.length;
      final message =
          failCount == 0
              ? AppLocalizations.playlistComplete(successCount, totalOriginal)
              : 'Started $successCount/${urls.length} downloads ($failCount failed)';

      AppSnackBar.completeProgress(
        context,
        id: progressToastId,
        message: message,
        success: failCount == 0,
      );
    }

    appLogger.info(
      '🎬 [Batch] Completed: $successCount success, $failCount failed',
    );
  }
}
