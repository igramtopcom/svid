import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../../../core/providers/notification_center_provider.dart';
import '../providers/activity_filter_provider.dart';
import '../providers/activity_unread_provider.dart';

/// Horizontal filter bar: search field + tab chips + date dropdown + mark all read.
/// Uses Flexible + horizontal scroll for tab chips to prevent overflow with longer locale strings.
class ActivityFilterBar extends ConsumerStatefulWidget {
  const ActivityFilterBar({super.key});

  @override
  ConsumerState<ActivityFilterBar> createState() => _ActivityFilterBarState();
}

class _ActivityFilterBarState extends ConsumerState<ActivityFilterBar> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final filter = ref.watch(activityFilterProvider);
    final fieldBorder =
        isDark
            ? AppColors.homeDarkBorderStrong
            : AppColors.border(context).withValues(alpha: 0.78);

    return SizedBox(
      height: 38,
      child: Row(
        children: [
          // ── Search field ─────────────────────────────────────────
          SizedBox(
            width: 260,
            child: TextField(
              controller: _searchController,
              style: theme.textTheme.bodySmall,
              decoration: InputDecoration(
                hintText: AppLocalizations.activityCenterSearchHint,
                hintStyle: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(
                    alpha: AppOpacity.medium,
                  ),
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurface.withValues(
                    alpha: AppOpacity.medium,
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 0,
                ),
                suffixIcon:
                    _searchController.text.isNotEmpty
                        ? GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            ref
                                .read(activityFilterProvider.notifier)
                                .setSearchQuery('');
                            setState(() {});
                          },
                          child: Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: AppOpacity.medium,
                            ),
                          ),
                        )
                        : null,
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 0,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 0,
                ),
                isDense: true,
                filled: true,
                fillColor: AppColors.surface2(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  borderSide: BorderSide(color: fieldBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  borderSide: BorderSide(color: fieldBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  borderSide: BorderSide(
                    color: AppColors.accentHighlight,
                    width: 1.5,
                  ),
                ),
              ),
              onChanged: (value) {
                ref.read(activityFilterProvider.notifier).setSearchQuery(value);
                setState(() {}); // refresh clear button visibility
              },
            ),
          ),
          const SizedBox(width: AppSpacing.smMd),

          // ── Scrollable tab chips + date dropdown ─────────────────
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ...ActivityFilterTab.values.map((tab) {
                    final isSelected = filter.selectedTab == tab;
                    return Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: _TabChip(
                        label: _tabLabel(tab),
                        isSelected: isSelected,
                        onTap:
                            () => ref
                                .read(activityFilterProvider.notifier)
                                .setTab(tab),
                      ),
                    );
                  }),

                  const SizedBox(width: AppSpacing.xs),

                  // Date range dropdown
                  PopupMenuButton<ActivityDateRange>(
                    tooltip: AppLocalizations.activityCenterDateRange,
                    onSelected: (range) {
                      ref
                          .read(activityFilterProvider.notifier)
                          .setDateRange(range);
                    },
                    itemBuilder:
                        (context) =>
                            ActivityDateRange.values.map((range) {
                              return PopupMenuItem<ActivityDateRange>(
                                value: range,
                                child: Row(
                                  children: [
                                    if (filter.dateRange == range)
                                      Icon(
                                        Icons.check_rounded,
                                        size: 16,
                                        color: AppColors.brand,
                                      )
                                    else
                                      const SizedBox(width: 16),
                                    const SizedBox(width: AppSpacing.sm),
                                    Text(
                                      _dateRangeLabel(range),
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.smMd,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface2(context),
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(color: fieldBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 14,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: AppOpacity.overlay,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            _dateRangeLabel(filter.dateRange),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Icon(
                            Icons.expand_more_rounded,
                            size: 14,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: AppOpacity.overlay,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: AppSpacing.sm),

          // ── Mark All Read (anchored right) ─────────────────────
          TextButton.icon(
            onPressed: () {
              // Mark system notifications as read
              ref.read(notificationCenterServiceProvider).markAllRead();
              // Mark activity center as visited (resets bell badge)
              ref.read(activityUnreadServiceProvider).markVisited();
              ref.invalidate(unreadActivityCountProvider);
            },
            icon: Icon(
              Icons.done_all_rounded,
              size: 16,
              color: theme.colorScheme.onSurface.withValues(
                alpha: AppOpacity.secondary,
              ),
            ),
            label: Text(
              AppLocalizations.activityCenterMarkAllRead,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(
                  alpha: AppOpacity.secondary,
                ),
                fontSize: 12,
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.smMd,
                vertical: AppSpacing.sm,
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  String _tabLabel(ActivityFilterTab tab) {
    return switch (tab) {
      ActivityFilterTab.all => AppLocalizations.activityCenterTabAll,
      ActivityFilterTab.active => AppLocalizations.activityCenterTabActive,
      ActivityFilterTab.success => AppLocalizations.activityCenterTabSuccess,
      ActivityFilterTab.errors => AppLocalizations.activityCenterTabErrors,
      ActivityFilterTab.system => AppLocalizations.activityCenterTabSystem,
    };
  }

  String _dateRangeLabel(ActivityDateRange range) {
    return switch (range) {
      ActivityDateRange.today => AppLocalizations.activityCenterDateToday,
      ActivityDateRange.last7Days =>
        AppLocalizations.activityCenterDateLast7Days,
      ActivityDateRange.last30Days =>
        AppLocalizations.activityCenterDateLast30Days,
      ActivityDateRange.allTime => AppLocalizations.activityCenterDateAllTime,
    };
  }
}

/// Styled chip for filter tabs — height 30px to align with date dropdown.
class _TabChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor =
        isDark
            ? AppColors.homeDarkBorderStrong
            : AppColors.border(context).withValues(alpha: 0.78);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.smMd),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:
              isSelected
                  ? AppColors.accentHighlight.withValues(alpha: 0.12)
                  : AppColors.surface2(context),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: isSelected ? AppColors.accentHighlight : borderColor,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color:
                isSelected
                    ? AppColors.accentHighlight
                    : theme.colorScheme.onSurface.withValues(
                      alpha: AppOpacity.strong,
                    ),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
