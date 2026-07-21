import 'package:flutter/material.dart';

import '../../../../core/core.dart';
import 'activity_heatmap.dart';
import 'activity_donut_chart.dart';
import 'activity_format_bars.dart';
import 'activity_platform_rank.dart';

/// Right-side analytics panel (340px wide, border-left).
/// Vertical scroll with heatmap, donut chart, format bars, platform ranking.
class ActivityAnalyticsPanel extends StatelessWidget {
  const ActivityAnalyticsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section: Heatmap
          _SectionLabel(
            label: AppLocalizations.activityCenterSectionDownloadActivity,
          ),
          const SizedBox(height: AppSpacing.sm),
          const ActivityHeatmap(),
          const SizedBox(height: AppSpacing.lg),

          // Section: Success donut
          _SectionLabel(
            label: AppLocalizations.activityCenterSectionSuccessRate,
          ),
          const SizedBox(height: AppSpacing.sm),
          const ActivityDonutChart(),
          const SizedBox(height: AppSpacing.lg),

          // Section: Format distribution
          _SectionLabel(
            label: AppLocalizations.activityCenterSectionFormatDistribution,
          ),
          const SizedBox(height: AppSpacing.sm),
          const ActivityFormatBars(),
          const SizedBox(height: AppSpacing.lg),

          // Section: Platform ranking
          _SectionLabel(
            label: AppLocalizations.activityCenterSectionTopPlatforms,
          ),
          const SizedBox(height: AppSpacing.sm),
          const ActivityPlatformRank(),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurface.withValues(alpha: AppOpacity.medium),
        fontWeight: FontWeight.w600,
        fontSize: 12,
        letterSpacing: 0,
      ),
    );
  }
}
