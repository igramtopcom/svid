import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/presentation/providers/settings_provider.dart';
import '../core.dart';
import 'navigation_constants.dart';

/// Full-height left navigation rail.
///
/// Two responsive states, chosen by the caller via [expanded]:
///  - expanded  (wide window): a brand header + rows of `icon + label`
///  - collapsed (narrow window): a logo mark + icon-only rows (labels move to
///    tooltips)
///
/// A brand header (logo + wordmark) sits above a divider so it reads as the
/// app header rather than another nav item; primary destinations, secondary
/// destinations, and the settings footer are separated by hairline dividers.
class LeftNavRail extends ConsumerWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool expanded;

  const LeftNavRail({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.expanded = true,
  });

  static const double expandedWidth = 220;
  static const double collapsedWidth = 72;

  /// Window width at/above which the rail shows labels.
  static const double expandBreakpoint = 1120;

  double get railWidth => expanded ? expandedWidth : collapsedWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    final isHome =
        selectedIndex == NavigationConstants.homeIndex ||
        NavigationConstants.isDownloadFilterTab(selectedIndex);
    final isExplore =
        selectedIndex == NavigationConstants.youtubeIndex ||
        selectedIndex == NavigationConstants.subscriptionsIndex;
    final isConverter = selectedIndex == NavigationConstants.converterIndex;
    final isBrowser = selectedIndex == NavigationConstants.browserIndex;
    final isSettings = selectedIndex == NavigationConstants.settingsIndex;
    final isSupport = selectedIndex == NavigationConstants.supportIndex;
    final isActivity =
        selectedIndex == NavigationConstants.activityCenterIndex;

    Widget divider() => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.smMd,
        vertical: AppSpacing.sm,
      ),
      child: Divider(
        height: 1,
        thickness: 1,
        color: cs.outlineVariant.withValues(alpha: AppOpacity.divider),
      ),
    );

    return Container(
      width: railWidth,
      decoration: BoxDecoration(
        color: isDark ? AppColors.homeDarkAppBg : cs.surface,
        border: Border(
          right: BorderSide(
            color: cs.outlineVariant.withValues(alpha: AppOpacity.divider),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Reserve space for the macOS traffic-light buttons at the top-left.
          SizedBox(height: Platform.isMacOS ? 30 : AppSpacing.sm),
          _RailHeader(
            expanded: expanded,
            onTap: () => onDestinationSelected(NavigationConstants.homeIndex),
          ),
          divider(),
          _RailItem(
            icon: isHome ? Icons.home_rounded : Icons.home_outlined,
            label: AppLocalizations.navHome,
            selected: isHome,
            expanded: expanded,
            onTap: () => onDestinationSelected(NavigationConstants.homeIndex),
          ),
          _RailItem(
            icon: Icons.explore_outlined,
            label: AppLocalizations.youtubeTabTitle,
            selected: isExplore,
            expanded: expanded,
            onTap: () => onDestinationSelected(NavigationConstants.youtubeIndex),
          ),
          _RailItem(
            icon: Icons.crop_rotate_rounded,
            label: AppLocalizations.navConverter,
            selected: isConverter,
            expanded: expanded,
            onTap:
                () => onDestinationSelected(NavigationConstants.converterIndex),
          ),
          _RailItem(
            icon: Icons.language_rounded,
            label: AppLocalizations.navBrowser,
            selected: isBrowser,
            expanded: expanded,
            onTap: () => onDestinationSelected(NavigationConstants.browserIndex),
          ),
          _RailItem(
            icon: Icons.support_agent_outlined,
            label: AppLocalizations.navSupport,
            selected: isSupport,
            expanded: expanded,
            onTap: () => onDestinationSelected(NavigationConstants.supportIndex),
          ),
          _RailItem(
            icon: Icons.timeline_outlined,
            label: AppLocalizations.activityCenterTitle,
            selected: isActivity,
            expanded: expanded,
            onTap:
                () => onDestinationSelected(
                  NavigationConstants.activityCenterIndex,
                ),
          ),
          const Spacer(),
          divider(),
          _RailItem(
            icon: isSettings ? Icons.settings : Icons.settings_outlined,
            label: AppLocalizations.navSettings,
            selected: isSettings,
            expanded: expanded,
            onTap: () => onDestinationSelected(NavigationConstants.settingsIndex),
          ),
          _RailItem(
            icon: isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
            label:
                isDark
                    ? AppLocalizations.settingsThemeLight
                    : AppLocalizations.settingsThemeDark,
            selected: false,
            expanded: expanded,
            onTap: () {
              ref
                  .read(settingsProvider.notifier)
                  .updateThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);
            },
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

/// Brand header: logo (+ wordmark when expanded) anchoring the top of the rail.
class _RailHeader extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;
  const _RailHeader({required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final logo = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Image.asset(
        AppAssets.logo,
        width: 34,
        height: 34,
        fit: BoxFit.contain,
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: expanded ? AppSpacing.md : AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child:
                expanded
                    ? Row(
                      children: [
                        logo,
                        const SizedBox(width: AppSpacing.smMd),
                        Expanded(
                          child: Text(
                            AppConstants.appName.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.appBarTitle.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                              letterSpacing: 2.2,
                            ),
                          ),
                        ),
                      ],
                    )
                    : Center(child: logo),
          ),
        ),
      ),
    );
  }
}

/// A rail entry — `icon + label` row when expanded, icon-only when collapsed.
class _RailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  const _RailItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentHighlight;
    final color = selected ? accent : AppColors.metaText(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      child: Tooltip(
        message: expanded ? '' : label,
        waitDuration: AppDurations.tooltipWaitDuration,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.button),
            child: Container(
              height: 44,
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: expanded ? AppSpacing.smMd : 0,
              ),
              alignment: expanded ? Alignment.centerLeft : Alignment.center,
              decoration: BoxDecoration(
                color:
                    selected
                        ? accent.withValues(alpha: AppOpacity.subtle)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
              child: Row(
                mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  Icon(icon, size: 22, color: color),
                  if (expanded) ...[
                    const SizedBox(width: AppSpacing.smMd),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: (selected
                                ? AppTypography.navItemSelected
                                : AppTypography.navItem)
                            .copyWith(color: color, fontSize: 14),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
