import '../../../../core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/browser_tab.dart';
import '../providers/browser_tab_providers.dart';

/// Horizontal tab bar for the in-app browser (single-tab mode: shows the one
/// tab chip for its title + ✕; the new-tab affordances were removed — see the
/// note in build()).
class BrowserTabBar extends ConsumerWidget {
  final void Function(String tabId)? onTabSwitch;
  final void Function(String tabId)? onTabClose;
  // Kept so BrowserScreen's wiring stays intact for an easy re-enable.
  final VoidCallback? onNewTab;
  final VoidCallback? onNewIncognitoTab;

  const BrowserTabBar({
    super.key,
    this.onTabSwitch,
    this.onTabClose,
    this.onNewTab,
    this.onNewIncognitoTab,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabState = ref.watch(browserTabsProvider);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark
            ? AppColors.homeDarkBorderSubtle
            : cs.outline.withValues(alpha: AppOpacity.divider);

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.surface1(context),
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(
                left: AppSpacing.xs,
                top: AppSpacing.xs,
                bottom: AppSpacing.xs,
              ),
              itemCount: tabState.tabs.length,
              itemBuilder: (context, index) {
                final tab = tabState.tabs[index];
                return _TabChip(
                  tab: tab,
                  isActive: tab.id == tabState.activeTabId,
                  onTap: () => onTabSwitch?.call(tab.id),
                  onClose: () => onTabClose?.call(tab.id),
                );
              },
            ),
          ),
          // Single-tab mode: the new-tab / incognito button is intentionally
          // removed. Multiple tabs shared one global sniff/detection state
          // (media from tab A showing — and downloading — in tab B) and each
          // extra WebView2 instance widens the native-plugin crash surface.
          // The tab chip stays for its ✕ (close page → bookmark start page).
          // window.open/_blank links load in the current tab (onCreateWindow).
        ],
      ),
    );
  }
}

class _TabChip extends StatefulWidget {
  final BrowserTab tab;
  final bool isActive;
  final VoidCallback? onTap;
  final VoidCallback? onClose;

  const _TabChip({
    required this.tab,
    required this.isActive,
    this.onTap,
    this.onClose,
  });

  @override
  State<_TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<_TabChip> {
  bool _isHovered = false;

  static const _incognitoColor = AppColors.incognitoAccent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeSurface = AppColors.surface2(context);
    final hoverSurface =
        isDark
            ? AppColors.homeDarkCardHover
            : cs.onSurface.withValues(alpha: AppOpacity.divider);
    final outlineColor =
        isDark
            ? AppColors.homeDarkBorderSubtle
            : cs.outline.withValues(alpha: AppOpacity.divider);

    final bgColor =
        widget.isActive
            ? (widget.tab.isPrivate
                ? _incognitoColor.withValues(alpha: AppOpacity.pressed)
                : activeSurface)
            : (_isHovered ? hoverSurface : Colors.transparent);

    return Tooltip(
      message:
          widget.tab.isPrivate ? AppLocalizations.browserIncognitoTooltip : '',
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            mouseCursor: SystemMouseCursors.click,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
            splashColor: AppColors.accentHighlight.withValues(
              alpha: AppOpacity.pressed,
            ),
            highlightColor: AppColors.accentHighlight.withValues(
              alpha: AppOpacity.hover,
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              constraints: const BoxConstraints(maxWidth: 190, minWidth: 96),
              margin: const EdgeInsets.only(right: AppSpacing.xxs),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(3),
                ),
                border:
                    widget.isActive ? Border.all(color: outlineColor) : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.tab.isPrivate) ...[
                    const Icon(
                      Icons.security_rounded,
                      size: 14,
                      color: _incognitoColor,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  Flexible(
                    child: Text(
                      widget.tab.title.isNotEmpty
                          ? widget.tab.title
                          : AppLocalizations.browserNewTab,
                      style: AppTypography.metadata.copyWith(
                        color:
                            widget.tab.isPrivate
                                ? _incognitoColor
                                : (widget.isActive
                                    ? cs.onSurface
                                    : cs.onSurface.withValues(
                                      alpha: AppOpacity.strong,
                                    )),
                        fontWeight:
                            widget.isActive ? FontWeight.w600 : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: _isHovered || widget.isActive ? 1.0 : 0.0,
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: IconButton(
                        onPressed: widget.onClose,
                        icon: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: cs.onSurface.withValues(
                            alpha: AppOpacity.strong,
                          ),
                        ),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
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
