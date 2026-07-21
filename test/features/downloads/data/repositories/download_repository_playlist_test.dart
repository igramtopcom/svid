/// Tests for the user-curated playlist contract on
/// [DownloadRepositoryImpl] (Hybrid #2 — v20 C-lite).
///
/// Locks the contract that the visual lane is building against — if
/// the dialog or list grouping starts depending on a behavior we
/// haven't promised, these tests fail fast and we notice before
/// regressions ship.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ssvid/core/errors/result.dart';
import 'package:ssvid/features/downloads/data/repositories/download_repository_impl.dart';

import '../../../../shared/mocks/mocks.dart';

void main() {
  late MockDownloadLocalDataSource mockLocalDS;
  late DownloadRepositoryImpl repo;

  setUp(() {
    mockLocalDS = MockDownloadLocalDataSource();
    repo = DownloadRepositoryImpl(mockLocalDS);
  });

  group('addToUserPlaylist — new playlist branch', () {
    test('mints a user_<uuid> id and upserts the playlist row', () async {
      when(
        () => mockLocalDS.upsertUserPlaylist(
          id: any(named: 'id'),
          title: any(named: 'title'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockLocalDS.addDownloadsToUserPlaylist(
          playlistId: any(named: 'playlistId'),
          downloadIds: any(named: 'downloadIds'),
        ),
      ).thenAnswer((_) async {});

      final result = await repo.addToUserPlaylist(
        downloadIds: [1, 2, 3],
        newPlaylistTitle: '  My Mix  ', // intentional whitespace
      );

      expect(result.isSuccess, isTrue);
      final info = result.dataOrThrow;
      // Title is trimmed before persisting.
      expect(info.title, 'My Mix');
      // Id format: user_ + RFC4122 v4 hex.
      expect(
        info.playlistId,
        matches(
          RegExp(
            r'^user_[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
        reason: 'Minted id must be `user_<uuid v4>` per contract',
      );

      // Side effects in correct order.
      verify(
        () => mockLocalDS.upsertUserPlaylist(
          id: info.playlistId,
          title: 'My Mix',
        ),
      ).called(1);
      verify(
        () => mockLocalDS.addDownloadsToUserPlaylist(
          playlistId: info.playlistId,
          downloadIds: [1, 2, 3],
        ),
      ).called(1);
    });

    test('rejects empty title with validation error', () async {
      final result = await repo.addToUserPlaylist(
        downloadIds: [1],
        newPlaylistTitle: '   ', // whitespace-only
      );
      expect(result.isFailure, isTrue);
      // Datasource is never touched — fail-fast happens before any I/O.
      verifyNever(
        () => mockLocalDS.upsertUserPlaylist(
          id: any(named: 'id'),
          title: any(named: 'title'),
        ),
      );
    });

    test('rejects null title (no playlistId, no newPlaylistTitle)', () async {
      final result = await repo.addToUserPlaylist(downloadIds: [1]);
      expect(result.isFailure, isTrue);
    });
  });

  group('addToUserPlaylist — existing playlist branch', () {
    test('looks up existing title and reuses the persisted name', () async {
      // Caller passes only the id; the repo MUST NOT clobber title.
      when(() => mockLocalDS.getUserPlaylistSummaries()).thenAnswer(
        (_) async => [
          (playlistId: 'user_abc', title: 'Persisted Title', count: 2),
        ],
      );
      when(
        () => mockLocalDS.addDownloadsToUserPlaylist(
          playlistId: any(named: 'playlistId'),
          downloadIds: any(named: 'downloadIds'),
        ),
      ).thenAnswer((_) async {});

      final result = await repo.addToUserPlaylist(
        downloadIds: [42],
        playlistId: 'user_abc',
      );

      expect(result.isSuccess, isTrue);
      expect(result.dataOrThrow.title, 'Persisted Title');

      // Critically: upsertUserPlaylist NOT called — we don't overwrite
      // the title when the caller picked an existing playlist.
      verifyNever(
        () => mockLocalDS.upsertUserPlaylist(
          id: any(named: 'id'),
          title: any(named: 'title'),
        ),
      );
      verify(
        () => mockLocalDS.addDownloadsToUserPlaylist(
          playlistId: 'user_abc',
          downloadIds: [42],
        ),
      ).called(1);
    });

    test('fails when playlistId no longer exists', () async {
      when(
        () => mockLocalDS.getUserPlaylistSummaries(),
      ).thenAnswer((_) async => const []);

      final result = await repo.addToUserPlaylist(
        downloadIds: [1],
        playlistId: 'user_deleted',
      );
      expect(result.isFailure, isTrue);
      verifyNever(
        () => mockLocalDS.addDownloadsToUserPlaylist(
          playlistId: any(named: 'playlistId'),
          downloadIds: any(named: 'downloadIds'),
        ),
      );
    });
  });

  group('addToUserPlaylist — input validation', () {
    test('rejects empty downloadIds list', () async {
      final result = await repo.addToUserPlaylist(
        downloadIds: const [],
        newPlaylistTitle: 'Anything',
      );
      expect(result.isFailure, isTrue);
      // No write should happen — the empty-list guard runs before
      // any side effect (mint id, insert row, etc.).
      verifyNever(
        () => mockLocalDS.upsertUserPlaylist(
          id: any(named: 'id'),
          title: any(named: 'title'),
        ),
      );
      verifyNever(
        () => mockLocalDS.addDownloadsToUserPlaylist(
          playlistId: any(named: 'playlistId'),
          downloadIds: any(named: 'downloadIds'),
        ),
      );
    });
  });

  group('createUserPlaylist', () {
    test('mints an empty user playlist row', () async {
      when(
        () => mockLocalDS.upsertUserPlaylist(
          id: any(named: 'id'),
          title: any(named: 'title'),
        ),
      ).thenAnswer((_) async {});

      final result = await repo.createUserPlaylist('  Watch Later  ');

      expect(result.isSuccess, isTrue);
      final info = result.dataOrThrow;
      expect(info.title, 'Watch Later');
      expect(info.playlistId, startsWith('user_'));
      verify(
        () => mockLocalDS.upsertUserPlaylist(
          id: info.playlistId,
          title: 'Watch Later',
        ),
      ).called(1);
      verifyNever(
        () => mockLocalDS.addDownloadsToUserPlaylist(
          playlistId: any(named: 'playlistId'),
          downloadIds: any(named: 'downloadIds'),
        ),
      );
    });

    test('rejects empty title before datasource call', () async {
      final result = await repo.createUserPlaylist('   ');

      expect(result.isFailure, isTrue);
      verifyNever(
        () => mockLocalDS.upsertUserPlaylist(
          id: any(named: 'id'),
          title: any(named: 'title'),
        ),
      );
    });
  });

  group('removeFromUserPlaylist', () {
    test('forwards to datasource with correct keys', () async {
      when(
        () => mockLocalDS.removeDownloadFromUserPlaylist(
          playlistId: any(named: 'playlistId'),
          downloadId: any(named: 'downloadId'),
        ),
      ).thenAnswer((_) async => 1);

      final result = await repo.removeFromUserPlaylist(
        playlistId: 'user_abc',
        downloadId: 42,
      );

      expect(result.isSuccess, isTrue);
      verify(
        () => mockLocalDS.removeDownloadFromUserPlaylist(
          playlistId: 'user_abc',
          downloadId: 42,
        ),
      ).called(1);
    });

    test('idempotent — succeeds even when membership does not exist', () async {
      // Removing a non-member returns 0 from the datasource (no rows
      // affected). The repo treats that as success — the desired end
      // state is "this download is not in this playlist", which is
      // already true.
      when(
        () => mockLocalDS.removeDownloadFromUserPlaylist(
          playlistId: any(named: 'playlistId'),
          downloadId: any(named: 'downloadId'),
        ),
      ).thenAnswer((_) async => 0);

      final result = await repo.removeFromUserPlaylist(
        playlistId: 'user_abc',
        downloadId: 999,
      );

      expect(result.isSuccess, isTrue);
    });

    test('rejects source playlist ids', () async {
      final result = await repo.removeFromUserPlaylist(
        playlistId: 'yt_source',
        downloadId: 42,
      );

      expect(result.isFailure, isTrue);
      verifyNever(
        () => mockLocalDS.removeDownloadFromUserPlaylist(
          playlistId: any(named: 'playlistId'),
          downloadId: any(named: 'downloadId'),
        ),
      );
    });
  });

  group('renameUserPlaylist', () {
    test('trims title and forwards to datasource', () async {
      when(
        () => mockLocalDS.renameUserPlaylist(
          playlistId: any(named: 'playlistId'),
          title: any(named: 'title'),
        ),
      ).thenAnswer((_) async => 1);

      final result = await repo.renameUserPlaylist(
        playlistId: 'user_abc',
        title: '  Renamed  ',
      );

      expect(result.isSuccess, isTrue);
      verify(
        () => mockLocalDS.renameUserPlaylist(
          playlistId: 'user_abc',
          title: 'Renamed',
        ),
      ).called(1);
    });

    test('rejects empty title before datasource call', () async {
      final result = await repo.renameUserPlaylist(
        playlistId: 'user_abc',
        title: '   ',
      );

      expect(result.isFailure, isTrue);
      verifyNever(
        () => mockLocalDS.renameUserPlaylist(
          playlistId: any(named: 'playlistId'),
          title: any(named: 'title'),
        ),
      );
    });

    test('rejects source playlist ids', () async {
      final result = await repo.renameUserPlaylist(
        playlistId: 'yt_source',
        title: 'Nope',
      );

      expect(result.isFailure, isTrue);
      verifyNever(
        () => mockLocalDS.renameUserPlaylist(
          playlistId: any(named: 'playlistId'),
          title: any(named: 'title'),
        ),
      );
    });
  });

  group('deleteUserPlaylist', () {
    test(
      'deletes user playlist and treats missing rows as idempotent',
      () async {
        when(
          () => mockLocalDS.deleteUserPlaylist(any()),
        ).thenAnswer((_) async => 0);

        final result = await repo.deleteUserPlaylist('user_abc');

        expect(result.isSuccess, isTrue);
        verify(() => mockLocalDS.deleteUserPlaylist('user_abc')).called(1);
      },
    );

    test('rejects source playlist ids', () async {
      final result = await repo.deleteUserPlaylist('yt_source');

      expect(result.isFailure, isTrue);
      verifyNever(() => mockLocalDS.deleteUserPlaylist(any()));
    });
  });

  group('reorderUserPlaylist', () {
    test('forwards ordered ids to datasource', () async {
      when(
        () => mockLocalDS.reorderUserPlaylist(
          playlistId: any(named: 'playlistId'),
          orderedDownloadIds: any(named: 'orderedDownloadIds'),
        ),
      ).thenAnswer((_) async {});

      final result = await repo.reorderUserPlaylist(
        playlistId: 'user_abc',
        orderedDownloadIds: [3, 1, 2],
      );

      expect(result.isSuccess, isTrue);
      verify(
        () => mockLocalDS.reorderUserPlaylist(
          playlistId: 'user_abc',
          orderedDownloadIds: [3, 1, 2],
        ),
      ).called(1);
    });

    test('empty ordered ids is a no-op success', () async {
      final result = await repo.reorderUserPlaylist(
        playlistId: 'user_abc',
        orderedDownloadIds: const [],
      );

      expect(result.isSuccess, isTrue);
      verifyNever(
        () => mockLocalDS.reorderUserPlaylist(
          playlistId: any(named: 'playlistId'),
          orderedDownloadIds: any(named: 'orderedDownloadIds'),
        ),
      );
    });

    test('rejects source playlist ids', () async {
      final result = await repo.reorderUserPlaylist(
        playlistId: 'yt_source',
        orderedDownloadIds: [1, 2],
      );

      expect(result.isFailure, isTrue);
      verifyNever(
        () => mockLocalDS.reorderUserPlaylist(
          playlistId: any(named: 'playlistId'),
          orderedDownloadIds: any(named: 'orderedDownloadIds'),
        ),
      );
    });
  });

  group('getUserPlaylists', () {
    test('maps datasource records to UserPlaylistSummary entities', () async {
      when(() => mockLocalDS.getUserPlaylistSummaries()).thenAnswer(
        (_) async => [
          (playlistId: 'user_a', title: 'Mix A', count: 5),
          (playlistId: 'user_b', title: 'Mix B', count: 0),
        ],
      );

      final result = await repo.getUserPlaylists();
      expect(result.isSuccess, isTrue);
      final list = result.dataOrThrow;
      expect(list, hasLength(2));
      expect(list[0].playlistId, 'user_a');
      expect(list[0].title, 'Mix A');
      expect(list[0].count, 5);
      // Empty playlists ARE returned (v20 contract — they exist as
      // first-class rows even with zero members).
      expect(list[1].count, 0);
    });
  });

  group('getUserPlaylistMemberships', () {
    test(
      'preserves datasource ordering (playlist updatedAt DESC, position ASC)',
      () async {
        // The datasource query already orders correctly; the repo MUST
        // pass the order through unchanged. Asserting via fixture order
        // catches accidental sort overrides.
        when(() => mockLocalDS.getUserPlaylistMemberships()).thenAnswer(
          (_) async => [
            (
              downloadId: 10,
              playlistId: 'user_recent',
              playlistTitle: 'Recent',
              position: 0,
            ),
            (
              downloadId: 11,
              playlistId: 'user_recent',
              playlistTitle: 'Recent',
              position: 1,
            ),
            (
              downloadId: 20,
              playlistId: 'user_old',
              playlistTitle: 'Old',
              position: 0,
            ),
          ],
        );

        final result = await repo.getUserPlaylistMemberships();
        expect(result.isSuccess, isTrue);
        final list = result.dataOrThrow;
        expect(list.map((m) => m.downloadId).toList(), [10, 11, 20]);
        expect(list.map((m) => m.position).toList(), [0, 1, 0]);
      },
    );
  });
}
