import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import 'package:flutter/foundation.dart';

import '../config/brand_config.dart';
import '../constants/app_constants.dart';
import '../network/shared_http_client.dart';
import 'binary_info.dart';
import 'binary_manager.dart';
import 'binary_type.dart';

/// Progress information for binary download
class BinaryDownloadProgress {
  final BinaryType type;
  final int downloadedBytes;
  final int totalBytes;
  final BinaryDownloadStatus status;
  final String? error;

  const BinaryDownloadProgress({
    required this.type,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.status,
    this.error,
  });

  double get progress => totalBytes > 0 ? downloadedBytes / totalBytes : 0;
  int get percentage => (progress * 100).round();

  factory BinaryDownloadProgress.starting(BinaryType type) {
    return BinaryDownloadProgress(
      type: type,
      downloadedBytes: 0,
      totalBytes: 0,
      status: BinaryDownloadStatus.starting,
    );
  }

  factory BinaryDownloadProgress.downloading(
    BinaryType type,
    int downloaded,
    int total,
  ) {
    return BinaryDownloadProgress(
      type: type,
      downloadedBytes: downloaded,
      totalBytes: total,
      status: BinaryDownloadStatus.downloading,
    );
  }

  factory BinaryDownloadProgress.extracting(BinaryType type) {
    return BinaryDownloadProgress(
      type: type,
      downloadedBytes: 0,
      totalBytes: 0,
      status: BinaryDownloadStatus.extracting,
    );
  }

  factory BinaryDownloadProgress.completed(BinaryType type) {
    return BinaryDownloadProgress(
      type: type,
      downloadedBytes: 0,
      totalBytes: 0,
      status: BinaryDownloadStatus.completed,
    );
  }

  factory BinaryDownloadProgress.error(BinaryType type, String message) {
    return BinaryDownloadProgress(
      type: type,
      downloadedBytes: 0,
      totalBytes: 0,
      status: BinaryDownloadStatus.error,
      error: message,
    );
  }
}

enum BinaryDownloadStatus {
  starting,
  downloading,
  extracting,
  completed,
  error,
}

/// Downloads binaries with progress reporting
class BinaryDownloader {
  final http.Client _client;
  final Duration _streamIdleTimeout;

  /// Default client is the process-lifetime [SharedHttpClient.instance],
  /// whose `close()` is a no-op — so [dispose] below is safe to call
  /// even when the downloader is garbage-collected while other services
  /// (auto-update, ytdlp version service) still hold the same singleton.
  /// Injecting a custom [client] is kept for tests; the injected client
  /// WILL be closed by [dispose].
  BinaryDownloader({
    http.Client? client,
    Duration streamIdleTimeout = const Duration(seconds: 45),
  }) : _client = client ?? SharedHttpClient.instance,
       _streamIdleTimeout = streamIdleTimeout;

  /// Download a binary with progress streaming
  Stream<BinaryDownloadProgress> download({
    required BinaryInfo info,
    required String targetDir,
  }) async* {
    yield BinaryDownloadProgress.starting(info.type);

    try {
      // Ensure target directory exists
      final dir = Directory(targetDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // Try each candidate URL in order (primary first, then fallbacks)
      // until one returns a 200. This defends against the upstream-
      // publishes-empty-release pattern (e.g. mikf/gallery-dl v1.32.0 on
      // 2026-04-24, which served HTTP 404 to every Windows fresh install).
      // Fallback URLs MUST point to a binary in the same format/archive
      // shape as the primary — _getArchiveExtension reads info.downloadUrl
      // for extension detection on the resulting temp file.
      http.StreamedResponse? response;
      String? lastErr;
      for (final candidateUrl in info.allUrls) {
        try {
          final resolvedUrl = await _resolveRedirects(candidateUrl);
          final request = http.Request('GET', Uri.parse(resolvedUrl));
          request.headers['User-Agent'] =
              '${BrandConfig.current.appName}/${AppConstants.appVersion}';

          // Bound the initial-response phase so a stalled CDN cannot
          // hang the binary-provisioning flow at first launch.
          final r = await _client
              .send(request)
              .timeout(
                const Duration(seconds: 30),
                onTimeout:
                    () =>
                        throw TimeoutException(
                          'Binary CDN did not respond within 30 seconds.',
                        ),
              );

          if (r.statusCode == 200) {
            response = r;
            break;
          }

          // Drain the stream so the underlying connection is freed before
          // we open a new request to the next mirror.
          await r.stream.drain<void>();
          lastErr = 'HTTP ${r.statusCode}';
          debugPrint(
            '⚠️ [BinaryDownloader] ${info.type.displayName}: '
            '$candidateUrl returned ${r.statusCode}, trying next mirror',
          );
        } on TimeoutException {
          lastErr = 'timeout';
          debugPrint(
            '⚠️ [BinaryDownloader] ${info.type.displayName}: '
            '$candidateUrl timed out, trying next mirror',
          );
        } catch (e) {
          lastErr = e.toString();
          debugPrint(
            '⚠️ [BinaryDownloader] ${info.type.displayName}: '
            '$candidateUrl failed ($e), trying next mirror',
          );
        }
      }

      if (response == null) {
        yield BinaryDownloadProgress.error(
          info.type,
          'All ${info.allUrls.length} mirror(s) failed for '
          '${info.type.displayName} (last error: ${lastErr ?? "unknown"}). '
          'Check your internet connection or upstream availability.',
        );
        return;
      }

      final totalBytes = response.contentLength ?? 0;
      var downloadedBytes = 0;

      // Determine temp file path with correct extension for archive detection
      final archiveExt = _getArchiveExtension(info.downloadUrl);
      final tempPath = path.join(
        targetDir,
        '${info.type.filename}$archiveExt.download',
      );
      final tempFile = File(tempPath);
      final sink = tempFile.openWrite();

      try {
        await for (final chunk in response.stream.timeout(
          _streamIdleTimeout,
          onTimeout: (eventSink) {
            eventSink.addError(
              TimeoutException(
                'Binary download stalled for '
                '${_streamIdleTimeout.inSeconds} seconds.',
              ),
            );
          },
        )) {
          sink.add(chunk);
          downloadedBytes += chunk.length;

          yield BinaryDownloadProgress.downloading(
            info.type,
            downloadedBytes,
            totalBytes,
          );
        }

        await sink.flush();
        await sink.close();

        // Integrity check — verify the downloaded payload against an
        // upstream SHA-256 manifest BEFORE we extract or install it. This
        // catches asset-level tampering (CDN serving a malicious file under
        // the expected asset name) and corrupted downloads that happen to
        // pass the size-only floor check. For sources that publish no
        // manifest (ffmpeg CDN, gallery-dl builds), we still compute and
        // log the hash so there is an audit trail — future work can move
        // that list into a backend-signed manifest.
        final downloadedHash = await _computeFileSha256(tempFile);
        if (info.checksumsUrl != null && info.checksumsFilename != null) {
          final expectedHash = await _fetchExpectedHash(
            info.checksumsUrl!,
            info.checksumsFilename!,
          );
          if (expectedHash == null) {
            // Manifest was unreachable or did not list our file. Failing
            // open here lets users keep downloading when GitHub is having
            // a hiccup; failing closed would strand everyone during the
            // outage. The hash we computed is still logged below.
            debugPrint(
              '⚠️ [BinaryDownloader] ${info.type.displayName} upstream '
              'manifest unavailable — accepting download on HTTPS trust only '
              '(sha256=$downloadedHash)',
            );
          } else if (expectedHash != downloadedHash) {
            if (await tempFile.exists()) {
              await tempFile.delete();
            }
            yield BinaryDownloadProgress.error(
              info.type,
              'Integrity verification failed for ${info.type.displayName}. '
              'Upstream SHA-256 manifest expected $expectedHash, '
              'downloaded file hashed to $downloadedHash. '
              'This can indicate CDN compromise or a corrupted download — '
              'retry, and if the mismatch persists, report the URL + hash.',
            );
            return;
          } else {
            debugPrint(
              '🔐 [BinaryDownloader] ${info.type.displayName} SHA-256 '
              'verified against upstream manifest',
            );
          }
        } else if (info.sha256 != null) {
          // Inline SHA-256 pinning — used when the upstream publishes no
          // co-located checksum manifest but the release flow is stable
          // enough that we pin the hex hash at build time and refresh on
          // version bumps (e.g. Deno publishes a separate hashes file we
          // mirror inline in `binary_info.dart`). Failure here is fatal —
          // a mismatch means either the CDN is serving a different file
          // than expected, or our pinned hash is stale and the build needs
          // updating. Either way, refusing the binary is the safe call.
          final expected = info.sha256!.toLowerCase();
          if (expected != downloadedHash.toLowerCase()) {
            if (await tempFile.exists()) {
              await tempFile.delete();
            }
            yield BinaryDownloadProgress.error(
              info.type,
              'Integrity verification failed for ${info.type.displayName}. '
              'Pinned SHA-256 expected $expected, downloaded file hashed '
              'to $downloadedHash. This indicates either CDN compromise '
              'or that the pinned hash is out of date — refuse the binary '
              'and report.',
            );
            return;
          }
          debugPrint(
            '🔐 [BinaryDownloader] ${info.type.displayName} SHA-256 '
            'verified against pinned manifest',
          );
        } else {
          // No upstream checksum source AND no inline pin — stay on HTTPS
          // trust but log the observed hash so operators can correlate
          // against a future backend-served manifest.
          debugPrint(
            '🔓 [BinaryDownloader] ${info.type.displayName} sha256='
            '$downloadedHash (no checksum manifest or inline pin)',
          );
        }

        // Handle archive extraction if needed
        final finalPath = path.join(targetDir, info.type.filename);

        if (info.isArchive) {
          yield BinaryDownloadProgress.extracting(info.type);
          await _extractBinary(
            tempPath,
            finalPath,
            info.archiveInternalPath,
            info.downloadUrl, // Pass URL for format detection
          );

          // Extract ffprobe companion from the same archive (Windows/Linux)
          if (info.type == BinaryType.ffmpeg) {
            await _extractFfprobe(tempPath, targetDir, info);
          }

          await tempFile.delete();
        } else {
          // Direct binary, just rename
          await tempFile.rename(finalPath);
        }

        // Make executable on Unix. chmod failing here is the difference
        // between a usable binary and a "permission denied" error that
        // surfaces much later at actual invocation time — yield an
        // actionable error now rather than reporting COMPLETED over a
        // binary the user can't run.
        if (!Platform.isWindows) {
          final chmodResult = await Process.run('chmod', ['+x', finalPath]);
          if (chmodResult.exitCode != 0) {
            yield BinaryDownloadProgress.error(
              info.type,
              'chmod +x failed for ${info.type.displayName} '
              '(${chmodResult.stderr.toString().trim()}). '
              'The binary cannot run until it is marked executable.',
            );
            return;
          }
        }

        // macOS: strip quarantine/provenance xattrs + ad-hoc codesign.
        // These are cosmetic hardening — the binary can still run without
        // them (first invocation just triggers Gatekeeper translocation).
        // Log any failures instead of aborting the download flow.
        if (Platform.isMacOS) {
          final xattrResult = await Process.run('xattr', ['-cr', finalPath]);
          if (xattrResult.exitCode != 0) {
            debugPrint(
              '⚠️ [BinaryDownloader] xattr -cr failed for '
              '${info.type.displayName}: ${xattrResult.stderr}',
            );
          }

          // If yt-dlp zipapp: patch shebang to use detected Python 3.10+ path
          // This avoids PyInstaller extraction + macOS XProtect scan delay (6-45s)
          if (info.type == BinaryType.ytDlp) {
            await _patchZipappShebang(finalPath);
          }

          final signResult = await Process.run('codesign', [
            '--force',
            '--sign',
            '-',
            finalPath,
          ]);
          if (signResult.exitCode != 0) {
            debugPrint(
              '⚠️ [BinaryDownloader] ad-hoc codesign failed for '
              '${info.type.displayName}: ${signResult.stderr}',
            );
          }
        }

        // macOS: ffprobe is a separate download (martin-riedl.de, arch-aware)
        if (info.type == BinaryType.ffmpeg && Platform.isMacOS) {
          await _ensureFfprobe(targetDir);
        }

        yield BinaryDownloadProgress.completed(info.type);
      } catch (e) {
        await sink.close();
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        rethrow;
      }
    } catch (e) {
      final msg = e.toString();
      final lower = msg.toLowerCase();
      String errorMsg;
      if (lower.contains('certificate_verify_failed') ||
          lower.contains('handshakeexception') ||
          lower.contains('bad certificate') ||
          lower.contains('tlsexception')) {
        errorMsg =
            'SSL certificate verification failed for ${info.type.displayName}. '
            'This is often caused by antivirus SSL scanning or corporate proxy.';
      } else if (lower.contains('socketexception') ||
          lower.contains('failed host lookup') ||
          lower.contains('network is unreachable')) {
        errorMsg =
            'Network error downloading ${info.type.displayName}. Check your internet connection.';
      } else if (lower.contains('timeout') || lower.contains('timed out')) {
        errorMsg =
            'Download timed out for ${info.type.displayName}. Server may be slow — try again.';
      } else {
        errorMsg = msg;
      }
      yield BinaryDownloadProgress.error(info.type, errorMsg);
    }
  }

  /// Get archive extension from URL
  String _getArchiveExtension(String url) {
    final lowerUrl = url.toLowerCase();
    if (lowerUrl.endsWith('.tar.xz')) return '.tar.xz';
    if (lowerUrl.endsWith('.tar.gz')) return '.tar.gz';
    if (lowerUrl.endsWith('.tgz')) return '.tgz';
    if (lowerUrl.endsWith('.zip')) return '.zip';
    if (lowerUrl.contains('/zip') || lowerUrl.contains('zip=')) return '.zip';
    return '';
  }

  /// Patch yt-dlp zipapp shebang to use detected Python 3.10+ path.
  /// The zipapp has `#!/usr/bin/env python3` which may resolve to Python 3.9 (too old).
  /// We replace it with the exact Python 3.10+ path found during initialization.
  Future<void> _patchZipappShebang(String filePath) async {
    final pythonPath = BinaryManager.pythonPath;
    if (pythonPath == null) {
      return; // No Python 3.10+ → file is PyInstaller binary, skip
    }

    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();

      // Check if file starts with "#!" (shebang = zipapp, not PyInstaller binary)
      if (bytes.length < 2 || bytes[0] != 0x23 || bytes[1] != 0x21) return;

      // Find end of first line
      final newlineIdx = bytes.indexOf(0x0A);
      if (newlineIdx == -1) return;

      final newShebang = '#!$pythonPath\n';
      final restOfFile = bytes.sublist(newlineIdx + 1);

      await file.writeAsBytes([...newShebang.codeUnits, ...restOfFile]);

      debugPrint('🐍 [BinaryDownloader] Patched yt-dlp shebang → $pythonPath');
    } catch (e) {
      debugPrint('⚠️ [BinaryDownloader] Failed to patch shebang: $e');
      // Non-fatal: yt-dlp will still work, just potentially slower
    }
  }

  /// Resolve redirects to get final download URL
  Future<String> _resolveRedirects(String url) async {
    var currentUrl = url;
    var redirectCount = 0;
    const maxRedirects = 10;

    while (redirectCount < maxRedirects) {
      final request = http.Request('HEAD', Uri.parse(currentUrl));
      request.followRedirects = false;
      request.headers['User-Agent'] =
          '${BrandConfig.current.appName}/${AppConstants.appVersion}';

      // HEAD probes for redirect chains must be bounded — an unresponsive
      // hop otherwise blocks the entire download pipeline before we even
      // start streaming bytes.
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 10));

      if (response.isRedirect) {
        final location = response.headers['location'];
        if (location != null) {
          // Handle relative redirects
          if (location.startsWith('/')) {
            final uri = Uri.parse(currentUrl);
            currentUrl = '${uri.scheme}://${uri.host}$location';
          } else {
            currentUrl = location;
          }
          redirectCount++;
          continue;
        }
      }

      return currentUrl;
    }

    return currentUrl;
  }

  /// Extract binary from archive
  /// Uses downloadUrl to detect archive format (more reliable than temp filename)
  Future<void> _extractBinary(
    String archivePath,
    String targetPath,
    String? internalPath,
    String downloadUrl,
  ) async {
    final bytes = await File(archivePath).readAsBytes();
    final lowerUrl = downloadUrl.toLowerCase();

    Archive archive;
    // Detect format from URL, not from temp file path
    if (lowerUrl.endsWith('.zip') ||
        lowerUrl.contains('/zip') ||
        lowerUrl.contains('zip=')) {
      archive = ZipDecoder().decodeBytes(bytes);
    } else if (lowerUrl.endsWith('.tar.xz')) {
      final decompressed = XZDecoder().decodeBytes(bytes);
      archive = TarDecoder().decodeBytes(decompressed);
    } else if (lowerUrl.endsWith('.tar.gz') || lowerUrl.endsWith('.tgz')) {
      final decompressed = GZipDecoder().decodeBytes(bytes);
      archive = TarDecoder().decodeBytes(decompressed);
    } else {
      // Fallback: try to detect from magic bytes
      archive = _detectAndDecodeArchive(bytes);
    }

    // Find the target file in archive
    final targetName = internalPath ?? path.basename(targetPath);

    for (final file in archive) {
      if (file.isFile) {
        final filePath = file.name;
        // Match by exact path or by filename
        if (filePath == targetName ||
            filePath.endsWith('/$targetName') ||
            filePath.endsWith('\\$targetName') ||
            path.basename(filePath) == path.basename(targetName)) {
          final data = file.content as List<int>;
          await File(targetPath).writeAsBytes(data);
          return;
        }
      }
    }

    throw Exception('Binary not found in archive: $targetName');
  }

  /// Detect archive format from magic bytes and decode
  Archive _detectAndDecodeArchive(List<int> bytes) {
    // ZIP magic: PK (0x50 0x4B)
    if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
      return ZipDecoder().decodeBytes(bytes);
    }
    // XZ magic: 0xFD 0x37 0x7A 0x58 0x5A 0x00
    if (bytes.length >= 6 &&
        bytes[0] == 0xFD &&
        bytes[1] == 0x37 &&
        bytes[2] == 0x7A &&
        bytes[3] == 0x58 &&
        bytes[4] == 0x5A &&
        bytes[5] == 0x00) {
      final decompressed = XZDecoder().decodeBytes(bytes);
      return TarDecoder().decodeBytes(decompressed);
    }
    // GZIP magic: 0x1F 0x8B
    if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
      final decompressed = GZipDecoder().decodeBytes(bytes);
      return TarDecoder().decodeBytes(decompressed);
    }
    throw UnsupportedError('Unable to detect archive format');
  }

  /// Extract ffprobe from the same archive as ffmpeg (Windows/Linux).
  /// On macOS (martin-riedl.de), ffprobe is NOT in the ffmpeg ZIP — handled separately.
  Future<void> _extractFfprobe(
    String archivePath,
    String targetDir,
    BinaryInfo info,
  ) async {
    final ffprobeName = Platform.isWindows ? 'ffprobe.exe' : 'ffprobe';
    final ffprobePath = path.join(targetDir, ffprobeName);
    if (await File(ffprobePath).exists()) return;

    // Derive ffprobe path from ffmpeg's archive internal path
    final ffprobeInternalPath = info.archiveInternalPath?.replaceAll(
      RegExp(r'ffmpeg(\.exe)?$'),
      ffprobeName,
    );

    try {
      await _extractBinary(
        archivePath,
        ffprobePath,
        ffprobeInternalPath,
        info.downloadUrl,
      );
      if (!Platform.isWindows) {
        final chmodResult = await Process.run('chmod', ['+x', ffprobePath]);
        if (chmodResult.exitCode != 0) {
          debugPrint(
            '⚠️ [BinaryDownloader] chmod +x failed for ffprobe: '
            '${chmodResult.stderr}',
          );
        }
      }
      if (Platform.isMacOS) {
        await Process.run('xattr', ['-cr', ffprobePath]);
        await Process.run('codesign', ['--force', '--sign', '-', ffprobePath]);
      }
    } catch (_) {
      // ffprobe not in this archive (e.g. macOS martin-riedl.de) — will be handled separately
    }
  }

  /// Download ffprobe separately for macOS (martin-riedl.de, architecture-aware).
  Future<void> _ensureFfprobe(String targetDir) async {
    final ffprobePath = path.join(targetDir, 'ffprobe');
    if (await File(ffprobePath).exists()) return;

    try {
      // Use same architecture detection as BinaryInfo
      final arch = BinaryManager.macOSArch;
      final ffprobeUrl =
          'https://ffmpeg.martin-riedl.de/redirect/latest/macos/$arch/snapshot/ffprobe.zip';
      final resolvedUrl = await _resolveRedirects(ffprobeUrl);
      final response = await _client
          .get(
            Uri.parse(resolvedUrl),
            headers: {
              'User-Agent':
                  '${BrandConfig.current.appName}/${AppConstants.appVersion}',
            },
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        debugPrint(
          '⚠️ [BinaryDownloader] ffprobe download returned '
          'HTTP ${response.statusCode} — metadata embedding will be '
          'degraded until next launch retry',
        );
        return;
      }

      final tempPath = path.join(targetDir, 'ffprobe.zip.download');
      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(response.bodyBytes);

      await _extractBinary(tempPath, ffprobePath, 'ffprobe', ffprobeUrl);
      await tempFile.delete();
      await Process.run('chmod', ['+x', ffprobePath]);
      await Process.run('xattr', ['-cr', ffprobePath]);
      await Process.run('codesign', ['--force', '--sign', '-', ffprobePath]);
    } catch (e) {
      // Non-fatal: metadata embedding won't work, but downloads still
      // succeed. Surface the cause at debug level so we can triage when
      // users report missing metadata / thumbnail oddities.
      debugPrint('⚠️ [BinaryDownloader] ffprobe ensure failed: $e');
    }
  }

  /// Fetch a GNU `sha256sum`-style checksum file and return the hex hash for
  /// [filename]. Tries the primary URL first, then any GitHub-mirror
  /// fallbacks if the primary fails — otherwise a network that blocked the
  /// binary download (forcing a mirror hop) would ALSO block the manifest
  /// fetch, and the integrity check would silently fall open (production
  /// risk: mirror serves a tampered binary AND user is in a region where
  /// the canonical manifest is unreachable). Returns null only when EVERY
  /// candidate URL fails — callers treat null as "proceed without
  /// authoritative check".
  Future<String?> _fetchExpectedHash(
    String checksumsUrl,
    String filename,
  ) async {
    final candidates = [checksumsUrl, ...githubMirrorChain(checksumsUrl)];
    for (final url in candidates) {
      try {
        final resolved = await _resolveRedirects(url);
        final response = await _client
            .get(
              Uri.parse(resolved),
              headers: {
                'User-Agent':
                    '${BrandConfig.current.appName}/${AppConstants.appVersion}',
              },
            )
            .timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) {
          debugPrint(
            '⚠️ [BinaryDownloader] checksum manifest HTTP '
            '${response.statusCode} from $url',
          );
          continue;
        }
        final hash = parseChecksums(response.body, filename);
        if (hash != null) return hash;
        // Manifest fetched but filename not listed — try next mirror.
        // (Public proxies occasionally serve a cached error page with 200.)
      } catch (e) {
        debugPrint(
          '⚠️ [BinaryDownloader] checksum manifest fetch failed for $url: $e',
        );
      }
    }
    return null;
  }

  /// Parse a GNU `sha256sum` manifest. Accepts both text mode
  /// (`<hash>␣␣<filename>`) and binary mode (`<hash>␣*<filename>`), skips
  /// blank lines and `#` comments, and tolerates extra whitespace. Returns
  /// the lowercase hex hash for [filename], or null if no valid entry is
  /// found. Exposed for unit tests.
  @visibleForTesting
  static String? parseChecksums(String body, String filename) {
    final hexLine = RegExp(r'^[0-9a-f]{64}$');
    for (final raw in const LineSplitter().convert(body)) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final hash = parts[0].toLowerCase();
      if (!hexLine.hasMatch(hash)) continue;
      final raw2 = parts.sublist(1).join(' ');
      final name = raw2.startsWith('*') ? raw2.substring(1) : raw2;
      if (name == filename) return hash;
    }
    return null;
  }

  /// Compute SHA-256 of a file via streaming read — O(chunk) memory,
  /// safe for 100MB+ archives without doubling peak RSS.
  Future<String> _computeFileSha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase();
  }

  void dispose() {
    _client.close();
  }
}
