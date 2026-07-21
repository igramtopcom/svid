import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/binaries/binary_providers.dart';
import '../../../../core/binaries/binary_type.dart';
import '../../data/repositories/youtube_search_repository.dart';
import '../../domain/entities/youtube_search_result.dart';
import '../../domain/entities/search_filters.dart';

/// YouTube search state
class YouTubeSearchState {
  final String query;

  /// Unfiltered raw results from yt-dlp (source of truth for client-side filtering)
  final List<YouTubeSearchResult> allResults;

  /// Filtered + sorted results shown in the UI
  final List<YouTubeSearchResult> results;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final int currentPage;
  final YouTubeSearchFilters filters;

  const YouTubeSearchState({
    this.query = '',
    this.allResults = const [],
    this.results = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    this.currentPage = 0,
    this.filters = const YouTubeSearchFilters(),
  });

  YouTubeSearchState copyWith({
    String? query,
    List<YouTubeSearchResult>? allResults,
    List<YouTubeSearchResult>? results,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    int? currentPage,
    YouTubeSearchFilters? filters,
    bool clearError = false,
  }) {
    return YouTubeSearchState(
      query: query ?? this.query,
      allResults: allResults ?? this.allResults,
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
      currentPage: currentPage ?? this.currentPage,
      filters: filters ?? this.filters,
    );
  }
}

/// YouTube search state notifier
class YouTubeSearchNotifier extends StateNotifier<YouTubeSearchState> {
  final Ref _ref;
  YouTubeSearchRepository? _repository;
  static const int _pageSize = 20;
  bool _disposed = false;
  int _requestSerial = 0;

  YouTubeSearchNotifier(this._ref) : super(const YouTubeSearchState());

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Get or initialize repository
  Future<YouTubeSearchRepository> _getRepository() async {
    if (_repository != null) return _repository!;
    _repository = await _ref.read(youtubeSearchRepositoryProvider.future);
    return _repository!;
  }

  /// Apply duration + upload-date filters and sort client-side
  List<YouTubeSearchResult> _applyFilters(
    List<YouTubeSearchResult> raw,
    YouTubeSearchFilters filters,
  ) {
    var results = raw.toList();

    // Duration filter
    if (filters.duration != SearchDuration.any) {
      results =
          results.where((r) {
            final d = r.durationSeconds;
            if (d == null) return false;
            switch (filters.duration) {
              case SearchDuration.short:
                return d < 240;
              case SearchDuration.medium:
                return d >= 240 && d <= 1200;
              case SearchDuration.long:
                return d > 1200;
              case SearchDuration.any:
                return true;
            }
          }).toList();
    }

    // Upload date filter — only works for YYYYMMDD format returned by yt-dlp
    if (filters.uploadDate != SearchUploadDate.anytime) {
      final now = DateTime.now();
      results =
          results.where((r) {
            final date = r.uploadDate;
            if (date == null || date.length != 8) {
              return true; // pass relative strings through
            }
            try {
              final parsed = DateTime(
                int.parse(date.substring(0, 4)),
                int.parse(date.substring(4, 6)),
                int.parse(date.substring(6, 8)),
              );
              final days = now.difference(parsed).inDays;
              switch (filters.uploadDate) {
                case SearchUploadDate.today:
                  return days == 0;
                case SearchUploadDate.thisWeek:
                  return days <= 7;
                case SearchUploadDate.thisMonth:
                  return days <= 30;
                case SearchUploadDate.thisYear:
                  return days <= 365;
                case SearchUploadDate.anytime:
                  return true;
              }
            } catch (_) {
              return true;
            }
          }).toList();
    }

    // Sort
    switch (filters.sortBy) {
      case SearchSortBy.viewCount:
        results.sort((a, b) => (b.viewCount ?? 0).compareTo(a.viewCount ?? 0));
      case SearchSortBy.uploadDate:
        results.sort(
          (a, b) => (b.uploadDate ?? '').compareTo(a.uploadDate ?? ''),
        );
      case SearchSortBy.relevance:
      case SearchSortBy.rating:
        // Keep yt-dlp relevance order; rating not available client-side
        break;
    }

    return results;
  }

  /// Search for videos
  Future<void> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      state = const YouTubeSearchState();
      return;
    }

    final requestId = ++_requestSerial;

    // Reset state for new search, preserving active filters
    state = YouTubeSearchState(
      query: trimmed,
      isLoading: true,
      filters: state.filters,
    );

    try {
      final repository = await _getRepository();
      final result = await repository.search(
        query: trimmed,
        maxResults: _pageSize,
      );

      if (_isStale(requestId, trimmed)) return;

      result.when(
        success: (rawResults) {
          final filtered = _applyFilters(rawResults, state.filters);
          state = state.copyWith(
            allResults: rawResults,
            results: filtered,
            isLoading: false,
            hasMore: rawResults.length >= _pageSize,
            currentPage: 1,
            clearError: true,
          );
        },
        failure: (exception) {
          state = state.copyWith(
            isLoading: false,
            error: exception.toString(),
            hasMore: false,
          );
        },
      );
    } catch (e) {
      if (_isStale(requestId, trimmed)) return;
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        hasMore: false,
      );
    }
  }

  /// Load more results (pagination)
  Future<void> loadMore() async {
    if (_disposed) return;
    if (state.isLoadingMore || !state.hasMore || state.query.isEmpty) return;

    final requestId = _requestSerial;
    final query = state.query;
    final startingRawCount = state.allResults.length;
    final nextPage = state.currentPage + 1;

    state = state.copyWith(isLoadingMore: true, clearError: true);

    try {
      final repository = await _getRepository();
      // For yt-dlp, request more results and skip existing raw ones
      final totalNeeded = nextPage * _pageSize;

      final result = await repository.search(
        query: query,
        maxResults: totalNeeded,
      );

      if (_isStale(requestId, query)) return;

      result.when(
        success: (fetchedResults) {
          // Only take new raw results (after current raw count)
          final newRaw = fetchedResults.skip(startingRawCount).toList();

          if (newRaw.isEmpty) {
            state = state.copyWith(isLoadingMore: false, hasMore: false);
          } else {
            final updatedAll = [...state.allResults, ...newRaw];
            final filtered = _applyFilters(updatedAll, state.filters);
            state = state.copyWith(
              allResults: updatedAll,
              results: filtered,
              isLoadingMore: false,
              hasMore: newRaw.length >= _pageSize,
              currentPage: nextPage,
              clearError: true,
            );
          }
        },
        failure: (exception) {
          state = state.copyWith(
            isLoadingMore: false,
            error: exception.toString(),
          );
        },
      );
    } catch (e) {
      if (_isStale(requestId, query)) return;
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }

  bool _isStale(int requestId, String query) {
    return _disposed || requestId != _requestSerial || state.query != query;
  }

  /// Update filters — applies client-side on cached results (no yt-dlp rerun)
  void updateFilters(YouTubeSearchFilters filters) {
    final filtered = _applyFilters(state.allResults, filters);
    state = state.copyWith(filters: filters, results: filtered);
  }

  /// Clear search
  void clear() {
    state = const YouTubeSearchState();
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

/// Provider for yt-dlp binary path (async)
final ytdlpBinaryPathAsyncProvider = FutureProvider<String>((ref) async {
  final path = await ref.watch(binaryPathProvider(BinaryType.ytDlp).future);
  if (path == null) {
    throw Exception('yt-dlp binary not found');
  }
  return path;
});

/// Provider for YouTube search repository (async initialization)
final youtubeSearchRepositoryProvider = FutureProvider<YouTubeSearchRepository>(
  (ref) async {
    final ytdlpPath = await ref.watch(ytdlpBinaryPathAsyncProvider.future);
    // Deno is optional — search returns metadata only, not GVS streams.
    // We still pass it when available so the args list stays consistent
    // with extract/download paths under yt-dlp 2025.11.12+.
    final denoPath = await ref.watch(
      binaryPathProvider(BinaryType.deno).future,
    );
    // TODO(Phase 59+): Add cookies support for age-restricted content
    return YouTubeSearchRepository(binaryPath: ytdlpPath, denoPath: denoPath);
  },
);

/// Provider for YouTube search state
/// Note: Repository is initialized lazily on first search
final youtubeSearchProvider =
    StateNotifierProvider<YouTubeSearchNotifier, YouTubeSearchState>((ref) {
      return YouTubeSearchNotifier(ref);
    });
