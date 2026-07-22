import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../../core/core.dart';
import '../../../downloads/domain/entities/download_context_menu_action.dart';
import '../../../downloads/domain/entities/download_entity.dart';
import '../../../downloads/domain/entities/download_error_code.dart';
import '../../../downloads/domain/entities/download_status.dart';
import '../../../downloads/domain/services/download_context_menu_service.dart';
import '../../../downloads/presentation/providers/batch_selection_provider.dart';
import '../../../downloads/presentation/providers/downloads_notifier.dart';
import '../../../downloads/presentation/widgets/add_to_playlist_dialog.dart';
import '../../../downloads/presentation/widgets/note_editor_dialog.dart';
import '../../../downloads/presentation/widgets/schedule_picker_dialog.dart';
import '../../../premium/domain/entities/premium_feature.dart';
import '../../../premium/presentation/widgets/premium_feature_guard.dart';
import '../../../player/presentation/providers/player_providers.dart';
import '../../../player/presentation/providers/playback_queue_providers.dart';
import '../../../downloads/domain/entities/download_priority.dart';
import '../../../downloads/presentation/widgets/priority_badge.dart';
import '../../../../core/navigation/navigation_constants.dart';
import '../../../../core/navigation/right_panel_provider.dart';
import '../../../../core/services/native_mac_service.dart';
import '../../../browser/presentation/providers/browser_providers.dart';
import '../../../converter/presentation/providers/converter_providers.dart';
import '../../../support/presentation/widgets/bug_report_dialog.dart';
import 'download_progress_painter.dart';
import 'download_list_helpers.dart';

/// Download Item Card with inline status and actions (list view variant).
class DownloadItemCard extends ConsumerStatefulWidget {
  final DownloadEntity download;
  final bool isKeyboardFocused;
  final bool inPanel;
  final ValueChanged<DownloadEntity>? onRemoveFromPlaylist;
  final ValueChanged<DownloadEntity>? onMovePlaylistItemUp;
  final ValueChanged<DownloadEntity>? onMovePlaylistItemDown;

  const DownloadItemCard({
    super.key,
    required this.download,
    this.isKeyboardFocused = false,
    this.inPanel = false,
    this.onRemoveFromPlaylist,
    this.onMovePlaylistItemUp,
    this.onMovePlaylistItemDown,
  });

  @override
  ConsumerState<DownloadItemCard> createState() => _DownloadItemCardState();
}

class _DownloadItemCardState extends ConsumerState<DownloadItemCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // Start shimmer animation if downloading
    if (widget.download.isActive) {
      _shimmerController.repeat();
    }
  }

  @override
  void didUpdateWidget(DownloadItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update shimmer animation based on status
    if (widget.download.isActive && !_shimmerController.isAnimating) {
      _shimmerController.repeat();
    } else if (!widget.download.isActive && _shimmerController.isAnimating) {
      _shimmerController.stop();
    }
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  /// Whether the file is missing from disk (deleted from Finder)
  bool get _isFileMissing {
    final downloadsState = ref.read(downloadsNotifierProvider);
    return downloadsState.isFileMissing(widget.download.id);
  }

  bool get _hasPrimaryAction =>
      widget.download.canPause ||
      widget.download.canResume ||
      widget.download.canRetry ||
      widget.download.isCompleted;

  void _toggleSelection(WidgetRef ref) {
    final id = widget.download.id;
    final current = ref.read(batchSelectionProvider);
    ref.read(batchSelectionProvider.notifier).state =
        current.contains(id)
            ? (Set.from(current)..remove(id))
            : {...current, id};
  }

  /// Single-tap entry point for the row card. Opens the side panel
  /// AND, when this download is a member of a source or user-created
  /// playlist, seeds the playback queue with all siblings in playlist
  /// order so the right-panel Playlist tab and any subsequent
  /// fullscreen-expand both have the full queue.
  ///
  /// V2 reconcile (2026-05-08): downloads list no longer collapses
  /// playlist members into a single grouped card, so the queue
  /// context that used to be implied by a tap on the group card is
  /// now resolved from the playlist library first, then from legacy
  /// `download.playlistId` fallback.
  void _onCardTap(WidgetRef ref) {
    seedPlaybackQueue(ref, widget.download);
    ref.read(rightPanelProvider.notifier).showDetail(widget.download);
  }

  List<String> _metadataParts() {
    final parts = <String>[];
    if (widget.download.qualityLabel != null) {
      parts.add(_formatQualityLabel(widget.download.qualityLabel!));
    }
    if (widget.download.fileExtension.isNotEmpty) {
      parts.add(
        widget.download.fileExtension.replaceAll('.', '').toUpperCase(),
      );
    }
    if (widget.download.formattedViewCount != null) {
      parts.add(widget.download.formattedViewCount!);
    }
    if (widget.download.isCompleted) {
      parts.add(FileUtils.formatBytes(widget.download.totalBytes));
      parts.add(Formatters.formatDate(widget.download.createdAt));
    }
    if (widget.download.userNote.isNotEmpty) {
      parts.add(AppLocalizations.notesEditNote);
    }
    return parts.where((part) => part.trim().isNotEmpty).toList();
  }

  Widget _buildPanelMetadataLine(bool isFileMissing) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final metaColor =
        isDark
            ? AppColors.homeDarkTextMuted
            : Theme.of(context).colorScheme.onSurfaceVariant;
    final parts = _metadataParts();

    return Row(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildStatusBadge(),
        if (isFileMissing) ...[
          const SizedBox(width: AppSpacing.xs),
          buildFileMissingBadge(context),
        ],
        if (parts.isNotEmpty) ...[
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              parts.join('  ·  '),
              style: AppTypography.metadata.copyWith(
                color: metaColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.15,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBadgeMetadataWrap(bool isFileMissing) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        _buildStatusBadge(),
        if (isFileMissing) buildFileMissingBadge(context),
        if (widget.download.qualityLabel != null)
          buildMetadataBadge(
            context,
            Icons.high_quality_outlined,
            _formatQualityLabel(widget.download.qualityLabel!),
          ),
        if (widget.download.fileExtension.isNotEmpty) _buildFormatBadge(),
        if (widget.download.formattedViewCount != null)
          buildMetadataBadge(
            context,
            Icons.visibility_outlined,
            widget.download.formattedViewCount!,
          ),
        if (widget.download.isCompleted) ...[
          buildMetadataBadge(
            context,
            Icons.file_present,
            FileUtils.formatBytes(widget.download.totalBytes),
          ),
          buildMetadataBadge(
            context,
            Icons.calendar_today,
            Formatters.formatDate(widget.download.createdAt),
          ),
        ],
        if (widget.download.userNote.isNotEmpty)
          buildMetadataBadge(
            context,
            Icons.edit_note,
            AppLocalizations.notesEditNote,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFileMissing = _isFileMissing;
    final selectedIds = ref.watch(batchSelectionProvider);
    final isSelectionMode = selectedIds.isNotEmpty;
    final isSelected = selectedIds.contains(widget.download.id);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Keep degraded states readable in the manager list. The status,
    // error strip and thumbnail treatment already signal failure.
    final cardOpacity =
        widget.download.isCancelled && !_isHovered
            ? AppOpacity.nearOpaque
            : 1.0;

    final cs = Theme.of(context).colorScheme;
    final accentColor = getStatusAccentColor(widget.download);
    final titleText =
        widget.download.displayTitle.trim().isEmpty
            ? widget.download.filenameWithoutExtension
            : widget.download.displayTitle.trim();
    Color cardColor;
    if (isSelected) {
      cardColor =
          isDark
              ? AppColors.homeDarkCardSelected
              : AppColors.accentHighlight.withValues(alpha: AppOpacity.hover);
    } else if (widget.download.isActive && isDark) {
      cardColor = AppColors.homeDarkCardActive;
    } else if (widget.inPanel) {
      cardColor =
          _isHovered
              ? (isDark
                  ? AppColors.homeDarkCardHover
                  : AppColors.accentHighlight.withValues(
                    alpha: AppOpacity.divider,
                  ))
              : Colors.transparent;
    } else if (_isHovered) {
      cardColor =
          isDark ? AppColors.homeDarkCardHover : AppColors.lightElevated;
    } else {
      cardColor = isDark ? AppColors.homeDarkCardBg : const Color(0xFFFFFFFF);
    }

    final borderColor =
        isSelected
            ? AppColors.accentHighlight.withValues(alpha: AppOpacity.medium)
            : widget.download.isActive
            ? AppColors.accentHighlight.withValues(
              alpha: isDark ? AppOpacity.quarter : AppOpacity.subtle,
            )
            : widget.inPanel
            ? Colors.transparent
            : isDark
            ? (_isHovered
                ? AppColors.homeDarkBorderStrong
                : AppColors.homeDarkBorderSubtle)
            : _isHovered
            ? cs.onSurface.withValues(alpha: AppOpacity.pressed)
            : Colors.transparent;

    final borderWidth =
        isSelected || widget.download.isActive || _isHovered ? 0.9 : 0.4;
    final showStateRail =
        isSelected ||
        widget.download.isActive ||
        widget.download.isFailed ||
        widget.download.isPaused ||
        widget.download.isCancelled ||
        !widget.inPanel;

    return AnimatedOpacity(
      duration: AppTransitions.normal,
      opacity: cardOpacity,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          if (mounted) setState(() => _isHovered = true);
        },
        onExit: (_) {
          if (mounted) setState(() => _isHovered = false);
        },
        child: GestureDetector(
          onTap:
              isSelectionMode
                  ? () => _toggleSelection(ref)
                  : () => _onCardTap(ref),
          onDoubleTap:
              isSelectionMode || (!widget.download.isCompleted || isFileMissing)
                  ? null
                  : () => openPlayerForDownload(context, ref, widget.download),
          onLongPress: () => _toggleSelection(ref),
          onSecondaryTapUp:
              (details) => _showContextMenu(details.globalPosition),
          child: AnimatedContainer(
            duration: AppTransitions.normal,
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: borderColor, width: borderWidth),
              boxShadow:
                  isDark && widget.download.status == DownloadStatus.downloading
                      ? [
                        BoxShadow(
                          color: AppColors.accentHighlight.withValues(
                            alpha: AppOpacity.subtle,
                          ),
                          blurRadius: 18,
                          spreadRadius: -8,
                        ),
                      ]
                      : widget.inPanel || isDark
                      ? null
                      : _isHovered
                      ? [
                        BoxShadow(
                          color: const Color(0x12000000),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                          spreadRadius: -8,
                        ),
                      ]
                      : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: Stack(
                children: [
                  if (showStateRail)
                    Positioned.fill(
                      left: 0,
                      right: null,
                      child: AnimatedContainer(
                        duration: AppTransitions.normal,
                        width: widget.download.isActive || isSelected ? 3 : 2,
                        color: accentColor.withValues(
                          alpha:
                              widget.download.isCompleted
                                  ? AppOpacity.medium
                                  : AppOpacity.nearOpaque,
                        ),
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.smMd,
                      widget.inPanel ? AppSpacing.sm : AppSpacing.xs,
                      AppSpacing.sm,
                      widget.inPanel ? AppSpacing.sm : AppSpacing.xs,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.inPanel) ...[
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _toggleSelection(ref),
                            child: SizedBox(
                              width: 26,
                              height: kDownloadThumbHeight,
                              child: Align(
                                alignment: Alignment.center,
                                child: SelectionCheckbox(selected: isSelected),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                        ],
                        _buildThumbnail(),
                        const SizedBox(width: AppSpacing.smMd),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildPriorityBadge(),
                                  Expanded(
                                    child: Text(
                                      titleText,
                                      style: AppTypography.fileName.copyWith(
                                        fontWeight: FontWeight.w600,
                                        fontSize: widget.inPanel ? 15 : null,
                                        height: widget.inPanel ? 1.18 : null,
                                        color:
                                            widget.download.isFailed
                                                ? (isDark
                                                    ? AppColors.darkMetaText
                                                    : Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant)
                                                : (isDark
                                                    ? AppColors.darkLightText
                                                    : Theme.of(
                                                      context,
                                                    ).colorScheme.onSurface),
                                        decoration:
                                            widget.download.isFailed
                                                ? TextDecoration.lineThrough
                                                : null,
                                        decorationColor:
                                            isDark
                                                ? AppColors.darkMuted
                                                : Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(
                                                      alpha: AppOpacity.scrim,
                                                    ),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              if (widget.download.uploader != null) ...[
                                const SizedBox(height: AppSpacing.xxs),
                                Text(
                                  widget.download.uploader!,
                                  style: AppTypography.metadata.copyWith(
                                    fontSize: widget.inPanel ? 12.5 : null,
                                    height: widget.inPanel ? 1.15 : null,
                                    color:
                                        isDark
                                            ? AppColors.homeDarkTextSecondary
                                            : Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              const SizedBox(height: AppSpacing.xxs),
                              widget.inPanel
                                  ? _buildPanelMetadataLine(isFileMissing)
                                  : _buildBadgeMetadataWrap(isFileMissing),
                              if (widget.download.isActive) ...[
                                const SizedBox(height: AppSpacing.sm),
                                _buildInlineProgress(isDark),
                              ],
                              if (widget.download.errorMessage != null) ...[
                                const SizedBox(height: AppSpacing.sm),
                                _buildErrorFeedback(context, widget.download),
                              ],
                              if (widget.download.isWatched) ...[
                                const SizedBox(height: AppSpacing.xs),
                                buildWatchedChip(compact: true),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.smMd),
                        SizedBox(
                          height: kDownloadThumbHeight,
                          child: Center(child: _buildActionCluster()),
                        ),
                      ],
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

  Widget _buildInlineProgress(bool isDark) {
    final metaColor =
        isDark
            ? AppColors.darkMetaText
            : Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DownloadProgressBar(
          progress: widget.download.progress,
          color: _getStatusColor(),
          backgroundColor:
              isDark ? AppColors.darkElevated : AppColors.lightSurface3,
          height: 3.0,
          animate: widget.download.status == DownloadStatus.downloading,
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              widget.download.totalBytes > 0
                  ? '${FileUtils.formatBytes(widget.download.downloadedBytes)} / ${FileUtils.formatBytes(widget.download.totalBytes)}'
                  : widget.download.status == DownloadStatus.pending
                  ? 'Waiting...'
                  : 'Preparing...',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: metaColor, height: 1.1),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (widget.download.speed > 0)
              Text(
                '↓ ${Formatters.formatSpeed(widget.download.speed)}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.accentHighlight,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (widget.download.speed > 0 &&
                widget.download.estimatedRemainingSeconds != null)
              Text(
                '· ${Formatters.formatDuration(Duration(seconds: widget.download.estimatedRemainingSeconds!))}',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: metaColor, height: 1.1),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionCluster() {
    final actionWidth = widget.inPanel ? 34.0 : 30.0;
    final gap = widget.inPanel ? AppSpacing.sm : AppSpacing.xs;
    return SizedBox(
      width: _hasPrimaryAction ? actionWidth * 2 + gap : actionWidth,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_hasPrimaryAction) ...[
            _buildPrimaryAction(),
            SizedBox(width: gap),
          ],
          _buildMoreActionButton(),
        ],
      ),
    );
  }

  Widget _buildThumbnail() {
    Widget thumbnailImage;

    if (widget.download.thumbnail != null) {
      thumbnailImage = AppCachedImage(
        imageUrl: widget.download.thumbnail,
        width: kDownloadThumbWidth,
        height: kDownloadThumbHeight,
        errorWidget: _buildPlaceholderThumbnail(),
      );
    } else if (widget.download.status.toDbString() == 'pending' ||
        widget.download.status.toDbString() == 'extracting') {
      thumbnailImage = const ShimmerPlaceholder(
        width: kDownloadThumbWidth,
        height: kDownloadThumbHeight,
      );
    } else {
      thumbnailImage = _buildPlaceholderThumbnail();
    }

    // Apply state-specific visual treatment (Nocturne Cinematic)
    final isFailed = widget.download.isFailed;
    final isCancelled = widget.download.isCancelled;
    final isPaused = widget.download.isPaused;
    if (isFailed || isCancelled) {
      thumbnailImage = ColorFiltered(
        colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.saturation),
        child: Opacity(opacity: isFailed ? 0.68 : 0.42, child: thumbnailImage),
      );
    } else if (isPaused) {
      thumbnailImage = Opacity(opacity: 0.7, child: thumbnailImage);
    }

    // Wrap in Stack for overlays — sharp corners (Nocturne)
    return SizedBox(
      width: kDownloadThumbWidth,
      height: kDownloadThumbHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Stack(
          children: [
            thumbnailImage,

            // Platform icon overlay (top-left) — SVG brand logo
            if (widget.download.platform.isNotEmpty &&
                widget.download.platform != 'unknown')
              Positioned(
                top: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.xxs),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: AppOpacity.secondary),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: PlatformIcon(
                    platform: widget.download.platform,
                    size: 16,
                  ),
                ),
              ),

            // Duration overlay (bottom-right) — YouTube style
            if (widget.download.formattedDuration != null)
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(
                      alpha: AppOpacity.nearOpaque,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Text(
                    widget.download.formattedDuration!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: AppTypography.semiBold,
                      height: 1.2,
                    ),
                  ),
                ),
              ),

            // Audio badge (bottom-left): an album-art thumbnail otherwise looks
            // identical to a video — flag audio-only files at a glance.
            if (FileUtils.isAudioFile(widget.download.filename))
              Positioned(
                bottom: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.xxs),
                  decoration: BoxDecoration(
                    color: AppColors.accentSecondary.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: const Icon(
                    Icons.music_note_rounded,
                    size: 13,
                    color: Colors.white,
                  ),
                ),
              ),

            // Failed error overlay (centered)
            if (widget.download.isFailed)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: AppOpacity.medium),
                  child: Icon(
                    Icons.error,
                    color: AppColors.statusFailed(context),
                    size: 28,
                  ),
                ),
              ),

            // Watch progress bar (bottom, YouTube-style red bar)
            if (widget.download.isCompleted) _buildWatchProgressBar(),

            // Selection checkbox (top-right) — visible when selection mode is active
            if (!widget.inPanel && ref.watch(batchSelectionProvider).isNotEmpty)
              Positioned(
                top: 4,
                right: 4,
                child: SelectionCheckbox(
                  onImage: true,
                  selected: ref
                      .watch(batchSelectionProvider)
                      .contains(widget.download.id),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Thin red progress bar at bottom of thumbnail showing how much has been watched
  Widget _buildWatchProgressBar() {
    try {
      final watchService = ref.read(watchProgressServiceProvider);
      final fraction = watchService.getWatchFraction(widget.download.id);
      if (fraction == null || fraction <= 0.0) return const SizedBox.shrink();

      return Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: LinearProgressIndicator(
          value: fraction,
          minHeight: 3,
          backgroundColor: Colors.black.withValues(alpha: AppOpacity.scrim),
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.accentHighlight),
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildPlaceholderThumbnail() {
    final fileColor = getFileTypeColor(context, widget.download);
    return Container(
      width: kDownloadThumbWidth,
      height: kDownloadThumbHeight,
      decoration: BoxDecoration(
        color: fileColor.withValues(alpha: AppOpacity.hover),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Icon(
        getFileIcon(widget.download),
        size: 32,
        color: fileColor.withValues(alpha: AppOpacity.secondary),
      ),
    );
  }

  Widget _buildStatusBadge() {
    final color = _getStatusColor();
    final containerColor = getDownloadStatusContainerColor(
      context,
      widget.download,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: AppTransitions.controls,
      curve: AppTransitions.curveSymmetric,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: color.withValues(
            alpha: isDark ? AppOpacity.quarter : AppOpacity.subtle,
          ),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: AppTransitions.controls,
            child:
                widget.download.isActive
                    ? SizedBox(
                      key: const ValueKey('active'),
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    )
                    : widget.download.isCompleted
                    ? CompletionCheckmark(
                      key: const ValueKey('completed'),
                      size: 14,
                      color: color,
                    )
                    : Icon(
                      getDownloadStatusIcon(widget.download),
                      key: ValueKey(widget.download.status),
                      size: 13,
                      color: color,
                    ),
          ),
          const SizedBox(width: AppSpacing.xs),
          AnimatedSwitcher(
            duration: AppTransitions.normal,
            child: Text(
              widget.download.status.displayLabel,
              key: ValueKey(widget.download.status.displayLabel),
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

  /// Format quality label for display — extract short form
  /// e.g., "MP4 720p [720x1280]" -> "720p"
  /// e.g., "Audio Only (mp3)" -> "Audio"
  String _formatQualityLabel(String label) {
    // Try to extract resolution like "720p", "1080p", "4K"
    final resMatch = RegExp(
      r'(\d{3,4}p|[248]K)',
      caseSensitive: false,
    ).firstMatch(label);
    if (resMatch != null) return resMatch.group(0)!;
    // Audio-only
    if (label.toLowerCase().contains('audio')) return 'Audio';
    // Fallback: return first meaningful part
    return label.length > 12 ? label.substring(0, 12) : label;
  }

  /// Build file format extension badge (e.g., MP4, MP3, WAV)
  Widget _buildFormatBadge() {
    final ext = widget.download.fileExtension.replaceAll('.', '').toUpperCase();
    if (ext.isEmpty) return const SizedBox.shrink();

    final isAudio = [
      'MP3',
      'WAV',
      'FLAC',
      'M4A',
      'AAC',
      'OGG',
      'OPUS',
    ].contains(ext);
    final isVideo = ['MP4', 'MKV', 'AVI', 'MOV', 'WEBM'].contains(ext);
    final isImage = ['JPG', 'JPEG', 'PNG', 'GIF', 'WEBP'].contains(ext);

    final IconData icon;
    if (isAudio) {
      icon = Icons.audiotrack;
    } else if (isVideo) {
      icon = Icons.videocam;
    } else if (isImage) {
      icon = Icons.image;
    } else {
      icon = Icons.insert_drive_file;
    }

    return buildMetadataBadge(
      context,
      icon,
      ext,
      color: isAudio ? AppColors.accentSecondary : null,
    );
  }

  /// Priority badge — shows smart-boost OR manual priority.
  /// Tappable for pending/queued downloads to open priority selector.
  Widget _buildPriorityBadge() {
    final downloadsState = ref.watch(downloadsNotifierProvider);
    final isBoosted = downloadsState.isSmartBoosted(widget.download.id);
    final manualPriority = DownloadPriority.fromInt(widget.download.priority);
    final isPendingOrQueued =
        widget.download.status == DownloadStatus.pending ||
        widget.download.status == DownloadStatus.queued;

    Widget? badge;
    if (isBoosted) {
      badge = const PriorityBadge(isHigh: true, isSmartBoosted: true);
    } else if (manualPriority == DownloadPriority.high) {
      badge = const PriorityBadge(isHigh: true);
    } else if (manualPriority == DownloadPriority.low) {
      badge = const PriorityBadge(isLow: true);
    }

    if (badge == null) return const SizedBox.shrink();

    final wrapped = Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: badge,
    );
    if (isPendingOrQueued) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) => _showPriorityMenu(details.globalPosition),
        child: Tooltip(
          message: AppLocalizations.smartQueueSetPriority,
          child: wrapped,
        ),
      );
    }
    return wrapped;
  }

  /// Primary action button — always visible (top-right of title row)
  Widget _buildPrimaryAction() {
    final notifier = ref.read(downloadsNotifierProvider.notifier);

    if (widget.download.canPause) {
      return _actionButton(
        icon: Icons.pause_rounded,
        tooltip: AppLocalizations.downloadsPause,
        color: AppColors.statusActive(context),
        onPressed: () => notifier.pauseDownload(widget.download.id),
      );
    }
    if (widget.download.canResume) {
      return _actionButton(
        icon: Icons.play_arrow_rounded,
        tooltip: AppLocalizations.downloadsResume,
        color: AppColors.statusPaused(context),
        onPressed: () => notifier.resumeDownload(widget.download.id),
      );
    }
    if (widget.download.canRetry) {
      return _actionButton(
        icon: Icons.refresh_rounded,
        tooltip: AppLocalizations.commonRetry,
        color: Theme.of(context).colorScheme.error,
        onPressed: () => notifier.retryDownload(widget.download.id),
      );
    }
    if (widget.download.isCompleted) {
      if (_isFileMissing) {
        // File deleted from Finder — show re-download action
        return _actionButton(
          icon: Icons.refresh_rounded,
          tooltip: AppLocalizations.downloadsRedownload,
          color: Theme.of(context).colorScheme.error,
          onPressed: _redownloadFromSource,
        );
      }
      return _actionButton(
        icon: _completedPrimaryIcon(),
        tooltip: AppLocalizations.homeOpen,
        color: AppColors.accentHighlight,
        onPressed: () => openPlayerForDownload(context, ref, widget.download),
      );
    }
    return const SizedBox.shrink();
  }

  IconData _completedPrimaryIcon() {
    final filename = widget.download.filename;
    if (FileUtils.isVideoFile(filename) || FileUtils.isAudioFile(filename)) {
      return Icons.play_arrow_rounded;
    }
    if (FileUtils.isImageFile(filename)) {
      return Icons.visibility_rounded;
    }
    return Icons.open_in_new_rounded;
  }

  void _redownloadFromSource() {
    ClipboardService.setText(widget.download.url);
    ref
        .read(navigationProvider.notifier)
        .navigateToTab(NavigationConstants.homeIndex);
    if (context.mounted) {
      AppSnackBar.info(
        context,
        message: AppLocalizations.downloadsUrlCopied,
        duration: const Duration(seconds: 2),
      );
    }
  }

  Widget _buildMoreActionButton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color =
        isDark
            ? AppColors.darkMetaText
            : Theme.of(context).colorScheme.onSurfaceVariant;
    final size = widget.inPanel ? 34.0 : 30.0;
    final iconSize = widget.inPanel ? 19.0 : 18.0;
    return Builder(
      builder:
          (buttonContext) => SizedBox(
            width: size,
            height: size,
            child: IconButton(
              icon: Icon(Icons.more_vert_rounded, size: iconSize),
              tooltip: AppLocalizations.commonMore,
              padding: EdgeInsets.zero,
              color: color,
              style: IconButton.styleFrom(
                backgroundColor:
                    isDark
                        ? AppColors.homeDarkCardHover
                        : color.withValues(alpha: AppOpacity.hover),
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

  Widget _actionButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onPressed,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = widget.inPanel ? 34.0 : 30.0;
    final iconSize = widget.inPanel ? 18.0 : 16.0;
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: iconSize),
        tooltip: tooltip,
        iconSize: iconSize,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          foregroundColor: color,
          backgroundColor: color.withValues(
            alpha: isDark ? AppOpacity.pressed : AppOpacity.hover,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
        ),
      ),
    );
  }

  /// Error feedback — Nocturne: left accent border, obsidian bg.
  Widget _buildErrorFeedback(BuildContext context, DownloadEntity download) {
    final errorCode = download.errorCode;
    final errorDetail = download.errorDetail;
    final isWaiting = download.isWaitingForNetwork;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final color = isWaiting ? AppColors.warningAmber : AppColors.errorRed;

    final icon = errorCode?.icon ?? Icons.error_outline_rounded;
    final title =
        errorCode != null
            ? AppLocalizations.errorFeedbackTitle(errorCode.name)
            : AppLocalizations.errorUnexpected;
    final hint =
        errorCode != null
            ? AppLocalizations.errorFeedbackHint(errorCode.name)
            : null;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: isDark ? AppOpacity.divider : AppOpacity.divider,
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border(
          left: BorderSide(
            width: 2,
            color: color.withValues(alpha: AppOpacity.strong),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.statusBadge.copyWith(color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (errorDetail != null)
                InkWell(
                  onTap: () {
                    ClipboardService.setText(errorDetail);
                    AppSnackBar.info(
                      context,
                      message: AppLocalizations.errorFeedbackCopied,
                    );
                  },
                  child: Icon(
                    Icons.copy_rounded,
                    size: 14,
                    color: color.withValues(alpha: AppOpacity.overlay),
                  ),
                ),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              hint,
              style: AppTypography.compact.copyWith(
                color: color.withValues(alpha: AppOpacity.strong),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  /// Shows a priority selector popup for pending/queued downloads.
  void _showPriorityMenu(Offset position) {
    final currentPriority = DownloadPriority.fromInt(widget.download.priority);
    final notifier = ref.read(downloadsNotifierProvider.notifier);

    showMenu<DownloadPriority>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items:
          DownloadPriority.values.map((p) {
            final isSelected = p == currentPriority;
            return PopupMenuItem<DownloadPriority>(
              value: p,
              child: ListTile(
                leading: Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color:
                      isSelected ? Theme.of(context).colorScheme.primary : null,
                ),
                title: Text(p.displayLabel),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            );
          }).toList(),
    ).then((selected) {
      if (selected != null) notifier.setPriority(widget.download.id, selected);
    });
  }

  /// Right-click context menu
  void _showContextMenu(Offset position) {
    const service = DownloadContextMenuService();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final actions = service.enabledActions(
      widget.download,
      isFileMissing: _isFileMissing,
    );

    final items = <PopupMenuEntry<DownloadContextMenuAction>>[];

    for (final action in actions) {
      // Group the menu: file/playback · source/clipboard · library · delete.
      if ((action == DownloadContextMenuAction.copyUrl ||
              action == DownloadContextMenuAction.editNote ||
              action == DownloadContextMenuAction.delete) &&
          items.isNotEmpty) {
        items.add(const PopupMenuDivider(height: AppSpacing.sm));
      }

      final actionColor =
          action.isDestructive
              ? AppColors.errorRed
              : action == DownloadContextMenuAction.addToPlaylist
              ? AppColors.accentHighlight
              : AppColors.metaText(context);
      final labelColor =
          action.isDestructive
              ? AppColors.errorRed
              : isDark
              ? AppColors.darkLightText
              : theme.colorScheme.onSurface;
      items.add(
        PopupMenuItem(
          value: action,
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: actionColor.withValues(
                    alpha: action.isDestructive ? 0.10 : AppOpacity.hover,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Icon(action.icon, size: 17, color: actionColor),
              ),
              const SizedBox(width: AppSpacing.smMd),
              Expanded(
                child: Text(
                  AppLocalizations.contextMenuLabel(action.titleKey),
                  style: AppTypography.metadata.copyWith(
                    color: labelColor,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (widget.onMovePlaylistItemUp != null ||
        widget.onMovePlaylistItemDown != null ||
        widget.onRemoveFromPlaylist != null) {
      items.add(const PopupMenuDivider(height: AppSpacing.sm));
    }
    if (widget.onMovePlaylistItemUp != null) {
      items.add(
        PopupMenuItem<DownloadContextMenuAction>(
          value: null,
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          onTap: () => widget.onMovePlaylistItemUp!(widget.download),
          child: Row(
            children: [
              Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 18,
                color: AppColors.accentHighlight,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(AppLocalizations.playlistRowMenuMoveUp)),
            ],
          ),
        ),
      );
    }
    if (widget.onMovePlaylistItemDown != null) {
      items.add(
        PopupMenuItem<DownloadContextMenuAction>(
          value: null,
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          onTap: () => widget.onMovePlaylistItemDown!(widget.download),
          child: Row(
            children: [
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: AppColors.accentHighlight,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(AppLocalizations.playlistRowMenuMoveDown)),
            ],
          ),
        ),
      );
    }
    if (widget.onRemoveFromPlaylist != null) {
      items.add(
        PopupMenuItem<DownloadContextMenuAction>(
          value: null,
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          onTap: () => widget.onRemoveFromPlaylist!(widget.download),
          child: Row(
            children: [
              Icon(
                Icons.playlist_remove_rounded,
                size: 18,
                color: AppColors.errorRed,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  AppLocalizations.rightPanelActionRemoveFromList,
                  style: TextStyle(color: AppColors.errorRed),
                ),
              ),
            ],
          ),
        ),
      );
    }

    showMenu<DownloadContextMenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: isDark ? AppColors.homeDarkCardBg : Colors.white,
      elevation: isDark ? 0 : 8,
      shadowColor: Colors.black.withValues(alpha: AppOpacity.hover),
      constraints: const BoxConstraints(minWidth: 250, maxWidth: 310),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(
          color:
              isDark
                  ? AppColors.homeDarkBorderStrong
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      items: items,
    ).then((action) {
      if (action == null) return;
      _handleContextMenuAction(action);
    });
  }

  void _handleContextMenuAction(DownloadContextMenuAction action) {
    final notifier = ref.read(downloadsNotifierProvider.notifier);
    switch (action) {
      case DownloadContextMenuAction.openFile:
        openPlayerForDownload(context, ref, widget.download);
      case DownloadContextMenuAction.showInFolder:
        openFileLocation(context, ref, widget.download);
      case DownloadContextMenuAction.shareFile:
        NativeMacService.shareFile(
          p.join(widget.download.savePath, widget.download.filename),
        );
      case DownloadContextMenuAction.pause:
        notifier.pauseDownload(widget.download.id);
      case DownloadContextMenuAction.resume:
        notifier.resumeDownload(widget.download.id);
      case DownloadContextMenuAction.cancel:
        notifier.cancelDownload(widget.download.id);
      case DownloadContextMenuAction.retry:
        notifier.retryDownload(widget.download.id);
      case DownloadContextMenuAction.copyUrl:
        copyDownloadUrl(context, widget.download);
      case DownloadContextMenuAction.openInBrowser:
        if (widget.download.url.isEmpty) break; // no source URL → no blank tab
        ref.read(browserInitialUrlProvider.notifier).state =
            widget.download.url;
        ref
            .read(navigationProvider.notifier)
            .navigateToTab(NavigationConstants.browserIndex);
      case DownloadContextMenuAction.copyFilePath:
        copyDownloadFilePath(context, widget.download);
      case DownloadContextMenuAction.editNote:
        _showNoteEditor();
      case DownloadContextMenuAction.markWatched:
        ref
            .read(watchProgressServiceProvider)
            .markAsWatched(widget.download.id);
        AppSnackBar.info(
          context,
          message: AppLocalizations.watchStatusWatched,
        );
      case DownloadContextMenuAction.markUnwatched:
        ref
            .read(watchProgressServiceProvider)
            .markAsUnwatched(widget.download.id);
        AppSnackBar.info(
          context,
          message: AppLocalizations.watchStatusUnwatched,
        );
      case DownloadContextMenuAction.delete:
        showDownloadDeleteDialog(context, ref, widget.download);
      case DownloadContextMenuAction.playNext:
        ref.read(playbackQueueProvider.notifier).playNext(widget.download);
        AppSnackBar.info(
          context,
          message: AppLocalizations.playbackQueuePlayNext,
        );
      case DownloadContextMenuAction.addToQueue:
        ref.read(playbackQueueProvider.notifier).addToQueue(widget.download);
        AppSnackBar.info(
          context,
          message: AppLocalizations.playbackQueueAddToQueue,
        );
      case DownloadContextMenuAction.watchNow:
        openPreviewForDownload(context, widget.download);
      case DownloadContextMenuAction.scheduleFor:
        _guardedSchedulePicker();
      case DownloadContextMenuAction.redownload:
        _redownloadFromSource();
      case DownloadContextMenuAction.convert:
        final filePath = p.join(
          widget.download.savePath,
          widget.download.filename,
        );
        ref.read(converterInputFileProvider.notifier).state = filePath;
        ref
            .read(navigationProvider.notifier)
            .navigateToTab(NavigationConstants.converterIndex);
      case DownloadContextMenuAction.reportError:
        BugReportDialog.show(context, downloadContext: widget.download);
      case DownloadContextMenuAction.addToPlaylist:
        _showAddToPlaylistDialog();
    }
  }

  Future<void> _showAddToPlaylistDialog() async {
    final playlistName = await AddToPlaylistDialog.show(
      context,
      downloadIds: [widget.download.id],
    );
    if (!mounted || playlistName == null) return;
    AppSnackBar.success(
      context,
      message: AppLocalizations.playlistAddSuccess(1, playlistName),
    );
  }

  Future<void> _guardedSchedulePicker() async {
    await PremiumFeatureGuard.run(
      ref: ref,
      context: context,
      feature: PremiumFeature.scheduledDownloads,
      action: () => _showSchedulePicker(),
    );
  }

  Future<void> _showSchedulePicker() async {
    final result = await SchedulePickerDialog.show(context);
    if (result == null || !mounted) return;
    ref
        .read(downloadsNotifierProvider.notifier)
        .scheduleFor(
          widget.download.id,
          result.dateTime,
          recurrence: result.recurrence,
        );
  }

  Future<void> _showNoteEditor() async {
    final result = await NoteEditorDialog.show(
      context,
      initialNote: widget.download.userNote,
    );
    if (result == null || !mounted) return;
    final notifier = ref.read(downloadsNotifierProvider.notifier);
    await notifier.saveUserNote(widget.download.id, result);
    if (mounted) {
      AppSnackBar.success(
        context,
        message:
            result.isEmpty
                ? AppLocalizations.notesNoteCleared
                : AppLocalizations.notesNoteSaved,
      );
    }
  }

  Color _getStatusColor() {
    return getDownloadStatusColor(context, widget.download);
  }
}
