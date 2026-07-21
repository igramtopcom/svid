import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/settings/presentation/widgets/settings_search_delegate.dart';

void main() {
  late SettingsSearchDelegate delegate;

  final testEntries = [
    const SettingsSearchResult(
      sectionIndex: 0,
      sectionLabel: 'General',
      sectionIcon: Icons.tune,
      settingLabel: 'Theme',
    ),
    const SettingsSearchResult(
      sectionIndex: 0,
      sectionLabel: 'General',
      sectionIcon: Icons.tune,
      settingLabel: 'Language',
    ),
    const SettingsSearchResult(
      sectionIndex: 0,
      sectionLabel: 'General',
      sectionIcon: Icons.tune,
      settingLabel: 'Notifications',
    ),
    const SettingsSearchResult(
      sectionIndex: 1,
      sectionLabel: 'Downloads',
      sectionIcon: Icons.download,
      settingLabel: 'Download Path',
    ),
    const SettingsSearchResult(
      sectionIndex: 1,
      sectionLabel: 'Downloads',
      sectionIcon: Icons.download,
      settingLabel: 'Concurrent Downloads',
    ),
    const SettingsSearchResult(
      sectionIndex: 1,
      sectionLabel: 'Downloads',
      sectionIcon: Icons.download,
      settingLabel: 'Auto-Start Downloads',
    ),
    const SettingsSearchResult(
      sectionIndex: 2,
      sectionLabel: 'Quality & Format',
      sectionIcon: Icons.high_quality,
      settingLabel: 'Video Codec',
    ),
    const SettingsSearchResult(
      sectionIndex: 2,
      sectionLabel: 'Quality & Format',
      sectionIcon: Icons.high_quality,
      settingLabel: 'Audio Codec',
    ),
    const SettingsSearchResult(
      sectionIndex: 3,
      sectionLabel: 'Network & Proxy',
      sectionIcon: Icons.wifi,
      settingLabel: 'Proxy',
    ),
    const SettingsSearchResult(
      sectionIndex: 4,
      sectionLabel: 'About & Support',
      sectionIcon: Icons.info_outline,
      settingLabel: 'Reset to Defaults',
    ),
  ];

  setUp(() {
    delegate = SettingsSearchDelegate.forTest(testEntries);
  });

  group('SettingsSearchDelegate', () {
    test('empty query returns empty list', () {
      expect(delegate.search(''), isEmpty);
    });

    test('whitespace-only query returns empty list', () {
      expect(delegate.search('   '), isEmpty);
    });

    test('finds exact match on label', () {
      final results = delegate.search('Theme');
      expect(results.length, 1);
      expect(results.first.settingLabel, 'Theme');
      expect(results.first.sectionIndex, 0);
    });

    test('case-insensitive search', () {
      final results = delegate.search('theme');
      expect(results.length, 1);
      expect(results.first.settingLabel, 'Theme');
    });

    test('partial match on label', () {
      final results = delegate.search('down');
      // Matches: "Download Path", "Concurrent Downloads", "Auto-Start Downloads", "Downloads" (section)
      expect(results.length, greaterThanOrEqualTo(3));
      expect(
        results.every(
          (r) =>
              r.settingLabel.toLowerCase().contains('down') ||
              r.sectionLabel.toLowerCase().contains('down'),
        ),
        isTrue,
      );
    });

    test('matches section label', () {
      final results = delegate.search('General');
      // All 3 General section entries match via section label
      expect(results.length, 3);
      expect(results.every((r) => r.sectionIndex == 0), isTrue);
    });

    test('no match returns empty', () {
      final results = delegate.search('zzzzzzz');
      expect(results, isEmpty);
    });

    test('search with leading/trailing spaces trims query', () {
      final results = delegate.search('  Theme  ');
      expect(results.length, 1);
      expect(results.first.settingLabel, 'Theme');
    });

    test('codec search finds multiple results', () {
      final results = delegate.search('Codec');
      expect(results.length, 2);
      expect(results.map((r) => r.settingLabel).toSet(), {'Video Codec', 'Audio Codec'});
    });

    test('matchingSectionIndices returns correct set', () {
      final indices = delegate.matchingSectionIndices('Codec');
      expect(indices, {2});
    });

    test('matchingSectionIndices for broad query', () {
      final indices = delegate.matchingSectionIndices('a');
      // 'a' matches many labels: Language, Notifications, Download Path, etc.
      expect(indices.length, greaterThan(1));
    });

    test('matchingSectionIndices for empty query', () {
      final indices = delegate.matchingSectionIndices('');
      expect(indices, isEmpty);
    });

    test('invalidateCache clears cached index', () {
      // First search populates cache
      final r1 = delegate.search('Theme');
      expect(r1.length, 1);

      // Invalidate clears the cached index
      delegate.invalidateCache();

      // After invalidation, _buildIndex() is called which uses AppLocalizations
      // In test context without l10n setup, .tr() returns raw key strings.
      // The test entries injected via forTest are gone — verifying cache was cleared.
      // A search for the original label should not match the test data anymore.
      final r2 = delegate.search('Theme');
      // After invalidation, the rebuilt index uses l10n raw keys, not our test labels
      expect(r2.every((r) => r.settingLabel != 'Theme'), isTrue);
    });

    test('SettingsSearchResult stores all fields', () {
      final result = testEntries.first;
      expect(result.sectionIndex, 0);
      expect(result.sectionLabel, 'General');
      expect(result.sectionIcon, Icons.tune);
      expect(result.settingLabel, 'Theme');
    });

    test('search for proxy returns single result', () {
      final results = delegate.search('Proxy');
      // Matches: "Proxy" label + "Network & Proxy" section label
      expect(results.where((r) => r.settingLabel == 'Proxy').length, 1);
    });

    test('search for reset finds About section', () {
      final results = delegate.search('Reset');
      expect(results.length, 1);
      expect(results.first.settingLabel, 'Reset to Defaults');
      expect(results.first.sectionIndex, 4);
    });
  });
}
