// Tests for #73: Smart Queue Priority — setPriority() and getPendingReordered()

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ssvid/core/errors/result.dart';
import 'package:ssvid/features/downloads/domain/entities/download_entity.dart';
import 'package:ssvid/features/downloads/domain/entities/download_priority.dart';
import 'package:ssvid/features/downloads/domain/entities/download_status.dart';
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

class _FakeSettingsNotifier extends StateNotifier<SettingsState>
    implements SettingsNotifier {
  _FakeSettingsNotifier()
      : super(const SettingsState(
          downloadPath: '/tmp',
          maxConcurrentDownloads: 3,
          themeMode: ThemeMode.system,
          autoStartDownloads: false,
          autoClipboardDetection: false,
          notificationsEnabled: false,
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

DownloadEntity _d(
  int id, {
  DownloadStatus status = DownloadStatus.pending,
  int totalBytes = 1000,
  int priority = 0,
  int speed = 0,
}) {
  return DownloadEntity(
    id: id,
    url: 'https://example.com/video_$id.mp4',
    filename: 'video_$id.mp4',
    savePath: '/tmp',
    status: status,
    totalBytes: totalBytes,
    downloadedBytes: 0,
    speed: speed,
    createdAt: DateTime(2026, 1, id),
    updatedAt: DateTime(2026),
    priority: priority,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(DownloadStatus.pending);
  });

  late MockDownloadRepository mockRepo;

  setUp(() {
    mockRepo = MockDownloadRepository();
    when(() => mockRepo.watchAllDownloads())
        .thenAnswer((_) => const Stream.empty());
    when(() => mockRepo.recoverDownloadsOnStartup())
        .thenAnswer((_) async => const Result.success(0));
    when(() => mockRepo.retryDownload(any()))
        .thenAnswer((_) async => const Result.success(null));
    when(() => mockRepo.getDownloadById(any()))
        .thenAnswer((_) async => Result<DownloadEntity>.failure(Exception('not found')));
    when(() => mockRepo.updateDownloadStatus(any(), any(), errorMessage: any(named: 'errorMessage')))
        .thenAnswer((_) async => const Result<void>.success(null));
    when(() => mockRepo.startDownload(any(),
            numSegments: any(named: 'numSegments'),
            maxSpeedBytes: any(named: 'maxSpeedBytes'),
            proxyUrl: any(named: 'proxyUrl'),
            headersJson: any(named: 'headersJson'),
            cookiesString: any(named: 'cookiesString')))
        .thenAnswer((_) async => const Result<void>.success(null));
  });

  ProviderContainer makeContainer(List<DownloadEntity> initial) {
    when(() => mockRepo.watchAllDownloads())
        .thenAnswer((_) => Stream.value(initial));
    return ProviderContainer(
      overrides: [
        downloadRepositoryProvider.overrideWithValue(mockRepo),
        settingsProvider.overrideWith((_) => _FakeSettingsNotifier()),
      ],
    );
  }

  group('setPriority', () {
    test('optimistically updates priority in state', () async {
      final download = _d(1, priority: 0);
      when(() => mockRepo.updatePriority(any(), any()))
          .thenAnswer((_) async => const Result.success(null));

      final container = makeContainer([download]);
      final notifier = container.read(downloadsNotifierProvider.notifier);
      await Future.delayed(const Duration(milliseconds: 50));

      await notifier.setPriority(1, DownloadPriority.high);

      final state = container.read(downloadsNotifierProvider);
      expect(state.downloads.first.priority, 1);
    });

    test('calls updatePriority on repository with correct id and value', () async {
      final download = _d(1, priority: 0);
      when(() => mockRepo.updatePriority(any(), any()))
          .thenAnswer((_) async => const Result.success(null));

      final container = makeContainer([download]);
      final notifier = container.read(downloadsNotifierProvider.notifier);
      await Future.delayed(const Duration(milliseconds: 50));

      await notifier.setPriority(1, DownloadPriority.low);

      verify(() => mockRepo.updatePriority(1, -1)).called(1);
    });

    test('is a no-op when download id is not found', () async {
      final download = _d(1);
      when(() => mockRepo.updatePriority(any(), any()))
          .thenAnswer((_) async => const Result.success(null));

      final container = makeContainer([download]);
      final notifier = container.read(downloadsNotifierProvider.notifier);
      await Future.delayed(const Duration(milliseconds: 50));

      await notifier.setPriority(99, DownloadPriority.high);

      verifyNever(() => mockRepo.updatePriority(any(), any()));
      expect(container.read(downloadsNotifierProvider).downloads.first.priority, 0);
    });

    test('handles persistence failure gracefully without throwing', () async {
      final download = _d(1);
      when(() => mockRepo.updatePriority(any(), any())).thenAnswer(
          (_) async => Result.failure(Exception('DB error')));

      final container = makeContainer([download]);
      final notifier = container.read(downloadsNotifierProvider.notifier);
      await Future.delayed(const Duration(milliseconds: 50));

      await expectLater(
        notifier.setPriority(1, DownloadPriority.high),
        completes,
      );
    });
  });

  group('getPendingReordered', () {
    test('returns only pending and queued downloads', () async {
      final items = [
        _d(1, status: DownloadStatus.pending),
        _d(2, status: DownloadStatus.downloading),
        _d(3, status: DownloadStatus.queued),
        _d(4, status: DownloadStatus.completed),
      ];
      final container = makeContainer(items);
      final notifier = container.read(downloadsNotifierProvider.notifier);
      await Future.delayed(const Duration(milliseconds: 50));

      final result = notifier.getPendingReordered(networkAwareEnabled: false);

      expect(result.map((d) => d.id).toList(), containsAll([1, 3]));
      expect(result.length, 2);
    });

    test('returns original order when networkAwareEnabled is false', () async {
      final items = [
        _d(1, totalBytes: 5000),
        _d(2, totalBytes: 100),
      ];
      final container = makeContainer(items);
      final notifier = container.read(downloadsNotifierProvider.notifier);
      await Future.delayed(const Duration(milliseconds: 50));

      final result = notifier.getPendingReordered(networkAwareEnabled: false);

      expect(result[0].id, 1); // original order preserved
      expect(result[1].id, 2);
    });

    test('returns empty list when no pending/queued downloads exist', () async {
      final items = [
        _d(1, status: DownloadStatus.completed),
        _d(2, status: DownloadStatus.failed),
      ];
      final container = makeContainer(items);
      final notifier = container.read(downloadsNotifierProvider.notifier);
      await Future.delayed(const Duration(milliseconds: 50));

      final result = notifier.getPendingReordered(networkAwareEnabled: true);

      expect(result, isEmpty);
    });

    test('reorders smaller files first when bandwidth is slow', () async {
      // speed=0 on all active → aggregateBps=0 < 2MB/s
      final items = [
        _d(1, totalBytes: 5000),
        _d(2, totalBytes: 100),
        _d(3, status: DownloadStatus.downloading, speed: 0),
      ];
      final container = makeContainer(items);
      final notifier = container.read(downloadsNotifierProvider.notifier);
      await Future.delayed(const Duration(milliseconds: 50));

      final result = notifier.getPendingReordered(networkAwareEnabled: true);

      expect(result[0].id, 2); // smaller first
      expect(result[1].id, 1);
    });

    test('preserves original order when aggregate bandwidth >= 2 MB/s', () async {
      const twombps = 2 * 1024 * 1024;
      final items = [
        _d(1, totalBytes: 5000),
        _d(2, totalBytes: 100),
        _d(3, status: DownloadStatus.downloading, speed: twombps),
      ];
      final container = makeContainer(items);
      final notifier = container.read(downloadsNotifierProvider.notifier);
      await Future.delayed(const Duration(milliseconds: 50));

      final result = notifier.getPendingReordered(networkAwareEnabled: true);

      // Fast bandwidth → original order unchanged
      expect(result[0].id, 1);
      expect(result[1].id, 2);
    });

    test('aggregates speed from multiple downloading items', () async {
      const oneMbps = 1024 * 1024;
      // Two downloads each at 1 MB/s → aggregate 2 MB/s → fast path
      final items = [
        _d(1, totalBytes: 5000),
        _d(2, totalBytes: 100),
        _d(3, status: DownloadStatus.downloading, speed: oneMbps),
        _d(4, status: DownloadStatus.downloading, speed: oneMbps),
      ];
      final container = makeContainer(items);
      final notifier = container.read(downloadsNotifierProvider.notifier);
      await Future.delayed(const Duration(milliseconds: 50));

      final result = notifier.getPendingReordered(networkAwareEnabled: true);

      // aggregate 2MB/s = threshold → fast path (not reordered)
      expect(result[0].id, 1);
      expect(result[1].id, 2);
    });
  });
}
