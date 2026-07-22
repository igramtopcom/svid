import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../../core/core.dart';
import '../../../downloads/domain/entities/download_entity.dart';
import '../../../downloads/domain/entities/download_status.dart';
import '../../../downloads/presentation/providers/batch_selection_provider.dart';
import '../../../downloads/presentation/providers/downloads_notifier.dart';
import '../../../player/presentation/providers/playback_queue_providers.dart';
import '../../../player/presentation/screens/image_viewer_screen.dart';
import '../../../player/presentation/screens/video_player_screen.dart';
import '../../../../core/navigation/right_panel_provider.dart';
import 'download_progress_painter.dart';
import 'download_list_helpers.dart';
import 'grouped_card_open_action.dart';

/// Grouped image card — shows N gallery-dl images as 1 card with stacked thumbnail.
class DownloadGroupedImageCard extends ConsumerStatefulWidget {
  final GroupedItem group;
  final bool inPanel;

  /// When set and this card is a playlist folder (source/user kind), a single
  /// tap opens that playlist's detail view via this callback (key like
  /// "source:yt_…") instead of the default preview-in-side-panel behaviour.
  final void Function(String playlistKey)? onOpenPlaylist;

  const DownloadGroupedImageCard({
    super.key,
    required this.group,
    this.inPanel = false,
    this.onOpenPlaylist,
  });

  @override
  ConsumerState<DownloadGroupedImageCard> createState() =>
      _DownloadGroupedImageCardState();
}

class _DownloadGroupedImageCardState
    extends ConsumerState<DownloadGroupedImageCard> {
  bool _isHovered = false;

  DownloadEntity get _first => widget.group.first;

  /// Aggregate status: any downloading -> downloading, any failed -> failed, else completed
  DownloadStatus get _aggregateStatus {
    final statuses = widget.group.downloads.map((d) => d.status).toSet();
    if (statuses.contains(DownloadStatus.downloading)) {
      return DownloadStatus.downloading;
    }
    if (statuses.contains(DownloadStatus.pending)) {
      return DownloadStatus.pending;
    }
    if (statuses.contains(DownloadStatus.waitingForNetwork)) {
      return DownloadStatus.waitingForNetwork;
    }
    if (statuses.contains(DownloadStatus.failed)) return DownloadStatus.failed;
    if (statuses.contains(DownloadStatus.paused)) return DownloadStatus.paused;
    if (statuses.every((s) => s == DownloadStatus.completed)) {
      return DownloadStatus.completed;
    }
    return _first.status;
  }

  /// Whether all images in the group are completed
  bool get _allCompleted => widget.group.downloads.every((d) => d.isCompleted);

  Set<int> get _groupIds => widget.group.downloads.map((d) => d.id).toSet();

  /// Check if any file in the group is missing
  bool get _anyFileMissing {
    final downloadsState = ref.watch(downloadsNotifierProvider);
    return widget.group.downloads.any(
      (d) => downloadsState.isFileMissing(d.id),
    );
  }

  /// Group display title. Playlist groups (yt_* / user_*) use the
  /// playlist's own title carried on [GroupedItem.groupTitle]; image
  /// carousels fall back to the first member's display title with
  /// trailing carousel indices stripped (so "Photo_001" → "Photo").
  String get _groupTitle {
    final explicit = widget.group.groupTitle;
    if (explicit != null && explicit.trim().isNotEmpty) return explicit;
    final title = _first.displayTitle;
    final cleaned = title.replaceAll(RegExp(r'[\s_\-]+\d+$'), '');
    return cleaned.isNotEmpty ? cleaned : title;
  }

  Color _getGroupKindColor() {
    return switch (widget.group.kind) {
      GroupedItemKind.imageCarousel => AppColors.statusPostProcessing,
      GroupedItemKind.ytSourcePlaylist => AppColors.infoBlue,
      GroupedItemKind.userPlaylist => AppColors.accentHighlight,
    };
  }

  IconData _getGroupKindIcon() {
    return switch (widget.group.kind) {
      GroupedItemKind.imageCarousel => Icons.collections_rounded,
      GroupedItemKind.ytSourcePlaylist => Icons.smart_display_rounded,
      GroupedItemKind.userPlaylist => Icons.bookmark_rounded,
    };
  }

  String _groupCountLabel() {
    return switch (widget.group.kind) {
      GroupedItemKind.imageCarousel => AppLocalizations.qualityDialogCountImage(
        widget.group.count,
      ),
      _ => AppLocalizations.qualityDialogCountVideo(widget.group.count),
    };
  }

  Color _getStatusColor() {
    return switch (_aggregateStatus) {
      DownloadStatus.downloading => AppColors.accentHighlight, // crimson
      DownloadStatus.pending || DownloadStatus.queued => AppColors.darkMetaText,
      DownloadStatus.postProcessing ||
      // RC10.3: new sub-states share post-processing color.
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

  @override
  Widget build(BuildContext context) {
    final isFileMissing = _anyFileMissing;
    final selectedIds = ref.watch(batchSelectionProvider);
    final groupIds = _groupIds;
    final allSelected =
        groupIds.isNotEmpty && groupIds.every((id) => selectedIds.contains(id));

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isActive =
        _aggregateStatus == DownloadStatus.downloading ||
        _aggregateStatus == DownloadStatus.pending ||
        _aggregateStatus == DownloadStatus.queued ||
        _aggregateStatus == DownloadStatus.postProcessing;
    final groupColor = _getGroupKindColor();
    final cardColor =
        isDark
            ? (isActive
                ? AppColors.homeDarkCardActive
                : _isHovered
                ? AppColors.homeDarkCardHover
                : widget.inPanel
                ? Colors.transparent
                : AppColors.homeDarkCardBg)
            : isActive
            ? AppColors.accentHighlight.withValues(alpha: AppOpacity.divider)
            : _isHovered
            ? groupColor.withValues(alpha: AppOpacity.hover)
            : widget.inPanel
            ? Colors.transparent
            : Colors.white;
    final borderColor =
        isActive
            ? AppColors.accentHighlight.withValues(
              alpha: isDark ? AppOpacity.quarter : AppOpacity.subtle,
            )
            : widget.inPanel
            ? Colors.transparent
            : isDark
            ? (_isHovered
                ? AppColors.homeDarkBorderStrong
                : AppColors.homeDarkBorderSubtle)
            : groupColor.withValues(alpha: AppOpacity.subtle);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (mounted) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _isHovered = false);
      },
      child: GestureDetector(
        onTap: _onGroupCardTap,
        onDoubleTap: _allCompleted && !isFileMissing ? _openCarousel : null,
        onSecondaryTapUp: (details) => _showContextMenu(details.globalPosition),
        child: AnimatedContainer(
          duration: AppTransitions.normal,
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: borderColor, width: isActive ? 0.8 : 0.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: isActive ? 3 : 2,
                    color: _getStatusColor().withValues(
                      alpha:
                          _aggregateStatus == DownloadStatus.completed
                              ? AppOpacity.medium
                              : AppOpacity.nearOpaque,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.smMd),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.inPanel) ...[
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _toggleGroupSelection,
                              child: SizedBox(
                                width: 26,
                                height: kDownloadThumbHeight,
                                child: Align(
                                  alignment: Alignment.center,
                                  child: SelectionCheckbox(
                                    selected: allSelected,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                          ],
                          // Stacked thumbnail
                          _buildStackedThumbnail(),

                          const Gap.md(),

                          // Info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Title row with primary action
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildGroupKindBadge(isDark),
                                    const SizedBox(width: AppSpacing.xs),
                                    Expanded(
                                      child: Text(
                                        _groupTitle,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelLarge?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color:
                                              isDark
                                                  ? AppColors.darkLightText
                                                  : Colors.black87,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),

                                // Uploader
                                if (_first.uploader != null) ...[
                                  const Gap.xxs(),
                                  Text(
                                    _first.uploader!,
                                    style: AppTypography.metadata.copyWith(
                                      color:
                                          isDark
                                              ? AppColors.darkMetaText
                                              : Colors.black54,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],

                                const Gap.xs(),

                                // Status badge + image count + metadata
                                Wrap(
                                  spacing: AppSpacing.sm,
                                  runSpacing: AppSpacing.xs,
                                  children: [
                                    _buildStatusBadge(),
                                    if (isFileMissing)
                                      buildFileMissingBadge(context),
                                    buildMetadataBadge(
                                      context,
                                      _getGroupKindIcon(),
                                      _groupCountLabel(),
                                    ),
                                    if (_first.platform.isNotEmpty &&
                                        _first.platform != 'unknown')
                                      buildMetadataBadge(
                                        context,
                                        Icons.language,
                                        _first.platform,
                                      ),
                                    if (_allCompleted) ...[
                                      buildMetadataBadge(
                                        context,
                                        Icons.file_present,
                                        FileUtils.formatBytes(
                                          widget.group.downloads.fold<int>(
                                            0,
                                            (sum, d) => sum + d.totalBytes,
                                          ),
                                        ),
                                      ),
                                      buildMetadataBadge(
                                        context,
                                        Icons.calendar_today,
                                        Formatters.formatDate(_first.createdAt),
                                      ),
                                    ],
                                  ],
                                ),

                                // Aggregate progress bar (if any download is active)
                                if (widget.group.downloads.any(
                                  (d) => d.isActive,
                                )) ...[
                                  const Gap.sm(),
                                  _buildAggregateProgress(),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.smMd),
                          _buildActionCluster(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _toggleGroupSelection() {
    final selectedIds = ref.read(batchSelectionProvider);
    final groupIds = _groupIds;
    final allSelected =
        groupIds.isNotEmpty && groupIds.every((id) => selectedIds.contains(id));
    final next = Set<int>.from(selectedIds);
    if (allSelected) {
      next.removeAll(groupIds);
    } else {
      next.addAll(groupIds);
    }
    ref.read(batchSelectionProvider.notifier).state = next;
  }

  Widget _buildActionCluster() {
    final primaryAction = _primaryAction();
    final hasPrimary = primaryAction != null;
    return SizedBox(
      width: hasPrimary ? 72 : 32,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (primaryAction != null) ...[
            primaryAction,
            const SizedBox(width: AppSpacing.xs),
          ],
          _buildMoreActionButton(),
        ],
      ),
    );
  }

  Widget? _primaryAction() {
    final status = _aggregateStatus;
    if (_allCompleted && !_anyFileMissing) {
      return _groupActionButton(
        icon: Icons.collections_rounded,
        tooltip: AppLocalizations.downloadsViewImagesTooltip,
        color: _getGroupKindColor(),
        onPressed: _openCarousel,
      );
    }
    if (status == DownloadStatus.failed) {
      return _groupActionButton(
        icon: Icons.refresh_rounded,
        tooltip: AppLocalizations.downloadsRetry,
        color: AppColors.errorRed,
        onPressed: _retryFailed,
      );
    }
    if (status == DownloadStatus.paused) {
      return _groupActionButton(
        icon: Icons.play_arrow_rounded,
        tooltip: AppLocalizations.downloadsResume,
        color: AppColors.successGreen,
        onPressed: _resumePaused,
      );
    }
    if (widget.group.downloads.any((d) => d.isActive)) {
      return _groupActionButton(
        icon: Icons.pause_rounded,
        tooltip: AppLocalizations.downloadsPause,
        color: AppColors.warningAmber,
        onPressed: _pauseActive,
      );
    }
    return null;
  }

  Widget _buildGroupKindBadge(bool isDark) {
    final color = _getGroupKindColor();
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: isDark ? AppOpacity.pressed : AppOpacity.hover,
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: color.withValues(
            alpha: isDark ? AppOpacity.quarter : AppOpacity.subtle,
          ),
          width: 0.5,
        ),
      ),
      child: Icon(_getGroupKindIcon(), size: 14, color: color),
    );
  }

  Widget _buildMoreActionButton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? AppColors.darkMetaText : Colors.black54;
    return Builder(
      builder:
          (buttonContext) => SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              icon: const Icon(Icons.more_vert_rounded, size: 18),
              tooltip: AppLocalizations.commonMore,
              padding: EdgeInsets.zero,
              color: color,
              style: IconButton.styleFrom(
                backgroundColor: color.withValues(alpha: AppOpacity.hover),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
              ),
              onPressed: () {
                final box = buttonContext.findRenderObject() as RenderBox?;
                final topLeft = box?.localToGlobal(Offset.zero) ?? Offset.zero;
                final size = box?.size ?? Size.zero;
                _showContextMenu(topLeft + Offset(size.width, size.height));
              },
            ),
          ),
    );
  }

  Widget _groupActionButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        tooltip: tooltip,
        iconSize: 17,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          foregroundColor: color,
          backgroundColor: color.withValues(alpha: AppOpacity.hover),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
        ),
      ),
    );
  }

  /// Aggregate progress bar — combined progress of all downloads in group
  Widget _buildAggregateProgress() {
    final activeDownloads =
        widget.group.downloads.where((d) => d.isActive).toList();
    final completedCount =
        widget.group.downloads.where((d) => d.isCompleted).length;
    final totalCount = widget.group.count;

    // Calculate combined progress
    final totalBytes = widget.group.downloads.fold<int>(
      0,
      (sum, d) => sum + d.totalBytes,
    );
    final downloadedBytes = widget.group.downloads.fold<int>(
      0,
      (sum, d) => sum + d.downloadedBytes,
    );
    final progress =
        totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DownloadProgressBar(
          progress: progress,
          color: AppColors.accentHighlight, // crimson
          backgroundColor:
              isDark ? AppColors.darkElevated : AppColors.lightSurface3,
          height: 3.0,
          animate: true,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '$completedCount/$totalCount · ${_groupCountLabel()}${activeDownloads.isNotEmpty ? ' · ${activeDownloads.length} downloading' : ''}',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: isDark ? AppColors.darkMetaText : Colors.black54,
          ),
        ),
      ],
    );
  }

  /// Stacked thumbnail — 2-3 offset rectangles behind main image + count badge
  Widget _buildStackedThumbnail() {
    final kindColor = _getGroupKindColor();
    return SizedBox(
      width: kDownloadThumbWidth + 8,
      height: kDownloadThumbHeight + 8,
      child: Stack(
        children: [
          // Third layer (if 3+ images)
          if (widget.group.count > 2)
            Positioned(
              left: 8,
              top: 0,
              child: Container(
                width: kDownloadThumbWidth,
                height: kDownloadThumbHeight,
                decoration: BoxDecoration(
                  color:
                      Theme.of(context).brightness == Brightness.dark
                          ? kindColor.withValues(alpha: AppOpacity.pressed)
                          : kindColor.withValues(alpha: AppOpacity.hover),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
              ),
            ),
          // Second layer (if 2+ images)
          if (widget.group.count > 1)
            Positioned(
              left: 4,
              top: 4,
              child: Container(
                width: kDownloadThumbWidth,
                height: kDownloadThumbHeight,
                decoration: BoxDecoration(
                  color:
                      Theme.of(context).brightness == Brightness.dark
                          ? AppColors.darkSurface1
                          : kindColor.withValues(alpha: AppOpacity.divider),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
              ),
            ),
          // Front layer — actual thumbnail
          Positioned(
            left: 0,
            top: 8,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child:
                  _first.thumbnail != null
                      ? AppCachedImage(
                        imageUrl: _first.thumbnail,
                        width: kDownloadThumbWidth,
                        height: kDownloadThumbHeight,
                        errorWidget: _buildPlaceholderThumbnail(),
                      )
                      : _buildPlaceholderThumbnail(),
            ),
          ),
          // Kind/source overlay (top-left of front thumbnail).
          Positioned(
            top: 12,
            left: 4,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xxs),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: AppOpacity.secondary),
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child:
                  widget.group.kind == GroupedItemKind.imageCarousel &&
                          _first.platform.isNotEmpty &&
                          _first.platform != 'unknown'
                      ? PlatformIcon(platform: _first.platform, size: 14)
                      : Icon(
                        _getGroupKindIcon(),
                        size: 14,
                        color: Colors.white,
                      ),
            ),
          ),
          // Count badge (top-right)
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: kindColor,
                borderRadius: BorderRadius.circular(AppRadius.card),
                boxShadow: [
                  BoxShadow(
                    color: kindColor.withValues(alpha: AppOpacity.scrim),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                    spreadRadius: -1,
                  ),
                ],
              ),
              child: Text(
                '${widget.group.count}',
                style: AppTypography.compact.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderThumbnail() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: kDownloadThumbWidth,
      height: kDownloadThumbHeight,
      decoration: BoxDecoration(
        color: _getStatusColor().withValues(
          alpha: isDark ? AppOpacity.hover : AppOpacity.divider,
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Icon(
        _getGroupKindIcon(),
        size: 32,
        color: _getStatusColor().withValues(
          alpha: isDark ? AppOpacity.secondary : AppOpacity.overlay,
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    final status = _aggregateStatus;
    final isActive =
        status == DownloadStatus.downloading ||
        status == DownloadStatus.pending;
    final color = _getStatusColor();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: AppTransitions.controls,
      curve: AppTransitions.curveSymmetric,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: isDark ? AppOpacity.pressed : AppOpacity.hover,
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color:
              isDark
                  ? AppColors.darkMuted.withValues(alpha: AppOpacity.scrim)
                  : Colors.black.withValues(alpha: AppOpacity.divider),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: AppTransitions.controls,
            child:
                isActive
                    ? SizedBox(
                      key: const ValueKey('active'),
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    )
                    : _allCompleted
                    ? CompletionCheckmark(
                      key: const ValueKey('completed'),
                      size: 12,
                      color: color,
                    )
                    : Icon(
                      _getStatusIcon(),
                      key: ValueKey(status),
                      size: 10,
                      color: color,
                    ),
          ),
          const SizedBox(width: AppSpacing.xs),
          AnimatedSwitcher(
            duration: AppTransitions.normal,
            child: Text(
              status.displayLabel,
              key: ValueKey(status.displayLabel),
              style: AppTypography.mini.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getStatusIcon() {
    final status = _aggregateStatus;
    if (status == DownloadStatus.completed) return Icons.check_circle;
    if (status == DownloadStatus.paused) return Icons.pause_circle;
    if (status == DownloadStatus.waitingForNetwork) {
      return Icons.wifi_off_rounded;
    }
    if (status == DownloadStatus.failed) return Icons.error;
    if (status == DownloadStatus.cancelled) return Icons.cancel;
    return Icons.pending;
  }

  /// Single-tap: open the side panel on the group head AND, for
  /// video-kind groups, seed the playback queue so the right-panel
  /// Playlist tab + the eventual fullscreen-expand step both have
  /// the full collection to work with. Without the seed step the
  /// right panel renders empty Playlist tab + the expand button
  /// pushes a VideoPlayerScreen with a queue of one — exactly the
  /// runtime symptom Chairman saw on a freshly-tapped playlist
  /// group. Image carousels still flow through `showDetail` only;
  /// the existing image embed path consumes `group.downloads`
  /// independently of the playback queue.
  void _onGroupCardTap() {
    // Playlist folder (All tab): a tap opens the playlist's detail list.
    final onOpenPlaylist = widget.onOpenPlaylist;
    if (onOpenPlaylist != null) {
      final keyPrefix = switch (widget.group.kind) {
        GroupedItemKind.ytSourcePlaylist => 'source',
        GroupedItemKind.userPlaylist => 'user',
        GroupedItemKind.imageCarousel => null,
      };
      if (keyPrefix != null) {
        onOpenPlaylist('$keyPrefix:${widget.group.groupId}');
        return;
      }
    }

    final action = decideGroupedCardOpenAction(
      kind: widget.group.kind,
      downloads: widget.group.downloads,
    );
    if (action is OpenVideoQueue) {
      ref.read(playbackQueueProvider.notifier).setQueue(action.queue);
    }
    // Always open the side panel on the head — single-tap UX is
    // "preview first item", and the queue we just seeded lets the
    // tab/fullscreen surfaces light up the rest.
    ref
        .read(rightPanelProvider.notifier)
        .showDetail(widget.group.downloads.first);
  }

  /// Activate the group — fullscreen entry point shared by double-tap,
  /// the expand IconButton and keyboard activation. Routing diverges
  /// per [GroupedItem.kind]: image carousels go to the image viewer,
  /// YouTube source / user playlists go to the video player with the
  /// group seeded into the playback queue.
  ///
  /// Pre-V2 this widget only rendered image carousels, so jumping
  /// straight to [ImageViewerScreen] was correct. V2 commit `f2e04405`
  /// reused this widget for `ytSourcePlaylist` + `userPlaylist`
  /// without updating this hop, so video groups landed in the image
  /// viewer — the regression every entry point on the card inherits.
  /// The decision is delegated to [decideGroupedCardOpenAction] so it
  /// can be unit-tested in isolation.
  void _openCarousel() {
    final action = decideGroupedCardOpenAction(
      kind: widget.group.kind,
      downloads: widget.group.downloads,
    );
    switch (action) {
      case OpenImageCarousel(:final first, :final carousel):
        Navigator.of(context).push(
          MaterialPageRoute(
            builder:
                (_) => ImageViewerScreen(
                  download: first,
                  carouselDownloads: carousel,
                ),
          ),
        );
      case OpenVideoQueue(:final first, :final queue):
        // VideoPlayerScreen reads queue state from playbackQueueProvider
        // on init — it does not take queue as a constructor arg — so
        // the queue must be set BEFORE the navigation hop. Set
        // `startIndex: 0` because [first] is always the head of the
        // group's downloads (see `decideGroupedCardOpenAction`).
        ref.read(playbackQueueProvider.notifier).setQueue(queue);
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => VideoPlayerScreen(download: first)),
        );
    }
  }

  /// Open file location of the first image
  Future<void> _openFolder() async {
    try {
      final filePath = p.join(_first.savePath, _first.filename);
      if (!File(filePath).existsSync()) {
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
          fallbackDirectory: _first.savePath,
        );
      } else if (Platform.isWindows) {
        await ProcessHelper.revealInFileManager(
          filePath,
          fallbackDirectory: _first.savePath,
        );
      } else if (Platform.isLinux) {
        await ProcessHelper.openDirectoryInFileManager(_first.savePath);
      }
    } catch (e) {
      appLogger.error('Failed to open file location', e);
      if (mounted) {
        AppSnackBar.error(
          context,
          message:
              'Failed to open location: ${AppExceptionX.readableMessage(e)}',
        );
      }
    }
  }

  Future<void> _pauseActive() async {
    final notifier = ref.read(downloadsNotifierProvider.notifier);
    for (final download in widget.group.downloads.where((d) => d.isActive)) {
      await notifier.pauseDownload(download.id);
    }
  }

  Future<void> _resumePaused() async {
    final notifier = ref.read(downloadsNotifierProvider.notifier);
    for (final download in widget.group.downloads.where(
      (d) => d.status == DownloadStatus.paused,
    )) {
      await notifier.resumeDownload(download.id);
    }
  }

  Future<void> _retryFailed() async {
    final notifier = ref.read(downloadsNotifierProvider.notifier);
    for (final download in widget.group.downloads.where(
      (d) => d.status == DownloadStatus.failed,
    )) {
      await notifier.retryDownload(download.id);
    }
  }

  /// Copy source URL to clipboard
  Future<void> _copyUrlToClipboard() async {
    try {
      await ClipboardService.setText(_first.url);
      if (mounted) {
        AppSnackBar.success(
          context,
          message: AppLocalizations.downloadsUrlCopied,
        );
      }
    } catch (e) {
      appLogger.error('Failed to copy URL', e);
    }
  }

  /// Delete dialog for grouped items.
  ///
  /// Captures the notifier + the download id list BEFORE [showDialog]
  /// so the action callbacks don't `ref.read` after this widget could
  /// be disposed (production crash class flagged in earlier audit:
  /// dialog button onPressed runs after `Navigator.pop` while parent
  /// `ref` may already be torn down). Mirrors the pattern in
  /// `showDownloadDeleteDialog` for the single-item path.
  void _showDeleteDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final notifier = ref.read(downloadsNotifierProvider.notifier);
    final ids = widget.group.downloads.map((d) => d.id).toList(growable: false);
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: isDark ? AppColors.darkBase : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              side:
                  isDark
                      ? BorderSide(
                        color: AppColors.darkMuted.withValues(
                          alpha: AppOpacity.subtle,
                        ),
                      )
                      : BorderSide.none,
            ),
            title: Text(
              AppLocalizations.downloadsDeleteDialogTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: isDark ? AppColors.darkLightText : null,
              ),
            ),
            content: Text(
              'Delete ${widget.group.count} images from "$_groupTitle"?',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isDark ? AppColors.darkMetaText : null,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.commonCancel),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  // Use captured `notifier` + `ids` from outside
                  // showDialog — see method-level comment.
                  for (final id in ids) {
                    notifier.deleteDownload(id, deleteFile: false);
                  }
                },
                child: Text(AppLocalizations.downloadsDeleteRecordOnly),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.errorRed,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  for (final id in ids) {
                    notifier.deleteDownload(id, deleteFile: true);
                  }
                },
                child: Text(AppLocalizations.downloadsDeleteFileAndRecord),
              ),
            ],
          ),
    );
  }

  /// Right-click context menu
  void _showContextMenu(Offset position) {
    final items = <PopupMenuEntry<String>>[];

    if (_allCompleted && !_anyFileMissing) {
      items.add(
        PopupMenuItem(
          value: 'open',
          child: ListTile(
            leading: const Icon(Icons.collections, size: 20),
            title: Text(AppLocalizations.contextMenuLabel('viewImages')),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      );
      items.add(
        PopupMenuItem(
          value: 'folder',
          child: ListTile(
            leading: const Icon(Icons.folder_open, size: 20),
            title: Text(AppLocalizations.contextMenuLabel('showInFolder')),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      );
      items.add(const PopupMenuDivider());
    }

    items.add(
      PopupMenuItem(
        value: 'copyUrl',
        child: ListTile(
          leading: const Icon(Icons.copy, size: 20),
          title: Text(AppLocalizations.contextMenuLabel('copyUrl')),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );

    items.add(const PopupMenuDivider());
    items.add(
      PopupMenuItem(
        value: 'delete',
        child: ListTile(
          leading: Icon(
            Icons.delete_outline,
            size: 20,
            color: AppColors.errorRed,
          ),
          title: Text(
            AppLocalizations.contextMenuLabel('deleteAll'),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.errorRed),
          ),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: items,
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'open':
          _openCarousel();
        case 'folder':
          _openFolder();
        case 'copyUrl':
          _copyUrlToClipboard();
        case 'delete':
          _showDeleteDialog();
      }
    });
  }
}
