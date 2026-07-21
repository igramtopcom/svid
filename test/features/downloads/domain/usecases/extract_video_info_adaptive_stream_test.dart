// Task 83.2 — tests for adaptive stream handling (raw audio streams) in
// ExtractVideoInfoUseCase._convertFormatsToQualities.
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:svid/core/errors/result.dart';
import 'package:svid/features/downloads/data/datasources/ytdlp_datasource.dart';
import 'package:svid/features/downloads/domain/entities/video_info.dart';
import 'package:svid/features/downloads/domain/usecases/extract_video_info_usecase.dart';
import 'package:svid/features/settings/domain/enums/download_engine.dart';

import '../../../../shared/mocks/mocks.dart';

void main() {
  late MockSvidApiService mockApi;
  late MockYtDlpDataSource mockYtdlp;
  late MockGalleryDlDataSource mockGalleryDl;
  late ExtractVideoInfoUseCase useCase;

  const testUrl = 'https://www.youtube.com/watch?v=adaptive83';

  // Minimal video format (muxed)
  YtDlpFormat makeVideoFormat({int height = 1080, String formatId = '137'}) =>
      YtDlpFormat(
        formatId: formatId,
        ext: 'mp4',
        height: height,
        width: height == 1080 ? 1920 : 1280,
        vcodec: 'avc1',
        acodec: 'none', // video-only
      );

  // Audio-only format helper
  YtDlpFormat makeAudioFormat({
    String formatId = '251',
    String acodec = 'opus',
    double? tbr = 128.0,
    int? filesize,
  }) =>
      YtDlpFormat(
        formatId: formatId,
        ext: 'webm',
        vcodec: 'none',
        acodec: acodec,
        tbr: tbr,
        filesize: filesize,
      );

  // Mocked extractInfo that returns a YtDlpVideoInfo with given formats
  void stubExtractInfo(List<YtDlpFormat> formats) {
    when(
      () => mockYtdlp.extractInfo(
        any(),
        cookiesFile: any(named: 'cookiesFile'),
        cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
        proxyUrl: any(named: 'proxyUrl'),
        extractorClient: any(named: 'extractorClient'),
        timeoutSecs: any(named: 'timeoutSecs'),
      ),
    ).thenAnswer(
      (_) async => YtDlpVideoInfo(
        id: 'adaptive83',
        title: 'Adaptive Stream Test',
        description: '',
        uploader: 'TestChannel',
        platform: 'youtube',
        formats: formats,
        isLive: false,
      ),
    );
  }

  // Helper: run use case and return qualities
  Future<List<Quality>> extractQualities(List<YtDlpFormat> formats) async {
    stubExtractInfo(formats);
    final result = await useCase(testUrl, engine: DownloadEngine.ytdlpOnly);
    expect(result.isSuccess, isTrue,
        reason: 'extraction must succeed: ${result.exceptionOrNull}');
    return result.dataOrNull!.availableQualities;
  }

  setUp(() {
    mockApi = MockSvidApiService();
    mockYtdlp = MockYtDlpDataSource();
    mockGalleryDl = MockGalleryDlDataSource();
    useCase = ExtractVideoInfoUseCase(
      mockApi,
      mockYtdlp,
      mockGalleryDl,
      delay: (_) async {},
    );
    when(() => mockYtdlp.isAvailable()).thenAnswer((_) async => true);
    when(() => mockGalleryDl.isAvailable()).thenAnswer((_) async => false);
  });

  group('raw audio streams (Task 83.2)', () {
    test('raw audio stream added for audio-only format', () async {
      final qualities = await extractQualities([
        makeVideoFormat(),
        makeAudioFormat(formatId: '251', acodec: 'opus', tbr: 128.0),
      ]);

      final rawAudio = qualities.where(
        (q) => q.isAudioOnly && q.encryptedUrl.startsWith('ytdlp:raw:'),
      ).toList();

      expect(rawAudio, isNotEmpty);
      expect(rawAudio.first.encryptedUrl, equals('ytdlp:raw:251'));
    });

    test('raw audio stream has correct mediaType=audio and isAudioOnly=true',
        () async {
      final qualities = await extractQualities([
        makeVideoFormat(),
        makeAudioFormat(formatId: '140', acodec: 'mp4a', tbr: 128.0),
      ]);

      final rawAudio = qualities
          .where((q) => q.encryptedUrl == 'ytdlp:raw:140')
          .toList();

      expect(rawAudio, hasLength(1));
      expect(rawAudio.first.mediaType, equals(MediaType.audio));
      expect(rawAudio.first.isAudioOnly, isTrue);
      expect(rawAudio.first.isVideoOnly, isFalse);
    });

    test('raw audio streams sorted by tbr descending (best first)', () async {
      final qualities = await extractQualities([
        makeVideoFormat(),
        makeAudioFormat(formatId: '251', acodec: 'opus', tbr: 128.0),
        makeAudioFormat(formatId: '250', acodec: 'opus', tbr: 70.0),
        makeAudioFormat(formatId: '249', acodec: 'opus', tbr: 50.0),
      ]);

      final rawAudio = qualities
          .where(
            (q) => q.isAudioOnly && q.encryptedUrl.startsWith('ytdlp:raw:'),
          )
          .toList();

      expect(rawAudio.length, greaterThanOrEqualTo(3));
      // First entry must have the highest bitrate (128kbps → formatId 251)
      expect(rawAudio.first.encryptedUrl, equals('ytdlp:raw:251'));
    });

    test('raw audio streams deduplicated by codec+bitrate bucket', () async {
      // Two Opus streams at the same ~128kbps bucket should produce one entry
      final qualities = await extractQualities([
        makeVideoFormat(),
        makeAudioFormat(formatId: '251', acodec: 'opus', tbr: 128.0),
        makeAudioFormat(formatId: '252', acodec: 'opus', tbr: 128.0), // dup
      ]);

      final rawAudio = qualities
          .where(
            (q) => q.isAudioOnly && q.encryptedUrl.startsWith('ytdlp:raw:'),
          )
          .toList();

      // Dedup keeps only the first at 128kbps/opus
      expect(rawAudio.where((q) => q.acodec == 'opus').length, equals(1));
    });

    test('no raw audio streams when no audio-only formats exist', () async {
      // Muxed format only — no audio-only tracks
      final qualities = await extractQualities([
        YtDlpFormat(
          formatId: '22',
          ext: 'mp4',
          height: 720,
          width: 1280,
          vcodec: 'avc1',
          acodec: 'mp4a', // muxed — both v+a
        ),
      ]);

      final rawAudio = qualities
          .where(
            (q) => q.isAudioOnly && q.encryptedUrl.startsWith('ytdlp:raw:'),
          )
          .toList();

      expect(rawAudio, isEmpty);
    });

    test('generic audio conversions (mp3/m4a/opus/wav) still present', () async {
      final qualities = await extractQualities([
        makeVideoFormat(),
        makeAudioFormat(),
      ]);

      final conversionUrls = qualities
          .where((q) => q.encryptedUrl.startsWith('ytdlp:audio:'))
          .map((q) => q.encryptedUrl)
          .toSet();

      expect(conversionUrls, containsAll([
        'ytdlp:audio:mp3',
        'ytdlp:audio:m4a',
        'ytdlp:audio:opus',
        'ytdlp:audio:wav',
      ]));
    });

    test('raw audio stream quality text contains codec and bitrate', () async {
      final qualities = await extractQualities([
        makeVideoFormat(),
        makeAudioFormat(formatId: '251', acodec: 'opus', tbr: 128.0),
      ]);

      final rawAudio = qualities
          .where((q) => q.encryptedUrl == 'ytdlp:raw:251')
          .toList();

      expect(rawAudio.first.qualityText, contains('Opus'));
      expect(rawAudio.first.qualityText, contains('128'));
    });

    test('raw audio stream with no tbr included (bitrate unknown)', () async {
      final qualities = await extractQualities([
        makeVideoFormat(),
        makeAudioFormat(formatId: '251', acodec: 'opus', tbr: null),
      ]);

      final rawAudio = qualities
          .where((q) => q.encryptedUrl == 'ytdlp:raw:251')
          .toList();

      expect(rawAudio, isNotEmpty,
          reason: 'streams without bitrate info should still be included');
    });

    test('raw audio stream with filesize stores filesizeBytes', () async {
      final qualities = await extractQualities([
        makeVideoFormat(),
        makeAudioFormat(
            formatId: '140', acodec: 'mp4a', tbr: 128.0, filesize: 5000000),
      ]);

      final rawAudio = qualities
          .where((q) => q.encryptedUrl == 'ytdlp:raw:140')
          .toList();

      expect(rawAudio.first.filesizeBytes, equals(5000000));
    });

    test('multiple codec raw audio streams all included', () async {
      final qualities = await extractQualities([
        makeVideoFormat(),
        makeAudioFormat(formatId: '251', acodec: 'opus', tbr: 128.0),
        makeAudioFormat(formatId: '140', acodec: 'mp4a', tbr: 128.0),
      ]);

      final rawAudioUrls = qualities
          .where(
            (q) => q.isAudioOnly && q.encryptedUrl.startsWith('ytdlp:raw:'),
          )
          .map((q) => q.encryptedUrl)
          .toSet();

      // Different codecs are NOT deduped (only same codec+bitrate are)
      expect(rawAudioUrls, containsAll(['ytdlp:raw:251', 'ytdlp:raw:140']));
    });

    test('raw audio stream acodec field populated', () async {
      final qualities = await extractQualities([
        makeVideoFormat(),
        makeAudioFormat(formatId: '251', acodec: 'opus', tbr: 128.0),
      ]);

      final rawAudio = qualities
          .where((q) => q.encryptedUrl == 'ytdlp:raw:251')
          .toList();

      expect(rawAudio.first.acodec, equals('opus'));
    });

    test('raw audio stream tbr field populated', () async {
      final qualities = await extractQualities([
        makeVideoFormat(),
        makeAudioFormat(formatId: '251', acodec: 'opus', tbr: 128.0),
      ]);

      final rawAudio = qualities
          .where((q) => q.encryptedUrl == 'ytdlp:raw:251')
          .toList();

      expect(rawAudio.first.tbr, equals(128.0));
    });
  });
}
