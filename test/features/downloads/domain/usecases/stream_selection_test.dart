import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:svid/core/errors/result.dart';
import 'package:svid/core/utils/platform_detector.dart';
import 'package:svid/features/downloads/data/datasources/ytdlp_datasource.dart';
import 'package:svid/features/downloads/domain/entities/video_info.dart';
import 'package:svid/features/downloads/domain/services/download_path_suggestion_service.dart';
import 'package:svid/features/downloads/domain/usecases/extract_video_info_usecase.dart';
import 'package:svid/features/settings/domain/enums/download_engine.dart';

import '../../../../shared/mocks/mocks.dart';

void main() {
  late MockYtDlpDataSource mockYtdlp;
  late MockGalleryDlDataSource mockGalleryDl;
  late ExtractVideoInfoUseCase useCase;

  const testUrl = 'https://www.youtube.com/watch?v=test123';

  /// Creates a YtDlpVideoInfo with video-only + audio-only + muxed formats
  YtDlpVideoInfo makeYtdlpInfoWithStreams({
    List<YtDlpSubtitleInfo> subtitles = const [],
    List<YtDlpSubtitleInfo> automaticCaptions = const [],
    List<YtDlpChapterInfo> chapters = const [],
  }) {
    return YtDlpVideoInfo(
      id: 'test123',
      title: 'Test Video',
      description: 'A test video',
      uploader: 'Test Channel',
      platform: 'youtube',
      formats: [
        // Muxed (video + audio)
        YtDlpFormat(
          formatId: '18',
          ext: 'mp4',
          height: 360,
          width: 640,
          vcodec: 'avc1.42001E',
          acodec: 'mp4a.40.2',
        ),
        // Video-only H.264
        YtDlpFormat(
          formatId: '137',
          ext: 'mp4',
          height: 1080,
          width: 1920,
          vcodec: 'avc1.640028',
          acodec: 'none',
        ),
        // Video-only VP9
        YtDlpFormat(
          formatId: '248',
          ext: 'webm',
          height: 1080,
          width: 1920,
          vcodec: 'vp9',
          acodec: 'none',
        ),
        // Video-only AV1
        YtDlpFormat(
          formatId: '399',
          ext: 'mp4',
          height: 1080,
          width: 1920,
          vcodec: 'av01.0.08M.08',
          acodec: 'none',
        ),
        // Video-only 4K VP9
        YtDlpFormat(
          formatId: '313',
          ext: 'webm',
          height: 2160,
          width: 3840,
          vcodec: 'vp9',
          acodec: 'none',
        ),
        // Audio-only
        YtDlpFormat(
          formatId: '140',
          ext: 'm4a',
          vcodec: 'none',
          acodec: 'mp4a.40.2',
        ),
      ],
      subtitles: subtitles,
      automaticCaptions: automaticCaptions,
      chapters: chapters,
    );
  }

  // Convenience stub helper — matches any call regardless of client/proxy/timeout.
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
    mockYtdlp = MockYtDlpDataSource();
    mockGalleryDl = MockGalleryDlDataSource();
    final mockApi = MockSSvidApiService();
    useCase = ExtractVideoInfoUseCase(mockApi, mockYtdlp, mockGalleryDl,
        delay: (_) async {});

    when(() => mockGalleryDl.isAvailable()).thenAnswer((_) async => false);
  });

  group('Video-only stream selection', () {
    test('generates video-only qualities with codec info', () async {
      when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
      whenExtractInfo().thenAnswer((_) async => makeYtdlpInfoWithStreams());

      final result = await useCase(testUrl, engine: DownloadEngine.ytdlpOnly);

      expect(result.isSuccess, isTrue);
      final qualities = result.dataOrNull!.availableQualities;
      final videoOnly = qualities.where((q) => q.isVideoOnly).toList();

      expect(videoOnly, isNotEmpty);
      // Should have H.264, VP9, AV1 at 1080p + VP9 at 4K
      expect(videoOnly.length, greaterThanOrEqualTo(3));
    });

    test('video-only qualities have "Video Only" in label', () async {
      when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
      whenExtractInfo().thenAnswer((_) async => makeYtdlpInfoWithStreams());

      final result = await useCase(testUrl, engine: DownloadEngine.ytdlpOnly);

      final videoOnly = result.dataOrNull!.availableQualities
          .where((q) => q.isVideoOnly)
          .toList();

      for (final q in videoOnly) {
        expect(q.qualityText, contains('Video Only'));
      }
    });

    test('video-only qualities show codec name (H.264/VP9/AV1)', () async {
      when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
      whenExtractInfo().thenAnswer((_) async => makeYtdlpInfoWithStreams());

      final result = await useCase(testUrl, engine: DownloadEngine.ytdlpOnly);

      final videoOnly = result.dataOrNull!.availableQualities
          .where((q) => q.isVideoOnly)
          .toList();

      final codecNames = videoOnly.map((q) => q.qualityText).toList();
      expect(codecNames.any((t) => t.contains('H.264')), isTrue);
      expect(codecNames.any((t) => t.contains('VP9')), isTrue);
      expect(codecNames.any((t) => t.contains('AV1')), isTrue);
    });

    test('video-only uses ytdlp:raw:FORMAT_ID pattern', () async {
      when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
      whenExtractInfo().thenAnswer((_) async => makeYtdlpInfoWithStreams());

      final result = await useCase(testUrl, engine: DownloadEngine.ytdlpOnly);

      final videoOnly = result.dataOrNull!.availableQualities
          .where((q) => q.isVideoOnly)
          .toList();

      for (final q in videoOnly) {
        expect(q.encryptedUrl, startsWith('ytdlp:raw:'));
      }
    });

    test('deduplicates video-only by height+codec', () async {
      when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
      // Two 1080p H.264 formats — should be deduplicated to one
      whenExtractInfo().thenAnswer((_) async => YtDlpVideoInfo(
            id: 'test',
            title: 'Test',
            platform: 'youtube',
            formats: [
              YtDlpFormat(
                formatId: '137',
                ext: 'mp4',
                height: 1080,
                width: 1920,
                vcodec: 'avc1.640028',
                acodec: 'none',
              ),
              YtDlpFormat(
                formatId: '298',
                ext: 'mp4',
                height: 1080,
                width: 1920,
                vcodec: 'avc1.640032',
                acodec: 'none',
                fps: 60,
              ),
            ],
          ));

      final result = await useCase(testUrl, engine: DownloadEngine.ytdlpOnly);

      final videoOnly = result.dataOrNull!.availableQualities
          .where((q) => q.isVideoOnly)
          .toList();

      // Both are H.264 1080p (avc1 maps to H.264) — only first should survive dedup
      final h264Count = videoOnly.where((q) =>
          q.qualityText.contains('H.264') &&
          q.qualityText.contains('1080p')).length;
      expect(h264Count, 1);
    });

    test('video-only preserves raw metadata (vcodec, fps, tbr)', () async {
      when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
      whenExtractInfo().thenAnswer((_) async => YtDlpVideoInfo(
            id: 'test',
            title: 'Test',
            platform: 'youtube',
            formats: [
              YtDlpFormat(
                formatId: '299',
                ext: 'mp4',
                height: 1080,
                width: 1920,
                vcodec: 'avc1.640028',
                acodec: 'none',
                fps: 60,
                tbr: 5000,
              ),
            ],
          ));

      final result = await useCase(testUrl, engine: DownloadEngine.ytdlpOnly);

      final videoOnly = result.dataOrNull!.availableQualities
          .where((q) => q.isVideoOnly)
          .first;

      expect(videoOnly.vcodec, 'avc1.640028');
      expect(videoOnly.fps, 60);
      expect(videoOnly.tbr, 5000);
    });
  });

  group('Subtitle download options', () {
    test('includes original subtitles in qualities', () async {
      when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
      whenExtractInfo().thenAnswer((_) async => makeYtdlpInfoWithStreams(
            subtitles: [
              YtDlpSubtitleInfo(lang: 'en', langName: 'English', ext: 'vtt'),
              YtDlpSubtitleInfo(lang: 'ja', langName: 'Japanese', ext: 'vtt'),
            ],
          ));

      final result = await useCase(testUrl, engine: DownloadEngine.ytdlpOnly);

      expect(result.isSuccess, isTrue);
      final subtitleQualities = result.dataOrNull!.availableQualities
          .where((q) => q.mediaType == MediaType.subtitle)
          .toList();

      expect(subtitleQualities.length, 2);
      expect(subtitleQualities[0].qualityText, contains('English'));
      expect(subtitleQualities[1].qualityText, contains('Japanese'));
    });

    test('subtitle qualities use ytdlp:subtitle:LANG pattern', () async {
      when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
      whenExtractInfo().thenAnswer((_) async => makeYtdlpInfoWithStreams(
            subtitles: [
              YtDlpSubtitleInfo(lang: 'en', langName: 'English', ext: 'vtt'),
            ],
          ));

      final result = await useCase(testUrl, engine: DownloadEngine.ytdlpOnly);

      final subtitleQualities = result.dataOrNull!.availableQualities
          .where((q) => q.mediaType == MediaType.subtitle)
          .toList();

      expect(subtitleQualities.first.encryptedUrl, 'ytdlp:subtitle:en');
    });

    test('auto-generated subtitles use ytdlp:subtitle:auto:LANG pattern', () async {
      when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
      whenExtractInfo().thenAnswer((_) async => makeYtdlpInfoWithStreams(
            automaticCaptions: [
              YtDlpSubtitleInfo(lang: 'vi', langName: 'Vietnamese', ext: 'vtt'),
            ],
          ));

      final result = await useCase(testUrl, engine: DownloadEngine.ytdlpOnly);

      final subtitleQualities = result.dataOrNull!.availableQualities
          .where((q) => q.mediaType == MediaType.subtitle)
          .toList();

      expect(subtitleQualities.first.encryptedUrl, 'ytdlp:subtitle:auto:vi');
      expect(subtitleQualities.first.size, 'Auto-generated');
    });

    test('deduplicates subtitles by lang code', () async {
      when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
      whenExtractInfo().thenAnswer((_) async => makeYtdlpInfoWithStreams(
            subtitles: [
              YtDlpSubtitleInfo(lang: 'en', langName: 'English', ext: 'vtt'),
              YtDlpSubtitleInfo(lang: 'en', langName: 'English', ext: 'srt'), // duplicate
            ],
          ));

      final result = await useCase(testUrl, engine: DownloadEngine.ytdlpOnly);

      final subtitleQualities = result.dataOrNull!.availableQualities
          .where((q) => q.mediaType == MediaType.subtitle)
          .toList();

      // Only 1 English subtitle (deduplicated by lang code)
      expect(subtitleQualities.length, 1);
    });

    test('mixes original + auto subtitles', () async {
      when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
      whenExtractInfo().thenAnswer((_) async => makeYtdlpInfoWithStreams(
            subtitles: [
              YtDlpSubtitleInfo(lang: 'en', langName: 'English', ext: 'vtt'),
            ],
            automaticCaptions: [
              YtDlpSubtitleInfo(lang: 'vi', langName: 'Vietnamese', ext: 'vtt'),
              YtDlpSubtitleInfo(lang: 'ja', langName: 'Japanese', ext: 'vtt'),
            ],
          ));

      final result = await useCase(testUrl, engine: DownloadEngine.ytdlpOnly);

      final subtitleQualities = result.dataOrNull!.availableQualities
          .where((q) => q.mediaType == MediaType.subtitle)
          .toList();

      expect(subtitleQualities.length, 3);
      // Original subtitles come first
      expect(subtitleQualities[0].encryptedUrl, 'ytdlp:subtitle:en');
      expect(subtitleQualities[0].size, 'Original subtitle');
      // Auto-generated after
      expect(subtitleQualities[1].encryptedUrl, 'ytdlp:subtitle:auto:vi');
      expect(subtitleQualities[1].size, 'Auto-generated');
    });
  });

  group('Codec name formatting', () {
    test('muxed qualities preserve vcodec metadata', () async {
      when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
      whenExtractInfo().thenAnswer((_) async => YtDlpVideoInfo(
            id: 'test',
            title: 'Test',
            platform: 'youtube',
            formats: [
              YtDlpFormat(
                formatId: '137',
                ext: 'mp4',
                height: 1080,
                width: 1920,
                vcodec: 'avc1.640028',
                acodec: 'mp4a.40.2',
              ),
            ],
          ));

      final result = await useCase(testUrl, engine: DownloadEngine.ytdlpOnly);

      final qualities = result.dataOrNull!.availableQualities;
      // Skip "Best Available" (index 0) — its qualityText also contains "1080p"
      final q1080 = qualities.firstWhere((q) =>
          q.qualityText == '1080p' && !q.isVideoOnly);
      expect(q1080.vcodec, 'avc1.640028');
      expect(q1080.acodec, 'mp4a.40.2');
    });
  });

  group('MediaType.subtitle in path suggestion', () {
    late DownloadPathSuggestionService pathService;

    setUp(() {
      pathService = DownloadPathSuggestionService();
    });

    test('youtube + subtitle → "YouTube Subtitles"', () {
      expect(
        pathService.suggestSubdirectory(VideoPlatform.youtube, MediaType.subtitle),
        'YouTube Subtitles',
      );
    });

    test('tiktok + subtitle → "TikTok Subtitles"', () {
      expect(
        pathService.suggestSubdirectory(VideoPlatform.tiktok, MediaType.subtitle),
        'TikTok Subtitles',
      );
    });

    test('unknown + subtitle → "Subtitles"', () {
      expect(
        pathService.suggestSubdirectory(VideoPlatform.unknown, MediaType.subtitle),
        'Subtitles',
      );
    });

    test('all platforms have subtitle mapping', () {
      for (final platform in VideoPlatform.values) {
        final result = pathService.suggestSubdirectory(platform, MediaType.subtitle);
        expect(result, isNotEmpty,
            reason: '$platform should have subtitle mapping');
        expect(result, contains('Subtitle'),
            reason: '$platform subtitle should contain "Subtitle"');
      }
    });
  });

  group('Quality entity extensions', () {
    test('isVideoOnly defaults to false', () {
      const q = Quality(
        qualityText: 'Test',
        size: '10 MB',
        encryptedUrl: 'ytdlp:1080p',
        mediaType: MediaType.video,
      );
      expect(q.isVideoOnly, isFalse);
    });

    test('isAudioOnly defaults to false', () {
      const q = Quality(
        qualityText: 'Test',
        size: '10 MB',
        encryptedUrl: 'ytdlp:1080p',
        mediaType: MediaType.video,
      );
      expect(q.isAudioOnly, isFalse);
    });

    test('Quality with video-only flag', () {
      const q = Quality(
        qualityText: '1080p Video Only (H.264)',
        size: '150 MB',
        encryptedUrl: 'ytdlp:raw:137',
        mediaType: MediaType.video,
        isVideoOnly: true,
        vcodec: 'avc1.640028',
      );
      expect(q.isVideoOnly, isTrue);
      expect(q.vcodec, 'avc1.640028');
      expect(q.mediaType, MediaType.video);
    });

    test('Quality with subtitle type', () {
      const q = Quality(
        qualityText: 'English (en)',
        size: 'Original subtitle',
        encryptedUrl: 'ytdlp:subtitle:en',
        mediaType: MediaType.subtitle,
      );
      expect(q.mediaType, MediaType.subtitle);
      expect(q.encryptedUrl, 'ytdlp:subtitle:en');
    });

    test('MediaType.subtitle displayName', () {
      // In pure-unit test env without EasyLocalization wrap, `.tr()` returns
      // the raw key `mediaType.subtitle` instead of localized "Subtitle".
      // Match by either to keep the contract holding in both environments.
      final name = MediaType.subtitle.displayName;
      expect(
        name == 'Subtitle' || name == 'mediaType.subtitle',
        isTrue,
        reason:
            'Expected localized "Subtitle" or raw i18n key '
            '"mediaType.subtitle", got "$name"',
      );
    });
  });
}
