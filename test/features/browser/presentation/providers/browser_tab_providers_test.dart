import 'package:flutter_test/flutter_test.dart';

import 'package:ssvid/features/browser/presentation/providers/browser_tab_providers.dart';

void main() {
  late BrowserTabNotifier notifier;

  setUp(() {
    notifier = BrowserTabNotifier();
  });

  group('BrowserTabNotifier', () {
    test('starts with one active tab', () {
      expect(notifier.state.tabs.length, 1);
      expect(notifier.state.activeTab, isNotNull);
      expect(notifier.state.activeTab!.isActive, isTrue);
      expect(notifier.state.activeTab!.url, 'about:blank');
    });

    test('addTab creates new tab and switches to it', () {
      final firstTabId = notifier.state.activeTabId;
      final newId = notifier.addTab(url: 'https://youtube.com');

      expect(newId, isNotNull);
      expect(notifier.state.tabs.length, 2);
      expect(notifier.state.activeTabId, newId);
      expect(notifier.state.activeTab!.url, 'https://youtube.com');
      // Previous tab deactivated
      final firstTab =
          notifier.state.tabs.firstWhere((t) => t.id == firstTabId);
      expect(firstTab.isActive, isFalse);
    });

    test('addTab defaults to google.com when no URL provided', () {
      notifier.addTab();
      expect(notifier.state.activeTab!.url, 'https://www.google.com');
    });

    test('addTab enforces max 10 tabs', () {
      // Already has 1, add 9 more
      for (int i = 0; i < 9; i++) {
        notifier.addTab(url: 'https://site$i.com');
      }
      expect(notifier.state.tabs.length, 10);

      // 11th should fail
      final result = notifier.addTab(url: 'https://overflow.com');
      expect(result, isNull);
      expect(notifier.state.tabs.length, 10);
    });

    test('closeTab removes tab and switches to adjacent', () {
      notifier.state.activeTabId; // first tab exists
      final secondId = notifier.addTab(url: 'https://b.com');
      final thirdId = notifier.addTab(url: 'https://c.com');

      // Close active (third), should switch to second
      notifier.closeTab(thirdId!);
      expect(notifier.state.tabs.length, 2);
      expect(notifier.state.activeTabId, secondId);
    });

    test('closeTab on last tab creates a new blank tab', () {
      final onlyTabId = notifier.state.activeTabId;
      notifier.closeTab(onlyTabId);

      expect(notifier.state.tabs.length, 1);
      expect(notifier.state.activeTab, isNotNull);
      expect(notifier.state.activeTab!.url, 'https://www.google.com');
      // Different ID from original
      expect(notifier.state.activeTabId, isNot(onlyTabId));
    });

    test('closeTab on non-active tab does not change active', () {
      final firstId = notifier.state.activeTabId;
      final secondId = notifier.addTab(url: 'https://b.com');

      // Switch back to first
      notifier.switchTab(firstId);

      // Close second (non-active)
      notifier.closeTab(secondId!);
      expect(notifier.state.tabs.length, 1);
      expect(notifier.state.activeTabId, firstId);
    });

    test('switchTab changes active tab', () {
      final firstId = notifier.state.activeTabId;
      notifier.addTab(url: 'https://b.com');

      notifier.switchTab(firstId);
      expect(notifier.state.activeTabId, firstId);
      expect(notifier.state.activeTab!.isActive, isTrue);
    });

    test('switchTab with same ID is no-op', () {
      final currentId = notifier.state.activeTabId;
      notifier.switchTab(currentId);
      expect(notifier.state.activeTabId, currentId);
    });

    test('switchTab with non-existent ID is no-op', () {
      final currentId = notifier.state.activeTabId;
      notifier.switchTab('non-existent');
      expect(notifier.state.activeTabId, currentId);
    });

    test('updateTabInfo updates URL and title', () {
      final tabId = notifier.state.activeTabId;
      notifier.updateTabInfo(tabId,
          url: 'https://updated.com', title: 'Updated');

      expect(notifier.state.activeTab!.url, 'https://updated.com');
      expect(notifier.state.activeTab!.title, 'Updated');
    });

    test('updateTabInfo with only URL', () {
      final tabId = notifier.state.activeTabId;
      notifier.updateTabInfo(tabId, url: 'https://new-url.com');

      expect(notifier.state.activeTab!.url, 'https://new-url.com');
      // In pure-unit test env without EasyLocalization wrap, `.tr()` returns
      // the raw key `browser.newTabTitle` instead of localized "New Tab".
      // Match by either to keep the contract holding in both environments.
      final title = notifier.state.activeTab!.title;
      expect(
        title == 'New Tab' || title == 'browser.newTabTitle',
        isTrue,
        reason:
            'Expected localized "New Tab" or raw i18n key '
            '"browser.newTabTitle", got "$title"',
      );
    });

    test('updateTabInfo with only title', () {
      final tabId = notifier.state.activeTabId;
      notifier.updateTabInfo(tabId, title: 'My Title');

      expect(notifier.state.activeTab!.url, 'about:blank');
      expect(notifier.state.activeTab!.title, 'My Title');
    });

    test('tabCount returns correct count', () {
      expect(notifier.state.tabCount, 1);
      notifier.addTab();
      expect(notifier.state.tabCount, 2);
      notifier.addTab();
      expect(notifier.state.tabCount, 3);
    });

    test('new tabs default canGoBack and canGoForward to false', () {
      final tab = notifier.state.activeTab!;
      expect(tab.canGoBack, isFalse);
      expect(tab.canGoForward, isFalse);

      notifier.addTab(url: 'https://example.com');
      final newTab = notifier.state.activeTab!;
      expect(newTab.canGoBack, isFalse);
      expect(newTab.canGoForward, isFalse);
    });

    test('updateNavState updates canGoBack and canGoForward', () {
      final tabId = notifier.state.activeTabId;

      notifier.updateNavState(tabId, canGoBack: true, canGoForward: true);
      expect(notifier.state.activeTab!.canGoBack, isTrue);
      expect(notifier.state.activeTab!.canGoForward, isTrue);

      notifier.updateNavState(tabId, canGoBack: false);
      expect(notifier.state.activeTab!.canGoBack, isFalse);
      expect(notifier.state.activeTab!.canGoForward, isTrue);
    });

    test('updateNavState only affects specified tab', () {
      final firstId = notifier.state.activeTabId;
      notifier.addTab(url: 'https://b.com');

      notifier.updateNavState(firstId, canGoBack: true, canGoForward: true);
      // Second tab (active) should remain unchanged
      expect(notifier.state.activeTab!.canGoBack, isFalse);
      expect(notifier.state.activeTab!.canGoForward, isFalse);

      // First tab should be updated
      final firstTab =
          notifier.state.tabs.firstWhere((t) => t.id == firstId);
      expect(firstTab.canGoBack, isTrue);
      expect(firstTab.canGoForward, isTrue);
    });
  });
}
