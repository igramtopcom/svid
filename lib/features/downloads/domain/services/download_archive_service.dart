import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../../../core/logging/app_logger.dart';

/// Result of a duplicate check against the download archive.
class ArchiveCheckResult {
  final bool isDuplicate;
  final String? title;
  final DateTime? completedAt;
  final String? reason;

  const ArchiveCheckResult({
    required this.isDuplicate,
    this.title,
    this.completedAt,
    this.reason,
  });

  const ArchiveCheckResult.notFound()
      : isDuplicate = false,
        title = null,
        completedAt = null,
        reason = null;
}

/// Service that checks if a URL has already been downloaded.
///
/// Two-layer check:
/// 1. **Database**: queries completed downloads by normalized URL
/// 2. **Archive file**: reads yt-dlp `--download-archive` file for video IDs
///
/// Used to prevent duplicate downloads when `archiveEnabled` setting is on.
class DownloadArchiveService {
  /// Check if [url] was already downloaded by looking up [completedDownloads].
  ///
  /// [completedDownloads] is a list of (url, title, completedAt) tuples
  /// from the download database (status == completed).
  ArchiveCheckResult checkDatabase(
    String url,
    List<({String url, String? title, DateTime updatedAt})> completedDownloads,
  ) {
    final normalizedInput = _normalizeUrl(url);

    for (final download in completedDownloads) {
      final normalizedExisting = _normalizeUrl(download.url);
      if (normalizedInput == normalizedExisting) {
        appLogger.debug(
          '📋 [Archive] Duplicate found in DB: ${download.title ?? url}',
        );
        return ArchiveCheckResult(
          isDuplicate: true,
          title: download.title,
          completedAt: download.updatedAt,
          reason: 'Previously downloaded${download.title != null ? ': ${download.title}' : ''}',
        );
      }
    }

    return const ArchiveCheckResult.notFound();
  }

  /// Check if [url] or its video ID exists in the yt-dlp archive file.
  ///
  /// Archive file format (one entry per line):
  /// ```
  /// youtube BjV35ZTRl_w
  /// instagram C1234567890
  /// ```
  Future<ArchiveCheckResult> checkArchiveFile(
    String url,
    String archiveFilePath,
  ) async {
    final file = File(archiveFilePath);
    if (!await file.exists()) {
      return const ArchiveCheckResult.notFound();
    }

    try {
      final videoId = extractVideoId(url);
      if (videoId == null) {
        return const ArchiveCheckResult.notFound();
      }

      final lines = await file.readAsLines();
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        // Format: "platform videoId"
        final parts = trimmed.split(RegExp(r'\s+'));
        if (parts.length >= 2 && parts[1] == videoId) {
          appLogger.debug(
            '📋 [Archive] Duplicate found in archive file: $videoId',
          );
          return ArchiveCheckResult(
            isDuplicate: true,
            reason: 'Found in download archive (ID: $videoId)',
          );
        }
      }

      return const ArchiveCheckResult.notFound();
    } catch (e) {
      appLogger.warning('⚠️ [Archive] Error reading archive file: $e');
      return const ArchiveCheckResult.notFound();
    }
  }

  /// Extract video/content ID from a URL for archive file matching.
  static String? extractVideoId(String url) {
    try {
      final uri = Uri.parse(url.trim());
      final host = uri.host.toLowerCase();

      // YouTube: ?v=ID or /shorts/ID or youtu.be/ID
      if (host.contains('youtube.com') || host.contains('youtu.be')) {
        if (host.contains('youtu.be')) {
          final path = uri.pathSegments;
          return path.isNotEmpty ? path.first : null;
        }
        if (uri.path.contains('/shorts/')) {
          final segments = uri.pathSegments;
          final idx = segments.indexOf('shorts');
          return idx >= 0 && idx + 1 < segments.length
              ? segments[idx + 1]
              : null;
        }
        return uri.queryParameters['v'];
      }

      // TikTok: /@user/video/ID
      if (host.contains('tiktok.com')) {
        final segments = uri.pathSegments;
        final idx = segments.indexOf('video');
        return idx >= 0 && idx + 1 < segments.length
            ? segments[idx + 1]
            : null;
      }

      // Vimeo: vimeo.com/ID
      if (host.contains('vimeo.com')) {
        final segments = uri.pathSegments;
        if (segments.isNotEmpty) {
          final last = segments.last;
          if (RegExp(r'^\d+$').hasMatch(last)) return last;
        }
        return null;
      }

      // Instagram: /p/ID or /reel/ID
      if (host.contains('instagram.com')) {
        final segments = uri.pathSegments;
        for (final key in ['p', 'reel', 'tv']) {
          final idx = segments.indexOf(key);
          if (idx >= 0 && idx + 1 < segments.length) {
            return segments[idx + 1];
          }
        }
        return null;
      }

      // Twitter/X: /status/ID
      if (host.contains('twitter.com') || host.contains('x.com')) {
        final segments = uri.pathSegments;
        final idx = segments.indexOf('status');
        return idx >= 0 && idx + 1 < segments.length
            ? segments[idx + 1]
            : null;
      }

      // Facebook: /videos/ID
      if (host.contains('facebook.com') || host.contains('fb.watch')) {
        final segments = uri.pathSegments;
        final idx = segments.indexOf('videos');
        if (idx >= 0 && idx + 1 < segments.length) {
          return segments[idx + 1];
        }
        return null;
      }

      // Bilibili: /video/BVxxx or /video/avxxx
      if (host.contains('bilibili.com')) {
        final segments = uri.pathSegments;
        final idx = segments.indexOf('video');
        return idx >= 0 && idx + 1 < segments.length
            ? segments[idx + 1]
            : null;
      }

      // Dailymotion: /video/ID
      if (host.contains('dailymotion.com')) {
        final segments = uri.pathSegments;
        final idx = segments.indexOf('video');
        return idx >= 0 && idx + 1 < segments.length
            ? segments[idx + 1]
            : null;
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  /// Normalize URL for comparison (same logic as ExtractionCacheService).
  static String _normalizeUrl(String url) {
    try {
      var uri = Uri.parse(url.trim());

      const trackingParams = {
        'utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content',
        'si', 'feature', 'ref', 'fbclid', 'gclid',
      };

      final cleanParams = Map<String, String>.from(uri.queryParameters)
        ..removeWhere((key, _) => trackingParams.contains(key));

      uri = uri.replace(
        queryParameters: cleanParams.isEmpty ? null : cleanParams,
      );

      var path = uri.path;
      if (path.endsWith('/') && path.length > 1) {
        path = path.substring(0, path.length - 1);
      }

      return '${uri.scheme}://${uri.host.toLowerCase()}$path'
          '${uri.query.isNotEmpty ? '?${uri.query}' : ''}';
    } catch (_) {
      return url.trim().toLowerCase();
    }
  }

  /// Compute a hash for the URL (for file-based lookups).
  static String hashUrl(String url) {
    final normalized = _normalizeUrl(url);
    return sha256.convert(utf8.encode(normalized)).toString();
  }

  // ==================== WRITE METHODS ====================

  /// Append an entry to the yt-dlp archive file.
  ///
  /// Format: `{platform} {videoId}\n`
  Future<void> addToArchive(
    String platform,
    String videoId,
    String archiveFilePath,
  ) async {
    try {
      final file = File(archiveFilePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '${platform.toLowerCase()} $videoId\n',
        mode: FileMode.append,
      );
      appLogger.debug(
        '📋 [Archive] Added to archive: $platform $videoId',
      );
    } catch (e) {
      appLogger.warning('⚠️ [Archive] Failed to add to archive: $e');
    }
  }

  /// Remove all entries for [videoId] from the archive file.
  Future<void> removeFromArchive(
    String videoId,
    String archiveFilePath,
  ) async {
    try {
      final file = File(archiveFilePath);
      if (!await file.exists()) return;

      final lines = await file.readAsLines();
      final filtered = lines.where((line) {
        final parts = line.trim().split(RegExp(r'\s+'));
        return !(parts.length >= 2 && parts[1] == videoId);
      }).toList();

      await file.writeAsString(
        filtered.isEmpty ? '' : '${filtered.join('\n')}\n',
      );
      appLogger.debug('📋 [Archive] Removed from archive: $videoId');
    } catch (e) {
      appLogger.warning('⚠️ [Archive] Failed to remove from archive: $e');
    }
  }

  /// Count the number of entries in the archive file.
  Future<int> getArchiveCount(String archiveFilePath) async {
    try {
      final file = File(archiveFilePath);
      if (!await file.exists()) return 0;

      final lines = await file.readAsLines();
      return lines.where((l) => l.trim().isNotEmpty).length;
    } catch (e) {
      appLogger.warning('⚠️ [Archive] Failed to count archive: $e');
      return 0;
    }
  }

  /// Delete all entries from the archive file.
  Future<void> clearArchive(String archiveFilePath) async {
    try {
      final file = File(archiveFilePath);
      if (await file.exists()) {
        await file.writeAsString('');
      }
      appLogger.info('📋 [Archive] Archive cleared');
    } catch (e) {
      appLogger.warning('⚠️ [Archive] Failed to clear archive: $e');
    }
  }

  /// Merge entries from [source] archive file into [targetPath], deduplicating.
  Future<void> importArchive(File source, String targetPath) async {
    try {
      if (!await source.exists()) return;

      final sourceLines = await source.readAsLines();
      final targetFile = File(targetPath);
      await targetFile.parent.create(recursive: true);

      final existingLines = await targetFile.exists()
          ? await targetFile.readAsLines()
          : <String>[];

      final existing = existingLines
          .where((l) => l.trim().isNotEmpty)
          .toSet();

      final toAdd = sourceLines
          .where((l) => l.trim().isNotEmpty && !existing.contains(l.trim()))
          .toList();

      if (toAdd.isNotEmpty) {
        await targetFile.writeAsString(
          '${toAdd.join('\n')}\n',
          mode: FileMode.append,
        );
      }
      appLogger.info(
        '📋 [Archive] Imported ${toAdd.length} new entries from ${source.path}',
      );
    } catch (e) {
      appLogger.warning('⚠️ [Archive] Failed to import archive: $e');
    }
  }

  /// Returns the archive file for export (null if file doesn't exist).
  Future<File?> exportArchive(String archiveFilePath) async {
    try {
      final file = File(archiveFilePath);
      if (!await file.exists()) return null;
      return file;
    } catch (e) {
      appLogger.warning('⚠️ [Archive] Failed to export archive: $e');
      return null;
    }
  }
}
