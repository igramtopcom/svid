import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/core/services/disk_space_service.dart';

/// Unit tests for [DiskSpaceService].
///
/// Covers the pure-parser surface in isolation (df / PowerShell output
/// shapes the platform-specific probes hand back) plus an end-to-end smoke
/// against the host's actual filesystem so the wiring against
/// `Process.run` is also exercised. The pure-parser tests run identically
/// on every host; the smoke test gates itself on platform support.
void main() {
  group('parseDfOutput', () {
    test('parses a canonical Linux df -k output', () {
      const output = '''Filesystem     1K-blocks      Used Available Use% Mounted on
/dev/sda1      488245288 153728448 309687480  34% /
''';
      // Available = 309687480 KB → bytes
      expect(
        DiskSpaceService.parseDfOutput(output),
        309687480 * 1024,
      );
    });

    test('parses a canonical macOS df -k output (two-% column layout)', () {
      // macOS df has BOTH a `Capacity` (disk %) and a `%iused` (inode %)
      // column. The header-based parser must lock onto `Available` by
      // name so it doesn't fall into the right-anchor trap and pick
      // `ifree` (inode count) instead of the actual byte-available value.
      const output = '''Filesystem    1024-blocks       Used Available Capacity iused      ifree %iused  Mounted on
/dev/disk1s1   488245288   153728448 309687480    34%  500000 4500000    10%   /
''';
      expect(
        DiskSpaceService.parseDfOutput(output),
        309687480 * 1024,
        reason: 'Available column must resolve to the disk byte count, '
            'not the inode count. Regression guard for the macOS '
            'two-% df layout.',
      );
    });

    test('returns null for completely empty input', () {
      expect(DiskSpaceService.parseDfOutput(''), isNull);
    });

    test('returns null for header-only input (no data row)', () {
      const output =
          'Filesystem 1K-blocks Used Available Use% Mounted on\n';
      expect(DiskSpaceService.parseDfOutput(output), isNull);
    });

    test('returns null when the data row has too few columns', () {
      const output = '''Filesystem 1K-blocks Used Available Use% Mounted on
/dev/x 1 2
''';
      expect(DiskSpaceService.parseDfOutput(output), isNull);
    });

    test('returns null when Available column is not numeric', () {
      const output = '''Filesystem 1K-blocks Used Available Use% Mounted on
/dev/x 100 50 not-a-number 50% /
''';
      expect(DiskSpaceService.parseDfOutput(output), isNull);
    });

    test('handles CRLF line endings (Windows df via WSL etc.)', () {
      const output =
          'Filesystem 1K-blocks Used Available Use% Mounted on\r\n'
          '/dev/sda1 100 50 50 50% /\r\n';
      expect(DiskSpaceService.parseDfOutput(output), 50 * 1024);
    });

    test('handles wrapped Filesystem name on its own line', () {
      // Very long device names cause BSD/GNU df to wrap the Filesystem
      // column onto a separate line, leaving the data row with one fewer
      // column than the header. The parser compensates by shifting the
      // Available index left by one.
      const output = '''Filesystem    1024-blocks       Used Available Capacity Mounted on
/dev/very/long/device/name/that/wraps/onto/next/line
            488245288   153728448 309687480    34% /
''';
      expect(DiskSpaceService.parseDfOutput(output), 309687480 * 1024);
    });

    test('returns null when header has no Available column', () {
      const output = '''Filesystem 1K-blocks Used Free Use% Mounted on
/dev/sda1 100 50 50 50% /
''';
      expect(DiskSpaceService.parseDfOutput(output), isNull);
    });
  });

  group('parsePowershellFreeOutput', () {
    test('parses a bare integer with trailing newline', () {
      expect(
        DiskSpaceService.parsePowershellFreeOutput('123456789\n'),
        123456789,
      );
    });

    test('parses with CRLF line ending', () {
      expect(
        DiskSpaceService.parsePowershellFreeOutput('987654321\r\n'),
        987654321,
      );
    });

    test('parses bare integer without any trailing whitespace', () {
      expect(DiskSpaceService.parsePowershellFreeOutput('42'), 42);
    });

    test('returns null for empty output', () {
      expect(DiskSpaceService.parsePowershellFreeOutput(''), isNull);
    });

    test('returns null for whitespace-only output', () {
      expect(DiskSpaceService.parsePowershellFreeOutput('   \n\r\n '), isNull);
    });

    test('returns null when output is not numeric', () {
      expect(
        DiskSpaceService.parsePowershellFreeOutput('Get-PSDrive : Cannot find drive'),
        isNull,
      );
    });
  });

  group('hasEnoughSpace contract', () {
    test(
      'returns true when free space is plentiful for a 0-byte request',
      () async {
        if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
          return; // unsupported host
        }
        final result = await DiskSpaceService.hasEnoughSpace(
          Directory.systemTemp.path,
          requiredBytes: 0,
          headroomBytes: 1, // anything more than 0 must pass on a real host
        );
        // result is null if probe failed (also OK — opportunistic gate)
        expect(result == null || result == true, isTrue);
      },
    );

    test(
      'returns false when the requested size is larger than any real disk',
      () async {
        if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
          return;
        }
        final result = await DiskSpaceService.hasEnoughSpace(
          Directory.systemTemp.path,
          // 1 EB. No consumer-grade disk has this.
          requiredBytes: 1 << 60,
          headroomBytes: 0,
        );
        // If probe returned null (couldn't measure), accept that — the
        // contract says null=unknown/proceed. Otherwise we expect false.
        expect(result == null || result == false, isTrue);
      },
    );
  });

  group('freeBytesAt host-smoke (best-effort)', () {
    test(
      'returns a positive integer for the system temp directory',
      () async {
        if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
          return;
        }
        final bytes = await DiskSpaceService.freeBytesAt(
          Directory.systemTemp.path,
        );
        // null is acceptable (sandboxed CI, mac df-quirk, etc.); when
        // present, must be positive.
        if (bytes != null) {
          expect(bytes, greaterThan(0));
        }
      },
    );
  });
}
