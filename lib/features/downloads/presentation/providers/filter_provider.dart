import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../../core/core.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/download_status.dart';
import '../../domain/services/filter_persistence_service.dart';

part 'filter_provider.freezed.dart';

/// Provider for [FilterPersistenceService].
final filterPersistenceServiceProvider =
    Provider<FilterPersistenceService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return FilterPersistenceService(prefs);
});

/// Watch status filter options
enum WatchFilter {
  all,
  watched,
  watching,
  unwatched;

  String get displayName {
    switch (this) {
      case WatchFilter.all:
        return AppLocalizations.watchStatusFilterAll;
      case WatchFilter.watched:
        return AppLocalizations.watchStatusFilterWatched;
      case WatchFilter.watching:
        return AppLocalizations.watchStatusFilterWatching;
      case WatchFilter.unwatched:
        return AppLocalizations.watchStatusFilterUnwatched;
    }
  }
}

/// Filter tabs enum
enum FilterTab {
  all,
  video,
  audio,
  image,
  // Playlist tab (v20+ Hybrid #1+#2):
  //   #1 Source-grouped — downloads tagged with a non-null
  //      `DownloadEntity.playlistId` (e.g. `yt_<list_id>`) from the
  //      YouTube playlist sheet. Owned by `HomeBatchDownloadMixin`.
  //   #2 User-curated — memberships in `user_playlists` /
  //      `user_playlist_items` (M:N). Owned by the
  //      "Add to playlist" dialog.
  // The downloads-list view unions both into the same `GroupedItem`
  // collapsible UI so the user sees one consistent list regardless
  // of how a video got into a playlist.
  playlist;

  String get displayName {
    switch (this) {
      case FilterTab.all:
        return AppLocalizations.navAll;
      case FilterTab.video:
        return AppLocalizations.navVideo;
      case FilterTab.audio:
        return AppLocalizations.navAudio;
      case FilterTab.image:
        return AppLocalizations.navImage;
      case FilterTab.playlist:
        return AppLocalizations.navPlaylist;
    }
  }
}

/// Sort options for downloads list
enum SortOption {
  dateNewest,
  dateOldest,
  nameAZ,
  nameZA,
  sizeLargest,
  sizeSmallest,
  status,
  durationLongest,
  durationShortest,
  viewsHighest,
  uploaderAZ;

  String get displayName {
    switch (this) {
      case SortOption.dateNewest:
        return AppLocalizations.sortDateNewest;
      case SortOption.dateOldest:
        return AppLocalizations.sortDateOldest;
      case SortOption.nameAZ:
        return AppLocalizations.sortNameAZ;
      case SortOption.nameZA:
        return AppLocalizations.sortNameZA;
      case SortOption.sizeLargest:
        return AppLocalizations.sortSizeLargest;
      case SortOption.sizeSmallest:
        return AppLocalizations.sortSizeSmallest;
      case SortOption.status:
        return AppLocalizations.sortStatus;
      case SortOption.durationLongest:
        return AppLocalizations.sortDurationLongest;
      case SortOption.durationShortest:
        return AppLocalizations.sortDurationShortest;
      case SortOption.viewsHighest:
        return AppLocalizations.sortViewsHighest;
      case SortOption.uploaderAZ:
        return AppLocalizations.sortUploaderAZ;
    }
  }
}

/// Filter state
@freezed
class FilterState with _$FilterState {
  const FilterState._();

  const factory FilterState({
    @Default(FilterTab.all) FilterTab selectedTab,
    @Default(null) VideoPlatform? selectedPlatform,
    @Default(false) bool isPlatformExpanded,
    @Default(SortOption.dateNewest) SortOption sortOption,
    @Default('') String searchQuery,
    @Default({}) Set<DownloadStatus> statusFilters,
    @Default({}) Set<String> selectedTags,
    @Default(WatchFilter.all) WatchFilter watchFilter,
  }) = _FilterState;

  /// Whether any non-default filters are active
  bool get hasActiveFilters =>
      searchQuery.isNotEmpty ||
      statusFilters.isNotEmpty ||
      selectedPlatform != null ||
      selectedTags.isNotEmpty ||
      watchFilter != WatchFilter.all;
}

/// Filter state provider
final filterProvider = StateNotifierProvider<FilterNotifier, FilterState>((ref) {
  final persistence = ref.watch(filterPersistenceServiceProvider);
  return FilterNotifier(persistence);
});

/// Filter notifier
class FilterNotifier extends StateNotifier<FilterState> {
  FilterNotifier(this._persistence)
      : super(FilterState(
          sortOption: _persistence.getSortOption(),
          selectedTab: _persistence.getFilterTab(),
        ));

  final FilterPersistenceService _persistence;

  /// Select tab
  void selectTab(FilterTab tab) {
    state = state.copyWith(
      selectedTab: tab,
      // Reset filters when switching tabs
      selectedPlatform: null,
    );
    _persistence.saveFilterTab(tab);
  }

  /// Select platform
  void selectPlatform(VideoPlatform? platform) {
    state = state.copyWith(
      selectedPlatform: platform,
    );
  }

  /// Toggle platform expansion
  void togglePlatformExpansion() {
    state = state.copyWith(isPlatformExpanded: !state.isPlatformExpanded);
  }

  /// Update sort option
  void updateSort(SortOption sort) {
    state = state.copyWith(sortOption: sort);
    _persistence.saveSortOption(sort);
  }

  /// Update search query
  void updateSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  /// Toggle a status filter (add if absent, remove if present)
  void toggleStatusFilter(DownloadStatus status) {
    final current = Set<DownloadStatus>.from(state.statusFilters);
    if (current.contains(status)) {
      current.remove(status);
    } else {
      current.add(status);
    }
    state = state.copyWith(statusFilters: current);
  }

  /// Toggle a tag filter (add if absent, remove if present)
  void toggleTagFilter(String tag) {
    final current = Set<String>.from(state.selectedTags);
    if (current.contains(tag)) {
      current.remove(tag);
    } else {
      current.add(tag);
    }
    state = state.copyWith(selectedTags: current);
  }

  /// Set watch filter
  void setWatchFilter(WatchFilter filter) {
    state = state.copyWith(watchFilter: filter);
  }

  /// Clear all filters (reset to defaults)
  void clearAllFilters() {
    state = const FilterState();
  }
}
