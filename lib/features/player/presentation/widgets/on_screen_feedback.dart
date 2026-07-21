import 'package:flutter/material.dart';
import '../../../../core/core.dart';

/// Types of on-screen feedback
enum FeedbackType { volume, speed, screenshot, frameStep, cinemaMode }

/// Data for an on-screen feedback display
class FeedbackData {
  final FeedbackType type;
  final double? value; // 0.0-1.0 for volume, actual value for speed
  final String? label;
  final IconData? icon;

  const FeedbackData({
    required this.type,
    this.value,
    this.label,
    this.icon,
  });
}

/// On-Screen Feedback Overlay — animated visual indicators for player actions.
///
/// Shows briefly (800ms) then fades out. Displays:
/// - Volume: vertical bar with icon
/// - Speed: text badge with current speed
/// - Screenshot: camera flash effect
/// - Frame step: direction arrow with "Frame" label
/// - Cinema mode: toggle indicator
class OnScreenFeedback extends StatefulWidget {
  final FeedbackData data;
  final VoidCallback onComplete;

  const OnScreenFeedback({
    super.key,
    required this.data,
    required this.onComplete,
  });

  @override
  State<OnScreenFeedback> createState() => _OnScreenFeedbackState();
}

class _OnScreenFeedbackState extends State<OnScreenFeedback>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_controller);

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.95), weight: 30),
    ]).animate(_controller);

    _controller.forward().then((_) => widget.onComplete());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          ),
        );
      },
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    switch (widget.data.type) {
      case FeedbackType.volume:
        return _buildVolumeFeedback();
      case FeedbackType.speed:
        return _buildSpeedFeedback();
      case FeedbackType.screenshot:
        return _buildScreenshotFeedback();
      case FeedbackType.frameStep:
        return _buildFrameStepFeedback();
      case FeedbackType.cinemaMode:
        return _buildCinemaModeFeedback();
    }
  }

  Widget _buildVolumeFeedback() {
    final volume = widget.data.value ?? 0.0;
    final icon = volume == 0
        ? Icons.volume_off
        : volume < 0.5
            ? Icons.volume_down
            : Icons.volume_up;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.darkBg.withValues(alpha: AppOpacity.nearOpaque),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: AppColors.darkMuted.withValues(alpha: AppOpacity.quarter),
          width: 0.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.darkLightText, size: 28),
          const SizedBox(height: AppSpacing.sm),
          // Volume bar
          SizedBox(
            width: 4,
            height: 60,
            child: RotatedBox(
              quarterTurns: 2,
              child: Stack(
                children: [
                  // Background
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.darkMuted.withValues(alpha: AppOpacity.scrim),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Fill
                  FractionallySizedBox(
                    heightFactor: volume.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.accentHighlight,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accentHighlight.withValues(alpha: AppOpacity.medium),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${(volume * 100).round()}%',
            style: AppTypography.compact.copyWith(
              color: AppColors.darkMetaText,
              fontWeight: AppTypography.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedFeedback() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.mdLg, vertical: AppSpacing.smMd),
      decoration: BoxDecoration(
        color: AppColors.darkBg.withValues(alpha: AppOpacity.nearOpaque),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: AppColors.accentHighlight.withValues(alpha: AppOpacity.scrim),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.speed,
            color: AppColors.accentHighlight,
            size: 22,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            widget.data.label ?? '1.0x',
            style: AppTypography.appBarTitle.copyWith(
              color: AppColors.darkLightText,
              fontSize: 20,
              fontWeight: AppTypography.bold,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScreenshotFeedback() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.mdLg, vertical: AppSpacing.smMd),
      decoration: BoxDecoration(
        color: AppColors.darkBg.withValues(alpha: AppOpacity.nearOpaque),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: AppColors.accentHighlight.withValues(alpha: AppOpacity.scrim),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.camera_alt,
            color: AppColors.accentHighlight,
            size: 22,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            widget.data.label ?? 'Screenshot saved',
            style: AppTypography.fileName.copyWith(
              color: AppColors.darkLightText,
              fontWeight: AppTypography.medium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFrameStepFeedback() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.smMd),
      decoration: BoxDecoration(
        color: AppColors.darkBg.withValues(alpha: AppOpacity.nearOpaque),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: AppColors.darkMuted.withValues(alpha: AppOpacity.quarter),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            widget.data.icon ?? Icons.skip_next,
            color: AppColors.darkLightText,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Frame',
            style: AppTypography.metadata.copyWith(
              color: AppColors.darkMetaText,
              fontWeight: AppTypography.medium,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCinemaModeFeedback() {
    final isOn = widget.data.value == 1.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.mdLg, vertical: AppSpacing.smMd),
      decoration: BoxDecoration(
        color: AppColors.darkBg.withValues(alpha: AppOpacity.nearOpaque),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: isOn
              ? AppColors.brand.withValues(alpha: AppOpacity.medium)
              : AppColors.darkMuted.withValues(alpha: AppOpacity.quarter),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.theaters,
            color: isOn ? AppColors.accentHighlight : AppColors.darkMuted,
            size: 22,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            isOn ? 'Cinema Mode' : 'Cinema Off',
            style: AppTypography.fileName.copyWith(
              color: isOn ? AppColors.darkLightText : AppColors.darkMetaText,
              fontWeight: AppTypography.medium,
            ),
          ),
        ],
      ),
    );
  }
}
