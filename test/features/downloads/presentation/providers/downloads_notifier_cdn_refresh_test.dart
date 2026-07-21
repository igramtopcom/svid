import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssvid/core/errors/app_exception.dart';
import 'package:ssvid/core/errors/result.dart';
import 'package:ssvid/features/downloads/domain/entities/download_entity.dart';
import 'package:ssvid/features/downloads/domain/entities/download_status.dart';
import 'package:ssvid/features/downloads/domain/entities/video_info.dart';
import 'package:ssvid/features/downloads/domain/usecases/extract_video_info_usecase.dart';
import 'package:ssvid/features/downloads/presentation/providers/download_providers.dart';
import 'package:ssvid/features/downloads/presentation/providers/downloads_notifier.dart';
import 'package:ssvid/features/settings/domain/enums/audio_codec_preference.dart';
import 'package:ssvid/features/settings/domain/enums/container_format_preference.dart';
import 'package:ssvid/features/settings/domain/enums/download_engine.dart';
import 'package:ssvid/features/settings/domain/enums/fps_preference.dart';
import 'package:ssvid/features/settings/domain/enums/quality_preference.dart';
import 'package:ssvid/features/settings/domain/enums/video_codec_preference.dart';
import 'package:ssvid/features/settings/presentation/providers/settings_provider.dart';

import '../../../../shared/mocks/mocks.dart';

class MockExtractVideoInfoUseCase extends Mock
    implements ExtractVideoInfoUseCase {}

/// Settings fake with notificationsEnabled = false (default for test env).
/// CDN refresh must fire regardless of this setting — that's the key invariant.
class _FakeSettingsNotifier extends StateNotifier<SettingsState>
    implements SettingsNotifier {
  _FakeSettingsNotifier()
      : super(const SettingsState(
          downloadPath: '/tmp',
          maxConcurrentDownloads: 3,
          themeMode: ThemeMode.system,
          autoStartDownloads: false,
          autoClipboardDetection: false,
          notificationsEnabled: false, // notifications OFF — CDN must still run
          preferredQuality: QualityPreference.auto,
          downloadEngine: DownloadEngine.ytdlpOnly,
          autoUpdateYtdlp: false,
          ytdlpTimeout: 30,
          videoCodecPreference: VideoCodecPreference.auto,
          audioCodecPreference: AudioCodecPreference.auto,
          containerFormatPreference: ContainerFormatPreference.mp4,
          fpsPreference: FpsPreference.auto,
          maxResolution: 0,
          subtitlesEnabled: false,
          subtitlesLanguages: ['en'],
          subtitlesFormat: 'srt',
          embedSubtitles: false,
          writeThumbnail: false,
          embedThumbnail: false,
          embedMetadata: false,
          embedChapters: false,
          sponsorBlockEnabled: false,
          sponsorBlockAction: 'skip',
          sponsorBlockCategories: ['sponsor'],
          forceRemux: false,
          tiktokRemoveWatermark: false,
          geoBypass: false,
          archiveEnabled: false,
        ));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// ─── helpers ───────────────────────────────────────────────────────────────

/// A Rust download with a sourceUrl — the primary subject for CDN refresh.
DownloadEntity _makeRustDownload({
  int id = 1,
  DownloadStatus status = DownloadStatus.downloading,
  String errorMessage = '',
  String downloadMethod = 'rust',
  String sourceUrl = 'https://www.youtube.com/watch?v=abc123',
  String? qualityLabel = '1080p',
}) {
  return DownloadEntity(
    id: id,
    url: 'https://cdn.example.com/expired.mp4',
    filename: 'video.mp4',
    savePath: '/tmp',
    status: status,
    totalBytes: 1000,
    downloadedBytes: 0,
    speed: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    errorMessage: errorMessage.isEmpty ? null : errorMessage,
    downloadMethod: downloadMethod,
    sourceUrl: sourceUrl,
    qualityLabel: qualityLabel,
  );
}

/// A VideoInfo with a single direct-URL quality at the given label.
VideoInfo _makeVideoInfo({
  String qualityLabel = '1080p',
  String freshUrl = 'https://cdn.fresh.example.com/video_1080p.mp4',
}) {
  return VideoInfo(
    url: 'https://www.youtube.com/watch?v=abc123',
    title: 'Test Video',
    availableQualities: [
      Quality(
        qualityText: qualityLabel,
        size: '100 MB',
        encryptedUrl: freshUrl,
        mediaType: MediaType.video,
      ),
    ],
    downloadMethod: 'ytdlp',
  );
}

// ─── tests ──────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockDownloadRepository mockRepo;
  late MockExtractVideoInfoUseCase mockExtractUseCase;
  late SharedPreferences prefs;

  setUp(() async {
    mockRepo = MockDownloadRepository();
    mockExtractUseCase = MockExtractVideoInfoUseCase();

    // Mock path_provider channel (used by AppLogger for log file init)
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationSupportDirectory') {
          return '/tmp/test_support';
        }
        return null;
      },
    );

    // Initialize SharedPreferences mock (required by backendClientProvider
    // which is read via analyticsServiceProvider in _handleDownloadStatusChanges)
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    // Common stubs always needed
    when(() => mockRepo.watchAllDownloads())
        .thenAnswer((_) => const Stream.empty());
    when(() => mockRepo.recoverDownloadsOnStartup())
        .thenAnswer((_) async => const Result.success(0));
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
  });

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [
        downloadRepositoryProvider.overrideWithValue(mockRepo),
        settingsProvider.overrideWith((_) => _FakeSettingsNotifier()),
        extractVideoInfoUseCaseProvider.overrideWithValue(mockExtractUseCase),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
  }

  // Helper: emit two snapshots to the notifier's stream to trigger
  // a status transition from [before] to [after].
  Future<ProviderContainer> emitTransition(
    StreamController<List<DownloadEntity>> ctrl,
    DownloadEntity before,
    DownloadEntity after, {
    int delayMs = 150,
  }) async {
    final container = makeContainer();
    when(() => mockRepo.watchAllDownloads())
        .thenAnswer((_) => ctrl.stream);
    container.read(downloadsNotifierProvider.notifier);

    ctrl.add([before]);
    await Future.delayed(const Duration(milliseconds: 50));
    ctrl.add([after]);
    await Future.delayed(Duration(milliseconds: delayMs));

    return container;
  }

  group('Task #181: CDN URL refresh — trigger conditions', () {
    test('HTTP 403 on Rust download triggers re-extraction, updateUrl, and retry',
        () async {
      final ctrl = StreamController<List<DownloadEntity>>();
      final freshUrl = 'https://cdn.fresh.example.com/video_1080p.mp4';

      when(() => mockExtractUseCase(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            cookiesFromBrowserFallback: any(named: 'cookiesFromBrowserFallback'),
            cookiesFromBrowserFallbackChain:
                any(named: 'cookiesFromBrowserFallbackChain'),
          ))
          .thenAnswer((_) async => Result.success(_makeVideoInfo(freshUrl: freshUrl)));
      when(() => mockRepo.updateUrl(1, freshUrl))
          .thenAnswer((_) async => const Result.success(null));
      when(() => mockRepo.getDownloadById(1)).thenAnswer((_) async => Result.success(
            _makeRustDownload(
              id: 1,
              status: DownloadStatus.failed,
              errorMessage: 'HTTP_403_FORBIDDEN: expired CDN token',
            ),
          ));
      when(() => mockRepo.retryDownload(1, retryPlan: any(named: 'retryPlan'), manualRetry: any(named: 'manualRetry')))
          .thenAnswer((_) async => const Result.success(null));

      final before = _makeRustDownload(id: 1, status: DownloadStatus.downloading);
      final after = _makeRustDownload(
        id: 1,
        status: DownloadStatus.failed,
        errorMessage: 'HTTP_403_FORBIDDEN: expired CDN token',
      );

      await emitTransition(ctrl, before, after);

      verify(() => mockExtractUseCase(
            'https://www.youtube.com/watch?v=abc123',
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            cookiesFromBrowserFallback: any(named: 'cookiesFromBrowserFallback'),
            cookiesFromBrowserFallbackChain:
                any(named: 'cookiesFromBrowserFallbackChain'),
          )).called(1);
      verify(() => mockRepo.updateUrl(1, freshUrl)).called(1);
      verify(() => mockRepo.retryDownload(1, retryPlan: any(named: 'retryPlan'), manualRetry: any(named: 'manualRetry'))).called(1);

      await ctrl.close();
    });

    test('yt-dlp download with 403 does NOT trigger CDN refresh', () async {
      final ctrl = StreamController<List<DownloadEntity>>();

      final before = _makeRustDownload(
        id: 1,
        status: DownloadStatus.downloading,
        downloadMethod: 'ytdlp',
      );
      final after = _makeRustDownload(
        id: 1,
        status: DownloadStatus.failed,
        errorMessage: 'HTTP_403_FORBIDDEN: access denied',
        downloadMethod: 'ytdlp',
      );

      await emitTransition(ctrl, before, after);

      verifyNever(() => mockExtractUseCase(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            cookiesFromBrowserFallback: any(named: 'cookiesFromBrowserFallback'),
            cookiesFromBrowserFallbackChain:
                any(named: 'cookiesFromBrowserFallbackChain'),
          ));
      verifyNever(() => mockRepo.updateUrl(any(), any()));

      await ctrl.close();
    });

    test('Rust download with empty sourceUrl does NOT trigger CDN refresh',
        () async {
      final ctrl = StreamController<List<DownloadEntity>>();

      final before =
          _makeRustDownload(id: 1, status: DownloadStatus.downloading, sourceUrl: '');
      final after = _makeRustDownload(
        id: 1,
        status: DownloadStatus.failed,
        errorMessage: 'HTTP_403_FORBIDDEN: expired',
        sourceUrl: '',
      );

      await emitTransition(ctrl, before, after);

      verifyNever(() => mockExtractUseCase(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            cookiesFromBrowserFallback: any(named: 'cookiesFromBrowserFallback'),
            cookiesFromBrowserFallbackChain:
                any(named: 'cookiesFromBrowserFallbackChain'),
          ));

      await ctrl.close();
    });

    test('HTTP 410 (videoNotFound) does NOT trigger CDN refresh', () async {
      final ctrl = StreamController<List<DownloadEntity>>();

      final before = _makeRustDownload(id: 1, status: DownloadStatus.downloading);
      final after = _makeRustDownload(
        id: 1,
        status: DownloadStatus.failed,
        // HTTP_410_GONE → DownloadErrorCode.videoNotFound, not accessDenied
        errorMessage: 'HTTP_410_GONE: resource removed',
      );

      await emitTransition(ctrl, before, after);

      verifyNever(() => mockExtractUseCase(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            cookiesFromBrowserFallback: any(named: 'cookiesFromBrowserFallback'),
            cookiesFromBrowserFallbackChain:
                any(named: 'cookiesFromBrowserFallbackChain'),
          ));

      await ctrl.close();
    });
  });

  group('Task #181: CDN URL refresh — one-shot guard', () {
    test('CDN refresh only fires once per download per session', () async {
      final ctrl = StreamController<List<DownloadEntity>>();
      final freshUrl = 'https://cdn.fresh.example.com/video_1080p.mp4';

      when(() => mockExtractUseCase(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            cookiesFromBrowserFallback: any(named: 'cookiesFromBrowserFallback'),
            cookiesFromBrowserFallbackChain:
                any(named: 'cookiesFromBrowserFallbackChain'),
          ))
          .thenAnswer((_) async => Result.success(_makeVideoInfo(freshUrl: freshUrl)));
      when(() => mockRepo.updateUrl(1, freshUrl))
          .thenAnswer((_) async => const Result.success(null));
      when(() => mockRepo.getDownloadById(1)).thenAnswer((_) async => Result.success(
            _makeRustDownload(id: 1, status: DownloadStatus.failed,
                errorMessage: 'HTTP_403_FORBIDDEN: expired'),
          ));
      when(() => mockRepo.retryDownload(1, retryPlan: any(named: 'retryPlan'), manualRetry: any(named: 'manualRetry')))
          .thenAnswer((_) async => const Result.success(null));

      final container = makeContainer();
      when(() => mockRepo.watchAllDownloads())
          .thenAnswer((_) => ctrl.stream);
      container.read(downloadsNotifierProvider.notifier);

      final downloading = _makeRustDownload(id: 1, status: DownloadStatus.downloading);
      final failed = _makeRustDownload(
        id: 1,
        status: DownloadStatus.failed,
        errorMessage: 'HTTP_403_FORBIDDEN: expired',
      );

      // First transition: downloading → failed (triggers refresh)
      ctrl.add([downloading]);
      await Future.delayed(const Duration(milliseconds: 50));
      ctrl.add([failed]);
      await Future.delayed(const Duration(milliseconds: 100));

      // Second transition: simulate another failed event for the same download
      ctrl.add([downloading]);
      await Future.delayed(const Duration(milliseconds: 50));
      ctrl.add([failed]);
      await Future.delayed(const Duration(milliseconds: 100));

      // Should only have been called once despite two 403 failure transitions
      verify(() => mockExtractUseCase(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            cookiesFromBrowserFallback: any(named: 'cookiesFromBrowserFallback'),
            cookiesFromBrowserFallbackChain:
                any(named: 'cookiesFromBrowserFallbackChain'),
          )).called(1);

      await ctrl.close();
      container.dispose();
    });
  });

  group('Task #181: CDN URL refresh — quality matching', () {
    test('uses exact quality match when qualityLabel matches', () async {
      final ctrl = StreamController<List<DownloadEntity>>();
      const url720 = 'https://cdn.fresh.example.com/video_720p.mp4';
      const url1080 = 'https://cdn.fresh.example.com/video_1080p.mp4';

      // VideoInfo has both 720p and 1080p — download wants 1080p
      final videoInfo = VideoInfo(
        url: 'https://www.youtube.com/watch?v=abc123',
        title: 'Test Video',
        availableQualities: [
          Quality(
              qualityText: '720p',
              size: '50 MB',
              encryptedUrl: url720,
              mediaType: MediaType.video),
          Quality(
              qualityText: '1080p',
              size: '100 MB',
              encryptedUrl: url1080,
              mediaType: MediaType.video),
        ],
        downloadMethod: 'ytdlp',
      );

      when(() => mockExtractUseCase(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            cookiesFromBrowserFallback: any(named: 'cookiesFromBrowserFallback'),
            cookiesFromBrowserFallbackChain:
                any(named: 'cookiesFromBrowserFallbackChain'),
          ))
          .thenAnswer((_) async => Result.success(videoInfo));
      when(() => mockRepo.updateUrl(1, url1080))
          .thenAnswer((_) async => const Result.success(null));
      when(() => mockRepo.getDownloadById(1)).thenAnswer((_) async =>
          Result.success(_makeRustDownload(
              id: 1, status: DownloadStatus.failed,
              errorMessage: 'HTTP_403_FORBIDDEN: expired', qualityLabel: '1080p')));
      when(() => mockRepo.retryDownload(1, retryPlan: any(named: 'retryPlan'), manualRetry: any(named: 'manualRetry')))
          .thenAnswer((_) async => const Result.success(null));

      final before = _makeRustDownload(id: 1, status: DownloadStatus.downloading, qualityLabel: '1080p');
      final after = _makeRustDownload(
          id: 1, status: DownloadStatus.failed,
          errorMessage: 'HTTP_403_FORBIDDEN: expired', qualityLabel: '1080p');

      await emitTransition(ctrl, before, after);

      // Should use 1080p URL, not 720p
      verify(() => mockRepo.updateUrl(1, url1080)).called(1);
      verifyNever(() => mockRepo.updateUrl(1, url720));

      await ctrl.close();
    });

    test('falls back to first quality when exact label not found', () async {
      final ctrl = StreamController<List<DownloadEntity>>();
      const fallbackUrl = 'https://cdn.fresh.example.com/video_720p.mp4';

      // VideoInfo only has 720p, but download wants 1080p
      when(() => mockExtractUseCase(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            cookiesFromBrowserFallback: any(named: 'cookiesFromBrowserFallback'),
            cookiesFromBrowserFallbackChain:
                any(named: 'cookiesFromBrowserFallbackChain'),
          )).thenAnswer((_) async =>
          Result.success(_makeVideoInfo(qualityLabel: '720p', freshUrl: fallbackUrl)));
      when(() => mockRepo.updateUrl(1, fallbackUrl))
          .thenAnswer((_) async => const Result.success(null));
      when(() => mockRepo.getDownloadById(1)).thenAnswer((_) async =>
          Result.success(_makeRustDownload(
              id: 1, status: DownloadStatus.failed,
              errorMessage: 'HTTP_403_FORBIDDEN: expired', qualityLabel: '1080p')));
      when(() => mockRepo.retryDownload(1, retryPlan: any(named: 'retryPlan'), manualRetry: any(named: 'manualRetry')))
          .thenAnswer((_) async => const Result.success(null));

      final before = _makeRustDownload(id: 1, status: DownloadStatus.downloading, qualityLabel: '1080p');
      final after = _makeRustDownload(
          id: 1, status: DownloadStatus.failed,
          errorMessage: 'HTTP_403_FORBIDDEN: expired', qualityLabel: '1080p');

      await emitTransition(ctrl, before, after);

      // Falls back to the first (and only) available quality
      verify(() => mockRepo.updateUrl(1, fallbackUrl)).called(1);

      await ctrl.close();
    });
  });

  group('Task #181: CDN URL refresh — non-direct URL guard', () {
    test('skips updateUrl when re-extracted quality is a yt-dlp encoded URL',
        () async {
      final ctrl = StreamController<List<DownloadEntity>>();

      // Re-extraction returns a yt-dlp URL, not a direct https:// URL
      when(() => mockExtractUseCase(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            cookiesFromBrowserFallback: any(named: 'cookiesFromBrowserFallback'),
            cookiesFromBrowserFallbackChain:
                any(named: 'cookiesFromBrowserFallbackChain'),
          )).thenAnswer((_) async =>
          Result.success(_makeVideoInfo(freshUrl: 'ytdlp:best:mp4')));

      final before = _makeRustDownload(id: 1, status: DownloadStatus.downloading);
      final after = _makeRustDownload(
          id: 1, status: DownloadStatus.failed,
          errorMessage: 'HTTP_403_FORBIDDEN: expired');

      await emitTransition(ctrl, before, after);

      // Extraction was called, but URL is not direct → no updateUrl / retry
      verify(() => mockExtractUseCase(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            cookiesFromBrowserFallback: any(named: 'cookiesFromBrowserFallback'),
            cookiesFromBrowserFallbackChain:
                any(named: 'cookiesFromBrowserFallbackChain'),
          )).called(1);
      verifyNever(() => mockRepo.updateUrl(any(), any()));
      verifyNever(() => mockRepo.retryDownload(any()));

      await ctrl.close();
    });

    test('skips updateUrl when re-extraction returns empty qualities', () async {
      final ctrl = StreamController<List<DownloadEntity>>();

      final emptyInfo = VideoInfo(
        url: 'https://www.youtube.com/watch?v=abc123',
        title: 'Test Video',
        availableQualities: [],
        downloadMethod: 'ytdlp',
      );
      when(() => mockExtractUseCase(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            cookiesFromBrowserFallback: any(named: 'cookiesFromBrowserFallback'),
            cookiesFromBrowserFallbackChain:
                any(named: 'cookiesFromBrowserFallbackChain'),
          ))
          .thenAnswer((_) async => Result.success(emptyInfo));

      final before = _makeRustDownload(id: 1, status: DownloadStatus.downloading);
      final after = _makeRustDownload(
          id: 1, status: DownloadStatus.failed,
          errorMessage: 'HTTP_403_FORBIDDEN: expired');

      await emitTransition(ctrl, before, after);

      verify(() => mockExtractUseCase(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            cookiesFromBrowserFallback: any(named: 'cookiesFromBrowserFallback'),
            cookiesFromBrowserFallbackChain:
                any(named: 'cookiesFromBrowserFallbackChain'),
          )).called(1);
      verifyNever(() => mockRepo.updateUrl(any(), any()));

      await ctrl.close();
    });
  });

  group('Task #181: CDN URL refresh — error handling', () {
    test('handles extraction failure gracefully without crashing', () async {
      final ctrl = StreamController<List<DownloadEntity>>();

      when(() => mockExtractUseCase(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            cookiesFromBrowserFallback: any(named: 'cookiesFromBrowserFallback'),
            cookiesFromBrowserFallbackChain:
                any(named: 'cookiesFromBrowserFallbackChain'),
          )).thenAnswer((_) async =>
          const Result.failure(
              AppException.network(message: 'yt-dlp not available')));

      final before = _makeRustDownload(id: 1, status: DownloadStatus.downloading);
      final after = _makeRustDownload(
          id: 1, status: DownloadStatus.failed,
          errorMessage: 'HTTP_403_FORBIDDEN: expired');

      await emitTransition(ctrl, before, after);

      // Extraction was called; failure logged gracefully — no crash, no retry
      verify(() => mockExtractUseCase(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            cookiesFromBrowserFallback: any(named: 'cookiesFromBrowserFallback'),
            cookiesFromBrowserFallbackChain:
                any(named: 'cookiesFromBrowserFallbackChain'),
          )).called(1);
      verifyNever(() => mockRepo.updateUrl(any(), any()));
      verifyNever(() => mockRepo.retryDownload(any()));

      await ctrl.close();
    });

    test('handles updateUrl failure gracefully without crashing', () async {
      final ctrl = StreamController<List<DownloadEntity>>();
      const freshUrl = 'https://cdn.fresh.example.com/video_1080p.mp4';

      when(() => mockExtractUseCase(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            cookiesFromBrowserFallback: any(named: 'cookiesFromBrowserFallback'),
            cookiesFromBrowserFallbackChain:
                any(named: 'cookiesFromBrowserFallbackChain'),
          ))
          .thenAnswer((_) async => Result.success(_makeVideoInfo(freshUrl: freshUrl)));
      when(() => mockRepo.updateUrl(1, freshUrl)).thenAnswer((_) async =>
          const Result.failure(AppException.storage(message: 'DB locked')));

      final before = _makeRustDownload(id: 1, status: DownloadStatus.downloading);
      final after = _makeRustDownload(
          id: 1, status: DownloadStatus.failed,
          errorMessage: 'HTTP_403_FORBIDDEN: expired');

      await emitTransition(ctrl, before, after);

      verify(() => mockExtractUseCase(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            cookiesFromBrowserFallback: any(named: 'cookiesFromBrowserFallback'),
            cookiesFromBrowserFallbackChain:
                any(named: 'cookiesFromBrowserFallbackChain'),
          )).called(1);
      verify(() => mockRepo.updateUrl(1, freshUrl)).called(1);
      // retryDownload not called when updateUrl fails
      verifyNever(() => mockRepo.retryDownload(any()));

      await ctrl.close();
    });
  });

  group('Task #181: CDN URL refresh — notifications gate', () {
    test('CDN refresh fires even when notificationsEnabled is false', () async {
      // _FakeSettingsNotifier has notificationsEnabled: false — this is the
      // critical regression guard ensuring we moved CDN refresh outside the
      // notifications gate in _handleDownloadStatusChanges.
      final ctrl = StreamController<List<DownloadEntity>>();
      const freshUrl = 'https://cdn.fresh.example.com/video_1080p.mp4';

      when(() => mockExtractUseCase(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            cookiesFromBrowserFallback: any(named: 'cookiesFromBrowserFallback'),
            cookiesFromBrowserFallbackChain:
                any(named: 'cookiesFromBrowserFallbackChain'),
          ))
          .thenAnswer((_) async => Result.success(_makeVideoInfo(freshUrl: freshUrl)));
      when(() => mockRepo.updateUrl(1, freshUrl))
          .thenAnswer((_) async => const Result.success(null));
      when(() => mockRepo.getDownloadById(1)).thenAnswer((_) async =>
          Result.success(_makeRustDownload(
              id: 1, status: DownloadStatus.failed,
              errorMessage: 'HTTP_403_FORBIDDEN: expired')));
      when(() => mockRepo.retryDownload(1, retryPlan: any(named: 'retryPlan'), manualRetry: any(named: 'manualRetry')))
          .thenAnswer((_) async => const Result.success(null));

      final before = _makeRustDownload(id: 1, status: DownloadStatus.downloading);
      final after = _makeRustDownload(
          id: 1, status: DownloadStatus.failed,
          errorMessage: 'HTTP_403_FORBIDDEN: expired');

      await emitTransition(ctrl, before, after);

      // CDN refresh must have fired despite notificationsEnabled = false
      verify(() => mockExtractUseCase(
            any(),
            cookiesFile: any(named: 'cookiesFile'),
            cookiesFromBrowser: any(named: 'cookiesFromBrowser'),
            cookiesFromBrowserFallback: any(named: 'cookiesFromBrowserFallback'),
            cookiesFromBrowserFallbackChain:
                any(named: 'cookiesFromBrowserFallbackChain'),
          )).called(1);
      verify(() => mockRepo.updateUrl(1, freshUrl)).called(1);
      verify(() => mockRepo.retryDownload(1, retryPlan: any(named: 'retryPlan'), manualRetry: any(named: 'manualRetry'))).called(1);

      await ctrl.close();
    });
  });
}
