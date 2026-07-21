import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:svid/features/downloads/data/datasources/ytdlp_datasource.dart';

/// RC10 Q-round C3 — pin the final-extension guard helper that
/// powers the three-layer defense:
///   1. Datasource pre-move guard (ytdlp_datasource.dart, before
///      _moveFilesToOutputDir): primary, blocks wrong-extension
///      files from ever reaching the user's Downloads folder.
///   2. Fresh-path use-case guard (start_download_usecase.dart,
///      between integrity and completeDownload): defense-in-depth.
///   3. Retry-path repository guard (download_repository_impl.dart,
///      _retryYtdlpDownload, same window): retry mirror per
///      [[feedback_mirror_path_diff_line_by_line]].
///
/// All three sites call the same pure helper —
/// `YtDlpDataSource.detectFinalExtensionMismatch`.
void main() {
  group('detectFinalExtensionMismatch — video native containers', () {
    test('WebM expected + .webm output → no mismatch', () {
      final result = YtDlpDataSource.detectFinalExtensionMismatch(
        outputPath: '/downloads/video.webm',
        videoFormat: 'webm',
      );
      expect(result, isNull);
    });

    test('WebM expected + .mp4 output → MISMATCH (the production bug)', () {
      // The exact 2026-05-25 vidcombo log scenario: TikTok user picked
      // WebM, platform fallback forced MP4, the file landed as .mp4.
      // C3 must catch this BEFORE move.
      final result = YtDlpDataSource.detectFinalExtensionMismatch(
        outputPath: '/temp/tiktok_video.mp4',
        videoFormat: 'webm',
      );
      expect(result, isNotNull);
      expect(result!.expected, 'webm');
      expect(result.actual, 'mp4');
    });

    test('MP4 expected + .mp4 output → no mismatch', () {
      final result = YtDlpDataSource.detectFinalExtensionMismatch(
        outputPath: '/downloads/video.mp4',
        videoFormat: 'mp4',
      );
      expect(result, isNull);
    });

    test('MKV expected + .mp4 output → MISMATCH', () {
      final result = YtDlpDataSource.detectFinalExtensionMismatch(
        outputPath: '/downloads/video.mp4',
        videoFormat: 'mkv',
      );
      expect(result, isNotNull);
      expect(result!.expected, 'mkv');
      expect(result.actual, 'mp4');
    });

    test('Case-insensitive: .WebM file with webm expected → no mismatch', () {
      final result = YtDlpDataSource.detectFinalExtensionMismatch(
        outputPath: '/downloads/video.WebM',
        videoFormat: 'webm',
      );
      expect(result, isNull);
    });

    test('Case-insensitive: webm file with WEBM expected → no mismatch', () {
      final result = YtDlpDataSource.detectFinalExtensionMismatch(
        outputPath: '/downloads/video.webm',
        videoFormat: 'WEBM',
      );
      expect(result, isNull);
    });
  });

  group('detectFinalExtensionMismatch — audio extraction', () {
    test('audio mp3 expected + .mp3 output → no mismatch', () {
      final result = YtDlpDataSource.detectFinalExtensionMismatch(
        outputPath: '/downloads/song.mp3',
        audioFormat: 'mp3',
        extractAudio: true,
      );
      expect(result, isNull);
    });

    test('audio opus expected + .m4a output → MISMATCH', () {
      // Audio extraction sometimes silently stream-copies when the
      // codec already matches the user's pick, but if the file ends
      // up with the wrong extension we want it caught.
      final result = YtDlpDataSource.detectFinalExtensionMismatch(
        outputPath: '/downloads/song.m4a',
        audioFormat: 'opus',
        extractAudio: true,
      );
      expect(result, isNotNull);
      expect(result!.expected, 'opus');
      expect(result.actual, 'm4a');
    });

    test('extractAudio=true skips videoFormat field even if provided', () {
      // Defensive: the guard scope rule is "audio path uses
      // audioFormat, video path uses videoFormat". A retry that
      // carries both must consult only the relevant one.
      final result = YtDlpDataSource.detectFinalExtensionMismatch(
        outputPath: '/downloads/song.mp3',
        videoFormat: 'webm', // present but irrelevant for audio
        audioFormat: 'mp3',
        extractAudio: true,
      );
      expect(result, isNull);
    });
  });

  group('detectFinalExtensionMismatch — scope and edge cases', () {
    test('empty outputPath → null (nothing to check)', () {
      final result = YtDlpDataSource.detectFinalExtensionMismatch(
        outputPath: '',
        videoFormat: 'webm',
      );
      expect(result, isNull);
    });

    test('null videoFormat (video path) → null (caller didnt enforce)', () {
      final result = YtDlpDataSource.detectFinalExtensionMismatch(
        outputPath: '/downloads/video.mp4',
        videoFormat: null,
      );
      expect(result, isNull);
    });

    test('empty videoFormat → null', () {
      final result = YtDlpDataSource.detectFinalExtensionMismatch(
        outputPath: '/downloads/video.mp4',
        videoFormat: '',
      );
      expect(result, isNull);
    });

    test('file with no extension → MISMATCH (suspicious)', () {
      // A "video" file without an extension on disk is suspicious;
      // mark mismatch with empty actual so caller surfaces a clear
      // error rather than silently completing.
      final result = YtDlpDataSource.detectFinalExtensionMismatch(
        outputPath: '/downloads/unnamed-video',
        videoFormat: 'webm',
      );
      expect(result, isNotNull);
      expect(result!.expected, 'webm');
      expect(result.actual, '');
    });

    test('extractAudio=false default reads videoFormat', () {
      final result = YtDlpDataSource.detectFinalExtensionMismatch(
        outputPath: '/downloads/video.mkv',
        videoFormat: 'mp4',
        // extractAudio defaults false
      );
      expect(result, isNotNull);
      expect(result!.expected, 'mp4');
      expect(result.actual, 'mkv');
    });
  });

  group('detectResolutionCapViolation — soft -S res:H hard guard', () {
    test('landscape 1920x1080 with max 1080 passes', () {
      final result = YtDlpDataSource.detectResolutionCapViolation(
        maxShortSide: 1080,
        width: 1920,
        height: 1080,
      );
      expect(result, isNull);
    });

    test('portrait 1080x1920 with max 1080 passes', () {
      final result = YtDlpDataSource.detectResolutionCapViolation(
        maxShortSide: 1080,
        width: 1080,
        height: 1920,
      );
      expect(result, isNull);
    });

    test('1440p output with max 1080 is rejected', () {
      final result = YtDlpDataSource.detectResolutionCapViolation(
        maxShortSide: 1080,
        width: 2560,
        height: 1440,
      );
      expect(result, isNotNull);
      expect(result!.expectedMaxShortSide, 1080);
      expect(result.actualShortSide, 1440);
    });

    test('unknown dimensions with max 1080 are rejected fail-closed', () {
      final result = YtDlpDataSource.detectResolutionCapViolation(
        maxShortSide: 1080,
        width: null,
        height: null,
      );
      expect(result, isNotNull);
      expect(result!.dimensionsUnavailable, isTrue);
      expect(result.expectedMaxShortSide, 1080);
    });

    test('audio extraction is out of scope', () {
      final result = YtDlpDataSource.detectResolutionCapViolation(
        maxShortSide: 1080,
        width: 2560,
        height: 1440,
        extractAudio: true,
      );
      expect(result, isNull);
    });

    // ── F1 fix: in-tier non-standard heights must NOT false-fail ──
    // The cap is a bucketed tier anchor; a real height that buckets DOWN
    // to that tier (768→"720p", 540→"480p", 1152→"1080p") used to exceed
    // its own bucketed cap and get the correct file deleted.
    test('F1 — 768@720-tier in-tier height passes (was false-fail)', () {
      expect(
        YtDlpDataSource.detectResolutionCapViolation(
          maxShortSide: 720,
          width: 1366,
          height: 768,
        ),
        isNull,
      );
    });

    test('F1 — 540@480 / 1152@1080 / 900@720 in-tier all pass', () {
      expect(
        YtDlpDataSource.detectResolutionCapViolation(
          maxShortSide: 480,
          width: 1024,
          height: 540,
        ),
        isNull,
      );
      expect(
        YtDlpDataSource.detectResolutionCapViolation(
          maxShortSide: 1080,
          width: 2048,
          height: 1152,
        ),
        isNull,
      );
      expect(
        YtDlpDataSource.detectResolutionCapViolation(
          maxShortSide: 720,
          width: 1600,
          height: 900,
        ),
        isNull,
      );
    });

    // ── F1 anti-regression: GENUINE cross-tier overrun STILL fails ──
    // Proves the fix is not a no-op. 1440@1080 already covered above;
    // add tier siblings + the exact boundary.
    test('F1 anti-regression — genuine overrun still rejected', () {
      expect(
        YtDlpDataSource.detectResolutionCapViolation(
          maxShortSide: 480,
          width: 1280,
          height: 720,
        ),
        isNotNull,
        reason: '720 > 480-tier ceiling 699 — a real cross-tier overrun',
      );
      expect(
        YtDlpDataSource.detectResolutionCapViolation(
          maxShortSide: 720,
          width: 1920,
          height: 1080,
        ),
        isNotNull,
      );
    });

    test('F1 tier-boundary exactness — 1439 passes, 1440 fails (1080 tier)',
        () {
      expect(
        YtDlpDataSource.detectResolutionCapViolation(
          maxShortSide: 1080,
          width: 2558,
          height: 1439,
        ),
        isNull,
      );
      expect(
        YtDlpDataSource.detectResolutionCapViolation(
          maxShortSide: 1080,
          width: 2560,
          height: 1440,
        ),
        isNotNull,
      );
    });

    test('F1 — a TRUE measured (non-anchor) cap keeps an exact bound', () {
      // 1000 is not a tier anchor → exact cap, 1001 exceeds it.
      expect(
        YtDlpDataSource.detectResolutionCapViolation(
          maxShortSide: 1000,
          width: 1780,
          height: 1001,
        ),
        isNotNull,
      );
    });
  });

  group('postprocessor final-path promotion', () {
    test('parses VideoRemuxer destination path from yt-dlp output', () {
      final result = YtDlpDataSource.postProcessorDestinationForTest(
        '[VideoRemuxer] Remuxing video from mp4 to mkv; Destination: '
        '/tmp/downloads/video [Best (1080p)].mkv',
      );

      expect(result, '/tmp/downloads/video [Best (1080p)].mkv');
    });

    test('ignores VideoRemuxer line when no destination was emitted', () {
      final result = YtDlpDataSource.postProcessorDestinationForTest(
        '[VideoRemuxer] Not remuxing media file "video.mp4"; '
        'already is in target format mp4',
      );

      expect(result, isNull);
    });

    test('parses VideoConvertor destination path from yt-dlp output', () {
      final result = YtDlpDataSource.postProcessorDestinationForTest(
        '[VideoConvertor] Converting video from mkv to avi; Destination: '
        '"/tmp/downloads/video [Best (1080p)].avi"',
      );

      expect(result, '/tmp/downloads/video [Best (1080p)].avi');
    });

    test(
      'promotes remuxed MKV over stale MP4 sidecar before C3 guard',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'ytdlp_remux_final_path_test_',
        );
        try {
          final staleMp4 = File(path.join(tempDir.path, 'video.mp4'));
          final finalMkv = File(path.join(tempDir.path, 'video.mkv'));
          await staleMp4.writeAsString('source mp4');
          await Future<void>.delayed(const Duration(milliseconds: 5));
          await finalMkv.writeAsString('remuxed mkv');

          final promoted =
              await YtDlpDataSource.promoteExpectedExtensionForTest(
                isolatedTempDir: tempDir.path,
                resolvedOutputFile: staleMp4.path,
                videoFormat: 'mkv',
              );

          expect(promoted, finalMkv.path);
          expect(
            YtDlpDataSource.detectFinalExtensionMismatch(
              outputPath: promoted!,
              videoFormat: 'mkv',
            ),
            isNull,
          );
        } finally {
          await tempDir.delete(recursive: true);
        }
      },
    );

    test(
      'promotes extracted audio over stale video sidecar before C3 guard',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'ytdlp_audio_final_path_test_',
        );
        try {
          final staleMp4 = File(path.join(tempDir.path, 'video.mp4'));
          final finalMp3 = File(path.join(tempDir.path, 'song.mp3'));
          await staleMp4.writeAsString('source video');
          await Future<void>.delayed(const Duration(milliseconds: 5));
          await finalMp3.writeAsString('extracted audio');

          final promoted =
              await YtDlpDataSource.promoteExpectedExtensionForTest(
                isolatedTempDir: tempDir.path,
                resolvedOutputFile: staleMp4.path,
                audioFormat: 'mp3',
                extractAudio: true,
              );

          expect(promoted, finalMp3.path);
          expect(
            YtDlpDataSource.detectFinalExtensionMismatch(
              outputPath: promoted!,
              audioFormat: 'mp3',
              extractAudio: true,
            ),
            isNull,
          );
        } finally {
          await tempDir.delete(recursive: true);
        }
      },
    );

    test(
      'does not promote DASH intermediate as a final remux target',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'ytdlp_remux_intermediate_test_',
        );
        try {
          final staleMp4 = File(path.join(tempDir.path, 'video.mp4'));
          final dashMkv = File(path.join(tempDir.path, 'video.f137.mkv'));
          await staleMp4.writeAsString('source mp4');
          await dashMkv.writeAsString('dash intermediate');

          final promoted =
              await YtDlpDataSource.promoteExpectedExtensionForTest(
                isolatedTempDir: tempDir.path,
                resolvedOutputFile: staleMp4.path,
                videoFormat: 'mkv',
              );

          expect(promoted, staleMp4.path);
          expect(
            YtDlpDataSource.detectFinalExtensionMismatch(
              outputPath: promoted!,
              videoFormat: 'mkv',
            ),
            isNotNull,
          );
        } finally {
          await tempDir.delete(recursive: true);
        }
      },
    );
  });
}
