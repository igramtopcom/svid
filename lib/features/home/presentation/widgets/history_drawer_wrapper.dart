import 'package:flutter/material.dart';
import '../../../../core/core.dart';
import '../../../downloads/domain/entities/video_info.dart';
import '../../../downloads/presentation/widgets/extraction_history_drawer.dart';

/// History drawer wrapper with smooth slide animation.
/// Uses AnimatedBuilder for proper clipping without overflow errors.
class HistoryDrawerWrapper extends StatefulWidget {
  final bool isOpen;
  final void Function(VideoInfo videoInfo) onItemTap;
  final VoidCallback onClose;

  const HistoryDrawerWrapper({
    super.key,
    required this.isOpen,
    required this.onItemTap,
    required this.onClose,
  });

  @override
  State<HistoryDrawerWrapper> createState() => _HistoryDrawerWrapperState();
}

class _HistoryDrawerWrapperState extends State<HistoryDrawerWrapper>
    with SingleTickerProviderStateMixin {
  static const double _drawerWidth = AppConstants.historyDrawerWidth;
  static const Duration _animationDuration = AppDurations.drawerAnimation;

  late AnimationController _controller;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _animationDuration,
    );
    _slideAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    if (widget.isOpen) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(HistoryDrawerWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen != oldWidget.isOpen) {
      if (widget.isOpen) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _slideAnimation,
      builder: (context, child) {
        // Don't render anything when fully closed for performance
        if (_slideAnimation.value == 1.0 && !widget.isOpen) {
          return const SizedBox.shrink();
        }

        // Slide in from the right edge (1.0 = fully off-screen right,
        // 0.0 = docked). No clip — lets the panel's left drop-shadow show.
        return FractionalTranslation(
          translation: Offset(_slideAnimation.value, 0),
          child: child,
        );
      },
      child: SizedBox(
        width: _drawerWidth,
        child: ExtractionHistoryDrawer(
          onItemTap: widget.onItemTap,
          onClose: widget.onClose,
        ),
      ),
    );
  }
}
