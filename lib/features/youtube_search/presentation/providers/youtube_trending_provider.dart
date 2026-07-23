import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/youtube_search_result.dart';
import 'youtube_search_provider.dart' show youtubeSearchRepositoryProvider;

/// Real popular YouTube videos, sourced from a hashtag feed (`#trending`).
///
/// YouTube retired the old global Trending page, so we surface the top videos
/// of a live hashtag tab instead — real, dynamic content the user can download
/// in one tap. Returns an empty list on any failure so the discovery screen
/// falls back to its curated topic shortcuts rather than surfacing an error.
final youtubeTrendingProvider = FutureProvider<List<YouTubeSearchResult>>((
  ref,
) async {
  final repo = await ref.watch(youtubeSearchRepositoryProvider.future);
  final result = await repo.trending(hashtag: 'trending', maxResults: 18);
  return result.when(
    success: (list) => list,
    failure: (_) => const <YouTubeSearchResult>[],
  );
});
