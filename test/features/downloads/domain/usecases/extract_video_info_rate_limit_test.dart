// Task 83.1 — tests for rate-limit retry logic in ExtractVideoInfoUseCase.
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:svid/core/errors/result.dart';
import 'package:svid/features/downloads/data/datasources/ytdlp_datasource.dart';
import 'package:svid/features/downloads/domain/usecases/extract_video_info_usecase.dart';
import 'package:svid/features/settings/domain/enums/download_engine.dart';

import '../../../../shared/mocks/mocks.dart';

void main() {
  late MockSvidApiService mockApi;
  late MockYtDlpDataSource mockYtdlp;
  late MockGalleryDlDataSource mockGalleryDl;
  late ExtractVideoInfoUseCase useCase;

  const testUrl = 'https://www.youtube.com/watch?v=antiblock83';
  // Use a non-YouTube URL for "does NOT trigger" tests — YouTube triggers the
  // client-fallback chain which makes multiple calls regardless of error type.
  const nonYoutubeUrl = 'https://vimeo.com/12345678';

  /// Build a minimal successful YtDlpVideoInfo (video + audio track).
  YtDlpVideoInfo makeYtdlpInfo() => YtDlpVideoInfo(
        id: 'antiblock83',
        title: 'Anti-Block Test Video',
        description: '',
        uploader: 'Test Channel',
        platform: 'youtube',
        formats: [
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
        isLive: false,
      );

  setUp(() {
    mockApi = MockSvidApiService();
    mockYtdlp = MockYtDlpDataSource();
    mockGalleryDl = MockGalleryDlDataSource();

    // Inject a no-op delay so tests do not actually wait 3 seconds.
    useCase = ExtractVideoInfoUseCase(
      mockApi,
      mockYtdlp,
      mockGalleryDl,
      delay: (_) async {},
    );

    // Default stubs
    when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
    when(() => mockGalleryDl.isAvailable()).thenAnswer((_) async => false);
  });

  // Convenience matcher for extractInfo with any named params
  When<Future<YtDlpVideoInfo>> whenExtractInfo() => when(
        () => mockYtdlp.extractInfo(
          any(),
          cookiesFile: any(named: 'cookiesFile'),
          cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
          proxyUrl: any(named: 'proxyUrl'),
          extractorClient: any(named: 'extractorClient'),
          timeoutSecs: any(named: 'timeoutSecs'),
        ),
      );

  group('rate-limit retry (Task 83.1)', () {
    // -----------------------------------------------------------------------
    // Tests that DO trigger the retry path
    // -----------------------------------------------------------------------

    test('rateLimited error triggers exactly one retry — extractInfo called twice',
        () async {
      int callCount = 0;
      whenExtractInfo().thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          throw YtDlpException(YtDlpErrorType.rateLimited, 'rate limited');
        }
        return makeYtdlpInfo();
      });

      final result = await useCase(testUrl, engine: DownloadEngine.ytdlpOnly);

      expect(callCount, equals(2));
      expect(result.isSuccess, isTrue);
    });

    test('rateLimited retry returns success when second call succeeds', () async {
      int callCount = 0;
      whenExtractInfo().thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          throw YtDlpException(YtDlpErrorType.rateLimited, 'rate limited');
        }
        return makeYtdlpInfo();
      });

      final result = await useCase(testUrl, engine: DownloadEngine.ytdlpOnly);

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.title, equals('Anti-Block Test Video'));
      expect(result.dataOrNull?.downloadMethod, equals('ytdlp'));
    });

    test('rateLimited retry fails on second attempt returns failure', () async {
      // Both calls throw rateLimited; second call has retryOnRateLimit=false
      // so it falls through to gallery-dl fallback (unavailable) then failure.
      whenExtractInfo().thenAnswer((_) async {
        throw YtDlpException(YtDlpErrorType.rateLimited, 'still rate limited');
      });

      final result = await useCase(testUrl, engine: DownloadEngine.ytdlpOnly);

      expect(result.isFailure, isTrue);
    });

    test('rateLimited in auto mode also triggers retry', () async {
      int callCount = 0;
      whenExtractInfo().thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          throw YtDlpException(YtDlpErrorType.rateLimited, 'rate limited');
        }
        return makeYtdlpInfo();
      });

      final result = await useCase(
        testUrl,
        engine: DownloadEngine.auto,
      );

      expect(callCount, equals(2));
      expect(result.isSuccess, isTrue);
    });

    // -----------------------------------------------------------------------
    // Tests that do NOT trigger the retry path
    // -----------------------------------------------------------------------

    test('networkError does NOT trigger rate-limit retry — extractInfo called once',
        () async {
      whenExtractInfo().thenAnswer((_) async {
        throw YtDlpException(YtDlpErrorType.networkError, 'connection refused');
      });

      // Non-YouTube URL bypasses the client-fallback chain so only 1 call is made.
      final result = await useCase(nonYoutubeUrl, engine: DownloadEngine.ytdlpOnly);

      expect(result.isFailure, isTrue);
      verify(
        () => mockYtdlp.extractInfo(
          any(),
          cookiesFile: any(named: 'cookiesFile'),
          cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
          proxyUrl: any(named: 'proxyUrl'),
          extractorClient: any(named: 'extractorClient'),
          timeoutSecs: any(named: 'timeoutSecs'),
        ),
      ).called(1);
    });

    test('timeout error does NOT trigger rate-limit retry', () async {
      whenExtractInfo().thenAnswer((_) async {
        throw YtDlpException(YtDlpErrorType.timeout, 'timed out');
      });

      final result = await useCase(nonYoutubeUrl, engine: DownloadEngine.ytdlpOnly);

      expect(result.isFailure, isTrue);
      verify(
        () => mockYtdlp.extractInfo(
          any(),
          cookiesFile: any(named: 'cookiesFile'),
          cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
          proxyUrl: any(named: 'proxyUrl'),
          extractorClient: any(named: 'extractorClient'),
          timeoutSecs: any(named: 'timeoutSecs'),
        ),
      ).called(1);
    });

    test('geoRestricted error does NOT trigger rate-limit retry', () async {
      whenExtractInfo().thenAnswer((_) async {
        throw YtDlpException(YtDlpErrorType.geoRestricted, 'blocked in your region');
      });

      final result = await useCase(nonYoutubeUrl, engine: DownloadEngine.ytdlpOnly);

      expect(result.isFailure, isTrue);
      verify(
        () => mockYtdlp.extractInfo(
          any(),
          cookiesFile: any(named: 'cookiesFile'),
          cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
          proxyUrl: any(named: 'proxyUrl'),
          extractorClient: any(named: 'extractorClient'),
          timeoutSecs: any(named: 'timeoutSecs'),
        ),
      ).called(1);
    });
  });
}
