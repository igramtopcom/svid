import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../../downloads/domain/entities/download_entity.dart';
import '../../../downloads/domain/entities/download_status.dart';
import '../../../downloads/domain/services/download_archive_service.dart';
import '../../../downloads/presentation/providers/downloads_notifier.dart';
import '../../../home/presentation/widgets/download_list_helpers.dart';
import '../../domain/entities/youtube_search_result.dart';
import 'video_preview_dialog.dart';

/// Individual YouTube search / trending result item.
///
/// Beyond Download it offers an in-app **Preview** (mini-player) and — once a
/// download for this video exists — shows its live progress inline and, on
/// completion, an **Open folder** action. This means the user never has to
/// switch to the Home tab to see what happened to a video they downloaded here.
class YouTubeSearchResultItem extends ConsumerStatefulWidget {
  final YouTubeSearchResult video;
  final VoidCallback? onTap;

  /// Called when the download button is tapped — does NOT close the search view.
  final VoidCallback? onDownload;

  const YouTubeSearchResultItem({
    super.key,
    required this.video,
    this.onTap,
    this.onDownload,
  });

  @override
  ConsumerState<YouTubeSearchResultItem> createState() =>
      _YouTubeSearchResultItemState();
}

class _YouTubeSearchResultItemState
    extends ConsumerState<YouTubeSearchResultItem> {
  bool _isHovered = false;

  /// The most recent download whose URL / video-id matches this result, or null.
  DownloadEntity? _matchDownload(List<DownloadEntity> downloads) {
    final video = widget.video;
    if (video.isChannel) return null;
    final url = video.url;
    final vid = video.id;
    final matches =
        downloads.where((d) {
          if (UrlNormalizer.same(d.url, url)) return true;
          if (d.sourceUrl.isNotEmpty && UrlNormalizer.same(d.sourceUrl, url)) {
            return true;
          }
          if (vid.length == 11) {
            if (DownloadArchiveService.extractVideoId(d.url) == vid) return true;
            if (d.sourceUrl.isNotEmpty &&
                DownloadArchiveService.extractVideoId(d.sourceUrl) == vid) {
              return true;
            }
          }
          return false;
        }).toList();
    if (matches.isEmpty) return null;
    matches.sort((a, b) => b.id.compareTo(a.id));
    return matches.first;
  }

  void _openPreview() {
    VideoPreviewDialog.show(
      context,
      widget.video,
      onDownload: widget.onDownload ?? widget.onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final video = widget.video;

    // Rebuild only when *this* video's matching download changes.
    final download = ref.watch(
      downloadsNotifierProvider.select((s) => _matchDownload(s.downloads)),
    );

    final showActions =
        !video.isChannel && (widget.onDownload != null || widget.onTap != null);

    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _isHovered = false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color:
              _isHovered
                  ? (isDark
                      ? AppColors.homeDarkCardHover
                      : AppColors.lightSurface2)
                  : (isDark
                      ? AppColors.homeDarkCardBg
                      : AppColors.surface1(context)),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border:
              isDark
                  ? Border.all(
                    color: AppColors.homeDarkBorderStrong,
                    width: 0.5,
                  )
                  : Border.all(color: AppColors.border(context)),
          boxShadow:
              !isDark && _isHovered
                  ? const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ]
                  : null,
        ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 680;
              final tight = constraints.maxWidth < 520;
              final thumbnailWidth =
                  video.isChannel
                      ? (tight ? 48.0 : 56.0)
                      : (tight ? 112.0 : (compact ? 136.0 : 160.0));
              final thumbnailHeight =
                  video.isChannel ? thumbnailWidth : thumbnailWidth * 9 / 16;

              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: tight ? AppSpacing.smMd : AppSpacing.md,
                  vertical: AppSpacing.smMd,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildThumbnail(
                      theme,
                      video,
                      width: thumbnailWidth,
                      height: thumbnailHeight,
                    ),
                    SizedBox(width: tight ? AppSpacing.sm : AppSpacing.md),
                    Expanded(child: _buildVideoInfo(theme, video)),
                    if (showActions)
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.sm),
                        child: _buildActions(
                          context,
                          compact: compact,
                          download: download,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // Actions: Preview + (Download | Progress | Open folder | Retry)
  // ===========================================================================

  Widget _buildActions(
    BuildContext context, {
    required bool compact,
    required DownloadEntity? download,
  }) {
    final Widget primary;
    if (download == null) {
      primary = _downloadButton(context, compact: compact);
    } else if (download.isCompleted) {
      primary = _openFolderButton(context, download, compact: compact);
    } else if (download.isFailed) {
      primary = _retryButton(context, download, compact: compact);
    } else {
      primary = _progressChip(context, download);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _previewButton(context),
        const SizedBox(width: AppSpacing.xs),
        primary,
      ],
    );
  }

  Widget _previewButton(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: _isHovered ? 1.0 : 0.72,
      child: Tooltip(
        message: AppLocalizations.youtubeSearchPreview,
        child: IconButton(
          onPressed: _openPreview,
          icon: const Icon(Icons.play_arrow_rounded, size: 20),
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            foregroundColor:
                isDark ? AppColors.darkLightText : theme.colorScheme.onSurface,
            backgroundColor:
                isDark
                    ? AppColors.homeDarkAppBg
                    : AppColors.surface3(context),
            side: BorderSide(
              color:
                  isDark
                      ? AppColors.homeDarkBorderStrong
                      : AppColors.border(context),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
          ),
        ),
      ),
    );
  }

  Widget _downloadButton(BuildContext context, {required bool compact}) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: _isHovered ? 1.0 : 0.82,
      child:
          compact
              ? Tooltip(
                message: AppLocalizations.youtubeSearchDownload,
                child: IconButton(
                  onPressed: widget.onDownload ?? widget.onTap,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: AppColors.brand,
                    hoverColor: AppColors.accentHighlight,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                ),
              )
              : FilledButton.icon(
                onPressed: widget.onDownload ?? widget.onTap,
                icon: const Icon(Icons.download, size: 18),
                label: Text(
                  AppLocalizations.youtubeSearchDownload,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.hovered)) {
                      return AppColors.accentHighlight;
                    }
                    return AppColors.brand;
                  }),
                  foregroundColor: const WidgetStatePropertyAll(Colors.white),
                  iconColor: const WidgetStatePropertyAll(Colors.white),
                  overlayColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.hovered)) {
                      return Colors.white.withValues(alpha: AppOpacity.subtle);
                    }
                    return null;
                  }),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(
                      horizontal: AppSpacing.smMd,
                      vertical: AppSpacing.sm,
                    ),
                  ),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                ),
              ),
    );
  }

  /// Live progress while the matching download runs.
  Widget _progressChip(BuildContext context, DownloadEntity download) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = AppColors.accentHighlight;
    final downloading = download.status == DownloadStatus.downloading;
    final percent = download.progressPercentage.round().clamp(0, 100);
    final label =
        downloading ? '$percent%' : download.status.displayLabel;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.smMd),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.14 : 0.10),
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: downloading && download.progress > 0
                  ? download.progress
                  : null,
              color: accent,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// After completion: open the containing folder so the user finds the file.
  Widget _openFolderButton(
    BuildContext context,
    DownloadEntity download, {
    required bool compact,
  }) {
    final green = AppColors.lightStatusCompleted;
    if (compact) {
      return Tooltip(
        message: AppLocalizations.youtubeSearchOpenFolder,
        child: IconButton(
          onPressed: () => openFileLocation(context, ref, download),
          icon: const Icon(Icons.folder_open_rounded, size: 18),
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            foregroundColor: green,
            backgroundColor: green.withValues(alpha: 0.12),
            side: BorderSide(color: green.withValues(alpha: 0.4)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
          ),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: () => openFileLocation(context, ref, download),
      icon: const Icon(Icons.check_circle_rounded, size: 18),
      label: Text(AppLocalizations.youtubeSearchOpenFolder),
      style: OutlinedButton.styleFrom(
        foregroundColor: green,
        side: BorderSide(color: green.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.smMd,
          vertical: AppSpacing.sm,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _retryButton(
    BuildContext context,
    DownloadEntity download, {
    required bool compact,
  }) {
    final red = AppColors.lightStatusFailed;
    void retry() =>
        ref.read(downloadsNotifierProvider.notifier).retryDownload(download.id);
    if (compact) {
      return Tooltip(
        message: AppLocalizations.youtubeSearchRetry,
        child: IconButton(
          onPressed: retry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            foregroundColor: red,
            backgroundColor: red.withValues(alpha: 0.10),
            side: BorderSide(color: red.withValues(alpha: 0.4)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
          ),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: retry,
      icon: const Icon(Icons.refresh_rounded, size: 18),
      label: Text(AppLocalizations.youtubeSearchRetry),
      style: OutlinedButton.styleFrom(
        foregroundColor: red,
        side: BorderSide(color: red.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.smMd,
          vertical: AppSpacing.sm,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildThumbnail(
    ThemeData theme,
    YouTubeSearchResult video, {
    double width = 160,
    double height = 90,
  }) {
    // Channel: circular avatar
    if (video.isChannel) {
      return ClipOval(
        child: SizedBox(
          width: width,
          height: height,
          child:
              video.thumbnail != null
                  ? CachedNetworkImage(
                    imageUrl: video.thumbnail!,
                    fit: BoxFit.cover,
                    memCacheWidth: 112,
                    memCacheHeight: 112,
                    placeholder: (_, __) => _buildChannelPlaceholder(theme),
                    errorWidget:
                        (_, __, ___) => _buildChannelPlaceholder(theme),
                  )
                  : _buildChannelPlaceholder(theme),
        ),
      );
    }

    // Video: rectangular 16:9 thumbnail with a hover play affordance.
    return GestureDetector(
      onTap: _openPreview,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: SizedBox(
                width: width,
                height: height,
                child:
                    video.highQualityThumbnail != null
                        ? CachedNetworkImage(
                          imageUrl: video.highQualityThumbnail!,
                          fit: BoxFit.cover,
                          memCacheWidth: 320,
                          memCacheHeight: 180,
                          placeholder: (_, __) => _buildPlaceholder(theme),
                          errorWidget: (_, __, ___) => _buildPlaceholder(theme),
                        )
                        : _buildPlaceholder(theme),
              ),
            ),
            // Play overlay (appears on hover) — click thumbnail to preview.
            Positioned.fill(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 140),
                opacity: _isHovered ? 1.0 : 0.0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      size: 34,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            // Duration badge
            if (video.formattedDuration.isNotEmpty)
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(
                      alpha: AppOpacity.nearOpaque,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    video.formattedDuration,
                    style: AppTypography.statusBadge.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelPlaceholder(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      color:
          isDark
              ? AppColors.homeDarkCardBg
              : theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.person_rounded,
          size: 24,
          color:
              isDark
                  ? AppColors.homeDarkTextSecondary
                  : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      color:
          isDark
              ? AppColors.homeDarkCardBg
              : theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.play_circle_outline,
          size: 32,
          color:
              isDark
                  ? AppColors.homeDarkTextSecondary.withValues(
                    alpha: AppOpacity.overlay,
                  )
                  : theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: AppOpacity.scrim,
                  ),
        ),
      ),
    );
  }

  Widget _buildVideoInfo(ThemeData theme, YouTubeSearchResult video) {
    final isDark = theme.brightness == Brightness.dark;
    final metaColor =
        isDark
            ? AppColors.homeDarkTextSecondary
            : theme.colorScheme.onSurfaceVariant;
    final ghostColor =
        isDark
            ? AppColors.homeDarkTextSecondary.withValues(
              alpha: AppOpacity.secondary,
            )
            : theme.colorScheme.onSurfaceVariant.withValues(
              alpha: AppOpacity.secondary,
            );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title (max 2 lines)
        Text(
          video.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        // Channel label for channel results
        if (video.isChannel) ...[
          Row(
            children: [
              Icon(Icons.person_rounded, size: 14, color: ghostColor),
              const SizedBox(width: AppSpacing.xs),
              Text(
                AppLocalizations.youtubeSearchChannel,
                style: theme.textTheme.bodySmall?.copyWith(color: metaColor),
              ),
              if (video.formattedViewCount.isNotEmpty)
                Text(
                  ' · ${video.formattedViewCount}',
                  style: theme.textTheme.bodySmall?.copyWith(color: ghostColor),
                ),
            ],
          ),
        ] else ...[
          // Channel name
          if (video.channel != null)
            Text(
              video.channel!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: metaColor),
            ),
          const SizedBox(height: AppSpacing.xxs),
          // Metadata row (views + date)
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (video.formattedViewCount.isNotEmpty) ...[
                Text(
                  video.formattedViewCount,
                  style: theme.textTheme.bodySmall?.copyWith(color: ghostColor),
                ),
                if (video.formattedUploadDate.isNotEmpty)
                  Text(
                    ' · ',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ghostColor,
                    ),
                  ),
              ],
              if (video.formattedUploadDate.isNotEmpty)
                Text(
                  video.formattedUploadDate,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: ghostColor),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
