import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Custom progress bar with rounded ends, gradient fill, and pulse animation
/// for active downloads. Replaces plain LinearProgressIndicator.
class DownloadProgressBar extends StatelessWidget {
  final double progress;
  final Color color;
  final Color? backgroundColor;
  final double height;
  final bool animate;

  const DownloadProgressBar({
    super.key,
    required this.progress,
    required this.color,
    this.backgroundColor,
    this.height = 4.0,
    this.animate = false,
  });

  @override
  Widget build(BuildContext context) {
    if (animate) {
      return _AnimatedDownloadProgressBar(
        progress: progress,
        color: color,
        backgroundColor: backgroundColor,
        height: height,
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      size: Size(double.infinity, height),
      painter: _DownloadProgressPainter(
        progress: progress.clamp(0.0, 1.0),
        color: color,
        backgroundColor: backgroundColor ??
            (isDark ? AppColors.darkElevated : AppColors.lightSurface3),
        pulseValue: 0.0,
      ),
    );
  }
}

/// Animated version with pulse effect for active downloads
class _AnimatedDownloadProgressBar extends StatefulWidget {
  final double progress;
  final Color color;
  final Color? backgroundColor;
  final double height;

  const _AnimatedDownloadProgressBar({
    required this.progress,
    required this.color,
    this.backgroundColor,
    this.height = 4.0,
  });

  @override
  State<_AnimatedDownloadProgressBar> createState() =>
      _AnimatedDownloadProgressBarState();
}

class _AnimatedDownloadProgressBarState
    extends State<_AnimatedDownloadProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return CustomPaint(
          size: Size(double.infinity, widget.height),
          painter: _DownloadProgressPainter(
            progress: widget.progress.clamp(0.0, 1.0),
            color: widget.color,
            backgroundColor: widget.backgroundColor ??
                (isDark ? AppColors.darkElevated : AppColors.lightSurface3),
            pulseValue: _pulseController.value,
          ),
        );
      },
    );
  }
}

/// CustomPainter for rounded gradient progress bar with optional pulse glow
class _DownloadProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color backgroundColor;
  final double pulseValue;

  _DownloadProgressPainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.height / 2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(radius),
    );

    // Background track
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, bgPaint);

    // Progress fill
    if (progress > 0) {
      final progressWidth = math.max(size.height, size.width * progress);
      final progressRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, progressWidth, size.height),
        Radius.circular(radius),
      );

      // Brand gradient fill: wine-red → crimson (horizontal) with vertical highlight
      final fillRect = Rect.fromLTWH(0, 0, progressWidth, size.height);
      final gradient = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          AppColors.brand, // wine-red #8D021F
          color, // status color (often crimson for active)
          Color.lerp(color, Colors.white, 0.10)!, // slight highlight at leading edge
        ],
        stops: const [0.0, 0.7, 1.0],
      );

      final fillPaint = Paint()
        ..shader = gradient.createShader(fillRect)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(progressRRect, fillPaint);

      // Vertical highlight overlay — subtle top-to-bottom luminosity
      final highlightPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: AppOpacity.pressed),
            Colors.transparent,
          ],
        ).createShader(fillRect)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(progressRRect, highlightPaint);

      // Crimson glow shadow beneath the progress bar (Nocturne Cinematic)
      final glowPaint = Paint()
        ..color = AppColors.brand.withValues(alpha: AppOpacity.medium)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawRRect(progressRRect, glowPaint);

      // Pulse glow effect (subtle brightness change for active downloads)
      if (pulseValue > 0) {
        final glowOpacity = pulseValue * 0.25;
        final pulsePaint = Paint()
          ..color = Colors.white.withValues(alpha: glowOpacity)
          ..style = PaintingStyle.fill;
        canvas.drawRRect(progressRRect, pulsePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DownloadProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.pulseValue != pulseValue ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}

/// Animated checkmark that scales up briefly when download completes
class CompletionCheckmark extends StatefulWidget {
  final double size;
  final Color color;

  const CompletionCheckmark({
    super.key,
    this.size = 20,
    this.color = AppColors.successGreen,
  });

  @override
  State<CompletionCheckmark> createState() => _CompletionCheckmarkState();
}

class _CompletionCheckmarkState extends State<CompletionCheckmark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.3), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 40),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Icon(
        Icons.check_circle,
        size: widget.size,
        color: widget.color,
      ),
    );
  }
}
