import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/utils/platform_detector.dart';
import 'package:svid/features/downloads/domain/entities/download_selection_intent.dart';
import 'package:svid/features/downloads/domain/entities/video_info.dart';
import 'package:svid/features/settings/domain/entities/platform_quality_preference.dart';

void main() {
  group('PlatformQualityPreference intent serialization', () {
    test('round-trips file type, quality intent, and portable target', () {
      final preference = PlatformQualityPreference(
        platform: VideoPlatform.youtube,
        qualityText: '1080p',
        mediaType: MediaType.video,
        savedAt: DateTime.utc(2026),
        fileType: DownloadFileType.video,
        qualityIntent: DownloadQualityIntent.specific,
        qualityTarget: const PortableQualityTarget.video(targetHeight: 1080),
      );

      final json = preference.toJson();
      final restored = PlatformQualityPreference.fromJson(json);

      expect(json['fileType'], 'video');
      expect(json['qualityIntent'], 'specific');
      expect(json['qualityTarget'], {
        'fileType': 'video',
        'targetHeight': 1080,
      });
      expect(restored.fileType, DownloadFileType.video);
      expect(restored.qualityIntent, DownloadQualityIntent.specific);
      expect(
        restored.qualityTarget,
        const PortableQualityTarget.video(targetHeight: 1080),
      );
      expect(restored.hasPrimaryIntent, isTrue);
    });

    test('round-trips advanced action overrides', () {
      final preference = PlatformQualityPreference(
        platform: VideoPlatform.youtube,
        qualityText: 'Best available',
        mediaType: MediaType.video,
        savedAt: DateTime.utc(2026),
        embedSubtitles: false,
        includeAutoSubs: true,
        writeThumbnail: true,
        forceRemux: true,
      );

      final json = preference.toJson();
      final restored = PlatformQualityPreference.fromJson(json);

      expect(json['embedSubtitles'], isFalse);
      expect(json['includeAutoSubs'], isTrue);
      expect(json['writeThumbnail'], isTrue);
      expect(json['forceRemux'], isTrue);
      expect(restored.embedSubtitles, isFalse);
      expect(restored.includeAutoSubs, isTrue);
      expect(restored.writeThumbnail, isTrue);
      expect(restored.forceRemux, isTrue);
      expect(restored.hasFormatOverrides, isTrue);
    });

    test('keeps old preferences valid when intent fields are absent', () {
      final restored = PlatformQualityPreference.fromJson({
        'platform': 'youtube',
        'qualityText': '720p',
        'mediaType': 'video',
        'savedAt': DateTime.utc(2026).toIso8601String(),
      });

      expect(restored.fileType, isNull);
      expect(restored.qualityIntent, isNull);
      expect(restored.qualityTarget, isNull);
      expect(restored.hasPrimaryIntent, isFalse);
    });
  });
}
