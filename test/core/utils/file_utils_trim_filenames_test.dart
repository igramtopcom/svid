import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/utils/file_utils.dart';

/// WIN-1b: `--trim-filenames` for the one Windows path the app cannot
/// literal-bound — a custom user `filenameTemplate` that yt-dlp expands after
/// launch. The default template substitutes the app-built (already-bounded)
/// filename, so it must stay a no-op. N is derived from the path budget; these
/// lock the contract (emit on Windows, no-op POSIX, stable, no double-trim).
void main() {
  const win = FileUtils.windowsMaxPathUnits; // 260
  const reserve = 48; // _pathBudgetReserveUnits

  List<String> args(List<String> dirs, {bool windows = true}) =>
      FileUtils.windowsTrimFilenamesArgs(
        candidateDirs: dirs,
        windows: windows,
      );

  group('windowsTrimFilenamesArgs — emit / no-op', () {
    test('custom-template Windows download emits --trim-filenames N', () {
      const dir = r'C:\Users\Christopher\Videos';
      final a = args([dir]);
      expect(a.length, 2);
      expect(a[0], '--trim-filenames');
      final n = int.parse(a[1]);
      expect(n, win - dir.length - 1 - reserve); // exact unit budget
      expect(n, greaterThan(0));
    });

    test('POSIX is a no-op (empty args) even for a normal folder', () {
      expect(args([r'/Users/me/Movies'], windows: false), isEmpty);
    });

    test('the worst-case temp dir drives N over a shallow save folder', () {
      const shallowSave = r'D:\v';
      final deepTemp =
          r'C:\Users\Christopher\AppData\Local\Temp\vidcombo_downloads'
          r'\9999999999999_99999';
      final n = int.parse(args([shallowSave, deepTemp])[1]);
      expect(n, win - deepTemp.length - 1 - reserve); // longest dir wins
    });
  });

  group('windowsTrimFilenamesArgs — N magnitude', () {
    test('a deeper Windows folder yields a smaller N', () {
      final shallow = int.parse(args([r'C:\v'])[1]);
      final deep = int.parse(
        args([r'C:\Users\Christopher\OneDrive\Videos\Facebook\2026\June'])[1],
      );
      expect(deep, lessThan(shallow));
    });

    test('N is the UTF-16 unit budget, NOT halved for emoji (conservative-'
        'for-emoji is handled by graceful ENAMETOOLONG, not by gutting the '
        'common case)', () {
      const dir = r'C:\Users\Christopher\Videos';
      final n = int.parse(args([dir])[1]);
      // Exactly the unit budget — a halving heuristic would give ~n/2.
      expect(n, win - dir.length - 1 - reserve);
    });

    test('a pathological deep folder (N below the useful floor) emits NOTHING '
        '— let it fail clearly as pathNotFound, not a 3-char garbage name', () {
      final tooDeep = 'C:\\${'a\\' * 110}'; // ~222 units
      expect(args([tooDeep]), isEmpty);
    });
  });

  group('windowsTrimFilenamesArgs — literal-path no-op guarantee', () {
    test('N is >= the app-side literal bound for the same dirs, so the default '
        '(already-bounded) path is never re-trimmed by yt-dlp', () {
      const dir = r'C:\Users\Christopher\OneDrive\Videos\Facebook\Archive';
      // What the app-side bound would produce for a very long literal name:
      final bounded = FileUtils.boundFilenameToPathLimit(
        fileName: '${'T' * 300}.mp4',
        candidateDirs: [dir],
        maxPathUnits: win,
      )!;
      final boundedStem = bounded.substring(0, bounded.length - '.mp4'.length);
      final n = int.parse(args([dir])[1]);
      // yt-dlp trims to N codepoints; the bounded literal stem (in units) is
      // <= N, so on the literal path the trim never fires.
      expect(boundedStem.length, lessThanOrEqualTo(n));
    });
  });

  group('windowsTrimFilenamesArgs — no duplicate / conflicting args', () {
    test('emits at most ONE --trim-filenames flag', () {
      final a = args([r'C:\Users\Christopher\Videos']);
      expect(a.where((x) => x == '--trim-filenames').length, 1);
    });

    test('empty candidateDirs is a safe no-op (no flag)', () {
      expect(args(const []), isEmpty);
    });
  });
}
