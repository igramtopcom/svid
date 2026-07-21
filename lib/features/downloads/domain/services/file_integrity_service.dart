import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../../../../core/binaries/binary_manager.dart';
import '../../../../core/binaries/binary_type.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/file_utils.dart';

/// Result of a file integrity check.
///
/// [isFatal] separates "this download is broken, mark it failed" from
/// "FFprobe complained but the file is probably fine". The orchestrator
/// (`StartDownloadUseCase`) treats fatal results as a download failure
/// and downgrades non-fatal results to a log line so a transient
/// FFprobe quirk does not silently sink a working file.
class FileIntegrityResult {
  final bool isValid;
  final bool isFatal;
  final String? reason; // null when valid

  const FileIntegrityResult.ok()
    : isValid = true,
      isFatal = false,
      reason = null;

  /// Non-fatal failure — log and continue. Used for ambiguous signals
  /// like "FFprobe exited non-zero" where the binary may be missing
  /// stream metadata but the user-facing file is likely intact.
  const FileIntegrityResult.failed(this.reason)
    : isValid = false,
      isFatal = false;

  /// Fatal failure — orchestrator must mark the download as failed
  /// and surface [reason] to the user. Used when the corruption is
  /// visible in the file's structural shape (e.g. video file with
  /// no audio stream — the smoking-gun symptom of a silent merge
  /// failure on Opus-into-MP4).
  const FileIntegrityResult.failedFatal(this.reason)
    : isValid = false,
      isFatal = true;
}

/// Post-download file integrity verification.
///
/// Checks:
/// - File exists and is non-empty (basic)
/// - Video files: quick FFmpeg container probe (first 1 s)
/// - Audio files: magic-byte header validation
///
/// Always **fails open** — if FFmpeg is unavailable or a check errors/times
/// out, the result is [FileIntegrityResult.ok()] so downloads are never
/// silently blocked by a monitoring bug.
class FileIntegrityService {
  final Future<String?> Function(BinaryType) _getBinaryPath;

  static const _ffmpegTimeout = Duration(seconds: 10);

  FileIntegrityService(BinaryManager binaryManager)
    : _getBinaryPath = binaryManager.getBinaryPath;

  /// Test constructor: inject a custom binary-path resolver.
  @visibleForTesting
  FileIntegrityService.forTest(this._getBinaryPath);

  /// Verify [filePath] after a completed download.
  ///
  /// Returns [FileIntegrityResult.ok()] if the file passes all checks.
  /// Returns [FileIntegrityResult.failed] with a human-readable [reason]
  /// if a definitive corruption is detected.
  Future<FileIntegrityResult> verifyFile(
    String filePath, {
    bool requireAudioStream = true,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return const FileIntegrityResult.failed('File does not exist');
    }
    final size = await file.length();
    if (size == 0) {
      return const FileIntegrityResult.failed('File is empty (0 bytes)');
    }

    if (FileUtils.isVideoFile(path.basename(filePath))) {
      return _verifyVideoContainer(
        filePath,
        requireAudioStream: requireAudioStream,
        fileSize: size,
      );
    } else if (FileUtils.isAudioFile(path.basename(filePath))) {
      return _verifyAudioMagicBytes(filePath);
    }
    // Subtitle, image, etc. — size check is sufficient
    return const FileIntegrityResult.ok();
  }

  // ---------------------------------------------------------------------------
  // Video
  // ---------------------------------------------------------------------------

  /// Runs `ffprobe` to verify the video container parses AND that the
  /// downloaded file actually contains both a video stream and an audio
  /// stream.
  ///
  /// The audio-stream check exists because yt-dlp's merge step can
  /// silently produce a video-only file when the requested container
  /// cannot hold the audio codec it picked (the canonical case is
  /// YouTube ≥1440p where the only audio is Opus, MP4 has no native
  /// Opus support, and ffmpeg either re-encodes or drops the audio
  /// track depending on the call). Catching that here turns a "user
  /// thinks it downloaded fine, opens the file, no sound" surprise
  /// into a normal download-failed error with an actionable message.
  ///
  /// Fails open on environmental issues (ffmpeg/ffprobe absent, JSON
  /// unparseable, timeout) — better to accept a possibly-fine file
  /// than to block downloads on a monitoring bug.
  Future<FileIntegrityResult> _verifyVideoContainer(
    String filePath, {
    required bool requireAudioStream,
    required int fileSize,
  }) async {
    // Derive ffprobe path from ffmpeg path (same directory)
    final ffmpegPath = await _getBinaryPath(BinaryType.ffmpeg);
    if (ffmpegPath == null) {
      appLogger.debug(
        '[FileIntegrity] FFmpeg not available — skipping container check',
      );
      return const FileIntegrityResult.ok();
    }
    final ffprobePath = ffmpegPath.replaceAll(
      RegExp(r'ffmpeg(\.exe)?$'),
      ffmpegPath.endsWith('.exe') ? 'ffprobe.exe' : 'ffprobe',
    );
    if (!await File(ffprobePath).exists()) {
      appLogger.debug(
        '[FileIntegrity] FFprobe not found — skipping container check',
      );
      return const FileIntegrityResult.ok();
    }

    try {
      final result = await Process.run(ffprobePath, [
        '-v',
        'fatal',
        '-show_entries',
        'format=format_name,duration:stream=codec_type,codec_name',
        '-of',
        'json',
        filePath,
      ], runInShell: false).timeout(_ffmpegTimeout);

      if (result.exitCode != 0) {
        appLogger.warning(
          '[FileIntegrity] FFprobe container check failed (exit ${result.exitCode}): '
          '${(result.stderr as String).trim()}',
        );
        return const FileIntegrityResult.failed(
          'Video container appears corrupt (FFprobe failed)',
        );
      }

      // Stream presence check: a downloaded "video" file with zero audio
      // streams is the smoking-gun symptom of the merge-fail-on-Opus
      // case. Surface it as a download failure instead of silently
      // handing the user a muted file.
      final stdoutStr = (result.stdout as String).trim();
      if (stdoutStr.isEmpty) {
        appLogger.debug(
          '[FileIntegrity] FFprobe produced no JSON for $filePath — '
          'assuming valid (fail open)',
        );
        return const FileIntegrityResult.ok();
      }
      return _parseStreamsAndValidate(
        stdoutStr,
        filePath,
        requireAudioStream: requireAudioStream,
        fileSize: fileSize,
      );
    } on TimeoutException {
      appLogger.debug(
        '[FileIntegrity] FFprobe container check timed out — assuming valid',
      );
      return const FileIntegrityResult.ok();
    } catch (e) {
      appLogger.debug(
        '[FileIntegrity] FFprobe container check error: $e — assuming valid',
      );
      return const FileIntegrityResult.ok();
    }
  }

  /// Parses ffprobe's `-show_entries stream=codec_type,...` JSON output
  /// and FAILs the integrity check when a video file has no audio
  /// stream. Visible to tests so the parser can be exercised without
  /// spawning ffprobe.
  @visibleForTesting
  FileIntegrityResult parseStreamsAndValidateForTest(
    String ffprobeJson,
    String filePath, {
    bool requireAudioStream = true,
    int fileSize = 1 << 30,
  }) => _parseStreamsAndValidate(
    ffprobeJson,
    filePath,
    requireAudioStream: requireAudioStream,
    fileSize: fileSize,
  );

  /// DL-011: a real video download is never shorter than this. A
  /// sub-half-second "video" is a truncated/partial file — e.g. a
  /// 403-killed DASH fragment that carried a stray keyframe. A MEASURED
  /// duration below this is a FATAL truncation (distinct from an
  /// unmeasurable probe, which fails open).
  static const _minPlausibleDurationSeconds = 0.5;

  /// DL-011: when duration is UNMEASURABLE, a video file this small is a
  /// truncated stub — the "completed but plays empty, few-dozen KB"
  /// defect. Above this floor we fail open so an exotic-but-valid small
  /// clip is never sunk.
  static const _minPlausibleVideoBytes = 50 * 1024;

  FileIntegrityResult _parseStreamsAndValidate(
    String ffprobeJson,
    String filePath, {
    required bool requireAudioStream,
    required int fileSize,
  }) {
    Map<String, dynamic> root;
    try {
      root = jsonDecode(ffprobeJson) as Map<String, dynamic>;
    } catch (e) {
      appLogger.debug(
        '[FileIntegrity] FFprobe JSON parse failed: $e — assuming valid',
      );
      return const FileIntegrityResult.ok();
    }

    final streams = root['streams'];
    if (streams is! List || streams.isEmpty) {
      // No streams reported — could be a parser variant that omits the
      // streams key. Don't second-guess — fail open.
      return const FileIntegrityResult.ok();
    }

    var videoCount = 0;
    var audioCount = 0;
    for (final s in streams) {
      if (s is! Map) continue;
      final type = s['codec_type'];
      if (type == 'video') videoCount++;
      if (type == 'audio') audioCount++;
    }

    if (videoCount == 0) {
      appLogger.warning('[FileIntegrity] No video stream found in $filePath');
      return const FileIntegrityResult.failedFatal(
        'Downloaded video file has no video stream',
      );
    }

    // DL-011: duration / min-size floor — close the truncated-but-has-
    // video slip-through. A 403-killed partial can carry one keyframe
    // (videoCount>0) yet be a few-dozen-KB "video" that plays nothing —
    // the user-reported "success but empty". ffprobe already returned
    // format.duration above; use it. Fail CLOSED on a measured
    // implausibly-short duration; when duration is UNMEASURABLE, fall
    // back to an absolute byte floor (and fail open above it).
    final duration = _parseFormatDuration(root['format']);
    if (duration != null && duration < _minPlausibleDurationSeconds) {
      appLogger.warning(
        '[FileIntegrity] Video duration ${duration}s below floor — '
        'truncated/incomplete: $filePath',
      );
      return const FileIntegrityResult.failedFatal(
        'Downloaded video is incomplete (truncated — playable length too '
        'short). The source may have been rate-limited mid-download; retry.',
      );
    }
    if (duration == null && fileSize < _minPlausibleVideoBytes) {
      appLogger.warning(
        '[FileIntegrity] Unmeasurable duration + ${fileSize}B below floor — '
        'truncated/incomplete: $filePath',
      );
      return const FileIntegrityResult.failedFatal(
        'Downloaded video is incomplete (truncated — file too small to be a '
        'real video). The source may have been rate-limited mid-download; retry.',
      );
    }

    if (audioCount == 0 && requireAudioStream) {
      appLogger.warning(
        '[FileIntegrity] No audio stream found in $filePath — likely a '
        'container/codec mismatch (e.g. Opus written into MP4 then '
        'dropped during merge).',
      );
      return const FileIntegrityResult.failedFatal(
        'Downloaded video has no audio. This usually happens when the '
        'requested container cannot hold the source audio codec — try '
        'switching to MKV in settings, or pick a 1080p quality.',
      );
    }

    return const FileIntegrityResult.ok();
  }

  /// DL-011: parse ffprobe `format.duration` (a string like "12.345" or
  /// "N/A") to seconds. Returns null when absent/unparseable so the caller
  /// treats it as unmeasurable (the byte-floor / fail-open path).
  static double? _parseFormatDuration(dynamic format) {
    if (format is! Map) return null;
    final raw = format['duration'];
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty || s == 'N/A') return null;
    return double.tryParse(s);
  }

  // ---------------------------------------------------------------------------
  // Audio magic bytes
  // ---------------------------------------------------------------------------

  static const _headerBytes = 16;

  /// Magic-byte signatures keyed by extension.
  ///
  /// Each entry is a list of accepted patterns (first-N-bytes prefix).
  static const Map<String, List<List<int>>> _audioMagic = {
    '.mp3': [
      [0x49, 0x44, 0x33], // ID3 tag (most MP3s)
      [0xFF, 0xFB], // MPEG-1 Layer 3, no padding
      [0xFF, 0xF3], // MPEG-1 Layer 3
      [0xFF, 0xF2], // MPEG-2 Layer 3
      [0xFF, 0xFA], // MPEG-1 Layer 3, padding
    ],
    '.wav': [
      [0x52, 0x49, 0x46, 0x46], // RIFF
    ],
    '.flac': [
      [0x66, 0x4C, 0x61, 0x43], // fLaC
    ],
    '.ogg': [
      [0x4F, 0x67, 0x67, 0x53], // OggS
    ],
    '.m4a': [
      // ftyp box is at offset 4 in ISO BMFF containers
    ],
    '.aac': [
      [0xFF, 0xF1], // ADTS AAC-LC
      [0xFF, 0xF9], // ADTS AAC-LC (mpeg4)
      [0xFF, 0xF0], // ADTS AAC
      [0xFF, 0xF8],
    ],
    '.wma': [
      [0x30, 0x26, 0xB2, 0x75], // ASF/WMA GUID
    ],
  };

  Future<FileIntegrityResult> _verifyAudioMagicBytes(String filePath) async {
    try {
      final file = File(filePath);
      final raf = await file.open(mode: FileMode.read);
      Uint8List header;
      try {
        header = await raf.read(_headerBytes);
      } finally {
        await raf.close();
      }

      if (header.isEmpty) {
        return const FileIntegrityResult.failed(
          'Audio file header is unreadable',
        );
      }

      final ext = path.extension(filePath).toLowerCase();

      // M4A: ftyp box at offset 4 (bytes 4-7 = 0x66 0x74 0x79 0x70)
      if (ext == '.m4a') {
        if (header.length >= 8 &&
            header[4] == 0x66 &&
            header[5] == 0x74 &&
            header[6] == 0x79 &&
            header[7] == 0x70) {
          return const FileIntegrityResult.ok();
        }
        appLogger.warning('[FileIntegrity] .m4a missing ftyp atom at offset 4');
        return const FileIntegrityResult.failed(
          'Audio file header invalid (not a valid M4A)',
        );
      }

      final patterns = _audioMagic[ext];
      if (patterns == null || patterns.isEmpty) {
        // Unknown extension — skip magic check
        return const FileIntegrityResult.ok();
      }

      for (final pattern in patterns) {
        if (_startsWith(header, pattern)) {
          return const FileIntegrityResult.ok();
        }
      }

      appLogger.warning(
        '[FileIntegrity] Audio magic bytes mismatch for $ext: '
        '${header.take(8).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
      );
      return FileIntegrityResult.failed(
        'Audio file header invalid (not a valid $ext file)',
      );
    } catch (e) {
      appLogger.debug(
        '[FileIntegrity] Audio magic check error: $e — assuming valid',
      );
      return const FileIntegrityResult.ok(); // Fail open
    }
  }

  static bool _startsWith(Uint8List bytes, List<int> pattern) {
    if (bytes.length < pattern.length) return false;
    for (var i = 0; i < pattern.length; i++) {
      if (bytes[i] != pattern[i]) return false;
    }
    return true;
  }
}
