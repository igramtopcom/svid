import 'package:flutter/material.dart';

/// Shared transition constants for consistent animations across the app.
///
/// Centralizes durations and curves to prevent inconsistency
/// between page transitions, control overlays, and floating panels.
abstract final class AppTransitions {
  // --- Durations ---

  /// Fast: micro-interactions, hover states (150ms)
  static const fast = Duration(milliseconds: 150);

  /// Normal: page transitions, panel show/hide (200ms)
  static const normal = Duration(milliseconds: 200);

  /// Slow: entrance animations, mini player (250ms)
  static const slow = Duration(milliseconds: 250);

  /// Controls: video/audio control bar show/hide (300ms)
  static const controls = Duration(milliseconds: 300);

  // --- Curves ---

  /// Default ease-out for most enter animations
  static const curveEnter = Curves.easeOutCubic;

  /// Default ease-in for most exit animations
  static const curveExit = Curves.easeInCubic;

  /// Subtle ease for bidirectional transitions
  static const curveSymmetric = Curves.easeInOut;

  // --- Page Transition Builder ---

  /// Fade + slide-up transition for page/section switching.
  ///
  /// Note: Do NOT re-curve the animation here. AnimatedSwitcher already
  /// applies switchInCurve/switchOutCurve before passing to transitionBuilder.
  /// Double-curving prevents the exiting widget's opacity from reaching 0,
  /// leaving old screens visible underneath (screen overlap bug on Windows).
  static Widget fadeSlideTransition(
    Widget child,
    Animation<double> animation,
  ) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  /// Standard page route using [fadeSlideTransition].
  /// Use in place of [MaterialPageRoute] for consistent app-wide transitions.
  static Route<T> pageRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: slow,
      reverseTransitionDuration: normal,
      transitionsBuilder: (_, animation, __, child) =>
          fadeSlideTransition(child, animation),
    );
  }
}
