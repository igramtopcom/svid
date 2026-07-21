import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/domain/entities/download_entity.dart';
import 'package:svid/features/downloads/domain/entities/download_status.dart';
import 'package:svid/features/home/presentation/widgets/download_list_helpers.dart';
import 'package:svid/features/home/presentation/widgets/grouped_card_open_action.dart';

DownloadEntity _entity({required int id, String? filename}) {
  final now = DateTime(2026, 5, 8, 12, 0);
  return DownloadEntity(
    id: id,
    url: 'https://example.com/video$id',
    filename: filename ?? 'video$id.mp4',
    savePath: '/downloads',
    status: DownloadStatus.completed,
    totalBytes: 1000,
    downloadedBytes: 1000,
    speed: 0,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  // The decision routing is the V2 regression fix point. These tests
  // pin both branches so a future kind addition can't silently send
  // a video group into the image viewer or vice-versa.
  group('decideGroupedCardOpenAction', () {
    test('imageCarousel routes to OpenImageCarousel', () {
      final downloads = [
        _entity(id: 1, filename: 'photo1.jpg'),
        _entity(id: 2, filename: 'photo2.jpg'),
        _entity(id: 3, filename: 'photo3.jpg'),
      ];
      final action = decideGroupedCardOpenAction(
        kind: GroupedItemKind.imageCarousel,
        downloads: downloads,
      );
      expect(action, isA<OpenImageCarousel>());
      final image = action as OpenImageCarousel;
      expect(image.first.id, 1, reason: 'first must be the group head');
      expect(image.carousel, downloads,
          reason: 'all sibling images must reach the viewer');
    });

    test('ytSourcePlaylist routes to OpenVideoQueue (V2 regression fix)', () {
      // This is the customer-visible bug case: playlist of YouTube
      // videos rendered as a grouped card. Pre-fix it landed in the
      // image viewer; post-fix it must land in the video player with
      // the queue seeded so up-next works on the first tap.
      final downloads = [
        _entity(id: 10, filename: 'song1.mp4'),
        _entity(id: 11, filename: 'song2.mp4'),
      ];
      final action = decideGroupedCardOpenAction(
        kind: GroupedItemKind.ytSourcePlaylist,
        downloads: downloads,
      );
      expect(action, isA<OpenVideoQueue>());
      final video = action as OpenVideoQueue;
      expect(video.first.id, 10);
      expect(video.queue, downloads);
    });

    test('userPlaylist routes to OpenVideoQueue (same surface as ytSource)', () {
      final downloads = [
        _entity(id: 20),
        _entity(id: 21),
        _entity(id: 22),
      ];
      final action = decideGroupedCardOpenAction(
        kind: GroupedItemKind.userPlaylist,
        downloads: downloads,
      );
      expect(action, isA<OpenVideoQueue>());
      final video = action as OpenVideoQueue;
      expect(video.queue, downloads);
    });

    test('single-item group still routes correctly per kind', () {
      final solo = [_entity(id: 99)];
      expect(
        decideGroupedCardOpenAction(
          kind: GroupedItemKind.imageCarousel,
          downloads: solo,
        ),
        isA<OpenImageCarousel>(),
      );
      expect(
        decideGroupedCardOpenAction(
          kind: GroupedItemKind.ytSourcePlaylist,
          downloads: solo,
        ),
        isA<OpenVideoQueue>(),
      );
    });

    test('throws ArgumentError on empty downloads', () {
      // Defensive — a grouped card with zero rows should never reach
      // activation, but this rule documents the contract so callers
      // don't have to guard.
      expect(
        () => decideGroupedCardOpenAction(
          kind: GroupedItemKind.imageCarousel,
          downloads: const [],
        ),
        throwsArgumentError,
      );
    });
  });
}
