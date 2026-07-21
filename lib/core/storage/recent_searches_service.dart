import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing recently searched keywords
class RecentSearchesService {
  static const String _keyRecentSearches = 'youtube_recent_searches';
  static const int _maxRecentSearches = 15;

  final SharedPreferences _prefs;

  RecentSearchesService(this._prefs);

  /// Get all recent searches (newest first)
  List<String> getRecentSearches() {
    return _prefs.getStringList(_keyRecentSearches) ?? [];
  }

  /// Add a new search keyword
  /// - Deduplicates: If keyword exists, moves it to top
  /// - Limits to max items
  Future<void> addSearch(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;

    final searches = getRecentSearches();

    // Remove if exists (will re-add at top)
    searches.remove(trimmed);

    // Add to beginning
    searches.insert(0, trimmed);

    // Limit to max items
    if (searches.length > _maxRecentSearches) {
      searches.removeRange(_maxRecentSearches, searches.length);
    }

    await _prefs.setStringList(_keyRecentSearches, searches);
  }

  /// Remove a specific search keyword
  Future<void> removeSearch(String keyword) async {
    final searches = getRecentSearches();
    searches.remove(keyword);
    await _prefs.setStringList(_keyRecentSearches, searches);
  }

  /// Clear all recent searches
  Future<void> clearAll() async {
    await _prefs.remove(_keyRecentSearches);
  }
}
