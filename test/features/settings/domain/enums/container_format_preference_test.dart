import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/settings/domain/enums/container_format_preference.dart';

/// RC3 of Ultra Plan v3 — pin `ContainerFormatPreference.fromExtension`
/// behavior. The retry path in `downloads_notifier` calls this to
/// recover the user's original container choice from
/// `download.filename` so the retry honors the original AVI/MOV/MKV
/// pick instead of drifting to whatever the user's current global
/// settings happen to be.
void main() {
  group('ContainerFormatPreference.fromExtension', () {
    test('bare extension token resolves all 7 containers', () {
      expect(ContainerFormatPreference.fromExtension('mp4'),
          ContainerFormatPreference.mp4);
      expect(ContainerFormatPreference.fromExtension('mkv'),
          ContainerFormatPreference.mkv);
      expect(ContainerFormatPreference.fromExtension('webm'),
          ContainerFormatPreference.webm);
      expect(ContainerFormatPreference.fromExtension('avi'),
          ContainerFormatPreference.avi);
      expect(ContainerFormatPreference.fromExtension('mov'),
          ContainerFormatPreference.mov);
      expect(ContainerFormatPreference.fromExtension('m4v'),
          ContainerFormatPreference.m4v);
      expect(ContainerFormatPreference.fromExtension('flv'),
          ContainerFormatPreference.flv);
    });

    test('leading dot is tolerated (".avi")', () {
      expect(ContainerFormatPreference.fromExtension('.avi'),
          ContainerFormatPreference.avi);
    });

    test('full filename: last segment after final dot wins', () {
      // The production log #402/#403 filenames look like:
      //   "Cologne Cathedral song [Best (1080p)].avi"
      // The parser must take the trailing `avi`, not get confused by
      // the qualityLabel parentheses or earlier dots in the title.
      expect(
        ContainerFormatPreference.fromExtension(
            'Cologne Cathedral song [Best (1080p)].avi'),
        ContainerFormatPreference.avi,
      );
      expect(
        ContainerFormatPreference.fromExtension('My.Video.With.Dots.mkv'),
        ContainerFormatPreference.mkv,
      );
    });

    test('case-insensitive', () {
      expect(ContainerFormatPreference.fromExtension('AVI'),
          ContainerFormatPreference.avi);
      expect(ContainerFormatPreference.fromExtension('video.MP4'),
          ContainerFormatPreference.mp4);
      expect(ContainerFormatPreference.fromExtension('Foo.MoV'),
          ContainerFormatPreference.mov);
    });

    test('null / empty / no extension → null (caller falls back)', () {
      expect(ContainerFormatPreference.fromExtension(null), isNull);
      expect(ContainerFormatPreference.fromExtension(''), isNull);
      expect(ContainerFormatPreference.fromExtension('filename_no_ext'),
          isNull);
      expect(ContainerFormatPreference.fromExtension('.'), isNull);
    });

    test('audio extensions return null — caller routes to audio path', () {
      // mp3/m4a/opus/flac etc. are audio-only formats. They are not
      // ContainerFormatPreference values, so fromExtension MUST
      // return null and let `_isAudioOnlyDownload` + the audio
      // branch of `_buildRetryPlanFromSettings` handle them.
      expect(ContainerFormatPreference.fromExtension('song.mp3'), isNull);
      expect(ContainerFormatPreference.fromExtension('song.m4a'), isNull);
      expect(ContainerFormatPreference.fromExtension('song.opus'), isNull);
      expect(ContainerFormatPreference.fromExtension('song.flac'), isNull);
      expect(ContainerFormatPreference.fromExtension('song.wav'), isNull);
      expect(ContainerFormatPreference.fromExtension('song.ogg'), isNull);
      expect(ContainerFormatPreference.fromExtension('song.aac'), isNull);
    });

    test('unknown video extension → null', () {
      expect(ContainerFormatPreference.fromExtension('video.3gp'), isNull);
      expect(ContainerFormatPreference.fromExtension('video.wmv'), isNull);
      expect(ContainerFormatPreference.fromExtension('video.ts'), isNull);
    });

    test('whitespace is trimmed', () {
      expect(ContainerFormatPreference.fromExtension('  avi  '),
          ContainerFormatPreference.avi);
      expect(ContainerFormatPreference.fromExtension('video.avi '),
          ContainerFormatPreference.avi);
    });
  });
}
