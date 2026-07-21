import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/presentation/providers/settings_provider.dart';
import '../core.dart';
import 'navigation_constants.dart';

/// Full-height vertical navigation rail on the left edge.
///
/// Brand logo anchors the top, primary destinations (Home / Explore /
/// Converter / Browser) sit below, and secondary destinations + app controls
/// (Assistant, Support, Activity, Settings, theme toggle) sit at the bottom —
/// every item shows an icon *and* a label.
class LeftNavRail extends ConsumerWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const LeftNavRail({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  static const double railWidth = 88;

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
    final isAssistant = selectedIndex == NavigationConstants.assistantIndex;
    final isSupport = selectedIndex == NavigationConstants.supportIndex;
    final isActivity =
        selectedIndex == NavigationConstants.activityCenterIndex;

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
          SizedBox(height: Platform.isMacOS ? 32 : AppSpacing.md),
          _RailLogo(
            onTap: () => onDestinationSelected(NavigationConstants.homeIndex),
          ),
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
          _RailItem(
            icon: Icons.auto_awesome_outlined,
            label: AppLocalizations.navAssistant,
            selected: isAssistant,
            onTap:
                () => onDestinationSelected(NavigationConstants.assistantIndex),
          ),
          _RailItem(
            icon: Icons.support_agent_outlined,
            label: AppLocalizations.navSupport,
            selected: isSupport,
            onTap: () => onDestinationSelected(NavigationConstants.supportIndex),
          ),
          _RailItem(
            icon: Icons.timeline_outlined,
            label: AppLocalizations.activityCenterTitle,
            selected: isActivity,
            onTap:
                () => onDestinationSelected(
                  NavigationConstants.activityCenterIndex,
                ),
          ),
          Divider(
            height: AppSpacing.md,
            thickness: 1,
            indent: AppSpacing.smMd,
            endIndent: AppSpacing.smMd,
            color: cs.outlineVariant.withValues(alpha: AppOpacity.divider),
          ),
          _RailItem(
            icon: isSettings ? Icons.settings : Icons.settings_outlined,
            label: AppLocalizations.navSettings,
            selected: isSettings,
            onTap: () => onDestinationSelected(NavigationConstants.settingsIndex),
          ),
          _RailItem(
            icon: isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
            label:
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
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

/// Brand logo anchoring the top of the rail.
class _RailLogo extends StatelessWidget {
  final VoidCallback onTap;
  const _RailLogo({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Image.asset(
                  AppAssets.logo,
                  width: 40,
                  height: 40,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                AppConstants.appName,
                style: AppTypography.navItemSelected.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A labelled rail entry (icon over label). Used for every destination.
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
      child: Tooltip(
        message: label,
        waitDuration: AppDurations.tooltipWaitDuration,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Container(
              height: 54,
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
      ),
    );
  }
}
