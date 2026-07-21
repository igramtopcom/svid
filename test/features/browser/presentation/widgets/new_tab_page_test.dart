import 'package:flutter_test/flutter_test.dart';

import 'package:svid/features/browser/domain/entities/browser_history_entry.dart';

/// Test the NewTabPage top-visited-sites algorithm.
///
/// Since `_getTopVisitedSites` is private, we replicate its logic here
/// to test the dedup-by-host + take(N) behavior.
List<QuickAccessSite> getTopVisitedSites(
  List<BrowserHistoryEntry> entries,
  int count,
) {
  final seen = <String, QuickAccessSite>{};
  for (final entry in entries) {
    if (entry.url.isEmpty ||
        entry.url == 'about:blank' ||
        entry.url.startsWith('data:')) {
      continue;
    }
    final host = Uri.tryParse(entry.url)?.host ?? '';
    if (host.isEmpty) continue;

    if (!seen.containsKey(host)) {
      seen[host] = QuickAccessSite(
        url: entry.url,
        title: entry.title.isNotEmpty ? entry.title : host,
        host: host,
      );
    }
  }

  return seen.values.take(count).toList();
}

class QuickAccessSite {
  final String url;
  final String title;
  final String host;

  const QuickAccessSite({
    required this.url,
    required this.title,
    required this.host,
  });
}

BrowserHistoryEntry _entry(String url, {String title = ''}) {
  return BrowserHistoryEntry(
    id: url.hashCode.toString(),
    url: url,
    title: title,
    visitedAt: DateTime.now(),
  );
}

void main() {
  group('NewTabPage top visited sites algorithm', () {
    test('returns empty list for empty history', () {
      final sites = getTopVisitedSites([], 8);
      expect(sites, isEmpty);
    });

    test('deduplicates by host', () {
      final entries = [
        _entry('https://www.google.com/search?q=1', title: 'Google 1'),
        _entry('https://www.google.com/search?q=2', title: 'Google 2'),
        _entry('https://www.youtube.com/watch?v=abc', title: 'YouTube'),
      ];
      final sites = getTopVisitedSites(entries, 8);
      expect(sites, hasLength(2));
      expect(sites[0].host, 'www.google.com');
      expect(sites[0].title, 'Google 1'); // First one wins
      expect(sites[1].host, 'www.youtube.com');
    });

    test('limits to requested count', () {
      final entries = [
        _entry('https://a.com', title: 'A'),
        _entry('https://b.com', title: 'B'),
        _entry('https://c.com', title: 'C'),
        _entry('https://d.com', title: 'D'),
        _entry('https://e.com', title: 'E'),
      ];
      final sites = getTopVisitedSites(entries, 3);
      expect(sites, hasLength(3));
    });

    test('filters out about:blank', () {
      final entries = [
        _entry('about:blank'),
        _entry('https://example.com', title: 'Example'),
      ];
      final sites = getTopVisitedSites(entries, 8);
      expect(sites, hasLength(1));
      expect(sites[0].host, 'example.com');
    });

    test('filters out data: URLs', () {
      final entries = [
        _entry('data:text/html,<h1>Hi</h1>'),
        _entry('https://example.com', title: 'Example'),
      ];
      final sites = getTopVisitedSites(entries, 8);
      expect(sites, hasLength(1));
    });

    test('filters out empty URLs', () {
      final entries = [
        _entry(''),
        _entry('https://example.com', title: 'Example'),
      ];
      final sites = getTopVisitedSites(entries, 8);
      expect(sites, hasLength(1));
    });

    test('uses host as title when title is empty', () {
      final entries = [
        _entry('https://example.com/page'),
      ];
      final sites = getTopVisitedSites(entries, 8);
      expect(sites[0].title, 'example.com');
    });

    test('uses provided title when available', () {
      final entries = [
        _entry('https://example.com/page', title: 'My Page'),
      ];
      final sites = getTopVisitedSites(entries, 8);
      expect(sites[0].title, 'My Page');
    });

    test('preserves first URL for each host', () {
      final entries = [
        _entry('https://example.com/page1', title: 'Page 1'),
        _entry('https://example.com/page2', title: 'Page 2'),
      ];
      final sites = getTopVisitedSites(entries, 8);
      expect(sites, hasLength(1));
      expect(sites[0].url, 'https://example.com/page1');
    });

    test('handles invalid URLs gracefully', () {
      final entries = [
        _entry('not a url at all'),
        _entry('https://valid.com', title: 'Valid'),
      ];
      final sites = getTopVisitedSites(entries, 8);
      // 'not a url at all' has empty host, filtered out
      expect(sites, hasLength(1));
      expect(sites[0].host, 'valid.com');
    });

    test('returns up to 8 distinct hosts', () {
      final entries = List.generate(
        12,
        (i) => _entry('https://site$i.com', title: 'Site $i'),
      );
      final sites = getTopVisitedSites(entries, 8);
      expect(sites, hasLength(8));
    });
  });
}
