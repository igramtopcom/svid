import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:ssvid/bridge/api.dart' as native;

import '../../../../core/errors/result.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/process_helper.dart';
import '../../domain/entities/playlist_info.dart';
import '../../domain/entities/playlist_video.dart';

/// Repository for YouTube playlist operations.
///
/// Uses the native Rust executor on Windows to avoid cmd.exe/runInShell
/// overhead while still hiding console windows. Unix intentionally keeps Dart
/// [Process.run] because e3a0a056 fixed a POSIX-only SIGCHLD/ECHILD race
/// between Rust tokio process handling and Dart-spawned download processes.
class YouTubePlaylistRepository {
  static const _nativePlaylistTimeout = Duration(seconds: 60);
  static const _nativeTimeoutBuffer = Duration(seconds: 2);

  final String _binaryPath;
  final String? _cookiesFile;
  final String? _denoPath;

  /// [denoPath] — see `YouTubeSearchRepository` for the same rationale.
  /// Forwarded as `--js-runtimes deno:<path>` to yt-dlp so playlist
  /// resolution stays consistent with the extract/download path under
  /// yt-dlp 2025.11.12+ JS runtime mandate.
  YouTubePlaylistRepository({
    required String binaryPath,
    String? cookiesFile,
    String? denoPath,
  }) : _binaryPath = binaryPath,
       _cookiesFile = cookiesFile,
       _denoPath = denoPath;

  /// Get playlist information with pagination support
  ///
  /// [startIndex] - Start position (1-based, 0 = from beginning)
  /// [endIndex] - End position (1-based, 0 = no limit)
  Future<Result<(PlaylistInfo, List<PlaylistVideo>)>> getPlaylistInfo({
    required String url,
    int startIndex = 0,
    int endIndex = 0,
  }) async {
    try {
      appLogger.info(
        '[YouTube Playlist] Fetching: "$url" (start: $startIndex, end: $endIndex)',
      );
      final stopwatch = Stopwatch()..start();

      if (Platform.isWindows) {
        final (playlistDto, videoDtos) = await native
            .ytdlpGetPlaylistInfo(
              binaryPath: _binaryPath,
              url: url,
              startIndex: startIndex,
              endIndex: endIndex,
              cookiesFile: _cookiesFile,
              jsRuntimePath: _denoPath,
            )
            .timeout(
              _guardTimeoutFor(_nativePlaylistTimeout),
              onTimeout: () => throw Exception('Playlist extraction timeout'),
            );
        final playlist = mapNativePlaylistDto(playlistDto);
        final videos = videoDtos.map(mapNativeVideoDto).toList();
        stopwatch.stop();
        appLogger.info(
          '[yt-dlp playlist] videos=${videos.length} '
          'range=$startIndex-$endIndex path=native-windows '
          'duration_ms=${stopwatch.elapsedMilliseconds}',
        );
        return Result.success((playlist, videos));
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
        if (_denoPath != null) ...['--js-runtimes', 'deno:$_denoPath'],
        if (startIndex > 0) ...['--playlist-start', '$startIndex'],
        if (endIndex > 0) ...['--playlist-end', '$endIndex'],
        if (_cookiesFile != null) ...['--cookies', _cookiesFile],
        url,
      ];

      final result = await ProcessHelper.run(_binaryPath, args).timeout(
        _nativePlaylistTimeout,
        onTimeout: () => throw Exception('Playlist extraction timeout'),
      );

      if (result.exitCode != 0 && result.stdout.toString().trim().isEmpty) {
        return Result.failure(
          Exception('Playlist fetch failed: ${result.stderr}'),
        );
      }

      final (playlist, videos) = _parsePlaylistOutput(result.stdout.toString());
      stopwatch.stop();
      appLogger.info(
        '[yt-dlp playlist] videos=${videos.length} '
        'range=$startIndex-$endIndex path=dart-process '
        'duration_ms=${stopwatch.elapsedMilliseconds}',
      );

      return Result.success((playlist, videos));
    } catch (e, stack) {
      appLogger.error('[YouTube Playlist] Fetch failed', e, stack);
      return Result.failure(Exception('Playlist fetch failed: $e'));
    }
  }

  static Duration _guardTimeoutFor(Duration nativeTimeout) {
    return nativeTimeout + _nativeTimeoutBuffer;
  }

  @visibleForTesting
  static PlaylistInfo mapNativePlaylistDto(native.PlaylistInfoDto dto) {
    return PlaylistInfo(
      id: dto.id,
      title: dto.title,
      uploader: dto.uploader,
      uploaderId: dto.uploaderId,
      thumbnail: dto.thumbnail,
      description: dto.description,
      videoCount: dto.videoCount,
      webpageUrl: dto.webpageUrl,
    );
  }

  @visibleForTesting
  static PlaylistVideo mapNativeVideoDto(native.PlaylistVideoDto dto) {
    return PlaylistVideo(
      id: dto.id,
      title: dto.title,
      url: dto.url,
      thumbnail: dto.thumbnail,
      durationSeconds: dto.duration?.toInt(),
      channel: dto.channel,
      channelId: dto.channelId,
      viewCount: dto.viewCount?.toInt(),
      uploadDate: dto.uploadDate,
    );
  }

  /// Parse yt-dlp --dump-json --flat-playlist output.
  /// Each line is a JSON object. Playlist metadata is extracted from
  /// embedded playlist_* fields in the first video entry.
  static (PlaylistInfo, List<PlaylistVideo>) _parsePlaylistOutput(
    String output,
  ) {
    final lines =
        output.split('\n').where((l) => l.trim().startsWith('{')).toList();

    if (lines.isEmpty) {
      return (const PlaylistInfo(id: '', title: '', webpageUrl: ''), []);
    }

    // Extract playlist metadata from first video's embedded fields
    final firstRaw = jsonDecode(lines.first) as Map<String, dynamic>;
    final playlist = PlaylistInfo(
      id: (firstRaw['playlist_id'] as String?) ?? '',
      title: (firstRaw['playlist_title'] as String?) ?? '',
      uploader: null,
      uploaderId: null,
      thumbnail: null,
      description: null,
      videoCount: firstRaw['playlist_count'] as int?,
      webpageUrl: (firstRaw['playlist_webpage_url'] as String?) ?? '',
    );

    // Parse all lines as video entries
    final videos = <PlaylistVideo>[];
    for (final line in lines) {
      try {
        final raw = jsonDecode(line) as Map<String, dynamic>;
        if (raw['_type'] == 'playlist') continue;

        final id = (raw['id'] as String?) ?? '';
        if (id.isEmpty) continue;

        // Best thumbnail
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

        final videoUrl =
            (raw['url'] as String?) ??
            (raw['webpage_url'] as String?) ??
            'https://www.youtube.com/watch?v=$id';

        videos.add(
          PlaylistVideo(
            id: id,
            title: (raw['title'] as String?) ?? '',
            url: videoUrl,
            thumbnail: thumbnail,
            durationSeconds: (raw['duration'] as num?)?.toInt(),
            channel:
                (raw['channel'] as String?) ?? (raw['uploader'] as String?),
            channelId:
                (raw['channel_id'] as String?) ??
                (raw['uploader_id'] as String?),
            viewCount: (raw['view_count'] as num?)?.toInt(),
            uploadDate: raw['upload_date'] as String?,
          ),
        );
      } catch (_) {
        continue;
      }
    }

    return (playlist, videos);
  }
}
