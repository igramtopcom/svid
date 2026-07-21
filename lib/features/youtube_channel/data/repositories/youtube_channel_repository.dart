import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:svid/bridge/api.dart' as native;

import '../../../../core/errors/app_exception.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/process_helper.dart';
import '../../../youtube_playlist/domain/entities/playlist_video.dart';
import '../../domain/entities/channel_info.dart';

/// Repository for YouTube channel operations.
///
/// Uses the native Rust executor on Windows to avoid cmd.exe/runInShell
/// overhead while still hiding console windows. Unix intentionally keeps Dart
/// [Process.run] because e3a0a056 fixed a POSIX-only SIGCHLD/ECHILD race
/// between Rust tokio process handling and Dart-spawned download processes.
class YouTubeChannelRepository {
  // TODO(windows-perf): extend the FRB bridge so search/playlist/channel
  // accept timeoutSecs like extractInfo, then remove these mirrored constants.
  // Keep these constants aligned with native/src/api.rs until then.
  static const _nativeChannelInfoTimeout = Duration(seconds: 60);
  static const _nativeChannelMetadataTimeout = Duration(seconds: 20);
  static const _nativeTimeoutBuffer = Duration(seconds: 2);

  final String _binaryPath;
  final String? _cookiesFile;
  final String? _denoPath;
  final Duration _timeout;

  /// [denoPath] — see `YouTubeSearchRepository` for the same rationale.
  /// Forwarded as `--js-runtimes deno:<path>` to yt-dlp so channel
  /// resolution stays consistent under yt-dlp 2025.11.12+ JS runtime
  /// mandate.
  YouTubeChannelRepository({
    required String binaryPath,
    String? cookiesFile,
    String? denoPath,
    Duration? timeout,
  }) : _binaryPath = binaryPath,
       _cookiesFile = cookiesFile,
       _denoPath = denoPath,
       _timeout = timeout ?? const Duration(seconds: 60);

  /// Get channel information with all videos
  Future<Result<(ChannelInfo, List<PlaylistVideo>)>> getChannelInfo({
    required String url,
    int startIndex = 0,
    int endIndex = 0,
  }) async {
    return runCatching(() async {
      appLogger.info(
        'Fetching channel info: $url (range: $startIndex-$endIndex)',
      );
      final stopwatch = Stopwatch()..start();

      if (Platform.isWindows) {
        if (_timeout != _nativeChannelInfoTimeout) {
          appLogger.warning(
            '[yt-dlp channel] custom_timeout_seconds=${_timeout.inSeconds} '
            'ignored_on_windows_native=true '
            'native_timeout_seconds=${_nativeChannelInfoTimeout.inSeconds}',
          );
        }
        final (channelDto, videoDtos) = await native
            .ytdlpGetChannelInfo(
              binaryPath: _binaryPath,
              url: url,
              startIndex: startIndex,
              endIndex: endIndex,
              cookiesFile: _cookiesFile,
              jsRuntimePath: _denoPath,
            )
            .timeout(
              _guardTimeoutFor(_nativeChannelInfoTimeout),
              onTimeout:
                  () =>
                      throw AppException.network(
                        message:
                            'Channel info request timed out after ${_nativeChannelInfoTimeout.inSeconds}s',
                      ),
            );
        final channel = mapNativeChannelDto(channelDto);
        final videos = videoDtos.map(mapNativeVideoDto).toList();
        stopwatch.stop();
        appLogger.info(
          '[yt-dlp channel] videos=${videos.length} '
          'range=$startIndex-$endIndex path=native-windows '
          'duration_ms=${stopwatch.elapsedMilliseconds}',
        );
        return (channel, videos);
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
        _timeout,
        onTimeout:
            () =>
                throw AppException.network(
                  message:
                      'Channel info request timed out after ${_timeout.inSeconds}s',
                ),
      );

      if (result.exitCode != 0 && result.stdout.toString().trim().isEmpty) {
        throw AppException.network(
          message: 'Channel fetch failed: ${result.stderr}',
        );
      }

      final (channel, videos) = _parseChannelOutput(
        result.stdout.toString(),
        url,
      );
      stopwatch.stop();
      appLogger.info(
        '[yt-dlp channel] videos=${videos.length} '
        'range=$startIndex-$endIndex path=dart-process '
        'duration_ms=${stopwatch.elapsedMilliseconds}',
      );
      return (channel, videos);
    });
  }

  /// Get accurate channel metadata (avatar, banner, description)
  Future<Result<ChannelInfo>> getChannelMetadata({required String url}) async {
    return runCatching(() async {
      appLogger.info('Fetching channel metadata for accurate thumbnail: $url');
      final stopwatch = Stopwatch()..start();

      if (Platform.isWindows) {
        final dto = await native
            .ytdlpGetChannelMetadata(
              binaryPath: _binaryPath,
              url: url,
              cookiesFile: _cookiesFile,
              jsRuntimePath: _denoPath,
            )
            .timeout(
              _guardTimeoutFor(_nativeChannelMetadataTimeout),
              onTimeout:
                  () =>
                      throw AppException.network(
                        message: 'Channel metadata request timed out',
                      ),
            );
        final channel = mapNativeChannelDto(dto);
        stopwatch.stop();
        appLogger.info(
          '[yt-dlp channel_metadata] thumbnail=${channel.thumbnail != null} '
          'path=native-windows duration_ms=${stopwatch.elapsedMilliseconds}',
        );
        return channel;
      }

      final args = <String>[
        '--dump-json',
        '--no-download',
        '--no-warnings',
        '--playlist-items',
        '0',
        '--socket-timeout',
        '15',
        '--extractor-retries',
        '2',
        '--no-check-certificates',
        if (_denoPath != null) ...['--js-runtimes', 'deno:$_denoPath'],
        if (_cookiesFile != null) ...['--cookies', _cookiesFile],
        url,
      ];

      final result = await ProcessHelper.run(_binaryPath, args).timeout(
        const Duration(seconds: 20),
        onTimeout:
            () =>
                throw AppException.network(
                  message: 'Channel metadata request timed out',
                ),
      );

      if (result.exitCode != 0 && result.stdout.toString().trim().isEmpty) {
        throw AppException.network(
          message: 'Channel metadata failed: ${result.stderr}',
        );
      }

      final channel = _parseChannelMetadata(result.stdout.toString(), url);
      stopwatch.stop();
      appLogger.info(
        '[yt-dlp channel_metadata] thumbnail=${channel.thumbnail != null} '
        'path=dart-process duration_ms=${stopwatch.elapsedMilliseconds}',
      );
      return channel;
    });
  }

  YouTubeChannelRepository copyWith({String? cookiesFile, Duration? timeout}) {
    return YouTubeChannelRepository(
      binaryPath: _binaryPath,
      cookiesFile: cookiesFile ?? _cookiesFile,
      timeout: timeout ?? _timeout,
    );
  }

  // ── Parsers ──────────────────────────────────────────────────────────

  static Duration _guardTimeoutFor(Duration nativeTimeout) {
    return nativeTimeout + _nativeTimeoutBuffer;
  }

  @visibleForTesting
  static ChannelInfo mapNativeChannelDto(native.ChannelInfoDto dto) {
    return ChannelInfo(
      id: dto.id,
      title: dto.title,
      uploader: dto.uploader,
      uploaderId: dto.uploaderId,
      thumbnail: dto.thumbnail,
      description: dto.description,
      subscriberCount: dto.subscriberCount?.toInt(),
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

  static (ChannelInfo, List<PlaylistVideo>) _parseChannelOutput(
    String output,
    String originalUrl,
  ) {
    final lines =
        output.split('\n').where((l) => l.trim().startsWith('{')).toList();

    if (lines.isEmpty) {
      return (
        ChannelInfo(id: '', title: '', webpageUrl: originalUrl),
        <PlaylistVideo>[],
      );
    }

    final firstRaw = jsonDecode(lines.first) as Map<String, dynamic>;

    // Extract channel ID from multiple sources
    final channelId =
        (firstRaw['channel_id'] as String?) ??
        _extractChannelIdFromUrl(originalUrl) ??
        (firstRaw['uploader_id'] as String?) ??
        originalUrl;

    final channelTitle =
        (firstRaw['channel'] as String?) ??
        (firstRaw['uploader'] as String?) ??
        '';

    final channel = ChannelInfo(
      id: channelId,
      title: channelTitle,
      uploader: firstRaw['uploader'] as String?,
      uploaderId: firstRaw['uploader_id'] as String?,
      thumbnail: _bestThumbnail(firstRaw),
      description: firstRaw['description'] as String?,
      subscriberCount: (firstRaw['channel_follower_count'] as num?)?.toInt(),
      videoCount: lines.length,
      webpageUrl: originalUrl,
    );

    final videos = <PlaylistVideo>[];
    for (final line in lines) {
      try {
        final raw = jsonDecode(line) as Map<String, dynamic>;
        if (raw['_type'] == 'playlist') continue;
        final id = (raw['id'] as String?) ?? '';
        if (id.isEmpty) continue;

        final videoUrl =
            (raw['url'] as String?) ??
            (raw['webpage_url'] as String?) ??
            'https://www.youtube.com/watch?v=$id';

        videos.add(
          PlaylistVideo(
            id: id,
            title: (raw['title'] as String?) ?? '',
            url: videoUrl,
            thumbnail: _bestThumbnail(raw),
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

    return (channel, videos);
  }

  static ChannelInfo _parseChannelMetadata(String output, String originalUrl) {
    final lines =
        output.split('\n').where((l) => l.trim().startsWith('{')).toList();

    if (lines.isEmpty) {
      return ChannelInfo(id: '', title: '', webpageUrl: originalUrl);
    }

    final raw = jsonDecode(lines.first) as Map<String, dynamic>;

    final channelId =
        (raw['channel_id'] as String?) ??
        (raw['id'] as String?) ??
        (raw['uploader_id'] as String?) ??
        '';

    return ChannelInfo(
      id: channelId,
      title:
          (raw['channel'] as String?) ??
          (raw['title'] as String?) ??
          (raw['uploader'] as String?) ??
          '',
      uploader: raw['uploader'] as String?,
      uploaderId: raw['uploader_id'] as String?,
      thumbnail: _bestThumbnail(raw),
      description: raw['description'] as String?,
      subscriberCount: (raw['channel_follower_count'] as num?)?.toInt(),
      videoCount: null,
      webpageUrl: (raw['webpage_url'] as String?) ?? originalUrl,
    );
  }

  /// Get best thumbnail from a JSON entry (highest preference)
  static String? _bestThumbnail(Map<String, dynamic> raw) {
    final direct = raw['thumbnail'] as String?;
    if (direct != null) return direct;
    final thumbs = raw['thumbnails'] as List<dynamic>?;
    if (thumbs == null || thumbs.isEmpty) return null;
    thumbs.sort(
      (a, b) => ((b as Map)['preference'] as int? ?? 0).compareTo(
        (a as Map)['preference'] as int? ?? 0,
      ),
    );
    return (thumbs.first as Map)['url'] as String?;
  }

  /// Extract channel ID from URL patterns like /channel/UCXXX or /@username
  static String? _extractChannelIdFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final segments = uri.pathSegments;
    for (var i = 0; i < segments.length; i++) {
      if (segments[i] == 'channel' && i + 1 < segments.length) {
        return segments[i + 1];
      }
    }
    // For /@username URLs, return @username
    for (final seg in segments) {
      if (seg.startsWith('@')) return seg;
    }
    return null;
  }
}
