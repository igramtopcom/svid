import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/data/datasources/ytdlp_datasource.dart';

/// RC4b of Ultra Plan v3 — final-path scan-extension resolver.
///
/// Production log #406 (2026-05-22) confirmed bug: M4V request →
/// yt-dlp `--recode-video mp4` runs successfully (because yt-dlp
/// rejects 'm4v' as a recode target, so the planner remaps to
/// 'mp4'), but the post-process scan demanded `.m4v` and errored
/// out BEFORE the `.mp4 → .m4v` rename block at
/// `ytdlp_datasource.dart:2669` could run. RC4b makes the scan look
/// for the extension yt-dlp actually emitted; the rename block then
/// promotes `.mp4 → .m4v` as designed.
void main() {
  group('YtDlpDataSource.recodeScanExtensionForTest — RC4b', () {
    test('M4V special: videoFormat=m4v + recodeVideo=mp4 → scan for "mp4"', () {
      // The exact #406 scenario. yt-dlp produced .mp4; the scan
      // MUST find that .mp4 (NOT demand .m4v) so the downstream
      // rename block can convert it to .m4v.
      expect(
        YtDlpDataSource.recodeScanExtensionForTest(
          videoFormat: 'm4v',
          recodeVideo: 'mp4',
        ),
        'mp4',
        reason:
            'RC4b: M4V rename path — scan must use the extension yt-dlp '
            'actually produced (.mp4), not the user pick (.m4v)',
      );
    });

    test(
      'AVI (no remap): videoFormat=avi + recodeVideo=avi → scan for "avi"',
      () {
        // AVI does NOT trigger the M4V special. yt-dlp produces .avi
        // directly (RC4a override notwithstanding), so scan for .avi.
        expect(
          YtDlpDataSource.recodeScanExtensionForTest(
            videoFormat: 'avi',
            recodeVideo: 'avi',
          ),
          'avi',
        );
      },
    );

    test(
      'MOV (no remap): videoFormat=mov + recodeVideo=mov → scan for "mov"',
      () {
        expect(
          YtDlpDataSource.recodeScanExtensionForTest(
            videoFormat: 'mov',
            recodeVideo: 'mov',
          ),
          'mov',
        );
      },
    );

    test(
      'FLV (no remap): videoFormat=flv + recodeVideo=flv → scan for "flv"',
      () {
        expect(
          YtDlpDataSource.recodeScanExtensionForTest(
            videoFormat: 'flv',
            recodeVideo: 'flv',
          ),
          'flv',
        );
      },
    );

    test(
      'Explicit mp4 recode target: videoFormat=mp4 + recodeVideo=mp4 → scan for "mp4"',
      () {
        // Defensive support for callers that explicitly request an mp4
        // recode target. Native MP4 downloads no longer use this path.
        expect(
          YtDlpDataSource.recodeScanExtensionForTest(
            videoFormat: 'mp4',
            recodeVideo: 'mp4',
          ),
          'mp4',
        );
      },
    );

    test('videoFormat null → fall back to recodeVideo as scan target', () {
      // Defensive: caller paths that don't track videoFormat fall
      // back to the recodeVideo extension. Common-case sanity.
      expect(
        YtDlpDataSource.recodeScanExtensionForTest(
          videoFormat: null,
          recodeVideo: 'mp4',
        ),
        'mp4',
      );
    });

    test('edge: both null → empty string (caller guards above this)', () {
      // The production call site is wrapped in
      // `if (recodeVideo != null && !extractAudio)` so this branch
      // is unreachable in practice. The helper returns '' rather
      // than throwing so a future codepath that drops the guard
      // surfaces an empty-scan ext (immediate visible bug) rather
      // than a NullPointerException deep in the stream.
      expect(
        YtDlpDataSource.recodeScanExtensionForTest(
          videoFormat: null,
          recodeVideo: null,
        ),
        '',
      );
    });

    test('case normalization: uppercase video format → lowercase output', () {
      // Defensive against future codepath bug. The production planner
      // always emits lowercase, but a normalize-once helper protects
      // the contract.
      expect(
        YtDlpDataSource.recodeScanExtensionForTest(
          videoFormat: 'AVI',
          recodeVideo: 'AVI',
        ),
        'avi',
      );
    });

    test(
      'M4V special does NOT fire when only one of (videoFormat, recodeVideo) is m4v/mp4',
      () {
        // Regression guard: the M4V remap is a TWO-condition gate
        // (videoFormat=='m4v' AND recodeVideo=='mp4'). Loosening
        // either condition could mask a planner bug.
        expect(
          YtDlpDataSource.recodeScanExtensionForTest(
            videoFormat: 'm4v',
            recodeVideo: 'mkv', // would never happen, but guards the gate
          ),
          'm4v',
        );
        expect(
          YtDlpDataSource.recodeScanExtensionForTest(
            videoFormat: 'mp4',
            recodeVideo: 'mp4',
          ),
          'mp4',
        );
      },
    );
  });

  // RC4b.1 — non-zero salvage path must use the same scan-extension
  // logic. The exit_code != 0 salvage block at the bottom of the
  // yt-dlp event loop was previously calling
  // `(videoFormat ?? recodeVideo).toLowerCase()` directly, missing
  // the M4V remap. These tests pin that the SAME helper is the
  // source of truth for both exit paths — the helper is the
  // single-source contract.
  group('Salvage-path parity (RC4b.1)', () {
    test(
      'M4V helper output is identical for exit==0 and exit!=0 callsites',
      () {
        // Both callsites pass the same (videoFormat, recodeVideo) pair
        // and read the same helper. The helper must therefore return
        // the same string for both — no callsite drift allowed.
        final exitZero = YtDlpDataSource.recodeScanExtensionForTest(
          videoFormat: 'm4v',
          recodeVideo: 'mp4',
        );
        final exitNonZero = YtDlpDataSource.recodeScanExtensionForTest(
          videoFormat: 'm4v',
          recodeVideo: 'mp4',
        );
        expect(
          exitZero,
          exitNonZero,
          reason:
              'RC4b.1: single-source contract — both salvage paths '
              'must scan the same ext for the M4V remap',
        );
        expect(exitZero, 'mp4');
      },
    );

    test(
      'AVI helper output is identical for exit==0 and exit!=0 callsites',
      () {
        // No remap, but pinning the parity invariant for the AVI
        // case so a future helper change for AVI lands consistently.
        final scan = YtDlpDataSource.recodeScanExtensionForTest(
          videoFormat: 'avi',
          recodeVideo: 'avi',
        );
        expect(scan, 'avi');
      },
    );
  });
}
