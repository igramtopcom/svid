import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../../../downloads/domain/entities/download_status.dart';
import '../../../downloads/presentation/providers/filter_provider.dart';
import '../../../downloads/presentation/providers/filtered_downloads_provider.dart';

/// Nocturne Cinematic chip — angular ghost-bordered tactical control
class _NocturneChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? avatar;
  final bool showCheck;

  const _NocturneChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.avatar,
    this.showCheck = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    final accent = AppColors.accentHighlight;
    final selectedForeground = isDark ? AppColors.darkLightText : cs.onSurface;
    final idleForeground =
        isDark
            ? AppColors.darkMetaText
            : cs.onSurface.withValues(alpha: AppOpacity.secondary);
    final selectedBg =
        isDark
            ? AppColors.homeDarkCardHover
            : accent.withValues(alpha: AppOpacity.hover);
    final idleBg = isDark ? AppColors.homeDarkCardBg : AppColors.lightElevated;
    final selectedBorder =
        isDark
            ? accent.withValues(alpha: AppOpacity.strong)
            : accent.withValues(alpha: AppOpacity.quarter);
    final idleBorder =
        isDark
            ? AppColors.homeDarkBorderSubtle
            : cs.onSurface.withValues(alpha: AppOpacity.hover);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(AppRadius.card),
        hoverColor:
            selected
                ? Colors.transparent
                : (isDark
                    ? Colors.white.withValues(alpha: AppOpacity.hover)
                    : Colors.black.withValues(alpha: AppOpacity.hover)),
        splashColor: accent.withValues(alpha: AppOpacity.pressed),
        highlightColor: accent.withValues(alpha: AppOpacity.hover),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          decoration: BoxDecoration(
            color: selected ? selectedBg : idleBg,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: selected ? selectedBorder : idleBorder,
              width: selected ? 0.8 : 0.6,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showCheck && selected) ...[
                Icon(Icons.check, size: 14, color: accent),
                const SizedBox(width: AppSpacing.xxs),
              ],
              if (avatar != null) ...[
                avatar!,
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: selected ? selectedForeground : idleForeground,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Platform filter chips for All/Video/Audio tabs
class PlatformFilterChips extends ConsumerWidget {
  const PlatformFilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterState = ref.watch(filterProvider);
    final selectedPlatform = filterState.selectedPlatform;
    final availablePlatforms = ref.watch(
      availablePlatformsForCurrentTabProvider,
    );
    final platformCounts = ref.watch(platformCountsForCurrentTabProvider);

    if (availablePlatforms.isEmpty) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Padding(
            padding: EdgeInsets.only(right: AppSpacing.xs),
            child: _NocturneChip(
              label: AppLocalizations.downloadsAllPlatforms,
              selected: selectedPlatform == null,
              onTap:
                  () => ref.read(filterProvider.notifier).selectPlatform(null),
            ),
          ),
          ...availablePlatforms.map((platform) {
            final count = platformCounts[platform] ?? 0;
            return Padding(
              padding: EdgeInsets.only(right: AppSpacing.xs),
              child: _NocturneChip(
                avatar: PlatformIcon(platform: platform.name, size: 15),
                label:
                    count > 0
                        ? '${platform.displayName} ($count)'
                        : platform.displayName,
                selected: selectedPlatform == platform,
                onTap:
                    () => ref
                        .read(filterProvider.notifier)
                        .selectPlatform(platform),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Filterable download statuses for the status chips
const _filterableStatuses = [
  DownloadStatus.completed,
  DownloadStatus.failed,
  DownloadStatus.paused,
  DownloadStatus.downloading,
  DownloadStatus.pending,
  DownloadStatus.cancelled,
];

/// Status filter chips for downloads list
class StatusFilterChips extends ConsumerWidget {
  const StatusFilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterState = ref.watch(filterProvider);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Padding(
            padding: EdgeInsets.only(right: AppSpacing.xs),
            child: Text(
              '${AppLocalizations.downloadFilterStatusFilter}:',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.metaText(context),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          ..._filterableStatuses.map((status) {
            return Padding(
              padding: EdgeInsets.only(right: AppSpacing.xs),
              child: _NocturneChip(
                label: status.displayLabel,
                selected: filterState.statusFilters.contains(status),
                onTap:
                    () => ref
                        .read(filterProvider.notifier)
                        .toggleStatusFilter(status),
                showCheck: true,
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Watch status filter chips: All / Watched / Unwatched
class WatchFilterChips extends ConsumerWidget {
  const WatchFilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterState = ref.watch(filterProvider);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Padding(
            padding: EdgeInsets.only(right: AppSpacing.xs),
            child: Text(
              '${AppLocalizations.watchStatusWatched}:',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.metaText(context),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          ...WatchFilter.values.map((filter) {
            return Padding(
              padding: EdgeInsets.only(right: AppSpacing.xs),
              child: _NocturneChip(
                label: filter.displayName,
                selected: filterState.watchFilter == filter,
                onTap:
                    () => ref
                        .read(filterProvider.notifier)
                        .setWatchFilter(filter),
                showCheck: true,
              ),
            );
          }),
        ],
      ),
    );
  }
}
