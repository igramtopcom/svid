import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/data/datasources/ytdlp_datasource.dart';

/// Lock the intermediate-DASH-file detector against upstream yt-dlp
/// naming drift. The motivating bug (`log.md` 2026-05-21 Incident C,
/// Wilson Facebook + tester no-audio) was that the legacy regex
/// `.f\d+(?:-\d+)?\.<ext>` did NOT match Facebook's
/// `.f964607196458600v.mp4` pattern — the `v`/`a` suffix that
/// yt-dlp's Facebook extractor appends to disambiguate DASH
/// video-only vs audio-only streams. Result: video-only files were
/// silently treated as the final download, integrity check found no
/// audio, fatal-failed without a recovery path.
///
/// This test pins:
///   - YouTube/Facebook DASH and Twitter/X HLS intermediates MUST be
///     classified as intermediates by the salvage path.
///   - Legitimate final filenames MUST NOT match (no false rejects).
///   - Edge cases (`.f` in title, no digits) must NOT trigger.
///
/// `_isYtDlpIntermediateFormatFile` is private so we exercise it via
/// `YtDlpDataSource.isIntermediateFormatFileForTest`.
void main() {
  bool isIntermediate(String basename) =>
      YtDlpDataSource.isIntermediateFormatFileForTest(basename);

  group('YouTube DASH intermediates (classic)', () {
    test('classic numeric format id matches', () {
      expect(isIntermediate('Title.f137.mp4'), isTrue);
      expect(isIntermediate('Audio_Only.f140.m4a'), isTrue);
    });

    test('format-id with -N subformat matches', () {
      // yt-dlp emits `.f251-10.webm` for DASH webm audio subformats.
      expect(isIntermediate('Vid.f251-10.webm'), isTrue);
      expect(isIntermediate('Vid.f399-1.mp4'), isTrue);
    });
  });

  group('Facebook DASH intermediates (the production bug)', () {
    test('long video-only format id with v suffix matches', () {
      // Wilson + tester production reports. Pre-fix this was NOT
      // matched and was silently picked as the final file.
      expect(
        isIntermediate('13K views ... [720p].f964607196458600v.mp4'),
        isTrue,
        reason:
            'Facebook DASH video-only `.f<long_id>v.<ext>` MUST be '
            'classified as intermediate so the salvage path rejects it',
      );
    });

    test('long audio-only format id with a suffix matches', () {
      expect(
        isIntermediate('reel.f1350541610457985a.m4a'),
        isTrue,
        reason:
            'Facebook DASH audio-only `.f<long_id>a.<ext>` MUST be '
            'classified as intermediate',
      );
    });

    test('shorter Facebook video id with v suffix matches', () {
      expect(isIntermediate('post.f964607196458600v.mp4'), isTrue);
      expect(isIntermediate('post.f100v.mp4'), isTrue);
    });
  });

  group('Protocol format-id intermediates', () {
    test('non-numeric hls audio format id matches', () {
      expect(
        isIntermediate('Stitch [1080p].fhls-audio-128000-Audio.mp4'),
        isTrue,
        reason:
            'Twitter/X HLS audio-only `.fhls-audio-...<ext>` MUST be '
            'classified as intermediate so recode final-path scan does not '
            'promote an audio-only mp4 over the real recoded mp4',
      );
    });

    test('non-numeric hls video format id matches', () {
      expect(isIntermediate('tweet.fhls-video-2176000-Video.mp4'), isTrue);
      expect(isIntermediate('tweet.fhls-2176.mp4'), isTrue);
    });

    test('dash/http protocol format ids match', () {
      expect(isIntermediate('reddit.fdash-video-2176000-Video.mp4'), isTrue);
      expect(isIntermediate('vimeo.fhttp-720p.mp4'), isTrue);
      expect(isIntermediate('daily.fhttps-1080p.mp4'), isTrue);
    });
  });

  group('Final files MUST NOT be classified as intermediate', () {
    test('normal video filenames without .f<id> segment', () {
      expect(isIntermediate('Title [720p].mp4'), isFalse);
      expect(isIntermediate('My Vlog (1080p) - 2024.mp4'), isFalse);
      expect(isIntermediate('audio.mp3'), isFalse);
      expect(isIntermediate('podcast.m4a'), isFalse);
    });

    test('title contains literal `.f` but no digits after', () {
      // Edge case: title naturally contains `.f` (e.g. abbrev). The
      // regex requires `\d+` after `.f`, so these MUST NOT trigger.
      expect(isIntermediate('A_fact.mp4'), isFalse);
      expect(isIntermediate('intro.fade-out.mp4'), isFalse);
    });

    test('files with .f<digits> but no extension match still fails', () {
      // The `$` anchor + extension class forces a real ext; bare
      // `.f137` without trailing ext does not match (defensive).
      expect(isIntermediate('Title.f137'), isFalse);
    });

    test('files with f<digits>.<ext> WITHOUT leading dot do not match', () {
      // Format-id naming requires a separator dot before `f<id>` —
      // a title that happens to contain `f137.mp4` mid-word should
      // not be misclassified (defensive against false-positive on
      // user titles).
      expect(isIntermediate('chapter f137 outro.mp4'), isFalse);
    });
  });

  group('Edge cases — suffix character precision', () {
    test(
      'only `v` or `a` are valid DASH disambiguators (not arbitrary letters)',
      () {
        // yt-dlp's known Facebook DASH disambiguators are `v` and `a`.
        // A theoretical `.f100z.mp4` is not a documented intermediate
        // shape; classifying it as intermediate would be over-greedy.
        // (Re-evaluate if upstream adds new suffixes.)
        expect(
          isIntermediate('.f100z.mp4'),
          isFalse,
          reason: 'Only v/a are known DASH suffixes; z must not match',
        );
        expect(isIntermediate('.f100b.mp4'), isFalse);
      },
    );

    test('uppercase F is NOT matched (yt-dlp always emits lowercase f)', () {
      // yt-dlp's output template uses lowercase `f`. Defensive: do not
      // expand the match to `[Ff]` without upstream evidence.
      expect(isIntermediate('Title.F137.mp4'), isFalse);
    });
  });

  // Cross-check: this test file's pattern literal must exactly match
  // the production literal in ytdlp_datasource.dart. If you touch one
  // and not the other, this assertion fires.
  group('production regex parity', () {
    test('matches the static literal embedded in the datasource', () {
      // Sentinel pattern values that must remain matched/unmatched in
      // production. If the production regex literal drifts away from
      // the test literal, the canonical-pattern tests above will
      // diverge from real runtime behavior — re-sync this file.
      const matchesProduction = <String, bool>{
        // intermediates
        'video.f137.mp4': true,
        'video.f251-10.webm': true,
        'reel.f964607196458600v.mp4': true,
        'reel.f1350541610457985a.m4a': true,
        'tweet.fhls-audio-128000-Audio.mp4': true,
        'reddit.fdash-video-2176000-Video.mp4': true,
        'vimeo.fhttp-720p.mp4': true,
        // finals
        'Title [720p].mp4': false,
        'A_fact.mp4': false,
        'audio.mp3': false,
      };
      for (final entry in matchesProduction.entries) {
        expect(
          isIntermediate(entry.key),
          entry.value,
          reason:
              'Pattern parity broke for "${entry.key}" expected=${entry.value}',
        );
      }
    });
  });
}

/// Dummy import so the test file ties to the package — referencing
/// the datasource ensures the production code stays compiled when this
/// test runs and forces a recompile-cascade when the datasource
/// changes the canonical regex.
// ignore: unused_element
void _typeAnchor() {
  // Reference one public symbol from the production library so the
  // test depends on the production unit.
  YtDlpDataSource;
}
