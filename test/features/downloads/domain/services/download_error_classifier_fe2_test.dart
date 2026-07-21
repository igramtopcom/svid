import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/domain/entities/download_error_code.dart';
import 'package:ssvid/features/downloads/domain/services/download_error_classifier.dart';

/// FE-2 (2026-06-25 live probe): the Windows yt-dlp.exe (PyInstaller onefile)
/// bootloader can fail to self-extract its bundled .pyd/.dll to %TEMP%\_MEIxxxx
/// ("[PYI-NNNNN:ERROR] Failed to extract a packed .pyd: decompression resulted
/// in return code -1"). 36 distinct current-build devices were hidden in the
/// `unknown` bucket. These now classify to `ytdlpBinaryMissing` (the engine
/// can't run) so the FE-2 cluster is measurable and gets the binary-unavailable
/// UX — WITHOUT mis-matching yt-dlp's own video-"extraction" errors.
///
/// Fixtures are verbatim production messages from the probe (device-id hex
/// elided). The WDAC / antivirus ytdlpBinaryMissing messages were ALREADY
/// classified correctly (via "failed to execute yt-dlp"); they are locked here
/// as regression guards.
void main() {
  DownloadErrorCode code(String m) =>
      DownloadErrorClassifier.classifyMessage(m);

  group('FE-2 PyInstaller self-extract → ytdlpBinaryMissing (out of unknown)', () {
    test('[PYI] decompression return-code -1 (the dominant self-extract form)',
        () {
      expect(
        code('Download failed: [PYI-12772:ERROR] Failed to extract '
            '81d243__mypyc.cp310-win_amd64.pyd: decompression resulted in '
            'return code -1!'),
        DownloadErrorCode.ytdlpBinaryMissing,
      );
    });

    test('[PYI] failed to extract a bundled .dll', () {
      expect(
        code('Download failed: [PYI-5728:ERROR] Failed to extract '
            'libcrypto-1_1.dll: decompression resulted in return code -1!'),
        DownloadErrorCode.ytdlpBinaryMissing,
      );
    });

    test('[PYI] wrapped in a Rust AnyhowException Unknown(...) (the unknown-bucket'
        ' shape that hid these)', () {
      expect(
        code('YtDlpException(YtDlpErrorType.unknown): AnyhowException('
            'yt-dlp error: Unknown("[PYI-19092:ERROR] Failed to extract entry: '
            '81d243...decompression resulted in return code -1"))'),
        DownloadErrorCode.ytdlpBinaryMissing,
      );
    });

    test('PyInstaller runtime-hook traceback frame', () {
      expect(
        code('Download failed: Traceback (most recent call last):\n  File '
            '"pyi_rth_multiprocessing.py", line 87, in <module>'),
        DownloadErrorCode.ytdlpBinaryMissing,
      );
    });
  });

  group('FE-2 regression guards — already-coded binary blocks stay correct', () {
    test('WDAC Application Control block still → ytdlpBinaryMissing', () {
      expect(
        code('Failed to execute yt-dlp\n\nCaused by:\n    An Application '
            'Control policy has blocked this file. (os error 4551)'),
        DownloadErrorCode.ytdlpBinaryMissing,
      );
    });

    test('binary-missing / antivirus-quarantine message still → '
        'ytdlpBinaryMissing', () {
      expect(
        code('Failed to execute yt-dlp: the download engine binary is missing '
            'and automatic repair did not succeed — your antivirus may have '
            'quarantined it.'),
        DownloadErrorCode.ytdlpBinaryMissing,
      );
    });
  });

  group('FE-2 no over-match — yt-dlp video-extraction errors are NOT binary', () {
    test('"Unable to extract" video data is NOT ytdlpBinaryMissing', () {
      expect(
        code('ERROR: Unable to extract video data; the site may have changed'),
        isNot(DownloadErrorCode.ytdlpBinaryMissing),
      );
    });

    test('a generic "failed to extract player response" is NOT binary-missing', () {
      // No PyInstaller `[pyi-` / decompression-return-code marker → must not
      // collide with the new self-extract patterns.
      expect(
        code('ERROR: Failed to extract any player response'),
        isNot(DownloadErrorCode.ytdlpBinaryMissing),
      );
    });
  });

  group('FE-2 review hardening — decompression line is AND-gated', () {
    test('"decompression resulted in return code" ALONE does NOT classify as '
        'binary-missing (the false-positive the AND-gate prevents)', () {
      expect(
        code('zip decompression resulted in return code 2 while unpacking'),
        isNot(DownloadErrorCode.ytdlpBinaryMissing),
      );
    });

    test('"failed to extract" + "decompression resulted in return code" '
        'together (a [pyi-]-tag-stripped self-extract variant) DO classify', () {
      expect(
        code('Failed to extract _ctypes.pyd: decompression resulted in '
            'return code -1'),
        DownloadErrorCode.ytdlpBinaryMissing,
      );
    });
  });
}
