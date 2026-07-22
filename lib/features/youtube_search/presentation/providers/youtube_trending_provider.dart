import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/youtube_search_result.dart';
import 'youtube_search_provider.dart' show youtubeSearchRepositoryProvider;

/// Real YouTube "Trending" feed for the region inferred from the device locale.
///
/// Returns an empty list on any failure so the discovery screen can fall back
/// to its curated topic shortcuts instead of surfacing an error. Region comes
/// from the platform locale's country code (e.g. VN, US); null lets yt-dlp use
/// whatever region the request resolves to.
final youtubeTrendingProvider = FutureProvider<List<YouTubeSearchResult>>((
  ref,
) async {
  final repo = await ref.watch(youtubeSearchRepositoryProvider.future);
  final region = PlatformDispatcher.instance.locale.countryCode;
  final result = await repo.trending(regionCode: region, maxResults: 18);
  return result.when(
    success: (list) => list,
    failure: (_) => const <YouTubeSearchResult>[],
  );
});
