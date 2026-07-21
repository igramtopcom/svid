import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../providers/activity_center_providers.dart';

/// Circular donut chart showing success rate.
/// Outer ring is a styled CircularProgressIndicator; center shows percentage.
class ActivityDonutChart extends ConsumerWidget {
  const ActivityDonutChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final stats = ref.watch(activityKpiStatsProvider);

    final successColor =
        isDark ? AppColors.successGreen : AppColors.lightStatusCompleted;
    final errorColor =
        isDark ? AppColors.errorRed : AppColors.lightStatusFailed;
    final borderColor =
        isDark
            ? AppColors.homeDarkBorderStrong
            : AppColors.border(context).withValues(alpha: 0.72);

    final total = stats.totalDownloads;
    final successCount =
        total > 0 ? (stats.successRate / 100 * total).round() : 0;
    final failedCount = total > 0 ? total - successCount : 0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
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
          // Donut ring
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Background track
                SizedBox(
                  width: 100,
                  height: 100,
                  child: CircularProgressIndicator(
                    value: 1.0,
                    strokeWidth: 8,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.colorScheme.onSurface.withValues(
                        alpha: AppOpacity.hover,
                      ),
                    ),
                  ),
                ),
                // Success arc
                SizedBox(
                  width: 100,
                  height: 100,
                  child: CircularProgressIndicator(
                    value: stats.successRate / 100,
                    strokeWidth: 8,
                    strokeCap: StrokeCap.round,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.brand),
                  ),
                ),
                // Center percentage
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${stats.successRate.toStringAsFixed(0)}%',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                      ),
                    ),
                    Text(
                      AppLocalizations.activityCenterDonutSuccess,
                      style: AppTypography.mini.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: AppOpacity.medium,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // Legend row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LegendDot(color: successColor),
              const SizedBox(width: AppSpacing.xs),
              Text(
                AppLocalizations.activityCenterLegendSuccess(successCount),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(
                    alpha: AppOpacity.secondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.smMd),
              _LegendDot(color: errorColor),
              const SizedBox(width: AppSpacing.xs),
              Text(
                AppLocalizations.activityCenterLegendFailed(failedCount),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(
                    alpha: AppOpacity.secondary,
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

class _LegendDot extends StatelessWidget {
  final Color color;

  const _LegendDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
