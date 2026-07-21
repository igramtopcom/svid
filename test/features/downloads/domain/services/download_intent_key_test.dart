import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/domain/entities/download_config.dart';
import 'package:ssvid/features/downloads/domain/entities/download_entity.dart';
import 'package:ssvid/features/downloads/domain/entities/download_status.dart';
import 'package:ssvid/features/downloads/domain/entities/video_info.dart';
import 'package:ssvid/features/downloads/domain/services/download_intent_key.dart';
import 'package:ssvid/features/settings/domain/enums/container_format_preference.dart';

/// RC10 Blocker 3 of Ultra Plan v3 — pin DownloadIntentKey contract.
/// Shared duplicate-detection key used by Home + Floating Capture +
/// Archive Warning so all surfaces agree on what counts as "same
/// download". MP4 1080p must NOT be flagged as duplicate of WebM
/// 1080p — that's the central regression these tests guard.
void main() {
  VideoInfo videoInfo(String url) => VideoInfo(
    url: url,
    title: 'test',
    availableQualities: const [],
    thumbnail: null,
    duration: const Duration(seconds: 0),
  );

  Quality videoQuality(String label, {String? vcodec, String? acodec}) =>
      Quality(
        qualityText: label,
        size: '10 MB',
        encryptedUrl: 'ytdlp:test',
        mediaType: MediaType.video,
        vcodec: vcodec,
        acodec: acodec,
      );

  DownloadConfig configFor(ContainerFormatPreference container) =>
      DownloadConfig(
        selectedQualities: const [],
        fileType: DownloadFileType.video,
        containerFormatOverride: container,
      );

  group('DownloadIntentKey.fromRequest — video flows', () {
    test('MP4 1080p vs WebM 1080p — DIFFERENT (Blocker 3 regression)', () {
      // The exact bug Codex identified: pre-RC10 these were treated
      // as duplicate because comparison was URL + qualityLabel only.
      final mp4 = DownloadIntentKey.fromRequest(
        videoInfo: videoInfo('https://youtube.com/watch?v=abc'),
        quality: videoQuality('1080p'),
        config: configFor(ContainerFormatPreference.mp4),
      );
      final webm = DownloadIntentKey.fromRequest(
        videoInfo: videoInfo('https://youtube.com/watch?v=abc'),
        quality: videoQuality('1080p'),
        config: configFor(ContainerFormatPreference.webm),
      );
      expect(
        mp4.matches(webm),
        isFalse,
        reason: 'MP4 1080p and WebM 1080p are DIFFERENT intents',
      );
      expect(mp4 == webm, isFalse);
    });

    test('Same container + same quality + same URL → DUPLICATE', () {
      final a = DownloadIntentKey.fromRequest(
        videoInfo: videoInfo('https://youtube.com/watch?v=abc'),
        quality: videoQuality('1080p'),
        config: configFor(ContainerFormatPreference.mp4),
      );
      final b = DownloadIntentKey.fromRequest(
        videoInfo: videoInfo('https://youtube.com/watch?v=abc'),
        quality: videoQuality('1080p'),
        config: configFor(ContainerFormatPreference.mp4),
      );
      expect(a.matches(b), isTrue);
      expect(a, b);
    });

    test('Different quality (1080p vs 720p) same container → DIFFERENT', () {
      final hd = DownloadIntentKey.fromRequest(
        videoInfo: videoInfo('https://youtube.com/watch?v=abc'),
        quality: videoQuality('1080p'),
        config: configFor(ContainerFormatPreference.mp4),
      );
      final hdLower = DownloadIntentKey.fromRequest(
        videoInfo: videoInfo('https://youtube.com/watch?v=abc'),
        quality: videoQuality('720p'),
        config: configFor(ContainerFormatPreference.mp4),
      );
      expect(hd.matches(hdLower), isFalse);
    });

    test('URL tracking params normalized → SAME', () {
      final a = DownloadIntentKey.fromRequest(
        videoInfo: videoInfo(
          'https://youtube.com/watch?v=abc&utm_source=share',
        ),
        quality: videoQuality('1080p'),
        config: configFor(ContainerFormatPreference.mp4),
      );
      final b = DownloadIntentKey.fromRequest(
        videoInfo: videoInfo('https://youtube.com/watch?v=abc&fbclid=xyz'),
        quality: videoQuality('1080p'),
        config: configFor(ContainerFormatPreference.mp4),
      );
      expect(
        a.matches(b),
        isTrue,
        reason: 'Tracking params must NOT split duplicate detection',
      );
    });

    test('Empty qualityLabel → never matches (defensive)', () {
      final a = DownloadIntentKey.fromRequest(
        videoInfo: videoInfo('https://youtube.com/watch?v=abc'),
        quality: videoQuality(''),
        config: configFor(ContainerFormatPreference.mp4),
      );
      final b = DownloadIntentKey.fromRequest(
        videoInfo: videoInfo('https://youtube.com/watch?v=abc'),
        quality: videoQuality(''),
        config: configFor(ContainerFormatPreference.mp4),
      );
      expect(
        a.matches(b),
        isFalse,
        reason:
            'Empty qualityLabel bails to "not a duplicate" — '
            'legacy behavior preserved',
      );
    });

    test('Case-insensitive qualityLabel match', () {
      final a = DownloadIntentKey.fromRequest(
        videoInfo: videoInfo('https://youtube.com/watch?v=abc'),
        quality: videoQuality('1080P'),
        config: configFor(ContainerFormatPreference.mp4),
      );
      final b = DownloadIntentKey.fromRequest(
        videoInfo: videoInfo('https://youtube.com/watch?v=abc'),
        quality: videoQuality('1080p'),
        config: configFor(ContainerFormatPreference.mp4),
      );
      expect(a.matches(b), isTrue);
    });
  });

  group('isDuplicateOfActive', () {
    DownloadEntity entity({
      required String url,
      required String filename,
      required DownloadStatus status,
      String? qualityLabel = '1080p',
    }) => DownloadEntity(
      id: 1,
      url: url,
      filename: filename,
      savePath: '/tmp',
      status: status,
      totalBytes: 0,
      downloadedBytes: 0,
      speed: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      qualityLabel: qualityLabel,
      sourceUrl: url,
    );

    test('Cancelled row → NOT a duplicate (retry path allowed)', () {
      final proposed = DownloadIntentKey.fromRequest(
        videoInfo: videoInfo('https://youtube.com/watch?v=abc'),
        quality: videoQuality('1080p'),
        config: configFor(ContainerFormatPreference.mp4),
      );
      final existing = entity(
        url: 'https://youtube.com/watch?v=abc',
        filename: 'video.mp4',
        status: DownloadStatus.cancelled,
      );
      expect(isDuplicateOfActive(proposed, existing), isFalse);
    });

    test('Failed row → NOT a duplicate (retry path allowed)', () {
      final proposed = DownloadIntentKey.fromRequest(
        videoInfo: videoInfo('https://youtube.com/watch?v=abc'),
        quality: videoQuality('1080p'),
        config: configFor(ContainerFormatPreference.mp4),
      );
      final existing = entity(
        url: 'https://youtube.com/watch?v=abc',
        filename: 'video.mp4',
        status: DownloadStatus.failed,
      );
      expect(isDuplicateOfActive(proposed, existing), isFalse);
    });

    test('Completed MP4 1080p row → DUPLICATE of new MP4 1080p intent', () {
      final proposed = DownloadIntentKey.fromRequest(
        videoInfo: videoInfo('https://youtube.com/watch?v=abc'),
        quality: videoQuality('1080p'),
        config: configFor(ContainerFormatPreference.mp4),
      );
      final existing = entity(
        url: 'https://youtube.com/watch?v=abc',
        filename: 'video.mp4',
        status: DownloadStatus.completed,
      );
      expect(isDuplicateOfActive(proposed, existing), isTrue);
    });

    test(
      'Completed WebM 1080p row → NOT a duplicate of new MP4 1080p intent',
      () {
        // Blocker 3 regression: this case incorrectly returned true
        // pre-RC10 because comparison was on qualityLabel only.
        final proposed = DownloadIntentKey.fromRequest(
          videoInfo: videoInfo('https://youtube.com/watch?v=abc'),
          quality: videoQuality('1080p'),
          config: configFor(ContainerFormatPreference.mp4),
        );
        final existingWebm = entity(
          url: 'https://youtube.com/watch?v=abc',
          filename: 'video.webm',
          status: DownloadStatus.completed,
        );
        expect(
          isDuplicateOfActive(proposed, existingWebm),
          isFalse,
          reason:
              'Pre-RC10 falsely flagged this; RC10 separates by '
              'container extension',
        );
      },
    );
  });

  group(
    'DownloadIntentKey.archiveFileSuffix — RC10 Codex-round-3 full intent',
    () {
      test('video pulls segment by quality + container', () {
        final mp4_1080 = DownloadIntentKey.archiveFileSuffix(
          mediaType: MediaType.video,
          container: ContainerFormatPreference.mp4,
          qualityLabel: '1080p',
        );
        final mp4_720 = DownloadIntentKey.archiveFileSuffix(
          mediaType: MediaType.video,
          container: ContainerFormatPreference.mp4,
          qualityLabel: '720p',
        );
        final webm_1080 = DownloadIntentKey.archiveFileSuffix(
          mediaType: MediaType.video,
          container: ContainerFormatPreference.webm,
          qualityLabel: '1080p',
        );
        expect(mp4_1080, '_video_1080p_mp4');
        expect(mp4_720, '_video_720p_mp4');
        expect(webm_1080, '_video_1080p_webm');
        // No two distinct intents share a suffix.
        expect({mp4_1080, mp4_720, webm_1080}.length, 3);
      });

      test('audio pulls segment by format + bitrate', () {
        final mp3_320 = DownloadIntentKey.archiveFileSuffix(
          mediaType: MediaType.audio,
          container: ContainerFormatPreference.mp4,
          qualityLabel: 'Audio Only',
          audioFormat: 'mp3',
          audioBitrateKbps: 320,
        );
        final mp3_192 = DownloadIntentKey.archiveFileSuffix(
          mediaType: MediaType.audio,
          container: ContainerFormatPreference.mp4,
          qualityLabel: 'Audio Only',
          audioFormat: 'mp3',
          audioBitrateKbps: 192,
        );
        final m4a_192 = DownloadIntentKey.archiveFileSuffix(
          mediaType: MediaType.audio,
          container: ContainerFormatPreference.mp4,
          qualityLabel: 'Audio Only',
          audioFormat: 'm4a',
          audioBitrateKbps: 192,
        );
        expect(mp3_320, '_audio_mp3_320k');
        expect(mp3_192, '_audio_mp3_192k');
        expect(m4a_192, '_audio_m4a_192k');
        expect({mp3_320, mp3_192, m4a_192}.length, 3);
      });

      test('audio with bitrate=0 omits bitrate segment (legacy auto)', () {
        final mp3Auto = DownloadIntentKey.archiveFileSuffix(
          mediaType: MediaType.audio,
          container: ContainerFormatPreference.mp4,
          qualityLabel: 'Audio Only',
          audioFormat: 'mp3',
          audioBitrateKbps: 0,
        );
        expect(mp3Auto, '_audio_mp3');
      });

      test('audio with empty format falls back to "auto"', () {
        final auto = DownloadIntentKey.archiveFileSuffix(
          mediaType: MediaType.audio,
          container: ContainerFormatPreference.mp4,
          qualityLabel: 'Audio Only',
        );
        expect(auto, '_audio_auto');
      });

      test(
        'arbitrary quality labels are sanitized to filesystem-safe tokens',
        () {
          final best4k = DownloadIntentKey.archiveFileSuffix(
            mediaType: MediaType.video,
            container: ContainerFormatPreference.mp4,
            qualityLabel: 'Best (4K 60fps)',
          );
          expect(best4k, '_video_best_4k_60fps_mp4');
        },
      );

      test('image and subtitle suffixes', () {
        expect(
          DownloadIntentKey.archiveFileSuffix(
            mediaType: MediaType.image,
            container: ContainerFormatPreference.mp4,
            qualityLabel: '',
          ),
          '_image',
        );
        expect(
          DownloadIntentKey.archiveFileSuffix(
            mediaType: MediaType.subtitle,
            container: ContainerFormatPreference.mp4,
            qualityLabel: '',
          ),
          '',
        );
      });

      test('Codex-round-5: section dimension splits clip from whole video', () {
        // Whole video MP4 1080p — empty section keeps legacy suffix shape.
        final whole = DownloadIntentKey.archiveFileSuffix(
          mediaType: MediaType.video,
          container: ContainerFormatPreference.mp4,
          qualityLabel: '1080p',
          section: '',
        );
        // Clip of the SAME video — different intent, different archive.
        final clip = DownloadIntentKey.archiveFileSuffix(
          mediaType: MediaType.video,
          container: ContainerFormatPreference.mp4,
          qualityLabel: '1080p',
          section: 'section:60000-120000',
        );
        expect(whole, '_video_1080p_mp4');
        expect(clip, '_video_1080p_mp4_section_60000_120000');
        expect(whole == clip, isFalse,
            reason:
                'Whole-video pull MUST NOT share archive with a clip pull');
      });

      test('archiveSuffix() instance method derives section from this.section',
          () {
        // Build an intent key with a section scope via fromRequest +
        // verify the instance method picks it up.
        final clipKey = DownloadIntentKey.fromRequest(
          videoInfo: videoInfo('https://youtube.com/watch?v=abc'),
          quality: videoQuality('1080p'),
          config: DownloadConfig(
            selectedQualities: const [],
            fileType: DownloadFileType.video,
            containerFormatOverride: ContainerFormatPreference.mp4,
            sectionStartTime: const Duration(seconds: 60),
            sectionEndTime: const Duration(seconds: 120),
          ),
        );
        // The instance helper should produce the same string as the
        // static helper called with the same dimensions — single source
        // of truth between duplicate detection and archive scoping.
        expect(
          clipKey.archiveSuffix(),
          '_video_1080p_mp4_section_60000_120000',
        );
      });
    },
  );

  group('DownloadIntentKey hashCode + ==', () {
    test('Set-based deduplication works', () {
      final keys = <DownloadIntentKey>{
        DownloadIntentKey.fromRequest(
          videoInfo: videoInfo('https://youtube.com/watch?v=abc'),
          quality: videoQuality('1080p'),
          config: configFor(ContainerFormatPreference.mp4),
        ),
        // Same intent — should de-dupe in set
        DownloadIntentKey.fromRequest(
          videoInfo: videoInfo('https://youtube.com/watch?v=abc'),
          quality: videoQuality('1080p'),
          config: configFor(ContainerFormatPreference.mp4),
        ),
        // Different container — should NOT de-dupe
        DownloadIntentKey.fromRequest(
          videoInfo: videoInfo('https://youtube.com/watch?v=abc'),
          quality: videoQuality('1080p'),
          config: configFor(ContainerFormatPreference.webm),
        ),
      };
      expect(
        keys.length,
        2,
        reason: 'Set should contain 2 distinct intents (MP4 + WebM)',
      );
    });
  });
}
