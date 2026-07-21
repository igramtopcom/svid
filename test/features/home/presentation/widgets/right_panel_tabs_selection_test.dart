import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:svid/features/home/presentation/widgets/right_panel_tabs.dart';

void main() {
  // The Subs & Audio tab previously had a tautology bug — every
  // audio tile rendered "selected" because the check compared a
  // list-derived item against the same list it came from. The
  // selection contract is now a pure function so it can be pinned
  // here without spinning a Player. Codex caught the original bug;
  // these tests make sure it does not regress.
  group('isAudioTrackSelected', () {
    test('returns true when ids match', () {
      const a = AudioTrack('1', 'English', 'eng');
      const current = AudioTrack('1', 'English', 'eng');
      expect(isAudioTrackSelected(a, current), isTrue);
    });

    test('returns false when ids differ', () {
      const a = AudioTrack('1', 'English', 'eng');
      const current = AudioTrack('2', 'Spanish', 'spa');
      expect(isAudioTrackSelected(a, current), isFalse);
    });

    test('returns false when current is the "no" sentinel', () {
      const a = AudioTrack('1', 'English', 'eng');
      final current = AudioTrack.no();
      expect(isAudioTrackSelected(a, current), isFalse);
    });

    test('returns false when current is the "auto" sentinel', () {
      const a = AudioTrack('1', 'English', 'eng');
      final current = AudioTrack.auto();
      expect(
        isAudioTrackSelected(a, current),
        isFalse,
        reason:
            'auto means mpv picks the track itself — no specific tile '
            'should claim selected',
      );
    });
  });

  group('isSubtitleTrackSelected', () {
    test('returns true when ids match', () {
      const s = SubtitleTrack('5', 'English', 'eng');
      const current = SubtitleTrack('5', 'English', 'eng');
      expect(isSubtitleTrackSelected(s, current), isTrue);
    });

    test('returns false when ids differ', () {
      const s = SubtitleTrack('5', 'English', 'eng');
      const current = SubtitleTrack('6', 'Vietnamese', 'vie');
      expect(isSubtitleTrackSelected(s, current), isFalse);
    });

    test('returns false when current is "no" (subtitles disabled)', () {
      const s = SubtitleTrack('5', 'English', 'eng');
      final current = SubtitleTrack.no();
      expect(isSubtitleTrackSelected(s, current), isFalse);
    });
  });
}
