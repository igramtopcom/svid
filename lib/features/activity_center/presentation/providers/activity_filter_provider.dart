import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Filter tabs for the Activity Center
enum ActivityFilterTab { all, active, success, errors, system }

/// Date range options for filtering activity
enum ActivityDateRange { today, last7Days, last30Days, allTime }

/// Filter state for the Activity Center
class ActivityFilterState {
  final ActivityFilterTab selectedTab;
  final ActivityDateRange dateRange;
  final String searchQuery;

  const ActivityFilterState({
    this.selectedTab = ActivityFilterTab.all,
    this.dateRange = ActivityDateRange.allTime,
    this.searchQuery = '',
  });

  ActivityFilterState copyWith({
    ActivityFilterTab? selectedTab,
    ActivityDateRange? dateRange,
    String? searchQuery,
  }) {
    return ActivityFilterState(
      selectedTab: selectedTab ?? this.selectedTab,
      dateRange: dateRange ?? this.dateRange,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

/// Notifier for Activity Center filter state
class ActivityFilterNotifier extends StateNotifier<ActivityFilterState> {
  ActivityFilterNotifier() : super(const ActivityFilterState());

  void setTab(ActivityFilterTab tab) {
    state = state.copyWith(selectedTab: tab);
  }

  void setDateRange(ActivityDateRange range) {
    state = state.copyWith(dateRange: range);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void reset() {
    state = const ActivityFilterState();
  }
}

/// Provider for activity filter state
final activityFilterProvider =
    StateNotifierProvider<ActivityFilterNotifier, ActivityFilterState>((ref) {
  return ActivityFilterNotifier();
});
