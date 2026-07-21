import '../../../../core/core.dart';
import 'package:flutter/material.dart';

/// Actions available in the browser context menu.
enum BrowserContextAction {
  downloadVideo,
  copyLink,
  openNewTab,
  openExternal,
}

/// Nocturne Cinematic context menu with keyboard shortcuts and visual hierarchy.
///
/// Download action is visually emphasized with primary (crimson) color.
/// Keyboard shortcuts are displayed as trailing badges.
class BrowserLinkContextMenu {
  /// Show the context menu and return the selected action, or null if dismissed.
  static Future<BrowserContextAction?> show(
    BuildContext context, {
    required Offset position,
    required String linkUrl,
    required bool isVideoLink,
  }) async {
    final cs = Theme.of(context).colorScheme;

    final items = <PopupMenuEntry<BrowserContextAction>>[
      if (isVideoLink) ...[
        _StyledMenuItem(
          value: BrowserContextAction.downloadVideo,
          icon: Icons.download_rounded,
          label: AppLocalizations.browserMenuDownloadVideo,
          iconColor: AppColors.accentHighlight,
          labelStyle: AppTypography.buttonPrimary.copyWith(
            color: AppColors.accentHighlight,
          ),
          cs: cs,
        ),
        PopupMenuDivider(height: 1),
      ],
      _StyledMenuItem(
        value: BrowserContextAction.copyLink,
        icon: Icons.content_copy_rounded,
        label: AppLocalizations.browserMenuCopyLink,
        shortcut: '⌘C',
        cs: cs,
      ),
      _StyledMenuItem(
        value: BrowserContextAction.openNewTab,
        icon: Icons.tab_rounded,
        label: AppLocalizations.browserMenuOpenNewTab,
        shortcut: '⌘T',
        cs: cs,
      ),
      _StyledMenuItem(
        value: BrowserContextAction.openExternal,
        icon: Icons.open_in_browser_rounded,
        label: AppLocalizations.browserMenuOpenExternal,
        cs: cs,
      ),
    ];

    return showMenu<BrowserContextAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: items,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      elevation: 4,
      color: cs.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      constraints: const BoxConstraints(minWidth: 200),
    );
  }

  /// Copy URL to clipboard and show confirmation snackbar.
  static void copyToClipboard(BuildContext context, String url) {
    ClipboardService.setText(url);
    AppSnackBar.info(
      context,
      message: AppLocalizations.browserMenuLinkCopied,
      duration: const Duration(seconds: 2),
    );
  }
}

/// Styled menu item with icon, label, and optional keyboard shortcut badge.
class _StyledMenuItem extends PopupMenuItem<BrowserContextAction> {
  _StyledMenuItem({
    required BrowserContextAction value,
    required IconData icon,
    required String label,
    String? shortcut,
    Color? iconColor,
    TextStyle? labelStyle,
    required ColorScheme cs,
  }) : super(
          value: value,
          height: 38,
          child: Row(
            children: [
              Icon(icon,
                  size: 16,
                  color: iconColor ?? cs.onSurface.withValues(alpha: AppOpacity.secondary)),
              const SizedBox(width: AppSpacing.smMd),
              Expanded(
                child: Text(
                  label,
                  style: labelStyle ??
                      AppTypography.buttonSecondary.copyWith(
                        fontWeight: FontWeight.w400,
                        color: cs.onSurface.withValues(alpha: AppOpacity.nearOpaque),
                      ),
                ),
              ),
              if (shortcut != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: AppOpacity.divider),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Text(
                    shortcut,
                    style: AppTypography.compact.copyWith(
                      color: cs.onSurface.withValues(alpha: AppOpacity.scrim),
                    ),
                  ),
                ),
            ],
          ),
        );
}
