import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../../../bridge/api.dart' as native;
import '../../../../core/logging/app_logger.dart';

/// Progress data from the Rust download engine
class NativeDownloadProgress {
  final int downloadedBytes;
  final int totalBytes;
  final String status; // 'downloading', 'paused', 'completed', 'failed', 'cancelled'

  const NativeDownloadProgress({
    required this.downloadedBytes,
    required this.totalBytes,
    required this.status,
  });

  bool get isTerminal =>
      status == 'completed' || status == 'failed' || status == 'cancelled';
}

/// Datasource wrapping Rust FFI calls for native HTTP downloads.
///
/// Provides UUID-based tracking: each DB integer ID is mapped to a
/// deterministic UUID so that pause/resume/cancel can find the download
/// across app restarts.
class DownloadNativeDataSource {
  static const _uuid = Uuid();

  /// Generate a deterministic UUID v5 from download URL + filename.
  /// Same inputs always produce the same UUID.
  static String generateNativeId(String url, String filename) {
    return _uuid.v5(Namespace.url.value, '$url::$filename');
  }

  /// Start a new download via Rust engine.
  /// [numSegments]: 1 = single-stream, 2-16 = multi-segment parallel download.
  /// [userAgent]: Custom User-Agent string for HTTP requests (null = default).
  /// [proxyUrl]: Optional proxy URL (e.g. "http://host:port"; null = no proxy).
  /// [headersJson]: Optional JSON string of custom HTTP headers (IDM mode).
  /// [cookiesString]: Optional raw cookie string (IDM mode).
  Future<void> startDownload({
    required String nativeId,
    required String url,
    required String outputPath,
    int? resumeOffset,
    int? maxSpeedBytes,
    int? numSegments,
    String? userAgent,
    String? proxyUrl,
    String? headersJson,
    String? cookiesString,
  }) async {
    final hasCustomHeaders = headersJson != null || cookiesString != null;
    appLogger.info('🚀 [Rust] Starting download: $nativeId'
        '${maxSpeedBytes != null && maxSpeedBytes > 0 ? " (limit: ${maxSpeedBytes}B/s)" : ""}'
        '${numSegments != null && numSegments > 1 ? " (segments: $numSegments)" : ""}'
        '${proxyUrl != null ? " (proxy: $proxyUrl)" : ""}'
        '${hasCustomHeaders ? " (IDM mode)" : ""}');

    if (hasCustomHeaders) {
      // IDM mode: use the advanced API with custom headers/cookies
      await native.downloadStartWithHeaders(
        id: nativeId,
        url: url,
        outputPath: outputPath,
        resumeOffset: resumeOffset != null ? BigInt.from(resumeOffset) : null,
        maxSpeedBytes: maxSpeedBytes != null && maxSpeedBytes > 0
            ? BigInt.from(maxSpeedBytes)
            : null,
        numSegments: numSegments,
        userAgent: userAgent,
        proxyUrl: proxyUrl,
        headersJson: headersJson,
        cookiesString: cookiesString,
      );
    } else {
      // Standard mode: existing API
      await native.downloadStart(
        id: nativeId,
        url: url,
        outputPath: outputPath,
        resumeOffset: resumeOffset != null ? BigInt.from(resumeOffset) : null,
        maxSpeedBytes: maxSpeedBytes != null && maxSpeedBytes > 0
            ? BigInt.from(maxSpeedBytes)
            : null,
        numSegments: numSegments,
        userAgent: userAgent,
        proxyUrl: proxyUrl,
      );
    }
  }

  /// Pause a running download.
  Future<void> pauseDownload(String nativeId) async {
    appLogger.info('⏸️ [Rust] Pausing download: $nativeId');
    await native.downloadPause(id: nativeId);
  }

  /// Resume a paused download.
  Future<void> resumeDownload(String nativeId) async {
    appLogger.info('▶️ [Rust] Resuming download: $nativeId');
    await native.downloadResume(id: nativeId);
  }

  /// Cancel a download.
  Future<void> cancelDownload(String nativeId) async {
    appLogger.info('❌ [Rust] Cancelling download: $nativeId');
    await native.downloadCancel(id: nativeId);
  }

  /// Get current progress snapshot.
  Future<NativeDownloadProgress> getProgress(String nativeId) async {
    final dto = await native.downloadGetProgress(id: nativeId);
    // Rust sends PascalCase via Debug format: "Downloading", "Completed",
    // "Failed(\"msg\")" — normalise to lowercase simple tokens that Dart expects.
    final raw = dto.status.toLowerCase();
    final status = raw.startsWith('failed(') ? 'failed' : raw;
    return NativeDownloadProgress(
      downloadedBytes: dto.downloadedBytes.toInt(),
      totalBytes: dto.totalBytes.toInt(),
      status: status,
    );
  }

  /// Remove a completed/failed/cancelled download from Rust memory.
  /// Call after a download reaches a terminal state to prevent memory leaks.
  Future<void> cleanupDownload(String nativeId) async {
    appLogger.info('🧹 [Rust] Cleaning up download: $nativeId');
    try {
      await native.downloadCleanup(id: nativeId);
    } catch (e) {
      // Non-fatal: task may already be removed or never existed
      appLogger.debug('[Rust] Cleanup skipped for $nativeId: $e');
    }
  }

  /// Stream progress updates by polling every [interval].
  /// Terminates when download reaches a terminal state.
  Stream<NativeDownloadProgress> watchProgress(
    String nativeId, {
    Duration interval = const Duration(milliseconds: 500),
  }) async* {
    while (true) {
      try {
        final progress = await getProgress(nativeId);
        yield progress;
        if (progress.isTerminal) break;
      } catch (e) {
        appLogger.error('[Rust] Progress poll error for $nativeId', e);
        yield NativeDownloadProgress(
          downloadedBytes: 0,
          totalBytes: 0,
          status: 'failed',
        );
        break;
      }
      await Future.delayed(interval);
    }
  }
}
