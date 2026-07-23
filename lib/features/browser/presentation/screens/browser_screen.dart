// Mixins access `mounted` via abstract getter — analyzer can't trace it
// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/core.dart';
import '../../../downloads/presentation/providers/extraction_provider.dart';
import '../../../downloads/presentation/providers/extraction_cache_provider.dart';
import '../../data/webview/app_webview.dart';
import '../../domain/services/cookie_inspector_service.dart';
import '../../domain/services/contextual_suggestion_service.dart';
import '../../domain/services/page_video_scanner_service.dart';
import '../../domain/services/video_url_detector.dart';
import '../providers/browser_providers.dart';
import '../providers/browser_tab_providers.dart';
import '../providers/browser_session_providers.dart';
import '../providers/content_filter_providers.dart';
import '../providers/unified_media_provider.dart';
import '../widgets/browser_context_menu.dart';
import '../widgets/browser_download_overlay.dart';
import '../widgets/media_sniff_panel.dart';
import '../widgets/browser_keyboard_intents.dart';
import '../widgets/browser_security_indicators.dart';
import '../widgets/browser_tab_bar.dart';
import '../widgets/browser_toolbar.dart';
import '../widgets/contextual_suggestion_banner.dart';
import '../widgets/find_in_page_bar.dart';
import '../widgets/new_tab_page.dart';
import 'browser_autocomplete_mixin.dart';
import 'browser_download_mixin.dart';
import 'browser_find_in_page_mixin.dart';
import 'browser_navigation_mixin.dart';
import 'browser_tab_mixin.dart';

/// In-app browser with tabs, history, bookmarks, and one-tap download FAB
class BrowserScreen extends ConsumerStatefulWidget {
  const BrowserScreen({super.key});

  @override
  ConsumerState<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends ConsumerState<BrowserScreen>
    with
        SingleTickerProviderStateMixin,
        BrowserDownloadMixin,
        BrowserFindInPageMixin,
        BrowserNavigationMixin,
        BrowserAutocompleteMixin,
        BrowserTabMixin {
  final Map<String, AppWebViewController> _controllers = {};
  final _urlController = TextEditingController();
  final _urlFocusNode = FocusNode();
  final _layerLink = LayerLink();

  bool _isLoading = false;
  String? _errorMessage;
  double _loadingProgress = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;
  @override
  bool isShowingDialog = false;
  final Set<String> _autoLoginAttemptedUrls = {};
  final Set<String> _dismissedExpiryWarnings = {};

  DownloadSuggestion? _currentSuggestion;
  final Set<String> _dismissedSuggestionUrls = {};

  late final AnimationController _toolbarAnimController;
  late final Animation<double> _toolbarAnim;
  bool _isFullscreen = false;
  bool _isToolbarRevealed = false;
  Timer? _hideToolbarTimer;

  final _pageVideoScannerInstance = PageVideoScannerService();

  // ── Mixin accessor implementations ─────────────────────────────────────

  @override
  Map<String, AppWebViewController> get controllers => _controllers;
  @override
  TextEditingController get urlControllerForNav => _urlController;
  @override
  TextEditingController get urlControllerForTab => _urlController;
  @override
  Set<String> get dismissedSuggestionUrls => _dismissedSuggestionUrls;
  @override
  Set<String> get autoLoginAttemptedUrls => _autoLoginAttemptedUrls;
  @override
  PageVideoScannerService get pageVideoScanner => _pageVideoScannerInstance;
  @override
  AppWebViewController? get activeControllerForFind => activeController;
  @override
  TextEditingController get urlControllerForAutocomplete => _urlController;
  @override
  FocusNode get urlFocusNodeForAutocomplete => _urlFocusNode;
  @override
  LayerLink get layerLinkForAutocomplete => _layerLink;
  @override
  void Function(String url) get onNavigateToUrl => _navigateToUrl;

  @override
  void setLoadingState({
    required bool isLoading,
    double? progress,
    String? error,
  }) {
    setState(() {
      _isLoading = isLoading;
      if (progress != null) _loadingProgress = progress;
      if (error != null) _errorMessage = error;
      if (isLoading) _errorMessage = null;
    });
  }

  @override
  void setNavigationState({
    required bool canGoBack,
    required bool canGoForward,
  }) {
    setState(() {
      _canGoBack = canGoBack;
      _canGoForward = canGoForward;
    });
  }

  @override
  void setSuggestion(DownloadSuggestion? suggestion) {
    setState(() => _currentSuggestion = suggestion);
  }

  @override
  void resetTabUiState() {
    setState(() {
      _isLoading = false;
      _canGoBack = false;
      _canGoForward = false;
      _errorMessage = null;
    });
    ref.read(browserVideoDetectionProvider.notifier).state = null;
    ref.read(browserDetectedVideosProvider.notifier).state = [];
    ref.read(browserPageUrlProvider.notifier).state = null;
  }

  @override
  void onTabNavStateChanged({bool? canGoBack, bool? canGoForward}) {
    setState(() {
      if (canGoBack != null) _canGoBack = canGoBack;
      if (canGoForward != null) _canGoForward = canGoForward;
    });
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _toolbarAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1.0,
    );
    _toolbarAnim = _toolbarAnimController;

    final tabState = ref.read(browserTabsProvider);
    final initialUrl = ref.read(browserInitialUrlProvider);
    final defaultUrl = ref.read(browserHomePageProvider);

    if (tabState.activeTab != null && initialUrl != defaultUrl) {
      Future(() {
        ref
            .read(browserTabsProvider.notifier)
            .updateTabInfo(tabState.activeTabId, url: initialUrl);
      });
    }

    initControllerForTab(
      tabState.activeTabId,
      initialUrl != defaultUrl
          ? initialUrl
          : tabState.activeTab?.url ?? defaultUrl,
    );
    final activeUrl = tabState.activeTab?.url ?? initialUrl;
    _urlController.text =
        (activeUrl == 'about:blank' || activeUrl.isEmpty) ? '' : activeUrl;

    _urlController.addListener(onUrlTextChanged);
    _urlFocusNode.addListener(onUrlFocusChanged);
    _urlFocusNode.onKeyEvent = handleUrlKeyEvent;
  }

  @override
  void dispose() {
    // Release WebView resources for all tabs
    for (final ctrl in _controllers.values) {
      ctrl.loadUrl('about:blank');
      ctrl.clearLocalStorage().catchError((_) {});
    }
    _controllers.clear();

    _toolbarAnimController.dispose();
    _hideToolbarTimer?.cancel();
    hideAutocompleteOverlay();
    _urlController.removeListener(onUrlTextChanged);
    _urlFocusNode.removeListener(onUrlFocusChanged);
    _urlController.dispose();
    _urlFocusNode.dispose();
    super.dispose();
  }

  // ── Fullscreen / immersive mode ────────────────────────────────────────

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
      _isToolbarRevealed = false;
    });
    if (_isFullscreen) {
      _toolbarAnimController.reverse();
    } else {
      _hideToolbarTimer?.cancel();
      _toolbarAnimController.forward();
    }
  }

  void _revealToolbar() {
    _hideToolbarTimer?.cancel();
    if (!_isToolbarRevealed) {
      setState(() => _isToolbarRevealed = true);
      _toolbarAnimController.forward();
    }
  }

  void _scheduleHideToolbar() {
    _hideToolbarTimer?.cancel();
    _hideToolbarTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted && _isFullscreen) {
        setState(() => _isToolbarRevealed = false);
        _toolbarAnimController.reverse();
      }
    });
  }

  // ── Navigation helpers ─────────────────────────────────────────────────

  void _navigateToUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) return;

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      if (url.contains('.') && !url.contains(' ')) {
        url = 'https://$url';
      } else {
        final engine = ref.read(selectedSearchEngineProvider);
        url = '${engine.searchUrlTemplate}${Uri.encodeComponent(url)}';
      }
    }

    activeController?.loadUrl(url);
    _urlFocusNode.unfocus();
  }

  void _goHome() {
    // The Home button returns to the start page (the bookmark grid), which is
    // rendered whenever the tab URL is about:blank — that's the page users
    // actually want to get back to, not a configured web homepage.
    activeController?.loadUrl('about:blank');
  }

  Future<void> _openExternal() async {
    final currentUrl = await activeController?.currentUrl();
    if (currentUrl != null) {
      final uri = Uri.tryParse(currentUrl);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  void _navigateFromPanel(String url) {
    activeController?.loadUrl(url);
  }

  // ── Context menu & bookmark ────────────────────────────────────────────

  Future<void> _showContextMenu(Offset position) async {
    final currentUrl = await activeController?.currentUrl();
    if (currentUrl == null || currentUrl == 'about:blank') return;
    if (!mounted) return;

    final isVideoLink = VideoUrlDetector.detect(currentUrl).isVideoPage;
    final action = await BrowserLinkContextMenu.show(
      context,
      position: position,
      linkUrl: currentUrl,
      isVideoLink: isVideoLink,
    );
    if (action == null || !mounted) return;

    switch (action) {
      case BrowserContextAction.downloadVideo:
        onDownloadTapped();
      case BrowserContextAction.copyLink:
        BrowserLinkContextMenu.copyToClipboard(context, currentUrl);
      case BrowserContextAction.openNewTab:
        final tabNotifier = ref.read(browserTabsProvider.notifier);
        final newId = tabNotifier.addTab(url: currentUrl);
        if (newId != null) initControllerForTab(newId, currentUrl);
      case BrowserContextAction.openExternal:
        final uri = Uri.tryParse(currentUrl);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
    }
  }

  void _toggleBookmark() {
    final url = _urlController.text;
    if (url.isEmpty || url == 'about:blank') return;

    final bookmarkService = ref.read(browserBookmarkServiceProvider);
    final tabState = ref.read(browserTabsProvider);
    final title = tabState.activeTab?.title ?? url;
    final added = bookmarkService.toggle(url, title);
    setState(() {});

    if (added) {
      AppSnackBar.success(
        context,
        message: AppLocalizations.browserBookmarkAdded,
      );
    } else {
      AppSnackBar.info(
        context,
        message: AppLocalizations.browserBookmarkRemoved,
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final browserBg = AppColors.surface1(context);
    final detection = ref.watch(browserVideoDetectionProvider);
    final detectedVideos = ref.watch(browserDetectedVideosProvider);
    final extractionState = ref.watch(extractionProvider);
    final tabState = ref.watch(browserTabsProvider);
    final bookmarkService = ref.watch(browserBookmarkServiceProvider);
    final currentUrl = _urlController.text;
    final isBookmarked = bookmarkService.isBookmarked(currentUrl);
    final sessionHealth = ref.watch(browserSessionHealthProvider);

    // Handle "Open in Browser" when browser is already alive (Offstage)
    ref.listen<String>(browserInitialUrlProvider, (previous, next) {
      if (previous != null && next != previous && next != _urlController.text) {
        activeController?.loadUrl(next);
      }
    });

    ref.listen<ExtractionState>(extractionProvider, (previous, next) {
      if (next.hasError && previous?.error != next.error) {
        final error = next.error!;
        final failedUrl = next.extractingUrl;
        ref.read(extractionProvider.notifier).clearError();
        unawaited(handleBrowserExtractionError(error, failedUrl));
      }
      if (next.hasPendingResult &&
          previous?.pendingVideoInfo != next.pendingVideoInfo) {
        // Atomically consume to prevent duplicate dialog from home listener
        final videoInfo =
            ref.read(extractionProvider.notifier).consumePendingResult();
        if (videoInfo != null) {
          ref
              .read(extractionHistoryProvider.notifier)
              .addExtraction(videoInfo.url, videoInfo);
          triggerPreloadIfDirect(videoInfo);
          handleDownloadDecision(videoInfo);
        }
      }
    });

    final activeCtrl = _controllers[tabState.activeTabId];
    final mod =
        Platform.isMacOS ? LogicalKeyboardKey.meta : LogicalKeyboardKey.control;
    final activeTabUrl = tabState.activeTab?.url ?? '';
    final isNewTabPage = activeTabUrl.isEmpty || activeTabUrl == 'about:blank';

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(mod, LogicalKeyboardKey.keyF): const ToggleFindIntent(),
        LogicalKeySet(mod, LogicalKeyboardKey.keyT): const NewTabIntent(),
        LogicalKeySet(mod, LogicalKeyboardKey.keyL): const FocusUrlIntent(),
        LogicalKeySet(mod, LogicalKeyboardKey.keyR): const ReloadIntent(),
        LogicalKeySet(LogicalKeyboardKey.f11): const ToggleFullscreenIntent(),
        LogicalKeySet(LogicalKeyboardKey.escape): const ExitFullscreenIntent(),
        // Tab management
        LogicalKeySet(mod, LogicalKeyboardKey.keyW): const CloseTabIntent(),
        // Tab switching: Cmd+Shift+]/[ (macOS) or Ctrl+Tab/Ctrl+Shift+Tab
        if (Platform.isMacOS) ...{
          LogicalKeySet(
                mod,
                LogicalKeyboardKey.shift,
                LogicalKeyboardKey.bracketRight,
              ):
              const NextTabIntent(),
          LogicalKeySet(
                mod,
                LogicalKeyboardKey.shift,
                LogicalKeyboardKey.bracketLeft,
              ):
              const PrevTabIntent(),
        } else ...{
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.tab):
              const NextTabIntent(),
          LogicalKeySet(
                LogicalKeyboardKey.control,
                LogicalKeyboardKey.shift,
                LogicalKeyboardKey.tab,
              ):
              const PrevTabIntent(),
        },
        // Navigation: Alt+Left/Right for back/forward
        LogicalKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.arrowLeft):
            const GoBackIntent(),
        LogicalKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.arrowRight):
            const GoForwardIntent(),
      },
      child: Actions(
        actions: {
          ToggleFindIntent: CallbackAction<ToggleFindIntent>(
            onInvoke: (_) {
              toggleFindBar();
              return null;
            },
          ),
          NewTabIntent: CallbackAction<NewTabIntent>(
            onInvoke: (_) {
              onNewTab();
              return null;
            },
          ),
          FocusUrlIntent: CallbackAction<FocusUrlIntent>(
            onInvoke: (_) {
              _urlFocusNode.requestFocus();
              _urlController.selection = TextSelection(
                baseOffset: 0,
                extentOffset: _urlController.text.length,
              );
              return null;
            },
          ),
          ReloadIntent: CallbackAction<ReloadIntent>(
            onInvoke: (_) {
              activeController?.reload();
              return null;
            },
          ),
          ToggleFullscreenIntent: CallbackAction<ToggleFullscreenIntent>(
            onInvoke: (_) {
              _toggleFullscreen();
              return null;
            },
          ),
          ExitFullscreenIntent: CallbackAction<ExitFullscreenIntent>(
            onInvoke: (_) {
              if (_isFullscreen) _toggleFullscreen();
              return null;
            },
          ),
          CloseTabIntent: CallbackAction<CloseTabIntent>(
            onInvoke: (_) {
              final activeTab = ref.read(browserTabsProvider).activeTab;
              if (activeTab != null) onTabClose(activeTab.id);
              return null;
            },
          ),
          NextTabIntent: CallbackAction<NextTabIntent>(
            onInvoke: (_) {
              final state = ref.read(browserTabsProvider);
              final tabs = state.tabs;
              if (tabs.length <= 1) return null;
              final currentIdx = tabs.indexWhere(
                (t) => t.id == state.activeTabId,
              );
              final nextIdx = (currentIdx + 1) % tabs.length;
              onTabSwitch(tabs[nextIdx].id);
              return null;
            },
          ),
          PrevTabIntent: CallbackAction<PrevTabIntent>(
            onInvoke: (_) {
              final state = ref.read(browserTabsProvider);
              final tabs = state.tabs;
              if (tabs.length <= 1) return null;
              final currentIdx = tabs.indexWhere(
                (t) => t.id == state.activeTabId,
              );
              final prevIdx = (currentIdx - 1 + tabs.length) % tabs.length;
              onTabSwitch(tabs[prevIdx].id);
              return null;
            },
          ),
          GoBackIntent: CallbackAction<GoBackIntent>(
            onInvoke: (_) {
              if (_canGoBack) activeController?.goBack();
              return null;
            },
          ),
          GoForwardIntent: CallbackAction<GoForwardIntent>(
            onInvoke: (_) {
              if (_canGoForward) activeController?.goForward();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: browserBg,
            body: _buildBody(
              detection,
              isBookmarked,
              sessionHealth,
              cs,
              isNewTabPage,
              activeCtrl,
              tabState,
              detectedVideos,
              extractionState,
            ),
            // FAB removed — Signal Intelligence panel handles downloads
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    VideoUrlDetection? detection,
    bool isBookmarked,
    AsyncValue<CookieSessionSummary?> sessionHealth,
    ColorScheme cs,
    bool isNewTabPage,
    AppWebViewController? activeCtrl,
    dynamic tabState,
    List<DetectedVideoLink> detectedVideos,
    ExtractionState extractionState,
  ) {
    return Stack(
      children: [
        Column(
          children: [
            // Toolbar + tab bar
            SizeTransition(
              sizeFactor: _toolbarAnim,
              axisAlignment: -1.0,
              child: MouseRegion(
                onEnter: (_) {
                  if (_isFullscreen) _revealToolbar();
                },
                onExit: (_) {
                  if (_isFullscreen) _scheduleHideToolbar();
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BrowserToolbar(
                      urlController: _urlController,
                      urlFocusNode: _urlFocusNode,
                      layerLink: _layerLink,
                      canGoBack: _canGoBack,
                      canGoForward: _canGoForward,
                      isLoading: _isLoading,
                      isBookmarked: isBookmarked,
                      isFullscreen: _isFullscreen,
                      isExtracting: extractionState.isExtracting,
                      detection: detection,
                      sessionHealth: sessionHealth,
                      onPrefixDownloadTapped: onDownloadTapped,
                      onGoBack: () => activeController?.goBack(),
                      onGoForward: () => activeController?.goForward(),
                      onReloadOrStop:
                          _isLoading
                              ? () => activeController?.loadUrl('about:blank')
                              : () => activeController?.reload(),
                      onHome: _goHome,
                      onToggleBookmark: _toggleBookmark,
                      onOpenExternal: _openExternal,
                      onToggleFullscreen: _toggleFullscreen,
                      onNavigateToUrl: _navigateToUrl,
                      onNavigateFromPanel: _navigateFromPanel,
                    ),
                    BrowserTabBar(
                      onTabSwitch: onTabSwitch,
                      onTabClose: onTabClose,
                      onNewTab: onNewTab,
                      onNewIncognitoTab: onNewIncognitoTab,
                    ),
                  ],
                ),
              ),
            ),
            // Banners
            if (_currentSuggestion != null)
              ContextualSuggestionBanner(
                suggestion: _currentSuggestion!,
                onDismiss: () {
                  _dismissedSuggestionUrls.add(_urlController.text);
                  setState(() => _currentSuggestion = null);
                },
                onDownload: () {
                  _dismissedSuggestionUrls.add(_urlController.text);
                  setState(() => _currentSuggestion = null);
                  _navigateToUrl(_urlController.text);
                },
              ),
            if (showFindBar)
              FindInPageBar(
                key: findBarKey,
                onSearch: onFindSearch,
                onNext: onFindNext,
                onPrevious: onFindPrevious,
                onClose: closeFindBar,
                currentMatch: findCurrentMatch,
                totalMatches: findTotalMatches,
              ),
            if (_isLoading)
              ClipRRect(
                borderRadius: BorderRadius.circular(1),
                child: LinearProgressIndicator(
                  value: _loadingProgress > 0 ? _loadingProgress : null,
                  minHeight: 2.5,
                  backgroundColor: AppColors.accentHighlight.withValues(
                    alpha: AppOpacity.hover,
                  ),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColors.accentHighlight,
                  ),
                ),
              ),
            if (_errorMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                color: cs.errorContainer,
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 16,
                      color: cs.onErrorContainer,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        AppLocalizations.browserErrorLoading,
                        style: AppTypography.metadata.copyWith(
                          color: cs.onErrorContainer,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() => _errorMessage = null);
                        activeController?.reload();
                      },
                      child: Text(AppLocalizations.browserRefresh),
                    ),
                  ],
                ),
              ),
            BrowserExpiryWarningBanner(
              healthAsync: sessionHealth,
              dismissedPlatforms: _dismissedExpiryWarnings,
              onDismiss:
                  (platform) => () {
                    setState(() => _dismissedExpiryWarnings.add(platform));
                  },
            ),
            // Content + Right-side media panel
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child:
                        Platform.isWindows
                            ? _buildWindowsContent(tabState, isNewTabPage)
                            : _buildDefaultContent(
                              tabState,
                              activeCtrl,
                              isNewTabPage,
                            ),
                  ),
                  MediaSniffPanel(activeController: activeCtrl),
                ],
              ),
            ),
            BrowserDownloadOverlay(
              onViewAllDownloads: () {
                ref.read(navigationProvider.notifier).navigateToHome();
              },
            ),
          ],
        ),
        if (_isFullscreen && !_isToolbarRevealed)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 8,
            child: MouseRegion(
              onEnter: (_) => _revealToolbar(),
              child: const SizedBox.expand(),
            ),
          ),
      ],
    );
  }

  /// Windows: Stack + Offstage keeps all tab WebViews alive during tab switch.
  /// InAppWebView widget owns the native view — unmounting destroys it.
  Widget _buildWindowsContent(dynamic tabState, bool isNewTabPage) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Keep all WebView widgets alive but hidden when not active.
        // SizedBox.expand ensures WebView2 native control gets explicit dimensions
        // (platform views on Windows default to 0x0 with loose constraints).
        for (final entry in _controllers.entries)
          Offstage(
            offstage: entry.key != tabState.activeTabId || isNewTabPage,
            child: SizedBox.expand(
              child: GestureDetector(
                onSecondaryTapUp:
                    (details) => _showContextMenu(details.globalPosition),
                child: entry.value.buildWidget(key: ValueKey(entry.key)),
              ),
            ),
          ),
        // NewTabPage on top when active — aurora breathes behind it
        if (isNewTabPage)
          Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: AppColors.surface1(context)),
              NewTabPage(
                onNavigate: _navigateToUrl,
                onSearch: (query) {
                  final engine = ref.read(selectedSearchEngineProvider);
                  final url =
                      '${engine.searchUrlTemplate}${Uri.encodeComponent(query)}';
                  _navigateToUrl(url);
                },
              ),
            ],
          ),
      ],
    );
  }

  /// macOS/Linux: Single active WebView — controller preserves state across rebuilds.
  Widget _buildDefaultContent(
    dynamic tabState,
    AppWebViewController? activeCtrl,
    bool isNewTabPage,
  ) {
    if (isNewTabPage) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: AppColors.surface1(context)),
          NewTabPage(
            onNavigate: _navigateToUrl,
            onSearch: (query) {
              final engine = ref.read(selectedSearchEngineProvider);
              final url =
                  '${engine.searchUrlTemplate}${Uri.encodeComponent(query)}';
              _navigateToUrl(url);
            },
          ),
        ],
      );
    }
    if (activeCtrl != null) {
      return GestureDetector(
        onSecondaryTapUp: (details) => _showContextMenu(details.globalPosition),
        child: activeCtrl.buildWidget(key: ValueKey(tabState.activeTabId)),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }
}
