import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:svid/core/binaries/binary_info.dart';
import 'package:svid/core/errors/app_exception.dart';
import 'package:svid/core/errors/result.dart';
import 'package:svid/features/downloads/data/datasources/ytdlp_datasource.dart';
import 'package:svid/features/downloads/domain/entities/download_error_code.dart';
import 'package:svid/features/downloads/domain/usecases/extract_video_info_usecase.dart';
import 'package:svid/features/settings/domain/enums/download_engine.dart';

import '../../../../shared/mocks/mocks.dart';

void main() {
  late MockSSvidApiService mockApi;
  late MockYtDlpDataSource mockYtdlp;
  late MockGalleryDlDataSource mockGalleryDl;
  late ExtractVideoInfoUseCase useCase;

  const testUrl = 'https://www.youtube.com/watch?v=test123';

  /// Creates a minimal YtDlpVideoInfo with video formats
  YtDlpVideoInfo makeYtdlpInfo({
    List<YtDlpFormat>? formats,
    bool isLive = false,
  }) {
    return YtDlpVideoInfo(
      id: 'test123',
      title: 'Test Video',
      description: 'A test video',
      uploader: 'Test Channel',
      platform: 'youtube',
      formats:
          formats ??
          [
            YtDlpFormat(
              formatId: '137',
              ext: 'mp4',
              height: 1080,
              width: 1920,
              vcodec: 'avc1',
              acodec: 'none',
            ),
            YtDlpFormat(
              formatId: '140',
              ext: 'm4a',
              vcodec: 'none',
              acodec: 'mp4a',
            ),
          ],
      isLive: isLive,
    );
  }

  // Convenience matcher for extractInfo with any named params.
  // Pass a specific cookiesFile value to match only that value.
  When<Future<YtDlpVideoInfo>> whenExtractInfo({
    Object? cookiesFile = const _AnyArg(),
  }) => when(
    () => mockYtdlp.extractInfo(
      any(),
      cookiesFile:
          cookiesFile is _AnyArg
              ? any(named: 'cookiesFile')
              : cookiesFile as String?,
      cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
      proxyUrl: any(named: 'proxyUrl'),
      extractorClient: any(named: 'extractorClient'),
      timeoutSecs: any(named: 'timeoutSecs'),
    ),
  );

  setUp(() {
    mockApi = MockSSvidApiService();
    mockYtdlp = MockYtDlpDataSource();
    mockGalleryDl = MockGalleryDlDataSource();
    useCase = ExtractVideoInfoUseCase(
      mockApi,
      mockYtdlp,
      mockGalleryDl,
      delay: (_) async {},
    );

    // Default: gallery-dl not available (most tests don't need it)
    when(() => mockGalleryDl.isAvailable()).thenAnswer((_) async => false);
  });

  group('ExtractVideoInfoUseCase', () {
    group('ytdlpOnly mode', () {
      test('succeeds when yt-dlp is available and extracts', () async {
        whenExtractInfo().thenAnswer((_) async => makeYtdlpInfo());

        final result = await useCase(testUrl, engine: DownloadEngine.ytdlpOnly);

        expect(result.isSuccess, isTrue);
        expect(result.dataOrNull!.title, 'Test Video');
        expect(result.dataOrNull!.downloadMethod, 'ytdlp');
        verifyNever(() => mockYtdlp.isAvailable());
        verify(
          () => mockYtdlp.extractInfo(
            testUrl,
            cookiesFile: null,
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            proxyUrl: any(named: 'proxyUrl'),
            extractorClient: any(named: 'extractorClient'),
            timeoutSecs: any(named: 'timeoutSecs'),
          ),
        ).called(1);
      });

      test(
        'propagates terminal yt-dlp binary missing from datasource',
        () async {
          const missingBinaryUrl = 'https://vimeo.com/123456';
          whenExtractInfo().thenThrow(
            YtDlpException(
              YtDlpErrorType.unknown,
              YtDlpDataSource.ytdlpBinaryMissingMessage,
            ),
          );

          final result = await useCase(
            missingBinaryUrl,
            engine: DownloadEngine.ytdlpOnly,
          );

          expect(result.isFailure, isTrue);
          final ex = result.exceptionOrNull;
          expect(ex, isA<YtDlpException>());
          expect(
            (ex as YtDlpException).message,
            YtDlpDataSource.ytdlpBinaryMissingMessage,
          );
          verify(
            () => mockYtdlp.extractInfo(
              missingBinaryUrl,
              cookiesFile: any(named: 'cookiesFile'),
              cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
              proxyUrl: any(named: 'proxyUrl'),
              extractorClient: any(named: 'extractorClient'),
              timeoutSecs: any(named: 'timeoutSecs'),
            ),
          ).called(1);
        },
      );

      test('fails when yt-dlp extraction fails', () async {
        when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
        whenExtractInfo().thenThrow(
          YtDlpException(YtDlpErrorType.networkError, 'network down'),
        );

        final result = await useCase(testUrl, engine: DownloadEngine.ytdlpOnly);

        expect(result.isFailure, isTrue);
      });

      test('emits final extraction failure telemetry once', () async {
        final events = <Map<String, Object?>>[];
        useCase = ExtractVideoInfoUseCase(
          mockApi,
          mockYtdlp,
          mockGalleryDl,
          extractionFailureTelemetrySink: ({
            required url,
            required platform,
            required errorCode,
            required errorPhase,
            required errorMessage,
            required metadata,
          }) {
            events.add({
              'url': url,
              'platform': platform,
              'errorCode': errorCode,
              'errorPhase': errorPhase,
              'errorMessage': errorMessage,
              'metadata': metadata,
            });
          },
          delay: (_) async {},
        );
        when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
        whenExtractInfo().thenThrow(
          YtDlpException(
            YtDlpErrorType.loginRequired,
            'Login required: raw yt-dlp error: HTTP Error 403: Forbidden',
            metadata: const {
              'stage': 'extract',
              'path': 'native-windows',
              'player_client': 'default',
              'looks_like_http_403': true,
            },
          ),
        );

        final result = await useCase(testUrl, engine: DownloadEngine.ytdlpOnly);

        expect(result.isFailure, isTrue);
        expect(events, hasLength(1));
        expect(events.single['url'], testUrl);
        expect(events.single['platform'], 'youtube');
        expect(events.single['errorCode'], DownloadErrorCode.loginRequired);
        expect(events.single['errorPhase'], 'extraction');
        expect(events.single['errorMessage'], startsWith('loginRequired:'));

        final metadata = events.single['metadata']! as Map<String, dynamic>;
        expect(metadata['stage'], 'extract');
        expect(metadata['path'], 'native-windows');
        expect(metadata['player_client'], 'default');
        expect(metadata['looks_like_http_403'], isTrue);
        expect(metadata['yt_dlp_channel'], ytDlpReleaseChannel);
        expect(metadata['yt_dlp_version'], 'unknown');
        expect(metadata['terminal_error_code'], 'loginRequired');
      });

      test(
        'maps Facebook Cannot parse data to login-required guidance',
        () async {
          const facebookUrl = 'https://www.facebook.com/reel/1659131188558491';
          when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
          whenExtractInfo().thenThrow(
            YtDlpException(
              YtDlpErrorType.unknown,
              'ERROR: [facebook] 1659131188558491: Cannot parse data',
            ),
          );

          final result = await useCase(
            facebookUrl,
            engine: DownloadEngine.ytdlpOnly,
          );

          expect(result.isFailure, isTrue);
          expect(
            (result.exceptionOrNull as AppException).message,
            contains('Facebook login required'),
          );
        },
      );
    });

    group('auto mode', () {
      test('uses yt-dlp when available', () async {
        whenExtractInfo().thenAnswer((_) async => makeYtdlpInfo());

        final result = await useCase(testUrl, engine: DownloadEngine.auto);

        expect(result.isSuccess, isTrue);
        verifyNever(() => mockYtdlp.isAvailable());
        verify(
          () => mockYtdlp.extractInfo(
            testUrl,
            cookiesFile: null,
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            proxyUrl: any(named: 'proxyUrl'),
            extractorClient: any(named: 'extractorClient'),
            timeoutSecs: any(named: 'timeoutSecs'),
          ),
        ).called(1);
      });

      test(
        'does not use API fallback for terminal yt-dlp binary missing',
        () async {
          whenExtractInfo().thenThrow(
            YtDlpException(
              YtDlpErrorType.unknown,
              YtDlpDataSource.ytdlpBinaryMissingMessage,
            ),
          );

          final result = await useCase(testUrl, engine: DownloadEngine.auto);

          expect(result.isFailure, isTrue);
          expect(result.exceptionOrNull, isA<YtDlpException>());
          verifyNever(() => mockApi.search(any()));
        },
      );

      test(
        'preserves loginRequired when first-login prompt is requested',
        () async {
          when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
          whenExtractInfo().thenThrow(
            YtDlpException(
              YtDlpErrorType.loginRequired,
              'Sign in to confirm you are not a bot',
            ),
          );

          final result = await useCase(
            testUrl,
            engine: DownloadEngine.auto,
            stopOnLoginRequired: true,
          );

          expect(result.isFailure, isTrue);
          expect(result.exceptionOrNull, isA<YtDlpException>());
          expect(
            (result.exceptionOrNull as YtDlpException).type,
            YtDlpErrorType.loginRequired,
          );
          verifyNever(() => mockApi.search(any()));
        },
      );
    });

    group('quality conversion', () {
      test('generates Best Available quality option', () async {
        when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
        whenExtractInfo().thenAnswer(
          (_) async => makeYtdlpInfo(
            formats: [
              YtDlpFormat(
                formatId: '137',
                ext: 'mp4',
                height: 1080,
                width: 1920,
                vcodec: 'avc1',
                acodec: 'none',
              ),
            ],
          ),
        );

        final result = await useCase(testUrl, engine: DownloadEngine.ytdlpOnly);

        expect(result.isSuccess, isTrue);
        final qualities = result.dataOrNull!.availableQualities;
        expect(qualities, isNotEmpty);
        expect(qualities.first.qualityText, contains('Best'));
      });

      test('adds audio format options when audio available', () async {
        when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
        whenExtractInfo().thenAnswer((_) async => makeYtdlpInfo());

        final result = await useCase(testUrl, engine: DownloadEngine.ytdlpOnly);

        final qualities = result.dataOrNull!.availableQualities;
        final audioQualities = qualities.where(
          (q) => q.qualityText.contains('Audio'),
        );
        expect(audioQualities, isNotEmpty);
      });

      test('maps 4K resolution correctly', () async {
        when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
        whenExtractInfo().thenAnswer(
          (_) async => makeYtdlpInfo(
            formats: [
              YtDlpFormat(
                formatId: '313',
                ext: 'webm',
                height: 2160,
                width: 3840,
                vcodec: 'vp9',
                acodec: 'none',
              ),
            ],
          ),
        );

        final result = await useCase(testUrl, engine: DownloadEngine.ytdlpOnly);

        expect(result.isSuccess, isTrue);
        final qualities = result.dataOrNull!.availableQualities;
        expect(qualities.first.qualityText, contains('4K'));
      });

      test(
        'returns failure when no video formats found (image-only content)',
        () async {
          when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
          whenExtractInfo().thenAnswer((_) async => makeYtdlpInfo(formats: []));

          final result = await useCase(
            testUrl,
            engine: DownloadEngine.ytdlpOnly,
          );

          // With 0 video formats, yt-dlp returns failure so gallery-dl fallback kicks in
          expect(result.isFailure, isTrue);
        },
      );
    });

    group('cookie retry logic', () {
      test('retries without cookies on formatNotAvailable error', () async {
        when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
        whenExtractInfo(cookiesFile: '/tmp/cookies.txt').thenThrow(
          YtDlpException(YtDlpErrorType.formatNotAvailable, 'bad cookies'),
        );
        whenExtractInfo(
          cookiesFile: null,
        ).thenAnswer((_) async => makeYtdlpInfo());

        final result = await useCase(
          testUrl,
          engine: DownloadEngine.ytdlpOnly,
          cookiesFile: '/tmp/cookies.txt',
        );

        expect(result.isSuccess, isTrue);
        // First call with cookies, second without
        verify(
          () => mockYtdlp.extractInfo(
            testUrl,
            cookiesFile: '/tmp/cookies.txt',
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            proxyUrl: any(named: 'proxyUrl'),
            extractorClient: any(named: 'extractorClient'),
            timeoutSecs: any(named: 'timeoutSecs'),
          ),
        ).called(1);
        verify(
          () => mockYtdlp.extractInfo(
            testUrl,
            cookiesFile: null,
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            proxyUrl: any(named: 'proxyUrl'),
            extractorClient: any(named: 'extractorClient'),
            timeoutSecs: any(named: 'timeoutSecs'),
          ),
        ).called(1);
      });
    });
  });

  // ─── #169: filesizeBytes on Quality ───────────────────────────────────────
  group('filesizeBytes population', () {
    YtDlpVideoInfo makeInfoWithFilesize() => makeYtdlpInfo(
      formats: [
        YtDlpFormat(
          formatId: '137',
          ext: 'mp4',
          height: 1080,
          width: 1920,
          vcodec: 'avc1.64001f',
          acodec: 'none',
          filesize: 28_000_000,
        ),
        YtDlpFormat(
          formatId: '248',
          ext: 'webm',
          height: 720,
          width: 1280,
          vcodec: 'vp09.00.31.08',
          acodec: 'none',
          filesize: 15_000_000,
        ),
        YtDlpFormat(
          formatId: '140',
          ext: 'm4a',
          vcodec: 'none',
          acodec: 'mp4a',
          filesize: 3_500_000,
        ),
      ],
    );

    test('individual qualities carry filesizeBytes', () async {
      when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
      whenExtractInfo().thenAnswer((_) async => makeInfoWithFilesize());

      final result = await useCase(testUrl, engine: DownloadEngine.ytdlpOnly);

      expect(result.isSuccess, isTrue);
      final qualities = result.dataOrNull!.availableQualities;

      final q1080 = qualities.firstWhere((q) => q.qualityText.contains('1080'));
      expect(q1080.filesizeBytes, equals(28_000_000));

      final q720 = qualities.firstWhere((q) => q.qualityText.contains('720'));
      expect(q720.filesizeBytes, equals(15_000_000));
    });

    test(
      'Best Available quality carries filesizeBytes of best format',
      () async {
        when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
        whenExtractInfo().thenAnswer((_) async => makeInfoWithFilesize());

        final result = await useCase(testUrl, engine: DownloadEngine.ytdlpOnly);

        expect(result.isSuccess, isTrue);
        final best = result.dataOrNull!.availableQualities.first;
        expect(best.encryptedUrl, equals('ytdlp:best:mp4'));
        expect(
          best.filesizeBytes,
          equals(28_000_000),
        ); // same as highest format
      },
    );

    test('Best Available size text is formatted when filesize known', () async {
      when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
      whenExtractInfo().thenAnswer((_) async => makeInfoWithFilesize());

      final result = await useCase(testUrl, engine: DownloadEngine.ytdlpOnly);

      final best = result.dataOrNull!.availableQualities.first;
      // 28 MB formatted (not the fallback string)
      expect(best.size, isNot(equals('Highest quality available')));
      expect(best.size, contains('MB'));
    });

    test('Best Available falls back to text when filesize is null', () async {
      when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
      whenExtractInfo().thenAnswer(
        (_) async => makeYtdlpInfo(
          formats: [
            YtDlpFormat(
              formatId: '137',
              ext: 'mp4',
              height: 1080,
              width: 1920,
              vcodec: 'avc1',
              acodec: 'none',
              // no filesize
            ),
          ],
        ),
      );

      final result = await useCase(testUrl, engine: DownloadEngine.ytdlpOnly);

      final best = result.dataOrNull!.availableQualities.first;
      expect(best.filesizeBytes, isNull);
      expect(best.size, equals('Highest quality available'));
    });

    test('Quality with null filesize has null filesizeBytes', () async {
      when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
      whenExtractInfo().thenAnswer(
        (_) async => makeYtdlpInfo(
          formats: [
            YtDlpFormat(
              formatId: '137',
              ext: 'mp4',
              height: 1080,
              width: 1920,
              vcodec: 'avc1',
              acodec: 'none',
              // no filesize
            ),
          ],
        ),
      );

      final result = await useCase(testUrl, engine: DownloadEngine.ytdlpOnly);

      final q1080 = result.dataOrNull!.availableQualities.firstWhere(
        (q) => q.qualityText.contains('1080'),
      );
      expect(q1080.filesizeBytes, isNull);
    });
  });
}

/// Sentinel type used as default for the [whenExtractInfo] cookiesFile parameter.
/// Distinguishes "not specified" (use any()) from "explicitly null".
class _AnyArg {
  const _AnyArg();
}
