import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/domain/entities/download_entity.dart';
import 'package:svid/features/downloads/domain/entities/download_status.dart';
import 'package:svid/features/downloads/presentation/providers/downloads_notifier.dart';
import 'package:svid/features/downloads/presentation/providers/playlist_library_provider.dart';
import 'package:svid/features/home/presentation/widgets/download_list_helpers.dart';
import 'package:svid/features/player/presentation/providers/playback_queue_providers.dart';

DownloadEntity _entity({
  required int id,
  String? playlistId,
  int? playlistIndex,
}) {
  final now = DateTime(2026, 5, 28);
  return DownloadEntity(
    id: id,
    url: 'https://example.com/v$id',
    filename: 'video$id.mp4',
    savePath: '/downloads',
    status: DownloadStatus.completed,
    totalBytes: 1000,
    downloadedBytes: 1000,
    speed: 0,
    createdAt: now,
    updatedAt: now,
    playlistId: playlistId,
    playlistIndex: playlistIndex,
  );
}

/// Adapter that turns a [ProviderContainer] into a [WidgetRef]-shaped
/// surface the helper can call. We only need `read` + `watch` here —
/// `seedPlaybackQueue` reads three providers and writes one.
class _ContainerRef implements WidgetRef {
  _ContainerRef(this._container);
  final ProviderContainer _container;

  @override
  T read<T>(ProviderListenable<T> provider) => _container.read(provider);

  @override
  T watch<T>(ProviderListenable<T> provider) => _container.read(provider);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _container(List<DownloadEntity> downloads) {
  return ProviderContainer(
    overrides: [
      downloadsNotifierProvider.overrideWith(
        (ref) => _FakeDownloadsNotifier(downloads),
      ),
      playlistLibraryProvider.overrideWith((ref) => const []),
    ],
  );
}

void main() {
  group('seedPlaybackQueue — entry-point queue determinism', () {
    test('seeds from yt_* playlist siblings when library is empty', () {
      final v1 = _entity(id: 1, playlistId: 'yt_abc', playlistIndex: 1);
      final v2 = _entity(id: 2, playlistId: 'yt_abc', playlistIndex: 2);
      final v3 = _entity(id: 3, playlistId: 'yt_abc', playlistIndex: 3);
      final c = _container([v1, v2, v3]);
      addTearDown(c.dispose);

      seedPlaybackQueue(_ContainerRef(c), v2);

      final state = c.read(playbackQueueProvider);
      expect(state.items.map((d) => d.id).toList(), [1, 2, 3]);
      expect(state.currentIndex, 1, reason: 'v2 is startIndex');
    });

    test('returns empty seed when item has no playlist context', () {
      final solo = _entity(id: 42);
      final c = _container([solo]);
      addTearDown(c.dispose);

      seedPlaybackQueue(_ContainerRef(c), solo);

      final state = c.read(playbackQueueProvider);
      expect(state.items, isEmpty);
    });

    test('list-card-tap, grid-card-tap, fullscreen-open seed same queue', () {
      // Phase 0B contract: tapping the same item from any entry point
      // must produce the same queue ordering + startIndex.
      final v1 = _entity(id: 10, playlistId: 'yt_x', playlistIndex: 1);
      final v2 = _entity(id: 11, playlistId: 'yt_x', playlistIndex: 2);
      final v3 = _entity(id: 12, playlistId: 'yt_x', playlistIndex: 3);

      List<int> capture(_ContainerRef ref, ProviderContainer c) {
        seedPlaybackQueue(ref, v2);
        final state = c.read(playbackQueueProvider);
        return state.items.map((d) => d.id).toList();
      }

      final listC = _container([v1, v2, v3]);
      final gridC = _container([v1, v2, v3]);
      final openC = _container([v1, v2, v3]);
      addTearDown(listC.dispose);
      addTearDown(gridC.dispose);
      addTearDown(openC.dispose);

      final listSeed = capture(_ContainerRef(listC), listC);
      final gridSeed = capture(_ContainerRef(gridC), gridC);
      final openSeed = capture(_ContainerRef(openC), openC);

      expect(listSeed, [10, 11, 12]);
      expect(gridSeed, listSeed);
      expect(openSeed, listSeed);

      // startIndex must also agree across entry points.
      expect(listC.read(playbackQueueProvider).currentIndex, 1);
      expect(gridC.read(playbackQueueProvider).currentIndex, 1);
      expect(openC.read(playbackQueueProvider).currentIndex, 1);
    });

    test('queue persists across consecutive seeds for different items', () {
      // Tapping v1 then v3 must end with the queue centered on v3.
      final v1 = _entity(id: 1, playlistId: 'yt_x', playlistIndex: 1);
      final v2 = _entity(id: 2, playlistId: 'yt_x', playlistIndex: 2);
      final v3 = _entity(id: 3, playlistId: 'yt_x', playlistIndex: 3);
      final c = _container([v1, v2, v3]);
      addTearDown(c.dispose);
      final ref = _ContainerRef(c);

      seedPlaybackQueue(ref, v1);
      expect(c.read(playbackQueueProvider).currentIndex, 0);

      seedPlaybackQueue(ref, v3);
      expect(c.read(playbackQueueProvider).currentIndex, 2);
      expect(
        c.read(playbackQueueProvider).items.map((d) => d.id).toList(),
        [1, 2, 3],
      );
    });
  });
}

class _FakeDownloadsNotifier extends StateNotifier<DownloadsState>
    implements DownloadsNotifier {
  _FakeDownloadsNotifier(List<DownloadEntity> downloads)
      : super(DownloadsState(downloads: downloads));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
