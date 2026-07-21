import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/domain/entities/download_entity.dart';
import 'package:svid/features/downloads/domain/entities/download_status.dart';
import 'package:svid/features/downloads/presentation/providers/playlist_library_provider.dart';
import 'package:svid/features/home/presentation/widgets/playlist_queue_seed.dart';

DownloadEntity _entity({
  required int id,
  String? playlistId,
  int? playlistIndex,
  String? filename,
}) {
  final now = DateTime(2026, 5, 8, 12, 0);
  return DownloadEntity(
    id: id,
    url: 'https://example.com/v$id',
    filename: filename ?? 'video$id.mp4',
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

void main() {
  group('selectPlaylistQueueSeed — yt_* playlist members', () {
    test('seeds queue with siblings sorted by playlistIndex', () {
      // 3 members of the same YouTube playlist scattered across the
      // app's downloads list (createdAt order != playlist order is
      // the realistic case — user picked all 3 then they completed
      // out of order).
      final v1 = _entity(id: 10, playlistId: 'yt_abc', playlistIndex: 1);
      final v2 = _entity(id: 11, playlistId: 'yt_abc', playlistIndex: 2);
      final v3 = _entity(id: 12, playlistId: 'yt_abc', playlistIndex: 3);
      final unrelated = _entity(id: 99); // standalone, different list
      final all = [unrelated, v3, v1, v2]; // out of playlist order

      final seed = selectPlaylistQueueSeed(me: v2, all: all);

      expect(seed.queue.length, 3);
      expect(
        seed.queue.map((d) => d.id).toList(),
        [10, 11, 12],
        reason: 'siblings must be playlist-index ordered, not createdAt',
      );
      expect(
        seed.startIndex,
        1,
        reason: 'tapped video v2 sits at index 1 in the sorted queue',
      );
    });

    test('falls back to filename when playlistIndex is missing', () {
      final v1 = _entity(id: 1, playlistId: 'yt_abc', filename: 'a.mp4');
      final v2 = _entity(id: 2, playlistId: 'yt_abc', filename: 'b.mp4');
      // Both missing playlistIndex — sort key collapses to filename.
      final seed = selectPlaylistQueueSeed(me: v2, all: [v2, v1]);
      expect(seed.queue.map((d) => d.filename).toList(), ['a.mp4', 'b.mp4']);
      expect(seed.startIndex, 1);
    });

    test(
      'singleton playlist returns empty seed (no fake "up-next of one")',
      () {
        // Only one member of the playlist exists in downloads — common
        // when the user picked just one episode of a series. The tab
        // should show empty state, not "1 of 1" up-next.
        final solo = _entity(id: 5, playlistId: 'yt_solo', playlistIndex: 1);
        final unrelated = _entity(id: 7);
        final seed = selectPlaylistQueueSeed(me: solo, all: [solo, unrelated]);
        expect(seed.queue, isEmpty);
        expect(seed.startIndex, 0);
      },
    );
  });

  group('selectPlaylistQueueSeed — non-playlist contexts', () {
    test('plain download (no playlistId) returns empty seed', () {
      final me = _entity(id: 1);
      final seed = selectPlaylistQueueSeed(me: me, all: [me]);
      expect(seed.queue, isEmpty);
    });

    test('user-curated playlist (no yt_ prefix) returns empty seed', () {
      // User-curated memberships live outside DownloadEntity — they
      // are tracked in the user_playlist_items table — so this
      // helper deliberately ignores any non-`yt_` playlistId. A
      // user-curated download falling through here clears the queue
      // rather than seeding bad data.
      final user = _entity(id: 1, playlistId: 'user_mix_2026');
      final seed = selectPlaylistQueueSeed(me: user, all: [user]);
      expect(seed.queue, isEmpty);
    });

    test('empty playlistId returns empty seed', () {
      final me = _entity(id: 1, playlistId: '');
      final seed = selectPlaylistQueueSeed(me: me, all: [me]);
      expect(seed.queue, isEmpty);
    });
  });

  group('selectPlaylistLibraryQueueSeed', () {
    test('prefers active user playlist context over source playlist', () {
      final tapped = _entity(id: 2, playlistId: 'yt_source', playlistIndex: 2);
      final sourceMate = _entity(
        id: 1,
        playlistId: 'yt_source',
        playlistIndex: 1,
      );
      final userMate = _entity(id: 3);

      final source = PlaylistLibraryItem(
        id: 'yt_source',
        title: 'Source playlist',
        kind: PlaylistLibraryKind.source,
        downloads: [sourceMate, tapped],
      );
      final user = PlaylistLibraryItem(
        id: 'user_mix',
        title: 'My mix',
        kind: PlaylistLibraryKind.user,
        downloads: [userMate, tapped],
      );

      final seed = selectPlaylistLibraryQueueSeed(
        me: tapped,
        playlists: [source, user],
        activePlaylistKey: user.key,
      );

      expect(seed.queue.map((d) => d.id), [3, 2]);
      expect(seed.startIndex, 1);
    });

    test('ignores singleton and empty playlist contexts', () {
      final tapped = _entity(id: 8);
      final singleton = PlaylistLibraryItem(
        id: 'user_single',
        title: 'Single',
        kind: PlaylistLibraryKind.user,
        downloads: [tapped],
      );
      const empty = PlaylistLibraryItem(
        id: 'user_empty',
        title: 'Empty',
        kind: PlaylistLibraryKind.user,
        downloads: [],
      );

      final seed = selectPlaylistLibraryQueueSeed(
        me: tapped,
        playlists: [empty, singleton],
        activePlaylistKey: empty.key,
      );

      expect(seed.queue, isEmpty);
      expect(seed.startIndex, 0);
    });
  });
}
