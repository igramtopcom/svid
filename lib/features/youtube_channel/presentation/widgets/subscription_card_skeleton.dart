import 'package:flutter/material.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/shimmer.dart';

/// Skeleton matching Nocturne Cinematic SubscribedChannelCard layout
/// Layout: [2px indicator] [Circle 44px] [Name + Stats] [Badge] [Chevron]
class SubscriptionCardSkeleton extends StatelessWidget {
  const SubscriptionCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
      child: Row(
        children: [
          // Left indicator bar
          Container(
            width: 2,
            height: 44,
            margin: const EdgeInsets.only(right: AppSpacing.md),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkMuted.withValues(alpha: AppOpacity.pressed)
                  : AppColors.lightBorder.withValues(alpha: AppOpacity.quarter),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          // Avatar circle
          const SkeletonCircle(size: 44),
          const SizedBox(width: AppSpacing.md),
          // Info lines
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SkeletonLine(height: 14, width: 120),
                const SizedBox(height: AppSpacing.sm),
                SkeletonLine(height: 10, width: 160),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.smMd),
          // Status badge placeholder
          SkeletonLine(height: 10, width: 48),
        ],
      ),
    );
  }
}
