import 'package:flutter/material.dart';

import '../../../../core/core.dart';
import '../../../youtube_playlist/domain/entities/playlist_video.dart';

class ChannelVideoItem extends StatefulWidget {
  final PlaylistVideo video;
  final bool isSelected;
  final ValueChanged<bool?>? onSelectionChanged;

  const ChannelVideoItem({
    super.key,
    required this.video,
    required this.isSelected,
    this.onSelectionChanged,
  });

  @override
  State<ChannelVideoItem> createState() => _ChannelVideoItemState();
}

class _ChannelVideoItemState extends State<ChannelVideoItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final video = widget.video;

    final lightSelected = const Color(0xFFEFF6FF);
    final lightBorder = widget.isSelected
        ? const Color(0xFF93C5FD)
        : (_hovered ? const Color(0xFFD1D5DB) : const Color(0xFFE5E7EB));
    final darkBorder = widget.isSelected
        ? AppColors.brand
        : (_hovered ? AppColors.darkMuted : AppColors.darkElevated);

    final cardColor = isDark
        ? (widget.isSelected ? AppColors.darkSurface1 : AppColors.darkBase)
        : (widget.isSelected ? lightSelected : Colors.white);

    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 0, 15, 10),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () =>
              widget.onSelectionChanged?.call(!widget.isSelected ? true : false),
          child: AnimatedContainer(
            duration: AppTransitions.normal,
            transform: Matrix4.translationValues(
              0,
              !isDark && _hovered ? -2 : 0,
              0,
            ),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: isDark ? darkBorder : lightBorder,
                width: 1,
              ),
              boxShadow: isDark
                  ? (_hovered
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: AppOpacity.hover),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null)
                  : (_hovered
                      ? const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 16,
                            offset: Offset(0, 6),
                          ),
                        ]
                      : const [
                          BoxShadow(
                            color: Color(0x0A000000),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ]),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.smMd),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildThumbnail(video, isDark),
                  const SizedBox(width: AppSpacing.smMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          video.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.fileName.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                            color: isDark ? Colors.white : const Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          _buildMetadata(video),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.metadata.copyWith(
                            color: isDark
                                ? AppColors.darkMetaText
                                : const Color(0xFF6B7280),
                          ),
                        ),
                        if (video.formattedDuration.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.sm),
                          _buildDurationChip(isDark, video.formattedDuration),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: _buildCheckbox(isDark),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(PlaylistVideo video, bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 160,
        height: 90,
        child: video.highQualityThumbnail != null
            ? Image.network(
                video.highQualityThumbnail!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildThumbnailPlaceholder(isDark),
              )
            : _buildThumbnailPlaceholder(isDark),
      ),
    );
  }

  Widget _buildDurationChip(bool isDark, String duration) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface1 : const Color(0xFFF5F6F8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark ? AppColors.darkElevated : const Color(0xFFE5E7EB),
        ),
      ),
      child: Text(
        duration,
        style: AppTypography.mini.copyWith(
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : const Color(0xFF374151),
        ),
      ),
    );
  }

  Widget _buildCheckbox(bool isDark) {
    return AnimatedContainer(
      duration: AppTransitions.fast,
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: widget.isSelected ? AppColors.brand : Colors.transparent,
        border: Border.all(
          color: widget.isSelected
              ? AppColors.brand
              : (isDark ? AppColors.darkMuted : const Color(0xFFD1D5DB)),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: widget.isSelected
          ? const Icon(
              Icons.check,
              size: 14,
              color: Colors.white,
            )
          : null,
    );
  }

  String _buildMetadata(PlaylistVideo video) {
    final parts = <String>[];
    if (video.formattedViewCount.isNotEmpty) {
      parts.add(video.formattedViewCount);
    }
    if (video.uploadDate != null && video.uploadDate!.isNotEmpty) {
      parts.add(video.uploadDate!);
    }
    return parts.isEmpty ? 'YouTube video' : parts.join(' · ');
  }

  Widget _buildThumbnailPlaceholder(bool isDark) {
    return Container(
      color: isDark ? AppColors.darkSurface1 : const Color(0xFFF3F4F6),
      alignment: Alignment.center,
      child: Icon(
        Icons.play_circle_outline_rounded,
        size: 34,
        color: isDark ? AppColors.darkMuted : const Color(0xFF9CA3AF),
      ),
    );
  }
}
