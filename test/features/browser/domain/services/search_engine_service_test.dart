import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svid/features/browser/domain/services/search_engine_service.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('SearchEngine enum', () {
    test('google has correct search URL template', () {
      expect(
        SearchEngine.google.searchUrlTemplate,
        'https://www.google.com/search?q=',
      );
    });

    test('bing has correct search URL template', () {
      expect(
        SearchEngine.bing.searchUrlTemplate,
        'https://www.bing.com/search?q=',
      );
    });

    test('duckDuckGo has correct search URL template', () {
      expect(
        SearchEngine.duckDuckGo.searchUrlTemplate,
        'https://duckduckgo.com/?q=',
      );
    });

    test('yahoo has correct search URL template', () {
      expect(
        SearchEngine.yahoo.searchUrlTemplate,
        'https://search.yahoo.com/search?p=',
      );
    });

    test('brave has correct search URL template', () {
      expect(
        SearchEngine.brave.searchUrlTemplate,
        'https://search.brave.com/search?q=',
      );
    });

    test('all engines have non-empty labels', () {
      for (final engine in SearchEngine.values) {
        expect(engine.label, isNotEmpty);
      }
    });
  });

  group('SearchEngineService', () {
    late SearchEngineService service;

    setUp(() {
      service = SearchEngineService(prefs);
    });

    group('searchEngine', () {
      test('defaults to Google', () {
        expect(service.searchEngine, SearchEngine.google);
      });

      test('returns saved engine', () async {
        await service.setSearchEngine(SearchEngine.duckDuckGo);
        expect(service.searchEngine, SearchEngine.duckDuckGo);
      });

      test('falls back to Google for unknown engine name', () async {
        await prefs.setString('browser_search_engine', 'nonexistent');
        final s = SearchEngineService(prefs);
        expect(s.searchEngine, SearchEngine.google);
      });

      test('persists across instances', () async {
        await service.setSearchEngine(SearchEngine.brave);
        final newService = SearchEngineService(prefs);
        expect(newService.searchEngine, SearchEngine.brave);
      });
    });

    group('buildSearchUrl', () {
      test('builds Google search URL by default', () {
        final url = service.buildSearchUrl('flutter widgets');
        expect(url, 'https://www.google.com/search?q=flutter%20widgets');
      });

      test('builds URL with selected engine', () async {
        await service.setSearchEngine(SearchEngine.bing);
        final url = service.buildSearchUrl('dart language');
        expect(url, 'https://www.bing.com/search?q=dart%20language');
      });

      test('encodes special characters in query', () {
        final url = service.buildSearchUrl('hello & world');
        expect(url, contains('hello%20%26%20world'));
      });

      test('encodes Unicode characters', () {
        final url = service.buildSearchUrl('tìm kiếm');
        expect(url, startsWith('https://www.google.com/search?q='));
        expect(url, contains(Uri.encodeComponent('tìm kiếm')));
      });
    });

    group('homePage', () {
      test('defaults to Google', () {
        expect(service.homePage, SearchEngineService.defaultHomePage);
      });

      test('returns custom home page after set', () async {
        await service.setHomePage('https://example.com');
        expect(service.homePage, 'https://example.com');
      });

      test('trims whitespace', () async {
        await service.setHomePage('  https://example.com  ');
        expect(service.homePage, 'https://example.com');
      });

      test('resets to default when set to empty string', () async {
        await service.setHomePage('https://example.com');
        await service.setHomePage('');
        expect(service.homePage, SearchEngineService.defaultHomePage);
      });

      test('resets to default when set to whitespace only', () async {
        await service.setHomePage('https://example.com');
        await service.setHomePage('   ');
        expect(service.homePage, SearchEngineService.defaultHomePage);
      });

      test('persists across instances', () async {
        await service.setHomePage('https://custom.home');
        final newService = SearchEngineService(prefs);
        expect(newService.homePage, 'https://custom.home');
      });
    });

    group('clearBrowsingData', () {
      test('clears history and bookmarks keys', () async {
        await prefs.setString('browser_history_data', '[]');
        await prefs.setString('browser_bookmarks_data', '[]');

        final cleared = await service.clearBrowsingData();
        expect(cleared, containsAll([
          'browser_history_data',
          'browser_bookmarks_data',
        ]));
        expect(prefs.getString('browser_history_data'), isNull);
        expect(prefs.getString('browser_bookmarks_data'), isNull);
      });

      test('returns empty list when no data to clear', () async {
        final cleared = await service.clearBrowsingData();
        expect(cleared, isEmpty);
      });

      test('does not clear search engine or home page', () async {
        await service.setSearchEngine(SearchEngine.bing);
        await service.setHomePage('https://custom.home');
        await prefs.setString('browser_history_data', '[]');

        await service.clearBrowsingData();

        expect(service.searchEngine, SearchEngine.bing);
        expect(service.homePage, 'https://custom.home');
      });
    });

    group('defaultHomePage constant', () {
      test('is a valid URL', () {
        expect(
          Uri.tryParse(SearchEngineService.defaultHomePage),
          isNotNull,
        );
      });
    });
  });
}
