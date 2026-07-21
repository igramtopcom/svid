import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/core/utils/queue_reorder_utils.dart';
import 'package:ssvid/features/downloads/domain/entities/download_entity.dart';
import 'package:ssvid/features/downloads/domain/entities/download_status.dart';

DownloadEntity _pending(int id, {int totalBytes = 1000, int priority = 0}) {
  return DownloadEntity(
    id: id,
    url: 'https://example.com/video_$id.mp4',
    filename: 'video_$id.mp4',
    savePath: '/tmp',
    status: DownloadStatus.pending,
    totalBytes: totalBytes,
    downloadedBytes: 0,
    speed: 0,
    createdAt: DateTime(2026, 1, id),
    updatedAt: DateTime(2026),
    priority: priority,
  );
}

void main() {
  const twoMbps = 2 * 1024 * 1024;

  group('reorderForBandwidth', () {
    test('returns list unchanged when bandwidth >= 2 MB/s', () {
      final items = [_pending(1, totalBytes: 500), _pending(2, totalBytes: 100)];
      final result = reorderForBandwidth(items, twoMbps);
      // Identical list (fast path: same object)
      expect(result, same(items));
    });

    test('returns list unchanged when empty', () {
      final result = reorderForBandwidth([], twoMbps - 1);
      expect(result, isEmpty);
    });

    test('places smaller file before larger when bandwidth is slow', () {
      final small = _pending(1, totalBytes: 100);
      final large = _pending(2, totalBytes: 5000);
      final result = reorderForBandwidth([large, small], twoMbps - 1);
      expect(result[0].id, 1); // small first
      expect(result[1].id, 2); // large second
    });

    test('higher priority group always precedes lower priority group', () {
      final lowPriSmall = _pending(1, totalBytes: 50, priority: -1);
      final highPriLarge = _pending(2, totalBytes: 9999, priority: 1);
      final result = reorderForBandwidth([lowPriSmall, highPriLarge], twoMbps - 1);
      expect(result[0].id, 2); // high priority even though larger
      expect(result[1].id, 1);
    });

    test('unknown size (totalBytes==0) sorts to end of its priority group', () {
      final known = _pending(1, totalBytes: 200);
      final unknown = _pending(2, totalBytes: 0);
      final result = reorderForBandwidth([unknown, known], twoMbps - 1);
      expect(result[0].id, 1); // known size first
      expect(result[1].id, 2); // unknown last
    });

    test('does not reorder when items already optimally ordered', () {
      final a = _pending(1, totalBytes: 100);
      final b = _pending(2, totalBytes: 200);
      final result = reorderForBandwidth([a, b], twoMbps - 1);
      expect(result[0].id, 1);
      expect(result[1].id, 2);
    });
  });

  group('hasPendingDownloads', () {
    test('returns true when list contains a pending item', () {
      final items = [_pending(1)];
      expect(hasPendingDownloads(items), isTrue);
    });

    test('returns false for empty list', () {
      expect(hasPendingDownloads([]), isFalse);
    });
  });
}
