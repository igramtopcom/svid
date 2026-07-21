import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssvid/features/browser/domain/entities/browser_tab.dart';
import 'package:ssvid/features/browser/domain/services/browser_history_service.dart';
import 'package:ssvid/features/browser/presentation/providers/browser_tab_providers.dart';

void main() {
  // ── BrowserHistoryService incognito ──
  group('BrowserHistoryService — incognito mode', () {
    late BrowserHistoryService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      service = BrowserHistoryService(prefs);
    });

    tearDown(() => service.dispose());

    test('addEntry isPrivate:false records the entry', () {
      service.addEntry('https://example.com', 'Example', isPrivate: false);
      expect(service.entries.length, 1);
      expect(service.entries.first.url, 'https://example.com');
    });

    test('addEntry isPrivate:true does NOT record the entry', () {
      service.addEntry('https://secret.com', 'Secret', isPrivate: true);
      expect(service.entries, isEmpty);
    });

    test('addEntry default (no isPrivate param) records entry', () {
      service.addEntry('https://default.com', 'Default');
      expect(service.entries.length, 1);
    });

    test('mix of private and non-private — only non-private recorded', () {
      service.addEntry('https://public.com', 'Public');
      service.addEntry('https://private.com', 'Private', isPrivate: true);
      service.addEntry('https://also-public.com', 'AlsoPublic');
      expect(service.entries.length, 2);
      expect(service.entries.map((e) => e.url),
          containsAll(['https://public.com', 'https://also-public.com']));
    });
  });

  // ── BrowserTab isPrivate field ──
  group('BrowserTab — isPrivate field', () {
    test('default isPrivate is false', () {
      final tab = BrowserTab(
        id: '1',
        url: 'https://example.com',
        createdAt: DateTime.now(),
      );
      expect(tab.isPrivate, isFalse);
    });

    test('isPrivate: true is preserved in copyWith', () {
      final tab = BrowserTab(
        id: '1',
        url: 'https://example.com',
        isPrivate: true,
        createdAt: DateTime.now(),
      );
      final copied = tab.copyWith(title: 'New Title');
      expect(copied.isPrivate, isTrue);
    });

    test('copyWith can override isPrivate', () {
      final tab = BrowserTab(
        id: '1',
        url: 'https://example.com',
        createdAt: DateTime.now(),
      );
      final privateTab = tab.copyWith(isPrivate: true);
      expect(privateTab.isPrivate, isTrue);
    });

    test('toJson/fromJson round-trip preserves isPrivate:true', () {
      final tab = BrowserTab(
        id: 'abc',
        url: 'https://example.com',
        isPrivate: true,
        createdAt: DateTime(2026, 1, 1),
      );
      final json = tab.toJson();
      final restored = BrowserTab.fromJson(json);
      expect(restored.isPrivate, isTrue);
    });

    test('toJson/fromJson round-trip preserves isPrivate:false', () {
      final tab = BrowserTab(
        id: 'xyz',
        url: 'https://example.com',
        createdAt: DateTime(2026, 1, 1),
      );
      final json = tab.toJson();
      final restored = BrowserTab.fromJson(json);
      expect(restored.isPrivate, isFalse);
    });

    test('fromJson with missing isPrivate key defaults to false', () {
      final json = {
        'id': '1',
        'url': 'https://example.com',
        'title': '',
        'isActive': false,
        'createdAt': '2026-01-01T00:00:00.000',
        // no 'isPrivate' key
      };
      final tab = BrowserTab.fromJson(json);
      expect(tab.isPrivate, isFalse);
    });
  });

  // ── BrowserTabNotifier addIncognitoTab ──
  group('BrowserTabNotifier — addIncognitoTab', () {
    late BrowserTabNotifier notifier;

    setUp(() {
      notifier = BrowserTabNotifier();
    });

    test('addIncognitoTab creates a tab with isPrivate: true', () {
      final id = notifier.addIncognitoTab();
      expect(id, isNotNull);
      final tab = notifier.state.tabs.firstWhere((t) => t.id == id!);
      expect(tab.isPrivate, isTrue);
    });

    test('addTab creates a tab with isPrivate: false', () {
      final id = notifier.addTab();
      expect(id, isNotNull);
      final tab = notifier.state.tabs.firstWhere((t) => t.id == id!);
      expect(tab.isPrivate, isFalse);
    });

    test('addIncognitoTab sets title to Incognito', () {
      final id = notifier.addIncognitoTab();
      final tab = notifier.state.tabs.firstWhere((t) => t.id == id!);
      // In pure-unit test env without EasyLocalization wrap, `.tr()` returns
      // the raw key `browser.incognitoTabTitle` instead of localized
      // "Incognito". Match by either to keep the contract holding in both
      // environments.
      expect(
        tab.title == 'Incognito' || tab.title == 'browser.incognitoTabTitle',
        isTrue,
        reason:
            'Expected localized "Incognito" or raw i18n key '
            '"browser.incognitoTabTitle", got "${tab.title}"',
      );
    });

    test('addIncognitoTab returns null when max tabs reached', () {
      // Fill up to max
      for (var i = 0; i < BrowserTabNotifier.maxTabs - 1; i++) {
        notifier.addTab();
      }
      expect(notifier.state.tabs.length, BrowserTabNotifier.maxTabs);
      final id = notifier.addIncognitoTab();
      expect(id, isNull);
    });
  });
}
