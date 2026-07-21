import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/domain/entities/download_entity.dart';
import 'package:svid/features/downloads/domain/entities/download_status.dart';
import 'package:svid/features/downloads/domain/entities/user_playlist_membership.dart';
import 'package:svid/features/downloads/domain/entities/user_playlist_summary.dart';
import 'package:svid/features/downloads/presentation/providers/playlist_library_provider.dart';

DownloadEntity _entity({
  required int id,
  String? title,
  String? playlistId,
  String? playlistTitle,
  int? playlistIndex,
  DateTime? updatedAt,
}) {
  final created = DateTime(2026, 5, 16, 10, id);
  return DownloadEntity(
    id: id,
    url: 'https://example.com/v$id',
    filename: 'video$id.mp4',
    savePath: '/downloads',
    status: DownloadStatus.completed,
    totalBytes: 1000,
    downloadedBytes: 1000,
    speed: 0,
    platform: 'youtube',
    createdAt: created,
    updatedAt: updatedAt ?? created,
    title: title,
    playlistId: playlistId,
    playlistTitle: playlistTitle,
    playlistIndex: playlistIndex,
  );
}

void main() {
  group('buildPlaylistLibraryItems', () {
    test('builds source playlist folders in playlist order', () {
      final first = _entity(
        id: 1,
        title: 'First',
        playlistId: 'yt_series',
        playlistTitle: 'Series',
        playlistIndex: 1,
      );
      final second = _entity(
        id: 2,
        title: 'Second',
        playlistId: 'yt_series',
        playlistTitle: 'Series',
        playlistIndex: 2,
      );

      final items = buildPlaylistLibraryItems(
        downloads: [second, first],
        memberships: const [],
      );

      expect(items, hasLength(1));
      expect(items.single.key, 'source:yt_series');
      expect(items.single.title, 'Series');
      expect(items.single.downloads.map((d) => d.id), [1, 2]);
    });

    test('builds user playlists from summaries and memberships', () {
      final older = _entity(id: 1, updatedAt: DateTime(2026, 5, 16, 10));
      final newer = _entity(id: 2, updatedAt: DateTime(2026, 5, 16, 11));

      final items = buildPlaylistLibraryItems(
        downloads: [older, newer],
        userPlaylists: const [
          UserPlaylistSummary(
            playlistId: 'user_mix',
            title: 'My Mix',
            count: 2,
          ),
        ],
        memberships: const [
          UserPlaylistMembership(
            downloadId: 2,
            playlistId: 'user_mix',
            playlistTitle: 'My Mix',
            position: 1,
          ),
          UserPlaylistMembership(
            downloadId: 1,
            playlistId: 'user_mix',
            playlistTitle: 'My Mix',
            position: 0,
          ),
        ],
      );

      expect(items.single.key, 'user:user_mix');
      expect(items.single.title, 'My Mix');
      expect(items.single.downloads.map((d) => d.id), [1, 2]);
    });

    test('keeps empty user playlists visible', () {
      final items = buildPlaylistLibraryItems(
        downloads: const [],
        memberships: const [],
        userPlaylists: const [
          UserPlaylistSummary(
            playlistId: 'user_empty',
            title: 'Watch later',
            count: 0,
          ),
        ],
      );

      expect(items, hasLength(1));
      expect(items.single.key, 'user:user_empty');
      expect(items.single.title, 'Watch later');
      expect(items.single.downloads, isEmpty);
      expect(items.single.count, 0);
    });

    test('keeps a download in both source and user playlist surfaces', () {
      final download = _entity(
        id: 7,
        playlistId: 'yt_original',
        playlistTitle: 'Original',
        playlistIndex: 1,
      );

      final items = buildPlaylistLibraryItems(
        downloads: [download],
        userPlaylists: const [
          UserPlaylistSummary(
            playlistId: 'user_saved',
            title: 'Saved',
            count: 1,
          ),
        ],
        memberships: const [
          UserPlaylistMembership(
            downloadId: 7,
            playlistId: 'user_saved',
            playlistTitle: 'Saved',
            position: 0,
          ),
        ],
      );

      expect(
        items.map((p) => p.key),
        containsAll(['user:user_saved', 'source:yt_original']),
      );
    });
  });
}
