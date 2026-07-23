import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/youtube_search_result.dart';

/// Fetches the **official YouTube Charts "Trending Videos"** chart — the modern,
/// region-aware, continuously-updated replacement for the retired
/// `youtube.com/feed/trending` page (which yt-dlp can no longer read).
///
/// Charts lives on its own host (`charts.youtube.com`) and is powered by an
/// internal `youtubei/v1/browse` endpoint using the `WEB_MUSIC_ANALYTICS`
/// client. The endpoint accepts an empty API key, so no credentials are
/// needed. It's undocumented and could change, so every failure degrades
/// silently to an empty list and the caller falls back to another source.
class YouTubeChartsService {
  static const String _endpoint =
      'https://charts.youtube.com/youtubei/v1/browse?alt=json&prettyPrint=false';

  /// Real trending videos for [countryCode] (ISO-3166, e.g. `VN`, `US`).
  ///
  /// Returns an empty list on any failure (network, unsupported region,
  /// schema change) — never throws.
  Future<List<YouTubeSearchResult>> trendingVideos({
    String countryCode = 'US',
    int maxResults = 18,
  }) async {
    final cc =
        countryCode.trim().isEmpty ? 'US' : countryCode.trim().toUpperCase();
    try {
      final body = jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB_MUSIC_ANALYTICS',
            'clientVersion': '2.0',
            'hl': 'en',
            'gl': cc,
            'theme': 'MUSIC',
          },
        },
        'browseId': 'FEmusic_analytics_charts_home',
        'query':
            'perspective=CHART_HOME&chart_params_country_code=${cc.toLowerCase()}'
            '&chart_params_chart_type=VIDEO&chart_params_period_type=WEEKLY',
      });

      appLogger.info('[YouTube Charts] Fetching trending videos (gl=$cc)');

      final resp = await http
          .post(
            Uri.parse(_endpoint),
            headers: const {
              'Content-Type': 'application/json',
              'Origin': 'https://charts.youtube.com',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/122.0 Safari/537.36',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) {
        appLogger.warning('[YouTube Charts] HTTP ${resp.statusCode}');
        return const [];
      }

      final data =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final views = _findTrendingViews(data);
      final results = <YouTubeSearchResult>[];
      for (final v in views) {
        if (v is! Map) continue;
        final id = v['id'];
        if (id is! String || id.length != 11) continue;
        results.add(
          YouTubeSearchResult(
            id: id,
            title: _runsText(v['title']) ?? id,
            channel: v['channelName'] as String?,
            channelId: v['externalChannelId'] as String?,
            thumbnail: _bestThumbnail(v['thumbnail']),
            durationSeconds:
                (v['videoDuration'] is num)
                    ? (v['videoDuration'] as num).toInt()
                    : null,
            url: 'https://www.youtube.com/watch?v=$id',
          ),
        );
        if (results.length >= maxResults) break;
      }
      appLogger.info('[YouTube Charts] Parsed ${results.length} trending videos');
      return results;
    } catch (e, stack) {
      appLogger.error('[YouTube Charts] failed', e, stack);
      return const [];
    }
  }

  /// Depth-first search for the `TRENDING_CHART` section's `videoViews` list.
  List<dynamic> _findTrendingViews(dynamic node) {
    if (node is Map) {
      if (node['listType'] == 'TRENDING_CHART' && node['videoViews'] is List) {
        return node['videoViews'] as List;
      }
      for (final v in node.values) {
        final found = _findTrendingViews(v);
        if (found.isNotEmpty) return found;
      }
    } else if (node is List) {
      for (final item in node) {
        final found = _findTrendingViews(item);
        if (found.isNotEmpty) return found;
      }
    }
    return const [];
  }

  /// Flattens a `{runs: [{text}]}` or plain-string title node to text.
  String? _runsText(dynamic node) {
    if (node is String) return node;
    if (node is Map && node['runs'] is List) {
      return (node['runs'] as List)
          .map((r) => (r is Map ? r['text'] : '') ?? '')
          .join();
    }
    return null;
  }

  /// Highest-resolution thumbnail URL from a `{thumbnails: [{url}]}` node.
  String? _bestThumbnail(dynamic node) {
    if (node is Map && node['thumbnails'] is List) {
      final thumbs = node['thumbnails'] as List;
      if (thumbs.isNotEmpty) {
        final last = thumbs.last;
        if (last is Map && last['url'] is String) return last['url'] as String;
      }
    }
    return null;
  }
}
