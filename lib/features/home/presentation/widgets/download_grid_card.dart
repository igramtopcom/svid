import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../../core/core.dart';
import '../../../downloads/domain/entities/download_context_menu_action.dart';
import '../../../downloads/domain/entities/download_entity.dart';
import '../../../downloads/domain/entities/download_status.dart';
import '../../../downloads/domain/services/download_context_menu_service.dart';
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

/// Grid card — compact vertical layout for grid view.
class DownloadGridCard extends ConsumerStatefulWidget {
  final DownloadEntity download;
  final List<DownloadEntity>? carouselDownloads;
  final ValueChanged<DownloadEntity>? onRemoveFromPlaylist;
  final ValueChanged<DownloadEntity>? onMovePlaylistItemUp;
  final ValueChanged<DownloadEntity>? onMovePlaylistItemDown;

  const DownloadGridCard({
    super.key,
    required this.download,
    this.carouselDownloads,
    this.onRemoveFromPlaylist,
    this.onMovePlaylistItemUp,
    this.onMovePlaylistItemDown,
  });

  @override
  ConsumerState<DownloadGridCard> createState() => _DownloadGridCardState();
}

class _DownloadGridCardState extends ConsumerState<DownloadGridCard> {
  bool _isHovered = false;

  bool get _isFileMissing {
    final downloadsState = ref.read(downloadsNotifierProvider);
    return downloadsState.isFileMissing(widget.download.id);
  }

  void _onCardTap() {
    seedPlaybackQueue(ref, widget.download);
    ref.read(rightPanelProvider.notifier).showDetail(widget.download);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final isDark = theme.brightness == Brightness.dark;
    final titleText =
        widget.download.displayTitle.trim().isEmpty
            ? widget.download.filenameWithoutExtension
            : widget.download.displayTitle.trim();
    // Nocturne: failed = 40% normally, 100% hover. Cancelled = 30%. Watched = 60%.
    final cardOpacity =
        widget.download.isFailed
            ? (_isHovered ? 1.0 : AppOpacity.medium)
            : widget.download.isCancelled
            ? AppOpacity.scrim
            : 1.0;

    // Home Dark Operator: flat token surface ladder.
    Color cardColor;
    if (widget.download.isActive && isDark) {
      cardColor = AppColors.homeDarkCardActive;
    } else if (_isHovered && isDark) {
      cardColor = AppColors.homeDarkCardHover;
    } else {
      cardColor = isDark ? AppColors.homeDarkCardBg : const Color(0xFFFFFFFF);
    }

    final borderColor =
        isDark
            ? (_isHovered
                ? AppColors.homeDarkBorderStrong
                : AppColors.homeDarkBorderSubtle)
            : cs.outlineVariant.withValues(alpha: _isHovered ? 0.92 : 0.68);

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
          onTap: _onCardTap,
          onDoubleTap:
              widget.download.isCompleted && !_isFileMissing
                  ? () => openPlayerForDownload(
                    context,
                    ref,
                    widget.download,
                    carouselDownloads: widget.carouselDownloads,
                  )
                  : null,
          onSecondaryTapUp:
              (details) => _showContextMenu(details.globalPosition),
          child: AnimatedContainer(
            duration: AppTransitions.normal,
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color:
                    widget.download.isActive && isDark
                        ? AppColors.homeDarkBorderStrong
                        : borderColor,
                width: isDark ? 0.75 : 1,
              ),
              boxShadow:
                  isDark && widget.download.status == DownloadStatus.downloading
                      ? [
                        BoxShadow(
                          color: AppColors.accentHighlight.withValues(
                            alpha: AppOpacity.subtle,
                          ),
                          blurRadius: 24,
                          spreadRadius: -4,
                        ),
                      ]
                      : isDark && _isHovered
                      ? [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: AppOpacity.overlay,
                          ),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                          spreadRadius: -2,
                        ),
                      ]
                      : isDark
                      ? null
                      : _isHovered
                      ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                          spreadRadius: -12,
                        ),
                      ]
                      : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Thumbnail — fills card width, 16:9
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _buildThumbnail(theme),
                  ),

                  // Info section — compact Nocturne
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.smMd,
                        AppSpacing.sm,
                        AppSpacing.smMd,
                        AppSpacing.smMd,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Title with priority badge
                          Row(
                            children: [
                              _buildPriorityBadge(),
                              Expanded(
                                child: Text(
                                  titleText,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color:
                                        widget.download.isFailed
                                            ? (isDark
                                                ? AppColors.darkMetaText
                                                : theme
                                                    .colorScheme
                                                    .onSurfaceVariant)
                                            : (isDark
                                                ? AppColors.darkLightText
                                                : theme.colorScheme.onSurface),
                                    decoration:
                                        widget.download.isFailed
                                            ? TextDecoration.lineThrough
                                            : null,
                                    decorationColor:
                                        isDark
                                            ? AppColors.darkMuted
                                            : theme.colorScheme.onSurface
                                                .withValues(
                                                  alpha: AppOpacity.scrim,
                                                ),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: AppSpacing.xs),

                          _buildStatusLine(theme),

                          // File metadata — size + type (completed) or progress + speed (active)
                          if (widget.download.totalBytes > 0 ||
                              widget.download.isActive) ...[
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              _metadataText(),
                              style: AppTypography.mini.copyWith(
                                color:
                                    widget.download.isActive
                                        ? AppColors.accentHighlight
                                        : (isDark
                                            ? AppColors.darkMetaText
                                            : theme
                                                .colorScheme
                                                .onSurfaceVariant),
                                fontWeight:
                                    widget.download.isActive
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],

                          if (widget.download.isWatched) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Align(
                              alignment: Alignment.centerRight,
                              child: buildWatchedChip(compact: true),
                            ),
                          ],
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

  Widget _buildThumbnail(ThemeData theme) {
    if (widget.download.thumbnail != null) {
      // Base image with state-specific visual treatment
      Widget image = AppCachedImage(
        imageUrl: widget.download.thumbnail,
        width: double.infinity,
        height: double.infinity,
        errorWidget: _buildPlaceholderThumbnail(theme),
      );

      // Apply state-specific filters (Nocturne Cinematic)
      final isFailed = widget.download.isFailed;
      final isCancelled = widget.download.isCancelled;
      final isPaused = widget.download.isPaused;
      if (isFailed || isCancelled) {
        image = ColorFiltered(
          colorFilter: const ColorFilter.mode(
            Colors.grey,
            BlendMode.saturation,
          ),
          child: Opacity(opacity: isFailed ? 0.4 : 0.2, child: image),
        );
      } else if (isPaused) {
        image = Opacity(opacity: 0.6, child: image);
      }

      return Stack(
        fit: StackFit.expand,
        children: [
          image,

          // Platform icon (top-left) — hidden for audio (its play-triangle
          // logo reads as "video"; the audio badge below is the media signal).
          if (widget.download.platform.isNotEmpty &&
              widget.download.platform != 'unknown' &&
              !FileUtils.isAudioFile(widget.download.filename))
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
                  size: 14,
                ),
              ),
            ),

          // Audio badge (top-left) — parity with the list view: flags
          // audio-only files whose album art looks just like a video.
          if (FileUtils.isAudioFile(widget.download.filename))
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.xxs),
                decoration: BoxDecoration(
                  color: AppColors.accentSecondary.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: const Icon(
                  Icons.music_note_rounded,
                  size: 12,
                  color: Colors.white,
                ),
              ),
            ),

          // Failed error overlay — atmospheric crimson vignette
          if (isFailed)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      AppColors.errorRed.withValues(alpha: AppOpacity.subtle),
                      Colors.black.withValues(alpha: AppOpacity.overlay),
                    ],
                    radius: 0.8,
                  ),
                ),
                child: Icon(
                  Icons.error_outline,
                  color: AppColors.errorRed.withValues(
                    alpha: AppOpacity.strong,
                  ),
                  size: 28,
                ),
              ),
            ),

          // Paused overlay
          if (isPaused)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: AppOpacity.medium),
                child: Icon(
                  Icons.pause_rounded,
                  color: Colors.white.withValues(alpha: AppOpacity.secondary),
                  size: 28,
                ),
              ),
            ),

          // Duration overlay
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
                  color: Colors.black.withValues(alpha: AppOpacity.nearOpaque),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Text(
                  widget.download.formattedDuration!,
                  style: AppTypography.compact.copyWith(
                    color: Colors.white,
                    fontWeight: AppTypography.semiBold,
                  ),
                ),
              ),
            ),

          // Active download: progress bar at bottom of thumbnail with crimson glow
          if (widget.download.isActive)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 3,
                color:
                    theme.brightness == Brightness.dark
                        ? AppColors.darkElevated
                        : AppColors.lightSurface3,
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: widget.download.progress.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.brand, AppColors.accentHighlight],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accentHighlight.withValues(
                            alpha: AppOpacity.secondary,
                          ),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Watch progress bar (bottom, YouTube-style red bar)
          if (widget.download.isCompleted) _buildWatchProgressBar(),
          // Preview play overlay — always mounted when state qualifies; opacity-toggled on hover.
          // Conditional mounting on _isHovered triggers mouse_tracker.dart:203 assertion
          // when scroll fetch-more rebuilds the list during pointer dispatch.
          if (widget.download.status == DownloadStatus.downloading &&
              widget.download.progress >= 0.1 &&
              (FileUtils.isVideoFile(widget.download.filename) ||
                  FileUtils.isAudioFile(widget.download.filename)))
            Positioned.fill(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: _isHovered ? 1.0 : 0.0,
                child: IgnorePointer(
                  ignoring: !_isHovered,
                  child: GestureDetector(
                    onTap:
                        () => openPreviewForDownload(context, widget.download),
                    child: Container(
                      color: Colors.black.withValues(alpha: AppOpacity.scrim),
                      child: const Center(
                        child: Icon(
                          Icons.play_circle_outline_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Hover quick actions — always mounted when actions exist; opacity-toggled.
          if (_hoverActions().isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: _isHovered ? 1.0 : 0.0,
                child: IgnorePointer(
                  ignoring: !_isHovered,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: AppOpacity.strong),
                        ],
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: _hoverActions(),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }
    return _buildPlaceholderThumbnail(theme);
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

  Widget _buildPlaceholderThumbnail(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final fileColor = getFileTypeColor(context, widget.download);
    final ext =
        widget.download.fileExtension.replaceFirst('.', '').toUpperCase();
    return Container(
      decoration: BoxDecoration(
        color:
            isDark
                ? fileColor.withValues(alpha: AppOpacity.pressed)
                : fileColor.withValues(alpha: AppOpacity.hover),
        gradient:
            isDark
                ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    fileColor.withValues(alpha: AppOpacity.subtle),
                    fileColor.withValues(alpha: AppOpacity.divider),
                  ],
                )
                : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            getFileIcon(widget.download),
            size: 32,
            color: fileColor.withValues(alpha: AppOpacity.secondary),
          ),
          if (ext.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: fileColor.withValues(alpha: AppOpacity.subtle),
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Text(
                ext,
                style: AppTypography.mini.copyWith(
                  fontWeight: FontWeight.w700,
                  color: fileColor.withValues(alpha: AppOpacity.strong),
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Priority badge — shows smart-boost OR manual priority (grid card variant).
  Widget _buildPriorityBadge() {
    final downloadsState = ref.watch(downloadsNotifierProvider);
    final isBoosted = downloadsState.isSmartBoosted(widget.download.id);
    final manualPriority = DownloadPriority.fromInt(widget.download.priority);

    if (isBoosted) {
      return const Padding(
        padding: EdgeInsets.only(right: AppSpacing.xs),
        child: PriorityBadge(isHigh: true, isSmartBoosted: true),
      );
    }
    if (manualPriority == DownloadPriority.high) {
      return const Padding(
        padding: EdgeInsets.only(right: AppSpacing.xs),
        child: PriorityBadge(isHigh: true),
      );
    }
    if (manualPriority == DownloadPriority.low) {
      return const Padding(
        padding: EdgeInsets.only(right: AppSpacing.xs),
        child: PriorityBadge(isLow: true),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildStatusLine(ThemeData theme) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildStatusChip(theme),
        if (_isFileMissing) buildFileMissingBadge(context),
      ],
    );
  }

  Widget _buildStatusChip(ThemeData theme) {
    final color = _getStatusColor(theme);
    final containerColor = getDownloadStatusContainerColor(
      context,
      widget.download,
    );
    final isDark = theme.brightness == Brightness.dark;
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
                      size: 13,
                      color: color,
                    )
                    : Icon(
                      getDownloadStatusIcon(widget.download),
                      key: ValueKey(widget.download.status),
                      size: 12,
                      color: color,
                    ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: AnimatedSwitcher(
              duration: AppTransitions.normal,
              child: Text(
                widget.download.status.displayLabel,
                key: ValueKey(widget.download.status.displayLabel),
                style: AppTypography.mini.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Metadata text: file size + type for completed, progress + speed for active.
  String _metadataText() {
    final d = widget.download;
    if (d.isActive) {
      final pct = '${(d.progress * 100).toStringAsFixed(1)}%';
      return d.speed > 0 ? '$pct · ${Formatters.formatSpeed(d.speed)}' : pct;
    }
    final size = FileUtils.formatBytes(d.totalBytes);
    final ext = d.fileExtension.replaceFirst('.', '').toUpperCase();
    return ext.isNotEmpty ? '$size · $ext' : size;
  }

  /// Hover action buttons — context-aware per download state.
  List<Widget> _hoverActions() {
    final d = widget.download;
    if (d.isCompleted && !_isFileMissing) {
      return [
        _hoverActionButton(
          Icons.play_arrow_rounded,
          () => openPlayerForDownload(
            context,
            ref,
            d,
            carouselDownloads: widget.carouselDownloads,
          ),
        ),
      ];
    }
    if (d.isPaused) {
      return [
        _hoverActionButton(
          Icons.play_arrow_rounded,
          () =>
              ref.read(downloadsNotifierProvider.notifier).resumeDownload(d.id),
        ),
      ];
    }
    if (d.isFailed) {
      return [
        _hoverActionButton(
          Icons.refresh_rounded,
          () =>
              ref.read(downloadsNotifierProvider.notifier).retryDownload(d.id),
        ),
      ];
    }
    return [];
  }

  Widget _hoverActionButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: AppOpacity.subtle),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: Colors.white.withValues(alpha: AppOpacity.quarter),
            width: 0.5,
          ),
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }

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
      if ((action == DownloadContextMenuAction.copyUrl ||
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
        openPlayerForDownload(
          context,
          ref,
          widget.download,
          carouselDownloads: widget.carouselDownloads,
        );
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
      case DownloadContextMenuAction.markUnwatched:
        ref
            .read(watchProgressServiceProvider)
            .markAsUnwatched(widget.download.id);
      case DownloadContextMenuAction.delete:
        showDownloadDeleteDialog(context, ref, widget.download);
      case DownloadContextMenuAction.playNext:
        ref.read(playbackQueueProvider.notifier).playNext(widget.download);
      case DownloadContextMenuAction.addToQueue:
        ref.read(playbackQueueProvider.notifier).addToQueue(widget.download);
      case DownloadContextMenuAction.watchNow:
        openPreviewForDownload(context, widget.download);
      case DownloadContextMenuAction.scheduleFor:
        _guardedSchedulePicker();
      case DownloadContextMenuAction.redownload:
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

  Color _getStatusColor(ThemeData theme) {
    return getDownloadStatusColor(context, widget.download);
  }
}
