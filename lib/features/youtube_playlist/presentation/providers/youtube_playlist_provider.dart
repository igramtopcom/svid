import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/binaries/binary_providers.dart';
import '../../../../core/binaries/binary_type.dart';
import '../../../../core/core.dart';
import '../../data/repositories/youtube_playlist_repository.dart';
import '../../domain/entities/playlist_info.dart';
import '../../domain/entities/playlist_video.dart';

/// YouTube playlist state
class YouTubePlaylistState {
  final String url;
  final PlaylistInfo? playlist;
  final List<PlaylistVideo> videos;
  final Set<String> selectedVideoIds;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final int currentPage;

  const YouTubePlaylistState({
    this.url = '',
    this.playlist,
    this.videos = const [],
    this.selectedVideoIds = const {},
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    this.currentPage = 0,
  });

  YouTubePlaylistState copyWith({
    String? url,
    PlaylistInfo? playlist,
    List<PlaylistVideo>? videos,
    Set<String>? selectedVideoIds,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    int? currentPage,
    bool clearError = false,
  }) {
    return YouTubePlaylistState(
      url: url ?? this.url,
      playlist: playlist ?? this.playlist,
      videos: videos ?? this.videos,
      selectedVideoIds: selectedVideoIds ?? this.selectedVideoIds,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
      currentPage: currentPage ?? this.currentPage,
    );
  }

  bool get hasSelection => selectedVideoIds.isNotEmpty;
  bool get isAllSelected => videos.isNotEmpty && selectedVideoIds.length == videos.length;
}

/// YouTube playlist state notifier
class YouTubePlaylistNotifier extends StateNotifier<YouTubePlaylistState> {
  final Ref _ref;
  YouTubePlaylistRepository? _repository;

  YouTubePlaylistNotifier(this._ref) : super(const YouTubePlaylistState());

  /// Deduplicate videos by ID (YouTube can return duplicates in playlists)
  List<PlaylistVideo> _deduplicateVideos(List<PlaylistVideo> videos) {
    final seen = <String>{};
    return videos.where((v) => seen.add(v.id)).toList();
  }

  /// Get or initialize repository
  Future<YouTubePlaylistRepository> _getRepository() async {
    if (_repository != null) return _repository!;
    _repository = await _ref.read(youtubePlaylistRepositoryProvider.future);
    return _repository!;
  }

  /// Load first page of playlist
  Future<void> loadPlaylist(String url) async {
    if (url.trim().isEmpty) {
      state = const YouTubePlaylistState();
      return;
    }

    state = YouTubePlaylistState(url: url, isLoading: true);

    try {
      final repository = await _getRepository();
      // Load first 20 videos (startIndex=0 means no start limit)
      final result = await repository.getPlaylistInfo(
        url: url,
        startIndex: 0,
        endIndex: 20,
      );

      result.when(
        success: (data) {
          final (playlist, videos) = data;
          // Determine hasMore: use playlist.videoCount if available, otherwise check if we got a full page
          final hasMore = playlist.videoCount != null
              ? videos.length < (playlist.videoCount ?? 0)
              : videos.length >= 20;
          appLogger.info('[Playlist] Loaded ${videos.length} videos, hasMore: $hasMore');

          state = state.copyWith(
            playlist: playlist,
            videos: videos,
            isLoading: false,
            hasMore: hasMore,
            currentPage: 1,
            clearError: true,
          );
        },
        failure: (exception) {
          state = state.copyWith(
            isLoading: false,
            error: exception.toString(),
          );
        },
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Load more videos (pagination)
  Future<void> loadMore() async {
    appLogger.info('[Playlist LoadMore] Called - isLoadingMore: ${state.isLoadingMore}, hasMore: ${state.hasMore}, url: ${state.url}');

    if (state.isLoadingMore || !state.hasMore || state.url.isEmpty) {
      appLogger.info('[Playlist LoadMore] Skipped - Already loading, no more, or empty URL');
      return;
    }

    state = state.copyWith(isLoadingMore: true);

    try {
      final repository = await _getRepository();
      final nextPage = state.currentPage + 1;
      final startIndex = (nextPage - 1) * 20 + 1;
      final endIndex = nextPage * 20;

      appLogger.info('[Playlist LoadMore] Fetching page $nextPage (videos $startIndex-$endIndex)');

      final result = await repository.getPlaylistInfo(
        url: state.url,
        startIndex: startIndex,
        endIndex: endIndex,
      );

      result.when(
        success: (data) {
          final (_, newVideos) = data;
          final allVideos = _deduplicateVideos([...state.videos, ...newVideos]);
          // Determine hasMore: use videoCount if available, otherwise check if we got a full page
          final hasMore = state.playlist?.videoCount != null
              ? allVideos.length < (state.playlist!.videoCount ?? 0)
              : newVideos.length >= 20;

          appLogger.info('[Playlist LoadMore] Got ${newVideos.length} videos, total now: ${allVideos.length}, hasMore: $hasMore');

          state = state.copyWith(
            videos: allVideos,
            isLoadingMore: false,
            hasMore: hasMore,
            currentPage: nextPage,
            clearError: true,
          );
        },
        failure: (exception) {
          state = state.copyWith(
            isLoadingMore: false,
            error: exception.toString(),
          );
        },
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingMore: false,
        error: e.toString(),
      );
    }
  }

  /// Toggle video selection
  void toggleSelection(String videoId) {
    final newSelection = Set<String>.from(state.selectedVideoIds);
    if (newSelection.contains(videoId)) {
      newSelection.remove(videoId);
    } else {
      newSelection.add(videoId);
    }
    state = state.copyWith(selectedVideoIds: newSelection);
  }

  /// Select all videos
  void selectAll() {
    state = state.copyWith(
      selectedVideoIds: state.videos.map((v) => v.id).toSet(),
    );
  }

  /// Deselect all videos
  void deselectAll() {
    state = state.copyWith(selectedVideoIds: {});
  }

  /// Get selected videos
  List<PlaylistVideo> getSelectedVideos() {
    return state.videos
        .where((v) => state.selectedVideoIds.contains(v.id))
        .toList();
  }

  /// Clear playlist
  void clear() {
    state = const YouTubePlaylistState();
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

/// Provider for YouTube playlist repository
final youtubePlaylistRepositoryProvider = FutureProvider<YouTubePlaylistRepository>((ref) async {
  final ytdlpPath = await ref.watch(binaryPathProvider(BinaryType.ytDlp).future);
  if (ytdlpPath == null) {
    throw Exception('yt-dlp binary not found');
  }
  // Deno is optional — playlist resolution returns metadata only.
  final denoPath = await ref.watch(binaryPathProvider(BinaryType.deno).future);
  return YouTubePlaylistRepository(
    binaryPath: ytdlpPath,
    denoPath: denoPath,
  );
});

/// Provider for YouTube playlist state
final youtubePlaylistProvider =
    StateNotifierProvider<YouTubePlaylistNotifier, YouTubePlaylistState>((ref) {
  return YouTubePlaylistNotifier(ref);
});
