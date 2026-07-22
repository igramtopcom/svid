import 'package:flutter/material.dart';

/// Actions available in the download item context menu.
enum DownloadContextMenuAction {
  openFile,
  showInFolder,
  shareFile,
  pause,
  resume,
  cancel,
  retry,
  copyUrl,
  openInBrowser,
  copyFilePath,
  editNote,
  markWatched,
  markUnwatched,
  delete,
  playNext,
  addToQueue,
  watchNow,
  scheduleFor,
  redownload,
  convert,
  reportError,
  addToPlaylist;

  /// Icon for this action.
  IconData get icon {
    switch (this) {
      case openFile:
        return Icons.play_circle_outline;
      case showInFolder:
        return Icons.folder_open;
      case shareFile:
        return Icons.share;
      case pause:
        return Icons.pause;
      case resume:
        return Icons.play_arrow;
      case cancel:
        return Icons.stop;
      case retry:
        return Icons.refresh;
      case copyUrl:
        return Icons.link_rounded;
      case openInBrowser:
        return Icons.language_rounded;
      case copyFilePath:
        return Icons.content_copy_rounded;
      case editNote:
        return Icons.edit_note;
      case markWatched:
        return Icons.visibility;
      case markUnwatched:
        return Icons.visibility_off;
      case delete:
        return Icons.delete_outline;
      case playNext:
        return Icons.queue_play_next;
      case addToQueue:
        return Icons.add_to_queue;
      case watchNow:
        return Icons.play_circle_fill_rounded;
      case scheduleFor:
        return Icons.schedule_rounded;
      case redownload:
        return Icons.replay_rounded;
      case convert:
        return Icons.transform_rounded;
      case reportError:
        return Icons.flag_outlined;
      case addToPlaylist:
        return Icons.playlist_add_rounded;
    }
  }

  /// l10n key suffix for this action's title.
  String get titleKey {
    switch (this) {
      case playNext:
        return 'playbackQueue.playNext';
      case addToQueue:
        return 'playbackQueue.addToQueue';
      case markWatched:
        return 'watchStatus.markWatched';
      case markUnwatched:
        return 'watchStatus.markUnwatched';
      case redownload:
        return 'downloads.redownload';
      case convert:
        return 'contextMenu.convert';
      case reportError:
        return 'contextMenu.reportError';
      case addToPlaylist:
        return 'playlist.rowMenu.addTo';
      default:
        return 'contextMenu.$name';
    }
  }

  /// Whether this action is destructive (shown in red).
  bool get isDestructive => this == delete || this == cancel;
}
