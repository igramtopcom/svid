import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/core/utils/file_utils.dart';
import 'package:ssvid/features/downloads/domain/entities/download_error_code.dart';
import 'package:ssvid/features/downloads/domain/services/download_error_classifier.dart';

/// WIN-1/DL-007: Facebook/CJK long titles in a deep folder overflow Windows
/// MAX_PATH (260 UTF-16 code units) and surface as a late, generic
/// pathNotFound. `boundFilenameToPathLimit` truncates the stem so BOTH the
/// final path AND the worst-case temp write path fit, preserving the
/// extension and CJK/emoji, and returns null only when even a minimal name
/// cannot fit (deep save folder) so the caller can fail clearly.
///
/// The tests call the helper with an explicit [maxPathUnits] so the Windows
/// branch is exercised on any host (the production caller passes
/// `Platform.isWindows ? windowsMaxPathUnits : null`).
void main() {
  const win = FileUtils.windowsMaxPathUnits; // 260

  // The longest intermediate the temp dir ever holds is
  // `<stem> (99).f<id>.<ext>.part` — ~17 units beyond the final name. A passing
  // budget must leave room for it; the helper reserves 24, so this is the
  // strong invariant every truncation result must satisfy.
  const worstIntermediateUnits = 17;
  void expectFitsWithIntermediate(String dir, String name) {
    expect(
      dir.length + 1 + name.length + worstIntermediateUnits,
      lessThanOrEqualTo(win),
      reason: 'full temp path "$dir/$name" + worst intermediate must fit $win',
    );
  }

  group('boundFilenameToPathLimit — truncation fits MAX_PATH', () {
    test('long Facebook title in a normal folder is truncated, ext preserved',
        () {
      const dir = r'C:\Users\Christopher\Videos';
      final longTitle =
          'Facebook Live ${'Very Long Reel Title Words ' * 12}.mp4';
      final r = FileUtils.boundFilenameToPathLimit(
        fileName: longTitle,
        candidateDirs: [dir],
        maxPathUnits: win,
      )!;
      expect(r, endsWith('.mp4')); // extension preserved
      expect(r.length, lessThan(longTitle.length)); // actually truncated
      expectFitsWithIntermediate(dir, r);
    });

    test('deep OneDrive folder truncates the stem more aggressively', () {
      final deepDir =
          r'C:\Users\Christopher\OneDrive\Pictures\Saved Videos\Facebook'
          r'\2026\June\Archived Reels Collection';
      final longTitle = '${'A' * 200}.mp4';
      final r = FileUtils.boundFilenameToPathLimit(
        fileName: longTitle,
        candidateDirs: [deepDir],
        maxPathUnits: win,
      )!;
      expect(r, endsWith('.mp4'));
      expectFitsWithIntermediate(deepDir, r);
    });

    test('the worst-case temp dir (deep AppData) drives the budget over a '
        'SHALLOW save folder — shallow dir alone would wrongly pass', () {
      const shallowSave = r'D:\v'; // 4 units — passes on its own
      final deepTemp =
          r'C:\Users\Christopher\AppData\Local\Temp\vidcombo_downloads'
          r'\9999999999999_99999'; // ~76 units — the real constraint
      final longTitle = '${'B' * 230}.mp4';
      final r = FileUtils.boundFilenameToPathLimit(
        fileName: longTitle,
        candidateDirs: [shallowSave, deepTemp],
        maxPathUnits: win,
      )!;
      // Must fit the LONGER (temp) dir, not the shallow save dir.
      expectFitsWithIntermediate(deepTemp, r);
    });
  });

  group('boundFilenameToPathLimit — CJK / emoji preservation', () {
    test('CJK title counts 1 unit/char (not 3 bytes) and stays intact', () {
      const dir = r'C:\Users\张伟\视频';
      // 150 CJK chars = 150 UTF-16 units (each BMP).
      final cjk = '${'视频标题精彩' * 25}.mp4';
      final r = FileUtils.boundFilenameToPathLimit(
        fileName: cjk,
        candidateDirs: [dir],
        maxPathUnits: win,
      )!;
      expect(r, endsWith('.mp4'));
      expect(r, startsWith('视频标题')); // CJK not mangled to bytes
      expectFitsWithIntermediate(dir, r);
    });

    test('emoji title is truncated WITHOUT splitting a surrogate pair', () {
      const dir = r'C:\Users\Christopher\Videos\Deep\Folder\Path\Here\More';
      final emoji = '${'😀😃😄😁' * 60}.mp4'; // each emoji = 2 UTF-16 units
      final r = FileUtils.boundFilenameToPathLimit(
        fileName: emoji,
        candidateDirs: [dir],
        maxPathUnits: win,
      )!;
      expect(r, endsWith('.mp4'));
      expectFitsWithIntermediate(dir, r);
      // No lone surrogate: every high surrogate is followed by a low surrogate.
      final units = r.codeUnits;
      for (var i = 0; i < units.length; i++) {
        final u = units[i];
        if (u >= 0xD800 && u <= 0xDBFF) {
          expect(i + 1, lessThan(units.length),
              reason: 'high surrogate must not be the last unit');
          expect(units[i + 1], inInclusiveRange(0xDC00, 0xDFFF),
              reason: 'high surrogate must be paired with a low surrogate');
        }
      }
    });
  });

  group('boundFilenameToPathLimit — no-op and edge cases', () {
    test('short name in shallow folder is returned UNCHANGED', () {
      const dir = r'C:\Users\Me\Videos';
      const name = 'Cat Reel.mp4';
      expect(
        FileUtils.boundFilenameToPathLimit(
          fileName: name,
          candidateDirs: [dir],
          maxPathUnits: win,
        ),
        name,
      );
    });

    test('POSIX (maxPathUnits null) is a no-op even for a huge name', () {
      final huge = '${'Z' * 400}.mp4';
      expect(
        FileUtils.boundFilenameToPathLimit(
          fileName: huge,
          candidateDirs: [r'/Users/me/Movies'],
          maxPathUnits: null,
        ),
        huge,
      );
    });

    test('extension preserved exactly for multi-dot and webm names', () {
      const dir = r'C:\Users\Christopher\Videos';
      final r = FileUtils.boundFilenameToPathLimit(
        fileName: '${'My.Show.S01.E01.' * 20}clip.webm',
        candidateDirs: [dir],
        maxPathUnits: win,
      )!;
      expect(r, endsWith('.webm'));
    });

    test('a save folder that is itself near the limit returns null '
        '(fail-clear, never a half-truncated name)', () {
      final tooDeep = 'C:\\${'a\\' * 125}'; // ~252 units of folder
      expect(
        FileUtils.boundFilenameToPathLimit(
          fileName: 'video.mp4',
          candidateDirs: [tooDeep],
          maxPathUnits: win,
        ),
        isNull,
      );
    });

    test('reserve leaves room: a name truncated to the budget edge still fits '
        'the worst-case `(99).f<id>.<ext>.part` intermediate', () {
      const dir = r'C:\Users\Christopher\AppData\Local\Temp\vidcombo_downloads'
          r'\1718000000000_42';
      final r = FileUtils.boundFilenameToPathLimit(
        fileName: '${'W' * 220}.mp4',
        candidateDirs: [dir],
        maxPathUnits: win,
      )!;
      // Construct the literal worst intermediate yt-dlp could write and assert
      // it is within MAX_PATH — proves the reserve is adequate.
      final stem = r.substring(0, r.length - '.mp4'.length);
      final intermediate = '$stem (99).f243-2.mp4.part';
      expect(dir.length + 1 + intermediate.length, lessThanOrEqualTo(win));
    });

    test('the reserve absorbs the LONGEST real format ids (FB DASH numeric + '
        'HLS named) — the DL-007 Facebook DASH overflow case', () {
      const dir = r'C:\Users\Christopher\AppData\Local\Temp\vidcombo_downloads'
          r'\9999999999999_99999'; // deep temp dir
      final r = FileUtils.boundFilenameToPathLimit(
        fileName: '${'F' * 230}.webm',
        candidateDirs: [dir],
        maxPathUnits: win,
      )!;
      final stem = r.substring(0, r.length - '.webm'.length);
      // The two longest intermediates observed in production must both fit:
      for (final intermediate in [
        '$stem (999).f1350541610457985a.webm.part', // FB DASH numeric id
        '$stem (999).fhls-audio-128000-Audio.webm.part', // HLS named id
      ]) {
        expect(dir.length + 1 + intermediate.length, lessThanOrEqualTo(win),
            reason: 'intermediate "$intermediate" must fit MAX_PATH');
      }
    });
  });

  group('fail-clear message routes to pathNotFound (end-to-end)', () {
    test('the upfront preflight message classifies to pathNotFound, NOT unknown',
        () {
      const msg =
          'The save folder path is too long for Windows (260-character limit). '
          'Choose a shorter folder, or move it closer to the drive root, then '
          'try again.';
      expect(
        DownloadErrorClassifier.classifyMessage(msg),
        DownloadErrorCode.pathNotFound,
      );
    });

    test('a real runtime ENAMETOOLONG also classifies to pathNotFound', () {
      expect(
        DownloadErrorClassifier.classifyMessage(
            'FileSystemException: ... (OS Error: File name too long, errno = 36)'),
        DownloadErrorCode.pathNotFound,
      );
      expect(
        DownloadErrorClassifier.classifyMessage(
            'The filename or extension is too long'),
        DownloadErrorCode.pathNotFound,
      );
    });
  });
}
