import 'package:shared_preferences/shared_preferences.dart';

/// Supported search engines.
enum SearchEngine {
  google('Google', 'https://www.google.com/search?q='),
  bing('Bing', 'https://www.bing.com/search?q='),
  duckDuckGo('DuckDuckGo', 'https://duckduckgo.com/?q='),
  yahoo('Yahoo', 'https://search.yahoo.com/search?p='),
  brave('Brave Search', 'https://search.brave.com/search?q=');

  const SearchEngine(this.label, this.searchUrlTemplate);

  final String label;
  final String searchUrlTemplate;
}

/// Manages search engine selection and home page URL.
///
/// Pure Dart, SharedPreferences-backed.
class SearchEngineService {
  static const _searchEngineKey = 'browser_search_engine';
  static const _homePageKey = 'browser_home_page';
  static const defaultHomePage = 'https://www.google.com';

  final SharedPreferences _prefs;

  SearchEngineService(this._prefs);

  /// Get the selected search engine. Default: Google.
  SearchEngine get searchEngine {
    final name = _prefs.getString(_searchEngineKey);
    if (name == null) return SearchEngine.google;
    return SearchEngine.values.firstWhere(
      (e) => e.name == name,
      orElse: () => SearchEngine.google,
    );
  }

  /// Set the search engine.
  Future<void> setSearchEngine(SearchEngine engine) async {
    await _prefs.setString(_searchEngineKey, engine.name);
  }

  /// Build a full search URL from query text.
  String buildSearchUrl(String query) {
    return '${searchEngine.searchUrlTemplate}${Uri.encodeComponent(query)}';
  }

  /// Get the home page URL.
  String get homePage {
    return _prefs.getString(_homePageKey) ?? defaultHomePage;
  }

  /// Set the home page URL.
  Future<void> setHomePage(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      await _prefs.remove(_homePageKey);
    } else {
      await _prefs.setString(_homePageKey, trimmed);
    }
  }

  /// Clear all browsing data (history, bookmarks, cookies keys).
  /// Returns the list of SharedPreferences keys that were cleared.
  Future<List<String>> clearBrowsingData() async {
    const keys = [
      'browser_history_data',
      'browser_bookmarks_data',
    ];
    final cleared = <String>[];
    for (final key in keys) {
      if (_prefs.containsKey(key)) {
        await _prefs.remove(key);
        cleared.add(key);
      }
    }
    return cleared;
  }
}
