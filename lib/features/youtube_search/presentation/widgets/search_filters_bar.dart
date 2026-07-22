import 'package:flutter/material.dart';
import '../../../../core/core.dart';
import '../../domain/entities/search_filters.dart';

/// Search filters bar with chips
class SearchFiltersBar extends StatelessWidget {
  final YouTubeSearchFilters filters;
  final void Function(YouTubeSearchFilters filters) onFiltersChanged;

  const SearchFiltersBar({
    super.key,
    required this.filters,
    required this.onFiltersChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(
          bottom: BorderSide(color: AppColors.border(context), width: 0.5),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color:
                    isDark ? AppColors.homeDarkAppBg : AppColors.lightSurface2,
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(
                  color:
                      isDark
                          ? AppColors.homeDarkBorderStrong
                          : AppColors.border(context),
                ),
              ),
              child: Row(
                children: [
                  _buildFilterChip(
                    context,
                    label: filters.sortBy.label(context),
                    icon: Icons.sort,
                    onTap: () => _showSortByDialog(context),
                    isActive: filters.sortBy != SearchSortBy.relevance,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _buildFilterChip(
                    context,
                    label: filters.duration.label(context),
                    icon: Icons.schedule,
                    onTap: () => _showDurationDialog(context),
                    isActive: filters.duration != SearchDuration.any,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _buildFilterChip(
                    context,
                    label: filters.uploadDate.label(context),
                    icon: Icons.calendar_today,
                    onTap: () => _showUploadDateDialog(context),
                    isActive: filters.uploadDate != SearchUploadDate.anytime,
                  ),
                ],
              ),
            ),
            if (!filters.isDefault) ...[
              const SizedBox(width: AppSpacing.sm),
              TextButton.icon(
                onPressed: () => onFiltersChanged(const YouTubeSearchFilters()),
                icon: const Icon(Icons.clear, size: 16),
                label: Text(AppLocalizations.commonClear),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required bool isActive,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.smMd,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color:
              isActive
                  ? (isDark
                      ? AppColors.homeDarkCardBg
                      : AppColors.surface3(context))
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color:
                isActive
                    ? (isDark
                        ? AppColors.homeDarkBorderStrong
                        : AppColors.border(context))
                    : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color:
                  isActive
                      ? (isDark
                          ? AppColors.darkLightText
                          : theme.colorScheme.onSurface)
                      : AppColors.metaText(context),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              label,
              style: AppTypography.statusBadge.copyWith(
                fontSize: 12.5,
                color:
                    isActive
                        ? (isDark
                            ? AppColors.darkLightText
                            : theme.colorScheme.onSurface)
                        : AppColors.metaText(context),
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSortByDialog(BuildContext context) {
    _showChoiceDialog<SearchSortBy>(
      context: context,
      title: AppLocalizations.youtubeSearchFilterSortBy,
      values: SearchSortBy.values,
      groupValue: filters.sortBy,
      label: (sortBy) => sortBy.label(context),
      onSelected: (value) => onFiltersChanged(filters.copyWith(sortBy: value)),
    );
  }

  void _showDurationDialog(BuildContext context) {
    _showChoiceDialog<SearchDuration>(
      context: context,
      title: AppLocalizations.youtubeSearchFilterDuration,
      values: SearchDuration.values,
      groupValue: filters.duration,
      label: (duration) => duration.label(context),
      onSelected:
          (value) => onFiltersChanged(filters.copyWith(duration: value)),
    );
  }

  void _showUploadDateDialog(BuildContext context) {
    _showChoiceDialog<SearchUploadDate>(
      context: context,
      title: AppLocalizations.youtubeSearchFilterUploadDate,
      values: SearchUploadDate.values,
      groupValue: filters.uploadDate,
      label: (uploadDate) => uploadDate.label(context),
      onSelected:
          (value) => onFiltersChanged(filters.copyWith(uploadDate: value)),
    );
  }

  void _showChoiceDialog<T>({
    required BuildContext context,
    required String title,
    required List<T> values,
    required T groupValue,
    required String Function(T value) label,
    required ValueChanged<T> onSelected,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final isDark = theme.brightness == Brightness.dark;

        return AlertDialog(
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xl,
          ),
          backgroundColor:
              isDark ? AppColors.homeDarkCardBg : AppColors.surface1(context),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
            side: BorderSide(color: AppColors.border(context)),
          ),
          title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children:
                  values.map((value) {
                    return RadioListTile<T>(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        label(value),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      value: value,
                      groupValue: groupValue,
                      onChanged: (next) {
                        if (next == null) return;
                        onSelected(next);
                        Navigator.pop(dialogContext);
                      },
                    );
                  }).toList(),
            ),
          ),
        );
      },
    );
  }
}
