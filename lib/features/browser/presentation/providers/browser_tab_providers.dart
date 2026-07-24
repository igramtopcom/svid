import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/browser_bookmark.dart';
import '../../domain/entities/browser_history_entry.dart';
import '../../domain/entities/browser_tab.dart';
import '../../domain/services/browser_bookmark_service.dart';
import '../../domain/services/browser_history_service.dart';

// ── Tab State ──

class BrowserTabState {
  final List<BrowserTab> tabs;
  final String activeTabId;

  const BrowserTabState({
    required this.tabs,
    required this.activeTabId,
  });

  BrowserTab? get activeTab {
    final index = tabs.indexWhere((t) => t.id == activeTabId);
    return index >= 0 ? tabs[index] : null;
  }

  int get tabCount => tabs.length;
}

// ── Tab Notifier ──

class BrowserTabNotifier extends StateNotifier<BrowserTabState> {
  static const int maxTabs = 10;
  static const _uuid = Uuid();

  BrowserTabNotifier() : super(_createInitialState());

  static BrowserTabState _createInitialState() {
    final id = _uuid.v4();
    return BrowserTabState(
      tabs: [
        BrowserTab(
          id: id,
          url: 'about:blank',
          title: AppLocalizations.browserNewTabTitle,
          isActive: true,
          createdAt: DateTime.now(),
        ),
      ],
      activeTabId: id,
    );
  }

  /// Add a new tab. Returns the new tab ID, or null if max reached.
  String? addTab({String? url}) {
    if (state.tabs.length >= maxTabs) return null;

    final id = _uuid.v4();
    final newTab = BrowserTab(
      id: id,
      // Open the bookmark start page by default (not an external search engine).
      url: url ?? 'about:blank',
      title: AppLocalizations.browserNewTabTitle,
      isActive: true,
      createdAt: DateTime.now(),
    );

    // Deactivate all existing tabs
    final updatedTabs = state.tabs
        .map((t) => t.isActive ? t.copyWith(isActive: false) : t)
        .toList();
    updatedTabs.add(newTab);

    state = BrowserTabState(tabs: updatedTabs, activeTabId: id);
    return id;
  }

  /// Add a new incognito (private) tab. History and cookies not persisted.
  /// Returns the new tab ID, or null if max tabs reached.
  String? addIncognitoTab({String? url}) {
    if (state.tabs.length >= maxTabs) return null;

    final id = _uuid.v4();
    final newTab = BrowserTab(
      id: id,
      url: url ?? 'about:blank',
      title: AppLocalizations.browserIncognitoTabTitle,
      isActive: true,
      isPrivate: true,
      createdAt: DateTime.now(),
    );

    final updatedTabs = state.tabs
        .map((t) => t.isActive ? t.copyWith(isActive: false) : t)
        .toList();
    updatedTabs.add(newTab);

    state = BrowserTabState(tabs: updatedTabs, activeTabId: id);
    return id;
  }

  /// Close a tab by ID. If last tab, creates a new blank one.
  void closeTab(String id) {
    if (state.tabs.length == 1) {
      // Last tab — replace with a blank tab that shows the bookmark start page
      // (same as the Home button), not an external search engine.
      final newId = _uuid.v4();
      state = BrowserTabState(
        tabs: [
          BrowserTab(
            id: newId,
            url: 'about:blank',
            title: AppLocalizations.browserNewTabTitle,
            isActive: true,
            createdAt: DateTime.now(),
          ),
        ],
        activeTabId: newId,
      );
      return;
    }

    final index = state.tabs.indexWhere((t) => t.id == id);
    if (index < 0) return;

    final wasActive = state.tabs[index].id == state.activeTabId;
    final remaining = state.tabs.where((t) => t.id != id).toList();

    String newActiveId = state.activeTabId;
    if (wasActive) {
      // Switch to adjacent tab (prefer right, then left)
      final newIndex = index < remaining.length ? index : remaining.length - 1;
      newActiveId = remaining[newIndex].id;
      remaining[newIndex] = remaining[newIndex].copyWith(isActive: true);
    }

    state = BrowserTabState(tabs: remaining, activeTabId: newActiveId);
  }

  /// Switch to a specific tab
  void switchTab(String id) {
    if (id == state.activeTabId) return;
    if (!state.tabs.any((t) => t.id == id)) return;

    final updatedTabs = state.tabs.map((t) {
      if (t.id == id) return t.copyWith(isActive: true);
      if (t.isActive) return t.copyWith(isActive: false);
      return t;
    }).toList();

    state = BrowserTabState(tabs: updatedTabs, activeTabId: id);
  }

  /// Update cached navigation state for a tab
  void updateNavState(String id, {bool? canGoBack, bool? canGoForward}) {
    final updatedTabs = state.tabs.map((t) {
      if (t.id == id) {
        return t.copyWith(
          canGoBack: canGoBack ?? t.canGoBack,
          canGoForward: canGoForward ?? t.canGoForward,
        );
      }
      return t;
    }).toList();
    state = BrowserTabState(tabs: updatedTabs, activeTabId: state.activeTabId);
  }

  /// Update tab info (URL, title) from WebView callbacks
  void updateTabInfo(String id, {String? url, String? title}) {
    final updatedTabs = state.tabs.map((t) {
      if (t.id == id) {
        return t.copyWith(
          url: url ?? t.url,
          title: title ?? t.title,
        );
      }
      return t;
    }).toList();

    state = BrowserTabState(tabs: updatedTabs, activeTabId: state.activeTabId);
  }
}

// ── Providers ──

final browserTabsProvider =
    StateNotifierProvider<BrowserTabNotifier, BrowserTabState>((ref) {
  return BrowserTabNotifier();
});

final browserHistoryServiceProvider = Provider<BrowserHistoryService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final service = BrowserHistoryService(prefs);
  ref.onDispose(() => service.dispose());
  return service;
});

final browserBookmarkServiceProvider = Provider<BrowserBookmarkService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final service = BrowserBookmarkService(prefs);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Stream of browsing history changes
final browserHistoryStreamProvider =
    StreamProvider<List<BrowserHistoryEntry>>((ref) {
  final service = ref.watch(browserHistoryServiceProvider);
  return Stream.value(service.entries).asyncExpand(
    (initial) => Stream.multi((controller) {
      controller.add(initial);
      final sub = service.stream.listen(controller.add);
      controller.onCancel = () => sub.cancel();
    }),
  );
});

/// Stream of bookmark changes
final browserBookmarkStreamProvider =
    StreamProvider<List<BrowserBookmark>>((ref) {
  final service = ref.watch(browserBookmarkServiceProvider);
  return Stream.value(service.bookmarks).asyncExpand(
    (initial) => Stream.multi((controller) {
      controller.add(initial);
      final sub = service.stream.listen(controller.add);
      controller.onCancel = () => sub.cancel();
    }),
  );
});
