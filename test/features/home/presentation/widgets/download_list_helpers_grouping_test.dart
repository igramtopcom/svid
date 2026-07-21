import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/domain/entities/download_entity.dart';
import 'package:svid/features/downloads/domain/entities/download_status.dart';
import 'package:svid/features/downloads/domain/entities/user_playlist_membership.dart';
import 'package:svid/features/home/presentation/widgets/download_list_helpers.dart';

DownloadEntity _entity({
  required int id,
  String? playlistId,
  int? playlistIndex,
  String? filename,
  String? url,
  bool isGalleryDl = false,
}) {
  final now = DateTime(2026, 5, 8, 12, 0);
  return DownloadEntity(
    id: id,
    url: url ?? 'https://example.com/v$id',
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
    downloadMethod: isGalleryDl ? 'gallerydl' : 'ytdlp',
  );
}

void main() {
  // V2 reconcile (2026-05-08): the downloads list is no longer
  // allowed to collapse video playlist members into a single
  // grouped card. The right-panel Playlist tab carries the queue
  // context, so a duplicate collapse in the history view obscured
  // "tải 5 video, thấy 1 item". Image carousels (gallery-dl
  // multi-image posts) keep their grouped card. These tests pin
  // both contracts so neither side regresses silently.
  group('buildDownloadListItems — yt_* video playlist (revert grouping)',
      () {
    test('emits 5 SingleItems for a 5-video YouTube playlist', () {
      // Out-of-order createdAt: realistic case where the user picked
      // 5 videos and they completed in random order. Function must
      // still emit them in playlistIndex order.
      final v1 =
          _entity(id: 10, playlistId: 'yt_xyz', playlistIndex: 1);
      final v2 =
          _entity(id: 11, playlistId: 'yt_xyz', playlistIndex: 2);
      final v3 =
          _entity(id: 12, playlistId: 'yt_xyz', playlistIndex: 3);
      final v4 =
          _entity(id: 13, playlistId: 'yt_xyz', playlistIndex: 4);
      final v5 =
          _entity(id: 14, playlistId: 'yt_xyz', playlistIndex: 5);
      final all = [v3, v5, v1, v4, v2];

      final items = buildDownloadListItems(all);

      expect(items.length, 5,
          reason: '5-video playlist must render 5 rows, not 1 grouped card');
      expect(
        items.every((i) => i is SingleItem),
        isTrue,
        reason: 'no GroupedItem allowed for video playlists in the history',
      );
      expect(
        items.map((i) => (i as SingleItem).download.id).toList(),
        [10, 11, 12, 13, 14],
        reason:
            'rows must follow YouTube playlist order, not download createdAt',
      );
    });

    test('1-video playlist still emits its single SingleItem', () {
      final solo = _entity(id: 7, playlistId: 'yt_solo', playlistIndex: 1);
      final items = buildDownloadListItems([solo]);
      expect(items.length, 1);
      expect(items.first, isA<SingleItem>());
    });
  });

  group('buildDownloadListItems — image carousel (kept grouped)', () {
    test('multi-image gallery-dl post still emits one GroupedItem', () {
      // gallery-dl multi-image posts share a URL — that's the group
      // key. 1 post = N images = 1 row is the correct semantic;
      // unlike video playlists, individual images aren't separate
      // "things" the user would want as queue rows.
      final url = 'https://instagram.com/p/abc';
      final i1 = _entity(
        id: 100,
        url: url,
        filename: 'a.jpg',
        isGalleryDl: true,
      );
      final i2 = _entity(
        id: 101,
        url: url,
        filename: 'b.jpg',
        isGalleryDl: true,
      );
      final i3 = _entity(
        id: 102,
        url: url,
        filename: 'c.jpg',
        isGalleryDl: true,
      );

      final items = buildDownloadListItems([i1, i2, i3]);

      expect(items.length, 1, reason: 'all 3 images live under 1 card');
      expect(items.first, isA<GroupedItem>());
      final g = items.first as GroupedItem;
      expect(g.kind, GroupedItemKind.imageCarousel);
      expect(g.downloads.length, 3);
    });

    test('single-image gallery-dl post falls through to SingleItem', () {
      final solo = _entity(
        id: 200,
        url: 'https://instagram.com/p/xyz',
        filename: 'lone.jpg',
        isGalleryDl: true,
      );
      final items = buildDownloadListItems([solo]);
      expect(items.length, 1);
      expect(items.first, isA<SingleItem>());
    });
  });

  group('buildDownloadListItems — user-curated playlist (revert grouping)',
      () {
    test('user-curated playlist members emit individual SingleItems', () {
      // V2 reconcile: user-curated playlist header card was dropped
      // from the history view because the right-panel Playlist tab
      // and the dedicated playlists screen own that surface now.
      final a = _entity(id: 30, filename: 'a.mp4');
      final b = _entity(id: 31, filename: 'b.mp4');
      final memberships = [
        const UserPlaylistMembership(
          downloadId: 30,
          playlistId: 'user_mix',
          playlistTitle: 'My Mix',
          position: 0,
        ),
        const UserPlaylistMembership(
          downloadId: 31,
          playlistId: 'user_mix',
          playlistTitle: 'My Mix',
          position: 1,
        ),
      ];

      final items =
          buildDownloadListItems([a, b], memberships: memberships);

      expect(items.length, 2,
          reason: '2-member user-curated playlist = 2 individual rows');
      expect(items.every((i) => i is SingleItem), isTrue);
    });
  });

  group('buildDownloadListItems — mixed contexts', () {
    test('plain video, yt playlist, image carousel coexist correctly', () {
      final plain = _entity(id: 1);
      final v1 = _entity(id: 2, playlistId: 'yt_p', playlistIndex: 1);
      final v2 = _entity(id: 3, playlistId: 'yt_p', playlistIndex: 2);
      final image1 = _entity(
        id: 4,
        url: 'https://ig.com/p/1',
        filename: 'a.jpg',
        isGalleryDl: true,
      );
      final image2 = _entity(
        id: 5,
        url: 'https://ig.com/p/1',
        filename: 'b.jpg',
        isGalleryDl: true,
      );

      final items = buildDownloadListItems([plain, v1, v2, image1, image2]);

      // Expected: plain SingleItem + 2 playlist SingleItems + 1
      // image GroupedItem = 4 rows.
      expect(items.length, 4);
      expect(items[0], isA<SingleItem>()); // plain
      expect(items[1], isA<SingleItem>()); // v1
      expect(items[2], isA<SingleItem>()); // v2
      expect(items[3], isA<GroupedItem>()); // image carousel
      expect(
        (items[3] as GroupedItem).kind,
        GroupedItemKind.imageCarousel,
      );
    });
  });
}
