import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/binaries/binary_providers.dart';
import '../../../../core/binaries/binary_type.dart';
import '../../../../core/core.dart';
import '../../../youtube_playlist/domain/entities/playlist_video.dart';
import '../../data/repositories/youtube_channel_repository.dart';
import '../../domain/entities/channel_info.dart';

/// Video sort options
enum VideoSortBy {
  dateNewest,
  dateOldest,
  durationShortest,
  durationLongest,
  viewsMost,
  viewsLeast;

  String label(BuildContext context) {
    switch (this) {
      case VideoSortBy.dateNewest:
        return AppLocalizations.youtubeChannelSortDateNewest;
      case VideoSortBy.dateOldest:
        return AppLocalizations.youtubeChannelSortDateOldest;
      case VideoSortBy.durationShortest:
        return AppLocalizations.youtubeChannelSortDurationShort;
      case VideoSortBy.durationLongest:
        return AppLocalizations.youtubeChannelSortDurationLong;
      case VideoSortBy.viewsMost:
        return AppLocalizations.youtubeChannelSortViewsMost;
      case VideoSortBy.viewsLeast:
        return AppLocalizations.youtubeChannelSortViewsLeast;
    }
  }
}

/// YouTube Channel state
class YouTubeChannelState {
  final String url;
  final ChannelInfo? channel;
  final List<PlaylistVideo> videos; // Raw videos from API
  final List<PlaylistVideo> filteredVideos; // Filtered and sorted videos
  final Set<String> selectedVideoIds;
  final bool isLoading;
  final bool isLoadingMore; // Loading more videos (pagination)
  final bool hasMore; // Whether there are more videos to load
  final int currentPage; // Current page (50 videos per page)
  final String searchQuery; // Search query for videos
  final VideoSortBy sortBy; // Sort option
  final int? minDuration; // Filter: minimum duration in seconds
  final int? maxDuration; // Filter: maximum duration in seconds
  final String? error;

  const YouTubeChannelState({
    this.url = '',
    this.channel,
    this.videos = const [],
    this.filteredVideos = const [],
    this.selectedVideoIds = const {},
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.currentPage = 0,
    this.searchQuery = '',
    this.sortBy = VideoSortBy.dateNewest,
    this.minDuration,
    this.maxDuration,
    this.error,
  });

  YouTubeChannelState copyWith({
    String? url,
    ChannelInfo? channel,
    List<PlaylistVideo>? videos,
    List<PlaylistVideo>? filteredVideos,
    Set<String>? selectedVideoIds,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? currentPage,
    String? searchQuery,
    VideoSortBy? sortBy,
    int? Function()? minDuration, // Use function to support null values
    int? Function()? maxDuration,
    String? error,
    bool clearError = false,
  }) {
    return YouTubeChannelState(
      url: url ?? this.url,
      channel: channel ?? this.channel,
      videos: videos ?? this.videos,
      filteredVideos: filteredVideos ?? this.filteredVideos,
      selectedVideoIds: selectedVideoIds ?? this.selectedVideoIds,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      searchQuery: searchQuery ?? this.searchQuery,
      sortBy: sortBy ?? this.sortBy,
      minDuration: minDuration != null ? minDuration() : this.minDuration,
      maxDuration: maxDuration != null ? maxDuration() : this.maxDuration,
      error: clearError ? null : (error ?? this.error),
    );
  }

  bool get hasSelection => selectedVideoIds.isNotEmpty;
  bool get isAllSelected => filteredVideos.isNotEmpty && selectedVideoIds.length == filteredVideos.length;
}

/// YouTube Channel state notifier
class YouTubeChannelNotifier extends StateNotifier<YouTubeChannelState> {
  final Ref _ref;
  YouTubeChannelRepository? _repository;

  YouTubeChannelNotifier(this._ref) : super(const YouTubeChannelState());

  /// Get or initialize repository
  Future<YouTubeChannelRepository> _getRepository() async {
    if (_repository != null) return _repository!;
    _repository = await _ref.read(youtubeChannelRepositoryProvider.future);
    return _repository!;
  }

  /// Load channel information (first page)
  Future<void> loadChannel(String url) async {
    if (url.trim().isEmpty) {
      state = state.copyWith(error: 'Please enter a channel URL');
      return;
    }

    state = state.copyWith(
      url: url,
      isLoading: true,
      clearError: true,
      channel: null,
      videos: [],
      filteredVideos: [],
      selectedVideoIds: {},
      currentPage: 0,
      hasMore: true,
      searchQuery: '',
      sortBy: VideoSortBy.dateNewest,
      minDuration: () => null,
      maxDuration: () => null,
    );

    try {
      final repository = await _getRepository();
      // Load first 50 videos (page 0)
      final result = await repository.getChannelInfo(
        url: url,
        startIndex: 0,
        endIndex: 50,
      );

      result.when(
        success: (data) {
          final (channel, videos) = data;
          // If we got less than 50 videos, there's no more
          final hasMore = videos.length >= 50;
          state = state.copyWith(
            channel: channel,
            videos: videos,
            isLoading: false,
            hasMore: hasMore,
            currentPage: 1,
          );
          _applyFiltersAndSort(); // Apply filters/sort after loading
          appLogger.info('Channel loaded: ${channel.title} with ${videos.length} videos (page 1${hasMore ? ", more available" : ""})');
        },
        failure: (error) {
          state = state.copyWith(
            isLoading: false,
            error: _formatError(error.toString()),
          );
          appLogger.error('Failed to load channel', error);
        },
      );
    } catch (e, stack) {
      state = state.copyWith(
        isLoading: false,
        error: _formatError(e.toString()),
      );
      appLogger.error('Failed to load channel', e, stack);
    }
  }

  /// Load more videos (pagination)
  Future<void> loadMoreVideos() async {
    if (state.isLoadingMore || !state.hasMore || state.url.isEmpty) {
      return;
    }

    state = state.copyWith(isLoadingMore: true);

    try {
      final repository = await _getRepository();
      final startIndex = state.currentPage * 50;
      final endIndex = startIndex + 50;

      final result = await repository.getChannelInfo(
        url: state.url,
        startIndex: startIndex,
        endIndex: endIndex,
      );

      result.when(
        success: (data) {
          final (_, newVideos) = data;
          // If we got less than 50 videos, there's no more
          final hasMore = newVideos.length >= 50;
          final allVideos = _deduplicateVideos([...state.videos, ...newVideos]);

          state = state.copyWith(
            videos: allVideos,
            isLoadingMore: false,
            hasMore: hasMore,
            currentPage: state.currentPage + 1,
          );
          _applyFiltersAndSort(); // Apply filters/sort after loading more
          appLogger.info('Loaded ${newVideos.length} more videos (page ${state.currentPage}, total: ${allVideos.length}${hasMore ? ", more available" : ""})');
        },
        failure: (error) {
          state = state.copyWith(
            isLoadingMore: false,
          );
          appLogger.error('Failed to load more videos', error);
        },
      );
    } catch (e, stack) {
      state = state.copyWith(
        isLoadingMore: false,
      );
      appLogger.error('Failed to load more videos', e, stack);
    }
  }

  /// Toggle video selection
  void toggleSelection(String videoId) {
    final selected = Set<String>.from(state.selectedVideoIds);
    if (selected.contains(videoId)) {
      selected.remove(videoId);
    } else {
      selected.add(videoId);
    }
    state = state.copyWith(selectedVideoIds: selected);
  }

  /// Select all videos (filtered)
  void selectAll() {
    final allIds = state.filteredVideos.map((v) => v.id).toSet();
    state = state.copyWith(selectedVideoIds: allIds);
    appLogger.info('Selected all ${allIds.length} videos');
  }

  /// Deselect all videos
  void deselectAll() {
    state = state.copyWith(selectedVideoIds: {});
    appLogger.info('Deselected all videos');
  }

  /// Get list of selected videos
  List<PlaylistVideo> getSelectedVideos() {
    return state.filteredVideos
        .where((v) => state.selectedVideoIds.contains(v.id))
        .toList();
  }

  /// Set search query
  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
    _applyFiltersAndSort();
  }

  /// Set sort option
  void setSortBy(VideoSortBy sortBy) {
    state = state.copyWith(sortBy: sortBy);
    _applyFiltersAndSort();
    appLogger.info('Sort changed to: $sortBy');
  }

  /// Set duration filter
  void setDurationFilter({int? minDuration, int? maxDuration}) {
    state = state.copyWith(
      minDuration: () => minDuration,
      maxDuration: () => maxDuration,
    );
    _applyFiltersAndSort();
    appLogger.info('Duration filter: ${minDuration ?? 0}s - ${maxDuration ?? "∞"}s');
  }

  /// Clear all filters
  void clearFilters() {
    state = state.copyWith(
      searchQuery: '',
      sortBy: VideoSortBy.dateNewest,
      minDuration: () => null,
      maxDuration: () => null,
    );
    _applyFiltersAndSort();
    appLogger.info('Filters cleared');
  }

  /// Deduplicate videos by ID (YouTube Mix/Radio playlists can return duplicates)
  List<PlaylistVideo> _deduplicateVideos(List<PlaylistVideo> videos) {
    final seen = <String>{};
    return videos.where((v) => seen.add(v.id)).toList();
  }

  /// Apply filters and sorting to videos
  void _applyFiltersAndSort() {
    var filtered = _deduplicateVideos(state.videos);

    // Apply search filter
    if (state.searchQuery.isNotEmpty) {
      final query = state.searchQuery.toLowerCase();
      filtered = filtered.where((video) {
        final titleMatch = video.title.toLowerCase().contains(query);
        final channelMatch = video.channel?.toLowerCase().contains(query) ?? false;
        return titleMatch || channelMatch;
      }).toList();
    }

    // Apply duration filter
    if (state.minDuration != null || state.maxDuration != null) {
      filtered = filtered.where((video) {
        final duration = video.durationSeconds;
        if (duration == null) return true; // Include videos without duration

        if (state.minDuration != null && duration < state.minDuration!) {
          return false;
        }
        if (state.maxDuration != null && duration > state.maxDuration!) {
          return false;
        }
        return true;
      }).toList();
    }

    // Apply sorting
    switch (state.sortBy) {
      case VideoSortBy.dateNewest:
        // Already sorted by default (newest first)
        break;
      case VideoSortBy.dateOldest:
        filtered = filtered.reversed.toList();
        break;
      case VideoSortBy.durationShortest:
        filtered.sort((a, b) {
          final aDur = a.durationSeconds ?? 0;
          final bDur = b.durationSeconds ?? 0;
          return aDur.compareTo(bDur);
        });
        break;
      case VideoSortBy.durationLongest:
        filtered.sort((a, b) {
          final aDur = a.durationSeconds ?? 0;
          final bDur = b.durationSeconds ?? 0;
          return bDur.compareTo(aDur);
        });
        break;
      case VideoSortBy.viewsMost:
        filtered.sort((a, b) {
          final aViews = a.viewCount ?? 0;
          final bViews = b.viewCount ?? 0;
          return bViews.compareTo(aViews);
        });
        break;
      case VideoSortBy.viewsLeast:
        filtered.sort((a, b) {
          final aViews = a.viewCount ?? 0;
          final bViews = b.viewCount ?? 0;
          return aViews.compareTo(bViews);
        });
        break;
    }

    state = state.copyWith(filteredVideos: filtered);
  }

  /// Clear state
  void clear() {
    state = const YouTubeChannelState();
  }

  /// Format error message for display
  String _formatError(String error) {
    if (error.contains('timeout') || error.contains('Timeout')) {
      return 'Request timed out. Please check your internet connection.';
    } else if (error.contains('not found') || error.contains('404')) {
      return 'Channel not found. Please check the URL.';
    } else if (error.contains('private') || error.contains('Private')) {
      return 'This channel is private or unavailable.';
    } else if (error.contains('network') || error.contains('Network')) {
      return 'Network error. Please check your connection.';
    }
    return 'Failed to load channel. Please try again.';
  }
}

/// Provider for YouTube channel repository
final youtubeChannelRepositoryProvider = FutureProvider<YouTubeChannelRepository>((ref) async {
  final ytdlpPath = await ref.watch(binaryPathProvider(BinaryType.ytDlp).future);
  if (ytdlpPath == null) {
    throw Exception('yt-dlp binary not found');
  }
  final denoPath = await ref.watch(binaryPathProvider(BinaryType.deno).future);
  return YouTubeChannelRepository(
    binaryPath: ytdlpPath,
    denoPath: denoPath,
  );
});

/// Provider for YouTube channel state
final youtubeChannelProvider =
    StateNotifierProvider<YouTubeChannelNotifier, YouTubeChannelState>((ref) {
  return YouTubeChannelNotifier(ref);
});
