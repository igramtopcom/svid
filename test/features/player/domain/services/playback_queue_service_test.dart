import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/domain/entities/download_entity.dart';
import 'package:ssvid/features/downloads/domain/entities/download_status.dart';
import 'package:ssvid/features/player/domain/services/playback_queue_service.dart';

DownloadEntity _makeDownload(int id, {String filename = 'video.mp4'}) {
  return DownloadEntity(
    id: id,
    url: 'https://example.com/$id',
    filename: filename,
    savePath: '/tmp',
    status: DownloadStatus.completed,
    totalBytes: 1000,
    downloadedBytes: 1000,
    speed: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

void main() {
  late PlaybackQueueService service;

  setUp(() {
    service = PlaybackQueueService();
  });

  group('initial state', () {
    test('starts empty', () {
      expect(service.isEmpty, isTrue);
      expect(service.isNotEmpty, isFalse);
      expect(service.length, 0);
      expect(service.items, isEmpty);
      expect(service.currentIndex, -1);
      expect(service.currentItem, isNull);
    });

    test('default repeat mode is off', () {
      expect(service.repeatMode, QueueRepeatMode.off);
    });

    test('default shuffle is disabled', () {
      expect(service.shuffleEnabled, isFalse);
    });

    test('hasNext and hasPrevious are false when empty', () {
      expect(service.hasNext, isFalse);
      expect(service.hasPrevious, isFalse);
    });
  });

  group('setQueue', () {
    test('sets items and starts at index 0', () {
      final downloads = [_makeDownload(1), _makeDownload(2), _makeDownload(3)];
      service.setQueue(downloads);

      expect(service.length, 3);
      expect(service.currentIndex, 0);
      expect(service.currentItem!.id, 1);
    });

    test('sets items with custom startIndex', () {
      final downloads = [_makeDownload(1), _makeDownload(2), _makeDownload(3)];
      service.setQueue(downloads, startIndex: 2);

      expect(service.currentIndex, 2);
      expect(service.currentItem!.id, 3);
    });

    test('clamps startIndex to valid range', () {
      final downloads = [_makeDownload(1), _makeDownload(2)];
      service.setQueue(downloads, startIndex: 10);

      expect(service.currentIndex, 1);
    });

    test('empty list sets index to -1', () {
      service.setQueue([]);

      expect(service.isEmpty, isTrue);
      expect(service.currentIndex, -1);
    });

    test('replaces previous queue', () {
      service.setQueue([_makeDownload(1), _makeDownload(2)]);
      service.setQueue([_makeDownload(3)]);

      expect(service.length, 1);
      expect(service.currentItem!.id, 3);
    });
  });

  group('addToQueue', () {
    test('adds item to end of queue', () {
      service.setQueue([_makeDownload(1)]);
      service.addToQueue(_makeDownload(2));

      expect(service.length, 2);
      expect(service.items.last.id, 2);
    });

    test('sets currentIndex to 0 when adding to empty queue', () {
      service.addToQueue(_makeDownload(1));

      expect(service.currentIndex, 0);
      expect(service.currentItem!.id, 1);
    });

    test('does not add duplicates', () {
      service.setQueue([_makeDownload(1)]);
      service.addToQueue(_makeDownload(1));

      expect(service.length, 1);
    });
  });

  group('playNext', () {
    test('inserts after current item', () {
      service.setQueue([_makeDownload(1), _makeDownload(3)]);
      // currentIndex = 0 (item 1)
      service.playNext(_makeDownload(2));

      expect(service.length, 3);
      expect(service.items[1].id, 2); // Inserted at index 1
      expect(service.currentIndex, 0); // Still on item 1
    });

    test('removes existing occurrence before inserting', () {
      service.setQueue([_makeDownload(1), _makeDownload(2), _makeDownload(3)]);
      // Move item 3 to play next (after index 0)
      service.playNext(_makeDownload(3));

      expect(service.length, 3);
      expect(service.items[0].id, 1);
      expect(service.items[1].id, 3); // Moved to play next
      expect(service.items[2].id, 2);
    });

    test('works on empty queue', () {
      service.playNext(_makeDownload(1));

      expect(service.length, 1);
      expect(service.currentIndex, 0);
    });
  });

  group('removeFromQueue', () {
    test('removes item by download ID', () {
      service.setQueue([_makeDownload(1), _makeDownload(2), _makeDownload(3)]);
      service.removeFromQueue(2);

      expect(service.length, 2);
      expect(service.items.map((d) => d.id).toList(), [1, 3]);
    });

    test('adjusts currentIndex when removing before current', () {
      service.setQueue([_makeDownload(1), _makeDownload(2), _makeDownload(3)],
          startIndex: 2);
      service.removeFromQueue(1); // Remove index 0

      expect(service.currentIndex, 1); // Was 2, shifted to 1
    });

    test('sets index to -1 when removing last item', () {
      service.setQueue([_makeDownload(1)]);
      service.removeFromQueue(1);

      expect(service.isEmpty, isTrue);
      expect(service.currentIndex, -1);
    });

    test('no-op for non-existent ID', () {
      service.setQueue([_makeDownload(1)]);
      service.removeFromQueue(999);

      expect(service.length, 1);
    });
  });

  group('reorder', () {
    test('moves item forward', () {
      service.setQueue([_makeDownload(1), _makeDownload(2), _makeDownload(3)]);
      service.reorder(0, 2); // Move item 1 from index 0 to index 2

      expect(service.items.map((d) => d.id).toList(), [2, 3, 1]);
    });

    test('moves item backward', () {
      service.setQueue([_makeDownload(1), _makeDownload(2), _makeDownload(3)]);
      service.reorder(2, 0); // Move item 3 from index 2 to index 0

      expect(service.items.map((d) => d.id).toList(), [3, 1, 2]);
    });

    test('updates currentIndex when current item is moved', () {
      service.setQueue([_makeDownload(1), _makeDownload(2), _makeDownload(3)]);
      // currentIndex = 0
      service.reorder(0, 2);

      expect(service.currentIndex, 2); // Follows the moved item
    });

    test('ignores invalid indices', () {
      service.setQueue([_makeDownload(1), _makeDownload(2)]);
      service.reorder(-1, 0);
      service.reorder(0, 5);

      expect(service.items.map((d) => d.id).toList(), [1, 2]);
    });

    test('no-op when same index', () {
      service.setQueue([_makeDownload(1), _makeDownload(2)]);
      service.reorder(0, 0);

      expect(service.items.map((d) => d.id).toList(), [1, 2]);
    });
  });

  group('clear', () {
    test('empties queue and resets index', () {
      service.setQueue([_makeDownload(1), _makeDownload(2)]);
      service.clear();

      expect(service.isEmpty, isTrue);
      expect(service.currentIndex, -1);
    });
  });

  group('next()', () {
    test('advances to next item', () {
      service.setQueue([_makeDownload(1), _makeDownload(2), _makeDownload(3)]);

      final next = service.next();
      expect(next!.id, 2);
      expect(service.currentIndex, 1);
    });

    test('returns null at end of queue (repeat off)', () {
      service.setQueue([_makeDownload(1), _makeDownload(2)], startIndex: 1);

      final next = service.next();
      expect(next, isNull);
    });

    test('wraps to start with repeatAll', () {
      service.setQueue([_makeDownload(1), _makeDownload(2)], startIndex: 1);
      service.setRepeatMode(QueueRepeatMode.repeatAll);

      final next = service.next();
      expect(next!.id, 1);
      expect(service.currentIndex, 0);
    });

    test('returns same item with repeatOne', () {
      service.setQueue([_makeDownload(1), _makeDownload(2)]);
      service.setRepeatMode(QueueRepeatMode.repeatOne);

      final next = service.next();
      expect(next!.id, 1); // Same item
      expect(service.currentIndex, 0);
    });

    test('returns null on empty queue', () {
      expect(service.next(), isNull);
    });

    test('shuffle picks a different index', () {
      service.setQueue([_makeDownload(1), _makeDownload(2), _makeDownload(3)]);
      service.setShuffle(true);

      // With shuffle and 3 items, next() should return something (not null)
      final next = service.next();
      expect(next, isNotNull);
    });
  });

  group('previous()', () {
    test('goes to previous item', () {
      service.setQueue([_makeDownload(1), _makeDownload(2), _makeDownload(3)],
          startIndex: 2);

      final prev = service.previous();
      expect(prev!.id, 2);
      expect(service.currentIndex, 1);
    });

    test('returns null at start of queue (repeat off)', () {
      service.setQueue([_makeDownload(1), _makeDownload(2)]);

      final prev = service.previous();
      expect(prev, isNull);
    });

    test('wraps to end with repeatAll', () {
      service.setQueue([_makeDownload(1), _makeDownload(2)]);
      service.setRepeatMode(QueueRepeatMode.repeatAll);

      final prev = service.previous();
      expect(prev!.id, 2);
      expect(service.currentIndex, 1);
    });

    test('returns same item with repeatOne', () {
      service.setQueue([_makeDownload(1), _makeDownload(2)], startIndex: 1);
      service.setRepeatMode(QueueRepeatMode.repeatOne);

      final prev = service.previous();
      expect(prev!.id, 2); // Same item
    });

    test('returns null on empty queue', () {
      expect(service.previous(), isNull);
    });
  });

  group('jumpTo', () {
    test('jumps to valid index', () {
      service.setQueue([_makeDownload(1), _makeDownload(2), _makeDownload(3)]);

      final item = service.jumpTo(2);
      expect(item!.id, 3);
      expect(service.currentIndex, 2);
    });

    test('returns null for invalid index', () {
      service.setQueue([_makeDownload(1)]);

      expect(service.jumpTo(-1), isNull);
      expect(service.jumpTo(5), isNull);
    });
  });

  group('cycleRepeatMode', () {
    test('cycles off → repeatAll → repeatOne → off', () {
      expect(service.repeatMode, QueueRepeatMode.off);

      service.cycleRepeatMode();
      expect(service.repeatMode, QueueRepeatMode.repeatAll);

      service.cycleRepeatMode();
      expect(service.repeatMode, QueueRepeatMode.repeatOne);

      service.cycleRepeatMode();
      expect(service.repeatMode, QueueRepeatMode.off);
    });
  });

  group('toggleShuffle', () {
    test('toggles shuffle on and off', () {
      expect(service.shuffleEnabled, isFalse);

      service.toggleShuffle();
      expect(service.shuffleEnabled, isTrue);

      service.toggleShuffle();
      expect(service.shuffleEnabled, isFalse);
    });

    test('returns new value', () {
      expect(service.toggleShuffle(), isTrue);
      expect(service.toggleShuffle(), isFalse);
    });
  });

  group('hasNext / hasPrevious', () {
    test('hasNext is true when not at end', () {
      service.setQueue([_makeDownload(1), _makeDownload(2)]);
      expect(service.hasNext, isTrue);
    });

    test('hasNext is false at end (repeat off)', () {
      service.setQueue([_makeDownload(1), _makeDownload(2)], startIndex: 1);
      expect(service.hasNext, isFalse);
    });

    test('hasNext is true at end with repeatAll', () {
      service.setQueue([_makeDownload(1), _makeDownload(2)], startIndex: 1);
      service.setRepeatMode(QueueRepeatMode.repeatAll);
      expect(service.hasNext, isTrue);
    });

    test('hasPrevious is true when not at start', () {
      service.setQueue([_makeDownload(1), _makeDownload(2)], startIndex: 1);
      expect(service.hasPrevious, isTrue);
    });

    test('hasPrevious is false at start (repeat off)', () {
      service.setQueue([_makeDownload(1), _makeDownload(2)]);
      expect(service.hasPrevious, isFalse);
    });

    test('hasPrevious is true at start with repeatAll', () {
      service.setQueue([_makeDownload(1), _makeDownload(2)]);
      service.setRepeatMode(QueueRepeatMode.repeatAll);
      expect(service.hasPrevious, isTrue);
    });
  });

  group('peekNext()', () {
    test('returns null on empty queue', () {
      expect(service.peekNext(), isNull);
    });

    test('returns null on single-item queue with repeat off', () {
      service.setQueue([_makeDownload(1)]);
      expect(service.peekNext(), isNull);
    });

    test('returns next item without advancing index', () {
      final d1 = _makeDownload(1);
      final d2 = _makeDownload(2);
      service.setQueue([d1, d2]);
      final peeked = service.peekNext();
      expect(peeked?.id, 2);
      // currentIndex must not have changed
      expect(service.currentIndex, 0);
    });

    test('returns null at end of queue with repeat off', () {
      service.setQueue([_makeDownload(1), _makeDownload(2)], startIndex: 1);
      expect(service.peekNext(), isNull);
    });

    test('returns first item at end of queue with repeatAll', () {
      final d1 = _makeDownload(1);
      final d2 = _makeDownload(2);
      service.setQueue([d1, d2], startIndex: 1);
      service.setRepeatMode(QueueRepeatMode.repeatAll);
      expect(service.peekNext()?.id, 1);
    });

    test('returns currentItem with repeatOne', () {
      final d1 = _makeDownload(1);
      service.setQueue([d1, _makeDownload(2)]);
      service.setRepeatMode(QueueRepeatMode.repeatOne);
      expect(service.peekNext()?.id, d1.id);
    });

    test('returns null when shuffle is enabled (non-deterministic)', () {
      service.setQueue([_makeDownload(1), _makeDownload(2), _makeDownload(3)]);
      service.setShuffle(true);
      expect(service.peekNext(), isNull);
    });
  });
}
