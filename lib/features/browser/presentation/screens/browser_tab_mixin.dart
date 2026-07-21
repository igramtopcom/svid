// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../data/webview/app_webview.dart';
import '../../domain/services/video_url_detector.dart';
import '../providers/browser_providers.dart';
import '../providers/browser_tab_providers.dart';
import '../providers/content_filter_providers.dart';

/// Mixin that provides tab management logic for BrowserScreen.
///
/// Extracted from _BrowserScreenState to reduce file size.
mixin BrowserTabMixin<T extends StatefulWidget> on State<T> {
  // ── Required abstract accessors ──

  WidgetRef get ref;
  Map<String, AppWebViewController> get controllers;
  TextEditingController get urlControllerForTab;

  void initControllerForTab(String tabId, String url);
  void resetTabUiState();

  void onNewTab() {
    final tabNotifier = ref.read(browserTabsProvider.notifier);
    final newId = tabNotifier.addTab(url: 'about:blank');
    if (newId != null) {
      initControllerForTab(newId, 'about:blank');
      urlControllerForTab.text = '';
      resetTabUiState();
    } else {
      AppSnackBar.info(context,
          message: AppLocalizations.browserMaxTabsReached);
    }
  }

  void onNewIncognitoTab() {
    final tabNotifier = ref.read(browserTabsProvider.notifier);
    final newId = tabNotifier.addIncognitoTab();
    if (newId != null) {
      initControllerForTab(newId, 'about:blank');
      urlControllerForTab.text = '';
      resetTabUiState();
      AppSnackBar.info(context,
          message: AppLocalizations.browserIncognitoNoHistory);
    } else {
      AppSnackBar.info(context,
          message: AppLocalizations.browserMaxTabsReached);
    }
  }

  void onTabSwitch(String tabId) {
    final tabNotifier = ref.read(browserTabsProvider.notifier);
    tabNotifier.switchTab(tabId);

    final tab =
        ref.read(browserTabsProvider).tabs.firstWhere((t) => t.id == tabId);
    initControllerForTab(tabId, tab.url);

    urlControllerForTab.text =
        (tab.url == 'about:blank' || tab.url.isEmpty) ? '' : tab.url;
    resetTabUiState();

    // Use cached navigation state — no async queries needed
    onTabNavStateChanged(canGoBack: tab.canGoBack, canGoForward: tab.canGoForward);

    // Video detection from cached URL (sync)
    final detection = VideoUrlDetector.detect(tab.url);
    ref.read(browserVideoDetectionProvider.notifier).state =
        detection.isVideoPage ? detection : null;
  }

  /// Called by tab switch to update individual nav state values.
  void onTabNavStateChanged({bool? canGoBack, bool? canGoForward});

  void onTabClose(String tabId) {
    final tabNotifier = ref.read(browserTabsProvider.notifier);
    final tabs = ref.read(browserTabsProvider).tabs;
    final closingTab = tabs.firstWhere((t) => t.id == tabId,
        orElse: () => tabs.first);
    final wasActive =
        ref.read(browserTabsProvider).activeTabId == tabId;

    // Cleanup controller resources before dropping reference
    final closingCtrl = controllers[tabId];
    if (closingCtrl != null) {
      if (closingTab.isPrivate && mounted) {
        AppSnackBar.info(context,
            message: AppLocalizations.browserIncognitoCookiesCleared);
      }
      // Release page resources — load blank + clear storage for all tabs
      closingCtrl.loadUrl('about:blank');
      closingCtrl.clearLocalStorage().catchError((_) {});
    }

    tabNotifier.closeTab(tabId);
    controllers.remove(tabId);

    if (wasActive) {
      final newState = ref.read(browserTabsProvider);
      final newActiveId = newState.activeTabId;
      final newTab = newState.activeTab;

      final homePage = ref.read(browserHomePageProvider);
      initControllerForTab(newActiveId, newTab?.url ?? homePage);
      final newUrl = newTab?.url ?? homePage;
      urlControllerForTab.text =
          (newUrl == 'about:blank' || newUrl.isEmpty) ? '' : newUrl;
      resetTabUiState();
    }
  }
}
