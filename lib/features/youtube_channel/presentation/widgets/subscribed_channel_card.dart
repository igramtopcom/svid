import 'package:flutter/material.dart';

import '../../../../core/core.dart';
import '../../domain/entities/subscribed_channel.dart';

/// Subscription list item styled to match Home list cards more closely.
class SubscribedChannelCard extends StatefulWidget {
  final SubscribedChannel subscription;
  final VoidCallback onTap;

  const SubscribedChannelCard({
    super.key,
    required this.subscription,
    required this.onTap,
  });

  @override
  State<SubscribedChannelCard> createState() => _SubscribedChannelCardState();
}

class _SubscribedChannelCardState extends State<SubscribedChannelCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sub = widget.subscription;
    final isPending = sub.lastChecked == null;
    final isNew = sub.hasNewVideos;
    final cardColor =
        isDark
            ? (_hovered
                ? AppColors.homeDarkCardHover
                : AppColors.homeDarkCardBg)
            : (_hovered
                ? AppColors.surface2(context)
                : AppColors.surface1(context));

    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovered = false);
      },
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 180),
          offset: !isDark && _hovered ? const Offset(0, -0.015) : Offset.zero,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border:
                  isDark
                      ? Border.all(
                        color:
                            _hovered
                                ? AppColors.homeDarkBorderStrong
                                : AppColors.homeDarkBorderSubtle,
                        width: 1,
                      )
                      : Border.all(color: AppColors.border(context), width: 1),
              boxShadow:
                  isDark
                      ? (_hovered
                          ? [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: AppOpacity.hover,
                              ),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ]
                          : null)
                      : (_hovered
                          ? const [
                            BoxShadow(
                              color: Color.fromRGBO(0, 0, 0, 0.08),
                              blurRadius: 16,
                              offset: Offset(0, 6),
                            ),
                          ]
                          : const [
                            BoxShadow(
                              color: Color.fromRGBO(0, 0, 0, 0.05),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ]),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 2,
                  height: 44,
                  margin: const EdgeInsets.only(right: AppSpacing.md),
                  decoration: BoxDecoration(
                    color:
                        isNew
                            ? (isDark
                                ? AppColors.brand
                                : AppColors.brand.withValues(
                                  alpha: AppOpacity.nearOpaque,
                                ))
                            : (isDark
                                ? AppColors.homeDarkBorderStrong
                                : AppColors.lightBorder.withValues(
                                  alpha: AppOpacity.scrim,
                                )),
                    borderRadius: BorderRadius.circular(1),
                    boxShadow:
                        isNew && isDark
                            ? [
                              BoxShadow(
                                color: AppColors.accentHighlight.withValues(
                                  alpha: AppOpacity.medium,
                                ),
                                blurRadius: 8,
                              ),
                            ]
                            : null,
                  ),
                ),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 500),
                      opacity: isPending && !_hovered ? 0.4 : 1.0,
                      child: ColorFiltered(
                        colorFilter:
                            isDark && !_hovered
                                ? const ColorFilter.matrix(<double>[
                                  0.33,
                                  0.33,
                                  0.33,
                                  0,
                                  0,
                                  0.33,
                                  0.33,
                                  0.33,
                                  0,
                                  0,
                                  0.33,
                                  0.33,
                                  0.33,
                                  0,
                                  0,
                                  0,
                                  0,
                                  0,
                                  1,
                                  0,
                                ])
                                : const ColorFilter.mode(
                                  Colors.transparent,
                                  BlendMode.multiply,
                                ),
                        child:
                            sub.highQualityThumbnail != null
                                ? Image.network(
                                  sub.highQualityThumbnail!,
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                  errorBuilder:
                                      (_, __, ___) =>
                                          _buildAvatarPlaceholder(isDark),
                                )
                                : _buildAvatarPlaceholder(isDark),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 500),
                    opacity: isPending && !_hovered ? 0.4 : 1.0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          sub.channelHandle?.isNotEmpty == true
                              ? sub.channelHandle!
                              : sub.channelName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.fileName.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                            color:
                                isDark
                                    ? AppColors.darkLightText
                                    : AppColors.darkSurface1,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          _buildStatsText(sub),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.compact.copyWith(
                            fontFamily: 'monospace',
                            letterSpacing: 0,
                            color:
                                isDark
                                    ? AppColors.homeDarkTextSecondary
                                    : AppColors.lightMetaText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.smMd),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 116),
                  child: _buildStatusBadge(sub, isDark),
                ),
                const SizedBox(width: AppSpacing.smMd),
                AnimatedPadding(
                  duration: const Duration(milliseconds: 300),
                  padding: EdgeInsets.only(left: _hovered ? 4 : 0),
                  child: Icon(
                    Icons.chevron_right,
                    size: 16,
                    color:
                        isDark
                            ? AppColors.homeDarkTextSecondary
                            : AppColors.lightMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _buildStatsText(SubscribedChannel sub) {
    final parts = <String>[];
    if (sub.formattedSubscriberCount.isNotEmpty) {
      parts.add(sub.formattedSubscriberCount);
    }
    if (sub.formattedVideoCount.isNotEmpty) {
      parts.add(sub.formattedVideoCount);
    }
    if (parts.isEmpty) return '-- subs · -- videos';
    return parts.join(' · ');
  }

  Widget _buildStatusBadge(SubscribedChannel sub, bool isDark) {
    if (sub.hasNewVideos) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.brand,
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        child: Text(
          'New',
          style: AppTypography.mini.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
            color: isDark ? const Color(0xFFFFDADA) : Colors.white,
          ),
        ),
      );
    }

    if (sub.lastChecked != null) {
      return Text(
        sub.lastCheckedDisplay,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.compact.copyWith(
          fontFamily: 'monospace',
          letterSpacing: 0,
          color:
              isDark
                  ? AppColors.homeDarkTextSecondary
                  : AppColors.lightMetaText,
        ),
      );
    }

    return Text(
      'Pending',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.compact.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: isDark ? AppColors.homeDarkTextMuted : AppColors.lightMuted,
      ),
    );
  }

  Widget _buildAvatarPlaceholder(bool isDark) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isDark ? AppColors.homeDarkCardHover : AppColors.lightSurface3,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.person_outline,
        size: 20,
        color: isDark ? AppColors.homeDarkTextMuted : AppColors.lightMuted,
      ),
    );
  }
}
