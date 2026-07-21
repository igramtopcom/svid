import 'dart:io';

import 'package:flutter/foundation.dart';

import '../logging/app_logger.dart';

/// Best-effort free-disk-space probe for the partition holding a given path.
///
/// Closes the production checklist gap "Preflight free disk space before
/// large download/conversion; stop retry loops when disk is full" by
/// surfacing the available bytes BEFORE a download is queued. yt-dlp's own
/// disk-full handling is reactive (the user only sees the error after a
/// partial download + retry burn), whereas a preflight refusal gives the
/// user an actionable message immediately.
///
/// Implementation contract:
///   * [freeBytesAt] returns `null` when the platform check fails (unknown
///     drive, OS process unavailable, permission denied). Callers MUST
///     treat `null` as "unknown, proceed" — preflight is opportunistic,
///     never a hard gate that blocks legitimate downloads on platforms we
///     can't measure.
///   * [hasEnoughSpace] returns `false` only when free space is definitively
///     insufficient. `null` (unknown) and `true` (enough) both allow the
///     download to proceed.
///
/// The probe shells out via `Process.run`. Adding a Dart package for this
/// would inflate the dependency surface — both platform implementations
/// rely on commands shipped with every install:
///   * Windows: `powershell.exe Get-PSDrive`
///   * macOS / Linux: `df -k`
class DiskSpaceService {
  DiskSpaceService._();

  /// Headroom reserved beyond the requested download size. Covers:
  ///   * yt-dlp temp intermediates (`.part`, `.f<id>.<ext>` fragments)
  ///   * ffmpeg muxing scratch
  ///   * gallery-dl staging directory
  ///   * Misc safety margin for filesystem overhead and other apps
  static const int defaultHeadroomBytes = 500 * 1024 * 1024; // 500 MB

  /// Process invocation timeout. The probes return in tens of ms on a
  /// healthy host; anything past this is a hung filesystem and we'd
  /// rather skip the check than block the download dialog.
  static const Duration _probeTimeout = Duration(seconds: 3);

  /// Returns free bytes on the partition that contains [path], or `null`
  /// when the platform-specific probe could not complete.
  static Future<int?> freeBytesAt(String path) async {
    try {
      if (Platform.isWindows) {
        return await _freeBytesWindows(path);
      }
      if (Platform.isMacOS || Platform.isLinux) {
        return await _freeBytesPosix(path);
      }
      return null;
    } catch (e) {
      appLogger.warning('DiskSpaceService.freeBytesAt failed: $e');
      return null;
    }
  }

  /// `true` when [path] has at least `requiredBytes + headroomBytes` free.
  /// `false` when free space is known and insufficient.
  /// `null` when free space cannot be determined.
  static Future<bool?> hasEnoughSpace(
    String path, {
    required int requiredBytes,
    int headroomBytes = defaultHeadroomBytes,
  }) async {
    final free = await freeBytesAt(path);
    if (free == null) return null;
    return free >= requiredBytes + headroomBytes;
  }

  static Future<int?> _freeBytesPosix(String path) async {
    final result = await Process.run('df', ['-k', path]).timeout(_probeTimeout);
    if (result.exitCode != 0) return null;
    return parseDfOutput(result.stdout as String);
  }

  static Future<int?> _freeBytesWindows(String path) async {
    // Accept both `C:` and `C:\\…` shapes. UNC paths (\\server\share) are
    // not supported by Get-PSDrive directly — return null and let the
    // caller proceed without preflight.
    if (path.length < 2 || path[1] != ':') return null;
    final driveLetter = path[0];
    final result = await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        '(Get-PSDrive -Name $driveLetter -ErrorAction Stop).Free',
      ],
    ).timeout(_probeTimeout);
    if (result.exitCode != 0) return null;
    return parsePowershellFreeOutput(result.stdout as String);
  }

  /// Parse the `Available` column from a `df -k` invocation by NAME.
  /// Returns bytes, or `null` if the layout is unexpected.
  ///
  /// Sample inputs (column count varies by platform):
  ///
  ///   Linux:
  ///     Filesystem     1K-blocks      Used Available Use% Mounted on
  ///     /dev/sda1      488245288 153728448 309687480  34% /
  ///
  ///   macOS (BSD df has TWO percent columns, `Capacity` and `%iused`):
  ///     Filesystem    1024-blocks       Used Available Capacity iused      ifree %iused  Mounted on
  ///     /dev/disk1s1   488245288   153728448 309687480    34%  500000 4500000    10%   /
  ///
  /// The earlier right-anchor heuristic picked the LAST `%`, which on
  /// macOS is `%iused` — its preceding column is `ifree` (file-system
  /// inode count), NOT the byte count we want. Header-based column
  /// lookup is the robust fix.
  @visibleForTesting
  static int? parseDfOutput(String output) {
    final lines = const LineSplitter()
        .convert(output)
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) return null;

    // Header row tells us which column index holds "Available". Normalise
    // the compound `Mounted on` suffix to a single column so the column
    // count matches the data row, where the mount point is one token.
    final header = lines.first;
    var headerCols = header.trim().split(RegExp(r'\s+'));
    if (headerCols.length >= 2 &&
        headerCols[headerCols.length - 2].toLowerCase() == 'mounted' &&
        headerCols.last.toLowerCase() == 'on') {
      headerCols = [
        ...headerCols.sublist(0, headerCols.length - 2),
        'Mounted on',
      ];
    }
    var availableIdx = -1;
    for (var i = 0; i < headerCols.length; i++) {
      if (headerCols[i].toLowerCase() == 'available') {
        availableIdx = i;
        break;
      }
    }
    if (availableIdx < 0) return null;

    // Data row is typically lines[1]; use the LAST non-empty line so
    // soft-wrapped headers (very long Filesystem names) don't shift the
    // count. Note: df wraps the filesystem onto its own line when the
    // name is long; in that case the data row has fewer cols than the
    // header (filesystem skipped). Detect this by checking column count.
    final lastLine = lines.last.trim();
    var cols = lastLine.split(RegExp(r'\s+'));

    // Wrapped-filesystem case: data row is missing the Filesystem column.
    // Compensate by skipping the leading "Filesystem" header index.
    if (cols.length == headerCols.length - 1 && availableIdx > 0) {
      availableIdx -= 1;
    }

    if (cols.length <= availableIdx) return null;
    final availableKb = int.tryParse(cols[availableIdx]);
    if (availableKb == null) return null;
    return availableKb * 1024;
  }

  /// Parse the bare integer printed by
  /// `(Get-PSDrive -Name C).Free`. PowerShell wraps the number in
  /// whitespace (newline + possible carriage return).
  @visibleForTesting
  static int? parsePowershellFreeOutput(String output) {
    final trimmed = output.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed);
  }
}

// Local LineSplitter so this service doesn't pull `dart:convert` into the
// callers' import set via the public API.
class LineSplitter {
  const LineSplitter();
  List<String> convert(String text) =>
      text.split(RegExp(r'\r?\n'));
}
