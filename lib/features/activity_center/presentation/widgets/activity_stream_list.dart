import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../domain/entities/activity_item.dart';
import '../providers/activity_center_providers.dart';
import 'activity_item_card.dart';

/// Scrollable list of activity items grouped by date ("Today", "Yesterday", date string).
class ActivityStreamList extends ConsumerWidget {
  const ActivityStreamList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(filteredActivityItemsProvider);

    if (items.isEmpty) {
      return _buildEmptyState(context);
    }

    final grouped = _groupByDate(items);
    final sectionKeys = grouped.keys.toList();

    return CustomScrollView(
      slivers: [
        for (int s = 0; s < sectionKeys.length; s++) ...[
          // Sticky section header
          SliverPadding(
            padding: const EdgeInsets.only(
              left: AppSpacing.md,
              right: AppSpacing.md,
              top: AppSpacing.smMd,
            ),
            sliver: SliverToBoxAdapter(
              child: _SectionHeader(label: sectionKeys[s]),
            ),
          ),
          // Items in section
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            sliver: SliverList.builder(
              itemCount: grouped[sectionKeys[s]]!.length,
              itemBuilder: (context, index) {
                final item = grouped[sectionKeys[s]]![index];
                // Stable per-item key — see youtube_results_view.dart for rationale.
                // Without this, MouseRegion State gets rebound on scroll/filter
                // → mouse_tracker.dart:203 assertion under pointer dispatch.
                return Padding(
                  key: ValueKey<String>('activity_${item.id}'),
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: ActivityItemCard(item: item),
                );
              },
            ),
          ),
        ],
        // Bottom padding
        const SliverPadding(padding: EdgeInsets.only(bottom: AppSpacing.lg)),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 48,
            color: theme.colorScheme.onSurface.withValues(
              alpha: AppOpacity.quarter,
            ),
          ),
          const SizedBox(height: AppSpacing.smMd),
          Text(
            AppLocalizations.activityCenterNoActivity,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(
                alpha: AppOpacity.medium,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            AppLocalizations.activityCenterNoActivityHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(
                alpha: AppOpacity.scrim,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Group items by date label: "Today", "Yesterday", or formatted date.
  Map<String, List<ActivityItem>> _groupByDate(List<ActivityItem> items) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final grouped = <String, List<ActivityItem>>{};

    for (final item in items) {
      final itemDay = DateTime(
        item.timestamp.year,
        item.timestamp.month,
        item.timestamp.day,
      );

      String label;
      if (itemDay == today) {
        label = AppLocalizations.activityCenterToday;
      } else if (itemDay == yesterday) {
        label = AppLocalizations.activityCenterYesterday;
      } else {
        label = Formatters.formatDate(item.timestamp);
      }

      grouped.putIfAbsent(label, () => []).add(item);
    }

    return grouped;
  }
}

/// Section header for date groups.
class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(
            alpha: AppOpacity.medium,
          ),
          fontWeight: FontWeight.w600,
          fontSize: 11,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
