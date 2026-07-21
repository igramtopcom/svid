import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/presentation/providers/settings_provider.dart';
import '../core.dart';
import 'navigation_constants.dart';

/// Vertical navigation rail on the left edge.
///
/// Replaces the old top tab bar: primary destinations (Home / Explore /
/// Converter / Browser) sit at the top with labels; utilities (Settings,
/// theme toggle, and an overflow menu for Activity / Assistant / Support)
/// sit at the bottom. Keeps the content area full-width and focused.
class LeftNavRail extends ConsumerWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const LeftNavRail({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  static const double railWidth = 80;

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
          const SizedBox(height: AppSpacing.md),
          _RailItem(
            icon: isHome ? Icons.home_rounded : Icons.home_outlined,
            label: AppLocalizations.navHome,
            selected: isHome,
            onTap: () => onDestinationSelected(NavigationConstants.homeIndex),
          ),
          _RailItem(
            icon: Icons.explore_outlined,
            label: AppLocalizations.youtubeTabTitle,
            selected: isExplore,
            onTap: () => onDestinationSelected(NavigationConstants.youtubeIndex),
          ),
          _RailItem(
            icon: Icons.crop_rotate_rounded,
            label: AppLocalizations.navConverter,
            selected: isConverter,
            onTap:
                () => onDestinationSelected(NavigationConstants.converterIndex),
          ),
          _RailItem(
            icon: Icons.language_rounded,
            label: AppLocalizations.navBrowser,
            selected: isBrowser,
            onTap: () => onDestinationSelected(NavigationConstants.browserIndex),
          ),
          const Spacer(),
          _RailIconButton(
            icon: isSettings ? Icons.settings : Icons.settings_outlined,
            tooltip: AppLocalizations.navSettings,
            selected: isSettings,
            onTap: () => onDestinationSelected(NavigationConstants.settingsIndex),
          ),
          _RailIconButton(
            icon: isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
            tooltip:
                isDark
                    ? AppLocalizations.settingsThemeLight
                    : AppLocalizations.settingsThemeDark,
            selected: false,
            onTap: () {
              ref
                  .read(settingsProvider.notifier)
                  .updateThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);
            },
          ),
          _RailOverflowButton(onSelected: onDestinationSelected),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

/// A labelled primary destination (icon over label) in the rail.
class _RailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RailItem({
    required this.icon,
    required this.label,
    required this.selected,
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Container(
            height: 56,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:
                  selected
                      ? accent.withValues(alpha: AppOpacity.subtle)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: (selected
                          ? AppTypography.navItemSelected
                          : AppTypography.navItem)
                      .copyWith(color: color, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An icon-only utility button in the rail's bottom cluster.
class _RailIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  const _RailIconButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentHighlight;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      child: Tooltip(
        message: tooltip,
        waitDuration: AppDurations.tooltipWaitDuration,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Container(
              height: 44,
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color:
                    selected
                        ? accent.withValues(alpha: AppOpacity.subtle)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Icon(
                icon,
                size: 22,
                color: selected ? accent : AppColors.metaText(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The ⋮ overflow at the bottom of the rail — secondary destinations.
class _RailOverflowButton extends StatelessWidget {
  final ValueChanged<int> onSelected;

  const _RailOverflowButton({required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      child: PopupMenuButton<int>(
        tooltip: AppLocalizations.commonMore,
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.over,
        onSelected: onSelected,
        child: Container(
          height: 44,
          width: double.infinity,
          alignment: Alignment.center,
          child: Icon(
            Icons.more_horiz,
            size: 22,
            color: AppColors.metaText(context),
          ),
        ),
        itemBuilder:
            (ctx) => [
              PopupMenuItem<int>(
                value: NavigationConstants.activityCenterIndex,
                child: _menuRow(
                  ctx,
                  Icons.timeline_outlined,
                  AppLocalizations.activityCenterTitle,
                ),
              ),
              PopupMenuItem<int>(
                value: NavigationConstants.assistantIndex,
                child: _menuRow(
                  ctx,
                  Icons.auto_awesome_outlined,
                  AppLocalizations.navAssistant,
                ),
              ),
              PopupMenuItem<int>(
                value: NavigationConstants.supportIndex,
                child: _menuRow(
                  ctx,
                  Icons.support_agent_outlined,
                  AppLocalizations.navSupport,
                ),
              ),
            ],
      ),
    );
  }

  Widget _menuRow(BuildContext context, IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.metaText(context)),
        const SizedBox(width: AppSpacing.sm),
        Text(label),
      ],
    );
  }
}
