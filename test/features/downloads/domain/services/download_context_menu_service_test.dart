import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/downloads/domain/entities/download_context_menu_action.dart';
import 'package:ssvid/features/downloads/domain/entities/download_entity.dart';
import 'package:ssvid/features/downloads/domain/entities/download_status.dart';
import 'package:ssvid/features/downloads/domain/services/download_context_menu_service.dart';

DownloadEntity _makeEntity({
  DownloadStatus status = DownloadStatus.pending,
}) =>
    DownloadEntity(
      id: 1,
      url: 'https://example.com/video',
      filename: 'video.mp4',
      savePath: '/tmp',
      status: status,
      totalBytes: 1000,
      downloadedBytes: 0,
      speed: 0,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  const service = DownloadContextMenuService();

  group('DownloadContextMenuService', () {
    group('completed download', () {
      test('returns open, folder, playNext, addToQueue, convert, copyUrl, copyFilePath, editNote, markWatched, delete when file exists', () {
        final actions = service.enabledActions(
          _makeEntity(status: DownloadStatus.completed),
        );
        expect(actions, [
          DownloadContextMenuAction.openFile,
          DownloadContextMenuAction.showInFolder,
          if (Platform.isMacOS) DownloadContextMenuAction.shareFile,
          DownloadContextMenuAction.playNext,
          DownloadContextMenuAction.addToQueue,
          DownloadContextMenuAction.convert,
          DownloadContextMenuAction.copyUrl,
          DownloadContextMenuAction.openInBrowser,
          DownloadContextMenuAction.copyFilePath,
          DownloadContextMenuAction.editNote,
          DownloadContextMenuAction.addToPlaylist,
          DownloadContextMenuAction.markWatched,
          DownloadContextMenuAction.delete,
        ]);
      });

      test('omits open, folder, copyFilePath, playNext, addToQueue when file is missing', () {
        final actions = service.enabledActions(
          _makeEntity(status: DownloadStatus.completed),
          isFileMissing: true,
        );
        expect(actions, [
          DownloadContextMenuAction.redownload,
          DownloadContextMenuAction.copyUrl,
          DownloadContextMenuAction.openInBrowser,
          DownloadContextMenuAction.editNote,
          DownloadContextMenuAction.addToPlaylist,
          DownloadContextMenuAction.markWatched,
          DownloadContextMenuAction.delete,
        ]);
      });
    });

    group('downloading', () {
      test('returns pause, cancel, copyUrl, openInBrowser, editNote', () {
        final actions = service.enabledActions(
          _makeEntity(status: DownloadStatus.downloading),
        );
        expect(actions, [
          DownloadContextMenuAction.pause,
          DownloadContextMenuAction.cancel,
          DownloadContextMenuAction.copyUrl,
          DownloadContextMenuAction.openInBrowser,
          DownloadContextMenuAction.editNote,
        ]);
      });
    });

    group('postProcessing', () {
      test('returns cancel, copyUrl, openInBrowser, editNote (cannot pause)', () {
        final actions = service.enabledActions(
          _makeEntity(status: DownloadStatus.postProcessing),
        );
        // postProcessing canPause is false, so no pause
        expect(actions, [
          DownloadContextMenuAction.cancel,
          DownloadContextMenuAction.copyUrl,
          DownloadContextMenuAction.openInBrowser,
          DownloadContextMenuAction.editNote,
        ]);
      });
    });

    group('paused', () {
      test('returns resume, cancel, copyUrl, openInBrowser, editNote, delete', () {
        final actions = service.enabledActions(
          _makeEntity(status: DownloadStatus.paused),
        );
        expect(actions, [
          DownloadContextMenuAction.resume,
          DownloadContextMenuAction.cancel,
          DownloadContextMenuAction.copyUrl,
          DownloadContextMenuAction.openInBrowser,
          DownloadContextMenuAction.editNote,
          DownloadContextMenuAction.delete,
        ]);
      });
    });

    group('failed', () {
      test('returns retry, reportError, copyUrl, openInBrowser, editNote, delete', () {
        final actions = service.enabledActions(
          _makeEntity(status: DownloadStatus.failed),
        );
        expect(actions, [
          DownloadContextMenuAction.retry,
          DownloadContextMenuAction.reportError,
          DownloadContextMenuAction.copyUrl,
          DownloadContextMenuAction.openInBrowser,
          DownloadContextMenuAction.editNote,
          DownloadContextMenuAction.delete,
        ]);
      });
    });

    group('waitingForNetwork', () {
      test('returns retry, reportError, cancel, copyUrl, openInBrowser, editNote, delete', () {
        final actions = service.enabledActions(
          _makeEntity(status: DownloadStatus.waitingForNetwork),
        );
        expect(actions, [
          DownloadContextMenuAction.retry,
          DownloadContextMenuAction.reportError,
          DownloadContextMenuAction.cancel,
          DownloadContextMenuAction.copyUrl,
          DownloadContextMenuAction.openInBrowser,
          DownloadContextMenuAction.editNote,
          DownloadContextMenuAction.delete,
        ]);
      });
    });

    group('cancelled', () {
      test('returns retry, copyUrl, openInBrowser, editNote, delete', () {
        final actions = service.enabledActions(
          _makeEntity(status: DownloadStatus.cancelled),
        );
        expect(actions, [
          DownloadContextMenuAction.retry,
          DownloadContextMenuAction.copyUrl,
          DownloadContextMenuAction.openInBrowser,
          DownloadContextMenuAction.editNote,
          DownloadContextMenuAction.delete,
        ]);
      });
    });

    group('pending', () {
      test('returns scheduleFor, cancel, copyUrl, openInBrowser, editNote', () {
        final actions = service.enabledActions(
          _makeEntity(status: DownloadStatus.pending),
        );
        expect(actions, [
          DownloadContextMenuAction.scheduleFor,
          DownloadContextMenuAction.cancel,
          DownloadContextMenuAction.copyUrl,
          DownloadContextMenuAction.openInBrowser,
          DownloadContextMenuAction.editNote,
        ]);
      });
    });

    group('queued', () {
      test('returns scheduleFor, cancel, copyUrl, openInBrowser, editNote', () {
        final actions = service.enabledActions(
          _makeEntity(status: DownloadStatus.queued),
        );
        expect(actions, [
          DownloadContextMenuAction.scheduleFor,
          DownloadContextMenuAction.cancel,
          DownloadContextMenuAction.copyUrl,
          DownloadContextMenuAction.openInBrowser,
          DownloadContextMenuAction.editNote,
        ]);
      });
    });

    group('all statuses return non-empty list', () {
      test('every status has at least one action', () {
        for (final status in DownloadStatus.values) {
          final actions = service.enabledActions(
            _makeEntity(status: status),
          );
          expect(actions, isNotEmpty, reason: 'Status $status should have actions');
        }
      });
    });
  });

  group('DownloadContextMenuAction', () {
    test('all actions have non-null icons', () {
      for (final action in DownloadContextMenuAction.values) {
        expect(action.icon, isNotNull);
      }
    });

    test('all actions have a non-empty titleKey', () {
      for (final action in DownloadContextMenuAction.values) {
        expect(action.titleKey, isNotEmpty);
      }
    });

    test('markWatched and markUnwatched use watchStatus. prefix', () {
      expect(DownloadContextMenuAction.markWatched.titleKey, startsWith('watchStatus.'));
      expect(DownloadContextMenuAction.markUnwatched.titleKey, startsWith('watchStatus.'));
    });

    test('playNext and addToQueue use playbackQueue. prefix', () {
      expect(DownloadContextMenuAction.playNext.titleKey, startsWith('playbackQueue.'));
      expect(DownloadContextMenuAction.addToQueue.titleKey, startsWith('playbackQueue.'));
    });

    test('remaining actions use contextMenu. prefix', () {
      const nonContextMenuActions = {
        DownloadContextMenuAction.markWatched,
        DownloadContextMenuAction.markUnwatched,
        DownloadContextMenuAction.playNext,
        DownloadContextMenuAction.addToQueue,
        DownloadContextMenuAction.redownload,
        // Playlist actions live under their own l10n namespace —
        // see `playlist.rowMenu.*` in the translations bundle.
        DownloadContextMenuAction.addToPlaylist,
      };
      for (final action in DownloadContextMenuAction.values) {
        if (nonContextMenuActions.contains(action)) continue;
        expect(action.titleKey, startsWith('contextMenu.'), reason: '$action should use contextMenu. prefix');
      }
    });

    test('only delete and cancel are destructive', () {
      expect(DownloadContextMenuAction.delete.isDestructive, isTrue);
      expect(DownloadContextMenuAction.cancel.isDestructive, isTrue);
      expect(DownloadContextMenuAction.openFile.isDestructive, isFalse);
      expect(DownloadContextMenuAction.copyUrl.isDestructive, isFalse);
      expect(DownloadContextMenuAction.resume.isDestructive, isFalse);
    });

    test('editNote is always present for every status', () {
      for (final status in DownloadStatus.values) {
        final actions = service.enabledActions(
          _makeEntity(status: status),
        );
        expect(
          actions.contains(DownloadContextMenuAction.editNote),
          isTrue,
          reason: 'Status $status should always have editNote',
        );
      }
    });

    test('editNote is not destructive', () {
      expect(DownloadContextMenuAction.editNote.isDestructive, isFalse);
    });

    test('editNote has edit_note icon', () {
      expect(DownloadContextMenuAction.editNote.icon, isNotNull);
    });

    test('scheduleFor has schedule icon', () {
      expect(DownloadContextMenuAction.scheduleFor.icon, isNotNull);
    });

    test('scheduleFor is not destructive', () {
      expect(DownloadContextMenuAction.scheduleFor.isDestructive, isFalse);
    });

    test('scheduleFor titleKey is contextMenu.scheduleFor', () {
      expect(DownloadContextMenuAction.scheduleFor.titleKey, 'contextMenu.scheduleFor');
    });

    test('scheduleFor appears for pending status', () {
      final actions = service.enabledActions(
        _makeEntity(status: DownloadStatus.pending),
      );
      expect(actions.contains(DownloadContextMenuAction.scheduleFor), isTrue);
    });

    test('scheduleFor appears for queued status', () {
      final actions = service.enabledActions(
        _makeEntity(status: DownloadStatus.queued),
      );
      expect(actions.contains(DownloadContextMenuAction.scheduleFor), isTrue);
    });

    test('scheduleFor does not appear for completed status', () {
      final actions = service.enabledActions(
        _makeEntity(status: DownloadStatus.completed),
      );
      expect(actions.contains(DownloadContextMenuAction.scheduleFor), isFalse);
    });

    test('scheduleFor does not appear for downloading status', () {
      final actions = service.enabledActions(
        _makeEntity(status: DownloadStatus.downloading),
      );
      expect(actions.contains(DownloadContextMenuAction.scheduleFor), isFalse);
    });

    test('copyUrl is always present for every status', () {
      for (final status in DownloadStatus.values) {
        final actions = service.enabledActions(
          _makeEntity(status: status),
        );
        expect(
          actions.contains(DownloadContextMenuAction.copyUrl),
          isTrue,
          reason: 'Status $status should always have copyUrl',
        );
      }
    });

    test('shareFile appears for completed+file-exists on macOS only', () {
      final actions = service.enabledActions(
        _makeEntity(status: DownloadStatus.completed),
      );
      // On macOS test environment, shareFile should be present
      // On other platforms it must be absent
      if (Platform.isMacOS) {
        expect(actions.contains(DownloadContextMenuAction.shareFile), isTrue);
        // shareFile should be after showInFolder
        final folderIdx = actions.indexOf(DownloadContextMenuAction.showInFolder);
        final shareIdx = actions.indexOf(DownloadContextMenuAction.shareFile);
        expect(shareIdx, greaterThan(folderIdx));
      } else {
        expect(actions.contains(DownloadContextMenuAction.shareFile), isFalse);
      }
    });

    test('shareFile is absent when file is missing', () {
      final actions = service.enabledActions(
        _makeEntity(status: DownloadStatus.completed),
        isFileMissing: true,
      );
      expect(actions.contains(DownloadContextMenuAction.shareFile), isFalse);
    });

    test('shareFile is absent for non-completed statuses', () {
      for (final status in [
        DownloadStatus.downloading,
        DownloadStatus.paused,
        DownloadStatus.failed,
        DownloadStatus.cancelled,
        DownloadStatus.pending,
        DownloadStatus.queued,
      ]) {
        final actions = service.enabledActions(_makeEntity(status: status));
        expect(
          actions.contains(DownloadContextMenuAction.shareFile),
          isFalse,
          reason: 'shareFile must not appear for status $status',
        );
      }
    });
  });
}
