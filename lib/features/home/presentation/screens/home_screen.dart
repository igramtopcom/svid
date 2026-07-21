import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/auth/presentation/widgets/platform_login_dialog.dart';
import '../../../../core/binaries/binary_manager.dart';
import '../../../../core/binaries/binary_type.dart';
import '../../../../core/core.dart';
import '../../../downloads/presentation/providers/download_providers.dart'
    show downloadRepositoryProvider, ratingTriggerProvider;
import '../../../downloads/presentation/providers/batch_selection_provider.dart';
import '../../../downloads/presentation/providers/downloads_notifier.dart';
import '../../../downloads/presentation/providers/filter_provider.dart';
import '../../../downloads/presentation/providers/extraction_provider.dart';
import '../../../downloads/presentation/providers/extraction_cache_provider.dart';
import '../../../downloads/presentation/providers/playlist_library_provider.dart';
import '../../../downloads/domain/entities/download_entity.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../player/presentation/providers/player_providers.dart';
import '../../../player/presentation/providers/playback_queue_providers.dart';
import '../widgets/glassmorphism_header.dart';
import '../widgets/batch_operations_bar.dart';
import '../widgets/downloads_list.dart';
import '../widgets/download_list_helpers.dart';
import '../../../../core/navigation/navigation_constants.dart';
import '../../../../core/navigation/right_panel_provider.dart';
import '../widgets/filter_chips.dart';
import '../widgets/playlist_library_view.dart';
import '../../../downloads/presentation/widgets/playlist_progress_indicator.dart';
import '../../../downloads/presentation/providers/filtered_downloads_provider.dart';
import '../../../downloads/presentation/providers/user_playlist_memberships_provider.dart';
import '../../../downloads/presentation/providers/user_playlists_provider.dart';
import '../../../downloads/domain/services/download_error_classifier.dart';
import '../../../downloads/domain/entities/download_error_code.dart';
import 'dart:async';
import 'package:path/path.dart' as p;

import '../../../downloads/domain/entities/download_status.dart';
import '../../../floating_capture/domain/entities/capture_download_request.dart';
import '../../../floating_capture/domain/entities/popup_action_result.dart';
import '../../../floating_capture/presentation/providers/floating_capture_providers.dart';
import '../../../floating_capture/presentation/providers/pending_capture_open_in_app_provider.dart';
import '../widgets/home_screen_banners.dart';
import '../widgets/history_drawer_wrapper.dart';
import '../widgets/batch_url_import_dialog.dart';
import '../../../premium/domain/entities/premium_feature.dart';
import '../../../premium/domain/entities/premium_limits.dart';
import '../../../premium/presentation/providers/premium_providers.dart';
import '../../../premium/presentation/widgets/upgrade_prompt_dialog.dart';
import '../../../support/presentation/widgets/rating_dialog.dart';
import 'home_download_mixin.dart';
import 'home_batch_download_mixin.dart';

/// Home Screen - All-in-one view with downloads
/// Design: Modern glassmorphism UI with real-time updates
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => HomeScreenState();
}

enum _DownloadManagerView { history, playlist }

class HomeScreenState extends ConsumerState<HomeScreen>
    with HomeDownloadMixin, HomeBatchDownloadMixin {
  final _urlController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _urlFocusNode = FocusNode();
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  String? _lastClipboardContent;
  bool _showAutoPasteIndicator = false;
  bool _isShowingDialog = false; // Prevent duplicate dialogs
  bool _showHistoryDrawer = false;
  bool _showFilterDrawer = false; // Collapsible filter drawer
  bool _searchExpanded = false; // Narrow mode: search icon → expanded field
  _DownloadManagerView _downloadManagerView = _DownloadManagerView.history;
  String? _selectedPlaylistKey;
  bool _bypassArchiveCheck = false;

  /// v2.2 Phase 2C reviewer-2 fix: URL-scoped one-shot intent token.
  ///
  /// Was a `bool` — but `handleDownloadDecision` may never run (extraction
  /// failure, form invalid, archive duplicate, premium guard, ...) → flag
  /// would leak into the next user-initiated download and silently bypass
  /// their manualMode preference.
  ///
  /// Now stores the URL the popup primary action was clicked for. Consumed
  /// in `handleDownloadDecision` only when the URL matches; cleared on
  /// consume. Stale entries don't apply to other URLs.
  String? _pendingDirectDownloadUrl;

  /// Popup "More options" intent. When this URL reaches
  /// handleDownloadDecision, it must open DownloadConfigDialog even if the
  /// active preset or saved platform preference would normally auto-pick.
  String? _pendingForceConfigDialogUrl;

  /// v2.2 Phase 2D.1 (CPO feedback, reviewer-7 P3): tracks downloads
  /// originated from the floating popup BY downloadId so when status
  /// transitions to Completed em can fire `setActionResult(PopupActionCompleted)`.
  ///
  /// Was URL-keyed in earlier draft but URL is ambiguous: same URL can
  /// have multiple concurrent downloads (different qualities, retries,
  /// dialog cancel + re-issue). id is the unique key from
  /// `DownloadRepository.createDownload`.
  ///
  /// Populated by `home_download_mixin._maybeEmitDirectDownloadStarted`
  /// after a popup-originated `startDownloadWithQuality` returns
  /// `DownloadStartResult.started`. Evicted on completion fire OR after
  /// `_kPopupCompletionTtl` (30 min stale guard so the set cannot grow
  /// unbounded if the user pkills the app or downloads stall forever).
  final Map<int, DateTime> _popupOriginatedDownloadIds = {};

  /// yt-dlp extraction + actual download P99 ≈ 5 minutes for HD; budget
  /// 30 minutes to cover 4K + slow networks before treating an id as
  /// stale and dropping it.
  static const Duration _kPopupCompletionTtl = Duration(minutes: 30);

  /// Tracks the last-known set of completed download IDs so we can spot
  /// new completions (id transitions Pending/Downloading → Completed)
  /// rather than re-fire on every state-notifier rebuild.
  ///
  /// Reviewer-7 P2 fix: seeded eagerly in initState via `ref.read` BEFORE
  /// the listener is attached so a download that completes between the
  /// popup click and the first listener tick doesn't get classified as
  /// "baseline" and skipped.
  late Set<int> _knownCompletedIds;
  final Set<String> _autoLoginAttemptedUrls =
      {}; // Prevent infinite auto-login retry
  final Set<String> _autoLoginCookieRetryAttemptedUrls =
      {}; // Retry once with saved cookies before showing login
  final Set<String> _autoLoginInFlightUrls =
      {}; // Collapse duplicate loginRequired listeners for the same URL
  // RC8.3 of Ultra Plan v3 — per-session guard so a failed download
  // is auto-retried AT MOST ONCE after the auto-login flow captures
  // fresh cookies. Without this, a loginRequired classification that
  // happens to misfire (e.g., transient extractor change classified
  // as login) would loop endlessly. Per Codex correction: DO NOT
  // make loginRequired globally isRetryable; gate retries by download
  // id here instead.
  final Set<int> _authRetryAttemptedDownloadIds = {};

  // ── Mixin interface (HomeDownloadMixin) ──

  @override
  TextEditingController get urlController => _urlController;
  @override
  GlobalKey<FormState> get formKey => _formKey;
  @override
  bool get isShowingDialog => _isShowingDialog;
  @override
  set isShowingDialog(bool value) => _isShowingDialog = value;
  @override
  bool get bypassArchiveCheck => _bypassArchiveCheck;
  @override
  set bypassArchiveCheck(bool value) => _bypassArchiveCheck = value;
  @override
  String? get pendingDirectDownloadUrl => _pendingDirectDownloadUrl;
  @override
  set pendingDirectDownloadUrl(String? value) =>
      _pendingDirectDownloadUrl = value;
  @override
  String? get pendingForceConfigDialogUrl => _pendingForceConfigDialogUrl;
  @override
  set pendingForceConfigDialogUrl(String? value) =>
      _pendingForceConfigDialogUrl = value;
  @override
  void registerPopupOriginatedDownloadId(int id) {
    _popupOriginatedDownloadIds[id] = DateTime.now();
  }

  @override
  Set<String> get autoLoginAttemptedUrls => _autoLoginAttemptedUrls;
  @override
  Set<String> get autoLoginCookieRetryAttemptedUrls =>
      _autoLoginCookieRetryAttemptedUrls;
  @override
  Set<String> get autoLoginInFlightUrls => _autoLoginInFlightUrls;
  @override
  Set<int> get authRetryAttemptedDownloadIds => _authRetryAttemptedDownloadIds;

  @override
  void initState() {
    super.initState();
    _urlFocusNode.addListener(_onFocusChanged);
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_onSearchFocusChanged);
    // Reviewer-7 P2 fix: seed completion-baseline NOW from the current
    // downloads snapshot so the first listener tick after a popup click
    // (which may already see the download as Completed if it finishes
    // very fast or was already done) treats every prior completion as
    // baseline + every NEW completion as a transition to fire on.
    _knownCompletedIds =
        ref
            .read(downloadsNotifierProvider)
            .downloads
            .where((d) => d.status == DownloadStatus.completed)
            .map((d) => d.id)
            .toSet();
    // Deferred init tasks (need ref access)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Auto-paste clipboard on init if setting enabled
      if (ref.read(settingsProvider).autoClipboardDetection) {
        _checkClipboard();
      }
      checkPendingExtraction();

      // Phase 1B.2: pick up "Open in SSvid" clicks on non-video URLs
      // from the floating capture popup (spec Q18). Download clicks are
      // routed by AppScaffold so System PiP cannot unmount their consumer.
      // Open-in-app still belongs here because it only needs the visible URL
      // field, not the background direct-download path.
      ref.listenManual<String?>(pendingCaptureOpenInAppProvider, (_, next) {
        if (next == null || next.isEmpty || !mounted) return;
        ref.read(pendingCaptureOpenInAppProvider.notifier).state = null;
        _handleCaptureOpenInApp(next);
      }, fireImmediately: true);
    });
  }

  Future<void> handleCaptureDownloadRequest(
    CaptureDownloadRequest request,
  ) async {
    if (!mounted) return;
    _urlController.text = request.preview.rawUrl;
    _urlController.selection = TextSelection.collapsed(
      offset: request.preview.rawUrl.length,
    );
    // Phase 2D.2 (anh Quân Windows feedback): do NOT poison
    // `_lastClipboardContent` here. Setting it would make any subsequent
    // manual focus-paste of the SAME URL silently no-op because
    // `_checkClipboard` compares `clipboardText != _lastClipboardContent`.
    // The field is reserved for auto-paste history of clipboard pulls,
    // NOT popup-routed URLs.

    // v2.2 Phase 2C reviewer-2: set URL-scoped intent tokens (NOT bools).
    // Download Now uses the direct token for popup Started/Completed
    // feedback; More options uses forceConfigDialog so it always opens the
    // config dialog instead of being swallowed by preset/saved-pref auto-pick.
    if (request.directDownload) {
      _pendingDirectDownloadUrl = request.preview.rawUrl;
      _pendingForceConfigDialogUrl = null;
    } else {
      _pendingDirectDownloadUrl = null;
      _pendingForceConfigDialogUrl = request.preview.rawUrl;
    }

    // Reviewer-7 P3: id-based registration moved into
    // `_maybeEmitDirectDownloadStarted` (executed after createDownload
    // returns the new download id). URL-keyed registration here was
    // ambiguous when the same URL has multiple concurrent / retry
    // downloads.

    // v2.2 Phase 2C reviewer-2 P1c FIX: do NOT fire setActionResult(Started)
    // here. startDownload() can early-return for ~10 reasons (form invalid,
    // archive duplicate, premium guard, etc.) before any actual enqueue.
    // Optimistic Started would lie to the user. The Started banner is now
    // emitted from inside handleDownloadDecision after the createDownload
    // call returns started=true (see home_download_mixin.dart Rule 1.5).
    //
    // The popup is in `pending` phase right now (entered when user clicked
    // Tải ngay) and will auto-recover to `idle` after 8s if no result fires
    // — so the user gets unlocked even when startDownload silently aborts.
    await startDownload();
  }

  void _handleCaptureOpenInApp(String url) {
    if (!mounted) return;
    setState(() {
      _urlController.text = url;
      _urlController.selection = TextSelection.collapsed(offset: url.length);
      // Phase 2D.2: same reasoning as `handleCaptureDownloadRequest` — popup
      // routing must not poison the clipboard-history field.
    });
    _urlFocusNode.requestFocus();
  }

  /// v2.2 Phase 2D.1 (reviewer-7 P2 + P3): detect downloads transitioning
  /// to Completed and, when the id is in `_popupOriginatedDownloadIds`,
  /// fire `setActionResult(PopupActionCompleted)` so the popup re-emerges
  /// with the saved filename + path.
  ///
  /// id-keyed (not URL-keyed) to handle the same URL having multiple
  /// concurrent downloads (different qualities, retries). Diff-based via
  /// `_knownCompletedIds` (seeded eagerly in initState) so a download that
  /// was already Completed before the click doesn't get classified as
  /// "new" on the first listener tick.
  void _emitPopupCompletedForNewlyFinished(
    DownloadsState? previous,
    DownloadsState next,
  ) {
    // Evict popup-watch entries older than TTL so the map cannot grow
    // unbounded across long sessions where the user clicks Tải ngay
    // but the download fails / cancels / stalls.
    final now = DateTime.now();
    _popupOriginatedDownloadIds.removeWhere(
      (_, t) => now.difference(t) > _kPopupCompletionTtl,
    );

    final currentCompleted =
        next.downloads
            .where((d) => d.status == DownloadStatus.completed)
            .map((d) => d.id)
            .toSet();

    final newlyCompleted = currentCompleted.difference(_knownCompletedIds);
    _knownCompletedIds = currentCompleted;

    if (newlyCompleted.isEmpty) return;
    if (_popupOriginatedDownloadIds.isEmpty) return;

    for (final id in newlyCompleted) {
      if (!_popupOriginatedDownloadIds.containsKey(id)) continue;
      final entity = next.downloads.firstWhere(
        (d) => d.id == id,
        orElse: () => next.downloads.first,
      );
      if (entity.id != id) continue;

      _popupOriginatedDownloadIds.remove(id);
      // Reviewer-7 P5: proper path join via package:path. Was naive
      // string concat with `.replaceAll('//', '/')` which would break
      // on Windows backslashes and double-collapse legitimate `//` in
      // paths (e.g. SMB shares).
      final savedFullPath = p.join(entity.savePath, entity.filename);
      unawaited(
        ref
            .read(floatingWindowProvider)
            .setActionResult(
              PopupActionCompleted(
                filename: entity.filename,
                savedPath: savedFullPath,
              ),
            )
            .catchError((Object e, StackTrace s) {
              appLogger.warning(
                '[Capture] setActionResult Completed failed',
                e,
                s,
              );
              return null;
            }),
      );
    }
  }

  void _handleFailedDownloadRouting(
    DownloadsState? previous,
    DownloadsState next,
  ) {
    // RC8.2 of Ultra Plan v3 — Pre-RC8.2 this listener only routed
    // `loginRequired` (auto-open login dialog). cookieDbLocked,
    // jsRuntimeUnavailable, and accessDenied silently dropped — user
    // saw the failed badge in activity center but no actionable hint.
    // The extraction path (home_download_mixin.dart) already routes
    // these correctly; this listener catches the download-time
    // counterpart and reaches feature parity.
    //
    // Riverpod can deliver the persisted DB snapshot after the
    // listener is attached. Those rows are history, not a fresh
    // failure transition, and must not pop a dialog/snackbar on
    // app launch.
    if (previous == null) return;

    final previousById = <int, DownloadEntity>{
      for (final download in previous.downloads) download.id: download,
    };

    for (final download in next.downloads) {
      if (download.status != DownloadStatus.failed) continue;

      final previousDownload = previousById[download.id];
      if (previousDownload == null) continue;
      if (previousDownload.status == DownloadStatus.failed) continue;

      final errorCode =
          download.errorCode ??
          DownloadErrorClassifier.classifyMessage(download.errorMessage ?? '');
      if (download.url.isEmpty) continue;

      switch (errorCode) {
        case DownloadErrorCode.loginRequired:
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            unawaited(handleAutoLogin(download.url));
          });
        case DownloadErrorCode.cookieDbLocked:
          // RC10.5 of Ultra Plan v3 — when Chrome/Edge's cookie DB
          // is locked (yt-dlp issue 7271), telling the user to "close
          // the browser" is unhelpful UX. The app has an in-app
          // PlatformLoginDialog that exports cookies via WebView,
          // which sidesteps the browser DB lock entirely.
          //
          // Detect platform; if it has marker-guard support
          // (RC8.1 added TikTok/Reddit/Pinterest to the existing
          // YouTube/FB/IG/X set), auto-trigger `handleAutoLogin`
          // — same machinery as `loginRequired` routing (RC8.3) so
          // post-login auto-retries the failed download by ID.
          //
          // Three guard sets prevent infinite loops:
          //   - autoLoginAttemptedUrls   → once per URL per session
          //   - autoLoginInFlightUrls    → dedupe concurrent listeners
          //   - authRetryAttemptedDownloadIds → once per download id
          //
          // Unsupported platforms (random domain, unknown extractor)
          // keep the legacy snackbar-only behavior — opening a
          // login dialog for an unknown site has no benefit.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            // RC10 Codex-round-2 catch 6 — yt-dlp engine rows often
            // store the canonical URL on `download.url` with
            // `sourceUrl` blank (the gallery-dl path uses sourceUrl,
            // engine path uses url). Detecting platform off
            // `download.url` alone misclassifies rows that only
            // have a sourceUrl; pick whichever is non-empty so the
            // auto-login routing fires for both shapes.
            final effectiveAuthUrl =
                download.sourceUrl.isNotEmpty
                    ? download.sourceUrl
                    : download.url;
            final platform = PlatformDetector.detectPlatform(effectiveAuthUrl);
            final hasInAppLogin = PlatformLoginDialog.authMarkers.containsKey(
              platform.name.toLowerCase(),
            );
            if (hasInAppLogin &&
                !autoLoginAttemptedUrls.contains(effectiveAuthUrl)) {
              // Reuse the same flow loginRequired uses (RC8.3).
              // Post-login `_retryExtractionAfterLogin` will retry
              // the failed download(s) by id, carrying the freshly
              // captured cookie file (RC1 file > browser precedence
              // means cookieDbLocked is impossible on the retry —
              // file cookies skip the Chrome DB entirely).
              unawaited(handleAutoLogin(effectiveAuthUrl));
            } else {
              AppSnackBar.error(
                context,
                message: AppLocalizations.errorFeedbackHint(errorCode.name),
                duration: const Duration(seconds: 6),
              );
            }
          });
        case DownloadErrorCode.jsRuntimeUnavailable:
          // Deno/Node missing on path. Fire BinaryManager repair (idempotent
          // via in-flight dedupe) AND surface a snackbar so the user knows
          // what's happening. Repair is fire-and-forget; if it succeeds
          // the next retry will succeed; if it fails the user still has
          // the snackbar message.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            unawaited(BinaryManager().triggerRepair(BinaryType.deno));
            AppSnackBar.error(
              context,
              message: AppLocalizations.errorFeedbackHint(errorCode.name),
              duration: const Duration(seconds: 6),
            );
          });
        case DownloadErrorCode.accessDenied:
          // 403 / geo / age / private — all collapsed to accessDenied
          // today (coarse). Surface the hint; do NOT trigger login
          // (login doesn't fix geo block or removed video).
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            AppSnackBar.error(
              context,
              message: AppLocalizations.errorFeedbackHint(errorCode.name),
              duration: const Duration(seconds: 6),
            );
          });
        default:
          // Other error codes already surfaced by the extraction
          // path or the activity-center failure card. No extra
          // routing here.
          break;
      }
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _urlFocusNode.removeListener(_onFocusChanged);
    _urlFocusNode.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ── Public methods (called from AppScaffold via GlobalKey) ──

  /// Public method to focus URL input field (called from +New button)
  void focusUrl() {
    _urlFocusNode.requestFocus();
  }

  /// Public method to focus search field (called from keyboard shortcut)
  void focusSearch() {
    _searchFocusNode.requestFocus();
  }

  /// Public method to check clipboard on window focus
  void checkClipboardOnWindowFocus() {
    _checkClipboard();
  }

  /// Public method to set a URL and immediately start download (called from YouTube search)
  Future<void> setUrlAndStart(String url) async {
    _urlController.text = url;
    _urlController.selection = TextSelection.collapsed(offset: url.length);
    await startDownload();
  }

  /// Public method for Cmd+Shift+V / Ctrl+Shift+V: paste clipboard URL and auto-start
  Future<void> pasteUrlAndStart() async {
    try {
      final text = (await ClipboardService.getText())?.trim() ?? '';
      if (text.isEmpty) return;
      _urlController.text = text;
      _urlController.selection = TextSelection.collapsed(offset: text.length);
      _lastClipboardContent = text;
      await startDownload();
    } catch (e) {
      appLogger.debug('Paste URL and start failed: $e');
    }
  }

  // ── Clipboard handling ──

  /// Clipboard auto-detect when focus changes
  void _onFocusChanged() {
    if (_urlFocusNode.hasFocus &&
        ref.read(settingsProvider).autoClipboardDetection) {
      _checkClipboard();
    }
  }

  /// Check clipboard and auto-paste if valid NEW URL detected.
  /// Replaces existing URL if clipboard has a different valid URL.
  Future<void> _checkClipboard() async {
    try {
      final clipboardText = (await ClipboardService.getText())?.trim();

      if (clipboardText != null &&
          clipboardText.isNotEmpty &&
          clipboardText != _lastClipboardContent &&
          clipboardText != _urlController.text) {
        if (Validators.isLikelyMediaUrl(clipboardText)) {
          _applyClipboardText(clipboardText);
        }
      }
    } catch (e) {
      appLogger.debug('Clipboard check failed: $e');
    }
  }

  /// Manual paste from button - always pastes, bypasses guards
  Future<void> _manualPaste() async {
    try {
      final clipboardText = (await ClipboardService.getText())?.trim();

      if (clipboardText != null && clipboardText.isNotEmpty) {
        if (Validators.isDownloadableUrl(clipboardText)) {
          _applyClipboardText(clipboardText);
        }
      }
    } catch (e) {
      appLogger.debug('Manual paste failed: $e');
    }
  }

  /// Apply clipboard text to URL field with animation indicator
  void _applyClipboardText(String text) {
    setState(() {
      _urlController.text = text;
      _urlController.selection = TextSelection.collapsed(offset: text.length);
      _lastClipboardContent = text;
      _showAutoPasteIndicator = true;
    });
  }

  /// Called by header when animation completes - resets indicator
  void _onAutoPasteAnimationDone() {
    if (mounted) {
      setState(() => _showAutoPasteIndicator = false);
    }
  }

  /// Search changed listener -- delegates to FilterNotifier
  void _onSearchChanged() {
    ref
        .read(filterProvider.notifier)
        .updateSearchQuery(_searchController.text.trim());
  }

  /// Collapse search to icon when focus is lost and field is empty
  void _onSearchFocusChanged() {
    if (!_searchFocusNode.hasFocus && _searchController.text.isEmpty) {
      setState(() => _searchExpanded = false);
    }
  }

  // ── Batch URL import dialog ──

  void _showBatchDownloadDialog() async {
    if (!ensurePremiumBootstrapReady()) return;

    // Premium gate: batch import is premium-only
    final isPremium = ref.read(isPremiumProvider);
    if (!isPremium) {
      await UpgradePromptDialog.showAndNavigate(
        context,
        ref,
        feature: PremiumFeature.batchImport,
      );
      return;
    }

    final urls = await showBatchUrlImportDialog(context);
    if (urls != null && urls.isNotEmpty) {
      appLogger.info(
        '🎬 [Batch] Starting batch download for ${urls.length} URLs',
      );
      handleBatchDownload(urls);
    }
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final downloadsState = ref.watch(downloadsNotifierProvider);
    final filterState = ref.watch(filterProvider);
    final filteredDownloads = ref.watch(filteredDownloadsProvider);
    final playlistLibrary = ref.watch(playlistLibraryProvider);

    // Watch extraction state and handle changes
    final extractionState = ref.watch(extractionProvider);

    // Watch extraction history for badge count
    final historyEntries = ref.watch(extractionHistoryProvider);

    // Listen for extraction completion
    ref.listen<ExtractionState>(extractionProvider, (previous, next) {
      // Handle error
      if (next.hasError && previous?.error != next.error) {
        final errorCode = DownloadErrorClassifier.classifyMessage(next.error!);
        final failedUrl = next.extractingUrl;
        ref.read(extractionProvider.notifier).clearError();

        // v2.2 Phase 2C reviewer-3 Fix 1: extraction failure for the
        // direct-download URL → clear token + tell popup the action
        // failed so it leaves pending phase. Without this, retrying the
        // same URL re-uses the leftover token + bypasses manualMode in a
        // context where the user might prefer the dialog after a failure.
        if (failedUrl != null &&
            UrlNormalizer.same(failedUrl, _pendingDirectDownloadUrl)) {
          _pendingDirectDownloadUrl = null;
          final isAuthError = errorCode == DownloadErrorCode.loginRequired;
          final popupResult =
              isAuthError
                  ? const PopupActionAuthRequired()
                  : PopupActionFailed(
                    AppLocalizations.errorFeedbackHint(errorCode.name),
                  );
          // Fire-and-forget so listener stays sync.
          unawaited(
            ref
                .read(floatingWindowProvider)
                .setActionResult(popupResult)
                .catchError((Object e, StackTrace s) {
                  appLogger.warning(
                    '[Capture] setActionResult on extraction error failed',
                    e,
                    s,
                  );
                  return null;
                }),
          );
        }

        if (_pendingForceConfigDialogUrl != null &&
            (failedUrl == null ||
                UrlNormalizer.same(failedUrl, _pendingForceConfigDialogUrl))) {
          _pendingForceConfigDialogUrl = null;
        }

        // Auto-navigate to login if cookies required
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
                      _urlController.text = failedUrl;
                      startDownload();
                    },
                  )
                  : null,
        );
      }

      // Handle successful extraction - save to cache and show dialog
      if (next.hasPendingResult &&
          previous?.pendingVideoInfo != next.pendingVideoInfo) {
        // Atomically consume to prevent duplicate dialog from browser listener
        final videoInfo =
            ref.read(extractionProvider.notifier).consumePendingResult();
        if (videoInfo != null) {
          // Save to extraction cache for history
          ref
              .read(extractionHistoryProvider.notifier)
              .addExtraction(videoInfo.url, videoInfo);
          // Schedule dialog after current build frame to avoid build-phase conflicts
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) showPendingResultDialog(videoInfo);
          });
        }
      }
    });

    // v2.2 Phase 2D.1 (CPO feedback): watch downloads list for transitions
    // to Completed and re-emerge the floating popup with a Completed
    // banner (filename + savedPath) so the user sees the result inside
    // the popup chrome instead of just the system download notification.
    //
    // Reviewer-7 P3: id-keyed (NOT URL-keyed) — popup-originated downloads
    // are registered by id in `_popupOriginatedDownloadIds` after
    // `startDownloadWithQuality` returns the new entity. TTL eviction
    // keeps the map bounded across long sessions.
    ref.listen<DownloadsState>(downloadsNotifierProvider, (previous, next) {
      _emitPopupCompletedForNewlyFinished(previous, next);
      _handleFailedDownloadRouting(previous, next);
    });

    // Auto-trigger rating dialog after N successful downloads
    ref.listen<bool>(ratingTriggerProvider, (prev, shouldShow) {
      if (shouldShow && mounted) {
        ref.read(ratingTriggerProvider.notifier).state = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            showDialog(context: context, builder: (_) => const RatingDialog());
          }
        });
      }
    });

    final isExtracting = extractionState.isExtracting;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final hasDownloads = downloadsState.downloads.isNotEmpty;
    final isPlaylistManager =
        _downloadManagerView == _DownloadManagerView.playlist ||
        filterState.selectedTab == FilterTab.playlist;
    final selectedPlaylist =
        isPlaylistManager ? _selectedPlaylistFor(playlistLibrary) : null;
    final visibleDownloads = _visibleDownloadsForManager(
      filteredDownloads,
      selectedPlaylist: selectedPlaylist,
    );
    final visiblePlaylists = _visiblePlaylistsForManager(
      playlistLibrary,
      filterState,
    );
    final hasManagerFilter =
        filterState.hasActiveFilters ||
        filterState.selectedTab != FilterTab.all;
    final playlistEmpty =
        isPlaylistManager &&
        selectedPlaylist == null &&
        playlistLibrary.isEmpty &&
        !filterState.hasActiveFilters;
    final showNoResults =
        hasDownloads &&
        ((isPlaylistManager &&
                selectedPlaylist == null &&
                playlistLibrary.isNotEmpty &&
                visiblePlaylists.isEmpty) ||
            (visibleDownloads.isEmpty &&
                (!isPlaylistManager || selectedPlaylist != null))) &&
        hasManagerFilter &&
        !playlistEmpty;
    const lightHomeBg = Color(0xFFF9F9FF);
    final darkHomeBg = AppColors.homeDarkAppBg;

    return Scaffold(
      backgroundColor: isDark ? darkHomeBg : lightHomeBg,
      body: Stack(
        children: [
          // ── Background wash ──
          Positioned.fill(
            child: ColoredBox(color: isDark ? darkHomeBg : lightHomeBg),
          ),

          // ── Main content column ──
          LayoutBuilder(
            builder: (context, constraints) {
              final availableHeight =
                  constraints.hasBoundedHeight
                      ? constraints.maxHeight
                      : MediaQuery.sizeOf(context).height;
              final needsVerticalScroll = availableHeight < 620;

              final content = Column(
                children: [
                  // Box 1 — V2 hero command surface. The section caption
                  // ("Link hoặc từ khóa") lives INSIDE the card per the
                  // mockup so the card itself reads as one cohesive
                  // bounded zone. The outer Padding here just inset the
                  // card from the page edges.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.lg,
                      AppSpacing.xl,
                      AppSpacing.sm,
                    ),
                    child: GlassmorphismHeader(
                      urlController: _urlController,
                      urlFocusNode: _urlFocusNode,
                      formKey: _formKey,
                      isExtracting: isExtracting,
                      extractingUrl: extractionState.extractingUrl,
                      extractionStartedAt: extractionState.startedAt,
                      onDownload: startDownload,
                      onPaste: _manualPaste,
                      onAutoPasteAnimationDone: _onAutoPasteAnimationDone,
                      onHistoryTap: () {
                        // Refresh cache when opening drawer to ensure latest data
                        if (!_showHistoryDrawer) {
                          ref
                              .read(extractionHistoryProvider.notifier)
                              .refresh();
                        }
                        setState(
                          () => _showHistoryDrawer = !_showHistoryDrawer,
                        );
                      },
                      onBatchDownload: _showBatchDownloadDialog,
                      showAutoPasteIndicator: _showAutoPasteIndicator,
                      historyCount: historyEntries.length,
                    ),
                  ),

                  // 1b. Free tier quota indicator
                  _FreeQuotaIndicator(),

                  // 2. System banners (update, announcement, suggestion)
                  const UpdateBanner(),
                  const AnnouncementBanner(),

                  // 3. Download manager panel (tabs + toolbar + filters +
                  // list/grid in one bounded surface per Home V2 mockup).
                  Expanded(
                    child: _buildDownloadManagerPanel(
                      downloadsState,
                      filterState,
                      visibleDownloads,
                      isDark,
                      cs,
                      hasDownloads: hasDownloads,
                      visiblePlaylists: visiblePlaylists,
                      selectedPlaylist: selectedPlaylist,
                      playlistEmpty: playlistEmpty,
                      showNoResults: showNoResults,
                    ),
                  ),
                ],
              );

              if (!needsVerticalScroll) return content;

              return SingleChildScrollView(
                child: SizedBox(height: 620, child: content),
              );
            },
          ),

          // Batch operations bar -- floats above content when items are selected
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: BatchOperationsBar(),
          ),

          // History Drawer (slides in from right with proper clipping)
          HistoryDrawerWrapper(
            isOpen: _showHistoryDrawer,
            onItemTap: (videoInfo) {
              setState(() => _showHistoryDrawer = false);
              handleDownloadDecision(videoInfo);
            },
            onClose: () => setState(() => _showHistoryDrawer = false),
          ),
        ],
      ),
    );
  }

  // ── Build helpers ──

  PlaylistLibraryItem? _selectedPlaylistFor(
    List<PlaylistLibraryItem> playlists,
  ) {
    final key = _selectedPlaylistKey;
    if (key == null) return null;
    for (final playlist in playlists) {
      if (playlist.key == key) return playlist;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selectedPlaylistKey != key) return;
      setState(() => _selectedPlaylistKey = null);
      ref.read(activePlaylistContextProvider.notifier).state = null;
    });
    return null;
  }

  List<PlaylistLibraryItem> _visiblePlaylistsForManager(
    List<PlaylistLibraryItem> playlists,
    FilterState filterState,
  ) {
    Iterable<PlaylistLibraryItem> result = playlists;

    if (filterState.searchQuery.isNotEmpty) {
      final query = filterState.searchQuery.toLowerCase();
      result = result.where((playlist) {
        if (playlist.title.toLowerCase().contains(query)) return true;
        return playlist.downloads.any(
          (download) =>
              download.displayTitle.toLowerCase().contains(query) ||
              download.filename.toLowerCase().contains(query) ||
              (download.uploader?.toLowerCase().contains(query) ?? false) ||
              (download.userNote.isNotEmpty &&
                  download.userNote.toLowerCase().contains(query)),
        );
      });
    }

    if (filterState.selectedPlatform != null) {
      final platform = filterState.selectedPlatform!.toDbString();
      result = result.where(
        (playlist) => playlist.downloads.any((d) => d.platform == platform),
      );
    }

    if (filterState.statusFilters.isNotEmpty) {
      result = result.where(
        (playlist) => playlist.downloads.any(
          (download) => filterState.statusFilters.contains(download.status),
        ),
      );
    }

    if (filterState.watchFilter != WatchFilter.all) {
      final watchService = ref.read(watchProgressServiceProvider);
      result = result.where(
        (playlist) => playlist.downloads.any((download) {
          return switch (filterState.watchFilter) {
            WatchFilter.watched => download.isWatched,
            WatchFilter.watching =>
              !download.isWatched &&
                  (watchService.getWatchFraction(download.id) ?? 0) > 0,
            WatchFilter.unwatched =>
              !download.isWatched &&
                  (watchService.getWatchFraction(download.id) ?? 0) == 0,
            WatchFilter.all => true,
          };
        }),
      );
    }

    return result.toList(growable: false);
  }

  List<DownloadEntity> _visibleDownloadsForManager(
    List<DownloadEntity> filteredDownloads, {
    PlaylistLibraryItem? selectedPlaylist,
  }) {
    if (selectedPlaylist == null) {
      return filteredDownloads;
    }
    final filteredIds = filteredDownloads.map((d) => d.id).toSet();
    return selectedPlaylist.downloads
        .where((d) => filteredIds.contains(d.id))
        .toList();
  }

  void _openPlaylist(PlaylistLibraryItem playlist) {
    setState(() {
      _downloadManagerView = _DownloadManagerView.playlist;
      _selectedPlaylistKey = playlist.key;
    });
    ref.read(filterProvider.notifier).selectTab(FilterTab.playlist);
    ref.read(activePlaylistContextProvider.notifier).state = playlist.key;
  }

  void _closePlaylist() {
    setState(() => _selectedPlaylistKey = null);
    ref.read(activePlaylistContextProvider.notifier).state = null;
  }

  void _playPlaylist(PlaylistLibraryItem playlist) {
    if (playlist.downloads.isEmpty) return;
    setState(() {
      _downloadManagerView = _DownloadManagerView.playlist;
      _selectedPlaylistKey = playlist.key;
    });
    ref.read(filterProvider.notifier).selectTab(FilterTab.playlist);
    ref.read(playbackQueueProvider.notifier).setQueue(playlist.downloads);
    ref.read(activePlaylistContextProvider.notifier).state = playlist.key;
    ref.read(rightPanelProvider.notifier).showDetail(playlist.first);
  }

  Future<void> _createPlaylist() async {
    final title = await _showPlaylistNameDialog(
      title: AppLocalizations.playlistManageCreateTitle,
      initialValue: '',
      confirmLabel: AppLocalizations.playlistAddDialogCreateButton,
    );
    if (!mounted || title == null) return;

    final result = await ref
        .read(downloadRepositoryProvider)
        .createUserPlaylist(title);
    if (!mounted) return;
    result.when(
      success: (info) {
        setState(() {
          _downloadManagerView = _DownloadManagerView.playlist;
          _selectedPlaylistKey = null;
        });
        ref.read(filterProvider.notifier).selectTab(FilterTab.playlist);
        ref.read(activePlaylistContextProvider.notifier).state = null;
        _refreshUserPlaylistProviders();
        AppSnackBar.success(
          context,
          message: AppLocalizations.playlistManageCreated(info.title),
        );
      },
      failure:
          (e) => AppSnackBar.error(
            context,
            message: AppExceptionX.readableMessage(e),
          ),
    );
  }

  Future<void> _renamePlaylist(PlaylistLibraryItem playlist) async {
    if (playlist.kind != PlaylistLibraryKind.user) return;
    final nextTitle = await _showPlaylistNameDialog(
      title: AppLocalizations.playlistManageRenameTitle,
      initialValue: playlist.title,
      confirmLabel: AppLocalizations.commonSave,
    );
    if (!mounted || nextTitle == null) return;

    final result = await ref
        .read(downloadRepositoryProvider)
        .renameUserPlaylist(playlistId: playlist.id, title: nextTitle);
    if (!mounted) return;
    result.when(
      success: (_) {
        _refreshUserPlaylistProviders();
        AppSnackBar.success(
          context,
          message: AppLocalizations.playlistManageRenamed,
        );
      },
      failure:
          (e) => AppSnackBar.error(
            context,
            message: AppExceptionX.readableMessage(e),
          ),
    );
  }

  Future<void> _deletePlaylist(PlaylistLibraryItem playlist) async {
    if (playlist.kind != PlaylistLibraryKind.user) return;
    final confirmed = await AppConfirmDialog.show(
      context,
      title: AppLocalizations.playlistManageDeleteTitle,
      message: AppLocalizations.playlistManageDeleteMessage(playlist.title),
      confirmLabel: AppLocalizations.commonDelete,
      isDestructive: true,
    );
    if (!mounted || !confirmed) return;

    final result = await ref
        .read(downloadRepositoryProvider)
        .deleteUserPlaylist(playlist.id);
    if (!mounted) return;
    result.when(
      success: (_) {
        setState(() => _selectedPlaylistKey = null);
        ref.read(activePlaylistContextProvider.notifier).state = null;
        _refreshUserPlaylistProviders();
        AppSnackBar.success(
          context,
          message: AppLocalizations.playlistManageDeleted,
        );
      },
      failure:
          (e) => AppSnackBar.error(
            context,
            message: AppExceptionX.readableMessage(e),
          ),
    );
  }

  Future<void> _removeFromPlaylist(
    PlaylistLibraryItem playlist,
    DownloadEntity download,
  ) async {
    if (playlist.kind != PlaylistLibraryKind.user) return;
    final result = await ref
        .read(downloadRepositoryProvider)
        .removeFromUserPlaylist(
          playlistId: playlist.id,
          downloadId: download.id,
        );
    if (!mounted) return;
    result.when(
      success: (_) {
        _refreshUserPlaylistProviders();
        AppSnackBar.success(
          context,
          message: AppLocalizations.playlistManageRemoved,
        );
      },
      failure:
          (e) => AppSnackBar.error(
            context,
            message: AppExceptionX.readableMessage(e),
          ),
    );
  }

  Future<void> _movePlaylistItem(
    PlaylistLibraryItem playlist,
    DownloadEntity download,
    int delta,
  ) async {
    if (playlist.kind != PlaylistLibraryKind.user) return;
    final orderedIds = playlist.downloads.map((d) => d.id).toList();
    final from = orderedIds.indexOf(download.id);
    if (from < 0) return;
    final to = from + delta;
    if (to < 0 || to >= orderedIds.length) return;

    final moved = orderedIds.removeAt(from);
    orderedIds.insert(to, moved);

    final result = await ref
        .read(downloadRepositoryProvider)
        .reorderUserPlaylist(
          playlistId: playlist.id,
          orderedDownloadIds: orderedIds,
        );
    if (!mounted) return;
    result.when(
      success: (_) {
        _refreshUserPlaylistProviders();
        AppSnackBar.success(
          context,
          message: AppLocalizations.playlistManageOrderUpdated,
        );
      },
      failure:
          (e) => AppSnackBar.error(
            context,
            message: AppExceptionX.readableMessage(e),
          ),
    );
  }

  void _refreshUserPlaylistProviders() {
    ref.invalidate(userPlaylistsProvider);
    ref.invalidate(userPlaylistMembershipsProvider);
  }

  Future<String?> _showPlaylistNameDialog({
    required String title,
    required String initialValue,
    required String confirmLabel,
  }) async {
    final controller = TextEditingController(text: initialValue);
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setDialogState) {
              final trimmed = controller.text.trim();
              return AlertDialog(
                title: Text(title),
                content: TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: AppLocalizations.playlistAddDialogNameHint,
                  ),
                  onChanged: (_) => setDialogState(() {}),
                  onSubmitted:
                      trimmed.isEmpty
                          ? null
                          : (_) => Navigator.of(ctx).pop(trimmed),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(AppLocalizations.commonCancel),
                  ),
                  FilledButton(
                    onPressed:
                        trimmed.isEmpty
                            ? null
                            : () => Navigator.of(ctx).pop(trimmed),
                    child: Text(confirmLabel),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  void _clearManagerFilters({bool keepPlaylist = false}) {
    _searchController.clear();
    ref.read(filterProvider.notifier).clearAllFilters();
    if (keepPlaylist || _downloadManagerView == _DownloadManagerView.playlist) {
      ref.read(filterProvider.notifier).selectTab(FilterTab.playlist);
      setState(() => _downloadManagerView = _DownloadManagerView.playlist);
    } else {
      ref.read(activePlaylistContextProvider.notifier).state = null;
      setState(() {
        _downloadManagerView = _DownloadManagerView.history;
        _selectedPlaylistKey = null;
      });
    }
  }

  Widget _buildDownloadManagerPanel(
    DownloadsState downloadsState,
    FilterState filterState,
    List<DownloadEntity> visibleDownloads,
    bool isDark,
    ColorScheme cs, {
    required bool hasDownloads,
    required List<PlaylistLibraryItem> visiblePlaylists,
    required PlaylistLibraryItem? selectedPlaylist,
    required bool playlistEmpty,
    required bool showNoResults,
  }) {
    final isPlaylistManager =
        _downloadManagerView == _DownloadManagerView.playlist ||
        filterState.selectedTab == FilterTab.playlist;
    final panelBorder =
        isDark
            ? AppColors.homeDarkBorderStrong
            : cs.onSurface.withValues(alpha: AppOpacity.pressed);
    final panelColor = isDark ? AppColors.homeDarkCardBg : Colors.white;
    final separatorColor =
        isDark
            ? AppColors.homeDarkBorderStrong
            : cs.onSurface.withValues(alpha: AppOpacity.hover);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xs,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: panelColor,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: panelBorder, width: 1),
          boxShadow:
              isDark
                  ? null
                  : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.035),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                      spreadRadius: -16,
                    ),
                  ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.smMd,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child:
                    hasDownloads
                        ? _buildToolbar(
                          downloadsState,
                          filterState,
                          visibleDownloads,
                          isDark,
                          cs,
                          playlistRoot:
                              isPlaylistManager && selectedPlaylist == null,
                        )
                        : _buildManagerTabs(downloadsState, isDark, cs),
              ),
              Divider(height: 1, thickness: 1, color: separatorColor),
              if (hasDownloads)
                _buildAdvancedFilterPanel(
                  downloadsState,
                  filterState,
                  isDark,
                  cs,
                  embedded: true,
                ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: PlaylistProgressIndicator(),
              ),
              Expanded(
                child: _buildManagerBody(
                  isPlaylistManager: isPlaylistManager,
                  visibleDownloads: visibleDownloads,
                  visiblePlaylists: visiblePlaylists,
                  selectedPlaylist: selectedPlaylist,
                  playlistEmpty: playlistEmpty,
                  showNoResults: showNoResults,
                  isDark: isDark,
                  cs: cs,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManagerBody({
    required bool isPlaylistManager,
    required List<DownloadEntity> visibleDownloads,
    required List<PlaylistLibraryItem> visiblePlaylists,
    required PlaylistLibraryItem? selectedPlaylist,
    required bool playlistEmpty,
    required bool showNoResults,
    required bool isDark,
    required ColorScheme cs,
  }) {
    if (isPlaylistManager && selectedPlaylist == null) {
      if (playlistEmpty) {
        return _buildPlaylistEmptyState(embedded: true);
      }
      if (showNoResults) {
        return _buildNoResultsState(embedded: true, keepPlaylist: true);
      }
      return PlaylistLibraryView(
        playlists: visiblePlaylists,
        onOpen: _openPlaylist,
        onPlay: _playPlaylist,
        onCreate: _createPlaylist,
      );
    }

    if (isPlaylistManager && selectedPlaylist != null) {
      final canReorderPlaylist =
          selectedPlaylist.kind == PlaylistLibraryKind.user &&
          _sameDownloadOrder(visibleDownloads, selectedPlaylist.downloads);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPlaylistDetailHeader(selectedPlaylist, isDark, cs),
          Expanded(
            child:
                selectedPlaylist.count == 0
                    ? _buildManagerStatePanel(
                      icon: Icons.playlist_play_rounded,
                      title: selectedPlaylist.title,
                      subtitle: AppLocalizations.playlistAddDialogEmpty,
                      embedded: true,
                    )
                    : showNoResults
                    ? _buildNoResultsState(embedded: true, keepPlaylist: true)
                    : DownloadsList(
                      downloads: visibleDownloads,
                      viewMode: ref.watch(settingsProvider).downloadsViewMode,
                      scrollable: true,
                      useOuterPanel: false,
                      groupUserPlaylists: false,
                      onRemoveFromPlaylist:
                          selectedPlaylist.kind == PlaylistLibraryKind.user
                              ? (download) => _removeFromPlaylist(
                                selectedPlaylist,
                                download,
                              )
                              : null,
                      onMovePlaylistItemUp:
                          canReorderPlaylist
                              ? (download) => _movePlaylistItem(
                                selectedPlaylist,
                                download,
                                -1,
                              )
                              : null,
                      onMovePlaylistItemDown:
                          canReorderPlaylist
                              ? (download) => _movePlaylistItem(
                                selectedPlaylist,
                                download,
                                1,
                              )
                              : null,
                      onNewDownload: focusUrl,
                      onOpenBrowser:
                          () => ref
                              .read(navigationProvider.notifier)
                              .navigateToTab(NavigationConstants.browserIndex),
                    ),
          ),
        ],
      );
    }

    if (showNoResults) {
      return _buildNoResultsState(embedded: true);
    }

    return DownloadsList(
      downloads: visibleDownloads,
      viewMode: ref.watch(settingsProvider).downloadsViewMode,
      scrollable: true,
      useOuterPanel: false,
      onNewDownload: focusUrl,
      onOpenBrowser:
          () => ref
              .read(navigationProvider.notifier)
              .navigateToTab(NavigationConstants.browserIndex),
    );
  }

  bool _sameDownloadOrder(
    List<DownloadEntity> left,
    List<DownloadEntity> right,
  ) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i].id != right[i].id) return false;
    }
    return true;
  }

  Widget _buildPlaylistDetailHeader(
    PlaylistLibraryItem playlist,
    bool isDark,
    ColorScheme cs,
  ) {
    final accent =
        playlist.kind == PlaylistLibraryKind.user
            ? AppColors.accentHighlight
            : AppColors.infoBlue;
    final kindIcon =
        playlist.kind == PlaylistLibraryKind.user
            ? Icons.bookmark_rounded
            : Icons.smart_display_rounded;
    final kindLabel =
        playlist.kind == PlaylistLibraryKind.user
            ? AppLocalizations.rightPanelTabsPlaylist
            : AppLocalizations.youtubePlaylistTitle;
    final metaColor = isDark ? AppColors.darkMetaText : cs.onSurfaceVariant;
    final borderColor =
        isDark
            ? AppColors.homeDarkBorderSubtle
            : cs.outlineVariant.withValues(alpha: AppOpacity.hover);
    final surfaceTint = accent.withValues(alpha: isDark ? 0.10 : 0.045);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaceTint,
        border: Border(bottom: BorderSide(color: borderColor, width: 1)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 620;
            final titleBlock = Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _buildPlaylistHeaderPill(
                        icon: kindIcon,
                        label: kindLabel,
                        color: accent,
                        isDark: isDark,
                      ),
                      _buildPlaylistHeaderPill(
                        icon: Icons.video_library_rounded,
                        label: AppLocalizations.rightPanelPlaylistItemCount(
                          playlist.count,
                        ),
                        color: metaColor,
                        isDark: isDark,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    playlist.title,
                    maxLines: compact ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.fileName.copyWith(
                      color: isDark ? AppColors.darkLightText : cs.onSurface,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            );

            final playButton = FilledButton.tonalIcon(
              onPressed:
                  playlist.count > 0 ? () => _playPlaylist(playlist) : null,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text(AppLocalizations.playerPlay),
            );
            final isUserPlaylist = playlist.kind == PlaylistLibraryKind.user;

            return Row(
              crossAxisAlignment:
                  compact
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
              children: [
                _buildPlaylistBackButton(isDark, cs),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    border: Border.all(
                      color: accent.withValues(alpha: isDark ? 0.28 : 0.18),
                    ),
                  ),
                  child: Icon(kindIcon, size: 19, color: accent),
                ),
                const SizedBox(width: AppSpacing.smMd),
                titleBlock,
                const SizedBox(width: AppSpacing.sm),
                if (isUserPlaylist) ...[
                  IconButton(
                    tooltip: AppLocalizations.batchOpsRename,
                    onPressed: () => _renamePlaylist(playlist),
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: AppLocalizations.commonDelete,
                    onPressed: () => _deletePlaylist(playlist),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    color: AppColors.errorRed,
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                if (compact)
                  SizedBox(width: 102, child: playButton)
                else
                  playButton,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlaylistBackButton(bool isDark, ColorScheme cs) {
    return Tooltip(
      message: AppLocalizations.commonBack,
      child: InkWell(
        onTap: _closePlaylist,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isDark ? AppColors.homeDarkCardBg : AppColors.lightElevated,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color:
                  isDark
                      ? AppColors.homeDarkBorderStrong
                      : cs.onSurface.withValues(alpha: AppOpacity.hover),
              width: 0.8,
            ),
          ),
          child: Icon(
            Icons.arrow_back_rounded,
            size: 18,
            color: isDark ? AppColors.darkLightText : cs.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildPlaylistHeaderPill({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      height: 23,
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.22 : 0.15),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.mini.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedFilterPanel(
    DownloadsState downloadsState,
    FilterState filterState,
    bool isDark,
    ColorScheme cs, {
    bool embedded = false,
  }) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child:
          _showFilterDrawer
              ? Padding(
                padding: EdgeInsets.fromLTRB(
                  embedded ? AppSpacing.lg : AppSpacing.xl,
                  AppSpacing.xs,
                  embedded ? AppSpacing.lg : AppSpacing.xl,
                  embedded ? AppSpacing.xs : 0,
                ),
                child: _buildAdvancedFilterContent(
                  downloadsState,
                  filterState,
                  isDark,
                  cs,
                  embedded: embedded,
                ),
              )
              : const SizedBox.shrink(),
    );
  }

  Widget _buildAdvancedFilterContent(
    DownloadsState downloadsState,
    FilterState filterState,
    bool isDark,
    ColorScheme cs, {
    required bool embedded,
  }) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (filterState.hasActiveFilters) ...[
          Row(
            children: [
              Flexible(
                child: _buildActiveFilterSummary(filterState, isDark, cs),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  _clearManagerFilters(
                    keepPlaylist:
                        _downloadManagerView == _DownloadManagerView.playlist,
                  );
                },
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  foregroundColor: AppColors.accentHighlight,
                ),
                child: Text(
                  AppLocalizations.downloadFilterClearAll,
                  style: AppTypography.compact.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        _buildTypeTabs(filterState, isDark, cs),
        const SizedBox(height: AppSpacing.xxs),
        const PlatformFilterChips(),
        const SizedBox(height: AppSpacing.xxs),
        const StatusFilterChips(),
        if (downloadsState.downloads.any((d) => d.isCompleted)) ...[
          const SizedBox(height: AppSpacing.xxs),
          const WatchFilterChips(),
        ],
      ],
    );

    if (!embedded) return content;

    return DecoratedBox(
      decoration: BoxDecoration(
        color:
            isDark
                ? AppColors.homeDarkAppBg.withValues(alpha: 0.72)
                : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color:
              isDark
                  ? AppColors.homeDarkBorderStrong.withValues(alpha: 0.74)
                  : cs.onSurface.withValues(alpha: AppOpacity.hover),
          width: 1,
        ),
        boxShadow:
            isDark
                ? null
                : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.025),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                    spreadRadius: -12,
                  ),
                ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.smMd,
          vertical: AppSpacing.sm,
        ),
        child: content,
      ),
    );
  }

  /// V2 download manager toolbar: section tabs, primary filters, search,
  /// sort, view mode, and batch actions. Advanced filters stay collapsed
  /// unless the user asks for them.
  Widget _buildToolbar(
    DownloadsState downloadsState,
    FilterState filterState,
    List<DownloadEntity> visibleDownloads,
    bool isDark,
    ColorScheme cs, {
    bool playlistRoot = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildManagerTabs(downloadsState, isDark, cs),
        const SizedBox(height: AppSpacing.sm),
        _buildManagerControls(
          filterState,
          visibleDownloads,
          isDark,
          cs,
          expand: true,
          playlistRoot: playlistRoot,
        ),
      ],
    );
  }

  Widget _buildManagerTabs(
    DownloadsState downloadsState,
    bool isDark,
    ColorScheme cs,
  ) {
    final counts = ref.watch(downloadCountsProvider);
    final selectedTab = ref.watch(filterProvider).selectedTab;
    final playlistCount = counts[FilterTab.playlist] ?? 0;
    final isPlaylistSelected =
        _downloadManagerView == _DownloadManagerView.playlist ||
        selectedTab == FilterTab.playlist;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _DownloadManagerTabButton(
            label: AppLocalizations.homeDownloadsHistoryTab,
            count: downloadsState.downloads.length,
            isSelected: !isPlaylistSelected,
            isDark: isDark,
            onTap: () {
              ref.read(filterProvider.notifier).selectTab(FilterTab.all);
              ref.read(activePlaylistContextProvider.notifier).state = null;
              setState(() {
                _downloadManagerView = _DownloadManagerView.history;
                _selectedPlaylistKey = null;
              });
            },
          ),
          const SizedBox(width: AppSpacing.mdLg),
          _DownloadManagerTabButton(
            label: AppLocalizations.navPlaylist,
            count: playlistCount,
            isSelected: isPlaylistSelected,
            isDark: isDark,
            onTap: () {
              ref.read(filterProvider.notifier).selectTab(FilterTab.playlist);
              ref.read(activePlaylistContextProvider.notifier).state = null;
              setState(() {
                _downloadManagerView = _DownloadManagerView.playlist;
                _selectedPlaylistKey = null;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTypeTabs(FilterState filterState, bool isDark, ColorScheme cs) {
    final counts = ref.watch(downloadCountsProvider);
    final primaryTabs = <FilterTab>[
      FilterTab.all,
      FilterTab.video,
      FilterTab.audio,
      FilterTab.playlist,
      if (filterState.selectedTab == FilterTab.image) FilterTab.image,
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children:
            primaryTabs.map((tab) {
              final isSelected = filterState.selectedTab == tab;
              final count = counts[tab] ?? 0;
              return Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: _DownloadTypeChip(
                  label: tab.displayName,
                  count: count,
                  icon: _tabIcon(tab),
                  isSelected: isSelected,
                  isDark: isDark,
                  onTap: () {
                    ref.read(filterProvider.notifier).selectTab(tab);
                    if (tab != FilterTab.playlist) {
                      ref.read(activePlaylistContextProvider.notifier).state =
                          null;
                    }
                    setState(() {
                      _downloadManagerView =
                          tab == FilterTab.playlist
                              ? _DownloadManagerView.playlist
                              : _DownloadManagerView.history;
                      if (tab != FilterTab.playlist) {
                        _selectedPlaylistKey = null;
                      }
                    });
                  },
                ),
              );
            }).toList(),
      ),
    );
  }

  IconData _tabIcon(FilterTab tab) {
    return switch (tab) {
      FilterTab.all => Icons.inbox_outlined,
      FilterTab.video => Icons.smart_display_outlined,
      FilterTab.audio => Icons.music_note_rounded,
      FilterTab.image => Icons.image_outlined,
      FilterTab.playlist => Icons.playlist_play_rounded,
    };
  }

  Widget _buildManagerControls(
    FilterState filterState,
    List<DownloadEntity> visibleDownloads,
    bool isDark,
    ColorScheme cs, {
    bool expand = false,
    bool playlistRoot = false,
  }) {
    final toolbarIconColor =
        isDark ? AppColors.darkMetaText : cs.onSurfaceVariant;
    final showCreatePlaylist = playlistRoot;

    Widget actionControls() {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showCreatePlaylist) ...[
            _ToolbarTextButton(
              icon: Icons.add_rounded,
              label: AppLocalizations.playlistManageCreateTitle,
              color: AppColors.accentHighlight,
              onTap: _createPlaylist,
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          _buildFilterToggle(filterState, isDark, cs),
          const SizedBox(width: AppSpacing.xs),
          _buildSortMenu(filterState, isDark, cs),
          if (filterState.hasActiveFilters) ...[
            const SizedBox(width: AppSpacing.xs),
            _ToolbarIconButton(
              icon: Icons.clear_all_rounded,
              tooltip: AppLocalizations.downloadFilterClearAll,
              color: toolbarIconColor,
              onTap: () {
                _clearManagerFilters(
                  keepPlaylist:
                      _downloadManagerView == _DownloadManagerView.playlist,
                );
              },
            ),
          ],
          const SizedBox(width: AppSpacing.sm),
          _buildViewModeToggle(isDark, cs),
          const SizedBox(width: AppSpacing.xs),
          _buildBatchActionsMenu(toolbarIconColor, isDark, cs),
        ],
      );
    }

    if (!expand) {
      final search = _buildSearchField(filterState, isDark, cs);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSelectVisibleToggle(visibleDownloads, isDark, cs),
          const SizedBox(width: AppSpacing.sm),
          search,
          const SizedBox(width: AppSpacing.sm),
          actionControls(),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final search = _buildSearchField(filterState, isDark, cs, expand: true);
        final compact = constraints.maxWidth < 720;

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _buildSelectVisibleToggle(visibleDownloads, isDark, cs),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: search),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: Alignment.centerRight,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: actionControls(),
                ),
              ),
            ],
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            _buildSelectVisibleToggle(visibleDownloads, isDark, cs),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: search),
            const SizedBox(width: AppSpacing.sm),
            actionControls(),
          ],
        );
      },
    );
  }

  Widget _buildSelectVisibleToggle(
    List<DownloadEntity> visibleDownloads,
    bool isDark,
    ColorScheme cs,
  ) {
    final selectedIds = ref.watch(batchSelectionProvider);
    final visibleIds = visibleDownloads.map((d) => d.id).toSet();
    final allSelected =
        visibleIds.isNotEmpty &&
        visibleIds.every((id) => selectedIds.contains(id));
    final hasPartial =
        !allSelected && visibleIds.any((id) => selectedIds.contains(id));
    final disabled = visibleIds.isEmpty;

    return _ToolbarSelectButton(
      selected: allSelected,
      partial: hasPartial,
      disabled: disabled,
      isDark: isDark,
      onTap:
          disabled
              ? null
              : () {
                final next = Set<int>.from(selectedIds);
                if (allSelected) {
                  next.removeAll(visibleIds);
                } else {
                  next.addAll(visibleIds);
                }
                ref.read(batchSelectionProvider.notifier).state = next;
              },
    );
  }

  Widget _buildSearchField(
    FilterState filterState,
    bool isDark,
    ColorScheme cs, {
    bool expand = false,
  }) {
    final metadataColor = isDark ? AppColors.darkMetaText : cs.onSurfaceVariant;
    final shouldShowField = expand || !_searchExpanded;
    final field = TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      style: AppTypography.metadata.copyWith(
        height: 1.15,
        color: isDark ? AppColors.darkLightText : cs.onSurface,
      ),
      maxLines: 1,
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        hintText: AppLocalizations.homeSearchPlaceholder,
        hintStyle: AppTypography.metadata.copyWith(
          height: 1.15,
          color:
              isDark
                  ? metadataColor
                  : metadataColor.withValues(alpha: AppOpacity.secondary),
        ),
        prefixIcon: SizedBox(
          width: 32,
          height: 34,
          child: Center(
            child: Icon(Icons.search_rounded, size: 17, color: metadataColor),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 32,
          minHeight: 34,
          maxHeight: 34,
        ),
        suffixIcon:
            filterState.searchQuery.isNotEmpty
                ? SizedBox(
                  width: 30,
                  height: 34,
                  child: Center(
                    child: IconButton(
                      icon: Icon(
                        Icons.clear_rounded,
                        size: 16,
                        color: metadataColor,
                      ),
                      onPressed: () => _searchController.clear(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                    ),
                  ),
                )
                : null,
        filled: true,
        fillColor: isDark ? AppColors.homeDarkCardBg : AppColors.lightElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(
            color:
                isDark
                    ? AppColors.homeDarkBorderSubtle
                    : cs.onSurface.withValues(alpha: AppOpacity.hover),
            width: 0.8,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: AppColors.accentHighlight, width: 1.2),
        ),
        contentPadding: const EdgeInsets.only(
          left: AppSpacing.xs,
          right: AppSpacing.sm,
        ),
        isDense: true,
      ),
    );

    if (expand) return SizedBox(height: 34, child: field);
    if (!shouldShowField) {
      return _ToolbarIconButton(
        icon: Icons.search_rounded,
        tooltip: AppLocalizations.homeSearchPlaceholder,
        color: metadataColor,
        onTap: () {
          setState(() => _searchExpanded = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _searchFocusNode.requestFocus();
          });
        },
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      width: 300,
      height: 34,
      child: field,
    );
  }

  Widget _buildSortMenu(FilterState filterState, bool isDark, ColorScheme cs) {
    final foreground = isDark ? AppColors.darkLightText : cs.onSurface;
    return PopupMenuButton<SortOption>(
      tooltip: AppLocalizations.downloadsSortBy,
      padding: EdgeInsets.zero,
      onSelected: (sort) => ref.read(filterProvider.notifier).updateSort(sort),
      itemBuilder: (context) {
        final currentSort = ref.read(filterProvider).sortOption;
        return SortOption.values.map((option) {
          final isSelected = currentSort == option;
          return PopupMenuItem<SortOption>(
            value: option,
            child: Row(
              children: [
                if (isSelected)
                  Icon(Icons.check, size: 16, color: AppColors.accentHighlight)
                else
                  const SizedBox(width: 16),
                const SizedBox(width: AppSpacing.sm),
                Text(option.displayName),
              ],
            ),
          );
        }).toList();
      },
      child: Container(
        height: 34,
        constraints: const BoxConstraints(minWidth: 96),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: isDark ? AppColors.homeDarkCardBg : AppColors.lightElevated,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color:
                isDark
                    ? AppColors.homeDarkBorderSubtle
                    : cs.onSurface.withValues(alpha: AppOpacity.hover),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_vert_rounded, size: 16, color: foreground),
            const SizedBox(width: AppSpacing.xs),
            Text(
              _sortLabel(filterState.sortOption),
              style: AppTypography.metadata.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  String _sortLabel(SortOption option) {
    final label = option.displayName;
    if (label.contains(':')) return label.split(':').last.trim();
    final match = RegExp(r'\(([^)]+)\)').firstMatch(label);
    return match?.group(1) ?? label;
  }

  Widget _buildViewModeToggle(bool isDark, ColorScheme cs) {
    final viewMode = ref.watch(settingsProvider).downloadsViewMode;
    final isGrid = viewMode == 'grid';
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: isDark ? AppColors.homeDarkCardBg : AppColors.lightSurface3,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color:
              isDark
                  ? AppColors.homeDarkBorderSubtle
                  : cs.onSurface.withValues(alpha: AppOpacity.hover),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ViewModeButton(
            icon: Icons.view_list_rounded,
            isActive: !isGrid,
            isDark: isDark,
            tooltip: AppLocalizations.downloadsViewSwitchToList,
            onTap:
                () => ref
                    .read(settingsProvider.notifier)
                    .updateDownloadsViewMode('list'),
          ),
          _ViewModeButton(
            icon: Icons.grid_view_rounded,
            isActive: isGrid,
            isDark: isDark,
            tooltip: AppLocalizations.downloadsViewSwitchToGrid,
            onTap:
                () => ref
                    .read(settingsProvider.notifier)
                    .updateDownloadsViewMode('grid'),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchActionsMenu(
    Color toolbarIconColor,
    bool isDark,
    ColorScheme cs,
  ) {
    return SizedBox(
      width: 36,
      height: 34,
      child: PopupMenuButton<String>(
        tooltip: AppLocalizations.homeBatchActions,
        padding: EdgeInsets.zero,
        iconSize: 18,
        onSelected: (action) {
          switch (action) {
            case 'clearCompleted':
              showClearCompletedDialog();
            case 'clearFailed':
              showClearFailedDialog();
            case 'pauseAll':
              ref.read(downloadsNotifierProvider.notifier).pauseAllDownloads();
              AppSnackBar.info(
                context,
                message: AppLocalizations.homePausedAll,
              );
            case 'resumeAll':
              ref.read(downloadsNotifierProvider.notifier).resumeAllDownloads();
              AppSnackBar.info(
                context,
                message: AppLocalizations.homeResumedAll,
              );
          }
        },
        itemBuilder:
            (context) => [
              PopupMenuItem(
                value: 'clearCompleted',
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 16),
                    const SizedBox(width: AppSpacing.sm),
                    Text(AppLocalizations.homeClearCompleted),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'clearFailed',
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, size: 16),
                    const SizedBox(width: AppSpacing.sm),
                    Text(AppLocalizations.homeClearFailed),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'pauseAll',
                child: Row(
                  children: [
                    const Icon(Icons.pause_circle_outline, size: 16),
                    const SizedBox(width: AppSpacing.sm),
                    Text(AppLocalizations.homePauseAll),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'resumeAll',
                child: Row(
                  children: [
                    const Icon(Icons.play_circle_outline, size: 16),
                    const SizedBox(width: AppSpacing.sm),
                    Text(AppLocalizations.homeResumeAll),
                  ],
                ),
              ),
            ],
        child: Container(
          width: 36,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isDark ? AppColors.homeDarkCardBg : AppColors.lightElevated,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color:
                  isDark
                      ? AppColors.homeDarkBorderStrong
                      : cs.onSurface.withValues(alpha: AppOpacity.hover),
              width: 0.8,
            ),
          ),
          child: Icon(
            Icons.more_horiz_rounded,
            size: 17,
            color: toolbarIconColor,
          ),
        ),
      ),
    );
  }

  Widget _buildActiveFilterSummary(
    FilterState filterState,
    bool isDark,
    ColorScheme cs,
  ) {
    final labels = <String>[];
    if (filterState.searchQuery.isNotEmpty) {
      labels.add('"${filterState.searchQuery}"');
    }
    if (filterState.selectedPlatform != null) {
      labels.add(filterState.selectedPlatform!.displayName);
    }
    labels.addAll(filterState.statusFilters.map((s) => s.displayLabel));
    if (filterState.watchFilter != WatchFilter.all) {
      labels.add(filterState.watchFilter.displayName);
    }

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          AppLocalizations.downloadFilterActiveFilters(labels.length),
          style: AppTypography.compact.copyWith(
            color: AppColors.metaText(context),
          ),
        ),
        ...labels
            .take(5)
            .map(
              (label) => Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      isDark
                          ? AppColors.homeDarkCardSelected
                          : AppColors.accentHighlight.withValues(
                            alpha: AppOpacity.hover,
                          ),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Text(
                  label,
                  style: AppTypography.compact.copyWith(
                    color:
                        isDark
                            ? AppColors.darkLightText
                            : AppColors.accentHighlight,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
      ],
    );
  }

  /// Filter toggle button — shows active filter count badge
  Widget _buildFilterToggle(
    FilterState filterState,
    bool isDark,
    ColorScheme cs,
  ) {
    // Count active advanced filters (platform + status + watch, not tab/search)
    int activeCount = 0;
    if (filterState.selectedTab != FilterTab.all &&
        filterState.selectedTab != FilterTab.playlist) {
      activeCount++;
    }
    if (filterState.selectedPlatform != null) activeCount++;
    activeCount += filterState.statusFilters.length;
    if (filterState.watchFilter != WatchFilter.all) activeCount++;
    final hasActive = activeCount > 0;

    final activeTint = AppColors.accentHighlight;
    final iconColor =
        hasActive || _showFilterDrawer
            ? activeTint
            : (isDark ? AppColors.darkMetaText : cs.onSurfaceVariant);

    return Badge(
      label: Text(
        '$activeCount',
        style: AppTypography.mini.copyWith(color: AppColors.darkLightText),
      ),
      isLabelVisible: hasActive && !_showFilterDrawer,
      backgroundColor: activeTint,
      child: AnimatedContainer(
        duration: AppTransitions.controls,
        curve: Curves.easeOut,
        width: 36,
        height: 34,
        decoration: BoxDecoration(
          color:
              _showFilterDrawer || hasActive
                  ? activeTint.withValues(
                    alpha: isDark ? AppOpacity.pressed : AppOpacity.hover,
                  )
                  : (isDark
                      ? AppColors.homeDarkCardBg
                      : AppColors.lightElevated),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color:
                _showFilterDrawer || hasActive
                    ? activeTint.withValues(
                      alpha: isDark ? AppOpacity.medium : AppOpacity.quarter,
                    )
                    : (isDark
                        ? AppColors.homeDarkBorderStrong
                        : cs.onSurface.withValues(alpha: AppOpacity.hover)),
            width: 0.8,
          ),
        ),
        child: IconButton(
          icon: Icon(
            _showFilterDrawer
                ? Icons.filter_list_off_rounded
                : Icons.filter_list_rounded,
            size: 18,
            color: iconColor,
          ),
          tooltip:
              _showFilterDrawer
                  ? AppLocalizations.downloadFilterClearAll
                  : AppLocalizations.downloadFilterStatusFilter,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 36, height: 34),
          onPressed:
              () => setState(() => _showFilterDrawer = !_showFilterDrawer),
        ),
      ),
    );
  }

  Widget _buildNoResultsState({
    bool embedded = false,
    bool keepPlaylist = false,
  }) {
    return _buildManagerStatePanel(
      icon: Icons.search_off_rounded,
      title: AppLocalizations.homeNoResultsTitle,
      subtitle: AppLocalizations.homeNoResultsSubtitle,
      embedded: embedded,
      action: OutlinedButton.icon(
        onPressed: () {
          _clearManagerFilters(keepPlaylist: keepPlaylist);
          setState(() => _showFilterDrawer = false);
        },
        icon: const Icon(Icons.clear_all_rounded, size: 16),
        label: Text(AppLocalizations.downloadFilterClearAll),
      ),
    );
  }

  Widget _buildPlaylistEmptyState({bool embedded = false}) {
    return _buildManagerStatePanel(
      icon: Icons.playlist_play_rounded,
      title: AppLocalizations.navPlaylist,
      subtitle: AppLocalizations.playlistAddDialogEmpty,
      embedded: embedded,
      action: FilledButton.tonalIcon(
        onPressed: _createPlaylist,
        icon: const Icon(Icons.add_rounded, size: 16),
        label: Text(AppLocalizations.playlistAddDialogCreateButton),
      ),
    );
  }

  Widget _buildManagerStatePanel({
    required IconData icon,
    required String title,
    required String subtitle,
    bool embedded = false,
    Widget? action,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final panelBorder =
        isDark
            ? AppColors.homeDarkBorderSubtle
            : cs.outlineVariant.withValues(alpha: AppOpacity.subtle);
    final muted = isDark ? AppColors.darkMetaText : cs.onSurfaceVariant;

    final state = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accentHighlight.withValues(
                    alpha: isDark ? AppOpacity.pressed : AppOpacity.hover,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.card * 2),
                ),
                child: Icon(icon, size: 30, color: AppColors.accentHighlight),
              ),
              const Gap.md(),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: isDark ? AppColors.darkLightText : cs.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Gap.sm(),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: AppTypography.metadata.copyWith(color: muted),
              ),
              if (action != null) ...[const Gap.md(), action],
            ],
          ),
        ),
      ),
    );

    if (embedded) return state;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xs,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? AppColors.homeDarkCardBg : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: panelBorder),
        ),
        child: state,
      ),
    );
  }
}

/// V2 free-tier plan strip — mockup-aligned inline banner.
///
/// Layout: [⭐] Gói miễn phí · Bạn còn N lượt tải tuần này · Nâng cấp ngay →
/// Hidden for premium users. Three counter states drive the tone:
///   - normal (remaining > 5): subtle metadata color
///   - warning (1-5): accent color signals urgency
///   - exhausted (0): accent color + alternate copy "Đã hết lượt tải tuần này"
/// Tap anywhere on the strip's CTA opens [UpgradePromptDialog]. The
/// counter uses [PremiumLimits.freeWeeklyDownloads] across brands.
class _FreeQuotaIndicator extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPremium = ref.watch(isPremiumProvider);
    if (isPremium) return const SizedBox.shrink();

    final total = PremiumLimits.freeWeeklyDownloads;
    final used =
        ref.watch(downloadQuotaNotifierProvider).clamp(0, total).toInt();
    final remaining = (total - used).clamp(0, total).toInt();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isExhausted = remaining <= 0;
    final isWarning = !isExhausted && remaining <= 5;

    // Brand-token strip: every accent flows through
    // [AppColors.accentHighlight] so SSvid renders Wine Red and
    // VidCombo renders Cyan. The mockup's violet crown + blue link
    // were Stitch placeholder colors, not a design-system rule.
    final brandAccent = AppColors.accentHighlight;
    final mutedText = AppColors.metaText(context);
    final cs = Theme.of(context).colorScheme;

    final counterColor = isExhausted || isWarning ? brandAccent : mutedText;
    final progress = total == 0 ? 0.0 : (remaining / total).clamp(0.0, 1.0);
    final surfaceColor =
        isDark ? AppColors.homeDarkCardBg : cs.surfaceContainerLowest;
    final tintColor =
        isExhausted
            ? cs.error.withValues(alpha: isDark ? 0.14 : 0.07)
            : brandAccent.withValues(alpha: isDark ? 0.08 : 0.035);
    final borderColor =
        isExhausted || isWarning
            ? brandAccent.withValues(alpha: isDark ? 0.48 : 0.34)
            : (isDark
                ? AppColors.homeDarkBorderSubtle
                : cs.outlineVariant.withValues(alpha: 0.36));

    Widget quotaIcon() {
      return Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: brandAccent.withValues(alpha: isDark ? 0.18 : 0.10),
          borderRadius: BorderRadius.circular(AppRadius.button),
          border: Border.all(
            color: brandAccent.withValues(alpha: isDark ? 0.26 : 0.18),
          ),
        ),
        child: Icon(
          Icons.workspace_premium_rounded,
          size: 19,
          color: brandAccent,
        ),
      );
    }

    Widget quotaCopy() {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLocalizations.homeQuotaFreePlan,
                style: AppTypography.metadata.copyWith(
                  color: isDark ? AppColors.darkLightText : cs.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: mutedText,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  isExhausted
                      ? AppLocalizations.homeQuotaExhausted
                      : AppLocalizations.homeQuotaRemaining(remaining),
                  style: AppTypography.metadata.copyWith(
                    color: counterColor,
                    fontWeight: isExhausted ? FontWeight.w800 : FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              color: brandAccent,
              backgroundColor:
                  isDark
                      ? AppColors.homeDarkBorderSubtle
                      : cs.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
        ],
      );
    }

    void openUpgrade() {
      UpgradePromptDialog.showAndNavigate(
        context,
        ref,
        feature: PremiumFeature.unlimitedDownloads,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xs,
        AppSpacing.xl,
        AppSpacing.xs,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final cta = _UpgradeCtaLink(
            label: AppLocalizations.homeQuotaUpgradeCta,
            accent: brandAccent,
            onTap: openUpgrade,
          );

          return Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? AppSpacing.smMd : AppSpacing.md,
              vertical: compact ? AppSpacing.sm : AppSpacing.smMd,
            ),
            decoration: BoxDecoration(
              color: Color.alphaBlend(tintColor, surfaceColor),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withValues(alpha: isDark ? 0.20 : 0.035),
                  blurRadius: isDark ? 22 : 14,
                  offset: Offset(0, isDark ? 10 : 3),
                  spreadRadius: isDark ? -16 : -8,
                ),
              ],
            ),
            child:
                compact
                    ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            quotaIcon(),
                            const SizedBox(width: AppSpacing.smMd),
                            Expanded(child: quotaCopy()),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Align(alignment: Alignment.centerRight, child: cta),
                      ],
                    )
                    : Row(
                      children: [
                        quotaIcon(),
                        const SizedBox(width: AppSpacing.smMd),
                        Expanded(child: quotaCopy()),
                        const SizedBox(width: AppSpacing.md),
                        cta,
                      ],
                    ),
          );
        },
      ),
    );
  }
}

/// Upgrade CTA pill — hover-aware and brand-colored. Pulled out so the plan
/// strip stays declarative.
class _UpgradeCtaLink extends StatefulWidget {
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const _UpgradeCtaLink({
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  State<_UpgradeCtaLink> createState() => _UpgradeCtaLinkState();
}

class _UpgradeCtaLinkState extends State<_UpgradeCtaLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.smMd,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: widget.accent.withValues(alpha: _hovered ? 0.18 : 0.10),
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(
              color: widget.accent.withValues(alpha: _hovered ? 0.44 : 0.28),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: AppTypography.metadata.copyWith(
                  color: widget.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_forward_rounded, size: 14, color: widget.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadManagerTabButton extends StatelessWidget {
  final String label;
  final int count;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _DownloadManagerTabButton({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor =
        isSelected
            ? (isDark
                ? AppColors.darkLightText
                : Theme.of(context).colorScheme.onSurface)
            : AppColors.metaText(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: AppTypography.buttonPrimary.copyWith(
                    color: textColor,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(width: AppSpacing.xs),
                Container(
                  height: 18,
                  constraints: const BoxConstraints(minWidth: 18),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        isSelected
                            ? AppColors.accentHighlight.withValues(
                              alpha:
                                  isDark
                                      ? AppOpacity.pressed
                                      : AppOpacity.hover,
                            )
                            : AppColors.metaText(
                              context,
                            ).withValues(alpha: AppOpacity.hover),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Text(
                    '$count',
                    style: AppTypography.mini.copyWith(
                      color:
                          isSelected
                              ? AppColors.accentHighlight
                              : AppColors.metaText(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            AnimatedContainer(
              duration: AppTransitions.controls,
              curve: Curves.easeOut,
              height: 2,
              width: isSelected ? 128 : 0,
              decoration: BoxDecoration(
                color: AppColors.accentHighlight,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadTypeChip extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _DownloadTypeChip({
    required this.label,
    required this.count,
    required this.icon,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selectedColor = AppColors.accentHighlight;
    final selectedForeground =
        isDark ? AppColors.darkLightText : AppColors.accentHighlight;
    final selectedMeta =
        isDark ? AppColors.darkMetaText : AppColors.accentHighlight;
    final foreground =
        isSelected
            ? selectedForeground
            : (isDark ? AppColors.darkMetaText : cs.onSurfaceVariant);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: AnimatedContainer(
          duration: AppTransitions.controls,
          curve: Curves.easeOut,
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          decoration: BoxDecoration(
            color:
                isSelected
                    ? selectedColor.withValues(
                      alpha: isDark ? 0.14 : AppOpacity.hover,
                    )
                    : (isDark
                        ? AppColors.homeDarkCardBg
                        : AppColors.lightElevated),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color:
                  isSelected
                      ? selectedColor.withValues(
                        alpha: isDark ? AppOpacity.medium : AppOpacity.quarter,
                      )
                      : (isDark
                          ? AppColors.homeDarkBorderStrong
                          : cs.onSurface.withValues(alpha: AppOpacity.hover)),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: isSelected ? selectedColor : foreground,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: AppTypography.metadata.copyWith(
                  color: foreground,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 12,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '$count',
                  style: AppTypography.mini.copyWith(
                    color:
                        isSelected
                            ? selectedMeta.withValues(alpha: AppOpacity.strong)
                            : foreground.withValues(alpha: AppOpacity.strong),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _ToolbarIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Container(
        width: 36,
        height: 34,
        decoration: BoxDecoration(
          color: isDark ? AppColors.homeDarkCardBg : AppColors.lightElevated,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color:
                isDark
                    ? AppColors.homeDarkBorderStrong
                    : cs.onSurface.withValues(alpha: AppOpacity.hover),
            width: 0.8,
          ),
        ),
        child: IconButton(
          icon: Icon(icon, size: 18),
          color: color,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 36, height: 34),
          onPressed: onTap,
          style: IconButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarTextButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ToolbarTextButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.16 : 0.09),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: color.withValues(alpha: isDark ? 0.36 : 0.22),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.compact.copyWith(
                  color: isDark ? color : cs.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarSelectButton extends StatelessWidget {
  final bool selected;
  final bool partial;
  final bool disabled;
  final bool isDark;
  final VoidCallback? onTap;

  const _ToolbarSelectButton({
    required this.selected,
    required this.partial,
    required this.disabled,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final outline =
        isDark
            ? AppColors.homeDarkBorderStrong
            : cs.onSurface.withValues(alpha: AppOpacity.hover);

    return Tooltip(
      message: AppLocalizations.batchOpsSelectAll,
      waitDuration: const Duration(milliseconds: 500),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 36,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isDark ? AppColors.homeDarkCardBg : AppColors.lightElevated,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: outline, width: 0.8),
          ),
          child:
              partial
                  ? Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.accentHighlight.withValues(
                        alpha: isDark ? AppOpacity.pressed : AppOpacity.hover,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(
                        color: AppColors.accentHighlight.withValues(
                          alpha: AppOpacity.medium,
                        ),
                        width: 1.2,
                      ),
                    ),
                    child: Icon(
                      Icons.remove_rounded,
                      size: 13,
                      color: AppColors.accentHighlight,
                    ),
                  )
                  : SelectionCheckbox(selected: selected && !disabled),
        ),
      ),
    );
  }
}

/// Nocturne view mode toggle button — contained with active highlight
class _ViewModeButton extends StatefulWidget {
  final IconData icon;
  final bool isActive;
  final bool isDark;
  final String tooltip;
  final VoidCallback onTap;

  const _ViewModeButton({
    required this.icon,
    required this.isActive,
    required this.isDark,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_ViewModeButton> createState() => _ViewModeButtonState();
}

class _ViewModeButtonState extends State<_ViewModeButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (mounted) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _isHovered = false);
      },
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 500),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 34,
            height: 32,
            decoration: BoxDecoration(
              color:
                  widget.isActive
                      ? (widget.isDark
                          ? AppColors.darkElevated
                          : AppColors.lightSurface1)
                      : (_isHovered
                          ? (widget.isDark
                              ? AppColors.darkSurface1
                              : AppColors.lightSurface2)
                          : Colors.transparent),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Icon(
              widget.icon,
              size: 18,
              color:
                  widget.isActive
                      ? (widget.isDark
                          ? AppColors.darkLightText
                          : Theme.of(context).colorScheme.onSurface)
                      : (widget.isDark
                          ? AppColors.darkMetaText
                          : Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }
}
