import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../core/core.dart';
import '../../domain/entities/youtube_search_result.dart';

/// Individual YouTube search result item
class YouTubeSearchResultItem extends StatefulWidget {
  final YouTubeSearchResult video;
  final VoidCallback? onTap;

  /// Called when the download button is tapped — does NOT close the search dialog
  final VoidCallback? onDownload;

  const YouTubeSearchResultItem({
    super.key,
    required this.video,
    this.onTap,
    this.onDownload,
  });

  @override
  State<YouTubeSearchResultItem> createState() =>
      _YouTubeSearchResultItemState();
}

class _YouTubeSearchResultItemState extends State<YouTubeSearchResultItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final video = widget.video;

    final showDownloadButton =
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
                    if (showDownloadButton)
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.sm),
                        child: _buildDownloadAction(context, compact: compact),
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

  Widget _buildDownloadAction(BuildContext context, {required bool compact}) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: _isHovered ? 1.0 : 0.76,
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

    // Video: rectangular 16:9 thumbnail
    return Stack(
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
                color: Colors.black.withValues(alpha: AppOpacity.nearOpaque),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                video.formattedDuration,
                style: AppTypography.statusBadge.copyWith(color: Colors.white),
              ),
            ),
          ),
      ],
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
