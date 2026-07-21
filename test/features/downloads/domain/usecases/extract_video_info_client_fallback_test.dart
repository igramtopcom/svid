// Task 84.3 — tests for yt-dlp extractor client fallback chain in ExtractVideoInfoUseCase.
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ssvid/core/errors/result.dart';
import 'package:ssvid/features/downloads/data/datasources/ytdlp_datasource.dart';
import 'package:ssvid/features/downloads/domain/usecases/extract_video_info_usecase.dart';
import 'package:ssvid/features/settings/domain/enums/download_engine.dart';

import '../../../../shared/mocks/mocks.dart';

void main() {
  late MockSSvidApiService mockApi;
  late MockYtDlpDataSource mockYtdlp;
  late MockGalleryDlDataSource mockGalleryDl;
  late ExtractVideoInfoUseCase useCase;

  const youtubeUrl = 'https://www.youtube.com/watch?v=client84test';
  const nonYoutubeUrl = 'https://vimeo.com/123456789';

  YtDlpVideoInfo makeYtdlpInfo() => YtDlpVideoInfo(
        id: 'client84test',
        title: 'Client Fallback Test',
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
              acodec: 'none'),
          YtDlpFormat(
              formatId: '140', ext: 'm4a', vcodec: 'none', acodec: 'mp4a'),
        ],
        isLive: false,
      );

  // Convenience matcher for extractInfo with any named params.
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

  setUp(() {
    mockApi = MockSSvidApiService();
    mockYtdlp = MockYtDlpDataSource();
    mockGalleryDl = MockGalleryDlDataSource();
    useCase = ExtractVideoInfoUseCase(
      mockApi,
      mockYtdlp,
      mockGalleryDl,
      delay: (_) async {}, // no-op delay so tests don't actually wait
    );
    when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
    when(() => mockGalleryDl.isAvailable()).thenAnswer((_) async => false);
  });

  group('extractor client fallback chain (Task 84.3)', () {
    // -------------------------------------------------------------------------
    // Non-YouTube URLs — must NOT use the multi-client chain
    // -------------------------------------------------------------------------

    test('non-YouTube URL success: extractInfo called exactly once', () async {
      int callCount = 0;
      whenExtractInfo().thenAnswer((_) async {
        callCount++;
        return makeYtdlpInfo();
      });

      final result = await useCase(nonYoutubeUrl, engine: DownloadEngine.ytdlpOnly);

      expect(result.isSuccess, isTrue);
      expect(callCount, equals(1));
    });

    test('non-YouTube URL failure does NOT retry with alternate clients', () async {
      int callCount = 0;
      whenExtractInfo().thenAnswer((_) async {
        callCount++;
        throw YtDlpException(YtDlpErrorType.networkError, 'network down');
      });

      final result = await useCase(nonYoutubeUrl, engine: DownloadEngine.ytdlpOnly);

      expect(result.isFailure, isTrue);
      // No chain — only 1 call (rate-limit retry doesn't apply to networkError)
      expect(callCount, equals(1));
    });

    // -------------------------------------------------------------------------
    // YouTube URLs — must use the multi-client chain on failure
    // -------------------------------------------------------------------------

    test('YouTube URL: first attempt succeeds — extractInfo called once', () async {
      int callCount = 0;
      whenExtractInfo().thenAnswer((_) async {
        callCount++;
        return makeYtdlpInfo();
      });

      final result = await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);

      expect(result.isSuccess, isTrue);
      expect(callCount, equals(1));
    });

    test('YouTube URL: first fails, second succeeds — 2 calls total', () async {
      int callCount = 0;
      whenExtractInfo().thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          throw YtDlpException(YtDlpErrorType.networkError, 'first fail');
        }
        return makeYtdlpInfo();
      });

      final result = await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);

      expect(result.isSuccess, isTrue);
      expect(callCount, equals(2));
    });

    test('YouTube URL: all 5 clients exhausted returns failure — 5 calls total',
        () async {
      int callCount = 0;
      whenExtractInfo().thenAnswer((_) async {
        callCount++;
        throw YtDlpException(YtDlpErrorType.networkError, 'always fail');
      });

      final result = await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);

      expect(result.isFailure, isTrue);
      // ios/web (default) + mweb,web + android + android_creator + tv_embedded = 5
      expect(callCount, equals(5));
    });

    // -------------------------------------------------------------------------
    // Client parameter values passed to extractInfo
    // -------------------------------------------------------------------------

    test('first YouTube attempt passes null extractorClient (ios,web default)', () async {
      final capturedClients = <String?>[];
      whenExtractInfo().thenAnswer((invocation) async {
        capturedClients.add(invocation.namedArguments[#extractorClient] as String?);
        return makeYtdlpInfo();
      });

      await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);

      expect(capturedClients, isNotEmpty);
      expect(capturedClients.first, isNull,
          reason: 'First attempt should use the default ios,web client (null)');
    });

    test('second YouTube attempt passes mweb,web extractorClient', () async {
      int callCount = 0;
      final capturedClients = <String?>[];
      whenExtractInfo().thenAnswer((invocation) async {
        callCount++;
        capturedClients.add(invocation.namedArguments[#extractorClient] as String?);
        if (callCount == 1) {
          throw YtDlpException(YtDlpErrorType.networkError, 'first fail');
        }
        return makeYtdlpInfo();
      });

      await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);

      expect(capturedClients.length, equals(2));
      expect(capturedClients[1], equals('mweb,web'));
    });

    test('third YouTube attempt passes android extractorClient', () async {
      int callCount = 0;
      final capturedClients = <String?>[];
      whenExtractInfo().thenAnswer((invocation) async {
        callCount++;
        capturedClients.add(invocation.namedArguments[#extractorClient] as String?);
        if (callCount < 3) {
          throw YtDlpException(YtDlpErrorType.networkError, 'fail');
        }
        return makeYtdlpInfo();
      });

      await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);

      expect(capturedClients.length, equals(3));
      expect(capturedClients[2], equals('android'));
    });

    test('fourth YouTube attempt passes android_creator extractorClient', () async {
      int callCount = 0;
      final capturedClients = <String?>[];
      whenExtractInfo().thenAnswer((invocation) async {
        callCount++;
        capturedClients.add(invocation.namedArguments[#extractorClient] as String?);
        if (callCount < 4) {
          throw YtDlpException(YtDlpErrorType.networkError, 'fail');
        }
        return makeYtdlpInfo();
      });

      await useCase(youtubeUrl, engine: DownloadEngine.ytdlpOnly);

      expect(capturedClients.length, equals(4));
      expect(capturedClients[3], equals('android_creator'));
    });
  });
}
