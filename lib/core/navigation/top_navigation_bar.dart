import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../features/premium/presentation/providers/premium_providers.dart';
import '../../features/settings/presentation/providers/settings_provider.dart';
import '../core.dart';
import 'navigation_constants.dart';

/// Top navigation bar for the desktop shell.
class TopNavigationBar extends ConsumerWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const TopNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final density = _TopNavDensity.fromWidth(constraints.maxWidth);

        return Container(
          height: 64,
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkBase : AppColors.surface1(context),
            border: Border(
              bottom: BorderSide(
                color:
                    isDark
                        ? AppColors.darkMuted.withValues(
                          alpha: AppOpacity.pressed,
                        )
                        : cs.outlineVariant.withValues(
                          alpha: AppOpacity.subtle,
                        ),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              // ── Left cluster: macOS traffic-light spacer + Logo + drag area ──
              GestureDetector(
                onPanStart: (_) => windowManager.startDragging(),
                onDoubleTap: _toggleMaximize,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: Platform.isMacOS ? 78 : 12),
                    _buildLogo(context, cs, density: density),
                    SizedBox(
                      width:
                          density.tightSpacing ? AppSpacing.sm : AppSpacing.md,
                    ),
                  ],
                ),
              ),

              // ── Primary tabs — Explore now owns YouTube discovery and
              //    channel subscriptions under one product surface.
              _buildPrimaryNavigation(
                context,
                isDark: isDark,
                density: density,
              ),

              // ── Drag-area spacer between tabs and right cluster ──
              Expanded(
                child: GestureDetector(
                  onPanStart: (_) => windowManager.startDragging(),
                  onDoubleTap: _toggleMaximize,
                  behavior: HitTestBehavior.opaque,
                ),
              ),

              // ── Right cluster: Upgrade / Activity / Settings / Theme / Overflow ──
              if (density.showUpgradePill &&
                  !BrandConfig.current.allFeaturesFree) ...[
                _buildUpgradePill(
                  context,
                  ref,
                  isDark: isDark,
                  compact: density.compactUtilityTabs,
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              _buildIconAction(
                context,
                isDark: isDark,
                icon:
                    selectedIndex == NavigationConstants.settingsIndex
                        ? Icons.settings
                        : Icons.settings_outlined,
                tooltip: '${AppLocalizations.navSettings} ($_modKey,)',
                isActive: selectedIndex == NavigationConstants.settingsIndex,
                onTap:
                    () => onDestinationSelected(
                      NavigationConstants.settingsIndex,
                    ),
              ),
              if (density.showThemeToggle) ...[
                const SizedBox(width: AppSpacing.xs),
                _buildThemeToggle(context, ref, isDark),
              ],
              const SizedBox(width: AppSpacing.xs),
              // Overflow ⋮ houses secondary destinations: Activity/analytics,
              // Assistant, and Support — keeps the top bar to a few clear
              // utilities (settings, theme, overflow) instead of a dense row.
              _buildOverflowMenu(context, isDark: isDark),
              if (!Platform.isMacOS) ...[
                const SizedBox(width: AppSpacing.xs),
                _GhostDivider(isDark: isDark, cs: cs),
                const SizedBox(width: AppSpacing.xs),
                _WindowControlButton(
                  icon: Icons.minimize_rounded,
                  type: _WindowControlType.minimize,
                  onTap: () => windowManager.minimize(),
                ),
                _WindowControlButton(
                  icon: Icons.crop_square_rounded,
                  type: _WindowControlType.maximize,
                  onTap: _toggleMaximize,
                ),
                _WindowControlButton(
                  icon: Icons.close_rounded,
                  type: _WindowControlType.close,
                  onTap: () => windowManager.close(),
                ),
              ],
              const SizedBox(width: AppSpacing.smMd),
            ],
          ),
        );
      },
    );
  }

  /// Right-cluster "Nâng cấp" pill — outlined light-bg variant per
  /// V2 mockup *shape*, with the brand accent color (NOT the mockup's
  /// industrial blue). Free users see the prominent upgrade CTA;
  /// premium users see a quiet glyph-only badge.
  ///
  /// Brand accent reasoning: the V2 mockup uses a placeholder blue,
  /// but Svid is Wine Red across every other surface (CTAs, badges,
  /// brand glyph). Adopting mockup shape (outlined pill on light bg)
  /// with brand color (Wine Red / VidCombo Cyan via BrandConfig)
  /// keeps the V2 layout intent without fracturing brand identity.
  Widget _buildUpgradePill(
    BuildContext context,
    WidgetRef ref, {
    required bool isDark,
    required bool compact,
  }) {
    // Free-unlimited build (svid): no upgrade/premium entry point in the bar.
    if (BrandConfig.current.allFeaturesFree) return const SizedBox.shrink();
    final isPremium = ref.watch(isPremiumProvider);
    final isActive = selectedIndex == NavigationConstants.premiumIndex;
    final accent = AppColors.accentHighlight;
    final cs = Theme.of(context).colorScheme;

    if (isPremium) {
      // Premium users: subtle glyph-only pill — never compete with CTAs.
      return Tooltip(
        message: AppLocalizations.premiumTitle,
        waitDuration: AppDurations.tooltipWaitDuration,
        child: InkWell(
          onTap: () => onDestinationSelected(NavigationConstants.premiumIndex),
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.smMd),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              color:
                  isActive
                      ? accent.withValues(alpha: AppOpacity.pressed)
                      : Colors.transparent,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.workspace_premium, size: 16, color: accent),
                if (!compact) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    AppLocalizations.premiumTitle,
                    style: AppTypography.navItemSelected.copyWith(
                      color: accent,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    // Free users: outlined blue light-bg pill — the V2 mockup CTA
    // shape. Background uses the surface lowest tone so it reads as
    // a chip on top of the bar surface; border + glyph + text use the
    // mockup's active-blue accent.
    return Tooltip(
      message: AppLocalizations.premiumUpgradeTitle,
      waitDuration: AppDurations.tooltipWaitDuration,
      child: InkWell(
        onTap: () => onDestinationSelected(NavigationConstants.premiumIndex),
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          height: 32,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? AppSpacing.sm : AppSpacing.smMd,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: accent, width: 1),
            color: cs.surfaceContainerLowest,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.workspace_premium, size: 16, color: accent),
              if (!compact) ...[
                const SizedBox(width: AppSpacing.xs),
                Text(
                  AppLocalizations.premiumUpgradeShort,
                  style: AppTypography.navItemSelected.copyWith(color: accent),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String get _modKey => Platform.isMacOS ? 'Cmd+' : 'Ctrl+';

  static Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  bool get _isDownloadsSelected =>
      selectedIndex == NavigationConstants.homeIndex ||
      NavigationConstants.isDownloadFilterTab(selectedIndex);

  Widget _buildPrimaryNavigation(
    BuildContext context, {
    required bool isDark,
    required _TopNavDensity density,
  }) {
    if (density.collapsePrimaryTabs) {
      return _buildPrimaryNavigationMenu(context, isDark: isDark);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTab(
          context,
          isDark: isDark,
          label: AppLocalizations.navHome,
          icon: _isDownloadsSelected ? Icons.home_rounded : Icons.home_outlined,
          index: NavigationConstants.homeIndex,
          isSelected: _isDownloadsSelected,
          compact: density.compactPrimaryTabs,
        ),
        _buildTab(
          context,
          isDark: isDark,
          label: AppLocalizations.youtubeTabTitle,
          icon: Icons.explore_outlined,
          index: NavigationConstants.youtubeIndex,
          isSelected:
              selectedIndex == NavigationConstants.youtubeIndex ||
              selectedIndex == NavigationConstants.subscriptionsIndex,
          compact: density.compactPrimaryTabs,
        ),
        _buildTab(
          context,
          isDark: isDark,
          label: AppLocalizations.navConverter,
          icon: Icons.crop_rotate_rounded,
          index: NavigationConstants.converterIndex,
          isSelected: selectedIndex == NavigationConstants.converterIndex,
          compact: density.compactPrimaryTabs,
        ),
        _buildTab(
          context,
          isDark: isDark,
          label: AppLocalizations.navBrowser,
          icon: Icons.language_rounded,
          index: NavigationConstants.browserIndex,
          isSelected: selectedIndex == NavigationConstants.browserIndex,
          compact: density.compactPrimaryTabs,
        ),
      ],
    );
  }

  Widget _buildPrimaryNavigationMenu(
    BuildContext context, {
    required bool isDark,
  }) {
    final cs = Theme.of(context).colorScheme;
    final accent = AppColors.accentHighlight;

    PopupMenuItem<int> item({
      required int value,
      required IconData icon,
      required String label,
      required bool selected,
    }) {
      return PopupMenuItem<int>(
        value: value,
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? accent : AppColors.metaText(context),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: selected ? cs.onSurface : AppColors.metaText(context),
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xxs),
      child: Tooltip(
        message: _currentPrimaryLabel,
        waitDuration: AppDurations.tooltipWaitDuration,
        child: PopupMenuButton<int>(
          tooltip: _currentPrimaryLabel,
          padding: EdgeInsets.zero,
          iconSize: 18,
          offset: const Offset(0, 38),
          onSelected: onDestinationSelected,
          itemBuilder:
              (ctx) => [
                item(
                  value: NavigationConstants.homeIndex,
                  icon:
                      _isDownloadsSelected
                          ? Icons.home_rounded
                          : Icons.home_outlined,
                  label: AppLocalizations.navHome,
                  selected: _isDownloadsSelected,
                ),
                item(
                  value: NavigationConstants.youtubeIndex,
                  icon: Icons.explore_outlined,
                  label: AppLocalizations.youtubeTabTitle,
                  selected:
                      selectedIndex == NavigationConstants.youtubeIndex ||
                      selectedIndex == NavigationConstants.subscriptionsIndex,
                ),
                item(
                  value: NavigationConstants.converterIndex,
                  icon: Icons.crop_rotate_rounded,
                  label: AppLocalizations.navConverter,
                  selected: selectedIndex == NavigationConstants.converterIndex,
                ),
                item(
                  value: NavigationConstants.browserIndex,
                  icon: Icons.language_rounded,
                  label: AppLocalizations.navBrowser,
                  selected: selectedIndex == NavigationConstants.browserIndex,
                ),
              ],
          icon: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: AppOpacity.hover),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: accent.withValues(alpha: AppOpacity.pressed),
                width: 1,
              ),
            ),
            child: Icon(_currentPrimaryIcon, size: 18, color: accent),
          ),
        ),
      ),
    );
  }

  String get _currentPrimaryLabel {
    if (_isDownloadsSelected) {
      return AppLocalizations.navHome;
    }
    if (selectedIndex == NavigationConstants.youtubeIndex ||
        selectedIndex == NavigationConstants.subscriptionsIndex) {
      return AppLocalizations.youtubeTabTitle;
    }
    if (selectedIndex == NavigationConstants.converterIndex) {
      return AppLocalizations.navConverter;
    }
    if (selectedIndex == NavigationConstants.browserIndex) {
      return AppLocalizations.navBrowser;
    }
    return AppLocalizations.commonMore;
  }

  IconData get _currentPrimaryIcon {
    if (_isDownloadsSelected) {
      return Icons.home_rounded;
    }
    if (selectedIndex == NavigationConstants.youtubeIndex ||
        selectedIndex == NavigationConstants.subscriptionsIndex) {
      return Icons.explore_outlined;
    }
    if (selectedIndex == NavigationConstants.converterIndex) {
      return Icons.crop_rotate_rounded;
    }
    if (selectedIndex == NavigationConstants.browserIndex) {
      return Icons.language_rounded;
    }
    return Icons.apps_rounded;
  }

  Widget _buildLogo(
    BuildContext context,
    ColorScheme cs, {
    required _TopNavDensity density,
  }) {
    return InkWell(
      onTap: () => onDestinationSelected(NavigationConstants.homeIndex),
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: Image.asset(
                AppAssets.logo,
                width: density.showLogoText ? 28 : 24,
                height: density.showLogoText ? 28 : 24,
                fit: BoxFit.contain,
              ),
            ),
            if (density.showLogoText) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(
                AppConstants.appName,
                style: AppTypography.appBarTitle.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTab(
    BuildContext context, {
    required bool isDark,
    required String label,
    required IconData icon,
    required int index,
    required bool isSelected,
    required bool compact,
    double height = 52,
  }) {
    final cs = Theme.of(context).colorScheme;
    final showLabel = !compact || isSelected;
    // Brand-consistent active tab accent. The V2 mockup hint at blue,
    // but Svid identity is Wine Red across every other surface
    // (CTAs, pills, badges, brand glyph). Copying the mockup blue
    // here would fracture the visual identity. Use the brand
    // accent so Svid renders Wine Red and VidCombo renders Cyan
    // automatically via [BrandConfig].
    final navAccent = AppColors.accentHighlight;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 1 : AppSpacing.xxs),
      child: Tooltip(
        message: showLabel ? '' : label,
        waitDuration: AppDurations.tooltipWaitDuration,
        child: _HoverableTab(
          isSelected: isSelected,
          onTap: () => onDestinationSelected(index),
          child: Container(
            height: height,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? AppSpacing.sm : AppSpacing.smMd,
            ),
            decoration: BoxDecoration(
              color: Colors.transparent,
              border:
                  isSelected
                      ? Border(bottom: BorderSide(color: navAccent, width: 2))
                      : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isSelected ? navAccent : AppColors.metaText(context),
                ),
                if (showLabel) ...[
                  SizedBox(width: compact ? AppSpacing.xs : AppSpacing.sm),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: (isSelected
                            ? AppTypography.navItemSelected
                            : AppTypography.navItem)
                        .copyWith(
                          color:
                              isSelected
                                  ? cs.onSurface
                                  : AppColors.metaText(context),
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Lightweight overflow menu housing Trợ lý AI + Hỗ trợ. Mockup
  /// shows no overflow but production app needs an access point —
  /// without it, the AI assistant and support screens become
  /// orphaned. Native PopupMenu, no extra surface area on the bar.
  Widget _buildOverflowMenu(BuildContext context, {required bool isDark}) {
    return PopupMenuButton<int>(
      tooltip: AppLocalizations.commonMore,
      padding: EdgeInsets.zero,
      onSelected: onDestinationSelected,
      // Framed 40x40 button to match the settings/theme utilities.
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(
          Icons.more_vert,
          size: 20,
          color: AppColors.metaText(context),
        ),
      ),
      itemBuilder:
          (ctx) => [
            PopupMenuItem<int>(
              value: NavigationConstants.activityCenterIndex,
              child: Row(
                children: [
                  Icon(
                    selectedIndex == NavigationConstants.activityCenterIndex
                        ? Icons.timeline
                        : Icons.timeline_outlined,
                    size: 18,
                    color: AppColors.metaText(context),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(AppLocalizations.activityCenterTitle),
                ],
              ),
            ),
            PopupMenuItem<int>(
              value: NavigationConstants.assistantIndex,
              child: Row(
                children: [
                  Icon(
                    selectedIndex == NavigationConstants.assistantIndex
                        ? Icons.auto_awesome
                        : Icons.auto_awesome_outlined,
                    size: 18,
                    color: AppColors.metaText(context),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(AppLocalizations.navAssistant),
                ],
              ),
            ),
            PopupMenuItem<int>(
              value: NavigationConstants.supportIndex,
              child: Row(
                children: [
                  Icon(
                    selectedIndex == NavigationConstants.supportIndex
                        ? Icons.support_agent
                        : Icons.support_agent_outlined,
                    size: 18,
                    color: AppColors.metaText(context),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(AppLocalizations.navSupport),
                ],
              ),
            ),
          ],
    );
  }

  Widget _buildIconAction(
    BuildContext context, {
    required bool isDark,
    required IconData icon,
    required String tooltip,
    bool isActive = false,
    VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: AppDurations.tooltipWaitDuration,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            color:
                isActive
                    ? AppColors.accentHighlight.withValues(
                      alpha: AppOpacity.pressed,
                    )
                    : Colors.transparent,
          ),
          child: Icon(
            icon,
            size: 20,
            color:
                isActive
                    ? AppColors.accentHighlight
                    : AppColors.metaText(context),
          ),
        ),
      ),
    );
  }

  Widget _buildThemeToggle(BuildContext context, WidgetRef ref, bool isDark) {
    return Tooltip(
      message:
          isDark
              ? AppLocalizations.settingsThemeLight
              : AppLocalizations.settingsThemeDark,
      waitDuration: AppDurations.tooltipWaitDuration,
      child: InkWell(
        onTap: () {
          ref
              .read(settingsProvider.notifier)
              .updateThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);
        },
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: SizedBox(
          width: 40,
          height: 40,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder:
                (child, animation) => RotationTransition(
                  turns: Tween(begin: 0.75, end: 1.0).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                ),
            child: Icon(
              isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              key: ValueKey(isDark),
              size: 20,
              color: AppColors.metaText(context),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopNavDensity {
  final bool showLogoText;
  final bool collapsePrimaryTabs;
  final bool compactPrimaryTabs;
  final bool compactUtilityTabs;
  final bool tightSpacing;
  final bool showUpgradePill;
  final bool showThemeToggle;

  const _TopNavDensity({
    required this.showLogoText,
    required this.collapsePrimaryTabs,
    required this.compactPrimaryTabs,
    required this.compactUtilityTabs,
    required this.tightSpacing,
    required this.showUpgradePill,
    required this.showThemeToggle,
  });

  factory _TopNavDensity.fromWidth(double width) {
    return _TopNavDensity(
      showLogoText: width >= 900,
      collapsePrimaryTabs: width < 640,
      compactPrimaryTabs: width < 940,
      compactUtilityTabs: width < 1120,
      tightSpacing: width < 920,
      showUpgradePill: width >= 620,
      showThemeToggle: width >= 430,
    );
  }
}

class _GhostDivider extends StatelessWidget {
  final bool isDark;
  final ColorScheme cs;

  const _GhostDivider({required this.isDark, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 0.5,
      height: 22,
      color:
          isDark
              ? AppColors.darkMuted.withValues(alpha: AppOpacity.subtle)
              : cs.outlineVariant.withValues(alpha: AppOpacity.quarter),
    );
  }
}

class _HoverableTab extends StatefulWidget {
  final bool isSelected;
  final VoidCallback onTap;
  final Widget child;

  const _HoverableTab({
    required this.isSelected,
    required this.onTap,
    required this.child,
  });

  @override
  State<_HoverableTab> createState() => _HoverableTabState();
}

class _HoverableTabState extends State<_HoverableTab> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        mouseCursor: SystemMouseCursors.click,
        hoverColor:
            widget.isSelected
                ? Colors.transparent
                : (isDark
                    ? Colors.white.withValues(alpha: AppOpacity.hover)
                    : Colors.black.withValues(alpha: AppOpacity.hover)),
        splashColor: AppColors.accentHighlight.withValues(
          alpha: AppOpacity.pressed,
        ),
        highlightColor: AppColors.accentHighlight.withValues(
          alpha: AppOpacity.hover,
        ),
        child: widget.child,
      ),
    );
  }
}

enum _WindowControlType { minimize, maximize, close }

class _WindowControlButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final _WindowControlType type;

  const _WindowControlButton({
    required this.icon,
    required this.onTap,
    required this.type,
  });

  @override
  State<_WindowControlButton> createState() => _WindowControlButtonState();
}

class _WindowControlButtonState extends State<_WindowControlButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isClose = widget.type == _WindowControlType.close;
    final accent = AppColors.accentHighlight;
    final iconColor =
        _isHovered
            ? (isClose ? AppColors.errorRed : accent)
            : (isDark
                ? AppColors.homeDarkTextSecondary
                : cs.onSurfaceVariant.withValues(alpha: 0.82));
    final hoverBg =
        isClose
            ? Color.alphaBlend(
              AppColors.errorRed.withValues(alpha: isDark ? 0.18 : 0.10),
              isDark ? AppColors.homeDarkCardBg : cs.surfaceContainerLowest,
            )
            : Color.alphaBlend(
              accent.withValues(alpha: isDark ? 0.16 : 0.08),
              isDark ? AppColors.homeDarkCardBg : cs.surfaceContainerLowest,
            );
    final hoverBorder =
        isClose
            ? AppColors.errorRed.withValues(alpha: isDark ? 0.52 : 0.36)
            : accent.withValues(alpha: isDark ? 0.42 : 0.30);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (mounted) {
          setState(() => _isHovered = true);
        }
      },
      onExit: (_) {
        if (mounted) {
          setState(() => _isHovered = false);
        }
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppTransitions.fast,
          curve: AppTransitions.curveSymmetric,
          width: 40,
          height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            color: _isHovered ? hoverBg : Colors.transparent,
            border: Border.all(
              color: _isHovered ? hoverBorder : Colors.transparent,
              width: 1,
            ),
          ),
          child: Icon(widget.icon, size: 18, color: iconColor),
        ),
      ),
    );
  }
}
