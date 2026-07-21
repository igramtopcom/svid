import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/utils/platform_detector.dart';
import 'package:svid/features/downloads/domain/entities/download_selection_intent.dart';
import 'package:svid/features/downloads/domain/services/format_selector_service.dart';
import 'package:svid/features/downloads/domain/entities/video_info.dart';
import 'package:svid/features/downloads/presentation/utils/platform_preference_config.dart';
import 'package:svid/features/settings/domain/enums/audio_codec_preference.dart';
import 'package:svid/features/settings/domain/enums/container_format_preference.dart';
import 'package:svid/features/settings/domain/enums/fps_preference.dart';
import 'package:svid/features/settings/domain/enums/video_codec_preference.dart';
import 'package:svid/features/settings/domain/entities/platform_quality_preference.dart';

void main() {
  group('downloadConfigFromPlatformPreference', () {
    final quality = const Quality(
      qualityText: '1080p MP4',
      size: '100 MB',
      encryptedUrl: 'quality-token',
      mediaType: MediaType.video,
    );

    test('returns null when the saved preference has no overrides', () {
      final preference = PlatformQualityPreference(
        platform: VideoPlatform.youtube,
        qualityText: quality.qualityText,
        mediaType: quality.mediaType,
        savedAt: DateTime.utc(2026),
      );

      expect(downloadConfigFromPlatformPreference(preference, quality), isNull);
    });

    test('maps primary intent even when no advanced overrides are saved', () {
      final preference = PlatformQualityPreference(
        platform: VideoPlatform.youtube,
        qualityText: quality.qualityText,
        mediaType: quality.mediaType,
        savedAt: DateTime.utc(2026),
        fileType: DownloadFileType.video,
        qualityIntent: DownloadQualityIntent.specific,
        qualityTarget: const PortableQualityTarget.video(targetHeight: 1080),
      );

      final config = downloadConfigFromPlatformPreference(preference, quality);

      expect(config, isNotNull);
      expect(config!.selectedQualities, [quality]);
      expect(config.fileType, DownloadFileType.video);
      expect(config.qualityIntent, DownloadQualityIntent.specific);
      expect(
        config.qualityTarget,
        const PortableQualityTarget.video(targetHeight: 1080),
      );
    });

    test('maps saved platform overrides into DownloadConfig', () {
      final preference = PlatformQualityPreference(
        platform: VideoPlatform.youtube,
        qualityText: quality.qualityText,
        mediaType: quality.mediaType,
        savedAt: DateTime.utc(2026),
        videoCodec: 'vp9',
        audioCodec: 'opus',
        containerFormat: 'webm',
        fpsPreference: 'prefer60',
        maxResolution: 1080,
        subtitlesEnabled: true,
        subtitlesLanguages: const ['vi', 'en'],
        subtitlesFormat: 'vtt',
        embedSubtitles: false,
        includeAutoSubs: true,
        writeThumbnail: true,
        sponsorBlockEnabled: true,
        sponsorBlockAction: 'remove',
        sponsorBlockCategories: const ['sponsor', 'intro'],
        forceRemux: true,
        tiktokRemoveWatermark: false,
        embedThumbnail: false,
        embedMetadata: false,
        embedChapters: false,
      );

      final config = downloadConfigFromPlatformPreference(preference, quality);

      expect(config, isNotNull);
      expect(config!.selectedQualities, [quality]);
      expect(config.videoCodecOverride, VideoCodecPreference.vp9);
      expect(config.audioCodecOverride, AudioCodecPreference.opus);
      expect(config.containerFormatOverride, ContainerFormatPreference.webm);
      expect(config.fpsOverride, FpsPreference.prefer60);
      expect(config.maxResolutionOverride, 1080);
      expect(config.subtitlesEnabled, isTrue);
      expect(config.subtitlesLanguages, ['vi', 'en']);
      expect(config.subtitlesFormat, 'vtt');
      expect(config.embedSubtitles, isFalse);
      expect(config.includeAutoSubs, isTrue);
      expect(config.writeThumbnail, isTrue);
      expect(config.sponsorBlockEnabled, isTrue);
      expect(config.sponsorBlockAction, 'remove');
      expect(config.sponsorBlockCategories, ['sponsor', 'intro']);
      expect(config.forceRemux, isTrue);
      expect(config.tiktokRemoveWatermark, isFalse);
      expect(config.embedThumbnail, isFalse);
      expect(config.embedMetadata, isFalse);
      expect(config.embedChapters, isFalse);
    });
  });

  group('resolveQualityForPlatformPreference', () {
    const qualities = [
      Quality(
        qualityText: 'Best (4K)',
        size: '512 MB',
        encryptedUrl: 'ytdlp:best:mp4',
        mediaType: MediaType.video,
      ),
      Quality(
        qualityText: 'Full HD',
        size: '220 MB',
        encryptedUrl: 'ytdlp:1080p',
        mediaType: MediaType.video,
      ),
      Quality(
        qualityText: 'HD',
        size: '120 MB',
        encryptedUrl: 'ytdlp:720p',
        mediaType: MediaType.video,
      ),
    ];

    test('resolves specific target before legacy quality text', () {
      final preference = PlatformQualityPreference(
        platform: VideoPlatform.youtube,
        qualityText: '1080p MP4',
        mediaType: MediaType.video,
        savedAt: DateTime.utc(2026),
        fileType: DownloadFileType.video,
        qualityIntent: DownloadQualityIntent.specific,
        qualityTarget: const PortableQualityTarget.video(targetHeight: 1080),
      );

      final resolution = resolveQualityForPlatformPreference(
        preference,
        qualities,
      );

      expect(resolution.quality?.encryptedUrl, 'ytdlp:1080p');
      expect(resolution.canAutoApply, isTrue);
      expect(resolution.warning, isNull);
    });

    test('resolves best available by intent even when text does not match', () {
      final preference = PlatformQualityPreference(
        platform: VideoPlatform.youtube,
        qualityText: 'Old Best Label',
        mediaType: MediaType.video,
        savedAt: DateTime.utc(2026),
        fileType: DownloadFileType.video,
        qualityIntent: DownloadQualityIntent.bestAvailable,
      );

      final resolution = resolveQualityForPlatformPreference(
        preference,
        qualities,
      );

      expect(resolution.quality?.encryptedUrl, 'ytdlp:best:mp4');
      expect(resolution.canAutoApply, isTrue);
    });

    test('resolves audio target as output format plus bitrate', () {
      final preference = PlatformQualityPreference(
        platform: VideoPlatform.youtube,
        qualityText: 'Old audio label',
        mediaType: MediaType.audio,
        savedAt: DateTime.utc(2026),
        fileType: DownloadFileType.audio,
        qualityIntent: DownloadQualityIntent.specific,
        qualityTarget: const PortableQualityTarget.audio(
          outputFormat: 'm4a',
          targetBitrateKbps: 256,
        ),
      );

      final resolution = resolveQualityForPlatformPreference(preference, const [
        Quality(
          qualityText: 'Audio - M4A (AAC)',
          size: 'Apple format, better quality',
          encryptedUrl: 'ytdlp:audio:m4a',
          mediaType: MediaType.audio,
          isAudioOnly: true,
        ),
      ]);

      expect(resolution.canAutoApply, isTrue);
      expect(resolution.quality?.encryptedUrl, 'ytdlp:audio:m4a');
      // qualityText is now i18n-keyed; assert stable identifiers + tbr only.
      expect(resolution.quality?.tbr, 256);
    });

    test('resolves lossless audio target without bitrate', () {
      final preference = PlatformQualityPreference(
        platform: VideoPlatform.youtube,
        qualityText: 'Old WAV label',
        mediaType: MediaType.audio,
        savedAt: DateTime.utc(2026),
        fileType: DownloadFileType.audio,
        qualityIntent: DownloadQualityIntent.specific,
        qualityTarget: const PortableQualityTarget.audio(outputFormat: 'wav'),
      );

      final resolution = resolveQualityForPlatformPreference(preference, const [
        Quality(
          qualityText: 'Audio - WAV',
          size: 'Uncompressed audio',
          encryptedUrl: 'ytdlp:audio:wav',
          mediaType: MediaType.audio,
          isAudioOnly: true,
        ),
      ]);

      expect(resolution.canAutoApply, isTrue);
      expect(resolution.quality?.encryptedUrl, 'ytdlp:audio:wav');
      // qualityText is now i18n-keyed; assert stable identifiers + tbr only.
      expect(resolution.quality?.tbr, isNull);
    });

    test('does not replay non-portable technical stream intent', () {
      final preference = PlatformQualityPreference(
        platform: VideoPlatform.youtube,
        qualityText: 'HD',
        mediaType: MediaType.video,
        savedAt: DateTime.utc(2026),
        fileType: DownloadFileType.video,
        qualityIntent: DownloadQualityIntent.technicalStream,
      );

      final resolution = resolveQualityForPlatformPreference(
        preference,
        qualities,
      );

      expect(resolution.quality, isNull);
      expect(resolution.canAutoApply, isFalse);
    });

    test('falls back to nearest lower video target with warning', () {
      final preference = PlatformQualityPreference(
        platform: VideoPlatform.youtube,
        qualityText: 'Old 1080p label',
        mediaType: MediaType.video,
        savedAt: DateTime.utc(2026),
        fileType: DownloadFileType.video,
        qualityIntent: DownloadQualityIntent.specific,
        qualityTarget: const PortableQualityTarget.video(targetHeight: 1080),
      );

      final resolution = resolveQualityForPlatformPreference(preference, const [
        Quality(
          qualityText: 'Best (4K)',
          size: '512 MB',
          encryptedUrl: 'ytdlp:best:mp4',
          mediaType: MediaType.video,
        ),
        Quality(
          qualityText: 'HD',
          size: '120 MB',
          encryptedUrl: 'ytdlp:720p',
          mediaType: MediaType.video,
        ),
        Quality(
          qualityText: 'SD',
          size: '80 MB',
          encryptedUrl: 'ytdlp:480p',
          mediaType: MediaType.video,
        ),
      ]);

      expect(resolution.quality?.encryptedUrl, 'ytdlp:720p');
      expect(resolution.canAutoApply, isTrue);
      expect(
        resolution.warning?.code,
        FormatSelectionWarningCode.exactUnavailable,
      );
      expect(resolution.warning?.requestedLabel, '1080p');
      expect(resolution.warning?.resolvedLabel, '720p');
    });

    test(
      'does not fall back to first quality when saved media type is absent',
      () {
        final preference = PlatformQualityPreference(
          platform: VideoPlatform.youtube,
          qualityText: '1080p',
          mediaType: MediaType.video,
          savedAt: DateTime.utc(2026),
          fileType: DownloadFileType.video,
          qualityIntent: DownloadQualityIntent.specific,
          qualityTarget: const PortableQualityTarget.video(targetHeight: 1080),
        );

        final resolution =
            resolveQualityForPlatformPreference(preference, const [
              Quality(
                qualityText: 'Audio - MP3',
                size: '12 MB',
                encryptedUrl: 'ytdlp:audio:mp3',
                mediaType: MediaType.audio,
              ),
            ]);

        expect(resolution.quality, isNull);
        expect(resolution.canAutoApply, isFalse);
      },
    );

    test('best available uses tallest video even when first item is audio', () {
      final preference = PlatformQualityPreference(
        platform: VideoPlatform.youtube,
        qualityText: 'Old best label',
        mediaType: MediaType.video,
        savedAt: DateTime.utc(2026),
        fileType: DownloadFileType.video,
        qualityIntent: DownloadQualityIntent.bestAvailable,
      );

      final resolution = resolveQualityForPlatformPreference(preference, const [
        Quality(
          qualityText: 'Audio - MP3',
          size: '12 MB',
          encryptedUrl: 'ytdlp:audio:mp3',
          mediaType: MediaType.audio,
        ),
        Quality(
          qualityText: '720p',
          size: '120 MB',
          encryptedUrl: 'ytdlp:720p',
          mediaType: MediaType.video,
        ),
        Quality(
          qualityText: '1080p',
          size: '220 MB',
          encryptedUrl: 'ytdlp:1080p',
          mediaType: MediaType.video,
        ),
      ]);

      expect(resolution.quality?.encryptedUrl, 'ytdlp:1080p');
      expect(resolution.canAutoApply, isTrue);
    });
  });
}
