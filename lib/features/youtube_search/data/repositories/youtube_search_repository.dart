import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:svid/bridge/api.dart' as native;

import '../../../../core/errors/result.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/process_helper.dart';
import '../../domain/entities/youtube_search_result.dart';

/// Repository for YouTube search operations.
///
/// Uses the native Rust executor on Windows to avoid cmd.exe/runInShell
/// overhead while still hiding console windows. Unix intentionally keeps Dart
/// [Process.run] because e3a0a056 fixed a POSIX-only SIGCHLD/ECHILD race
/// between Rust tokio process handling and Dart-spawned download processes.
class YouTubeSearchRepository {
  static const _nativeSearchTimeout = Duration(seconds: 30);
  static const _nativeTimeoutBuffer = Duration(seconds: 2);

  final String _binaryPath;
  final String? _cookiesFile;
  final String? _denoPath;

  /// [denoPath] is the absolute path to the app-managed Deno binary
  /// returned by `BinaryManager.getBinaryPath(BinaryType.deno)`. When
  /// non-null it is forwarded to yt-dlp via `--js-runtimes deno:<path>`
  /// so YouTube extraction can solve nsig/n-challenge JavaScript. Null
  /// means Deno is unavailable on this install — yt-dlp falls back to
  /// its built-in jsinterp which yt-dlp 2025.11.12+ has deprecated, so
  /// search/playlist/channel listing still WORKS (those paths read
  /// metadata not GVS streams) but live extraction of selected videos
  /// will degrade.
  YouTubeSearchRepository({
    required String binaryPath,
    String? cookiesFile,
    String? denoPath,
  }) : _binaryPath = binaryPath,
       _cookiesFile = cookiesFile,
       _denoPath = denoPath;

  /// Search YouTube videos
  ///
  /// [query] - Search query string
  /// [maxResults] - Maximum results to return (1-50)
  Future<Result<List<YouTubeSearchResult>>> search({
    required String query,
    int maxResults = 20,
  }) async {
    try {
      appLogger.info('[YouTube Search] Searching: "$query" (max: $maxResults)');

      final limit = maxResults.clamp(1, 50);
      final searchQuery = 'ytsearch$limit:$query';
      final stopwatch = Stopwatch()..start();

      if (Platform.isWindows) {
        final dtos = await native
            .ytdlpSearchYoutube(
              binaryPath: _binaryPath,
              query: query,
              maxResults: limit,
              cookiesFile: _cookiesFile,
              jsRuntimePath: _denoPath,
            )
            .timeout(
              _guardTimeoutFor(_nativeSearchTimeout),
              onTimeout: () => throw TimeoutException('YouTube search timeout'),
            );
        final entities = dtos.map(mapNativeSearchDto).toList();
        stopwatch.stop();
        appLogger.info(
          '[yt-dlp search] results=${entities.length} '
          'path=native-windows duration_ms=${stopwatch.elapsedMilliseconds}',
        );
        return Result.success(entities);
      }

      final args = <String>[
        '--dump-json',
        '--no-download',
        '--no-warnings',
        '--flat-playlist',
        '--ignore-errors',
        '--socket-timeout',
        '15',
        '--extractor-retries',
        '2',
        '--no-check-certificates',
        // Deno JS runtime — see YtDlpDataSource for full rationale.
        // Search results don't need stream URLs (only metadata), but
        // yt-dlp upstream may still invoke jsinterp for parsing — pass
        // explicit runtime when available so behaviour stays consistent
        // with extract/download paths.
        if (_denoPath != null) ...['--js-runtimes', 'deno:$_denoPath'],
        if (_cookiesFile != null) ...['--cookies', _cookiesFile],
        searchQuery,
      ];

      final result = await ProcessHelper.run(_binaryPath, args).timeout(
        _nativeSearchTimeout,
        onTimeout: () => throw TimeoutException('YouTube search timeout'),
      );

      if (result.exitCode != 0 && result.stdout.toString().trim().isEmpty) {
        return Result.failure(
          Exception('YouTube search failed: ${result.stderr}'),
        );
      }

      final entities = _parseSearchResults(result.stdout.toString());
      stopwatch.stop();
      appLogger.info(
        '[yt-dlp search] results=${entities.length} '
        'path=dart-process duration_ms=${stopwatch.elapsedMilliseconds}',
      );

      return Result.success(entities);
    } catch (e, stack) {
      appLogger.error('[YouTube Search] Search failed', e, stack);
      return Result.failure(Exception('Search failed: $e'));
    }
  }

  /// Fetch real popular YouTube videos via a **hashtag feed** (best-effort).
  ///
  /// YouTube retired the old `/feed/trending` page, so instead we point yt-dlp
  /// at a hashtag tab (`/hashtag/<tag>`) — these are still live and return the
  /// tag's top (most-popular) real videos with thumbnails. Unlike [search],
  /// this always uses the Dart `ProcessHelper` path (even on Windows) because
  /// the native search bridge only speaks `ytsearch:`. Returns videos only
  /// (channels filtered out); the caller falls back to curated shortcuts on
  /// failure.
  Future<Result<List<YouTubeSearchResult>>> trending({
    String hashtag = 'trending',
    int maxResults = 20,
  }) async {
    try {
      final limit = maxResults.clamp(1, 50);
      final tag = hashtag.trim().replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      final safeTag = tag.isEmpty ? 'trending' : tag;
      appLogger.info('[YouTube Trending] hashtag="#$safeTag" (max: $limit)');

      final args = <String>[
        '--dump-json',
        '--no-download',
        '--no-warnings',
        '--flat-playlist',
        '--ignore-errors',
        '--socket-timeout',
        '15',
        '--extractor-retries',
        '2',
        '--no-check-certificates',
        '--playlist-end',
        '$limit',
        if (_denoPath != null) ...['--js-runtimes', 'deno:$_denoPath'],
        if (_cookiesFile != null) ...['--cookies', _cookiesFile],
        'https://www.youtube.com/hashtag/$safeTag',
      ];

      final result = await ProcessHelper.run(_binaryPath, args).timeout(
        _nativeSearchTimeout,
        onTimeout: () => throw TimeoutException('YouTube trending timeout'),
      );

      if (result.exitCode != 0 && result.stdout.toString().trim().isEmpty) {
        return Result.failure(
          Exception('YouTube trending failed: ${result.stderr}'),
        );
      }

      final entities =
          _parseSearchResults(
            result.stdout.toString(),
          ).where((e) => !e.isChannel).toList();
      return Result.success(entities);
    } catch (e, stack) {
      appLogger.error('[YouTube Trending] failed', e, stack);
      return Result.failure(Exception('Trending failed: $e'));
    }
  }

  static Duration _guardTimeoutFor(Duration nativeTimeout) {
    return nativeTimeout + _nativeTimeoutBuffer;
  }

  /// Parse yt-dlp `--dump-json --flat-playlist` output into search results.
  /// Each line is one JSON object.
  static List<YouTubeSearchResult> _parseSearchResults(String output) {
    return output
        .split('\n')
        .where((line) => line.trim().startsWith('{'))
        .map(_parseSingleResult)
        .whereType<YouTubeSearchResult>()
        .toList();
  }

  @visibleForTesting
  static YouTubeSearchResult mapNativeSearchDto(
    native.YouTubeSearchResultDto dto,
  ) {
    return YouTubeSearchResult(
      id: dto.id,
      title: dto.title,
      channel: dto.channel,
      channelId: dto.channelId,
      thumbnail: dto.thumbnail,
      durationSeconds: dto.duration?.toInt(),
      viewCount: dto.viewCount?.toInt(),
      uploadDate: dto.uploadDate,
      url: dto.url,
      description: dto.description,
    );
  }

  /// Parse a single JSON line into a [YouTubeSearchResult], or null if invalid.
  static YouTubeSearchResult? _parseSingleResult(String jsonLine) {
    try {
      final raw = jsonDecode(jsonLine) as Map<String, dynamic>;

      // Skip playlist entries
      if (raw['_type'] == 'playlist') return null;

      final id = raw['id'] as String?;
      if (id == null || id.isEmpty) return null;

      // Best thumbnail: explicit field, or highest-preference from array
      String? thumbnail = raw['thumbnail'] as String?;
      if (thumbnail == null) {
        final thumbs = raw['thumbnails'] as List<dynamic>?;
        if (thumbs != null && thumbs.isNotEmpty) {
          thumbs.sort(
            (a, b) => ((b as Map)['preference'] as int? ?? 0).compareTo(
              (a as Map)['preference'] as int? ?? 0,
            ),
          );
          thumbnail = (thumbs.first as Map)['url'] as String?;
        }
      }

      final url =
          (raw['url'] as String?) ??
          (raw['webpage_url'] as String?) ??
          'https://www.youtube.com/watch?v=$id';

      return YouTubeSearchResult(
        id: id,
        title: (raw['title'] as String?) ?? '',
        channel: (raw['channel'] as String?) ?? (raw['uploader'] as String?),
        channelId:
            (raw['channel_id'] as String?) ?? (raw['uploader_id'] as String?),
        thumbnail: thumbnail,
        durationSeconds: (raw['duration'] as num?)?.toInt(),
        viewCount: (raw['view_count'] as num?)?.toInt(),
        uploadDate: raw['upload_date'] as String?,
        url: url,
        description: raw['description'] as String?,
      );
    } catch (e) {
      appLogger.warning('[YouTube Search] Failed to parse result: $e');
      return null;
    }
  }
}
