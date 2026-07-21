import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/domain/entities/download_config.dart';
import 'package:ssvid/features/downloads/domain/entities/video_info.dart';
import 'package:ssvid/features/settings/domain/enums/audio_codec_preference.dart';
import 'package:ssvid/features/settings/domain/enums/container_format_preference.dart';
import 'package:ssvid/features/settings/domain/enums/download_engine.dart';
import 'package:ssvid/features/settings/domain/enums/fps_preference.dart';
import 'package:ssvid/features/settings/domain/enums/quality_preference.dart';
import 'package:ssvid/features/settings/domain/enums/video_codec_preference.dart';
import 'package:ssvid/features/settings/presentation/providers/settings_provider.dart';

void main() {
  group('DownloadConfig.hasOverrides', () {
    final settings = _settingsState();

    test('returns false when no override fields are set', () {
      expect(
        const DownloadConfig(selectedQualities: []).hasOverrides(settings),
        isFalse,
      );
    });

    for (final entry
        in <String, DownloadConfig>{
          'subtitlesLanguages': const DownloadConfig(
            selectedQualities: [],
            subtitlesLanguages: ['vi', 'en'],
          ),
          'subtitlesFormat': const DownloadConfig(
            selectedQualities: [],
            subtitlesFormat: 'vtt',
          ),
          'embedSubtitles': const DownloadConfig(
            selectedQualities: [],
            embedSubtitles: false,
          ),
          'includeAutoSubs': const DownloadConfig(
            selectedQualities: [],
            includeAutoSubs: true,
          ),
          'writeThumbnail': const DownloadConfig(
            selectedQualities: [],
            writeThumbnail: true,
          ),
          'sponsorBlockAction': const DownloadConfig(
            selectedQualities: [],
            sponsorBlockAction: 'remove',
          ),
          'sponsorBlockCategories': const DownloadConfig(
            selectedQualities: [],
            sponsorBlockCategories: ['sponsor', 'intro'],
          ),
          'sectionEndTime': const DownloadConfig(
            selectedQualities: [],
            sectionEndTime: Duration(seconds: 30),
          ),
        }.entries) {
      test('returns true for ${entry.key}', () {
        expect(entry.value.hasOverrides(settings), isTrue);
      });
    }
  });

  group('DownloadConfig audio bitrate target', () {
    const audioQuality = Quality(
      qualityText: 'Audio - AAC 320 kbps',
      size: 'High quality',
      encryptedUrl: 'ytdlp:audio:m4a',
      mediaType: MediaType.audio,
      isAudioOnly: true,
      tbr: 320,
    );

    test('uses portable audio target bitrate for audio downloads', () {
      const config = DownloadConfig(
        selectedQualities: [audioQuality],
        fileType: DownloadFileType.audio,
        qualityTarget: PortableQualityTarget.audio(
          outputFormat: 'm4a',
          targetBitrateKbps: 256,
        ),
      );

      expect(config.audioBitrateKbpsFor(audioQuality), 256);
    });

    test('returns null for lossless audio target bitrate', () {
      const losslessQuality = Quality(
        qualityText: 'Audio - WAV Lossless',
        size: 'Lossless audio',
        encryptedUrl: 'ytdlp:audio:wav',
        mediaType: MediaType.audio,
        isAudioOnly: true,
      );
      const config = DownloadConfig(
        selectedQualities: [losslessQuality],
        fileType: DownloadFileType.audio,
        qualityTarget: PortableQualityTarget.audio(outputFormat: 'wav'),
      );

      expect(config.audioBitrateKbpsFor(losslessQuality), isNull);
    });

    test('ignores accidental bitrate on lossless audio targets', () {
      const losslessQuality = Quality(
        qualityText: 'Audio - WAV Lossless',
        size: 'Lossless audio',
        encryptedUrl: 'ytdlp:audio:wav',
        mediaType: MediaType.audio,
        isAudioOnly: true,
      );
      const config = DownloadConfig(
        selectedQualities: [losslessQuality],
        fileType: DownloadFileType.audio,
        qualityTarget: PortableQualityTarget.audio(
          outputFormat: 'wav',
          targetBitrateKbps: 320,
        ),
      );

      expect(config.audioBitrateKbpsFor(losslessQuality), isNull);
    });

    test('does not infer bitrate from raw quality metadata', () {
      const config = DownloadConfig(selectedQualities: [audioQuality]);

      expect(config.audioBitrateKbpsFor(audioQuality), isNull);
    });

    test('returns null for non-audio qualities', () {
      const videoQuality = Quality(
        qualityText: '1080p',
        size: '10 MB',
        encryptedUrl: 'ytdlp:bestvideo+bestaudio',
        mediaType: MediaType.video,
      );
      const config = DownloadConfig(
        selectedQualities: [videoQuality],
        qualityTarget: PortableQualityTarget.audio(
          outputFormat: 'mp3',
          targetBitrateKbps: 320,
        ),
      );

      expect(config.audioBitrateKbpsFor(videoQuality), isNull);
    });
  });

  group('DownloadConfig.copyWith savePathOverride', () {
    test('sets one-time save path override', () {
      final config = const DownloadConfig(
        selectedQualities: [],
      ).copyWith(savePathOverride: () => '/Users/test/Downloads');

      expect(config.savePathOverride, '/Users/test/Downloads');
    });

    test('clears one-time save path override with null sentinel', () {
      final config = const DownloadConfig(
        selectedQualities: [],
        savePathOverride: '/Users/test/Downloads',
      ).copyWith(savePathOverride: () => null);

      expect(config.savePathOverride, isNull);
    });
  });

  group('DownloadConfig primary selection intent', () {
    test('stores file type, quality intent, and portable target', () {
      final target = const PortableQualityTarget.video(targetHeight: 1080);
      final config = DownloadConfig(
        selectedQualities: const [],
        fileType: DownloadFileType.video,
        qualityIntent: DownloadQualityIntent.specific,
        qualityTarget: target,
      );

      expect(config.fileType, DownloadFileType.video);
      expect(config.qualityIntent, DownloadQualityIntent.specific);
      expect(config.qualityTarget, target);
      expect(config.hasOverrides(_settingsState()), isTrue);
    });

    test('copyWith can update and clear portable target', () {
      final config = const DownloadConfig(
        selectedQualities: [],
        fileType: DownloadFileType.video,
        qualityIntent: DownloadQualityIntent.specific,
        qualityTarget: PortableQualityTarget.video(targetHeight: 1080),
      );

      final updated = config.copyWith(
        fileType: DownloadFileType.audio,
        qualityIntent: DownloadQualityIntent.recommended,
        qualityTarget:
            () => const PortableQualityTarget.audio(
              outputFormat: 'mp3',
              targetBitrateKbps: 192,
            ),
      );

      expect(updated.fileType, DownloadFileType.audio);
      expect(updated.qualityIntent, DownloadQualityIntent.recommended);
      expect(updated.qualityTarget?.outputFormat, 'mp3');
      expect(updated.qualityTarget?.targetBitrateKbps, 192);

      final cleared = updated.copyWith(qualityTarget: () => null);
      expect(cleared.qualityTarget, isNull);
    });
  });
}

SettingsState _settingsState() {
  return const SettingsState(
    downloadPath: '/tmp',
    maxConcurrentDownloads: 3,
    themeMode: ThemeMode.system,
    autoStartDownloads: false,
    autoClipboardDetection: true,
    notificationsEnabled: true,
    preferredQuality: QualityPreference.auto,
    downloadEngine: DownloadEngine.ytdlpOnly,
    enableApiFallback: false,
    autoUpdateYtdlp: true,
    ytdlpTimeout: 30,
    showDownloadMethodBadge: true,
    videoCodecPreference: VideoCodecPreference.h264,
    audioCodecPreference: AudioCodecPreference.aac,
    containerFormatPreference: ContainerFormatPreference.mp4,
    fpsPreference: FpsPreference.auto,
    maxResolution: 0,
    subtitlesEnabled: false,
    subtitlesLanguages: ['en'],
    subtitlesFormat: 'srt',
    embedSubtitles: true,
    writeThumbnail: false,
    embedThumbnail: true,
    embedMetadata: true,
    embedChapters: true,
    sponsorBlockEnabled: false,
    sponsorBlockAction: 'skip',
    sponsorBlockCategories: ['sponsor'],
    forceRemux: false,
    tiktokRemoveWatermark: true,
    geoBypass: false,
    archiveEnabled: false,
  );
}
