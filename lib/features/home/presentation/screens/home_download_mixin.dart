// Mixin accesses `mounted` via abstract getter — analyzer can't trace it
// ignore_for_file: use_build_context_synchronously
import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/core.dart';
import '../../../downloads/presentation/providers/downloads_notifier.dart';
import '../../../downloads/presentation/providers/download_providers.dart';
import '../../../downloads/presentation/providers/extraction_provider.dart';
import '../../../downloads/presentation/providers/extraction_cache_provider.dart';
import '../../../settings/domain/entities/platform_quality_preference.dart';
import '../../../settings/presentation/providers/platform_preferences_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../downloads/domain/entities/download_entity.dart';
import '../../../downloads/domain/entities/download_status.dart';
import '../../../downloads/domain/entities/video_info.dart';
import '../../../downloads/domain/entities/download_config.dart';
import '../../../downloads/presentation/providers/download_path_suggestion_provider.dart';
import '../../../downloads/presentation/utils/download_start_result.dart';
import '../../../downloads/presentation/widgets/download_config_dialog.dart';
import '../../../floating_capture/domain/entities/popup_action_result.dart';
import '../../../floating_capture/presentation/providers/floating_capture_providers.dart';
import '../../../settings/domain/entities/format_preset_extended.dart';
import '../../../settings/domain/enums/audio_codec_preference.dart';
import '../../../settings/domain/enums/container_format_preference.dart';
import '../../../settings/domain/enums/fps_preference.dart';
import '../../../settings/domain/enums/video_codec_preference.dart';
import '../../../settings/domain/services/preset_quality_matcher.dart';
import '../../../settings/presentation/providers/active_preset_provider.dart';
import '../../../../core/providers/proxy_rotation_provider.dart';
import '../../../../core/providers/backend_providers.dart';
import '../../../../core/services/network_monitor_service.dart';
import '../../../downloads/domain/services/adaptive_segment_service.dart';
import '../../../downloads/domain/services/download_intent_key.dart';
import '../../../downloads/domain/services/network_throughput_monitor.dart';
import '../../../downloads/domain/services/download_error_classifier.dart';
import '../../../downloads/domain/services/gallery_default_quality_selector.dart';
import '../../../downloads/domain/services/quality_resolution_parser.dart';
import '../../../downloads/domain/entities/download_error_code.dart';
import '../../../../core/auth/presentation/widgets/platform_login_dialog.dart';
import '../../../premium/domain/entities/premium_feature.dart';
import '../../../premium/domain/entities/premium_limits.dart';
import '../../../premium/presentation/providers/premium_providers.dart';
import '../../../premium/presentation/widgets/upgrade_prompt_dialog.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/navigation/navigation_constants.dart';
import '../../../browser/presentation/providers/browser_tab_providers.dart';
import '../../../youtube_search/youtube_search.dart';
import '../../../youtube_channel/youtube_channel.dart';
import '../../../youtube_playlist/youtube_playlist.dart';
import '../../domain/services/url_classifier_service.dart';

/// Result of batch download decision.
/// Contains download status and quality for "Apply to all" feature.
class BatchDownloadDecision {
  final bool started;
  final Quality? quality;
  final DownloadConfig? config;
  final bool applyToAll;

  /// V2 reconcile: optional warning string (from FormatSelectionWarning
  /// converted via formatSelectionWarningMessage). Null in V2 auto-pick path.
  final String? warning;

  BatchDownloadDecision({
    required this.started,
    this.quality,
    this.config,
    this.applyToAll = false,
    this.warning,
  });
}

/// Mixin that provides all single-URL download logic for HomeScreen.
///
/// Extracted from HomeScreenState to reduce file size.
/// Requires the host class to expose certain fields via abstract getters/setters.
mixin HomeDownloadMixin {
  // ── Required abstract accessors (provided by HomeScreenState) ──

  /// Riverpod ref - provided by ConsumerState
  WidgetRef get ref;

  /// Whether this State is currently mounted
  bool get mounted;

  /// The BuildContext of the widget
  BuildContext get context;

  TextEditingController get urlController;
  GlobalKey<FormState> get formKey;
  bool get isShowingDialog;
  set isShowingDialog(bool value);
  bool get bypassArchiveCheck;
  set bypassArchiveCheck(bool value);

  /// v2.2 Phase 2C reviewer-2: URL-scoped one-shot intent token.
  ///
  /// When set, `handleDownloadDecision` consumes (read+clear) it only
  /// when its videoInfo URL matches the stored URL. Bypasses
  /// `useManualMode` for THAT specific URL only — won't leak across
  /// downloads if extraction or early-return prevented decision running.
  String? get pendingDirectDownloadUrl;
  set pendingDirectDownloadUrl(String? value);
  String? get pendingForceConfigDialogUrl;
  set pendingForceConfigDialogUrl(String? value);

  /// v2.2 Phase 2D.1 reviewer-7 P3: id-based completion watch set,
  /// implemented as a `Map<int, DateTime>` on the host. Mixin calls
  /// [registerPopupOriginatedDownloadId] after a successful
  /// `startDownloadWithQuality` so the host's listener can fire
  /// `setActionResult(PopupActionCompleted)` when this exact download
  /// (not "any download with the same URL") transitions to Completed.
  void registerPopupOriginatedDownloadId(int id);

  Set<String> get autoLoginAttemptedUrls;
  Set<String> get autoLoginCookieRetryAttemptedUrls;
  Set<String> get autoLoginInFlightUrls;

  /// RC8.3 — per-session set tracking which failed download IDs have
  /// already been auto-retried after an auth flow. Prevents infinite
  /// loop if the retry ALSO fails with loginRequired (e.g.,
  /// extractor classification misfire or cookies still rejected).
  /// Per Codex correction: gate retries by download id here rather
  /// than make loginRequired globally isRetryable.
  Set<int> get authRetryAttemptedDownloadIds;

  String _activePresetDownloadDescription(ActivePresetState state) {
    final baseName =
        state.activePreset.name.trim().isEmpty
            ? state.activeId
            : state.activePreset.name.trim();
    if (!state.isModified) return baseName;
    return '$baseName (${_presetConfigSummary(state.currentConfig)})';
  }

  String _presetConfigSummary(FormatPresetExtended preset) {
    final rawFormat = preset.containerFormat.trim().toLowerCase();
    final format =
        rawFormat.isEmpty || rawFormat == 'auto'
            ? 'auto'
            : rawFormat.toUpperCase();

    if (preset.audioOnly) {
      final bitrate = preset.audioBitrate;
      return bitrate == null ? format : '$format ${bitrate}kbps';
    }

    final quality =
        preset.maxResolution > 0 ? '${preset.maxResolution}p' : 'best';
    return '$format $quality';
  }

  /// Provided by [HomeBatchDownloadMixin] on the same host class. Used
  /// by the smart-routing path in [startDownload] to dispatch a list of
  /// URLs (e.g. coming back from the channel/playlist sheet) into the
  /// existing batch flow without duplicating logic here.
  ///
  /// When [playlistId] is non-null the batch was kicked off from a
  /// `YouTubePlaylistSheet` — every successfully created download gets
  /// stamped with this id (+ optional [playlistTitle]) so the sidebar
  /// `FilterTab.playlist` and grouped popover light up automatically.
  Future<void> handleBatchDownload(
    List<String> urls, {
    String? playlistId,
    String? playlistTitle,
  });

  /// Queued extraction result when dialog is already showing.
  /// Processed after the current dialog closes.
  VideoInfo? _queuedVideoInfo;

  // ── Auto-login flow ──

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

  /// Auto-login flow: detect platform -> show login dialog -> retry extraction with cookies.
  /// Only triggers once per URL to prevent infinite retry loops.
  Future<void> handleAutoLogin(String url) async {
    if (autoLoginInFlightUrls.contains(url)) {
      appLogger.debug('[Login] Auto-login already in flight for $url');
      return;
    }

    // Guard: only attempt auto-login once per URL
    if (autoLoginAttemptedUrls.contains(url)) {
      if (mounted) {
        AppSnackBar.error(
          context,
          message: AppLocalizations.errorFeedbackHint('loginRequired'),
        );
      }
      return;
    }

    autoLoginInFlightUrls.add(url);
    try {
      // If the user has already completed in-app login, do not force the
      // browser dialog again. Refresh/export the saved cookie record once and
      // retry extraction directly. If that still fails with loginRequired, the
      // next pass falls through to the actual login dialog.
      if (!autoLoginCookieRetryAttemptedUrls.contains(url)) {
        final cookiesFile = await _readFreshCookiesFileForUrl(url);
        if (!mounted) return;
        if (cookiesFile != null) {
          autoLoginCookieRetryAttemptedUrls.add(url);
          _retryExtractionAfterLogin(url, cookiesFile);
          return;
        }
      }

      await _showLoginAndRetryExtraction(url);
    } finally {
      autoLoginInFlightUrls.remove(url);
    }
  }

  Future<String?> _readFreshCookiesFileForUrl(String url) async {
    try {
      ref.invalidate(cookiesFileForUrlProvider(url));
      return await ref.read(cookiesFileForUrlProvider(url).future);
    } catch (e) {
      appLogger.warning('Cookie export failed, retrying without auth: $e');
      return null;
    }
  }

  Future<void> _showLoginAndRetryExtraction(String url) async {
    final platform = PlatformDetector.detectPlatform(url);
    final loginUrl = PlatformDetector.getLoginUrl(platform);

    if (loginUrl == null) {
      if (mounted) {
        AppSnackBar.error(
          context,
          message: AppLocalizations.errorFeedbackHint('loginRequired'),
        );
      }
      return;
    }

    autoLoginAttemptedUrls.add(url);

    final success = await showPlatformLoginDialog(
      context: context,
      platform: platform.name,
      loginUrl: loginUrl,
    );

    if (!success || !mounted) return;

    // Get cookies and retry extraction
    final cookiesFile = await _readFreshCookiesFileForUrl(url);
    if (!mounted) return;
    _retryExtractionAfterLogin(url, cookiesFile);
  }

  void _retryExtractionAfterLogin(String url, String? cookiesFile) {
    if (!mounted) return;

    // Auto retry extraction. The retry path must mirror the manual path's
    // full param set — `cookiesFromBrowser` (Chrome/Firefox/Safari import
    // toggle) and `proxyUrl` (rotation-aware) — otherwise platforms that
    // require browser cookies or proxied egress will fail again with the
    // same loginRequired classification and we'll have wasted the user's
    // login flow. resolveActiveProxy() picks the rotation pool entry when
    // proxyList is non-empty, else falls back to the single proxyUrl
    // setting — same logic the manual extraction uses.
    final settings = ref.read(settingsProvider);
    ref
        .read(extractionProvider.notifier)
        .startExtraction(
          url: url,
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
          proxyUrl: resolveActiveProxy(ref),
        );

    // RC8.3 of Ultra Plan v3 — also retry the original failed
    // download row(s). Pre-RC8.3, the extraction re-ran (above) and
    // the user saw a fresh quality picker — but the ORIGINAL failed
    // download row stayed in `Failed` status forever (audit found
    // this leaves users confused; they expect the row they clicked
    // retry on to actually retry).
    //
    // Find any rows with the same source URL that are currently
    // Failed AND were classified as loginRequired (the only class
    // that auto-login resolves). Skip rows already retried in this
    // session via `authRetryAttemptedDownloadIds` (Codex's loop
    // guard — gate by id, NOT by global isRetryable flag, because
    // that flag would also affect manual retries and create
    // open-ended loops). The retry call goes through
    // `_buildRetryPlanFromSettings` which reads cookiesFile via the
    // same provider this auto-login flow just invalidated, so the
    // retry plan carries the fresh cookies automatically.
    // RC10 Blocker 1 of Codex spec — retry filter expanded:
    //   - Accept cookieDbLocked as auth-resolvable (in-app login
    //     captures cookies to a FILE; the retry then uses cookiesFile
    //     not browser DB, sidestepping the lock entirely).
    //   - Match normalized URL across both `download.url` and
    //     `download.sourceUrl` (yt-dlp engine commonly persists the
    //     resolved URL on `url` with `sourceUrl` blank; rust engine
    //     uses `sourceUrl` for the user-pasted URL).
    final downloadsState = ref.read(downloadsNotifierProvider);
    for (final download in downloadsState.downloads) {
      if (download.status != DownloadStatus.failed) continue;
      // Match either field via shared URL normalizer so query-string
      // noise (utm_*, fbclid, fragments, trailing slash) doesn't
      // produce false negatives.
      final urlMatches =
          UrlNormalizer.same(download.url, url) ||
          UrlNormalizer.same(download.sourceUrl, url);
      if (!urlMatches) continue;
      if (authRetryAttemptedDownloadIds.contains(download.id)) continue;
      final errorCode =
          download.errorCode ??
          DownloadErrorClassifier.classifyMessage(download.errorMessage ?? '');
      // Both error codes resolve via in-app login + cookie file:
      //   - loginRequired: extractor needs auth cookies
      //   - cookieDbLocked: yt-dlp couldn't copy browser DB; in-app
      //     login writes a fresh cookies file that bypasses the lock
      final isAuthResolvable =
          errorCode == DownloadErrorCode.loginRequired ||
          errorCode == DownloadErrorCode.cookieDbLocked;
      if (!isAuthResolvable) continue;
      authRetryAttemptedDownloadIds.add(download.id);
      appLogger.info(
        '🔁 [Auth] Auto-retrying failed download ${download.id} '
        '(errorCode=${errorCode.name}) after auth flow captured '
        'fresh cookies for $url',
      );
      unawaited(
        ref.read(downloadsNotifierProvider.notifier).retryDownload(download.id),
      );
    }
  }

  // ── Extraction pending result handling ──

  /// Check if there's a pending extraction result and show dialog.
  void checkPendingExtraction() {
    final extractionState = ref.read(extractionProvider);

    // Show error if extraction failed
    if (extractionState.hasError && mounted) {
      final error = extractionState.error!;
      final errorCode = DownloadErrorClassifier.classifyMessage(error);
      final failedUrl = extractionState.extractingUrl;
      ref.read(extractionProvider.notifier).clearError();

      // Auto-navigate to in-app browser login when cookies are
      // genuinely required AND the extraction wasn't already a
      // PO-Token / cookie-DB-locked artefact. Phase 3 (Codex review
      // 2026-05-13): `loginRequired` is also the surface yt-dlp
      // emits when it cannot read the browser cookie DB (issue 7271)
      // — bouncing the user into the in-app login screen at that
      // point misleads them ("I AM logged in… why does it ask
      // again?"). The browser-fallback-chain in
      // `_extractWithYtdlp` / `StartDownloadUseCase` already
      // exhausts the candidate list before this routing fires, so
      // if we still see `loginRequired` here AND no chain candidate
      // surfaced the more specific `cookieDbLocked` text on the
      // way, the user genuinely needs to authenticate.
      //
      // `cookieDbLocked` is short-circuited to the snackbar path
      // with a targeted hint instead of the login flow — the fix
      // is "close the named browser" / "let the chain advance",
      // not "log in again".
      if (errorCode == DownloadErrorCode.loginRequired && failedUrl != null) {
        handleAutoLogin(failedUrl);
        return;
      }

      AppSnackBar.error(
        context,
        message: AppLocalizations.errorFeedbackHint(errorCode.name),
        duration: failedUrl != null ? const Duration(seconds: 6) : null,
        action:
            failedUrl != null
                ? SnackBarAction(
                  label: AppLocalizations.batchOpsRetry,
                  onPressed: () {
                    urlController.text = failedUrl;
                    startDownload();
                  },
                )
                : null,
      );
      return;
    }

    // Show dialog if extraction completed
    if (extractionState.hasPendingResult && !isShowingDialog) {
      showPendingResultDialog(extractionState.pendingVideoInfo!);
    }
  }

  /// Show dialog for pending extraction result.
  /// If a dialog is already showing, queues the result for display after the current dialog closes.
  Future<void> showPendingResultDialog(VideoInfo videoInfo) async {
    if (!mounted) return;

    final extractionNotifier = ref.read(extractionProvider.notifier);
    if (isShowingDialog) {
      // Queue instead of drop — will be processed after current dialog closes
      _queuedVideoInfo = videoInfo;
      appLogger.info(
        '📋 Queued extraction result (dialog active): ${videoInfo.title}',
      );
      return;
    }

    isShowingDialog = true;
    appLogger.info('📋 Showing pending extraction result: ${videoInfo.title}');

    try {
      final downloadStarted = await handleDownloadDecision(videoInfo);

      // Clear input if download started
      if (downloadStarted) {
        urlController.clear();

        if (mounted) {
          AppSnackBar.success(
            context,
            message: AppLocalizations.homeDownloadStarted(videoInfo.title),
          );
        }
      }
    } finally {
      isShowingDialog = false;
      // Clear pending result regardless of outcome
      extractionNotifier.clearPendingResult();

      // Process queued result if any
      if (_queuedVideoInfo != null && mounted) {
        final queued = _queuedVideoInfo!;
        _queuedVideoInfo = null;
        // Schedule after current frame to avoid re-entrant dialog issues
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) showPendingResultDialog(queued);
        });
      }
    }
  }

  // ── Download start flow ──

  /// Resolve the optimal numSegments for the next download.
  ///
  /// When [adaptiveSegments] is enabled, computes segments from current
  /// aggregate throughput of active downloads.  Falls back to the user's
  /// manual [maxSegments] setting when disabled or when there is no
  /// bandwidth signal yet (aggregateThroughput == 0 on the first download).
  int resolveNumSegments(SettingsState settings) {
    if (!settings.adaptiveSegments) return settings.maxSegments;
    final downloads = ref.read(downloadsNotifierProvider).downloads;
    final bps = NetworkThroughputMonitor.aggregateThroughput(downloads);
    final segments =
        bps > 0
            ? AdaptiveSegmentService.computeOptimalSegments(bps)
            : settings.maxSegments; // No signal yet -> use manual setting
    appLogger.info(AdaptiveSegmentService.logMessage(segments, bps));
    return segments;
  }

  /// Non-blocking extract and download flow.
  /// Extraction runs in background via provider - user can navigate freely.
  /// Uses cache for instant re-extraction of same URL.
  Future<void> startDownload() async {
    final raw = urlController.text.trim();

    // Smart classify before validation. Routes keyword text +
    // channel/playlist URLs to the right sheet so the user never sees
    // a "URL không hợp lệ" error for a perfectly valid search query.
    final smartType = const UrlClassifierService().classify(raw);
    switch (smartType) {
      case SmartInputType.empty:
        // Let validate() surface the empty-field message.
        break;
      case SmartInputType.searchKeyword:
        // YouTube is the only search-capable platform exposed today —
        // TikTok / IG / X don't have a search-by-keyword sheet. Keyword
        // text always opens the YouTube search sheet; if the user wants
        // a different platform they paste the URL directly.
        await YouTubeSearchSheet.show(
          context,
          initialKeyword: raw,
          onVideoSelected: (videoUrl) {
            urlController.text = videoUrl;
            startDownload();
          },
        );
        return;
      case SmartInputType.channel:
        // The dedicated channel sheet only knows YouTube's API today.
        // TikTok / IG / FB / X channel URLs paste-routed here would
        // open an empty / errored sheet — degraded UX. Fall through to
        // single-URL extraction (yt-dlp natively expands a channel URL
        // into its recent uploads, surfaced via the existing decision
        // dialog) for non-YouTube hosts. When dedicated per-platform
        // sheets land, swap this guard for a registry lookup.
        if (PlatformDetector.detectPlatform(raw) == VideoPlatform.youtube) {
          await YouTubeChannelSheet.show(
            context,
            initialUrl: raw,
            onDownloadSelected: (urls) async {
              await handleBatchDownload(urls);
            },
          );
          return;
        }
        break;
      case SmartInputType.playlist:
        // Same reasoning as `channel` — playlist sheet is YouTube-only.
        // Non-YouTube playlist-shaped URLs (rare; mostly Spotify-style
        // share links) fall through to single-URL extraction.
        if (PlatformDetector.detectPlatform(raw) == VideoPlatform.youtube) {
          await YouTubePlaylistSheet.show(
            context,
            initialUrl: raw,
            onDownloadSelected: (urls, {playlistId, playlistTitle}) async {
              await handleBatchDownload(
                urls,
                playlistId: playlistId,
                playlistTitle: playlistTitle,
              );
            },
          );
          return;
        }
        break;
      case SmartInputType.unsupportedUrl:
        // The CTA reads "Mở trình duyệt" — honor that promise instead
        // of falling through to extract (which would fail on a URL we
        // can't process). Spec §6.2: macOS / Linux open the URL in
        // the in-app browser tab; Windows defers to the system
        // browser via url_launcher because webview_flutter has no
        // Windows support.
        if (Platform.isWindows) {
          final uri = Uri.tryParse(raw);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        } else {
          ref.read(browserTabsProvider.notifier).addTab(url: raw);
          ref
              .read(navigationProvider.notifier)
              .navigateToTab(NavigationConstants.browserIndex);
        }
        return;
      case SmartInputType.multipleUrls:
        // CTA reads "Tải hàng loạt N" — dispatch to the existing batch
        // pipeline ([HomeBatchDownloadMixin.handleBatchDownload]) which
        // owns premium-gating, dedupe, resume-skip and per-URL
        // extraction. The classifier already validated that ≥2 URL-
        // shaped tokens exist; reuse its tokenizer so detection and
        // dispatch share the same regex (no "counted 3, split into 1"
        // drift). The empty-list branch should never fire in practice
        // — classify() returned multipleUrls only after seeing ≥2
        // tokens — so any drift is a bug worth surfacing rather than
        // silently feeding the multi-line raw text to single-URL
        // extraction (which would emit a confusing yt-dlp error two
        // seconds later).
        final urls = const UrlClassifierService().extractUrlTokens(raw);
        if (urls.isEmpty) {
          if (mounted) {
            AppSnackBar.error(
              context,
              message: AppLocalizations.homeUrlInvalid,
            );
          }
          return;
        }
        await handleBatchDownload(urls);
        return;
      case SmartInputType.singleVideo:
        // Fall through to existing single-URL extract + download flow.
        break;
    }

    if (!formKey.currentState!.validate()) return;

    final url = urlController.text.trim();
    ref.read(analyticsServiceProvider).track('url_pasted', {
      'platform': _detectPlatform(url),
    });
    final extractionNotifier = ref.read(extractionProvider.notifier);
    final extractionState = ref.read(extractionProvider);

    // Reset auto-login guard for new manual extraction attempt
    autoLoginAttemptedUrls.remove(url);
    autoLoginCookieRetryAttemptedUrls.remove(url);
    autoLoginInFlightUrls.remove(url);

    // Don't start if already extracting
    if (extractionState.isExtracting) {
      AppSnackBar.info(
        context,
        message: AppLocalizations.homeExtractionInProgress,
      );
      return;
    }

    // 2026-05-26 Codex spec — all duplicate gating removed from the
    // user-initiated Home path. RC10 Codex-round-3 removed the
    // pre-extraction URL-only archive check; this round removed the
    // post-quality `DownloadIntentKey.findDuplicateAmong` gate too
    // (see `startDownloadWithQuality`). Re-downloading the same URL
    // at the same quality is no longer a UX interruption — the
    // datasource's `_moveFilesToOutputDir` applies a shared ` (N)`
    // suffix when the destination exists, so each download lands as
    // a distinct file (`video.mp4`, `video (1).mp4`, ...). Archive
    // Mode (`settings.archiveEnabled`, default false) remains a
    // power-user opt-in via yt-dlp's own `--download-archive`.
    final settings = ref.read(settingsProvider);

    // Check cache first for instant extraction
    final cachedInfo = await ref
        .read(extractionHistoryProvider.notifier)
        .getCachedAsync(url);
    if (!mounted) return;
    if (cachedInfo != null) {
      appLogger.info(
        '⚡ [Cache] Using cached extraction for: ${cachedInfo.title}',
      );
      // Show dialog immediately with cached data
      final downloadStarted = await handleDownloadDecision(cachedInfo);
      if (!mounted) return;
      if (downloadStarted) {
        urlController.clear();
        if (mounted) {
          AppSnackBar.success(
            context,
            message: AppLocalizations.homeDownloadStarted(cachedInfo.title),
          );
        }
      }
      return;
    }

    // Debug log settings
    appLogger.info(
      '⚙️ [Settings] Engine: ${settings.downloadEngine.displayName}',
    );

    // Get cookies for this URL (if user is logged in to the platform)
    String? cookiesFile;
    try {
      cookiesFile = await ref.read(cookiesFileForUrlProvider(url).future);
      if (cookiesFile != null) {
        appLogger.info(
          '🍪 [Cookies] Found cookies for URL, using: $cookiesFile',
        );
      }
    } catch (e) {
      appLogger.debug('🍪 [Cookies] No cookies available for this URL');
    }
    if (!mounted) return;

    // Get browser cookie import setting
    final cookiesFromBrowser = ref.read(cookiesFromBrowserProvider);
    final cookiesFromBrowserFallback = ref.read(
      cookiesFromBrowserFallbackProvider,
    );
    final cookiesFromBrowserFallbackChain = ref.read(
      cookiesFromBrowserFallbackChainProvider,
    );
    final stopOnLoginRequired = _shouldStopOnLoginRequiredForFirstLogin(
      url: url,
      cookiesFile: cookiesFile,
      cookiesFromBrowser: cookiesFromBrowser,
    );

    // Start extraction in background (non-blocking)
    // Result will be handled by listener in build()
    extractionNotifier.startExtraction(
      url: url,
      engine: settings.downloadEngine,
      cookiesFile: cookiesFile,
      cookiesFromBrowser: cookiesFile == null ? cookiesFromBrowser : null,
      cookiesFromBrowserFallback: cookiesFromBrowserFallback,
      cookiesFromBrowserFallbackChain: cookiesFromBrowserFallbackChain,
      proxyUrl: resolveActiveProxy(ref),
      stopOnLoginRequired: stopOnLoginRequired,
    );
  }

  // 2026-05-26 Codex spec P2 — `startDownloadBypassArchive` and
  // `showDuplicateDownloadDialog` removed. Both were sole-purpose
  // callers of the duplicate-gate flow that was removed in the same
  // commit; with no gate to bypass and no dialog to show, these
  // were orphan code (Codex round-2 P2 finding). The localization
  // keys `duplicateDownload.*` are kept in translations for
  // historical record + low-risk follow-up if a future audit
  // surface needs them (single source of truth, no behavior change
  // from keeping them).
  //
  // `bypassArchiveCheck` abstract getter/setter on the mixin contract
  // is intentionally preserved (line ~97) — it's mixin shape, not
  // dead code, and its implementing widget keeps the field. If a
  // future Archive Mode UI surface re-adds a "Download Anyway" path
  // it should consume the same flag.

  // ── Quality / preference decision logic ──

  /// Fire-and-forget preload for the first direct-URL quality.
  /// Called immediately after extraction so bytes are warm before the user
  /// finishes picking a quality.
  void triggerPreload(VideoInfo videoInfo) {
    final directQuality = videoInfo.availableQualities.firstWhere(
      (q) =>
          q.encryptedUrl.startsWith('https://') ||
          q.encryptedUrl.startsWith('http://'),
      orElse: () => videoInfo.availableQualities.first,
    );
    final url = directQuality.encryptedUrl;
    if (!url.startsWith('http')) {
      return; // yt-dlp scheme -- nothing to preload yet
    }
    final preloadService = ref.read(smartPreloadServiceProvider);
    preloadService.preload(url).ignore(); // fire-and-forget
  }

  /// v2.2 Phase 2C reviewer-2 P1c: emit popup Started banner ONLY after
  /// the download was actually enqueued. Called from every auto-pick
  /// branch in [handleDownloadDecision] (Rule 1 single, Rule 1.1 image,
  /// Rule 1.5 PresetMatched). When the popup is in pending phase awaiting
  /// outcome, this flips it to resultStarted and keeps the popup visible
  /// while downloading. When result is `notStarted` (premium/disk/concurrency
  /// guard), em emits Failed instead so the popup unlocks without lying.
  ///
  /// Fire-and-forget at the call site — IPC errors logged + swallowed
  /// because main-app download flow already succeeded; reporting failure
  /// to popup is best-effort UX.
  void _maybeEmitDirectDownloadStarted(
    bool forceDirectAutoPick,
    VideoInfo videoInfo,
    DownloadStartResult result,
  ) {
    if (!forceDirectAutoPick) return;
    // VideoInfo.title is non-nullable String — codex review-5 fix:
    // remove null-aware ?. + force-unwrap ! that flutter analyze flagged.
    final filename =
        videoInfo.title.isNotEmpty ? videoInfo.title : videoInfo.url;
    final popupResult =
        result.started
            ? PopupActionStarted(filename: filename)
            : PopupActionFailed(result.warning ?? 'Download not started');
    Future<void>(() async {
      try {
        await ref.read(floatingWindowProvider).setActionResult(popupResult);
      } catch (e, s) {
        appLogger.warning(
          '[Capture] setActionResult after direct download failed',
          e,
          s,
        );
      }
    });

    // Reviewer-7 P3 (id-based completion watch): when the download
    // actually started, find the just-created DownloadEntity by URL —
    // most recent matching entry is the one we just enqueued — and
    // register its id with the host so the completion-diff listener
    // can fire setActionResult(Completed) precisely for this id (not
    // any historical download with the same URL).
    if (!result.started) return;
    try {
      final downloads = ref.read(downloadsNotifierProvider).downloads;
      DownloadEntity? mostRecent;
      for (final d in downloads) {
        if (d.url != videoInfo.url) continue;
        if (mostRecent == null || d.id > mostRecent.id) mostRecent = d;
      }
      if (mostRecent != null) {
        registerPopupOriginatedDownloadId(mostRecent.id);
      }
    } catch (e, s) {
      appLogger.warning(
        '[Capture] registerPopupOriginatedDownloadId failed',
        e,
        s,
      );
    }
  }

  /// Show dialog for quality selection.
  /// Returns true if download started, false if cancelled.
  Future<bool> handleDownloadDecision(VideoInfo videoInfo) async {
    triggerPreload(videoInfo); // warm the cache while user picks quality
    final platform = PlatformDetector.detectPlatform(videoInfo.url);

    // v2.2 Phase 2D.0 (reviewer-6 policy decision): URL-scoped intent
    // token is still consumed here for telemetry / popup Started feedback,
    // but it NO LONGER overrides `useManualMode`. When the user enables
    // "Always show advanced dialog" globally that intent must apply to
    // popup-initiated downloads too — popup primary "Tải ngay" cannot
    // hide-bypass the user's explicit setting.
    //
    // Effect:
    //   - manualMode OFF: Rule 1.5 preset auto-pick fires the same as
    //     for any non-popup download. The token only flags the download
    //     as popup-originated for `_maybeEmitDirectDownloadStarted`.
    //   - manualMode ON: dialog opens regardless of token. Popup primary
    //     and "Tuỳ chọn…" converge on the dialog path — UI honesty.
    final tokenUrl = pendingDirectDownloadUrl;
    final popupOriginated =
        tokenUrl != null && UrlNormalizer.same(tokenUrl, videoInfo.url);
    if (tokenUrl != null) {
      pendingDirectDownloadUrl = null;
      if (popupOriginated) {
        appLogger.info(
          '[Capture] popup-originated download for $tokenUrl '
          '(manualMode preference still applies)',
        );
      } else {
        appLogger.info(
          '[Capture] direct download token URL mismatch '
          '(token=$tokenUrl, current=${videoInfo.url}); falling through',
        );
      }
    }
    final forceDialogUrl = pendingForceConfigDialogUrl;
    final forceConfigDialog = forceDialogUrl != null;
    if (forceDialogUrl != null) {
      pendingForceConfigDialogUrl = null;
      if (UrlNormalizer.same(forceDialogUrl, videoInfo.url)) {
        appLogger.info(
          '[Capture] popup More options forcing config dialog for '
          '$forceDialogUrl',
        );
      } else {
        appLogger.info(
          '[Capture] popup More options forcing config dialog after URL '
          'canonicalized (token=$forceDialogUrl, current=${videoInfo.url})',
        );
      }
    }
    // Renamed local to reflect new semantics — used by
    // `_maybeEmitDirectDownloadStarted` to gate popup feedback emission.
    final forceDirectAutoPick = popupOriginated;

    // Rule 1: Single item -> Auto-download (no dialog)
    if (!forceConfigDialog && videoInfo.availableQualities.length == 1) {
      appLogger.info('Single item detected -> auto-downloading');
      final r = await startDownloadWithQuality(
        videoInfo,
        videoInfo.availableQualities.first,
      );
      _maybeEmitDirectDownloadStarted(forceDirectAutoPick, videoInfo, r);
      // Reviewer-3 Fix 3: return reflects ACTUAL start status so callers
      // (e.g. URL-clear / success snackbar logic) don't treat a guarded
      // notStarted result as success.
      return r.started;
    }

    // Rule 1.1: Pure image galleries default to downloading every image.
    final allImagesQuality = GalleryDefaultQualitySelector.allImagesQuality(
      videoInfo,
    );
    if (!forceConfigDialog && allImagesQuality != null) {
      appLogger.info(
        'Pure image gallery detected -> auto-downloading all images',
      );
      final r = await startDownloadWithQuality(videoInfo, allImagesQuality);
      _maybeEmitDirectDownloadStarted(forceDirectAutoPick, videoInfo, r);
      return r.started;
    }

    // Rule 1.5: Active command preset (Spec §5.4 — chip popover drives
    // the download). Precedence per chốt:
    //
    //   explicit sheet choice > active command preset > platform saved
    //   preference > global settings
    //
    // Carousel + mixed-content videos still go through the picker
    // dialog because preset-based selection assumes one-quality-fits-all.
    // `block` fallback (PresetBlocked) bypasses Rule 2 and goes straight
    // to the picker dialog — when the user explicitly opted in to "do
    // not auto-download a different quality", silently picking a
    // saved-preference quality would violate their intent.
    // "Always show advanced dialog" mode (manual override). Skips the
    // entire preset auto-pick chain and falls straight to Rule 3 so
    // the user gets the legacy DownloadConfigDialog — full control
    // over codec / container / fps / subs / sponsor block / watermark.
    // Preserves the pre-V2 "super feature" surface for power users.
    final activePresetSnapshot = ref.read(activePresetProvider);
    // Phase 2D.0: manualMode honored regardless of popup origin. Floating
    // Capture "More options" also lands here as a one-shot force-dialog
    // intent, bypassing preset/saved-pref auto-pick for this URL only.
    final manualModeOn =
        forceConfigDialog || activePresetSnapshot.useManualMode;

    bool presetBlockedDialog = false;
    if (!manualModeOn && canApplySavedChoice(videoInfo)) {
      final preset = activePresetSnapshot.currentConfig;
      final presetDescription = _activePresetDownloadDescription(
        activePresetSnapshot,
      );
      final isPremiumForMatcher = ref.read(isPremiumProvider);
      final outcome = PresetQualityMatcher.match(
        preset: preset,
        available: videoInfo.availableQualities,
        videoPlatform: platform,
        isPremium: isPremiumForMatcher,
      );
      switch (outcome) {
        case PresetMatched(quality: final matched):
          appLogger.info(
            'Auto-downloading via active preset "$presetDescription" → '
            '${matched.qualityText}',
          );
          final presetConfig = buildConfigFromPreset(preset, matched);
          // Surface the auto-pick the same way Rule 2 does — without a
          // SnackBar the user has no signal Rule 1.5 fired and can't
          // tell whether the preset overrode a savedPref they expected.
          // Wording lane is GPT 5.5; the placeholder string here is a
          // mechanical parity with `homeAutoDownloading` and should be
          // i18n-keyed once the UI agent specs the final copy.
          if (mounted) {
            AppSnackBar.success(
              context,
              message: AppLocalizations.homeAutoDownloadingByPreset(
                presetDescription,
                matched.qualityText,
              ),
              action: SnackBarAction(
                label: AppLocalizations.commonEdit,
                textColor: Theme.of(context).colorScheme.inversePrimary,
                onPressed: () async {
                  if (!mounted) return;
                  await DownloadConfigDialog.show(
                    context,
                    videoInfo,
                    PlatformDetector.detectPlatform(videoInfo.url),
                  );
                },
              ),
              duration: const Duration(seconds: 5),
            );
          }
          final r = await startDownloadWithQuality(
            videoInfo,
            matched,
            config: presetConfig,
            basePathOverride: preset.saveLocation,
          );
          _maybeEmitDirectDownloadStarted(forceDirectAutoPick, videoInfo, r);
          return r.started;
        case PresetBlocked():
          // Honour explicit-block intent: skip Rule 2 (savedPref auto-
          // download would silently violate the contract) and fall
          // straight to Rule 3 (dialog) so the user picks consciously.
          appLogger.info(
            'Active preset "${preset.name}" blocked auto-pick '
            '(fallbackBehavior=block, no exact match) — surfacing dialog',
          );
          presetBlockedDialog = true;
          break;
        case PresetScopeMismatch():
          // Preset is scoped to a different platform than this URL
          // (e.g. user activated "📌 TikTok (đã lưu)" then pasted a
          // YouTube URL). The preset has no opinion — fall through to
          // Rule 2 so platform-savedPref / dialog handle this video.
          // No regression vs pre-V2: legacy savedPref Rule 2 still
          // auto-applies when set for this platform.
          appLogger.info(
            'Active preset "${preset.name}" scoped to '
            '${preset.platformScope} but URL platform is '
            '${platform.toDbString()} — falling through to Rule 2',
          );
          break;
        case PresetNoCandidate():
          // Fall through to Rule 2 — no preset signal to honour.
          break;
      }
    }

    // Rule 2: Check saved preference (non-carousel, non-mixed). Skipped
    // when Rule 1.5 returned PresetBlocked so the explicit-block intent
    // is honoured all the way to the picker dialog. Also skipped when
    // manualMode is on — the user explicitly asked for the dialog, so
    // a savedPref auto-apply would defeat that intent (bypass dialog).
    final savedPref =
        (manualModeOn || presetBlockedDialog)
            ? null
            : ref
                .read(platformPreferencesProvider.notifier)
                .getPreference(platform);
    if (savedPref != null && canApplySavedChoice(videoInfo)) {
      // Find matching quality
      final matchingQuality = videoInfo.availableQualities.firstWhere(
        (q) =>
            q.qualityText == savedPref.qualityText &&
            q.mediaType == savedPref.mediaType,
        orElse: () => videoInfo.availableQualities.first,
      );

      // Build config from saved preference's format overrides
      final prefConfig = buildConfigFromPreference(savedPref, matchingQuality);

      appLogger.info(
        'Using saved preference for ${platform.displayName}: ${savedPref.qualityText}',
      );
      if (mounted) {
        AppSnackBar.success(
          context,
          message: AppLocalizations.homeAutoDownloading(
            videoInfo.title,
            platform.displayName,
          ),
          action: SnackBarAction(
            label: AppLocalizations.commonEdit,
            textColor: Theme.of(context).colorScheme.inversePrimary,
            onPressed: () => editSavedPreference(videoInfo, platform),
          ),
          duration: const Duration(seconds: 5),
        );
      }
      // Reviewer-3 Fix 2: Rule 2 was missing _maybeEmit so popup stayed
      // pending 8s when saved-preference auto-pick succeeded. Direct
      // download primary action also covers Rule 2's auto-pick path.
      final r = await startDownloadWithQuality(
        videoInfo,
        matchingQuality,
        config: prefConfig,
      );
      _maybeEmitDirectDownloadStarted(forceDirectAutoPick, videoInfo, r);
      return r.started;
    }

    // Rule 3: Show config dialog
    final config = await DownloadConfigDialog.show(
      context,
      videoInfo,
      platform,
    );

    if (config != null && config.selectedQualities.isNotEmpty) {
      return await startDownloadWithConfig(videoInfo, config);
    }

    return false; // User cancelled
  }

  /// Open config dialog to edit saved preference (without starting a new download).
  /// Called from the "Edit" action on the auto-download SnackBar.
  Future<void> editSavedPreference(
    VideoInfo videoInfo,
    VideoPlatform platform,
  ) async {
    if (!mounted) return;

    final config = await DownloadConfigDialog.show(
      context,
      videoInfo,
      platform,
    );
    if (config == null || config.selectedQualities.isEmpty) return;

    // Update the saved preference with user's new choice
    final quality = config.selectedQualities.first;
    try {
      await ref
          .read(platformPreferencesProvider.notifier)
          .savePreference(
            platform: platform,
            qualityText: quality.qualityText,
            mediaType: quality.mediaType,
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
      if (mounted) {
        AppSnackBar.success(
          context,
          message: AppLocalizations.homePreferenceSaved(
            platform.displayName,
            quality.qualityText,
          ),
        );
      }
    } catch (e, stack) {
      appLogger.error('Failed to update platform preference', e, stack);
    }
  }

  /// Check if saved choice can be applied.
  /// Don't apply for carousel or mixed content.
  bool canApplySavedChoice(VideoInfo videoInfo) {
    // Don't apply for carousel
    if (videoInfo.isCarousel) return false;

    // Don't apply for mixed content (images + videos)
    final hasImages = videoInfo.availableQualities.any(
      (q) => q.mediaType == MediaType.image,
    );
    final hasVideos = videoInfo.availableQualities.any(
      (q) => q.mediaType == MediaType.video,
    );
    if (hasImages && hasVideos) return false;

    return true;
  }

  /// Build DownloadConfig from saved PlatformQualityPreference.
  /// Returns null if the preference has no format overrides.
  DownloadConfig? buildConfigFromPreference(
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

  /// Inverse of [buildConfigFromPreset] — converts a one-time
  /// [DownloadConfig] choice (typically what the user just picked in
  /// `DownloadConfigDialog`) into a persistable [FormatPresetExtended]
  /// so it can be saved via
  /// `ActivePresetController.addUserPreset` and surface in the chip
  /// popover for re-use.
  ///
  /// Mirrors the V2 design intent: the old dialog's "Save as
  /// preference" checkbox wrote per-platform records that were
  /// invisible from the home command bar. The new "Save as preset"
  /// flow (UI checkbox owned by the UI agent) uses this builder to
  /// promote the same choice into the user-wide preset store where
  /// it's discoverable.
  ///
  /// `name` is supplied by the caller (text field next to the save
  /// button — UI lane). `matchedQuality` is the Quality object the
  /// user chose; its `mediaType` and `tbr` drive `audioOnly` /
  /// `audioBitrate` derivation. ID is generated as a sortable timestamp
  /// + name hash so concurrent saves can't collide.
  FormatPresetExtended buildPresetFromConfig({
    required String name,
    required DownloadConfig config,
    required Quality matchedQuality,
  }) {
    final isAudio = matchedQuality.mediaType == MediaType.audio;
    final explicitAudioTarget =
        isAudio && config.qualityTarget?.fileType == DownloadFileType.audio
            ? config.qualityTarget
            : null;
    int? audioBitrate;
    if (isAudio) {
      audioBitrate =
          explicitAudioTarget?.targetBitrateKbps ?? matchedQuality.tbr?.round();
    }

    final pickedHeight =
        QualityResolutionParser.heightForQuality(matchedQuality) ?? 0;

    final containerFormat =
        explicitAudioTarget?.outputFormat ??
        config.containerFormatOverride?.toDbString() ??
        (isAudio ? 'mp3' : 'mp4');

    return FormatPresetExtended(
      id:
          'user_${DateTime.now().millisecondsSinceEpoch}_'
          '${name.hashCode.toRadixString(16)}',
      name: name,
      isBuiltIn: false,
      maxResolution: config.maxResolutionOverride ?? pickedHeight,
      videoCodec: config.videoCodecOverride?.toDbString() ?? 'auto',
      audioCodec: config.audioCodecOverride?.toDbString() ?? 'auto',
      containerFormat: containerFormat,
      fpsPreference: config.fpsOverride?.toDbString() ?? 'auto',
      audioOnly: isAudio,
      audioBitrate: audioBitrate,
      fallbackBehavior: FormatPresetFallback.nearest,
      saveLocation: null,
      subtitlesEnabled: config.subtitlesEnabled,
      embedThumbnail: config.embedThumbnail,
      embedMetadata: config.embedMetadata,
      embedChapters: config.embedChapters,
      schemaVersion: FormatPresetExtended.currentSchemaVersion,
      createdAt: DateTime.now(),
    );
  }

  /// Build a [DownloadConfig] from an active [FormatPresetExtended].
  ///
  /// Treats the literal `'auto'` token in codec / container / fps fields
  /// as "inherit from settings" — the override is left null and
  /// [startDownloadWithQuality] resolves the global setting via its
  /// existing `config?.resolveX(settings) ?? settings.X` fallback chain.
  /// `maxResolution == 0` (the auto / archive built-ins) is also treated
  /// as "no cap, use settings". Subtitle / embed flags pass through as
  /// nullable so the downstream resolver inherits when null.
  ///
  /// `saveLocation` is NOT carried in the returned [DownloadConfig] —
  /// it lives outside the codec/format axis. Callers apply it through
  /// `startDownloadWithQuality`'s `basePathOverride` param so the
  /// downstream `pathService.suggestSubdirectory` still nests by
  /// platform/mediaType (Spec §5.4 — per-preset folder, branded
  /// subdirectories preserved).
  DownloadConfig buildConfigFromPreset(
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

  // ── Batch download decision (single-item) ──

  /// Handle batch download decision (with apply-to-all support).
  Future<BatchDownloadDecision> handleBatchDownloadDecision(
    VideoInfo videoInfo, {
    required int remainingCount,
  }) async {
    if (!mounted) {
      return BatchDownloadDecision(started: false);
    }

    final platform = PlatformDetector.detectPlatform(videoInfo.url);

    // Rule 1: Single item -> Auto-download (no dialog)
    if (videoInfo.availableQualities.length == 1) {
      appLogger.info('Single item detected -> auto-downloading');
      await startDownloadWithQuality(
        videoInfo,
        videoInfo.availableQualities.first,
      );
      return BatchDownloadDecision(
        started: true,
        quality: videoInfo.availableQualities.first,
      );
    }

    // Same pure-image gallery default as the single-URL flow; batch should not
    // interrupt on every image carousel when the extractor already has an
    // explicit "all images" quality.
    final allImagesQuality = GalleryDefaultQualitySelector.allImagesQuality(
      videoInfo,
    );
    if (allImagesQuality != null) {
      appLogger.info(
        'Batch pure image gallery detected -> auto-downloading all images',
      );
      await startDownloadWithQuality(videoInfo, allImagesQuality);
      return BatchDownloadDecision(started: true, quality: allImagesQuality);
    }

    // Rule 1.5: Active command preset (mirror of single-URL flow). The
    // batch path does not have the platform-savedPref Rule 2 because
    // batch items typically span platforms; the preset is the only
    // user-controlled signal. Carousel + mixed-content guards via
    // canApplySavedChoice keep the dialog as escape hatch for the
    // ambiguous cases. PresetBlocked falls through to the dialog so the
    // user makes a conscious choice (the dialog's "Apply to all" then
    // amortises that decision across remaining items).
    //
    // No per-item SnackBar here — the batch summary at the end of
    // [HomeBatchDownloadMixin.handleBatchDownload] surfaces the
    // aggregate result instead. Per-item toasts would be spammy at
    // batch sizes.
    // Same manualMode short-circuit as the single-URL flow — when the
    // user wants the dialog, every batch item gets the dialog (the
    // dialog's "Apply to all" then amortises the choice across the
    // remaining items in the batch).
    final batchSnapshot = ref.read(activePresetProvider);
    if (!batchSnapshot.useManualMode && canApplySavedChoice(videoInfo)) {
      final preset = batchSnapshot.currentConfig;
      final presetDescription = _activePresetDownloadDescription(batchSnapshot);
      final isPremiumForBatch = ref.read(isPremiumProvider);
      final outcome = PresetQualityMatcher.match(
        preset: preset,
        available: videoInfo.availableQualities,
        videoPlatform: platform,
        isPremium: isPremiumForBatch,
      );
      if (outcome is PresetMatched) {
        final matched = outcome.quality;
        appLogger.info(
          'Batch auto-downloading via active preset "$presetDescription" → '
          '${matched.qualityText}',
        );
        final presetConfig = buildConfigFromPreset(preset, matched);
        await startDownloadWithQuality(
          videoInfo,
          matched,
          config: presetConfig,
          basePathOverride: preset.saveLocation,
        );
        return BatchDownloadDecision(
          started: true,
          quality: matched,
          config: presetConfig,
        );
      }
      // PresetBlocked + PresetNoCandidate → fall through to dialog.
    }

    // Show config dialog with "Apply to all" option
    final config = await DownloadConfigDialog.show(
      context,
      videoInfo,
      platform,
      remainingCount: remainingCount,
    );

    if (config != null && config.selectedQualities.isNotEmpty) {
      // Start downloads using config
      await startDownloadWithConfig(videoInfo, config);

      return BatchDownloadDecision(
        started: true,
        quality: config.selectedQualities.first,
        config: config,
        applyToAll: config.applyToAll,
      );
    }

    return BatchDownloadDecision(started: false);
  }

  // ── Core download execution ──

  /// Start download with selected quality.
  /// If [config] is provided, resolves format overrides from it; otherwise uses global settings.
  /// Set [skipQuotaCheck] when quota was already reserved by the caller (e.g. multi-quality batch).
  ///
  /// V2 reconcile: returns [DownloadStartResult] for PR #234 batch contract.
  /// `started=false` when premium gate / quota / duplicate / wifi / disk
  /// guards reject. `warning` carries the format-selector
  /// container-change disclosure (e.g. "Saved as MKV instead of MP4")
  /// when an auto-promotion happened — populated via the
  /// `onContainerChangeWarning` callback wired into `startUseCase`
  /// below. A snackbar is also emitted on the success path so the user
  /// sees the disclosure even if the caller drops the result.
  Future<DownloadStartResult> startDownloadWithQuality(
    VideoInfo videoInfo,
    Quality quality, {
    DownloadConfig? config,
    bool skipDuplicateCheck = false,
    bool skipQuotaCheck = false,
    String? basePathOverride,
  }) async {
    if (!ensurePremiumBootstrapReady()) {
      return const DownloadStartResult.notStarted();
    }

    ref.read(analyticsServiceProvider).track('quality_selected', {
      'quality': quality.qualityText,
      'platform': videoInfo.platform,
    });
    final startUseCase = ref.read(startDownloadUseCaseProvider);
    final settings = ref.read(settingsProvider);
    final isPremium = ref.read(isPremiumProvider);

    // ── Premium: quality cap (free tier: 1080p max) ──
    if (!isPremium) {
      final qualityHeight = QualityResolutionParser.heightForQuality(quality);
      if (qualityHeight != null &&
          qualityHeight > PremiumLimits.freeMaxResolutionP) {
        if (!mounted) return const DownloadStartResult.notStarted();
        appLogger.info(
          '🚫 [Premium] Quality ${qualityHeight}p exceeds free tier limit (${PremiumLimits.freeMaxResolutionP}p)',
        );
        await UpgradePromptDialog.showAndNavigate(
          context,
          ref,
          feature: PremiumFeature.highQuality4K,
        );
        return const DownloadStartResult.notStarted();
      }
    }

    // WiFi-only mode gate: block download if not on WiFi
    if (settings.wifiOnlyMode) {
      final networkMonitor = ref.read(networkMonitorServiceProvider);
      final onWifi = await networkMonitor.isWifi();
      if (!mounted) return const DownloadStartResult.notStarted();
      if (!onWifi) {
        AppSnackBar.warning(
          context,
          message: AppLocalizations.wifiOnlyNotOnWifi,
        );
        return const DownloadStartResult.notStarted();
      }
    }

    // Resolve branded save path. Precedence:
    //   1. [basePathOverride] — typically active preset's `saveLocation`
    //      (Spec §5.4: per-preset folder beats global setting).
    //   2. Global [downloadPathProvider] when set.
    //   3. OS Downloads dir, falling back to app documents dir.
    // The pathService.suggestSubdirectory layer below still nests by
    // platform/mediaType so users keep their library structured even
    // when preset.saveLocation is set ("Music" preset → ~/Music/YouTube
    // not ~/Music flat).
    final pathService = ref.read(downloadPathSuggestionServiceProvider);
    final platform = PlatformDetector.detectPlatform(videoInfo.url);
    final settingsPath = ref.read(downloadPathProvider);
    // PR #234 — dialog save-location picker (config.savePathOverride) wins
    // over preset.saveLocation. Order: dialog override > preset > settings >
    // OS-default.
    final dialogOverride = config?.savePathOverride;
    final basePath =
        (dialogOverride != null && dialogOverride.isNotEmpty)
            ? dialogOverride
            : (basePathOverride != null && basePathOverride.isNotEmpty)
            ? basePathOverride
            : (settingsPath.isNotEmpty
                ? settingsPath
                : (await getDownloadsDirectory())?.path ??
                    (await getApplicationDocumentsDirectory()).path);
    if (!mounted) return const DownloadStartResult.notStarted();
    final subdirectory = pathService.suggestSubdirectory(
      platform,
      quality.mediaType,
    );
    final savePath = await pathService.resolveAndCreate(basePath, subdirectory);
    if (!mounted) return const DownloadStartResult.notStarted();

    // Pre-check disk space if file size is known from extraction metadata
    final requiredBytes = quality.filesizeBytes ?? 0;
    if (requiredBytes > 0) {
      final hasSpace = await FileUtils.hasEnoughSpace(savePath, requiredBytes);
      if (!mounted) return const DownloadStartResult.notStarted();
      if (!hasSpace) {
        AppSnackBar.warning(
          context,
          message: AppLocalizations.homeInsufficientSpace,
        );
        return const DownloadStartResult.notStarted();
      }
    }

    // 2026-05-26 Codex spec — duplicate warning removed for user-
    // initiated Home downloads. UX rationale: "user muốn tải lại thì
    // cứ tải lại" — duplicate dialog was the source of false-positive
    // friction (same video at different quality, same audio at
    // different bitrate, retry-after-fail loops). The safety net is
    // now in `ytdlp_datasource._moveFilesToOutputDir`: when the
    // destination file exists, the batch gets a shared ` (N)` suffix
    // (`video.mp4` → `video (1).mp4`, sub/thumb sibling files follow
    // the same suffix). No overwrite, no data loss.
    //
    // The `skipDuplicateCheck` parameter is intentionally preserved
    // for callers that still pass it (gallery-dl batch path, future
    // refactor); it has become a no-op for Home but remains in the
    // signature to avoid churn in unrelated callsites.
    //
    // Power-user Archive Mode (`settings.archiveEnabled`, default
    // false) keeps its yt-dlp `--download-archive` flag — explicit
    // opt-in for users who DO want skip-on-archive behavior.

    // ── Premium: daily download quota (atomic check + reserve) ──
    if (!skipQuotaCheck) {
      final quotaNotifier = ref.read(downloadQuotaNotifierProvider.notifier);
      if (!quotaNotifier.tryConsume(isPremium: isPremium)) {
        if (!mounted) return const DownloadStartResult.notStarted();
        appLogger.info(
          '🚫 [Premium] Weekly limit reached (${quotaNotifier.currentPeriodCount()}/${PremiumLimits.freeWeeklyDownloads})',
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
        return const DownloadStartResult.notStarted();
      }
    }

    // Get cookies for this URL
    String? cookiesFile;
    try {
      cookiesFile = await ref.read(
        cookiesFileForUrlProvider(videoInfo.url).future,
      );
      if (cookiesFile != null) {
        appLogger.debug('🍪 [Download] Using cookies: $cookiesFile');
      }
    } catch (e) {
      appLogger.debug('🍪 [Download] No cookies available: $e');
    }
    if (!mounted) return const DownloadStartResult.notStarted();

    String? capturedContainerWarning;
    final startResult = await startUseCase(
      videoInfo: videoInfo,
      selectedQuality: quality,
      savePath: savePath,
      isPremium: isPremium,
      quotaAlreadyReserved: true,
      cookiesFile: cookiesFile,
      cookiesFromBrowser:
          cookiesFile == null ? ref.read(cookiesFromBrowserProvider) : null,
      cookiesFromBrowserFallbackChain: ref.read(
        cookiesFromBrowserFallbackChainProvider,
      ),
      onContainerChangeWarning: (warning) {
        // The use case fires this synchronously before yt-dlp launches
        // when the format selector auto-promotes the user's container
        // (e.g. MP4 → MKV at YouTube ≥1440p). Capture for return so
        // the surrounding flow can render a snackbar without coupling
        // domain-layer code to UI widgets.
        capturedContainerWarning = warning;
      },
      // Format preferences: resolve from config overrides or global settings
      videoCodecPreference:
          config?.resolveVideoCodec(settings) ?? settings.videoCodecPreference,
      audioCodecPreference:
          config?.resolveAudioCodec(settings) ?? settings.audioCodecPreference,
      audioBitrateKbps: config?.audioBitrateKbpsFor(quality),
      containerFormatPreference:
          config?.resolveContainerFormat(settings) ??
          settings.containerFormatPreference,
      fpsPreference: config?.resolveFps(settings) ?? settings.fpsPreference,
      // === P0 Features ===
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
      // === P1 Features ===
      forceRemux: config?.resolveForceRemux(settings) ?? settings.forceRemux,
      // === P2 Features ===
      tiktokRemoveWatermark:
          config?.resolveTiktokRemoveWatermark(settings) ??
          settings.tiktokRemoveWatermark,
      // === P3 Features ===
      // Use rotation if proxyList non-empty, else fall back to single proxyUrl
      proxyUrl: resolveActiveProxy(ref),
      geoBypass: settings.geoBypass,
      geoBypassCountry: settings.geoBypassCountry,
      archiveEnabled: settings.archiveEnabled,
      // RC10 Codex-round-5 — derive archive suffix from the same
      // DownloadIntentKey used for duplicate detection so archive
      // scoping cannot drift from duplicate detection (the round-3
      // suffix took quality/container/audio fields directly and
      // missed the section/chapter dimension, so a clip pull could
      // share an archive entry with the whole-video pull).
      archiveFile:
          settings.archiveEnabled
              ? '$savePath/.${BrandConfig.current.brand.name}_archive'
                  '${DownloadIntentKey.fromRequest(videoInfo: videoInfo, quality: quality, config: config, fallbackContainer: settings.containerFormatPreference, fallbackAudioCodec: settings.audioCodecPreference).archiveSuffix()}.txt'
              : null,
      dateAfter: settings.dateAfter,
      dateBefore: settings.dateBefore,
      minDuration: settings.minDuration,
      maxDuration: settings.maxDuration,
      // === Network Tuning ===
      socketTimeout: settings.socketTimeout,
      maxRetries: settings.maxRetries,
      httpChunkSizeMb: settings.httpChunkSizeMb,
      // === Multi-Segment Download ===
      numSegments: resolveNumSegments(settings),
      // === Output Filename Template ===
      filenameTemplate: settings.filenameTemplate,
      // === Custom Postprocessor Args ===
      customPostprocessorArgs: settings.customPostprocessorArgs,
      // === Section download ===
      sectionStartTime: config?.sectionStartTime,
      sectionEndTime: config?.sectionEndTime,
      selectedChapterRanges: config?.selectedChapterRanges,
    );

    final startException = startResult.exceptionOrNull;
    if (startException != null) {
      appLogger.error('Download start failed', startException);
      if (mounted) {
        AppSnackBar.error(
          context,
          message:
              '${AppLocalizations.commonError}: ${_downloadStartFailureMessage(startException)}',
        );
      }
      return const DownloadStartResult.notStarted();
    }

    appLogger.info('Download started successfully');

    // Auto-promotion disclosure: when the format selector swapped the
    // user's container preference (typically MP4 → MKV at YouTube
    // ≥1440p where the only audio is Opus), surface a snackbar BEFORE
    // returning so the user understands why their file landed with a
    // different extension. Stays a non-blocking info toast — the
    // download is already in flight at this point.
    if (capturedContainerWarning != null && mounted) {
      AppSnackBar.warning(context, message: capturedContainerWarning!);
    }

    return DownloadStartResult.started(capturedContainerWarning);
  }

  String _downloadStartFailureMessage(Exception exception) {
    final message = AppExceptionX.readableMessage(exception);
    final lower = message.toLowerCase();
    if (lower.contains('sqlite') ||
        lower.contains('database is locked') ||
        lower.contains('unable to open database file')) {
      return 'The download database is temporarily unavailable. Please try again in a moment.';
    }
    return message;
  }

  /// Start downloads from a DownloadConfig (multiple qualities + format overrides).
  /// Handles remember-for-platform and save-as-default.
  /// Returns true if at least one download started.
  Future<bool> startDownloadWithConfig(
    VideoInfo videoInfo,
    DownloadConfig config,
  ) async {
    if (!ensurePremiumBootstrapReady()) return false;

    final settings = ref.read(settingsProvider);
    final isPremium = ref.read(isPremiumProvider);
    int successCount = 0;
    int failCount = 0;

    // Block premium-only qualities before reserving quota, otherwise a free
    // user can burn daily slots on a selection that will never start.
    if (!isPremium) {
      for (final quality in config.selectedQualities) {
        final qualityHeight = QualityResolutionParser.heightForQuality(quality);
        if (qualityHeight != null &&
            qualityHeight > PremiumLimits.freeMaxResolutionP) {
          if (!mounted) return false;
          appLogger.info(
            '🚫 [Premium] Quality ${qualityHeight}p exceeds free tier limit (${PremiumLimits.freeMaxResolutionP}p)',
          );
          await UpgradePromptDialog.showAndNavigate(
            context,
            ref,
            feature: PremiumFeature.highQuality4K,
          );
          return false;
        }
      }
    }

    // Reserve quota for ALL selected qualities at once (atomic).
    // This prevents the race where quality #1 consumes the last slot
    // and quality #2 gets blocked — multi-quality = one user action.
    final quotaNotifier = ref.read(downloadQuotaNotifierProvider.notifier);
    final qualityCount = config.selectedQualities.length;
    if (!quotaNotifier.tryConsume(isPremium: isPremium, count: qualityCount)) {
      if (!mounted) return false;
      final remaining = quotaNotifier.remainingThisWeek(isPremium: isPremium);
      appLogger.info(
        '🚫 [Premium] Not enough quota for $qualityCount downloads ($remaining remaining)',
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
      return false;
    }

    // Track confirmed gallery-dl URLs to skip duplicate dialog for batch items
    final confirmedGalleryDlUrls = <String>{};

    for (final quality in config.selectedQualities) {
      try {
        final isGalleryDl = quality.encryptedUrl.startsWith('gallerydl:');
        final skipDup =
            isGalleryDl && confirmedGalleryDlUrls.contains(videoInfo.url);

        // Quota already reserved above — skip per-quality check
        await startDownloadWithQuality(
          videoInfo,
          quality,
          config: config,
          skipDuplicateCheck: skipDup,
          skipQuotaCheck: true,
        );
        if (!mounted) return successCount > 0;

        if (isGalleryDl) confirmedGalleryDlUrls.add(videoInfo.url);
        successCount++;
      } catch (e, stack) {
        failCount++;
        appLogger.error(
          'Failed to start download for ${quality.qualityText}',
          e,
          stack,
        );
      }
    }

    // Handle "Remember for platform" -- save first selected quality as preference
    if (config.rememberForPlatform && config.selectedQualities.isNotEmpty) {
      if (!mounted) return successCount > 0;
      final platform = PlatformDetector.detectPlatform(videoInfo.url);
      final quality = config.selectedQualities.first;
      try {
        await ref
            .read(platformPreferencesProvider.notifier)
            .savePreference(
              platform: platform,
              qualityText: quality.qualityText,
              mediaType: quality.mediaType,
              // PR #234 portable contract — persist so future downloads from
              // this platform resolve through FormatSelectorService rather
              // than the legacy quality-text match.
              fileType: config.fileType,
              qualityIntent: config.qualityIntent,
              qualityTarget: config.qualityTarget,
              // Save format overrides (null if same as global)
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
        appLogger.info(
          '💾 Saved preference for ${platform.displayName}: ${quality.qualityText}',
        );
        if (mounted) {
          AppSnackBar.success(
            context,
            message: AppLocalizations.homePreferenceSaved(
              platform.displayName,
              quality.qualityText,
            ),
          );
        }
      } catch (e, stack) {
        appLogger.error('Failed to save platform preference', e, stack);
        if (mounted) {
          AppSnackBar.error(
            context,
            message: AppLocalizations.homePreferenceSaveFailed,
          );
        }
      }
    }

    // Handle "Save as default"
    if (config.saveAsDefault && config.hasOverrides(settings)) {
      if (!mounted) return successCount > 0;
      final notifier = ref.read(settingsProvider.notifier);
      // PR #234 portable contract — persist file type / quality intent /
      // target as global defaults so the dialog opens with them next time.
      // Technical-stream intents are not portable across videos and are
      // skipped by the settings layer.
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
      if (config.subtitlesEnabled != null) {
        if (config.subtitlesEnabled != settings.subtitlesEnabled) {
          await notifier.toggleSubtitles();
        }
      }
      if (config.embedThumbnail != null) {
        if (config.embedThumbnail != settings.embedThumbnail) {
          await notifier.toggleEmbedThumbnail();
        }
      }
      if (config.embedMetadata != null) {
        if (config.embedMetadata != settings.embedMetadata) {
          await notifier.toggleEmbedMetadata();
        }
      }
      if (config.embedChapters != null) {
        if (config.embedChapters != settings.embedChapters) {
          await notifier.toggleEmbedChapters();
        }
      }
      if (config.sponsorBlockEnabled != null) {
        if (config.sponsorBlockEnabled != settings.sponsorBlockEnabled) {
          await notifier.toggleSponsorBlock();
        }
      }
      if (config.tiktokRemoveWatermark != null) {
        if (config.tiktokRemoveWatermark != settings.tiktokRemoveWatermark) {
          await notifier.toggleTiktokRemoveWatermark();
        }
      }
      appLogger.info('💾 Saved format overrides as global defaults');
    }

    // Show summary for multi-quality downloads
    if (config.selectedQualities.length > 1 && mounted) {
      final unit =
          successCount == 1
              ? AppLocalizations.homeFile
              : AppLocalizations.homeFiles;
      final message =
          failCount == 0
              ? AppLocalizations.homeStartedDownloading(successCount, unit)
              : 'Started $successCount/${config.selectedQualities.length} downloads ($failCount failed)';
      if (failCount == 0) {
        AppSnackBar.success(context, message: message);
      } else {
        AppSnackBar.warning(context, message: message);
      }
    }

    return successCount > 0;
  }

  // ── Clear dialogs ──

  /// Show confirmation dialog for clearing completed downloads.
  void showClearCompletedDialog() {
    final notifier = ref.read(downloadsNotifierProvider.notifier);
    final completedCount =
        ref
            .read(downloadsNotifierProvider)
            .downloads
            .where((d) => d.isCompleted)
            .length;

    if (completedCount == 0) {
      AppSnackBar.info(
        context,
        message: AppLocalizations.homeNoCompletedDownloads,
      );
      return;
    }

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(AppLocalizations.homeClearCompletedTitle),
            content: Text(
              AppLocalizations.homeClearCompletedMessage(completedCount),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.commonCancel),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  notifier.deleteCompletedDownloads();
                  if (mounted) {
                    AppSnackBar.success(
                      this.context,
                      message: AppLocalizations.homeCleared(completedCount),
                    );
                  }
                },
                child: Text(AppLocalizations.downloadsDeleteRecordOnly),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  notifier.deleteCompletedDownloads(deleteFiles: true);
                  if (mounted) {
                    AppSnackBar.success(
                      this.context,
                      message: AppLocalizations.homeDeleted(completedCount),
                    );
                  }
                },
                child: Text(AppLocalizations.downloadsDeleteFileAndRecord),
              ),
            ],
          ),
    );
  }

  /// Show confirmation dialog for clearing failed downloads.
  void showClearFailedDialog() {
    final notifier = ref.read(downloadsNotifierProvider.notifier);
    final failedCount =
        ref
            .read(downloadsNotifierProvider)
            .downloads
            .where((d) => d.isFailed)
            .length;

    if (failedCount == 0) {
      AppSnackBar.info(
        context,
        message: AppLocalizations.homeNoFailedDownloads,
      );
      return;
    }

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(AppLocalizations.homeClearFailedTitle),
            content: Text(AppLocalizations.homeClearFailedMessage(failedCount)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.commonCancel),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  notifier.deleteFailedDownloads();
                  if (mounted) {
                    AppSnackBar.success(
                      this.context,
                      message: AppLocalizations.homeCleared(failedCount),
                    );
                  }
                },
                child: Text(AppLocalizations.downloadsDeleteRecordOnly),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  notifier.deleteFailedDownloads(deleteFiles: true);
                  if (mounted) {
                    AppSnackBar.success(
                      this.context,
                      message: AppLocalizations.homeDeleted(failedCount),
                    );
                  }
                },
                child: Text(AppLocalizations.downloadsDeleteFileAndRecord),
              ),
            ],
          ),
    );
  }

  bool ensurePremiumBootstrapReady() {
    if (ref.read(premiumBootstrapReadyProvider)) return true;
    appLogger.info(
      '⏳ [Premium] Download blocked while premium state initializes',
    );
    if (mounted) {
      AppSnackBar.info(
        context,
        message: AppLocalizations.homeCheckingPremiumLicense,
      );
    }
    return false;
  }

  /// Detect platform from URL for analytics.
  static String _detectPlatform(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('youtube.com') || lower.contains('youtu.be')) {
      return 'youtube';
    }
    if (lower.contains('tiktok.com')) return 'tiktok';
    if (lower.contains('instagram.com')) return 'instagram';
    if (lower.contains('facebook.com') || lower.contains('fb.watch')) {
      return 'facebook';
    }
    if (lower.contains('twitter.com') || lower.contains('x.com')) {
      return 'twitter';
    }
    if (lower.contains('reddit.com')) return 'reddit';
    if (lower.contains('vimeo.com')) return 'vimeo';
    if (lower.contains('twitch.tv')) return 'twitch';
    if (lower.contains('pinterest.com')) return 'pinterest';
    if (lower.contains('soundcloud.com')) return 'soundcloud';
    return 'other';
  }
}
