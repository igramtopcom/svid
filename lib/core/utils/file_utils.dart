import 'dart:io';
import 'package:path/path.dart' as path;
import '../constants/app_constants.dart';

class FileUtils {
  FileUtils._();

  /// Format bytes to human-readable size (KB, MB, GB, etc.)
  static String formatBytes(int bytes, {int decimals = 2}) {
    if (bytes <= 0) return '0 B';

    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    var size = bytes.toDouble();

    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }

    return '${size.toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  /// Get file extension from filename
  static String getExtension(String filename) {
    return path.extension(filename).toLowerCase();
  }

  /// Get filename without extension
  static String getFilenameWithoutExtension(String filename) {
    return path.basenameWithoutExtension(filename);
  }

  /// Check if file is a video file
  static bool isVideoFile(String filename) {
    final ext = getExtension(filename);
    return AppConstants.supportedVideoExtensions.contains(ext);
  }

  /// Check if file is an audio file
  static bool isAudioFile(String filename) {
    final ext = getExtension(filename);
    return AppConstants.supportedAudioExtensions.contains(ext);
  }

  /// Check if file is an image file
  static bool isImageFile(String filename) {
    final ext = getExtension(filename);
    return AppConstants.supportedImageExtensions.contains(ext);
  }

  /// Check if file is a media file (video, audio, or image)
  static bool isMediaFile(String filename) {
    return isVideoFile(filename) ||
        isAudioFile(filename) ||
        isImageFile(filename);
  }

  /// Sanitize filename to remove invalid characters.
  /// Uses BYTE length (not char length) because macOS/Linux limit is 255 bytes.
  /// Reserves space for yt-dlp temp suffixes like `.f<id>.mp4.part` (~40 bytes)
  /// and duplicate counter suffix ` (999)` (~6 bytes).
  static String sanitizeFilename(String filename) {
    // Strip null bytes (U+0000) — forbidden on all filesystems
    var sanitized = filename.replaceAll('\x00', '');

    // Remove invalid characters for file systems
    const invalidChars = r'<>:"/\|?*';
    for (var char in invalidChars.split('')) {
      sanitized = sanitized.replaceAll(char, '_');
    }

    // Replace newlines and control characters with space
    // (titles with \n break stdout line-based parsing in yt-dlp progress)
    sanitized = sanitized.replaceAll(RegExp(r'[\r\n\t]'), ' ');
    // Collapse multiple spaces
    sanitized = sanitized.replaceAll(RegExp(r' {2,}'), ' ');

    // Trim leading/trailing whitespace
    sanitized = sanitized.trim();

    // Trim trailing dots and spaces — Windows forbids filenames ending with . or space
    sanitized = sanitized.replaceAll(RegExp(r'[. ]+$'), '');

    // Reserve bytes for:
    // - yt-dlp temp suffix: .f<format_id>.<ext>.part  (~40 bytes)
    // - duplicate counter:  " (999)"                  (~6 bytes)
    // - extension:          ".mp4"                     (~5 bytes)
    const reservedBytes = 51;
    final maxBytes =
        AppConstants.maxFileNameLength - reservedBytes; // 204 bytes

    // Truncate by BYTE length (UTF-8), not character length.
    // macOS HFS+/APFS limit = 255 bytes, Linux ext4 = 255 bytes.
    sanitized = _truncateToUtf8Bytes(sanitized, maxBytes);

    // Final fallback: empty result (e.g. whitespace-only or all-invalid input)
    return sanitized.isEmpty ? 'download' : sanitized;
  }

  /// Truncate string to fit within [maxBytes] of UTF-8 encoding.
  /// Cuts at character boundaries (never splits a multi-byte character).
  static String _truncateToUtf8Bytes(String s, int maxBytes) {
    if (s.isEmpty) return s;

    var byteCount = 0;
    var charEnd = 0;

    for (final rune in s.runes) {
      // Calculate UTF-8 byte length for this code point
      int runeBytes;
      if (rune <= 0x7F) {
        runeBytes = 1;
      } else if (rune <= 0x7FF) {
        runeBytes = 2;
      } else if (rune <= 0xFFFF) {
        runeBytes = 3;
      } else {
        runeBytes = 4;
      }

      if (byteCount + runeBytes > maxBytes) break;
      byteCount += runeBytes;
      charEnd += String.fromCharCode(rune).length;
    }

    final result = s.substring(0, charEnd).trimRight();
    return result.isEmpty ? 'download' : result;
  }

  /// Windows MAX_PATH: a full path may not exceed 260 UTF-16 code units
  /// (drive + dirs + filename + the implicit terminating NUL). Dart's
  /// `String.length` counts UTF-16 code units, so it maps 1:1 onto this
  /// limit — a CJK character is 1 unit, an emoji (astral plane) is 2.
  static const int windowsMaxPathUnits = 260;

  /// Units reserved, BEYOND the extension, for the names yt-dlp and the app
  /// derive from the stem while a download is in flight: the per-format DASH/HLS
  /// fragment id + partial suffix (`<stem> (999).f<id>.<ext>.part`). Sized for
  /// the LONGEST format ids seen in production — Facebook DASH numeric ids
  /// (`f1350541610457985a`, ~18 units) and HLS named ids
  /// (`fhls-audio-128000-Audio`, ~24 units) — plus the duplicate counter and
  /// `.part`. A pathological, manifest-defined id beyond this still fails
  /// gracefully: the OS ENAMETOOLONG is classified as `pathNotFound`, never a
  /// silent wrong-path completion. [sanitizeFilename]'s 51-byte component
  /// reserve covers the POSIX per-component cap; this is the full-PATH headroom.
  static const int _pathBudgetReserveUnits = 48;

  /// Bound [fileName] so that, on a path-length-limited platform, BOTH the
  /// final `<saveDir>/<fileName>` path AND the worst-case temp write path
  /// (the file is written to an isolated temp dir first, then moved) fit the
  /// platform limit. Only the stem is truncated — the extension is preserved —
  /// on a UTF-16 code-unit boundary that never splits a surrogate pair, and any
  /// trailing dot/space the cut exposes is stripped (forbidden as a Windows
  /// name ending).
  ///
  /// [candidateDirs] are every directory the file passes through (the user's
  /// save folder + the worst-case temp dir); the longest one drives the budget,
  /// because a shallow save folder still overflows in the deep AppData temp dir.
  ///
  /// [maxPathUnits] is the platform path ceiling in UTF-16 code units, or null
  /// to no-op — POSIX, where the 255-byte per-component cap in
  /// [sanitizeFilename] already bounds the only relevant limit. Pure of
  /// `Platform` so the Windows branch is unit-testable on any host.
  ///
  /// Returns the (possibly unchanged) bounded name, or null when even a
  /// single-character stem cannot fit — [candidateDirs] is itself so deep that
  /// no filename works. The caller must then surface a clear path-too-long
  /// error rather than let it manifest as a late, generic pathNotFound.
  static String? boundFilenameToPathLimit({
    required String fileName,
    required List<String> candidateDirs,
    required int? maxPathUnits,
    int reserveUnits = _pathBudgetReserveUnits,
  }) {
    if (maxPathUnits == null) return fileName; // POSIX: no MAX_PATH constraint
    if (candidateDirs.isEmpty) return fileName;

    final ext = path.extension(fileName); // leading dot included; '' if none
    final stem = fileName.substring(0, fileName.length - ext.length);

    final longestDir = candidateDirs
        .map((d) => d.length)
        .reduce((a, b) => a > b ? a : b);

    // -1 for the path separator between the directory and the filename.
    final available =
        maxPathUnits - longestDir - 1 - reserveUnits - ext.length;
    if (available < 1) return null; // even a 1-char stem cannot fit
    if (stem.length <= available) return fileName; // already within budget

    var cut = available;
    // Never split a surrogate pair: if the last kept unit is a high surrogate
    // whose low half is about to be dropped, drop the high half too.
    if (_isHighSurrogate(stem.codeUnitAt(cut - 1))) cut -= 1;

    var truncatedStem = stem
        .substring(0, cut)
        .replaceAll(RegExp(r'[. ]+$'), ''); // no trailing '.'/' ' on Windows

    if (truncatedStem.isEmpty) {
      const fallback = 'download';
      if (fallback.length > available) return null;
      truncatedStem = fallback;
    }
    return '$truncatedStem$ext';
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

  /// WIN-1b: yt-dlp `--trim-filenames` args for a Windows download whose final
  /// name the app CANNOT literal-bound — a custom user `filenameTemplate` that
  /// yt-dlp expands (`%(title)s`, `%(uploader)s`, …) only after launch. yt-dlp
  /// trims the expanded stem to N so the produced path fits MAX_PATH.
  ///
  /// Returns `['--trim-filenames', '$n']` on Windows, or `const []` on POSIX
  /// and when [candidateDirs] is so deep that N falls below [minUseful] (a
  /// pathological folder — let it fail clearly as pathNotFound rather than
  /// emit a useless 3-character name).
  ///
  /// N is the stem budget for the LONGEST of [candidateDirs] (pass the save
  /// folder + the *worst-case* temp dir, NOT the live temp dir, so N is stable
  /// across fresh / retry / `--continue` resume — an unstable N would shift the
  /// trimmed name and orphan the `.part`). The extension is folded into the
  /// reserve (not subtracted) so N is always ≥ the app-side literal bound for
  /// the same dirs — the default, already-bounded path is therefore a
  /// guaranteed no-op.
  ///
  /// yt-dlp trims by CODEPOINTS while MAX_PATH counts UTF-16 units; N is the
  /// unit budget, exact for BMP titles (ASCII / CJK — effectively all titles).
  /// An all-emoji custom-template title beyond N units still overflows and
  /// fails gracefully (ENAMETOOLONG → pathNotFound). Halving N to cover the
  /// all-emoji case is deliberately rejected: it would brutally over-trim every
  /// common-case name and break the literal-path no-op guarantee above.
  static List<String> windowsTrimFilenamesArgs({
    required List<String> candidateDirs,
    required bool windows,
    int maxPathUnits = windowsMaxPathUnits,
    int reserveUnits = _pathBudgetReserveUnits,
    int minUseful = 16,
  }) {
    if (!windows || candidateDirs.isEmpty) return const [];
    final longestDir = candidateDirs
        .map((d) => d.length)
        .reduce((a, b) => a > b ? a : b);
    final n = maxPathUnits - longestDir - 1 - reserveUnits;
    if (n < minUseful) return const [];
    return ['--trim-filenames', '$n'];
  }

  /// Normalize a URL by stripping known tracking parameters.
  ///
  /// Used for duplicate download detection: two URLs that differ only in
  /// tracking params (utm_*, si=, feature=, pp=) are considered the same.
  /// Returns the original URL unchanged if parsing fails.
  static String normalizeUrlForDuplicateCheck(String rawUrl) {
    try {
      final uri = Uri.parse(rawUrl);
      const trackingParams = {
        'utm_source',
        'utm_medium',
        'utm_campaign',
        'utm_term',
        'utm_content',
        'si',
        'feature',
        'pp',
        'fbclid',
        'gclid',
        'ref',
        'source',
      };
      final cleanParams = Map<String, String>.fromEntries(
        uri.queryParameters.entries.where(
          (e) => !trackingParams.contains(e.key),
        ),
      );
      final normalized = uri.replace(
        queryParameters: cleanParams.isEmpty ? null : cleanParams,
        fragment: '',
      );
      // uri.replace(fragment: '') adds a trailing '#' — strip it
      return normalized.toString().replaceAll(RegExp(r'#$'), '');
    } catch (_) {
      return rawUrl;
    }
  }

  /// Generate unique filename if file already exists
  static Future<String> getUniqueFilename(
    String directory,
    String filename,
  ) async {
    var file = File(path.join(directory, filename));

    if (!await file.exists()) {
      return filename;
    }

    final ext = path.extension(filename);
    final nameWithoutExt = path.basenameWithoutExtension(filename);
    var counter = 1;

    while (await file.exists()) {
      final newFilename = '$nameWithoutExt ($counter)$ext';
      file = File(path.join(directory, newFilename));
      counter++;
    }

    return path.basename(file.path);
  }

  /// Create directory if it doesn't exist.
  /// Throws [FileSystemException] with clear context on permission/IO failures.
  static Future<Directory> ensureDirectoryExists(String directoryPath) async {
    final directory = Directory(directoryPath);
    try {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return directory;
    } on FileSystemException catch (e) {
      throw FileSystemException(
        'Cannot create directory (${e.osError?.message ?? 'unknown'})',
        directoryPath,
        e.osError,
      );
    }
  }

  /// Test if the app can write to a directory.
  /// Creates and deletes a temporary test file.
  static Future<bool> canWriteToDirectory(String directoryPath) async {
    try {
      final dir = Directory(directoryPath);
      if (!await dir.exists()) return false;

      final testFile = File(
        path.join(
          directoryPath,
          '.ssvid_write_test_${DateTime.now().millisecondsSinceEpoch}',
        ),
      );
      await testFile.writeAsString('test');
      await testFile.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Get total size of a directory
  static Future<int> getDirectorySize(String directoryPath) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      return 0;
    }

    var totalSize = 0;
    await for (var entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        try {
          totalSize += await entity.length();
        } catch (_) {
          // Ignore files we can't access
        }
      }
    }

    return totalSize;
  }

  /// Return available bytes for an existing directory when the platform can
  /// report it. Returns null when unavailable or when parsing fails.
  static Future<int?> getAvailableBytes(String directoryPath) async {
    try {
      final dir = Directory(directoryPath);
      if (!await dir.exists()) return null;

      if (Platform.isWindows) {
        final root = path.rootPrefix(directoryPath);
        final drive = RegExp(r'^([A-Za-z]):').firstMatch(root)?.group(1);
        if (drive == null) return null;
        final result = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          '\$d=Get-PSDrive -Name $drive; [int64]\$d.Free',
        ]);
        if (result.exitCode != 0) return null;
        return int.tryParse((result.stdout as String).trim());
      }

      if (!Platform.isLinux && !Platform.isMacOS) return null;

      final result = await Process.run('df', ['-k', directoryPath]);
      if (result.exitCode != 0) return null;

      final lines = (result.stdout as String).trim().split('\n');
      for (int i = lines.length - 1; i >= 1; i--) {
        final parts = lines[i].trim().split(RegExp(r'\s+'));
        if (parts.length >= 4) {
          final availableKb = int.tryParse(parts[3]);
          if (availableKb != null) return availableKb * 1024;
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Check if directory has enough free space.
  ///
  /// On macOS/Linux uses `df -k` to query filesystem available bytes.
  /// On Windows returns true (graceful degradation — download errors will
  /// still surface but not upfront).
  /// Always fails open (returns true) on any unexpected error so downloads
  /// are never silently blocked by a monitoring bug.
  static Future<bool> hasEnoughSpace(
    String directoryPath,
    int requiredBytes, {
    int bufferBytes = 50 * 1024 * 1024, // 50 MB safety buffer
  }) async {
    if (requiredBytes <= 0) return true;
    try {
      if (Platform.isLinux || Platform.isMacOS) {
        // Ensure directory exists before querying (df needs a real path)
        final dir = Directory(directoryPath);
        if (!await dir.exists()) return true;

        final result = await Process.run('df', ['-k', directoryPath]);
        if (result.exitCode == 0) {
          final lines = (result.stdout as String).trim().split('\n');
          // df output (macOS): "Filesystem 1K-blocks Used Available ..."
          // The available column is index 3 on macOS, 3 on Linux too.
          // Iterate from the end to handle multi-line wrapped output.
          for (int i = lines.length - 1; i >= 1; i--) {
            final parts = lines[i].trim().split(RegExp(r'\s+'));
            if (parts.length >= 4) {
              final availableKb = int.tryParse(parts[3]);
              if (availableKb != null) {
                final availableBytes = availableKb * 1024;
                return availableBytes >= requiredBytes + bufferBytes;
              }
            }
          }
        }
      }
      // Windows or parse failure: fail open
      return true;
    } catch (_) {
      return true; // Never block downloads due to monitoring errors
    }
  }

  /// Delete file safely (with error handling)
  static Future<bool> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Copy file to destination
  static Future<bool> copyFile(
    String sourcePath,
    String destinationPath,
  ) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) {
        return false;
      }

      await source.copy(destinationPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Move file to destination
  static Future<bool> moveFile(
    String sourcePath,
    String destinationPath,
  ) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) {
        return false;
      }

      try {
        await source.rename(destinationPath);
      } on FileSystemException catch (e) {
        if (!_isCrossDeviceRenameError(e)) {
          return false;
        }

        final copied = await source.copy(destinationPath);
        final sourceSize = await source.length();
        final copiedSize = await copied.length();
        if (sourceSize != copiedSize) {
          await copied.delete().catchError((_) => copied);
          return false;
        }

        try {
          await source.delete();
        } catch (_) {
          await copied.delete().catchError((_) => copied);
          return false;
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool _isCrossDeviceRenameError(FileSystemException e) {
    final code = e.osError?.errorCode;
    if (Platform.isWindows) {
      return code == 17; // ERROR_NOT_SAME_DEVICE
    }
    return code == 18; // EXDEV
  }
}
