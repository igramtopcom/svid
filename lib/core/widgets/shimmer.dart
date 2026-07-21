import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../constants/app_spacing.dart';
import '../theme/app_colors.dart';

// ============================================================
// Shimmer Color System — Theme-aware for both Light & Dark modes
//
// The shimmer "highlight" must always be BRIGHTER than "bone":
//   Light mode: bone = gray, highlight = near-white (less overlay)
//   Dark mode:  bone = dark gray, highlight = lighter gray (more overlay)
//
// Uses onSurface alpha-blended onto surface, which auto-adapts to
// any theme because onSurface is always opposite contrast to surface.
// ============================================================

/// Centralized shimmer/skeleton color calculator
class ShimmerColors {
  ShimmerColors._();

  /// Skeleton bone color — the static resting color of skeleton elements
  static Color bone(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    // Dark: moderate overlay (visible on dark bg)
    // Light: stronger overlay (visible gray on white bg)
    return Color.alphaBlend(
      scheme.onSurface.withValues(alpha: isDark ? AppOpacity.hover : AppOpacity.pressed),
      scheme.surface,
    );
  }

  /// Shimmer wave highlight — the bright band that sweeps across
  /// Always BRIGHTER than bone for the "light passing over" effect
  static Color highlight(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    // Dark: stronger overlay = lighter = brighter flash
    // Light: weaker overlay = closer to white = brighter flash
    return Color.alphaBlend(
      scheme.onSurface.withValues(alpha: isDark ? AppOpacity.subtle : AppOpacity.divider),
      scheme.surface,
    );
  }
}

/// Shimmer loading effect widget — left-to-right brightness sweep
class Shimmer extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Color? baseColor;
  final Color? highlightColor;

  const Shimmer({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1500),
    this.baseColor,
    this.highlightColor,
  });

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.baseColor ?? ShimmerColors.bone(context);
    final highlight = widget.highlightColor ?? ShimmerColors.highlight(context);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Sweep the bright band from left to right
        // Gradient spans -1.0 to 2.0 (3x widget width)
        // Stops move from left edge (0) to right edge (1)
        final t = _controller.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: const Alignment(-1.0, 0.0),
              end: const Alignment(2.0, 0.0),
              colors: [base, base, highlight, base, base],
              stops: [
                0.0,
                math.max(0.0, t - 0.15),
                t,
                math.min(1.0, t + 0.15),
                1.0,
              ],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Shimmer placeholder for skeleton loading (standalone with own animation)
class ShimmerPlaceholder extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const ShimmerPlaceholder({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: ShimmerColors.bone(context),
          borderRadius: borderRadius ?? BorderRadius.circular(AppRadius.card),
        ),
      ),
    );
  }
}

/// Skeleton text line placeholder — mimics a line of text
class SkeletonLine extends StatelessWidget {
  final double? width;
  final double height;

  const SkeletonLine({
    super.key,
    this.width,
    this.height = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: ShimmerColors.bone(context),
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }
}

/// Skeleton circle placeholder — mimics avatars/icons
class SkeletonCircle extends StatelessWidget {
  final double size;

  const SkeletonCircle({
    super.key,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: ShimmerColors.bone(context),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Skeleton box placeholder — mimics thumbnails/images
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: ShimmerColors.bone(context),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Skeleton badge placeholder — mimics small status chips
class SkeletonBadge extends StatelessWidget {
  final double width;

  const SkeletonBadge({
    super.key,
    this.width = 60,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 22,
      decoration: BoxDecoration(
        color: ShimmerColors.bone(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
    );
  }
}
