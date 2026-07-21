import 'package:shared_preferences/shared_preferences.dart';

import '../../presentation/providers/filter_provider.dart';

/// Persists sort option and filter tab selections across app sessions.
///
/// Pure Dart, SharedPreferences-backed. Keys are prefixed with
/// `downloads_filter_` to avoid collisions.
class FilterPersistenceService {
  static const _keySortOption = 'downloads_filter_sort_option';
  static const _keyFilterTab = 'downloads_filter_tab';

  final SharedPreferences _prefs;

  FilterPersistenceService(this._prefs);

  /// Returns the persisted [SortOption], or [SortOption.dateNewest] if not set.
  SortOption getSortOption() {
    final name = _prefs.getString(_keySortOption);
    if (name == null) return SortOption.dateNewest;
    return SortOption.values.firstWhere(
      (e) => e.name == name,
      orElse: () => SortOption.dateNewest,
    );
  }

  /// Persists [sort].
  Future<void> saveSortOption(SortOption sort) async {
    await _prefs.setString(_keySortOption, sort.name);
  }

  /// Returns the persisted [FilterTab], or [FilterTab.all] if not set.
  FilterTab getFilterTab() {
    final name = _prefs.getString(_keyFilterTab);
    if (name == null) return FilterTab.all;
    return FilterTab.values.firstWhere(
      (e) => e.name == name,
      orElse: () => FilterTab.all,
    );
  }

  /// Persists [tab].
  Future<void> saveFilterTab(FilterTab tab) async {
    await _prefs.setString(_keyFilterTab, tab.name);
  }
}
