import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/storage/recent_searches_service.dart';

/// Provider for RecentSearchesService
final recentSearchesServiceProvider = FutureProvider<RecentSearchesService>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return RecentSearchesService(prefs);
});

/// State notifier for recent searches
class RecentSearchesNotifier extends StateNotifier<AsyncValue<List<String>>> {
  final Ref _ref;
  RecentSearchesService? _service;

  RecentSearchesNotifier(this._ref) : super(const AsyncValue.loading()) {
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _service = await _ref.read(recentSearchesServiceProvider.future);
      state = AsyncValue.data(_service!.getRecentSearches());
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<RecentSearchesService> _getService() async {
    if (_service != null) return _service!;
    _service = await _ref.read(recentSearchesServiceProvider.future);
    return _service!;
  }

  /// Add a new search keyword
  Future<void> addSearch(String keyword) async {
    try {
      final service = await _getService();
      await service.addSearch(keyword);
      state = AsyncValue.data(service.getRecentSearches());
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// Remove a specific search
  Future<void> removeSearch(String keyword) async {
    try {
      final service = await _getService();
      await service.removeSearch(keyword);
      state = AsyncValue.data(service.getRecentSearches());
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// Clear all recent searches
  Future<void> clearAll() async {
    try {
      final service = await _getService();
      await service.clearAll();
      state = const AsyncValue.data([]);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }
}

/// Provider for recent searches state
final recentSearchesProvider = StateNotifierProvider<RecentSearchesNotifier, AsyncValue<List<String>>>((ref) {
  return RecentSearchesNotifier(ref);
});
