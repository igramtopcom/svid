import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../providers/activity_center_providers.dart';

/// 28-day activity heatmap (4 rows x 7 cols).
/// Cell color intensity reflects download count for that day.
class ActivityHeatmap extends ConsumerWidget {
  const ActivityHeatmap({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final heatmapData = ref.watch(activityHeatmapProvider);
    final borderColor =
        isDark
            ? AppColors.homeDarkBorderStrong
            : AppColors.border(context).withValues(alpha: 0.72);

    // Build ordered list of 28 days (oldest first → newest last)
    final now = DateTime.now();
    final days = <DateTime>[];
    for (int i = 27; i >= 0; i--) {
      final day = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: i));
      days.add(day);
    }

    // Find max for intensity scaling
    final maxCount = heatmapData.values.fold<int>(
      0,
      (max, count) => count > max ? count : max,
    );
    final totalCount = heatmapData.values.fold<int>(0, (sum, c) => sum + c);

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Text(
                AppLocalizations.activityCenterActivity28Days,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text(
                AppLocalizations.activityCenterTotalCount(totalCount),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(
                    alpha: AppOpacity.medium,
                  ),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.smMd),

          // Day label row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children:
                [
                      AppLocalizations.activityCenterDayMon,
                      AppLocalizations.activityCenterDayTue,
                      AppLocalizations.activityCenterDayWed,
                      AppLocalizations.activityCenterDayThu,
                      AppLocalizations.activityCenterDayFri,
                      AppLocalizations.activityCenterDaySat,
                      AppLocalizations.activityCenterDaySun,
                    ]
                    .map(
                      (d) => SizedBox(
                        width: 20,
                        child: Text(
                          d,
                          textAlign: TextAlign.center,
                          style: AppTypography.mini.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: AppOpacity.scrim,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: AppSpacing.xs),

          // 4 rows x 7 cols grid
          for (int row = 0; row < 4; row++) ...[
            if (row > 0) const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (int col = 0; col < 7; col++)
                  _HeatmapCell(
                    count: heatmapData[days[row * 7 + col]] ?? 0,
                    maxCount: maxCount,
                    isDark: isDark,
                  ),
              ],
            ),
          ],

          const SizedBox(height: AppSpacing.sm),

          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                AppLocalizations.activityCenterHeatmapLess,
                style: AppTypography.mini.copyWith(
                  color: theme.colorScheme.onSurface.withValues(
                    alpha: AppOpacity.scrim,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _HeatmapCell(count: 0, maxCount: 1, isDark: isDark, size: 12),
              const SizedBox(width: AppSpacing.xxs),
              _HeatmapCell(count: 1, maxCount: 4, isDark: isDark, size: 12),
              const SizedBox(width: AppSpacing.xxs),
              _HeatmapCell(count: 2, maxCount: 4, isDark: isDark, size: 12),
              const SizedBox(width: AppSpacing.xxs),
              _HeatmapCell(count: 4, maxCount: 4, isDark: isDark, size: 12),
              const SizedBox(width: AppSpacing.xs),
              Text(
                AppLocalizations.activityCenterHeatmapMore,
                style: AppTypography.mini.copyWith(
                  color: theme.colorScheme.onSurface.withValues(
                    alpha: AppOpacity.scrim,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Single heatmap cell with intensity-based coloring.
class _HeatmapCell extends StatelessWidget {
  final int count;
  final int maxCount;
  final bool isDark;
  final double size;

  const _HeatmapCell({
    required this.count,
    required this.maxCount,
    required this.isDark,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    if (count == 0) {
      color = isDark ? AppColors.darkSurface1 : AppColors.lightSurface3;
    } else if (maxCount <= 0) {
      color = AppColors.brand.withValues(alpha: AppOpacity.quarter);
    } else {
      final intensity = (count / maxCount).clamp(0.0, 1.0);
      if (intensity <= 0.25) {
        color = AppColors.brand.withValues(alpha: AppOpacity.quarter);
      } else if (intensity <= 0.5) {
        color = AppColors.brand.withValues(alpha: AppOpacity.medium);
      } else if (intensity <= 0.75) {
        color = AppColors.brand.withValues(alpha: AppOpacity.secondary);
      } else {
        color = AppColors.brand;
      }
    }

    return Tooltip(
      message:
          count > 0
              ? AppLocalizations.activityCenterHeatmapDownload(count)
              : AppLocalizations.activityCenterHeatmapNoActivity,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
    );
  }
}
