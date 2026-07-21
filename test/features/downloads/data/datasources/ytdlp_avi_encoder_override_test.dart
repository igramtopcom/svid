import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/data/datasources/ytdlp_datasource.dart';

/// RC4a of Ultra Plan v3 — AVI encoder override via yt-dlp
/// `--postprocessor-args VideoConvertor:...`.
///
/// Production log #403 (line 125): fresh AVI download fails with
/// "Encoder not found" because yt-dlp's FFmpegVideoConvertorPP
/// HARDCODES `-c:v libxvid -vtag XVID` and the bundled ffmpeg
/// (martin-riedl.de build) is compiled WITHOUT libxvid. Bundled
/// ffmpeg DOES ship `mpeg4` (built-in) + `libmp3lame`, so the
/// override produces a valid Xvid-compatible AVI.
///
/// These tests pin the args STRING the production code emits.
/// Runtime verification (Chairman fresh AVI smoke test on bundled
/// binaries) is the next gate per Codex direction — args correctness
/// is necessary but not sufficient.
void main() {
  group('YtDlpDataSource.recodeEncoderOverrideArgsForTest — RC4a', () {
    test(
      'recodeVideo="avi" → emits postprocessor-args with mpeg4 + libmp3lame',
      () {
        final args = YtDlpDataSource.recodeEncoderOverrideArgsForTest('avi');
        expect(args.length, 2,
            reason: 'Override emits exactly two args: flag + value');
        expect(args[0], '--postprocessor-args',
            reason: 'First arg is the yt-dlp flag');
        expect(args[1], startsWith('VideoConvertor:'),
            reason: 'Targets VideoConvertor postprocessor specifically');
        expect(args[1], contains('-c:v mpeg4'),
            reason: 'Overrides hardcoded libxvid with bundled mpeg4');
        expect(args[1], contains('-vtag XVID'),
            reason: 'Keeps XVID FourCC for legacy AVI editor compatibility');
        expect(args[1], contains('-c:a libmp3lame'),
            reason: 'Audio codec compatible with AVI + bundled');
        expect(args[1], isNot(contains('libxvid')),
            reason: 'libxvid is the bundled-ffmpeg gap RC4a closes');
      },
    );

    test('exact args string is pinned (regression guard)', () {
      // Pinned exactly to catch silent edits. If you change this
      // string (e.g., to add a different encoder or bitrate flag),
      // update this test in the SAME commit and document why in
      // the commit message.
      expect(
        YtDlpDataSource.recodeEncoderOverrideArgsForTest('avi'),
        equals([
          '--postprocessor-args',
          'VideoConvertor:-c:v mpeg4 -vtag XVID -c:a libmp3lame',
        ]),
      );
    });

    test(
      'non-AVI containers return empty list — no preemptive override',
      () {
        // Per Codex direction: don't override what isn't proven
        // broken. mp4/mkv/webm don't need recode at all (the
        // function won't be called). mov/m4v/flv let yt-dlp
        // auto-pick an encoder that bundled ffmpeg should have;
        // RC4b smoke verification will confirm or refute.
        for (final ext in ['mp4', 'mkv', 'webm', 'mov', 'm4v', 'flv']) {
          expect(
            YtDlpDataSource.recodeEncoderOverrideArgsForTest(ext),
            isEmpty,
            reason: '$ext must NOT receive RC4a override (pending RC4b smoke)',
          );
        }
      },
    );

    test('null recodeVideo returns empty list (defensive)', () {
      // Production path guards `if (recodeVideo != null)` BEFORE
      // calling this helper. Defensive null-tolerance kept so the
      // helper is safe to call from any context.
      expect(
        YtDlpDataSource.recodeEncoderOverrideArgsForTest(null),
        isEmpty,
      );
    });

    test('unknown / unexpected token returns empty list', () {
      expect(
        YtDlpDataSource.recodeEncoderOverrideArgsForTest(''),
        isEmpty,
      );
      expect(
        YtDlpDataSource.recodeEncoderOverrideArgsForTest('AVI'),
        isEmpty,
        reason:
            'Production passes lowercase ext; uppercase would indicate a '
            'codepath bug we want to surface, not silently override',
      );
      expect(
        YtDlpDataSource.recodeEncoderOverrideArgsForTest('3gp'),
        isEmpty,
      );
    });
  });
}
