import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../core.dart';

/// Slim window header over the content area: a draggable region (double-click
/// to maximize) and window min/max/close controls (non-macOS). The brand logo
/// and navigation live in the [LeftNavRail]; this strip is pure window chrome.
class WindowTopStrip extends StatelessWidget {
  const WindowTopStrip({super.key});

  static const double stripHeight = 40;

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: stripHeight,
      child: Row(
        children: [
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
            _WinButton(icon: Icons.crop_square_rounded, onTap: _toggleMaximize),
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
          height: 30,
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
