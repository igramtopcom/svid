// Mixin accesses `mounted` via abstract getter — analyzer can't trace it
// ignore_for_file: use_build_context_synchronously
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../../premium/presentation/providers/premium_providers.dart';
import '../../data/webview/app_webview.dart';
import '../../domain/services/contextual_suggestion_service.dart';
import '../../domain/services/fingerprint_protection_service.dart';
import '../../domain/services/media_interceptor_service.dart';
import '../../domain/services/page_video_scanner_service.dart';
import '../../domain/services/phishing_detection_service.dart';
import '../../domain/services/video_url_detector.dart';
import '../providers/browser_providers.dart';
import '../providers/browser_tab_providers.dart';
import '../providers/content_filter_providers.dart';
import '../providers/media_detector_provider.dart';
import '../providers/unified_media_provider.dart';
import '../widgets/browser_phishing_dialog.dart';

/// Mixin that provides WebView controller creation, navigation delegate,
/// page-finished handling, and content-filter injection for BrowserScreen.
///
/// Extracted from _BrowserScreenState to reduce file size.
mixin BrowserNavigationMixin<T extends StatefulWidget> on State<T> {
  // ── Required abstract accessors ──

  WidgetRef get ref;
  Map<String, AppWebViewController> get controllers;
  TextEditingController get urlControllerForNav;

  // State setters the mixin needs
  void setLoadingState({required bool isLoading, double? progress, String? error});
  void setNavigationState({required bool canGoBack, required bool canGoForward});
  void setSuggestion(DownloadSuggestion? suggestion);

  Set<String> get dismissedSuggestionUrls;
  PageVideoScannerService get pageVideoScanner;

  // ── Platform-aware user-agent ─────────────────────────────────────────

  static final String _platformUserAgent = Platform.isWindows
      ? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/120.0.0.0 Safari/537.36'
      : Platform.isLinux
          ? 'Mozilla/5.0 (X11; Linux x86_64) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/120.0.0.0 Safari/537.36'
          : 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) '
            'Version/17.2 Safari/605.1.15';

  // ── WebView controller creation ────────────────────────────────────────

  AppWebViewController createController(String tabId, String url) {
    final ctrl = AppWebViewController(
      initialUrl: url,
      userAgent: _platformUserAgent,
      callbacks: _buildCallbacks(tabId),
    );
    // Register IDM media interceptor channel
    _registerMediaChannel(ctrl);
    return ctrl;
  }

  void _registerMediaChannel(AppWebViewController ctrl) {
    ctrl.addJavaScriptChannel(
      MediaInterceptorService.channelName,
      (dynamic message) {
        if (!mounted) return;
        // The interceptor batches reports into arrays (one bridge call per
        // window); older single-object messages still arrive for DRM signals.
        dynamic decoded = message;
        if (decoded is String) {
          try {
            decoded = jsonDecode(decoded);
          } catch (_) {}
        }
        final items = decoded is List ? decoded : <dynamic>[decoded];
        for (final item in items) {
          if (_isDrmSignal(item)) {
            ref.read(browserDrmDetectedProvider.notifier).state = true;
            continue;
          }
          ref.read(interceptedMediaProvider.notifier).processMessage(item);
        }
      },
    );
    // SPA navigation channel — detects URL changes in single-page apps
    ctrl.addJavaScriptChannel(
      MediaInterceptorService.spaChannelName,
      (dynamic message) {
        if (!mounted) return;
        _handleSpaNavigation(message);
      },
    );
  }

  /// Whether an interceptor message is a DRM (EME) signal rather than a media
  /// item — such pages are download-declined by policy.
  bool _isDrmSignal(dynamic message) {
    try {
      final data = message is String ? jsonDecode(message) : message;
      return data is Map && data['type'] == 'drm';
    } catch (_) {
      return false;
    }
  }

  /// Timestamp of last scroll-triggered re-scan (rate-limiting).
  DateTime _lastScrollRescan = DateTime(2000);

  /// Handle SPA navigation events (pushState/replaceState/popstate)
  /// and scroll-triggered re-scan requests.
  ///
  /// For URL changes: updates the page URL provider and re-scans DOM.
  /// For scroll: re-scans DOM on known platform feeds (rate-limited).
  /// Does NOT clear intercepted media — the network interceptor continues
  /// running and new requests will be caught independently.
  void _handleSpaNavigation(dynamic rawMessage) {
    Map<String, dynamic>? data;
    if (rawMessage is Map<String, dynamic>) {
      data = rawMessage;
    } else if (rawMessage is String) {
      try {
        data = jsonDecode(rawMessage) as Map<String, dynamic>?;
      } catch (_) {}
    }
    if (data == null) return;

    final msgType = data['type'] as String?;

    // Scroll-triggered DOM re-scan (rate-limited, feed pages only)
    if (msgType == 'scroll_update') {
      _handleScrollRescan();
      return;
    }

    final newUrl = data['url'] as String?;
    if (newUrl == null || newUrl.isEmpty) return;

    final currentUrl = ref.read(browserPageUrlProvider);
    if (newUrl == currentUrl) return;

    appLogger.debug('[SPA] URL changed: $newUrl');

    // Update page URL for unified media classification
    ref.read(browserPageUrlProvider.notifier).state = newUrl;

    // Update URL bar
    urlControllerForNav.text = newUrl;

    // Update tab info
    final activeId = ref.read(browserTabsProvider).activeTabId;
    ref.read(browserTabsProvider.notifier).updateTabInfo(
          activeId,
          url: newUrl,
          title: data['title'] as String?,
        );

    // Re-detect video page type
    final detection = VideoUrlDetector.detect(newUrl);
    ref.read(browserVideoDetectionProvider.notifier).state =
        detection.isVideoPage ? detection : null;

    // Re-scan DOM for video links after a short delay (let SPA render)
    final ctrl = controllers[activeId];
    if (ctrl != null) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        scanPageForVideos(ctrl).timeout(
          const Duration(seconds: 5),
          onTimeout: () {},
        );
      });
    }
  }

  /// Re-scan DOM after scroll on known platform pages.
  /// Rate-limited to once per 3 seconds to avoid flooding.
  void _handleScrollRescan() {
    final now = DateTime.now();
    if (now.difference(_lastScrollRescan).inSeconds < 3) return;
    _lastScrollRescan = now;

    // Only re-scan on known platform pages (where new content loads on scroll)
    final pageUrl = ref.read(browserPageUrlProvider);
    if (pageUrl == null) return;
    final platform = PlatformDetector.detectPlatform(pageUrl);
    if (platform == VideoPlatform.unknown) return;

    final activeId = ref.read(browserTabsProvider).activeTabId;
    final ctrl = controllers[activeId];
    if (ctrl != null) {
      scanPageForVideos(ctrl).timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );
    }
  }

  WebViewNavigationCallbacks _buildCallbacks(String tabId) {
    return WebViewNavigationCallbacks(
      onPageStarted: (String pageUrl) {
        if (!mounted) return;
        final activeId = ref.read(browserTabsProvider).activeTabId;
        if (tabId == activeId) {
          setLoadingState(isLoading: true, progress: 0);
          urlControllerForNav.text =
              (pageUrl == 'about:blank' || pageUrl.isEmpty) ? '' : pageUrl;
          ref.read(browserVideoDetectionProvider.notifier).state = null;
          ref.read(browserDetectedVideosProvider.notifier).state = [];
          ref.read(interceptedMediaProvider.notifier).clear();
          ref.read(browserDrmDetectedProvider.notifier).state = false;
          setSuggestion(null);
        }
        ref
            .read(browserTabsProvider.notifier)
            .updateTabInfo(tabId, url: pageUrl);
      },
      onProgress: (int progress) {
        if (!mounted) return;
        final activeId = ref.read(browserTabsProvider).activeTabId;
        if (tabId == activeId) {
          setLoadingState(isLoading: true, progress: progress / 100.0);
        }
      },
      onPageFinished: (String pageUrl) => _onPageFinished(tabId, pageUrl),
      onError: (String description, {bool isUnknown = false}) {
        if (!mounted) return;
        if (isUnknown) return;
        final activeId = ref.read(browserTabsProvider).activeTabId;
        if (tabId == activeId) {
          setLoadingState(isLoading: false, error: description);
        }
        appLogger.warning('WebView error: $description');
      },
      onNavigationRequest: (String url, bool isMainFrame) =>
          _onNavigationRequest(tabId, url, isMainFrame),
    );
  }

  /// URL we last showed the YouTube hint for, to avoid re-showing it on every
  /// SPA page-finish for the same page.
  String? _lastYtHintUrl;

  /// On a YouTube page, show a one-tap hint to download via the Home tab. The
  /// action copies the current URL and switches to Home so the user can paste
  /// (Ctrl+V) into the download field.
  void _maybeShowYouTubeDownloadHint(String pageUrl) {
    if (!mounted) return;
    if (pageUrl.isEmpty || pageUrl == 'about:blank') return;
    if (PlatformDetector.detectPlatform(pageUrl) != VideoPlatform.youtube) {
      return;
    }
    if (_lastYtHintUrl == pageUrl) return;
    _lastYtHintUrl = pageUrl;

    AppSnackBar.info(
      context,
      message: AppLocalizations.browserYoutubeUseHomeHint,
      action: SnackBarAction(
        label: AppLocalizations.browserYoutubeOpenHome,
        onPressed: () {
          Clipboard.setData(ClipboardData(text: pageUrl));
          ref.read(navigationProvider.notifier).navigateToHome();
        },
      ),
    );
  }

  Future<void> _onPageFinished(String tabId, String pageUrl) async {
    if (!mounted) return;
    final activeId = ref.read(browserTabsProvider).activeTabId;

    // Get page title
    final ctrl = controllers[tabId];
    String? title;
    if (ctrl != null) {
      try {
        title = await ctrl.getTitle();
      } catch (_) {}
    }
    ref.read(browserTabsProvider.notifier).updateTabInfo(
          tabId,
          url: pageUrl,
          title: title,
        );

    // Save to history (skip blank/empty pages and incognito tabs)
    final isPrivateTab = ref
        .read(browserTabsProvider)
        .tabs
        .any((t) => t.id == tabId && t.isPrivate);
    if (pageUrl.isNotEmpty &&
        pageUrl != 'about:blank' &&
        !pageUrl.startsWith('data:')) {
      ref.read(browserHistoryServiceProvider).addEntry(
            pageUrl,
            title ?? pageUrl,
            isPrivate: isPrivateTab,
          );
    }

    // Auto-capture platform session cookies into the DB so yt-dlp can use
    // them on the next download. Skipped for private tabs to honour the
    // incognito contract (same gate as the history write above). Fire-and-
    // forget — capture failures must never block page load.
    if (!isPrivateTab && pageUrl.isNotEmpty && !pageUrl.startsWith('data:')) {
      ref
          .read(browserCookieAutoCaptureServiceProvider)
          .captureIfLoggedIn(pageUrl);
    }

    if (tabId == activeId) {
      setLoadingState(isLoading: false, progress: 1.0);
      urlControllerForNav.text =
          (pageUrl == 'about:blank' || pageUrl.isEmpty) ? '' : pageUrl;

      // Update browser page URL for unified media provider
      ref.read(browserPageUrlProvider.notifier).state = pageUrl;

      // YouTube streams can't be captured by the in-browser sniffer (SABR /
      // session-signed googlevideo URLs) — steer the user to the Home tab where
      // yt-dlp handles it, instead of leaving them waiting on an empty panel.
      _maybeShowYouTubeDownloadHint(pageUrl);

      // Update navigation state and cache on the tab entity
      if (ctrl != null) {
        final canBack = await ctrl.canGoBack();
        final canFwd = await ctrl.canGoForward();
        if (mounted) {
          setNavigationState(canGoBack: canBack, canGoForward: canFwd);
          ref.read(browserTabsProvider.notifier).updateNavState(
                tabId,
                canGoBack: canBack,
                canGoForward: canFwd,
              );
        }
      }

      // Detect video page
      final detection = VideoUrlDetector.detect(pageUrl);
      ref.read(browserVideoDetectionProvider.notifier).state =
          detection.isVideoPage ? detection : null;

      // Contextual suggestion (playlist/series/channel)
      final suggestion = ContextualSuggestionService.analyze(pageUrl);
      if (suggestion != null &&
          !dismissedSuggestionUrls.contains(pageUrl)) {
        setSuggestion(suggestion);
      } else {
        setSuggestion(null);
      }

      // Inject content filter scripts
      if (ctrl != null) {
        await _injectContentFilterScripts(ctrl);
      }

      // Scan page for video links (batch detection)
      // Must await on Windows — WebView2 blocks UI thread on fire-and-forget JS
      if (ctrl != null) {
        await scanPageForVideos(ctrl).timeout(
          const Duration(seconds: 5),
          onTimeout: () {},
        );
      }
    }
  }

  Future<void> _injectContentFilterScripts(AppWebViewController ctrl) async {
    final parts = <String>[];
    final isPremium = ref.read(isPremiumProvider);
    if (isPremium && ref.read(adBlockEnabledProvider)) {
      parts.add(ref.read(adBlockServiceProvider).generateHideAdsScript());
    }
    if (ref.read(popupBlockEnabledProvider)) {
      parts.add(
          ref.read(popupBlockerServiceProvider).generateBlockPopupsScript());
    }
    if (ref.read(fingerprintProtectionEnabledProvider)) {
      // Skip fingerprint spoofing on auth domains (Facebook, Google, etc.)
      // — it triggers anti-bot detection and breaks login flows
      final pageUrl = ref.read(browserPageUrlProvider);
      if (FingerprintProtectionService.shouldProtect(pageUrl)) {
        parts.add(ref
            .read(fingerprintProtectionServiceProvider)
            .generateProtectionScript());
      }
    }

    // IDM mode: inject media interceptor + SPA navigation monitor
    if (ref.read(mediaSniffingEnabledProvider)) {
      parts.add(MediaInterceptorService.generateScript(
        useCallHandler: Platform.isWindows,
      ));
      parts.add(MediaInterceptorService.generateSpaMonitorScript(
        useCallHandler: Platform.isWindows,
      ));
    }

    if (parts.isEmpty) return;
    try {
      await ctrl.runJavaScript(parts.join('\n'));
    } catch (_) {}
  }

  bool _onNavigationRequest(String tabId, String url, bool isMainFrame) {
    // HTTPS enforcement -- auto-upgrade http to https
    if (isMainFrame && ref.read(httpsEnforcementEnabledProvider)) {
      final httpsService = ref.read(httpsEnforcementServiceProvider);
      if (httpsService.shouldUpgrade(url)) {
        final upgraded = httpsService.upgradeUrl(url);
        controllers[tabId]?.loadUrl(upgraded);
        return false;
      }
    }

    // Phishing detection -- warn for suspicious/dangerous URLs
    if (isMainFrame && ref.read(phishingDetectionEnabledProvider)) {
      final phishingService = ref.read(phishingDetectionServiceProvider);
      final result = phishingService.checkUrl(url);
      if (result == PhishingCheckResult.dangerous ||
          result == PhishingCheckResult.suspicious) {
        BrowserPhishingDialog.show(
          context: context,
          url: url,
          result: result,
          phishingService: phishingService,
          controller: controllers[tabId],
        );
        return false;
      }
    }

    // Ad domain blocking (premium only)
    final isAdBlockOn = ref.read(adBlockEnabledProvider);
    if (isAdBlockOn && ref.read(isPremiumProvider)) {
      final adBlocker = ref.read(adBlockServiceProvider);
      if (adBlocker.shouldBlock(url)) {
        return false;
      }
    }

    // Popup blocking (cross-origin new-window requests)
    if (!isMainFrame) {
      final isPopupBlockOn = ref.read(popupBlockEnabledProvider);
      if (isPopupBlockOn) {
        final currentUrl =
            ref.read(browserTabsProvider).activeTab?.url ?? '';
        final blocker = ref.read(popupBlockerServiceProvider);
        if (blocker.shouldBlockPopup(currentUrl, url)) {
          return false;
        }
      }
    }

    return true;
  }

  /// Scan the current page for video links via JS DOM scanning.
  Future<void> scanPageForVideos(AppWebViewController ctrl) async {
    try {
      final result = await ctrl.runJavaScriptReturningResult(
        pageVideoScanner.generateScanScript(),
      ).timeout(const Duration(seconds: 3));
      final jsonStr = result.toString();
      final videos = pageVideoScanner.parseResults(jsonStr);
      if (mounted) {
        ref.read(browserDetectedVideosProvider.notifier).state = videos;
      }
    } catch (_) {
      if (mounted) {
        ref.read(browserDetectedVideosProvider.notifier).state = [];
      }
    }
  }

  void initControllerForTab(String tabId, String url) {
    if (controllers.containsKey(tabId)) return;
    controllers[tabId] = createController(tabId, url);
  }

  AppWebViewController? get activeController {
    final activeId = ref.read(browserTabsProvider).activeTabId;
    return controllers[activeId];
  }
}
