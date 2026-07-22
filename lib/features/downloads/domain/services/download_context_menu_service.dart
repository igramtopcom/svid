import 'dart:io';

import '../../../../core/utils/file_utils.dart';
import '../entities/download_context_menu_action.dart';
import '../entities/download_entity.dart';
import '../entities/download_status.dart';

/// Pure Dart service that determines which context menu actions
/// are available for a given download based on its current state.
class DownloadContextMenuService {
  const DownloadContextMenuService();

  /// Returns the ordered list of actions available for [download].
  ///
  /// [isFileMissing] indicates whether the file has been deleted from disk
  /// (e.g. removed via Finder/Explorer while still in the downloads list).
  List<DownloadContextMenuAction> enabledActions(
    DownloadEntity download, {
    bool isFileMissing = false,
  }) {
    final actions = <DownloadContextMenuAction>[];

    switch (download.status) {
      case DownloadStatus.completed:
        if (!isFileMissing) {
          actions.add(DownloadContextMenuAction.openFile);
          actions.add(DownloadContextMenuAction.showInFolder);
          if (Platform.isMacOS) {
            actions.add(DownloadContextMenuAction.shareFile);
          }
          actions.add(DownloadContextMenuAction.playNext);
          actions.add(DownloadContextMenuAction.addToQueue);
          // Convert only makes sense for media the forge can transcode —
          // audio/video. Hide it for images, subtitles, PDFs, etc.
          if (FileUtils.isVideoFile(download.filename) ||
              FileUtils.isAudioFile(download.filename)) {
            actions.add(DownloadContextMenuAction.convert);
          }
        } else {
          // File missing — offer re-download via source URL extraction
          actions.add(DownloadContextMenuAction.redownload);
        }
        actions.add(DownloadContextMenuAction.copyUrl);
        actions.add(DownloadContextMenuAction.openInBrowser);
        if (!isFileMissing) {
          actions.add(DownloadContextMenuAction.copyFilePath);
        }
        actions.add(DownloadContextMenuAction.editNote);
        // Playlist organisation — Add-to-playlist is always offered
        // for completed rows (incl. file-missing case, treated as
        // library-organisation semantic per Chairman call). The
        // matching `removeFrom` lives on the row's per-playlist
        // submenu in `download_list_item.dart` because v20 lets one
        // download belong to N playlists; the service can't model a
        // 1-of-N picker, so the row UI handles it.
        actions.add(DownloadContextMenuAction.addToPlaylist);
        // Toggle watched state
        if (download.isWatched) {
          actions.add(DownloadContextMenuAction.markUnwatched);
        } else {
          actions.add(DownloadContextMenuAction.markWatched);
        }
        actions.add(DownloadContextMenuAction.delete);

      case DownloadStatus.downloading:
      case DownloadStatus.postProcessing:
      // RC10.3: new sub-states share the context-menu actions of the
      // generic post-processing state (cancel, etc.).
      case DownloadStatus.merging:
      case DownloadStatus.remuxing:
      case DownloadStatus.converting:
        // Allow watching a partial file once ≥ 10% downloaded
        if (download.status == DownloadStatus.downloading &&
            download.progress >= 0.1 &&
            _isPlayableMediaFile(download.filename)) {
          actions.add(DownloadContextMenuAction.watchNow);
        }
        if (download.canPause) {
          actions.add(DownloadContextMenuAction.pause);
        }
        actions.add(DownloadContextMenuAction.cancel);
        actions.add(DownloadContextMenuAction.copyUrl);
        actions.add(DownloadContextMenuAction.openInBrowser);
        actions.add(DownloadContextMenuAction.editNote);

      case DownloadStatus.paused:
        actions.add(DownloadContextMenuAction.resume);
        actions.add(DownloadContextMenuAction.cancel);
        actions.add(DownloadContextMenuAction.copyUrl);
        actions.add(DownloadContextMenuAction.openInBrowser);
        actions.add(DownloadContextMenuAction.editNote);
        actions.add(DownloadContextMenuAction.delete);

      case DownloadStatus.failed:
        actions.add(DownloadContextMenuAction.retry);
        actions.add(DownloadContextMenuAction.reportError);
        actions.add(DownloadContextMenuAction.copyUrl);
        actions.add(DownloadContextMenuAction.openInBrowser);
        actions.add(DownloadContextMenuAction.editNote);
        actions.add(DownloadContextMenuAction.delete);

      case DownloadStatus.waitingForNetwork:
        actions.add(DownloadContextMenuAction.retry);
        actions.add(DownloadContextMenuAction.reportError);
        actions.add(DownloadContextMenuAction.cancel);
        actions.add(DownloadContextMenuAction.copyUrl);
        actions.add(DownloadContextMenuAction.openInBrowser);
        actions.add(DownloadContextMenuAction.editNote);
        actions.add(DownloadContextMenuAction.delete);

      case DownloadStatus.cancelled:
        actions.add(DownloadContextMenuAction.retry);
        actions.add(DownloadContextMenuAction.copyUrl);
        actions.add(DownloadContextMenuAction.openInBrowser);
        actions.add(DownloadContextMenuAction.editNote);
        actions.add(DownloadContextMenuAction.delete);

      case DownloadStatus.pending:
      case DownloadStatus.queued:
        actions.add(DownloadContextMenuAction.scheduleFor);
        actions.add(DownloadContextMenuAction.cancel);
        actions.add(DownloadContextMenuAction.copyUrl);
        actions.add(DownloadContextMenuAction.openInBrowser);
        actions.add(DownloadContextMenuAction.editNote);
    }

    return actions;
  }

  /// Returns true if [filename] is a video or audio file that MediaKit can play.
  bool _isPlayableMediaFile(String filename) {
    final ext = filename.toLowerCase().split('.').last;
    const videoExts = {'mp4', 'mkv', 'webm', 'avi', 'mov', 'm4v', 'ts', 'flv'};
    const audioExts = {'mp3', 'aac', 'flac', 'm4a', 'ogg', 'wav', 'opus'};
    return videoExts.contains(ext) || audioExts.contains(ext);
  }
}
