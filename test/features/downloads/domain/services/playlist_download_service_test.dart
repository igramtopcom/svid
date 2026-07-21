import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/domain/entities/download_entity.dart';
import 'package:svid/features/downloads/domain/entities/download_status.dart';
import 'package:svid/features/downloads/domain/services/playlist_download_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

DownloadEntity _completed({required String url, int id = 1}) {
  return DownloadEntity(
    id: id,
    url: url,
    title: 'Test Video',
    status: DownloadStatus.completed,
    savePath: '/tmp',
    filename: 'video.mp4',
    totalBytes: 1024,
    downloadedBytes: 1024,
    speed: 0,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

DownloadEntity _downloading({required String url, int id = 2}) {
  return DownloadEntity(
    id: id,
    url: url,
    title: 'Pending Video',
    status: DownloadStatus.downloading,
    savePath: '/tmp',
    filename: 'video2.mp4',
    totalBytes: 0,
    downloadedBytes: 0,
    speed: 0,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

void main() {
  late PlaylistDownloadService svc;

  setUp(() => svc = const PlaylistDownloadService());

  // -------------------------------------------------------------------------
  // PlaylistSession
  // -------------------------------------------------------------------------

  group('PlaylistSession', () {
    test('processed = completed + failed + skipped', () {
      final s = PlaylistSession(
        id: 'test',
        total: 10,
        completed: 3,
        failed: 1,
        skipped: 2,
      );
      expect(s.processed, equals(6));
    });

    test('progress = processed / total', () {
      final s = PlaylistSession(id: 'test', total: 10, completed: 5);
      expect(s.progress, closeTo(0.5, 0.001));
    });

    test('progress clamped to 1.0 when processed > total', () {
      final s = PlaylistSession(id: 'test', total: 5, completed: 7);
      expect(s.progress, equals(1.0));
    });

    test('progress is 0.0 when total is 0', () {
      final s = PlaylistSession(id: 'test', total: 0);
      expect(s.progress, equals(0.0));
    });

    test('copyWith updates only specified fields', () {
      final s = PlaylistSession(id: 'test', total: 10, completed: 2, failed: 1);
      final updated = s.copyWith(
        completed: 5,
        phase: PlaylistSessionPhase.queueing,
      );
      expect(updated.id, equals('test'));
      expect(updated.total, equals(10));
      expect(updated.completed, equals(5));
      expect(updated.failed, equals(1));
      expect(updated.phase, PlaylistSessionPhase.queueing);
    });

    test('isActive defaults to true', () {
      final s = PlaylistSession(id: 'test', total: 5);
      expect(s.isActive, isTrue);
      expect(s.phase, PlaylistSessionPhase.extracting);
    });

    test('copyWith can set isActive=false', () {
      final s = PlaylistSession(id: 'test', total: 5);
      expect(s.copyWith(isActive: false).isActive, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // filterPendingUrls
  // -------------------------------------------------------------------------

  group('filterPendingUrls', () {
    test('returns all urls when nothing completed', () {
      final urls = [
        'https://youtube.com/watch?v=AAA',
        'https://youtube.com/watch?v=BBB',
      ];
      expect(svc.filterPendingUrls(urls, []), equals(urls));
    });

    test('removes already-completed URL', () {
      final completed = [_completed(url: 'https://youtube.com/watch?v=AAA')];
      final pending = svc.filterPendingUrls([
        'https://youtube.com/watch?v=AAA',
        'https://youtube.com/watch?v=BBB',
      ], completed);
      expect(pending, equals(['https://youtube.com/watch?v=BBB']));
    });

    test('ignores non-completed downloads (e.g. downloading)', () {
      final downloads = [_downloading(url: 'https://youtube.com/watch?v=AAA')];
      final pending = svc.filterPendingUrls([
        'https://youtube.com/watch?v=AAA',
      ], downloads);
      expect(pending, equals(['https://youtube.com/watch?v=AAA']));
    });

    test('normalises YouTube tracking params (si=...)', () {
      final completed = [_completed(url: 'https://youtube.com/watch?v=AAA')];
      final pending = svc.filterPendingUrls([
        'https://youtube.com/watch?v=AAA&si=tracker123',
      ], completed);
      expect(pending, isEmpty);
    });

    test('returns empty list when all urls already done', () {
      final completed = [
        _completed(url: 'https://youtube.com/watch?v=AAA', id: 1),
        _completed(url: 'https://youtube.com/watch?v=BBB', id: 2),
      ];
      final pending = svc.filterPendingUrls([
        'https://youtube.com/watch?v=AAA',
        'https://youtube.com/watch?v=BBB',
      ], completed);
      expect(pending, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // isAlreadyDownloaded
  // -------------------------------------------------------------------------

  group('isAlreadyDownloaded', () {
    test('returns true for completed URL', () {
      final completed = [_completed(url: 'https://youtube.com/watch?v=ZZZ')];
      expect(
        svc.isAlreadyDownloaded('https://youtube.com/watch?v=ZZZ', completed),
        isTrue,
      );
    });

    test('returns false for URL not in list', () {
      final completed = [_completed(url: 'https://youtube.com/watch?v=ZZZ')];
      expect(
        svc.isAlreadyDownloaded('https://youtube.com/watch?v=NEW', completed),
        isFalse,
      );
    });

    test('returns false for downloading (not completed) URL', () {
      final downloads = [_downloading(url: 'https://youtube.com/watch?v=ZZZ')];
      expect(
        svc.isAlreadyDownloaded('https://youtube.com/watch?v=ZZZ', downloads),
        isFalse,
      );
    });
  });

  // -------------------------------------------------------------------------
  // splitIntoBatches
  // -------------------------------------------------------------------------

  group('splitIntoBatches', () {
    test('empty list returns empty', () {
      expect(svc.splitIntoBatches([]), isEmpty);
    });

    test('splits 5 urls into batches of 2: [[a,b],[c,d],[e]]', () {
      final urls = ['a', 'b', 'c', 'd', 'e'];
      final batches = svc.splitIntoBatches(urls);
      expect(batches.length, equals(3));
      expect(batches[0], equals(['a', 'b']));
      expect(batches[1], equals(['c', 'd']));
      expect(batches[2], equals(['e']));
    });

    test('exact multiple: 4 urls → 2 batches of 2', () {
      final batches = svc.splitIntoBatches(['a', 'b', 'c', 'd']);
      expect(batches.length, equals(2));
    });

    test('single url → one batch of 1', () {
      final batches = svc.splitIntoBatches(['a']);
      expect(batches.length, equals(1));
      expect(batches[0], equals(['a']));
    });

    test('batchSize=3 works correctly', () {
      final batches = svc.splitIntoBatches([
        'a',
        'b',
        'c',
        'd',
        'e',
      ], batchSize: 3);
      expect(batches.length, equals(2));
      expect(batches[0], equals(['a', 'b', 'c']));
      expect(batches[1], equals(['d', 'e']));
    });
  });

  // -------------------------------------------------------------------------
  // URL detection helpers
  // -------------------------------------------------------------------------

  group('isPlaylistUrl', () {
    test('YouTube playlist URL returns true', () {
      expect(
        svc.isPlaylistUrl('https://www.youtube.com/watch?v=AAA&list=PLxxx'),
        isTrue,
      );
    });

    test('YouTube watch URL without list= returns false', () {
      expect(svc.isPlaylistUrl('https://www.youtube.com/watch?v=AAA'), isFalse);
    });

    test('non-YouTube URL returns false', () {
      expect(svc.isPlaylistUrl('https://tiktok.com/@user/video/123'), isFalse);
    });
  });

  group('isChannelUrl', () {
    test('/@handle URL returns true', () {
      expect(svc.isChannelUrl('https://www.youtube.com/@SomeChannel'), isTrue);
    });

    test('/channel/ URL returns true', () {
      expect(
        svc.isChannelUrl('https://www.youtube.com/channel/UC1234'),
        isTrue,
      );
    });

    test('/c/ URL returns true', () {
      expect(svc.isChannelUrl('https://www.youtube.com/c/SomeName'), isTrue);
    });

    test('regular watch URL returns false', () {
      expect(svc.isChannelUrl('https://www.youtube.com/watch?v=AAA'), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // URL normalisation
  // -------------------------------------------------------------------------

  group('normaliseUrlForTest', () {
    test('YouTube watch URLs with different params → same canonical', () {
      const a = 'https://www.youtube.com/watch?v=BBB&si=tracker';
      const b = 'https://www.youtube.com/watch?v=BBB';
      expect(
        PlaylistDownloadService.normaliseUrlForTest(a),
        equals(PlaylistDownloadService.normaliseUrlForTest(b)),
      );
    });

    test('Different video IDs → different canonical', () {
      const a = 'https://www.youtube.com/watch?v=AAA';
      const b = 'https://www.youtube.com/watch?v=BBB';
      expect(
        PlaylistDownloadService.normaliseUrlForTest(a),
        isNot(equals(PlaylistDownloadService.normaliseUrlForTest(b))),
      );
    });
  });
}
