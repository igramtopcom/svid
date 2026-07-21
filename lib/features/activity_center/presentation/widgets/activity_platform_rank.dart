import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../providers/activity_center_providers.dart';

/// Top 5 platforms ranked by download count with horizontal bar indicators.
class ActivityPlatformRank extends ConsumerWidget {
  const ActivityPlatformRank({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final platformData = ref.watch(platformDistributionProvider);
    final borderColor =
        isDark
            ? AppColors.homeDarkBorderStrong
            : AppColors.border(context).withValues(alpha: 0.72);

    if (platformData.isEmpty) {
      return _buildEmpty(context, isDark);
    }

    // Take top 5
    final entries = platformData.entries.take(5).toList();
    final maxCount = entries.first.value;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.smMd),
      decoration: BoxDecoration(
        color: AppColors.surface2(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: borderColor),
        boxShadow:
            isDark
                ? null
                : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: AppOpacity.divider),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ],
      ),
      child: Column(
        children: [
          for (int i = 0; i < entries.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.smMd),
            _PlatformRow(
              rank: i + 1,
              platform: entries[i].key,
              count: entries[i].value,
              maxCount: maxCount,
              isDark: isDark,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, bool isDark) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface2(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color:
              isDark
                  ? AppColors.homeDarkBorderStrong
                  : AppColors.border(context).withValues(alpha: 0.72),
        ),
      ),
      child: Center(
        child: Text(
          AppLocalizations.activityCenterNoDownloads,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(
              alpha: AppOpacity.scrim,
            ),
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

class _PlatformRow extends StatelessWidget {
  final int rank;
  final String platform;
  final int count;
  final int maxCount;
  final bool isDark;

  const _PlatformRow({
    required this.rank,
    required this.platform,
    required this.count,
    required this.maxCount,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final platformColor = _platformColor(platform);
    final barFraction = maxCount > 0 ? count / maxCount : 0.0;

    return Row(
      children: [
        // Rank number
        SizedBox(
          width: 18,
          child: Text(
            '$rank',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              color:
                  rank <= 3
                      ? AppColors.brand
                      : theme.colorScheme.onSurface.withValues(
                        alpha: AppOpacity.medium,
                      ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),

        // Platform name
        SizedBox(
          width: 72,
          child: Text(
            _displayName(platform),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),

        // Horizontal bar
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final barWidth = constraints.maxWidth * barFraction;
              return Stack(
                children: [
                  Container(
                    height: 12,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: AppOpacity.divider,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    width: math.max(barWidth, 0.0),
                    height: 12,
                    decoration: BoxDecoration(
                      color: platformColor.withValues(alpha: AppOpacity.strong),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(width: AppSpacing.sm),

        // Count
        SizedBox(
          width: 28,
          child: Text(
            '$count',
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 11,
              color: theme.colorScheme.onSurface.withValues(
                alpha: AppOpacity.secondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Capitalize and clean up platform name for display.
  String _displayName(String platform) {
    if (platform.isEmpty || platform == 'unknown' || platform == 'Other') {
      return AppLocalizations.activityCenterOther;
    }
    // Capitalize first letter
    return platform[0].toUpperCase() + platform.substring(1);
  }

  Color _platformColor(String platform) {
    final p = platform.toLowerCase();
    if (p.contains('youtube')) return const Color(0xFFFF0000);
    if (p.contains('tiktok')) return const Color(0xFF000000);
    if (p.contains('instagram')) return const Color(0xFFE1306C);
    if (p.contains('twitter') || p.contains('x.com')) {
      return const Color(0xFF1DA1F2);
    }
    if (p.contains('reddit')) return const Color(0xFFFF4500);
    if (p.contains('facebook')) return const Color(0xFF1877F2);
    if (p.contains('vimeo')) return const Color(0xFF1AB7EA);
    if (p.contains('soundcloud')) return const Color(0xFFFF5500);
    // Fallback: surfaceVariant-ish
    return AppColors.statusQueued;
  }
}
