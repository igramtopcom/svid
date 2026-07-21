import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../../../../core/binaries/binary_manager.dart';
import '../../../../core/binaries/binary_type.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/file_utils.dart';
import '../../../../core/utils/process_helper.dart';

// ==================== Models ====================

/// Single item extracted from gallery-dl --dump-json output
class GalleryDlItem {
  final int index; // 1-based position
  final String url; // Direct download URL
  final String? filename;
  final String extension; // "jpg", "png", "mp4"
  final int? filesize;
  final int? width;
  final int? height;
  final String? description;

  const GalleryDlItem({
    required this.index,
    required this.url,
    this.filename,
    required this.extension,
    this.filesize,
    this.width,
    this.height,
    this.description,
  });

  bool get isImage {
    const imageExts = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'tiff', 'avif', 'heic'};
    return imageExts.contains(extension.toLowerCase());
  }

  bool get isVideo {
    const videoExts = {'mp4', 'webm', 'mkv', 'mov', 'avi'};
    return videoExts.contains(extension.toLowerCase());
  }
}

/// Complete extraction result from gallery-dl
class GalleryDlInfo {
  final String url; // Original URL
  final String? title; // Post title or caption
  final String? uploader; // Username
  final String platform; // "instagram", "tiktok", etc.
  final String? thumbnail; // First image URL as thumbnail
  final List<GalleryDlItem> items;

  const GalleryDlInfo({
    required this.url,
    this.title,
    this.uploader,
    required this.platform,
    this.thumbnail,
    required this.items,
  });

  int get imageCount => items.where((i) => i.isImage).length;
  int get videoCount => items.where((i) => i.isVideo).length;
  bool get hasImages => items.any((i) => i.isImage);
  bool get isCarousel => items.length > 1;
}

// ==================== Progress Events ====================

/// Progress events for gallery-dl downloads (mirrors YtDlpProgressEvent pattern)
sealed class GalleryDlProgressEvent {
  const GalleryDlProgressEvent();

  factory GalleryDlProgressEvent.progress({
    required double percent,
    String? currentFile,
  }) = GalleryDlProgressUpdate;

  factory GalleryDlProgressEvent.completed({
    required List<String> outputPaths,
  }) = GalleryDlDownloadComplete;

  factory GalleryDlProgressEvent.error({
    required String message,
  }) = GalleryDlDownloadError;

  factory GalleryDlProgressEvent.cancelled() = GalleryDlDownloadCancelled;
}

class GalleryDlProgressUpdate extends GalleryDlProgressEvent {
  final double percent;
  final String? currentFile;

  const GalleryDlProgressUpdate({
    required this.percent,
    this.currentFile,
  });
}

class GalleryDlDownloadComplete extends GalleryDlProgressEvent {
  final List<String> outputPaths;

  const GalleryDlDownloadComplete({required this.outputPaths});
}

class GalleryDlDownloadError extends GalleryDlProgressEvent {
  final String message;

  const GalleryDlDownloadError({required this.message});
}

class GalleryDlDownloadCancelled extends GalleryDlProgressEvent {
  const GalleryDlDownloadCancelled();
}

// ==================== Exception ====================

class GalleryDlException implements Exception {
  final String message;
  final GalleryDlErrorType type;

  const GalleryDlException(this.type, this.message);

  @override
  String toString() => 'GalleryDlException($type): $message';
}

enum GalleryDlErrorType {
  binaryNotFound,
  unsupportedUrl,
  loginRequired,
  networkError,
  rateLimited,
  noResults,
  timeout,
  unknown,
}

// ==================== DataSource ====================

/// Data source for gallery-dl image extraction and download.
/// Follows the same pattern as YtDlpDataSource.
///
/// When Python 3.10+ is available, uses `python3 -m gallery_dl` (pip package)
/// instead of the PyInstaller binary. This avoids macOS XProtect scanning
/// the PyInstaller-extracted Python runtime (~7s delay → ~1s).
class GalleryDlDataSource {
  final BinaryManager _binaryManager;
  String? _binaryPath;
  bool _initialized = false;
  final Map<String, Process> _activeProcesses = {};

  /// If non-null, gallery-dl runs via Python: `_pythonPath -m gallery_dl`
  /// This is 6x faster than the PyInstaller binary on macOS.
  String? _pythonPath;
  String? _pipPkgDir;
  bool _usePythonMode = false;

  GalleryDlDataSource(this._binaryManager);

  /// Initialize — prefer Python pip mode over PyInstaller binary.
  Future<void> initialize() async {
    if (_initialized && (_binaryPath != null || _usePythonMode)) return;

    _binaryPath = await _binaryManager.getBinaryPath(BinaryType.galleryDl);

    // Try Python mode: pip-installed gallery-dl runs 6x faster (no XProtect)
    if (Platform.isMacOS && BinaryManager.pythonPath != null) {
      _pythonPath = BinaryManager.pythonPath;
      final appSupport = _binaryManager.binDir;
      _pipPkgDir = path.join(appSupport, 'gallery-dl-pkg');
      await _ensurePipGalleryDl();
    }

    _initialized = true;
    if (_usePythonMode) {
      appLogger.debug('✅ [gallery-dl] Using Python mode: $_pythonPath -m gallery_dl');
    } else if (_binaryPath != null) {
      appLogger.debug('✅ [gallery-dl] Binary found: $_binaryPath');
    }
  }

  /// Install gallery-dl via pip to app-local directory (if not already installed).
  Future<void> _ensurePipGalleryDl() async {
    if (_pythonPath == null || _pipPkgDir == null) return;

    final markerFile = File(path.join(_pipPkgDir!, 'gallery_dl', '__main__.py'));
    if (await markerFile.exists()) {
      _usePythonMode = true;
      return;
    }

    // Install gallery-dl to app-local directory
    try {
      appLogger.info('[gallery-dl] Installing pip package to $_pipPkgDir');
      final result = await ProcessHelper.run(
        _pythonPath!,
        ['-m', 'pip', 'install', 'gallery-dl', '--target', _pipPkgDir!, '--quiet'],
      ).timeout(const Duration(seconds: 60));

      if (result.exitCode == 0 && await markerFile.exists()) {
        _usePythonMode = true;
        appLogger.info('✅ [gallery-dl] pip package installed');
      } else {
        appLogger.warning('[gallery-dl] pip install failed: ${result.stderr}');
      }
    } catch (e) {
      appLogger.warning('[gallery-dl] pip install error: $e');
    }
  }

  /// Build executable + args for running gallery-dl.
  /// Returns (executable, prefixArgs) — caller appends command-specific args.
  (String, List<String>) _buildCommand() {
    if (_usePythonMode && _pythonPath != null) {
      return (_pythonPath!, ['-m', 'gallery_dl']);
    }
    return (_binaryPath!, []);
  }

  /// Build environment vars (PYTHONPATH for pip mode, ffmpeg PATH, encoding).
  Map<String, String>? _buildEnvironment({String? ffmpegPath}) {
    final env = <String, String>{};

    // Force Python to use UTF-8 for all I/O on Windows.
    // Without this, Python outputs using system codepage (cp1252/Windows-1252),
    // corrupting non-ASCII filenames and JSON output.
    if (Platform.isWindows) {
      env['PYTHONUTF8'] = '1';
      env['PYTHONIOENCODING'] = 'utf-8';
    }

    if (_usePythonMode && _pipPkgDir != null) {
      env['PYTHONPATH'] = _pipPkgDir!;
    }

    if (ffmpegPath != null) {
      final ffmpegDir = path.dirname(ffmpegPath);
      final currentPath = Platform.environment['PATH'] ?? '';
      final sep = Platform.isWindows ? ';' : ':';
      env['PATH'] = '$ffmpegDir$sep$currentPath';
    }

    return env.isEmpty ? null : env;
  }

  /// Check if gallery-dl is available (either Python mode or binary)
  Future<bool> isAvailable() async {
    await initialize();
    return _usePythonMode || _binaryPath != null;
  }

  /// Get gallery-dl version
  Future<String?> get version async {
    await initialize();
    if (_binaryPath == null) return null;
    return _binaryManager.getVersion(BinaryType.galleryDl);
  }

  // ==================== Extraction ====================

  /// Extract metadata from URL using gallery-dl --dump-json
  /// Returns [GalleryDlInfo] with extracted items.
  /// Throws [GalleryDlException] on failure.
  ///
  /// [_redirectDepth] is internal — prevents infinite redirect loops
  /// (e.g., pin.it → pinterest.com/pin/... via type-6 Queue entries).
  Future<GalleryDlInfo> extractInfo(
    String url, {
    String? cookiesFile,
  }) =>
      _extractInfoImpl(url, cookiesFile: cookiesFile, redirectDepth: 0);

  Future<GalleryDlInfo> _extractInfoImpl(
    String url, {
    String? cookiesFile,
    int redirectDepth = 0,
  }) async {
    await initialize();
    if (!_usePythonMode && _binaryPath == null) {
      throw const GalleryDlException(
        GalleryDlErrorType.binaryNotFound,
        'gallery-dl binary not found',
      );
    }

    final (executable, prefixArgs) = _buildCommand();
    final args = <String>[
      ...prefixArgs,
      '--dump-json',
      '--no-download',
    ];

    // Add cookies if available (Netscape format, same as yt-dlp)
    if (cookiesFile != null) {
      args.addAll(['--cookies', cookiesFile]);
    }

    args.add(url);

    appLogger.info('🔍 [gallery-dl] Extracting: $url${_usePythonMode ? ' (python mode)' : ''}');
    appLogger.debug('[gallery-dl] Command: $executable ${args.join(' ')}');

    try {
      // P0 (2026-05-25 Windows audio recode sibling fix): gallery-dl
      // executable resolves under `%APPDATA%\Bui Xuan Mai\
      // <ProductName>\bin\gallery-dl.exe` — same path-with-spaces
      // class as the ffmpeg P0. Switch to `runDirect` so the
      // executable path is passed verbatim. The URL arg (added at
      // line ~302 above) is a single list element passed directly
      // to CreateProcessW (no cmd.exe parsing) so `&` in URL query
      // params is NOT split — bypassing the shell removes the need
      // for the `_escapeCmdMeta` workaround that `run` applies.
      final result = await ProcessHelper.runDirect(
        executable,
        args,
        environment: _buildEnvironment(),
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 60));

      if (result.exitCode != 0) {
        final stderr = result.stderr.toString().trim();
        appLogger.error('[gallery-dl] Exit code: ${result.exitCode}, stderr: $stderr');
        throw _parseError(stderr, result.exitCode);
      }

      final stdout = result.stdout.toString().trim();
      if (stdout.isEmpty) {
        throw const GalleryDlException(
          GalleryDlErrorType.noResults,
          'No content found at this URL',
        );
      }

      return _parseExtractOutput(url, stdout);
    } on _QueueRedirectException catch (e) {
      // Type-6 Queue redirect (e.g., pin.it short URL → full pinterest.com URL)
      if (redirectDepth >= 2) {
        throw const GalleryDlException(
          GalleryDlErrorType.noResults,
          'Too many redirects — could not resolve content URL',
        );
      }
      appLogger.info('🔄 [gallery-dl] Following queue redirect → ${e.resolvedUrl}');
      return _extractInfoImpl(e.resolvedUrl, cookiesFile: cookiesFile, redirectDepth: redirectDepth + 1);
    } on TimeoutException {
      throw const GalleryDlException(
        GalleryDlErrorType.timeout,
        'Extraction timed out (60s)',
      );
    } on GalleryDlException {
      rethrow;
    } catch (e) {
      throw GalleryDlException(
        GalleryDlErrorType.unknown,
        'Extraction failed: $e',
      );
    }
  }

  /// Parse gallery-dl --dump-json output.
  ///
  /// gallery-dl outputs a JSON array of tuples:
  /// - [2, {metadata}]         → Directory/post-level metadata
  /// - [3, "url", {metadata}]  → File URL with per-file metadata
  /// - [6, "url", {metadata}]  → Queue (external URL, ignored)
  GalleryDlInfo _parseExtractOutput(String originalUrl, String stdout) {
    dynamic parsed;
    try {
      parsed = jsonDecode(stdout);
    } catch (e) {
      appLogger.error('[gallery-dl] Failed to parse JSON: $e');
      throw GalleryDlException(
        GalleryDlErrorType.unknown,
        'Failed to parse gallery-dl output: $e',
      );
    }

    if (parsed is! List) {
      throw const GalleryDlException(
        GalleryDlErrorType.noResults,
        'Unexpected output format from gallery-dl',
      );
    }

    String? platform;
    String? uploader;
    String? title;
    String? thumbnail;
    final items = <GalleryDlItem>[];
    final queueUrls = <String>[];
    int itemIndex = 0;

    for (final entry in parsed) {
      if (entry is! List || entry.isEmpty) continue;

      final messageType = entry[0];

      if (messageType == 6 && entry.length >= 2) {
        // Queue message: [6, "url", {metadata}] — redirect to resolved URL
        final queueUrl = entry[1]?.toString();
        if (queueUrl != null && queueUrl.isNotEmpty) {
          queueUrls.add(queueUrl);
        }
      } else if (messageType == 2 && entry.length >= 2) {
        // Directory message: [2, {metadata}]
        final meta = entry[1];
        if (meta is Map<String, dynamic>) {
          platform ??= meta['category']?.toString();
          uploader ??= meta['username']?.toString() ??
              meta['uploader']?.toString() ??
              meta['owner']?.toString() ??
              meta['fullname']?.toString();
          // Check nested user objects (TikTok, Instagram)
          if (uploader == null && meta['user'] is Map) {
            final user = meta['user'] as Map;
            uploader = user['name']?.toString() ??
                user['nickname']?.toString() ??
                user['username']?.toString();
          }
          title ??= meta['description']?.toString() ??
              meta['title']?.toString() ??
              meta['content']?.toString();
          // Truncate long captions for title
          if (title != null && title.length > 200) {
            title = '${title.substring(0, 197)}...';
          }
          // Extract thumbnail from post-level metadata (Instagram display_url, etc.)
          thumbnail ??= meta['display_url']?.toString() ??
              meta['thumbnail_url']?.toString() ??
              meta['thumbnail_src']?.toString() ??
              meta['thumbnail']?.toString();
        }
      } else if (messageType == 3 && entry.length >= 3) {
        // URL message: [3, "url", {metadata}]
        final fileUrl = entry[1]?.toString();
        final meta = entry[2];

        if (fileUrl == null || fileUrl.isEmpty) continue;
        if (meta is! Map<String, dynamic>) continue;

        itemIndex++;

        final ext = meta['extension']?.toString() ?? _guessExtension(fileUrl);
        final filename = meta['filename']?.toString();
        final width = _parseInt(meta['width']);
        final height = _parseInt(meta['height']);
        final filesize = _parseInt(meta['filesize']) ?? _parseInt(meta['content_length']);

        // Extract platform/uploader from file-level metadata too
        platform ??= meta['category']?.toString();
        uploader ??= meta['username']?.toString() ?? meta['uploader']?.toString();

        // Use first image URL as thumbnail
        const imageExts = {'jpg', 'jpeg', 'png', 'webp', 'gif'};
        if (thumbnail == null && imageExts.contains(ext.toLowerCase())) {
          thumbnail = fileUrl;
        }
        // For video items, try metadata thumbnail fields (Instagram display_url, etc.)
        thumbnail ??= meta['display_url']?.toString() ??
            meta['thumbnail_url']?.toString() ??
            meta['thumbnail_src']?.toString() ??
            meta['thumbnail']?.toString();

        items.add(GalleryDlItem(
          index: itemIndex,
          url: fileUrl,
          filename: filename,
          extension: ext,
          filesize: filesize,
          width: width,
          height: height,
          description: meta['description']?.toString() ?? meta['content']?.toString(),
        ));
      }
      // Type 6 (Queue) is ignored — external URLs for other extractors
    }

    if (items.isEmpty) {
      // Check for queue redirect (type 6) — e.g., pin.it short URL → full pinterest.com URL
      if (queueUrls.isNotEmpty) {
        throw _QueueRedirectException(queueUrls.first);
      }

      // Check for error entries (type -1) that indicate login requirement
      for (final entry in parsed) {
        if (entry is! List || entry.length < 2) continue;
        if (entry[0] == -1 && entry[1] is Map) {
          final msg = (entry[1]['message'] ?? '').toString().toLowerCase();
          if (msg.contains('login') || msg.contains('authentication') || msg.contains('401')) {
            throw GalleryDlException(
              GalleryDlErrorType.loginRequired,
              'Login required: ${entry[1]['message']}',
            );
          }
        }
      }
      throw const GalleryDlException(
        GalleryDlErrorType.noResults,
        'No downloadable content found',
      );
    }

    // Generate title from uploader if no description
    title ??= uploader != null ? 'Post by $uploader' : 'Image';

    appLogger.info(
      '✅ [gallery-dl] Extracted ${items.length} items from ${platform ?? 'unknown'}'
      ' (${items.where((i) => i.isImage).length} images, ${items.where((i) => i.isVideo).length} videos)',
    );

    return GalleryDlInfo(
      url: originalUrl,
      title: title,
      uploader: uploader,
      platform: platform ?? 'unknown',
      thumbnail: thumbnail,
      items: items,
    );
  }

  // ==================== Download ====================

  /// Download images using gallery-dl subprocess.
  ///
  /// [range] — 1-based item index (e.g., "1"), or null to download all.
  /// [outputFilename] — Custom filename template (without extension).
  ///
  /// gallery-dl prints file paths to stdout as downloads complete.
  /// Lines starting with `#` are URLs; other lines are saved file paths.
  Stream<GalleryDlProgressEvent> downloadWithProgress({
    required String url,
    required String outputDir,
    String? outputFilename,
    String? range,
    String? cookiesFile,
    int? expectedItemCount,
    bool imageOnly = false,
    bool videoOnly = false,
    String? ffmpegPath,
  }) async* {
    await initialize();
    if (!_usePythonMode && _binaryPath == null) {
      yield GalleryDlProgressEvent.error(
        message: 'gallery-dl binary not found',
      );
      return;
    }

    final (executable, prefixArgs) = _buildCommand();
    final args = <String>[
      ...prefixArgs,
      // Output directory
      '-d', outputDir,
    ];

    // Custom filename template
    if (outputFilename != null) {
      final sanitized = FileUtils.sanitizeFilename(outputFilename);
      if (range == null && expectedItemCount != null && expectedItemCount > 1) {
        // Multiple items — numbered filenames to avoid collision
        args.addAll(['--filename', '${sanitized}_{num}.{extension}']);
      } else {
        // Single item
        args.addAll(['--filename', '$sanitized.{extension}']);
      }
    }

    // Range filter for selecting specific item(s)
    if (range != null) {
      args.addAll(['--range', range]);
    }

    // Cookies for authentication
    if (cookiesFile != null) {
      args.addAll(['--cookies', cookiesFile]);
    }

    // Filter to images only (skip audio/video tracks from posts)
    if (imageOnly) {
      args.addAll([
        '--filter',
        "extension in ('jpg','jpeg','png','webp','gif','bmp','tiff','avif','heic')",
      ]);
    }

    // Filter to videos only (skip images from carousel posts)
    if (videoOnly) {
      args.addAll([
        '--filter',
        "extension in ('mp4','webm','mkv','mov','avi')",
      ]);
    }

    // Disable subdirectory creation (download directly to outputDir)
    args.addAll(['--directory', '']);

    args.add(url);

    appLogger.info('📥 [gallery-dl] Downloading: $url (range: ${range ?? 'all'})${_usePythonMode ? ' (python mode)' : ''}');
    appLogger.debug('[gallery-dl] Command: $executable ${args.join(' ')}');

    Process process;
    try {
      process = await ProcessHelper.start(executable, args, environment: _buildEnvironment(ffmpegPath: ffmpegPath));
      // Unique key: same URL can have multiple concurrent downloads (different ranges/filenames)
      final processKey = '$url\x00${outputFilename ?? ''}\x00${range ?? ''}';
      _activeProcesses[processKey] = process;
    } catch (e) {
      yield GalleryDlProgressEvent.error(message: 'Failed to start gallery-dl: $e');
      return;
    }

    final outputPaths = <String>[];
    String? lastError;

    // Parse stdout for file paths
    final stdoutCompleter = Completer<void>();
    final stderrBuffer = StringBuffer();

    final stdoutSub = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(
      (line) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) return;

        // Lines starting with # are URL comments — skip
        if (trimmed.startsWith('#')) return;

        // Check if the line is a file path that exists
        final file = File(trimmed);
        if (file.existsSync()) {
          outputPaths.add(trimmed);
          appLogger.debug('[gallery-dl] Downloaded: ${path.basename(trimmed)}');
        } else {
          // Some gallery-dl output lines are status messages
          appLogger.debug('[gallery-dl] stdout: $trimmed');
        }
      },
      onDone: () => stdoutCompleter.complete(),
      onError: (e) => stdoutCompleter.complete(),
    );

    // Capture stderr for error messages
    final stderrSub = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(
      (line) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) return;
        stderrBuffer.writeln(trimmed);
        appLogger.debug('[gallery-dl] stderr: $trimmed');

        // Detect specific errors
        if (trimmed.contains('Login required') || trimmed.contains('login')) {
          lastError = 'Login required — add cookies for this platform';
        } else if (trimmed.contains('404') || trimmed.contains('Not Found')) {
          lastError = 'Content not found (404)';
        } else if (trimmed.contains('429') || trimmed.contains('Rate Limit')) {
          lastError = 'Rate limited — try again later';
        }
      },
    );

    // Wait for process to complete
    final exitCode = await process.exitCode;
    await stdoutCompleter.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    );
    await stdoutSub.cancel();
    await stderrSub.cancel();
    _activeProcesses.remove('$url\x00${outputFilename ?? ''}\x00${range ?? ''}');

    final stderr = stderrBuffer.toString().trim();

    if (exitCode != 0 && outputPaths.isEmpty) {
      final errorMsg = lastError ?? _extractErrorMessage(stderr) ?? 'Download failed (exit code: $exitCode)';
      appLogger.error('[gallery-dl] Download failed: $errorMsg');
      yield GalleryDlProgressEvent.error(message: errorMsg);
      return;
    }

    if (outputPaths.isEmpty) {
      yield GalleryDlProgressEvent.error(
        message: 'No files were downloaded',
      );
      return;
    }

    appLogger.info('✅ [gallery-dl] Downloaded ${outputPaths.length} files');
    yield GalleryDlProgressEvent.completed(outputPaths: outputPaths);
  }

  /// Cancel active download by URL. If [url] is null, cancels all.
  /// Cancels ALL processes matching this URL (handles composite keys).
  Future<void> cancelDownload([String? url]) async {
    if (url != null) {
      // Find all process keys that match this URL
      final matchingKeys = _activeProcesses.keys
          .where((key) => key.startsWith('$url\x00') || key == url)
          .toList();
      for (final key in matchingKeys) {
        await _killProcess(key);
      }
    } else {
      // Cancel all active gallery-dl processes
      for (final key in _activeProcesses.keys.toList()) {
        await _killProcess(key);
      }
    }
  }

  Future<void> _killProcess(String processKey) async {
    final process = _activeProcesses.remove(processKey);
    if (process == null) return;

    appLogger.info('🛑 [gallery-dl] Cancelling download: $processKey');
    try {
      process.kill(ProcessSignal.sigterm);
      // Wait up to 5s for graceful exit, then force-kill on Unix
      await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          if (!Platform.isWindows) {
            try {
              process.kill(ProcessSignal.sigkill);
            } catch (_) {}
          }
          return -1;
        },
      );
    } catch (e) {
      appLogger.debug('gallery-dl process already terminated: $e');
    }
  }

  // ==================== Helpers ====================

  /// Parse gallery-dl error from stderr
  GalleryDlException _parseError(String stderr, int exitCode) {
    final lower = stderr.toLowerCase();

    if (lower.contains('no suitable extractor') ||
        lower.contains('unsupported url') ||
        lower.contains('no results')) {
      return GalleryDlException(
        GalleryDlErrorType.unsupportedUrl,
        'URL not supported by gallery-dl: ${_truncate(stderr, 200)}',
      );
    }

    if (lower.contains('login') || lower.contains('authentication') || lower.contains('401')) {
      return GalleryDlException(
        GalleryDlErrorType.loginRequired,
        'Login required — add cookies for this platform',
      );
    }

    if (lower.contains('429') || lower.contains('rate limit')) {
      return const GalleryDlException(
        GalleryDlErrorType.rateLimited,
        'Rate limited — try again later',
      );
    }

    if (lower.contains('connection') || lower.contains('timeout') || lower.contains('network')) {
      return GalleryDlException(
        GalleryDlErrorType.networkError,
        'Network error: ${_truncate(stderr, 200)}',
      );
    }

    return GalleryDlException(
      GalleryDlErrorType.unknown,
      _truncate(stderr, 300),
    );
  }

  /// Extract meaningful error message from stderr
  String? _extractErrorMessage(String stderr) {
    if (stderr.isEmpty) return null;
    // Take first non-empty line as error message
    final lines = stderr.split('\n').where((l) => l.trim().isNotEmpty);
    if (lines.isEmpty) return null;
    return _truncate(lines.first.trim(), 200);
  }

  /// Guess file extension from URL
  String _guessExtension(String url) {
    try {
      final uri = Uri.parse(url);
      final ext = path.extension(uri.path).toLowerCase().replaceFirst('.', '');
      if (ext.isNotEmpty && ext.length <= 5) return ext;
    } catch (_) {}
    return 'jpg'; // Default to jpg
  }

  /// Parse an int from dynamic value
  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Truncate string to max length
  static String _truncate(String s, int maxLength) {
    if (s.length <= maxLength) return s;
    return '${s.substring(0, maxLength - 3)}...';
  }
}

/// Internal exception for type-6 Queue redirects.
/// gallery-dl returns [6, "url", {metadata}] when a short URL (e.g., pin.it)
/// resolves to a full URL that needs re-extraction.
class _QueueRedirectException implements Exception {
  final String resolvedUrl;
  const _QueueRedirectException(this.resolvedUrl);
}
