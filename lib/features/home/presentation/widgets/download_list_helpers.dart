import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../../core/core.dart';
import '../../../downloads/domain/entities/download_entity.dart';
import '../../../downloads/domain/entities/download_status.dart';
import '../../../downloads/domain/entities/user_playlist_membership.dart';
import '../../../downloads/presentation/providers/downloads_notifier.dart';
import '../../../downloads/presentation/providers/playlist_library_provider.dart';
import '../../../player/presentation/providers/playback_queue_providers.dart';
import '../../../player/presentation/screens/video_player_screen.dart';
import '../../../player/presentation/screens/audio_player_screen.dart';
import '../../../player/presentation/screens/image_viewer_screen.dart';
import 'playlist_queue_seed.dart';

/// Thumbnail dimensions used across all download card variants.
const kDownloadThumbWidth = 144.0;
const kDownloadThumbHeight = 81.0;

/// Represents an item in the download list — either single or grouped carousel images.
sealed class DownloadListItem {
  const DownloadListItem();
}

class SingleItem extends DownloadListItem {
  final DownloadEntity download;
  const SingleItem(this.download);
}

class GroupedItem extends DownloadListItem {
  final List<DownloadEntity> downloads;

  /// Header label for the group. For image carousels this is empty
  /// (the URL itself is uninteresting); for playlists it carries
  /// the playlist title so the collapsed row reads as the
  /// collection's name rather than its first video.
  final String? groupTitle;

  /// Stable id used as widget key when rebuilding. For playlist
  /// groups this is the `yt_*` / `user_*` id; for carousel groups
  /// it's the source URL. Never null at construction.
  final String groupId;

  /// Distinguishes a YouTube source-grouped header (`yt_*`) from a
  /// user-curated header (`user_*`) from a plain image carousel.
  /// Drives badge styling in the row UI.
  final GroupedItemKind kind;

  const GroupedItem(
    this.downloads, {
    this.groupTitle,
    required this.groupId,
    required this.kind,
  });

  DownloadEntity get first => downloads.first;
  int get count => downloads.length;
}

/// Kind tag for [GroupedItem] — Hybrid #1+#2 needs to render
/// source-grouped vs user-curated headers differently (different
/// icon, label, and "remove from playlist" semantics).
enum GroupedItemKind {
  /// Image carousel from gallery-dl — group header is implicit.
  imageCarousel,

  /// `yt_*` source playlist tagged on `downloads.playlistId`.
  ytSourcePlaylist,

  /// `user_*` curated playlist from `user_playlist_items`.
  userPlaylist,
}

/// Group related downloads into single list items so collections
/// (image carousels, YouTube playlists, user-curated playlists)
/// render as one collapsible row instead of cluttering the flat
/// list with siblings.
///
/// Three grouping rules layered (priority order):
///   1. User-curated playlists (v20+) — memberships in
///      `user_playlist_items`. A download can appear under multiple
///      user playlists (M:N), so a video in 2 user playlists emits
///      under both headers.
///   2. Source-grouped playlists (v19+) — `downloads.playlistId`
///      starting with `yt_`. Stamped by `HomeBatchDownloadMixin`
///      from `YouTubePlaylistSheet`.
///   3. Gallery-dl image carousels — same source URL.
///
/// A download that is BOTH in a yt_* source playlist AND in user
/// playlists appears under each — the user's mental model is "this
/// video is in playlist A *and* playlist B"; hiding it from one
/// would surprise them.
///
/// Two-pass approach preserves sort order from
/// `filteredDownloadsProvider`. Single-element "groups" emit as
/// [SingleItem] so a 1-video playlist doesn't get a header.
///
/// [memberships] is the live `user_playlist_items` snapshot from
/// `userPlaylistMembershipsProvider`. Empty list (default) makes
/// the function behave exactly like v19 — useful for tests that
/// don't care about the user-curated layer.
List<DownloadListItem> buildDownloadListItems(
  List<DownloadEntity> downloads, {
  List<UserPlaylistMembership> memberships = const [],
}) {
  // === Pass 1: build all three group types ===

  // Index downloads by id for membership lookup. Iteration cost is
  // O(N+M) total, much better than per-membership full scan.
  final Map<int, DownloadEntity> byId = {for (final d in downloads) d.id: d};

  // user_* groups — each membership row contributes one entry to
  // the playlist's member list at its persisted position.
  final Map<String, List<({DownloadEntity download, int position})>>
  userGroupsRaw = {};
  final Map<String, String> userGroupTitles = {};
  for (final m in memberships) {
    final dl = byId[m.downloadId];
    if (dl == null) continue; // download deleted but membership not yet swept
    userGroupsRaw.putIfAbsent(m.playlistId, () => []).add((
      download: dl,
      position: m.position,
    ));
    userGroupTitles[m.playlistId] = m.playlistTitle;
  }
  // Materialise sorted member lists.
  final Map<String, List<DownloadEntity>> userGroups = {
    for (final entry in userGroupsRaw.entries)
      entry.key:
          (entry.value..sort((a, b) => a.position.compareTo(b.position)))
              .map((e) => e.download)
              .toList(),
  };

  // yt_* source groups + image carousel groups.
  final Map<String, List<DownloadEntity>> ytGroups = {};
  final Map<String, List<DownloadEntity>> imageGroups = {};
  for (final d in downloads) {
    final pid = d.playlistId;
    if (pid != null && pid.isNotEmpty && pid.startsWith('yt_')) {
      ytGroups.putIfAbsent(pid, () => []).add(d);
    } else if (d.isGalleryDlDownload && FileUtils.isImageFile(d.filename)) {
      imageGroups.putIfAbsent(d.url, () => []).add(d);
    }
  }

  // Sort yt_* groups by playlistIndex (preserves YouTube order).
  for (final group in ytGroups.values) {
    group.sort((a, b) {
      final ai = a.playlistIndex ?? 999999;
      final bi = b.playlistIndex ?? 999999;
      if (ai != bi) return ai.compareTo(bi);
      return a.filename.compareTo(b.filename);
    });
  }
  // Sort image groups by filename.
  for (final group in imageGroups.values) {
    group.sort((a, b) => a.filename.compareTo(b.filename));
  }

  // Reverse index: download.id → user playlist ids it belongs to.
  // Used in pass 2 to emit user playlist headers AT the position of
  // their first member in the sorted source list.
  final Map<int, List<String>> userPlaylistsByDownload = {};
  for (final m in memberships) {
    userPlaylistsByDownload
        .putIfAbsent(m.downloadId, () => [])
        .add(m.playlistId);
  }

  // === Pass 2: emit in original sort order ===
  final Set<String> emittedYt = {};
  final Set<String> emittedUser = {};
  final Set<String> emittedImage = {};
  final List<DownloadListItem> items = [];

  for (final d in downloads) {
    final pid = d.playlistId;

    // V2 reconcile (2026-05-08): video playlists no longer collapse
    // into a single grouped card in the downloads list. The right-
    // panel Playlist tab handles the queue context — duplicating
    // that collapse in the history view obscured "tải 5 video, thấy
    // 1 item" and conflicted with the user's expectation that the
    // history is one row per download. Image carousels (gallery-dl
    // multi-image posts) keep their grouped card because the
    // semantic is "1 post = N images = 1 thing", which is genuinely
    // 1 row.

    final userPids = userPlaylistsByDownload[d.id];

    // yt_* source playlist member — render as individual row in
    // chronological-ish order (already sorted by playlistIndex
    // inside the group). The single-item card is responsible for
    // seeding the playback queue from siblings on tap so the
    // sidebar Playlist tab still lights up the rest of the
    // playlist when the user opens any one of its videos.
    if (pid != null && pid.isNotEmpty && pid.startsWith('yt_')) {
      if (emittedYt.add(pid)) {
        // Walk every member in the sorted group order, not just
        // the current download — `downloads` is sorted by the
        // outer caller's criteria (createdAt, etc.), but inside a
        // playlist we want playlist order. Emitting members in
        // group-order preserves the YouTube playlist sequence in
        // the list view; subsequent iterations of the outer loop
        // skip these via `emittedYt`.
        final group = ytGroups[pid]!;
        for (final member in group) {
          items.add(SingleItem(member));
        }
      }
      continue;
    }

    // User-curated playlist member — same flat-emission rule.
    // We deliberately drop the user-playlist *header* card here:
    // user-curated playlists also live in the right-panel Playlist
    // tab and a dedicated playlists screen, so a duplicate header
    // in the history view added noise without helping discovery.
    if (userPids != null) {
      // Two outcomes count as "this download is already represented
      // in `items`": (a) one of its memberships emits the playlist's
      // members during this iteration, OR (b) one of its memberships
      // was already emitted in a previous iteration. Both mean the
      // download appears via the playlist's flat list and must skip
      // the fallback `SingleItem(d)` at the end of the loop —
      // otherwise it renders twice.
      var representedByMembership = false;
      for (final upid in userPids) {
        if (!emittedUser.add(upid)) {
          representedByMembership = true; // earlier iteration claimed it
          continue;
        }
        final group = userGroups[upid]!;
        for (final member in group) {
          items.add(SingleItem(member));
        }
        representedByMembership = true;
      }
      if (representedByMembership && (pid == null || pid.isEmpty)) continue;
    }

    // Image carousel (gallery-dl multi-image post). Kept as
    // GroupedItem because conceptually 1 post = N images = 1 row,
    // unlike video playlists where each video stands on its own.
    if (d.isGalleryDlDownload && FileUtils.isImageFile(d.filename)) {
      if (emittedImage.add(d.url)) {
        final group = imageGroups[d.url]!;
        if (group.length > 1) {
          items.add(
            GroupedItem(
              group,
              groupId: d.url,
              kind: GroupedItemKind.imageCarousel,
            ),
          );
        } else {
          items.add(SingleItem(group.first));
        }
      }
      continue;
    }

    items.add(SingleItem(d));
  }

  return items;
}

/// Animated checkbox — Nocturne Cinematic: angular wine-red, no circle.
class SelectionCheckbox extends StatelessWidget {
  final bool selected;
  final bool onImage;

  const SelectionCheckbox({
    super.key,
    required this.selected,
    this.onImage = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final uncheckedBorder =
        onImage
            ? Colors.white.withValues(alpha: AppOpacity.scrim)
            : isDark
            ? AppColors.homeDarkBorderStrong
            : cs.outlineVariant;
    final uncheckedFill =
        onImage ? Colors.black.withValues(alpha: AppOpacity.overlay) : null;
    return AnimatedContainer(
      duration: AppTransitions.fast,
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: selected ? AppColors.brand : uncheckedFill,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: selected ? AppColors.brand : uncheckedBorder,
          width: 1.5,
        ),
      ),
      child:
          selected
              ? const Icon(Icons.check, color: Colors.white, size: 12)
              : null,
    );
  }
}

/// Empty state when no downloads yet — with optional quick-action buttons.
class DownloadEmptyState extends StatelessWidget {
  final VoidCallback? onNewDownload;
  final VoidCallback? onOpenBrowser;

  const DownloadEmptyState({super.key, this.onNewDownload, this.onOpenBrowser});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final accent = AppColors.accentHighlight;
    final titleColor = isDark ? AppColors.darkLightText : cs.onSurface;
    final bodyColor = AppColors.metaText(context);
    final borderColor =
        isDark
            ? AppColors.homeDarkBorderStrong.withValues(alpha: 0.78)
            : cs.outlineVariant.withValues(alpha: 0.72);

    return LayoutBuilder(
      builder: (context, constraints) {
        final boundedHeight = constraints.hasBoundedHeight;
        final compact = boundedHeight && constraints.maxHeight < 320;
        final iconSize = compact ? 52.0 : 64.0;
        final iconGlyph = compact ? 24.0 : 30.0;
        final maxWidth = compact ? 440.0 : 520.0;

        final primaryAction =
            onNewDownload == null
                ? null
                : FilledButton.icon(
                  onPressed: onNewDownload,
                  icon: const Icon(Icons.add_link_rounded, size: 18),
                  label: Text(AppLocalizations.downloadsEmptyPasteAction),
                  style: FilledButton.styleFrom(
                    backgroundColor: isDark ? accent : AppColors.brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.sm,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.input),
                    ),
                  ),
                );
        final secondaryAction =
            onOpenBrowser == null
                ? null
                : OutlinedButton.icon(
                  onPressed: onOpenBrowser,
                  icon: const Icon(Icons.language_rounded, size: 18),
                  label: Text(AppLocalizations.downloadsEmptyOpenBrowserAction),
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        isDark ? AppColors.darkLightText : AppColors.brand,
                    side: BorderSide(color: borderColor, width: 1),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.sm,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.input),
                    ),
                  ),
                );

        final content = ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  color:
                      isDark
                          ? AppColors.homeDarkAccentSoft
                          : accent.withValues(alpha: AppOpacity.hover),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: borderColor, width: 1),
                ),
                child: Icon(
                  Icons.download_for_offline_rounded,
                  size: iconGlyph,
                  color: isDark ? accent : AppColors.brand,
                ),
              ),
              SizedBox(height: compact ? AppSpacing.sm : AppSpacing.smMd),
              Text(
                AppLocalizations.downloadsEmptyTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: titleColor,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                AppLocalizations.downloadsEmptySubtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: bodyColor,
                  height: 1.35,
                ),
                textAlign: TextAlign.center,
                maxLines: compact ? 2 : 3,
                overflow: TextOverflow.ellipsis,
              ),
              if (primaryAction != null || secondaryAction != null) ...[
                SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    if (primaryAction != null) primaryAction,
                    if (secondaryAction != null) secondaryAction,
                  ],
                ),
              ],
            ],
          ),
        );

        final padded = Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: compact ? AppSpacing.lg : AppSpacing.xxl,
          ),
          child: content,
        );

        if (!boundedHeight) {
          return Padding(
            padding: EdgeInsets.only(
              top: compact ? AppSpacing.xl : AppSpacing.xxxl,
              bottom: AppSpacing.xxxl,
            ),
            child: Center(child: padded),
          );
        }

        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Align(
                alignment:
                    compact ? Alignment.center : const Alignment(0, -0.48),
                child: padded,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Status color — Nocturne Cinematic: downloading uses CRIMSON brand accent.
Color getDownloadStatusColor(BuildContext context, DownloadEntity download) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return switch (download.status) {
    DownloadStatus.downloading => AppColors.accentHighlight, // Crimson #C41E3A
    DownloadStatus.pending || DownloadStatus.queued =>
      isDark ? AppColors.darkMetaText : AppColors.statusQueued,
    DownloadStatus.postProcessing ||
    // RC10.3: new sub-states share post-processing accent color.
    DownloadStatus.merging ||
    DownloadStatus.remuxing ||
    DownloadStatus.converting => AppColors.statusPostProcessing,
    DownloadStatus.completed => AppColors.statusCompleted(context),
    DownloadStatus.paused => AppColors.statusPaused(context),
    DownloadStatus.failed => AppColors.statusFailed(context),
    DownloadStatus.cancelled => AppColors.statusCancelled(context),
    DownloadStatus.waitingForNetwork => AppColors.warningAmber,
  };
}

/// Status badge container — Nocturne tinted backgrounds per status.
Color getDownloadStatusContainerColor(
  BuildContext context,
  DownloadEntity download,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return switch (download.status) {
    DownloadStatus.downloading => AppColors.accentHighlight.withValues(
      alpha: isDark ? AppOpacity.subtle : AppOpacity.hover,
    ),
    DownloadStatus.pending || DownloadStatus.queued => (isDark
            ? AppColors.darkMetaText
            : AppColors.statusQueued)
        .withValues(alpha: AppOpacity.pressed),
    DownloadStatus.postProcessing ||
    // RC10.3: new sub-states share post-processing tinted bg.
    DownloadStatus.merging ||
    DownloadStatus.remuxing ||
    DownloadStatus.converting => AppColors.statusPostProcessing.withValues(
      alpha: isDark ? AppOpacity.subtle : AppOpacity.hover,
    ),
    DownloadStatus.completed => AppColors.statusCompleted(
      context,
    ).withValues(alpha: isDark ? AppOpacity.pressed : AppOpacity.hover),
    DownloadStatus.paused => AppColors.statusPaused(
      context,
    ).withValues(alpha: isDark ? AppOpacity.pressed : AppOpacity.hover),
    DownloadStatus.failed => AppColors.statusFailed(
      context,
    ).withValues(alpha: isDark ? AppOpacity.subtle : AppOpacity.hover),
    DownloadStatus.cancelled => AppColors.statusCancelled(
      context,
    ).withValues(alpha: isDark ? AppOpacity.pressed : AppOpacity.hover),
    DownloadStatus.waitingForNetwork => AppColors.warningAmber.withValues(
      alpha: isDark ? AppOpacity.pressed : AppOpacity.hover,
    ),
  };
}

/// Left accent bar color (2px) — Nocturne Cinematic per-status.
Color getStatusAccentColor(DownloadEntity download) {
  return switch (download.status) {
    DownloadStatus.downloading => AppColors.accentHighlight,
    DownloadStatus.pending || DownloadStatus.queued => AppColors.darkMuted,
    DownloadStatus.postProcessing ||
    // RC10.3: new sub-states share post-processing accent color.
    DownloadStatus.merging ||
    DownloadStatus.remuxing ||
    DownloadStatus.converting => AppColors.statusPostProcessing,
    DownloadStatus.completed => AppColors.successGreen,
    DownloadStatus.paused => AppColors.warningAmber,
    DownloadStatus.failed => AppColors.errorRed,
    DownloadStatus.cancelled => AppColors.darkMuted,
    DownloadStatus.waitingForNetwork => AppColors.warningAmber,
  };
}

/// Common helper: get status icon for a download entity.
IconData getDownloadStatusIcon(DownloadEntity download) {
  if (download.isCompleted) return Icons.check_circle;
  if (download.isPaused) return Icons.pause_circle;
  if (download.isWaitingForNetwork) return Icons.wifi_off_rounded;
  if (download.isFailed) return Icons.error;
  if (download.isCancelled) return Icons.cancel;
  return Icons.pending;
}

/// Common helper: get file type icon for a download entity.
IconData getFileIcon(DownloadEntity download) {
  final ext = download.fileExtension.toLowerCase();
  if (['.mp4', '.mkv', '.avi', '.mov', '.webm'].contains(ext)) {
    return Icons.video_library;
  } else if ([
    '.mp3',
    '.wav',
    '.flac',
    '.m4a',
    '.aac',
    '.ogg',
    '.opus',
  ].contains(ext)) {
    return Icons.music_note;
  } else if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext)) {
    return Icons.image;
  }
  return Icons.insert_drive_file;
}

/// Common helper: get file type color for a download entity.
Color getFileTypeColor(BuildContext context, DownloadEntity download) {
  final ext = download.fileExtension.toLowerCase();
  if (['.mp4', '.mkv', '.avi', '.mov', '.webm'].contains(ext)) {
    return AppColors.infoBlue;
  } else if ([
    '.mp3',
    '.wav',
    '.flac',
    '.m4a',
    '.aac',
    '.ogg',
    '.opus',
  ].contains(ext)) {
    return AppColors.statusPostProcessing;
  } else if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext)) {
    return AppColors.warningAmber;
  }
  return getDownloadStatusColor(context, download);
}

/// Seed playback queue from the best available context for [download].
///
/// Tries user/source playlist context first, then falls back to
/// yt_* playlistId siblings. Call this before opening any player
/// surface so Next/Previous work correctly regardless of entry point.
void seedPlaybackQueue(WidgetRef ref, DownloadEntity download) {
  final librarySeed = selectPlaylistLibraryQueueSeed(
    me: download,
    playlists: ref.read(playlistLibraryProvider),
    activePlaylistKey: ref.read(activePlaylistContextProvider),
  );
  final seed =
      librarySeed.queue.isNotEmpty
          ? librarySeed
          : selectPlaylistQueueSeed(
            me: download,
            all: ref.read(downloadsNotifierProvider).downloads,
          );
  ref
      .read(playbackQueueProvider.notifier)
      .setQueue(seed.queue, startIndex: seed.startIndex);
}

/// Common helper: open appropriate player based on file type.
///
/// Seeds the playback queue from playlist/library context before
/// opening so Next/Previous work consistently from every entry point.
void openPlayerForDownload(
  BuildContext context,
  WidgetRef ref,
  DownloadEntity download, {
  List<DownloadEntity>? carouselDownloads,
}) {
  if (!download.isCompleted) return;

  // Validate file exists before opening
  final filePath = p.join(download.savePath, download.filename);
  if (!File(filePath).existsSync()) {
    ref
        .read(downloadsNotifierProvider.notifier)
        .revalidateFile(download.id, download.savePath, download.filename);
    AppSnackBar.error(
      context,
      message: AppLocalizations.downloadsFileMissingError,
    );
    return;
  }

  seedPlaybackQueue(ref, download);

  if (FileUtils.isVideoFile(download.filename)) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VideoPlayerScreen(download: download),
      ),
    );
  } else if (FileUtils.isAudioFile(download.filename)) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AudioPlayerScreen(download: download),
      ),
    );
  } else if (FileUtils.isImageFile(download.filename)) {
    // Find carousel siblings for gallery-dl images
    List<DownloadEntity>? carousel = carouselDownloads;
    if (carousel == null && download.isGalleryDlDownload) {
      final downloadsState = ref.read(downloadsNotifierProvider);
      final siblings =
          downloadsState.downloads
              .where(
                (d) =>
                    d.url == download.url &&
                    d.isGalleryDlDownload &&
                    d.isCompleted &&
                    FileUtils.isImageFile(d.filename),
              )
              .toList()
            ..sort((a, b) => a.filename.compareTo(b.filename));
      if (siblings.length > 1) carousel = siblings;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => ImageViewerScreen(
              download: download,
              carouselDownloads: carousel,
            ),
      ),
    );
  } else {
    // For other file types, open file location
    openFileLocation(context, ref, download);
  }
}

/// Common helper: open player in preview mode (file still downloading).
void openPreviewForDownload(BuildContext context, DownloadEntity download) {
  final filename = download.filename;
  if (FileUtils.isVideoFile(filename)) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => VideoPlayerScreen(download: download, isPreview: true),
      ),
    );
  } else if (FileUtils.isAudioFile(filename)) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AudioPlayerScreen(download: download),
      ),
    );
  }
}

/// Common helper: open file location in system file explorer.
Future<void> openFileLocation(
  BuildContext context,
  WidgetRef ref,
  DownloadEntity download,
) async {
  try {
    final filePath = p.join(download.savePath, download.filename);

    // Validate file exists
    if (!File(filePath).existsSync()) {
      ref
          .read(downloadsNotifierProvider.notifier)
          .revalidateFile(download.id, download.savePath, download.filename);
      if (context.mounted) {
        AppSnackBar.error(
          context,
          message: AppLocalizations.downloadsFileMissingError,
        );
      }
      return;
    }

    if (Platform.isMacOS) {
      await ProcessHelper.revealInFileManager(
        filePath,
        fallbackDirectory: download.savePath,
      );
    } else if (Platform.isWindows) {
      await ProcessHelper.revealInFileManager(
        filePath,
        fallbackDirectory: download.savePath,
      );
    } else if (Platform.isLinux) {
      // Open parent directory on Linux
      await ProcessHelper.openDirectoryInFileManager(download.savePath);
    }

    if (context.mounted) {
      AppSnackBar.info(
        context,
        message: AppLocalizations.downloadsFileOpened(download.filename),
      );
    }
  } catch (e) {
    appLogger.error('Failed to open file location', e);
    if (context.mounted) {
      AppSnackBar.error(
        context,
        message: AppLocalizations.downloadsFailedToOpenLocation(
          AppExceptionX.readableMessage(e),
        ),
      );
    }
  }
}

/// Common helper: copy download URL to clipboard.
Future<void> copyDownloadUrl(
  BuildContext context,
  DownloadEntity download,
) async {
  try {
    await ClipboardService.setText(download.url);
    if (context.mounted) {
      AppSnackBar.success(
        context,
        message: AppLocalizations.downloadsUrlCopied,
      );
    }
  } catch (e) {
    appLogger.error('Failed to copy URL', e);
    if (context.mounted) {
      AppSnackBar.error(
        context,
        message: AppLocalizations.downloadsFailedToCopyUrl(
          AppExceptionX.readableMessage(e),
        ),
      );
    }
  }
}

/// Common helper: copy file path to clipboard.
Future<void> copyDownloadFilePath(
  BuildContext context,
  DownloadEntity download,
) async {
  final filePath = p.join(download.savePath, download.filename);
  try {
    await ClipboardService.setText(filePath);
    if (context.mounted) {
      AppSnackBar.success(
        context,
        message: AppLocalizations.contextMenuCopiedFilePath,
      );
    }
  } catch (e) {
    if (context.mounted) {
      AppSnackBar.error(
        context,
        message: AppLocalizations.downloadsFailedToCopyUrl(
          AppExceptionX.readableMessage(e),
        ),
      );
    }
  }
}

/// Delete dialog — Nocturne Cinematic: obsidian bg, ghost border, sharp.
void showDownloadDeleteDialog(
  BuildContext context,
  WidgetRef ref,
  DownloadEntity download,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  // Capture the notifier BEFORE showing the dialog. If the parent widget
  // disposes between dialog open and the user pressing a button (e.g.
  // user swipes the row out of the list, navigates away, or the list
  // rebuilds), `ref.read` from inside the dialog throws
  // `Bad state: Cannot use "ref" after the widget was disposed.`
  // (3 production crashes in audit, raw stack pointing here.)
  // The notifier itself is owned by the provider container, not the
  // widget tree, so it stays valid even after the caller unmounts.
  final notifier = ref.read(downloadsNotifierProvider.notifier);
  showDialog(
    context: context,
    builder:
        (context) => AlertDialog(
          backgroundColor: isDark ? AppColors.darkBase : AppColors.lightBase,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
            side:
                isDark
                    ? BorderSide(
                      color: AppColors.darkMuted.withValues(
                        alpha: AppOpacity.scrim,
                      ),
                    )
                    : BorderSide.none,
          ),
          title: Text(
            AppLocalizations.downloadsDeleteDialogTitle,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: isDark ? AppColors.darkLightText : null,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            AppLocalizations.downloadsDeleteDialogMessage(download.filename),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isDark ? AppColors.darkMetaText : null,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: isDark ? AppColors.darkMetaText : null,
              ),
              child: Text(AppLocalizations.commonCancel),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                notifier.deleteDownload(download.id, deleteFile: false);
              },
              child: Text(AppLocalizations.downloadsDeleteRecordOnly),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.errorRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
              ),
              onPressed: () {
                Navigator.pop(context);
                notifier.deleteDownload(download.id, deleteFile: true);
              },
              child: Text(AppLocalizations.downloadsDeleteFileAndRecord),
            ),
          ],
        ),
  );
}

/// Metadata badge — Nocturne Cinematic: ghost-bordered, sharp corners.
Widget buildMetadataBadge(
  BuildContext context,
  IconData icon,
  String text, {
  // Optional accent — used to make a media-type chip (e.g. audio) read
  // distinctly from the neutral chips.
  Color? color,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final tinted = color != null;
  final fg =
      color ??
      (isDark
          ? AppColors.darkMetaText
          : Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: AppOpacity.overlay));
  return Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xxs,
    ),
    decoration: BoxDecoration(
      color:
          tinted
              ? color.withValues(alpha: isDark ? 0.18 : 0.10)
              : (isDark
                  ? AppColors.darkLightText.withValues(alpha: AppOpacity.divider)
                  : AppColors.lightSurface2),
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(
        color:
            tinted
                ? color.withValues(alpha: 0.36)
                : (isDark
                    ? AppColors.darkMuted.withValues(alpha: AppOpacity.scrim)
                    : Colors.black.withValues(alpha: AppOpacity.divider)),
        width: 0.5,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: fg),
        const SizedBox(width: AppSpacing.xs),
        Text(
          text,
          style: AppTypography.mini.copyWith(
            fontWeight: tinted ? FontWeight.w700 : FontWeight.w500,
            color: fg,
          ),
        ),
      ],
    ),
  );
}

/// Common helper: build a "file missing" badge widget.
Widget buildFileMissingBadge(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.errorRed.withValues(
        alpha: isDark ? AppOpacity.pressed : AppOpacity.hover,
      ),
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(
        color:
            isDark
                ? AppColors.errorRed.withValues(alpha: AppOpacity.quarter)
                : AppColors.errorRed.withValues(alpha: AppOpacity.subtle),
        width: 0.5,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.broken_image_outlined,
          size: 10,
          color: AppColors.errorRed.withValues(alpha: AppOpacity.nearOpaque),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          AppLocalizations.downloadsFileMissing,
          style: AppTypography.mini.copyWith(
            color: AppColors.errorRed.withValues(alpha: AppOpacity.nearOpaque),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

/// Watched chip — Nocturne Cinematic: ghost-bordered, wine-red tint.
Widget buildWatchedChip({bool compact = false}) {
  return Container(
    padding: EdgeInsets.symmetric(
      horizontal: compact ? AppSpacing.xs : AppSpacing.sm,
      vertical: compact ? 1 : AppSpacing.xxs,
    ),
    decoration: BoxDecoration(
      color: const Color(0xFFDBEAFE),
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: const Color(0xFF93C5FD), width: 1),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1A2563EB),
          blurRadius: 10,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.done_all_rounded,
          size: compact ? 10 : 12,
          color: Color(0xFF1D4ED8),
        ),
        SizedBox(width: compact ? 4 : AppSpacing.xs),
        Text(
          AppLocalizations.watchStatusWatched.toUpperCase(),
          style: AppTypography.mini.copyWith(
            color: const Color(0xFF1E40AF),
            fontWeight: FontWeight.w800,
            fontSize: compact ? 9 : null,
            height: compact ? 1.0 : null,
          ),
        ),
      ],
    ),
  );
}
