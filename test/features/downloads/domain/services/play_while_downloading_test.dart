import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/domain/entities/download_context_menu_action.dart';
import 'package:svid/features/downloads/domain/entities/download_entity.dart';
import 'package:svid/features/downloads/domain/entities/download_status.dart';
import 'package:svid/features/downloads/domain/services/download_context_menu_service.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

DownloadEntity _makeDownloading({
  String filename = 'video.mp4',
  int totalBytes = 10000,
  int downloadedBytes = 1000, // 10% default
}) =>
    DownloadEntity(
      id: 1,
      url: 'https://example.com/video',
      filename: filename,
      savePath: '/tmp',
      status: DownloadStatus.downloading,
      totalBytes: totalBytes,
      downloadedBytes: downloadedBytes,
      speed: 0,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

const _service = DownloadContextMenuService();

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Play-While-Downloading — DownloadContextMenuService', () {
    // ── watchNow availability ──────────────────────────────────────────────

    group('watchNow — video files', () {
      test('included when progress = 10% exactly', () {
        final actions = _service.enabledActions(
          _makeDownloading(totalBytes: 100, downloadedBytes: 10),
        );
        expect(actions, contains(DownloadContextMenuAction.watchNow));
      });

      test('included when progress = 50%', () {
        final actions = _service.enabledActions(
          _makeDownloading(totalBytes: 100, downloadedBytes: 50),
        );
        expect(actions, contains(DownloadContextMenuAction.watchNow));
      });

      test('included when progress = 99%', () {
        final actions = _service.enabledActions(
          _makeDownloading(totalBytes: 100, downloadedBytes: 99),
        );
        expect(actions, contains(DownloadContextMenuAction.watchNow));
      });

      test('NOT included when progress = 9% (below threshold)', () {
        final actions = _service.enabledActions(
          _makeDownloading(totalBytes: 100, downloadedBytes: 9),
        );
        expect(actions, isNot(contains(DownloadContextMenuAction.watchNow)));
      });

      test('NOT included when progress = 0%', () {
        final actions = _service.enabledActions(
          _makeDownloading(totalBytes: 100, downloadedBytes: 0),
        );
        expect(actions, isNot(contains(DownloadContextMenuAction.watchNow)));
      });

      test('NOT included when totalBytes is 0 (unknown size)', () {
        final actions = _service.enabledActions(
          _makeDownloading(totalBytes: 0, downloadedBytes: 0),
        );
        expect(actions, isNot(contains(DownloadContextMenuAction.watchNow)));
      });
    });

    group('watchNow — audio files', () {
      test('mp3 at 10%: included', () {
        final actions = _service.enabledActions(
          _makeDownloading(filename: 'song.mp3', totalBytes: 100, downloadedBytes: 10),
        );
        expect(actions, contains(DownloadContextMenuAction.watchNow));
      });

      test('m4a at 50%: included', () {
        final actions = _service.enabledActions(
          _makeDownloading(filename: 'track.m4a', totalBytes: 100, downloadedBytes: 50),
        );
        expect(actions, contains(DownloadContextMenuAction.watchNow));
      });
    });

    group('watchNow — non-playable files', () {
      test('pdf: NOT included even at 50%', () {
        final actions = _service.enabledActions(
          _makeDownloading(filename: 'document.pdf', totalBytes: 100, downloadedBytes: 50),
        );
        expect(actions, isNot(contains(DownloadContextMenuAction.watchNow)));
      });

      test('zip: NOT included even at 100%', () {
        final actions = _service.enabledActions(
          _makeDownloading(filename: 'archive.zip', totalBytes: 100, downloadedBytes: 100),
        );
        expect(actions, isNot(contains(DownloadContextMenuAction.watchNow)));
      });

      test('jpg image: NOT included', () {
        final actions = _service.enabledActions(
          _makeDownloading(filename: 'photo.jpg', totalBytes: 100, downloadedBytes: 50),
        );
        expect(actions, isNot(contains(DownloadContextMenuAction.watchNow)));
      });
    });

    group('watchNow — status gate', () {
      test('NOT included when status is postProcessing (even at 50%)', () {
        final entity = DownloadEntity(
          id: 1,
          url: 'https://example.com/video',
          filename: 'video.mp4',
          savePath: '/tmp',
          status: DownloadStatus.postProcessing,
          totalBytes: 100,
          downloadedBytes: 50,
          speed: 0,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );
        final actions = _service.enabledActions(entity);
        expect(actions, isNot(contains(DownloadContextMenuAction.watchNow)));
      });

      test('NOT included when status is paused', () {
        final entity = DownloadEntity(
          id: 1,
          url: 'https://example.com/video',
          filename: 'video.mp4',
          savePath: '/tmp',
          status: DownloadStatus.paused,
          totalBytes: 100,
          downloadedBytes: 50,
          speed: 0,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );
        final actions = _service.enabledActions(entity);
        expect(actions, isNot(contains(DownloadContextMenuAction.watchNow)));
      });
    });

    // ── Order of watchNow in action list ─────────────────────────────────

    group('action ordering', () {
      test('watchNow appears BEFORE pause and cancel', () {
        final actions = _service.enabledActions(
          _makeDownloading(totalBytes: 100, downloadedBytes: 10),
        );
        final watchIdx = actions.indexOf(DownloadContextMenuAction.watchNow);
        final pauseIdx = actions.indexOf(DownloadContextMenuAction.pause);
        final cancelIdx = actions.indexOf(DownloadContextMenuAction.cancel);
        expect(watchIdx, isNonNegative);
        expect(watchIdx, lessThan(pauseIdx));
        expect(watchIdx, lessThan(cancelIdx));
      });
    });

    // ── _isPlayableMediaFile — additional extensions ──────────────────────

    group('_isPlayableMediaFile via enabledActions', () {
      for (final ext in ['mkv', 'webm', 'avi', 'mov', 'ts']) {
        test('$ext: included at 10%', () {
          final actions = _service.enabledActions(
            _makeDownloading(filename: 'video.$ext', totalBytes: 100, downloadedBytes: 10),
          );
          expect(actions, contains(DownloadContextMenuAction.watchNow));
        });
      }

      for (final ext in ['aac', 'flac', 'ogg', 'opus']) {
        test('$ext: included at 10%', () {
          final actions = _service.enabledActions(
            _makeDownloading(filename: 'audio.$ext', totalBytes: 100, downloadedBytes: 10),
          );
          expect(actions, contains(DownloadContextMenuAction.watchNow));
        });
      }
    });
  });
}
