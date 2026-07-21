import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ssvid/features/browser/presentation/providers/browser_download_providers.dart';
import 'package:ssvid/features/downloads/domain/entities/download_entity.dart';
import 'package:ssvid/features/downloads/domain/entities/download_status.dart';
import 'package:ssvid/features/downloads/presentation/providers/downloads_notifier.dart';

DownloadEntity _makeDownload({
  required int id,
  DownloadStatus status = DownloadStatus.downloading,
  int speed = 0,
  int totalBytes = 1000,
  int downloadedBytes = 500,
}) {
  return DownloadEntity(
    id: id,
    url: 'https://example.com/$id',
    filename: 'file_$id.mp4',
    savePath: '/tmp',
    status: status,
    totalBytes: totalBytes,
    downloadedBytes: downloadedBytes,
    speed: speed,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

/// Fake StateNotifier that provides a fixed DownloadsState.
class _FakeDownloadsNotifier extends StateNotifier<DownloadsState>
    implements DownloadsNotifier {
  _FakeDownloadsNotifier(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('browserActiveDownloadsProvider', () {
    test('filters active downloads only', () {
      final container = ProviderContainer(
        overrides: [
          downloadsNotifierProvider.overrideWith((_) {
            return _FakeDownloadsNotifier(DownloadsState(downloads: [
              _makeDownload(id: 1, status: DownloadStatus.downloading),
              _makeDownload(id: 2, status: DownloadStatus.completed),
              _makeDownload(id: 3, status: DownloadStatus.pending),
              _makeDownload(id: 4, status: DownloadStatus.failed),
              _makeDownload(id: 5, status: DownloadStatus.queued),
              _makeDownload(id: 6, status: DownloadStatus.paused),
              _makeDownload(id: 7, status: DownloadStatus.postProcessing),
              _makeDownload(id: 8, status: DownloadStatus.cancelled),
            ]));
          }),
        ],
      );
      addTearDown(container.dispose);

      final active = container.read(browserActiveDownloadsProvider);
      final ids = active.map((d) => d.id).toSet();

      // downloading, pending, queued, postProcessing are active
      expect(ids, {1, 3, 5, 7});
      // completed, failed, paused, cancelled are NOT active
      expect(ids.contains(2), isFalse);
      expect(ids.contains(4), isFalse);
      expect(ids.contains(6), isFalse);
      expect(ids.contains(8), isFalse);
    });

    test('returns empty list when no downloads', () {
      final container = ProviderContainer(
        overrides: [
          downloadsNotifierProvider.overrideWith((_) {
            return _FakeDownloadsNotifier(const DownloadsState());
          }),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(browserActiveDownloadsProvider), isEmpty);
    });

    test('returns empty list when all downloads are terminal', () {
      final container = ProviderContainer(
        overrides: [
          downloadsNotifierProvider.overrideWith((_) {
            return _FakeDownloadsNotifier(DownloadsState(downloads: [
              _makeDownload(id: 1, status: DownloadStatus.completed),
              _makeDownload(id: 2, status: DownloadStatus.failed),
              _makeDownload(id: 3, status: DownloadStatus.cancelled),
            ]));
          }),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(browserActiveDownloadsProvider), isEmpty);
    });
  });

  group('browserTotalSpeedProvider', () {
    test('sums speed of all active downloads', () {
      final container = ProviderContainer(
        overrides: [
          downloadsNotifierProvider.overrideWith((_) {
            return _FakeDownloadsNotifier(DownloadsState(downloads: [
              _makeDownload(
                  id: 1, status: DownloadStatus.downloading, speed: 1000000),
              _makeDownload(
                  id: 2, status: DownloadStatus.downloading, speed: 2000000),
              _makeDownload(
                  id: 3, status: DownloadStatus.completed, speed: 5000000),
            ]));
          }),
        ],
      );
      addTearDown(container.dispose);

      // Only active downloads (1+2), completed excluded
      expect(container.read(browserTotalSpeedProvider), 3000000);
    });

    test('returns 0 when no active downloads', () {
      final container = ProviderContainer(
        overrides: [
          downloadsNotifierProvider.overrideWith((_) {
            return _FakeDownloadsNotifier(const DownloadsState());
          }),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(browserTotalSpeedProvider), 0);
    });

    test('returns 0 when active downloads have zero speed', () {
      final container = ProviderContainer(
        overrides: [
          downloadsNotifierProvider.overrideWith((_) {
            return _FakeDownloadsNotifier(DownloadsState(downloads: [
              _makeDownload(
                  id: 1, status: DownloadStatus.pending, speed: 0),
              _makeDownload(
                  id: 2, status: DownloadStatus.queued, speed: 0),
            ]));
          }),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(browserTotalSpeedProvider), 0);
    });
  });

  group('browserActiveCountProvider', () {
    test('returns count of active downloads', () {
      final container = ProviderContainer(
        overrides: [
          downloadsNotifierProvider.overrideWith((_) {
            return _FakeDownloadsNotifier(DownloadsState(downloads: [
              _makeDownload(id: 1, status: DownloadStatus.downloading),
              _makeDownload(id: 2, status: DownloadStatus.pending),
              _makeDownload(id: 3, status: DownloadStatus.completed),
              _makeDownload(id: 4, status: DownloadStatus.queued),
            ]));
          }),
        ],
      );
      addTearDown(container.dispose);

      // downloading + pending + queued = 3
      expect(container.read(browserActiveCountProvider), 3);
    });

    test('returns 0 when no active downloads', () {
      final container = ProviderContainer(
        overrides: [
          downloadsNotifierProvider.overrideWith((_) {
            return _FakeDownloadsNotifier(const DownloadsState());
          }),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(browserActiveCountProvider), 0);
    });

    test('includes postProcessing in active count', () {
      final container = ProviderContainer(
        overrides: [
          downloadsNotifierProvider.overrideWith((_) {
            return _FakeDownloadsNotifier(DownloadsState(downloads: [
              _makeDownload(id: 1, status: DownloadStatus.postProcessing),
            ]));
          }),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(browserActiveCountProvider), 1);
    });

    test('excludes paused and waitingForNetwork', () {
      final container = ProviderContainer(
        overrides: [
          downloadsNotifierProvider.overrideWith((_) {
            return _FakeDownloadsNotifier(DownloadsState(downloads: [
              _makeDownload(id: 1, status: DownloadStatus.paused),
              _makeDownload(id: 2, status: DownloadStatus.waitingForNetwork),
            ]));
          }),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(browserActiveCountProvider), 0);
    });
  });
}
