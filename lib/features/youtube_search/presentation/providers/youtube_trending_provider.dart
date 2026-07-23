import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/youtube_charts_service.dart';
import '../../domain/entities/youtube_search_result.dart';
import 'youtube_search_provider.dart' show youtubeSearchRepositoryProvider;

/// Real trending YouTube videos for the user's region, tried in order:
///
/// 1. **YouTube Charts** (`charts.youtube.com`) — the official, region-aware,
///    continuously-updated Trending Videos chart (replaces the retired
///    `/feed/trending`). Region comes from the device locale country code.
/// 2. **Hashtag feed** (`#trending` via yt-dlp) — if Charts is unavailable.
///
/// Returns an empty list only if both fail, so the discovery screen falls back
/// to its curated topic shortcuts instead of surfacing an error.
final youtubeTrendingProvider = FutureProvider<List<YouTubeSearchResult>>((
  ref,
) async {
  final repo = await ref.watch(youtubeSearchRepositoryProvider.future);
  final countryCode = PlatformDispatcher.instance.locale.countryCode ?? 'US';

  // 1. Official YouTube Charts trending (region-aware, freshest source).
  final charts = await YouTubeChartsService().trendingVideos(
    countryCode: countryCode,
    maxResults: 18,
  );
  if (charts.isNotEmpty) return charts;

  // 2. Fallback: #trending hashtag feed via yt-dlp.
  final result = await repo.trending(hashtag: 'trending', maxResults: 18);
  return result.when(
    success: (list) => list,
    failure: (_) => const <YouTubeSearchResult>[],
  );
});
