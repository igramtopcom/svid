import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ssvid/core/errors/result.dart';
import 'package:ssvid/core/utils/platform_detector.dart';
import 'package:ssvid/features/downloads/data/datasources/gallerydl_datasource.dart';
import 'package:ssvid/features/downloads/data/datasources/ytdlp_datasource.dart';
import 'package:ssvid/features/downloads/domain/entities/download_error_code.dart';
import 'package:ssvid/features/downloads/domain/entities/video_info.dart';
import 'package:ssvid/features/downloads/domain/repositories/download_repository.dart';
import 'package:ssvid/features/downloads/domain/usecases/start_download_usecase.dart';
import 'package:ssvid/features/premium/domain/services/download_quota_reserver.dart';

class _MockDownloadRepository extends Mock implements DownloadRepository {}

class _MockYtDlpDataSource extends Mock implements YtDlpDataSource {}

class _MockGalleryDlDataSource extends Mock implements GalleryDlDataSource {}

class _DenyingQuotaReserver implements DownloadQuotaReserver {
  @override
  bool tryConsume({required bool isPremium, int count = 1}) => false;

  @override
  int currentPeriodCount() => 15;

  @override
  int remainingThisWeek({required bool isPremium}) => 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StartDownloadUseCase.inferRawAudioFormat', () {
    Quality rawAudio(String acodec) => Quality(
      qualityText: 'Audio Stream',
      size: '1 MB',
      encryptedUrl: 'ytdlp:raw:251',
      mediaType: MediaType.audio,
      acodec: acodec,
      isAudioOnly: true,
    );

    test('maps opus raw stream to opus output', () {
      expect(
        StartDownloadUseCase.inferRawAudioFormat(rawAudio('opus')),
        'opus',
      );
    });

    test('maps mp4a raw stream to m4a output', () {
      expect(
        StartDownloadUseCase.inferRawAudioFormat(rawAudio('mp4a.40.2')),
        'm4a',
      );
    });

    test('maps aac raw stream to m4a output', () {
      expect(StartDownloadUseCase.inferRawAudioFormat(rawAudio('aac')), 'm4a');
    });

    test('maps aac variants to m4a output', () {
      expect(
        StartDownloadUseCase.inferRawAudioFormat(rawAudio('aac_latm')),
        'm4a',
      );
      expect(StartDownloadUseCase.inferRawAudioFormat(rawAudio('alac')), 'm4a');
    });

    test('returns null for non-audio quality', () {
      const quality = Quality(
        qualityText: '1080p',
        size: '10 MB',
        encryptedUrl: 'ytdlp:raw:137',
        mediaType: MediaType.video,
        vcodec: 'avc1',
      );

      expect(StartDownloadUseCase.inferRawAudioFormat(quality), isNull);
    });
  });

  group('StartDownloadUseCase post-processing timeout policy', () {
    test('keeps legacy 5 minute guard for merge/remux paths', () {
      final timeout = StartDownloadUseCase.postProcessingTimeoutForTest(
        recodeVideo: null,
        selectedHeight: 4320,
        videoDuration: const Duration(hours: 1),
      );

      expect(timeout, const Duration(minutes: 5));
    });

    test('Wave B (AUD-5): extract-audio is exempt from the 5m wall — '
        'lossy -x is a full-duration transcode (same class as recode); '
        'the fixed guard killed long podcasts mid-conversion = the '
        'standing 74 audio-MP3-timeout telemetry rows', () {
      // Short content → 15m floor (was 5m).
      expect(
        StartDownloadUseCase.postProcessingTimeoutForTest(
          recodeVideo: null,
          selectedHeight: null,
          videoDuration: const Duration(minutes: 10),
          extractAudio: true,
        ),
        const Duration(minutes: 40),
      );
      // No duration metadata → base floor.
      expect(
        StartDownloadUseCase.postProcessingTimeoutForTest(
          recodeVideo: null,
          selectedHeight: null,
          videoDuration: null,
          extractAudio: true,
        ),
        const Duration(minutes: 15),
      );
      // Multi-hour mix → duration-scaled, capped at 4h like video.
      expect(
        StartDownloadUseCase.postProcessingTimeoutForTest(
          recodeVideo: null,
          selectedHeight: null,
          videoDuration: const Duration(hours: 3),
          extractAudio: true,
        ),
        const Duration(hours: 4),
      );
    });

    test(
      'allows long-running 8K explicit recode instead of killing at 300s',
      () {
        final timeout = StartDownloadUseCase.postProcessingTimeoutForTest(
          recodeVideo: 'avi',
          selectedHeight: 4320,
          videoDuration: const Duration(minutes: 5),
        );

        expect(timeout, const Duration(minutes: 90));
        expect(timeout, greaterThan(const Duration(seconds: 300)));
      },
    );

    test('scales 4K recode with content duration and caps runaway jobs', () {
      final timeout = StartDownloadUseCase.postProcessingTimeoutForTest(
        recodeVideo: 'mov',
        selectedHeight: 2160,
        videoDuration: const Duration(hours: 2),
      );

      expect(timeout, const Duration(hours: 4));
    });
  });

  group('StartDownloadUseCase WebM output source selector', () {
    test(
      'uses broad height-capped source selector when WebM will be recoded',
      () {
        expect(
          StartDownloadUseCase.webmRecodeSourceSelectorForTest(
            targetHeight: 1440,
            maxVideoHeight: null,
          ),
          'bestvideo[height<=1440]+bestaudio/'
          'bestvideo[width<=1440]+bestaudio/'
          'best[height<=1440]/best[width<=1440]',
        );
      },
    );

    test('caps WebM recode source selector by free-tier max height', () {
      expect(
        StartDownloadUseCase.webmRecodeSourceSelectorForTest(
          targetHeight: 2160,
          maxVideoHeight: 1080,
        ),
        'bestvideo[height<=1080]+bestaudio/'
        'bestvideo[width<=1080]+bestaudio/'
        'best[height<=1080]/best[width<=1080]',
      );
    });

    test('forces WebM recode for Facebook when codecs are unknown', () {
      expect(
        StartDownloadUseCase.shouldForceWebmOutputRecodeForTest(
          platform: VideoPlatform.facebook,
          videoFormat: 'webm',
          remuxVideo: 'webm',
        ),
        isTrue,
      );
    });

    test('forces WebM recode when planner already selected recode', () {
      expect(
        StartDownloadUseCase.shouldForceWebmOutputRecodeForTest(
          platform: VideoPlatform.instagram,
          videoFormat: 'webm',
          recodeVideo: 'webm',
          sourceVcodec: 'avc1.640028',
          sourceAcodec: 'mp4a.40.2',
        ),
        isTrue,
      );
    });

    test('keeps YouTube WebM native fast path for unknown adaptive codecs', () {
      expect(
        StartDownloadUseCase.shouldForceWebmOutputRecodeForTest(
          platform: VideoPlatform.youtube,
          videoFormat: 'webm',
          remuxVideo: 'webm',
        ),
        isFalse,
      );
    });

    test(
      'keeps non-YouTube WebM fast path only when codecs are proven native',
      () {
        expect(
          StartDownloadUseCase.shouldForceWebmOutputRecodeForTest(
            platform: VideoPlatform.vimeo,
            videoFormat: 'webm',
            remuxVideo: 'webm',
            sourceVcodec: 'vp09.00.51.08',
            sourceAcodec: 'opus',
          ),
          isFalse,
        );
      },
    );
  });

  group('StartDownloadUseCase cookie retry policy', () {
    test('retries without cookies for YouTube download-stage 403', () {
      expect(
        StartDownloadUseCase.shouldRetryWithoutCookiesAfterDownloadErrorForTest(
          errorCode: DownloadErrorCode.accessDenied,
          platformString: 'youtube',
        ),
        isTrue,
      );
    });

    test('does not retry without cookies for non-YouTube 403', () {
      expect(
        StartDownloadUseCase.shouldRetryWithoutCookiesAfterDownloadErrorForTest(
          errorCode: DownloadErrorCode.accessDenied,
          platformString: 'instagram',
        ),
        isFalse,
      );
    });

    test('keeps existing formatUnavailable cookie retry on all platforms', () {
      expect(
        StartDownloadUseCase.shouldRetryWithoutCookiesAfterDownloadErrorForTest(
          errorCode: DownloadErrorCode.formatUnavailable,
          platformString: 'youtube',
        ),
        isTrue,
      );
      expect(
        StartDownloadUseCase.shouldRetryWithoutCookiesAfterDownloadErrorForTest(
          errorCode: DownloadErrorCode.formatUnavailable,
          platformString: 'tiktok',
        ),
        isTrue,
      );
    });

    test(
      'preserves original YouTube 403 when no-cookie retry returns login',
      () {
        expect(
          StartDownloadUseCase.shouldPreserveCookieRetryOriginalErrorForTest(
            originalErrorCode: DownloadErrorCode.accessDenied,
            retryErrorCode: DownloadErrorCode.loginRequired,
          ),
          isTrue,
        );
      },
    );

    test('does not preserve original error for non-login retry failures', () {
      expect(
        StartDownloadUseCase.shouldPreserveCookieRetryOriginalErrorForTest(
          originalErrorCode: DownloadErrorCode.accessDenied,
          retryErrorCode: DownloadErrorCode.networkTimeout,
        ),
        isFalse,
      );
      expect(
        StartDownloadUseCase.shouldPreserveCookieRetryOriginalErrorForTest(
          originalErrorCode: DownloadErrorCode.formatUnavailable,
          retryErrorCode: DownloadErrorCode.loginRequired,
        ),
        isFalse,
      );
    });
  });

  group('StartDownloadUseCase quota enforcement', () {
    test('blocks free 4K quality at domain layer before quota', () async {
      final useCase = StartDownloadUseCase(
        _MockDownloadRepository(),
        _MockYtDlpDataSource(),
        _MockGalleryDlDataSource(),
      );

      const videoInfo = VideoInfo(
        url: 'https://www.youtube.com/watch?v=video-1',
        title: 'Video',
        availableQualities: [],
      );
      const quality = Quality(
        qualityText: 'Best (4K)',
        size: '100 MB',
        encryptedUrl: 'ytdlp:best:mp4',
        mediaType: MediaType.video,
      );

      final result = await useCase(
        videoInfo: videoInfo,
        selectedQuality: quality,
        savePath: '/tmp',
        isPremium: false,
      );

      expect(result.isFailure, isTrue);
      expect(
        result.exceptionOrNull.toString(),
        contains('Premium required for video qualities above 1080p'),
      );
    });

    test('blocks at domain layer when quota is exhausted', () async {
      final useCase = StartDownloadUseCase(
        _MockDownloadRepository(),
        _MockYtDlpDataSource(),
        _MockGalleryDlDataSource(),
        null,
        _DenyingQuotaReserver(),
      );

      const videoInfo = VideoInfo(
        url: 'https://www.youtube.com/watch?v=video-1',
        title: 'Video',
        availableQualities: [],
      );
      const quality = Quality(
        qualityText: '720p',
        size: '10 MB',
        encryptedUrl: 'ytdlp:raw:18',
        mediaType: MediaType.video,
      );

      final result = await useCase(
        videoInfo: videoInfo,
        selectedQuality: quality,
        savePath: '/tmp',
        isPremium: false,
      );

      expect(result.isFailure, isTrue);
      expect(
        result.exceptionOrNull.toString(),
        contains('Weekly free download limit reached'),
      );
    });
  });

  // Codex round-4 audit (2026-05-09): pin the FFmpeg gate at the
  // usecase layer so the "MP4 · Best → 360p silent degrade"
  // regression can't slip back through the StartDownloadUseCase
  // surface. The unit tests in `ytdlp_ensure_ffmpeg_test.dart`
  // cover `ensureFFmpegOrRepair` in isolation; these tests pin
  // the end-to-end contract: gate fires when format requires
  // merge + FFmpeg missing, repair-success continues with the
  // ORIGINAL DASH format (no silent rewrite to `best`), and
  // repair-failure returns an actionable AppException.download
  // surface visible to the UI.
  group('StartDownloadUseCase FFmpeg gate', () {
    const youtubeUrl = 'https://www.youtube.com/watch?v=ffmpeg-gate-test';
    const videoInfo = VideoInfo(
      url: youtubeUrl,
      title: 'Gate test',
      availableQualities: [],
    );
    const bestMp4 = Quality(
      qualityText: 'Best (Auto)',
      size: 'unknown',
      encryptedUrl: 'ytdlp:best:mp4',
      mediaType: MediaType.video,
    );

    test('repair fails => returns failure with actionable FFmpeg message — '
        'no silent fallback to "best" / 360p', () async {
      // Premium user so the 1080p cap from `_extractWithYtdlp`
      // does NOT route the flow into the resolution-specific
      // path that bypasses the "best" pathway we are pinning.
      final ytdlp = _MockYtDlpDataSource();
      when(() => ytdlp.hasFFmpeg).thenReturn(false);
      when(() => ytdlp.ensureFFmpegOrRepair()).thenAnswer((_) async => false);

      final useCase = StartDownloadUseCase(
        _MockDownloadRepository(),
        ytdlp,
        _MockGalleryDlDataSource(),
      );

      final result = await useCase(
        videoInfo: videoInfo,
        selectedQuality: bestMp4,
        savePath: '/tmp',
        isPremium: true,
      );

      expect(result.isFailure, isTrue);
      final errMsg = result.exceptionOrNull.toString();
      expect(
        errMsg,
        contains('FFmpeg'),
        reason: 'failure surface must name FFmpeg so the user can act',
      );
      expect(
        errMsg,
        contains('Settings'),
        reason:
            'failure surface must point the user at the recovery surface '
            '(Settings → yt-dlp Engine), not just say "download failed"',
      );

      // Critical pin: the repair attempt MUST have been awaited.
      // Pre-fix the code skipped repair entirely and silently
      // rewrote the format; this assertion catches any future
      // reversion to that pattern.
      verify(() => ytdlp.ensureFFmpegOrRepair()).called(1);
    });

    test(
      'repair succeeds + hasFFmpeg true => gate does not fail download',
      () async {
        // After a successful repair the gate must permit the
        // download to proceed. We can't easily run the full
        // download codepath in a unit test (it spawns yt-dlp), so
        // we assert the gate's POST-REPAIR signal: `hasFFmpeg`
        // flipped to true and `ensureFFmpegOrRepair` returned
        // true. Anything downstream that errors out belongs to a
        // different layer (extraction, network) and is not the
        // gate's regression surface.
        final ytdlp = _MockYtDlpDataSource();
        // Returns false on the first probe (entry to the gate),
        // then true after repair runs — matches the real shape
        // where the cached `_ffmpegPath` is null on probe and
        // refreshed inside `ensureFFmpegOrRepair`.
        var probed = 0;
        when(() => ytdlp.hasFFmpeg).thenAnswer((_) {
          probed++;
          return probed > 1; // first call false, subsequent true
        });
        when(() => ytdlp.ensureFFmpegOrRepair()).thenAnswer((_) async => true);

        final useCase = StartDownloadUseCase(
          _MockDownloadRepository(),
          ytdlp,
          _MockGalleryDlDataSource(),
        );

        final result = await useCase(
          videoInfo: videoInfo,
          selectedQuality: bestMp4,
          savePath: '/tmp',
          isPremium: true,
        );

        // The gate itself should NOT be the failure source — any
        // failure here is downstream (extraction calls the real
        // yt-dlp binary which is not present in the test
        // environment). We pin the gate behavior by asserting
        // ensureFFmpegOrRepair was invoked AND no FFmpeg-related
        // error text shows up in the failure surface (if any).
        verify(() => ytdlp.ensureFFmpegOrRepair()).called(1);
        if (result.isFailure) {
          final errMsg = result.exceptionOrNull.toString();
          expect(
            errMsg.contains('FFmpeg'),
            isFalse,
            reason:
                'after successful repair the failure surface must NOT '
                'mention FFmpeg — that would mean the gate spuriously '
                'fired again',
          );
        }
      },
    );

    test(
      'format that does NOT require merge bypasses the FFmpeg gate',
      () async {
        // Quality `ytdlp:raw:18` is YouTube format 18 = pre-muxed
        // 360p MP4. It explicitly does not need FFmpeg to merge.
        // The gate condition is `ytdlpFormat.contains('+')`, so
        // raw single-stream formats must skip the gate even when
        // `hasFFmpeg == false`.
        final ytdlp = _MockYtDlpDataSource();
        when(() => ytdlp.hasFFmpeg).thenReturn(false);
        when(() => ytdlp.ensureFFmpegOrRepair()).thenAnswer((_) async => false);

        final useCase = StartDownloadUseCase(
          _MockDownloadRepository(),
          ytdlp,
          _MockGalleryDlDataSource(),
        );

        const rawQuality = Quality(
          qualityText: '360p (pre-muxed)',
          size: '5 MB',
          encryptedUrl: 'ytdlp:raw:18',
          mediaType: MediaType.video,
        );

        final result = await useCase(
          videoInfo: videoInfo,
          selectedQuality: rawQuality,
          savePath: '/tmp',
          isPremium: true,
        );

        // The gate must NOT trigger repair for non-merge formats —
        // that would impose FFmpeg as a hard dependency on
        // download paths that never needed it.
        verifyNever(() => ytdlp.ensureFFmpegOrRepair());

        // If the call fails it's for a downstream reason (the
        // mock can't actually run yt-dlp), but it must not name
        // FFmpeg as the cause.
        if (result.isFailure) {
          final errMsg = result.exceptionOrNull.toString();
          expect(
            errMsg.contains('FFmpeg'),
            isFalse,
            reason: 'pre-muxed format should bypass the FFmpeg gate entirely',
          );
        }
      },
    );
  });
}
