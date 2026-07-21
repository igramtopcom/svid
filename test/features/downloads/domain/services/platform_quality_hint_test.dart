import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/core/utils/platform_detector.dart';
import 'package:ssvid/features/downloads/domain/entities/video_info.dart';
import 'package:ssvid/features/downloads/domain/services/platform_quality_hint.dart';

VideoInfo _info({required List<Quality> qualities}) => VideoInfo(
      title: 'test',
      url: 'https://example.test/video',
      availableQualities: qualities,
    );

Quality _q(String label, {bool audioOnly = false}) => Quality(
      qualityText: label,
      size: '',
      encryptedUrl: 'ytdlp:test',
      mediaType: MediaType.video,
      isAudioOnly: audioOnly,
    );

void main() {
  group('shouldHintLoginForHq — positive cases', () {
    test(
      'Bilibili + max 480p + no cookies → emit hint',
      () {
        final info = _info(qualities: [
          _q('MP4 360p [640x360]'),
          _q('MP4 480p [854x480]'),
        ]);
        expect(
          PlatformQualityHint.shouldHintLoginForHq(
            platform: VideoPlatform.bilibili,
            videoInfo: info,
            hasCookiesForPlatform: false,
          ),
          isTrue,
        );
      },
    );

    test('Bilibili + max 360p + no cookies → emit hint', () {
      final info = _info(qualities: [_q('MP4 360p [640x360]')]);
      expect(
        PlatformQualityHint.shouldHintLoginForHq(
          platform: VideoPlatform.bilibili,
          videoInfo: info,
          hasCookiesForPlatform: false,
        ),
        isTrue,
      );
    });

    test('Bilibili + label "Best (480p)" + no cookies → emit hint', () {
      final info = _info(qualities: [_q('Best (480p)')]);
      expect(
        PlatformQualityHint.shouldHintLoginForHq(
          platform: VideoPlatform.bilibili,
          videoInfo: info,
          hasCookiesForPlatform: false,
        ),
        isTrue,
      );
    });
  });

  group('shouldHintLoginForHq — negative cases', () {
    test('Bilibili + 1080p available + no cookies → no hint (already HQ)', () {
      final info = _info(qualities: [
        _q('MP4 480p [854x480]'),
        _q('MP4 720p [1280x720]'),
        _q('MP4 1080p [1920x1080]'),
      ]);
      expect(
        PlatformQualityHint.shouldHintLoginForHq(
          platform: VideoPlatform.bilibili,
          videoInfo: info,
          hasCookiesForPlatform: false,
        ),
        isFalse,
      );
    });

    test('Bilibili + max 480p + cookies present → no hint (user already signed in)', () {
      final info = _info(qualities: [_q('MP4 480p [854x480]')]);
      expect(
        PlatformQualityHint.shouldHintLoginForHq(
          platform: VideoPlatform.bilibili,
          videoInfo: info,
          hasCookiesForPlatform: true,
        ),
        isFalse,
      );
    });

    test('YouTube + max 480p + no cookies → no hint (not in gated list)', () {
      // YouTube quality clamps come from a different cause (Premium /
      // age-gate / private). Not the same code path; not in the
      // positive list. Production reports show no symmetric
      // complaint for YouTube SD-only.
      final info = _info(qualities: [_q('MP4 480p [854x480]')]);
      expect(
        PlatformQualityHint.shouldHintLoginForHq(
          platform: VideoPlatform.youtube,
          videoInfo: info,
          hasCookiesForPlatform: false,
        ),
        isFalse,
      );
    });

    test('Bilibili + audio-only qualities (no video heights) → no hint', () {
      // Music-only / audio-only Bilibili extracts have no video
      // height; the helper must not falsely trip on missing data.
      final info = _info(qualities: [
        _q('MP3 128kbps', audioOnly: true),
        _q('M4A 192kbps', audioOnly: true),
      ]);
      expect(
        PlatformQualityHint.shouldHintLoginForHq(
          platform: VideoPlatform.bilibili,
          videoInfo: info,
          hasCookiesForPlatform: false,
        ),
        isFalse,
      );
    });

    test('Bilibili + empty qualities → no hint (best-effort)', () {
      final info = _info(qualities: const []);
      expect(
        PlatformQualityHint.shouldHintLoginForHq(
          platform: VideoPlatform.bilibili,
          videoInfo: info,
          hasCookiesForPlatform: false,
        ),
        isFalse,
      );
    });
  });

  group('threshold edge cases', () {
    test('Bilibili + exactly 720p available → no hint (threshold exclusive)', () {
      // The threshold is "strictly below 720" so a confirmed 720p
      // signal means the user is already at the entry-level HD tier
      // and additional auth would not buy "much more". Avoids hint
      // fatigue on the SD/HD boundary.
      final info = _info(qualities: [_q('MP4 720p [1280x720]')]);
      expect(
        PlatformQualityHint.shouldHintLoginForHq(
          platform: VideoPlatform.bilibili,
          videoInfo: info,
          hasCookiesForPlatform: false,
        ),
        isFalse,
      );
    });

    test('Bilibili + max 480 via WxH matrix (portrait form) → emit hint', () {
      // Portrait labels (`854x480` shape: width x height) should still
      // give us 480 — the helper uses min(W, H) so both portrait and
      // landscape extract correctly.
      final info = _info(qualities: [_q('MP4 [854x480]')]);
      expect(
        PlatformQualityHint.shouldHintLoginForHq(
          platform: VideoPlatform.bilibili,
          videoInfo: info,
          hasCookiesForPlatform: false,
        ),
        isTrue,
      );
    });

    test('Bilibili + 4K alias in label → no hint (already HQ)', () {
      final info = _info(qualities: [_q('Best (4K)')]);
      expect(
        PlatformQualityHint.shouldHintLoginForHq(
          platform: VideoPlatform.bilibili,
          videoInfo: info,
          hasCookiesForPlatform: false,
        ),
        isFalse,
      );
    });
  });
}
