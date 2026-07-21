import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/presentation/providers/downloads_notifier.dart';
import 'package:svid/features/settings/domain/enums/audio_codec_preference.dart';

/// RC5 of Ultra Plan v3 — pin `DownloadsNotifier.resolveRetryAudioFormat`.
///
/// Pre-RC5 the audio retry branch hardcoded `audioFormat: 'mp3'`, so an
/// Opus or AAC extract would silently convert to MP3 on retry. RC5
/// mirrors RC3's filename-first derivation. These tests pin the
/// resolver's contract; the retry-flow integration is covered by
/// `downloads_notifier_retry_test.dart`.
void main() {
  group('DownloadsNotifier.resolveRetryAudioFormatForTest — RC5', () {
    // ----- Filename derivation (the primary path) -----
    test('filename .mp3 → "mp3"', () {
      expect(
        DownloadsNotifier.resolveRetryAudioFormatForTest(
          filename: 'song.mp3',
          qualityLabel: null,
          settingsCodec: null,
        ),
        'mp3',
      );
    });

    test('filename .opus → "opus"', () {
      expect(
        DownloadsNotifier.resolveRetryAudioFormatForTest(
          filename: 'song.opus',
          qualityLabel: null,
          settingsCodec: null,
        ),
        'opus',
      );
    });

    test('filename .m4a → "m4a"', () {
      expect(
        DownloadsNotifier.resolveRetryAudioFormatForTest(
          filename: 'song.m4a',
          qualityLabel: null,
          settingsCodec: null,
        ),
        'm4a',
      );
    });

    test('filename .aac → "aac"', () {
      expect(
        DownloadsNotifier.resolveRetryAudioFormatForTest(
          filename: 'song.aac',
          qualityLabel: null,
          settingsCodec: null,
        ),
        'aac',
      );
    });

    test('filename .flac → "flac"', () {
      expect(
        DownloadsNotifier.resolveRetryAudioFormatForTest(
          filename: 'song.flac',
          qualityLabel: null,
          settingsCodec: null,
        ),
        'flac',
      );
    });

    test('filename .wav → "wav"', () {
      expect(
        DownloadsNotifier.resolveRetryAudioFormatForTest(
          filename: 'song.wav',
          qualityLabel: null,
          settingsCodec: null,
        ),
        'wav',
      );
    });

    test(
      'filename .ogg → "vorbis" (OGG container conventionally holds Vorbis)',
      () {
        expect(
          DownloadsNotifier.resolveRetryAudioFormatForTest(
            filename: 'song.ogg',
            qualityLabel: null,
            settingsCodec: null,
          ),
          'vorbis',
        );
      },
    );

    test('filename .alac → "alac" (Apple Lossless)', () {
      expect(
        DownloadsNotifier.resolveRetryAudioFormatForTest(
          filename: 'song.alac',
          qualityLabel: null,
          settingsCodec: null,
        ),
        'alac',
      );
    });

    test('filename ext is case-insensitive', () {
      expect(
        DownloadsNotifier.resolveRetryAudioFormatForTest(
          filename: 'song.OPUS',
          qualityLabel: null,
          settingsCodec: null,
        ),
        'opus',
      );
    });

    test('multi-dot filename uses LAST extension', () {
      // Production audio filenames include qualityLabel parentheses
      // and quality markers: "Song Title [Best (256kbps)].opus".
      expect(
        DownloadsNotifier.resolveRetryAudioFormatForTest(
          filename: 'Some Song Title [Best (256kbps)].opus',
          qualityLabel: null,
          settingsCodec: null,
        ),
        'opus',
      );
    });

    // ----- Quality label hint fallback -----
    test('qualityLabel "Audio Only (Opus)" + no filename ext → "opus"', () {
      expect(
        DownloadsNotifier.resolveRetryAudioFormatForTest(
          filename: 'song_no_ext',
          qualityLabel: 'Audio Only (Opus)',
          settingsCodec: null,
        ),
        'opus',
      );
    });

    test('qualityLabel "Audio Only (AAC)" → "aac"', () {
      expect(
        DownloadsNotifier.resolveRetryAudioFormatForTest(
          filename: null,
          qualityLabel: 'Audio Only (AAC)',
          settingsCodec: null,
        ),
        'aac',
      );
    });

    test(
      'qualityLabel "Audio Only (M4A/AAC)" → "m4a" (most specific wins)',
      () {
        // Order of checks in the resolver: opus → m4a → flac → aac →
        // mp3. M4A is more specific than AAC for the produced
        // container, so the resolver prefers it.
        expect(
          DownloadsNotifier.resolveRetryAudioFormatForTest(
            filename: null,
            qualityLabel: 'Audio Only (M4A/AAC)',
            settingsCodec: null,
          ),
          'm4a',
        );
      },
    );

    test('filename wins over qualityLabel', () {
      // Belt-and-braces: if both filename ext AND qualityLabel hint
      // are present, filename is the source of truth.
      expect(
        DownloadsNotifier.resolveRetryAudioFormatForTest(
          filename: 'song.opus',
          qualityLabel: 'Audio Only (MP3)',
          settingsCodec: null,
        ),
        'opus',
      );
    });

    // ----- Settings codec fallback -----
    test('settings.aac fallback when filename + qualityLabel are null', () {
      expect(
        DownloadsNotifier.resolveRetryAudioFormatForTest(
          filename: null,
          qualityLabel: null,
          settingsCodec: AudioCodecPreference.aac,
        ),
        'aac',
      );
    });

    test('settings.opus fallback', () {
      expect(
        DownloadsNotifier.resolveRetryAudioFormatForTest(
          filename: null,
          qualityLabel: null,
          settingsCodec: AudioCodecPreference.opus,
        ),
        'opus',
      );
    });

    test('settings.mp3 fallback', () {
      expect(
        DownloadsNotifier.resolveRetryAudioFormatForTest(
          filename: null,
          qualityLabel: null,
          settingsCodec: AudioCodecPreference.mp3,
        ),
        'mp3',
      );
    });

    test('settings.auto + no filename + no label → "mp3" last resort', () {
      // `auto` means "let yt-dlp pick" — but `--audio-format` needs
      // a concrete value. The resolver falls all the way through
      // to mp3 rather than emitting an empty or invalid arg.
      expect(
        DownloadsNotifier.resolveRetryAudioFormatForTest(
          filename: null,
          qualityLabel: null,
          settingsCodec: AudioCodecPreference.auto,
        ),
        'mp3',
      );
    });

    test('all-null → "mp3" last resort', () {
      expect(
        DownloadsNotifier.resolveRetryAudioFormatForTest(
          filename: null,
          qualityLabel: null,
          settingsCodec: null,
        ),
        'mp3',
      );
    });

    test(
      'unknown extension → falls through to qualityLabel / settings / mp3',
      () {
        // `.xyz` is not an audio ext; resolver moves to qualityLabel,
        // then settings, then mp3 fallback.
        expect(
          DownloadsNotifier.resolveRetryAudioFormatForTest(
            filename: 'song.xyz',
            qualityLabel: 'Audio Only (Opus)',
            settingsCodec: null,
          ),
          'opus',
          reason: 'Unknown ext defers to qualityLabel',
        );
        expect(
          DownloadsNotifier.resolveRetryAudioFormatForTest(
            filename: 'song.xyz',
            qualityLabel: null,
            settingsCodec: AudioCodecPreference.aac,
          ),
          'aac',
          reason: 'Unknown ext defers to settings',
        );
        expect(
          DownloadsNotifier.resolveRetryAudioFormatForTest(
            filename: 'song.xyz',
            qualityLabel: null,
            settingsCodec: null,
          ),
          'mp3',
          reason: 'Unknown ext + no signals = mp3 fallback',
        );
      },
    );
  });

  group('DownloadsNotifier.resolveRetryAudioBitrateKbpsForTest', () {
    test('derives bitrate from filename before quality label', () {
      expect(
        DownloadsNotifier.resolveRetryAudioBitrateKbpsForTest(
          filename: 'song [Audio - AAC 256 kbps].m4a',
          qualityLabel: 'Audio - AAC 320 kbps',
        ),
        256,
      );
    });

    test('derives bitrate from quality label when filename has no bitrate', () {
      expect(
        DownloadsNotifier.resolveRetryAudioBitrateKbpsForTest(
          filename: 'song.opus',
          qualityLabel: 'Audio - Opus 192 kbps',
        ),
        192,
      );
    });

    test('returns null when no bitrate is persisted', () {
      expect(
        DownloadsNotifier.resolveRetryAudioBitrateKbpsForTest(
          filename: 'song.mp3',
          qualityLabel: 'Audio Only (MP3)',
        ),
        isNull,
      );
    });
  });
}
