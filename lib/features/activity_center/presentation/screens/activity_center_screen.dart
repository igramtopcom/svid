import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../providers/activity_unread_provider.dart';
import '../widgets/activity_kpi_stats_row.dart';
import '../widgets/activity_filter_bar.dart';
import '../widgets/activity_stream_list.dart';
import '../widgets/activity_analytics_panel.dart';

/// Activity Center — full-page utility screen showing download activity
/// with KPI stats, filtered stream, and analytics.
class ActivityCenterScreen extends ConsumerStatefulWidget {
  const ActivityCenterScreen({super.key});

  @override
  ConsumerState<ActivityCenterScreen> createState() =>
      _ActivityCenterScreenState();
}

class _ActivityCenterScreenState extends ConsumerState<ActivityCenterScreen> {
  @override
  void initState() {
    super.initState();
    // Mark the activity center as visited so unread badge resets
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activityUnreadServiceProvider).markVisited();
      ref.invalidate(unreadActivityCountProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final background = isDark ? AppColors.homeDarkAppBg : AppColors.lightBase;

    return Container(
      color: background,
      child: Column(
        children: [
          // ── Top Bar (56px) ──────────────────────────────────────
          _buildTopBar(theme, isDark),

          // ── Content: Left stream + Right analytics ─────────────
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left panel (flex 7): KPI + Filters + Stream
                Expanded(
                  flex: 7,
                  child: Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.md,
                          AppSpacing.md,
                          AppSpacing.sm,
                        ),
                        child: ActivityKpiStatsRow(),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                        ),
                        child: ActivityFilterBar(),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const Expanded(child: ActivityStreamList()),
                    ],
                  ),
                ),

                // Right panel (340px): Analytics
                SizedBox(
                  width: 340,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color:
                              isDark
                                  ? AppColors.homeDarkBorderStrong
                                  : AppColors.border(context),
                        ),
                      ),
                    ),
                    child: const ActivityAnalyticsPanel(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(ThemeData theme, bool isDark) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color:
                isDark
                    ? AppColors.homeDarkBorderStrong
                    : AppColors.border(context),
          ),
        ),
      ),
      child: Row(
        children: [
          // Back button — navigate back to Home via navigationProvider
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            onPressed: () {
              ref.read(navigationProvider.notifier).navigateToHome();
            },
            tooltip: AppLocalizations.activityCenterBack,
            style: IconButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Icon(Icons.analytics_outlined, size: 20, color: AppColors.brand),
          const SizedBox(width: AppSpacing.sm),
          Text(
            AppLocalizations.activityCenterTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
