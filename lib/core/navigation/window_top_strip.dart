import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../constants/app_assets.dart';
import '../constants/app_constants.dart';
import '../core.dart';

/// Slim window header strip: brand logo on the left, a draggable middle
/// region (double-click to maximize), and window min/max/close controls on
/// the right (non-macOS). Primary navigation lives in the [LeftNavRail]; this
/// strip only carries window chrome + brand mark.
class WindowTopStrip extends StatelessWidget {
  final VoidCallback? onLogoTap;

  const WindowTopStrip({super.key, this.onLogoTap});

  static const double stripHeight = 44;

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: stripHeight,
      decoration: BoxDecoration(
        color: isDark ? AppColors.homeDarkAppBg : cs.surface,
        border: Border(
          bottom: BorderSide(
            color: cs.outlineVariant.withValues(alpha: AppOpacity.divider),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Reserve space for macOS traffic-light buttons.
          SizedBox(width: Platform.isMacOS ? 78 : AppSpacing.smMd),
          InkWell(
            onTap: onLogoTap,
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    child: Image.asset(
                      AppAssets.logo,
                      width: 22,
                      height: 22,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    AppConstants.appName,
                    style: AppTypography.appBarTitle.copyWith(
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Draggable region — fills the rest of the strip.
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: _toggleMaximize,
              child: const SizedBox.expand(),
            ),
          ),
          if (!Platform.isMacOS) ...[
            _WinButton(
              icon: Icons.minimize_rounded,
              onTap: () => windowManager.minimize(),
            ),
            _WinButton(
              icon: Icons.crop_square_rounded,
              onTap: _toggleMaximize,
            ),
            _WinButton(
              icon: Icons.close_rounded,
              isClose: true,
              onTap: () => windowManager.close(),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

class _WinButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isClose;

  const _WinButton({
    required this.icon,
    required this.onTap,
    this.isClose = false,
  });

  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hoverBg =
        widget.isClose
            ? AppColors.errorRed.withValues(alpha: AppOpacity.hover)
            : AppColors.accentHighlight.withValues(alpha: AppOpacity.hover);
    final iconColor =
        _hovered && widget.isClose
            ? AppColors.errorRed
            : AppColors.metaText(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 40,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            color: _hovered ? hoverBg : Colors.transparent,
            border: Border.all(
              color:
                  _hovered
                      ? (widget.isClose
                          ? AppColors.errorRed.withValues(
                            alpha: AppOpacity.pressed,
                          )
                          : cs.outlineVariant)
                      : Colors.transparent,
              width: 1,
            ),
          ),
          child: Icon(widget.icon, size: 18, color: iconColor),
        ),
      ),
    );
  }
}
