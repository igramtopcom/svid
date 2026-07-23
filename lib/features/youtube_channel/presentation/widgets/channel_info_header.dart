import 'package:flutter/material.dart';

import '../../../../core/core.dart';
import '../../domain/entities/channel_info.dart';

/// Subject Profile — Nocturne Cinematic "The Dossier" surveillance style
/// Design ref: Stitch screen aeb19b1031ea45b4b26f3cfbf57f0cc6
class ChannelInfoHeader extends StatefulWidget {
  final ChannelInfo channel;

  const ChannelInfoHeader({
    super.key,
    required this.channel,
  });

  @override
  State<ChannelInfoHeader> createState() => _ChannelInfoHeaderState();
}

class _ChannelInfoHeaderState extends State<ChannelInfoHeader> {
  bool _avatarHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ch = widget.channel;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xs,
        AppSpacing.xl,
        AppSpacing.mdLg,
      ),
      color: isDark ? AppColors.darkBg : AppColors.lightSurface2,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar with wine-red glow halo
          MouseRegion(
            onEnter: (_) => setState(() => _avatarHovered = true),
            onExit: (_) => setState(() => _avatarHovered = false),
            child: SizedBox(
              width: 88,
              height: 88,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Wine-red ambient glow behind avatar
                  if (isDark)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.brand.withValues(
                              alpha: _avatarHovered ? 0.35 : 0.15,
                            ),
                            blurRadius: _avatarHovered ? 30 : 20,
                          ),
                        ],
                      ),
                    ),
                  // Avatar — grayscale noir filter, color on hover
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    width: 80,
                    height: 80,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(40),
                      child: ColorFiltered(
                        colorFilter: isDark && !_avatarHovered
                            ? const ColorFilter.matrix(<double>[
                                0.33, 0.33, 0.33, 0, 0,
                                0.33, 0.33, 0.33, 0, 0,
                                0.33, 0.33, 0.33, 0, 0,
                                0, 0, 0, 1, 0,
                              ])
                            : const ColorFilter.mode(
                                Colors.transparent, BlendMode.multiply),
                        child: ch.highQualityThumbnail != null
                            ? Image.network(
                                ch.highQualityThumbnail!,
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _buildAvatarPlaceholder(isDark),
                              )
                            : _buildAvatarPlaceholder(isDark),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.mdLg),

          // Channel info column
          Expanded(
            child: Transform.translate(
              offset: const Offset(0, -4),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              mainAxisSize: MainAxisSize.max,
              children: [
                // Channel name — bold, tight tracking
                Text(
                  ch.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.appBarTitle.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: isDark
                        ? AppColors.darkLightText
                        : AppColors.darkSurface1,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                // Handle — rose-pink monospace
                if (ch.channelHandle != null)
                  Text(
                    ch.channelHandle!,
                    style: AppTypography.metadata.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? BrandConfig.current.colors.gradientTail
                          : AppColors.brand.withValues(alpha: AppOpacity.nearOpaque),
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                // Stats — surveillance bracket format
                Text(
                  _buildStatsText(ch),
                  style: AppTypography.compact.copyWith(
                    fontFamily: 'monospace',
                    letterSpacing: 1.5,
                    color: isDark
                        ? AppColors.darkMetaText.withValues(alpha: AppOpacity.medium)
                        : AppColors.lightMetaText,
                  ),
                ),
              ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _buildStatsText(ChannelInfo ch) {
    final parts = <String>[];
    if (ch.formattedVideoCount.isNotEmpty) {
      parts.add(ch.formattedVideoCount.toUpperCase());
    }
    if (ch.formattedSubscriberCount.isNotEmpty) {
      parts.add(ch.formattedSubscriberCount.toUpperCase());
    }
    if (parts.isEmpty) return '[-- VIDEOS \u00b7 -- SUBSCRIBERS]';
    return '[${parts.join(' \u00b7 ')}]';
  }

  Widget _buildAvatarPlaceholder(bool isDark) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkElevated : AppColors.lightSurface3,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.person_outline,
        size: 36,
        color: isDark ? AppColors.darkMetaText : AppColors.lightMetaText,
      ),
    );
  }
}
