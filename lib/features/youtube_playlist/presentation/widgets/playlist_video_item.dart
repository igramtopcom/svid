import 'package:flutter/material.dart';
import '../../../../core/core.dart';
import '../../domain/entities/playlist_video.dart';

/// Video item with checkbox for selection
class PlaylistVideoItem extends StatelessWidget {
  final PlaylistVideo video;
  final bool isSelected;
  final ValueChanged<bool>? onSelectionChanged;

  const PlaylistVideoItem({
    super.key,
    required this.video,
    this.isSelected = false,
    this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isSelected
          ? (isDark
              ? AppColors.brand.withValues(alpha: AppOpacity.pressed)
              : theme.colorScheme.primaryContainer.withValues(alpha: AppOpacity.scrim))
          : Colors.transparent,
      child: InkWell(
        onTap: () => onSelectionChanged?.call(!isSelected),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Checkbox
              Checkbox(
                value: isSelected,
                onChanged: (value) => onSelectionChanged?.call(value ?? false),
                activeColor: AppColors.accentHighlight,
                checkColor: AppColors.darkLightText,
                side: isDark
                    ? BorderSide(color: AppColors.darkMuted, width: 1.5)
                    : null,
              ),

              const SizedBox(width: AppSpacing.smMd),

              // Thumbnail
              _buildThumbnail(theme, isDark),

              const SizedBox(width: AppSpacing.md),

              // Info
              Expanded(child: _buildVideoInfo(theme, isDark)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(ThemeData theme, bool isDark) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: SizedBox(
            width: AppConstants.videoThumbnailWidth,
            height: AppConstants.videoThumbnailHeight,
            child: video.highQualityThumbnail != null
                ? Image.network(
                    video.highQualityThumbnail!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildPlaceholder(theme),
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
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: AppOpacity.nearOpaque),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                video.formattedDuration,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      color: isDark ? AppColors.darkSurface1 : AppColors.lightSurface2,
      child: Center(
        child: Icon(
          Icons.play_circle_outline,
          size: 40,
          color: isDark ? AppColors.darkMetaText : theme.colorScheme.onSurface.withValues(alpha: AppOpacity.scrim),
        ),
      ),
    );
  }

  Widget _buildVideoInfo(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        Text(
          video.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.darkLightText : null,
          ),
        ),

        const SizedBox(height: AppSpacing.xs),

        // Channel
        if (video.channel != null)
          Text(
            video.channel!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark ? AppColors.darkMetaText : theme.colorScheme.onSurfaceVariant,
            ),
          ),

        const SizedBox(height: AppSpacing.xxs),

        // Views
        if (video.formattedViewCount.isNotEmpty)
          Text(
            video.formattedViewCount,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark ? AppColors.darkMetaText : theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
