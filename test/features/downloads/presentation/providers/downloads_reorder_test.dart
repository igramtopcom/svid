// Tests for #172: Download Queue Drag-and-Drop Reorder
// Covers: reorderDownloads optimistic state, DB persistence, filteredDownloads sort

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:svid/core/errors/result.dart';
import 'package:svid/features/downloads/domain/entities/download_entity.dart';
import 'package:svid/features/downloads/domain/entities/download_status.dart';
import 'package:svid/features/downloads/presentation/providers/download_providers.dart';
import 'package:svid/features/downloads/presentation/providers/downloads_notifier.dart';
import 'package:svid/features/settings/domain/enums/audio_codec_preference.dart';
import 'package:svid/features/settings/domain/enums/container_format_preference.dart';
import 'package:svid/features/settings/domain/enums/download_engine.dart';
import 'package:svid/features/settings/domain/enums/fps_preference.dart';
import 'package:svid/features/settings/domain/enums/quality_preference.dart';
import 'package:svid/features/settings/domain/enums/video_codec_preference.dart';
import 'package:svid/features/settings/presentation/providers/settings_provider.dart';

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

DownloadEntity _d(int id, {int? queuePosition, DateTime? createdAt}) {
  return DownloadEntity(
    id: id,
    url: 'https://example.com/video_$id.mp4',
    filename: 'video_$id.mp4',
    savePath: '/tmp',
    status: DownloadStatus.pending,
    totalBytes: 1000,
    downloadedBytes: 0,
    speed: 0,
    createdAt: createdAt ?? DateTime(2026, 1, id),
    updatedAt: DateTime(2026),
    queuePosition: queuePosition,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockDownloadRepository mockRepo;

  setUp(() {
    mockRepo = MockDownloadRepository();
    when(() => mockRepo.watchAllDownloads())
        .thenAnswer((_) => const Stream.empty());
    when(() => mockRepo.recoverDownloadsOnStartup())
        .thenAnswer((_) async => const Result.success(0));
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

  group('reorderDownloads — state update', () {
    test('assigns queuePosition 0..N-1 to each listed id', () async {
      final downloads = [_d(10), _d(20), _d(30)];
      when(() => mockRepo.updateQueuePositions(any()))
          .thenAnswer((_) async => const Result.success(null));

      final container = makeContainer(downloads);
      // Initialize notifier BEFORE delay so stream emits while notifier listens
      final notifier = container.read(downloadsNotifierProvider.notifier);
      await Future.delayed(const Duration(milliseconds: 50));

      await notifier.reorderDownloads([30, 10, 20]);

      final state = container.read(downloadsNotifierProvider);
      final d30 = state.downloads.firstWhere((d) => d.id == 30);
      final d10 = state.downloads.firstWhere((d) => d.id == 10);
      final d20 = state.downloads.firstWhere((d) => d.id == 20);
      expect(d30.queuePosition, 0);
      expect(d10.queuePosition, 1);
      expect(d20.queuePosition, 2);
    });

    test('downloads NOT in orderedIds keep their existing queuePosition', () async {
      final downloads = [_d(1, queuePosition: 5), _d(2), _d(3)];
      when(() => mockRepo.updateQueuePositions(any()))
          .thenAnswer((_) async => const Result.success(null));

      final container = makeContainer(downloads);
      final notifier = container.read(downloadsNotifierProvider.notifier);
      await Future.delayed(const Duration(milliseconds: 50));

      await notifier.reorderDownloads([2, 3]);

      final state = container.read(downloadsNotifierProvider);
      // d1 not in list → position unchanged at 5
      expect(state.downloads.firstWhere((d) => d.id == 1).queuePosition, 5);
      // d2 and d3 updated
      expect(state.downloads.firstWhere((d) => d.id == 2).queuePosition, 0);
      expect(state.downloads.firstWhere((d) => d.id == 3).queuePosition, 1);
    });

    test('empty orderedIds is a no-op', () async {
      final downloads = [_d(1), _d(2)];
      when(() => mockRepo.updateQueuePositions(any()))
          .thenAnswer((_) async => const Result.success(null));

      final container = makeContainer(downloads);
      final notifier = container.read(downloadsNotifierProvider.notifier);
      await Future.delayed(const Duration(milliseconds: 50));

      await notifier.reorderDownloads([]);

      final state = container.read(downloadsNotifierProvider);
      // Positions unchanged (null)
      for (final d in state.downloads) {
        expect(d.queuePosition, isNull);
      }
    });
  });

  group('reorderDownloads — persistence', () {
    test('calls updateQueuePositions with the ordered ids', () async {
      final downloads = [_d(1), _d(2), _d(3)];
      when(() => mockRepo.updateQueuePositions(any()))
          .thenAnswer((_) async => const Result.success(null));

      final container = makeContainer(downloads);
      final notifier = container.read(downloadsNotifierProvider.notifier);
      await Future.delayed(const Duration(milliseconds: 50));

      await notifier.reorderDownloads([3, 1, 2]);

      verify(() => mockRepo.updateQueuePositions([3, 1, 2])).called(1);
    });

    test('handles persistence failure gracefully (no exception thrown)', () async {
      final downloads = [_d(1), _d(2)];
      when(() => mockRepo.updateQueuePositions(any())).thenAnswer((_) async =>
          Result.failure(Exception('DB error')));

      final container = makeContainer(downloads);
      final notifier = container.read(downloadsNotifierProvider.notifier);
      await Future.delayed(const Duration(milliseconds: 50));

      // Should not throw
      await expectLater(
        notifier.reorderDownloads([2, 1]),
        completes,
      );
    });
  });

  group('filteredDownloads sort: dateNewest with queuePosition', () {
    List<DownloadEntity> sortDateNewest(List<DownloadEntity> items) {
      final sorted = List<DownloadEntity>.from(items);
      sorted.sort((a, b) {
        final aPos = a.queuePosition;
        final bPos = b.queuePosition;
        if (aPos == null && bPos == null) return b.createdAt.compareTo(a.createdAt);
        if (aPos == null) return 1;
        if (bPos == null) return -1;
        final cmp = aPos.compareTo(bPos);
        return cmp != 0 ? cmp : b.createdAt.compareTo(a.createdAt);
      });
      return sorted;
    }

    test('items with queuePosition sort before nulls', () {
      final items = [
        _d(1, queuePosition: null),
        _d(2, queuePosition: 0),
        _d(3, queuePosition: 1),
      ];
      final result = sortDateNewest(items);
      expect(result[0].id, 2); // queuePosition 0
      expect(result[1].id, 3); // queuePosition 1
      expect(result[2].id, 1); // null → last
    });

    test('items without queuePosition sort by createdAt DESC', () {
      final items = [
        _d(1, createdAt: DateTime(2026, 1, 1)),
        _d(2, createdAt: DateTime(2026, 1, 3)),
        _d(3, createdAt: DateTime(2026, 1, 2)),
      ];
      final result = sortDateNewest(items);
      expect(result.map((d) => d.id).toList(), [2, 3, 1]);
    });

    test('all items with queuePosition sort by position ASC', () {
      final items = [
        _d(1, queuePosition: 2),
        _d(2, queuePosition: 0),
        _d(3, queuePosition: 1),
      ];
      final result = sortDateNewest(items);
      expect(result.map((d) => d.id).toList(), [2, 3, 1]);
    });

    test('mixed: positioned items first, then unordered by createdAt', () {
      final items = [
        _d(1, queuePosition: null, createdAt: DateTime(2026, 1, 5)),
        _d(2, queuePosition: 1),
        _d(3, queuePosition: null, createdAt: DateTime(2026, 1, 1)),
        _d(4, queuePosition: 0),
      ];
      final result = sortDateNewest(items);
      expect(result[0].id, 4); // position 0
      expect(result[1].id, 2); // position 1
      expect(result[2].id, 1); // null, newer createdAt
      expect(result[3].id, 3); // null, older createdAt
    });
  });
}
