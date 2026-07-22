import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../constants/app_durations.dart';
import '../constants/app_spacing.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Nocturne Cinematic snackbar — command-center intelligence briefings.
///
/// Design: 3px left accent bar, tonal background tint, angular 3px radius,
/// auto-dismiss progress fuse, ghost border. Dense and sharp.
///
/// Usage:
/// ```dart
/// AppSnackBar.success(context, message: 'Download complete');
/// AppSnackBar.error(context, message: 'Failed to extract');
/// AppSnackBar.warning(context, message: 'Low disk space');
/// AppSnackBar.info(context, message: 'URL copied');
/// AppSnackBar.loading(context, message: 'Updating...');
/// ```
class AppSnackBar {
  AppSnackBar._();

  static final Map<String, ValueNotifier<_SnackProgressData>> _progressToasts =
      {};

  // ── Semantic accent colors ──────────────────────────────────────────
  static const _successColor = AppColors.successGreen;
  static const _errorColor = AppColors.errorRed;
  static const _warningColor = AppColors.warningAmber;
  static const _infoColor = Color(0xFF3B82F6);

  // ── Tinted backgrounds (dark mode) ─────────────────────────────────
  static const _successBgDark = Color(0xFF152017);
  static const _errorBgDark = Color(0xFF201515);
  static const _warningBgDark = Color(0xFF201C15);
  static const _infoBgDark = Color(0xFF151920);
  static const _premiumBgDark = Color(0xFF1F1518);

  // ── Tinted backgrounds (light mode) ────────────────────────────────
  static const _successBgLight = Color(0xFFF0FFF4);
  static const _errorBgLight = Color(0xFFFFF0F0);
  static const _warningBgLight = Color(0xFFFFFBF0);
  static const _infoBgLight = Color(0xFFF0F4FF);
  static const _premiumBgLight = Color(0xFFFFF0F3);

  /// Show a success notification.
  static void success(
    BuildContext context, {
    required String message,
    SnackBarAction? action,
    Duration? duration,
  }) {
    _show(
      context,
      message: message,
      icon: Icons.check_circle_rounded,
      accentColor: _successColor,
      action: action,
      duration: duration,
    );
  }

  /// Show an error notification.
  static void error(
    BuildContext context, {
    required String message,
    SnackBarAction? action,
    Duration? duration,
  }) {
    _show(
      context,
      message: message,
      icon: Icons.error_rounded,
      accentColor: _errorColor,
      action: action,
      duration: duration ?? const Duration(seconds: 4),
    );
  }

  /// Show a warning notification.
  static void warning(
    BuildContext context, {
    required String message,
    SnackBarAction? action,
    Duration? duration,
  }) {
    _show(
      context,
      message: message,
      icon: Icons.warning_rounded,
      accentColor: _warningColor,
      action: action,
      duration: duration,
    );
  }

  /// Show an info notification.
  static void info(
    BuildContext context, {
    required String message,
    SnackBarAction? action,
    Duration? duration,
  }) {
    _show(
      context,
      message: message,
      icon: Icons.info_rounded,
      accentColor: _infoColor,
      action: action,
      duration: duration,
    );
  }

  /// Show an interactive prompt (resume, undo, etc) — crimson accent, on-brand.
  static void prompt(
    BuildContext context, {
    required String message,
    IconData? icon,
    SnackBarAction? action,
    Duration? duration,
  }) {
    _show(
      context,
      message: message,
      icon: icon ?? Icons.history_rounded,
      accentColor: AppColors.accentHighlight,
      action: action,
      duration: duration ?? const Duration(seconds: 6),
    );
  }

  /// Show a loading notification with spinner.
  static void loading(BuildContext context, {required String message}) {
    _show(
      context,
      message: message,
      icon: null,
      accentColor: AppColors.accentHighlight,
      showSpinner: true,
      duration: const Duration(minutes: 5),
    );
  }

  /// Show a premium upsell notification.
  static void premium(
    BuildContext context, {
    required String message,
    SnackBarAction? action,
    Duration? duration,
  }) {
    _show(
      context,
      message: message,
      icon: Icons.workspace_premium_rounded,
      accentColor: AppColors.accentHighlight,
      isPremium: true,
      action: action,
      duration: duration ?? const Duration(seconds: 4),
    );
  }

  /// Dismiss current SnackBar.
  static void dismiss(BuildContext context) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  /// Show or update a long-running progress notification.
  ///
  /// Reusing the same [id] updates the existing toast instead of stacking or
  /// flickering a new SnackBar on every progress tick.
  static void progress(
    BuildContext context, {
    required String id,
    required String message,
    double? value,
    SnackBarAction? action,
  }) {
    final clampedValue = value?.clamp(0.0, 1.0).toDouble();
    final existing = _progressToasts[id];
    final data = _SnackProgressData(
      message: message,
      value: clampedValue,
      accentColor: AppColors.accentHighlight,
      actionLabel: action?.label,
      onAction: action?.onPressed,
    );

    if (existing != null) {
      existing.value = data;
      return;
    }

    final notifier = ValueNotifier<_SnackProgressData>(data);
    _progressToasts[id] = notifier;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.darkElevated : AppColors.lightSurface3;
    final textColor = isDark ? AppColors.darkLightText : AppColors.darkBase;
    final mutedColor =
        isDark ? AppColors.darkMetaText : AppColors.lightMetaText;
    final borderColor =
        isDark
            ? Colors.white.withValues(alpha: AppOpacity.divider)
            : Colors.black.withValues(alpha: AppOpacity.hover);
    final messenger = ScaffoldMessenger.of(context);

    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        // Cap the width and anchor bottom-right so the progress toast reads as
        // a compact floating card instead of a full-window bar spanning under
        // the nav rail and past the content box.
        content: Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: _ProgressSnackContent(
              notifier: notifier,
              textColor: textColor,
              mutedColor: mutedColor,
              borderColor: borderColor,
              bgColor: bgColor,
              isDark: isDark,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        padding: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(),
        margin: const EdgeInsets.only(
          left: AppSpacing.md,
          right: AppSpacing.md,
          bottom: AppSpacing.md,
        ),
        duration: const Duration(hours: 1),
        dismissDirection: DismissDirection.horizontal,
      ),
    );

    controller.closed.whenComplete(() {
      final current = _progressToasts[id];
      if (current == notifier) {
        _progressToasts.remove(id);
        notifier.dispose();
      }
    });
  }

  static void completeProgress(
    BuildContext context, {
    required String id,
    required String message,
    bool success = true,
  }) {
    final existing = _progressToasts[id];
    if (existing == null) {
      if (success) {
        AppSnackBar.success(context, message: message);
      } else {
        AppSnackBar.warning(context, message: message);
      }
      return;
    }

    existing.value = _SnackProgressData(
      message: message,
      value: 1.0,
      accentColor: success ? _successColor : _warningColor,
      done: true,
    );

    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (context.mounted && _progressToasts[id] == existing) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    });
  }

  // ── Internal ────────────────────────────────────────────────────────

  static Color _bgForAccent(Color accent, bool isDark) {
    if (accent == _successColor) {
      return isDark ? _successBgDark : _successBgLight;
    }
    if (accent == _errorColor) return isDark ? _errorBgDark : _errorBgLight;
    if (accent == _warningColor) {
      return isDark ? _warningBgDark : _warningBgLight;
    }
    if (accent == _infoColor) return isDark ? _infoBgDark : _infoBgLight;
    // Premium / loading / default
    return isDark ? _premiumBgDark : _premiumBgLight;
  }

  static void _show(
    BuildContext context, {
    required String message,
    required IconData? icon,
    required Color accentColor,
    SnackBarAction? action,
    Duration? duration,
    bool showSpinner = false,
    bool isPremium = false,
  }) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveDuration = duration ?? AppDurations.snackbarDuration;
    final bgColor =
        showSpinner
            ? (isDark ? AppColors.darkElevated : AppColors.lightSurface3)
            : _bgForAccent(accentColor, isDark);
    final textColor = isDark ? AppColors.darkLightText : AppColors.darkBase;
    final mutedColor =
        isDark ? AppColors.darkMetaText : AppColors.lightMetaText;
    final borderColor =
        isDark
            ? Colors.white.withValues(alpha: AppOpacity.divider)
            : Colors.black.withValues(alpha: AppOpacity.hover);

    final messenger = ScaffoldMessenger.of(context);

    final snackBar = SnackBar(
      content: _NocturneSnackContent(
        message: message,
        icon: icon,
        accentColor: accentColor,
        textColor: textColor,
        mutedColor: mutedColor,
        borderColor: borderColor,
        bgColor: bgColor,
        showSpinner: showSpinner,
        isPremium: isPremium,
        isDark: isDark,
        duration: effectiveDuration,
        actionLabel: action?.label,
        onAction:
            action == null
                ? null
                : () {
                  messenger.hideCurrentSnackBar();
                  action.onPressed();
                },
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      padding: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(),
      margin: const EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        bottom: AppSpacing.md,
      ),
      duration: effectiveDuration,
      dismissDirection: DismissDirection.horizontal,
    );

    messenger.showSnackBar(snackBar);
  }
}

class _SnackProgressData {
  final String message;
  final double? value;
  final Color accentColor;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool done;

  const _SnackProgressData({
    required this.message,
    required this.value,
    required this.accentColor,
    this.actionLabel,
    this.onAction,
    this.done = false,
  });

  bool get hasAction => actionLabel != null && onAction != null;
}

class _ProgressSnackContent extends StatelessWidget {
  final ValueListenable<_SnackProgressData> notifier;
  final Color textColor;
  final Color mutedColor;
  final Color borderColor;
  final Color bgColor;
  final bool isDark;

  const _ProgressSnackContent({
    required this.notifier,
    required this.textColor,
    required this.mutedColor,
    required this.borderColor,
    required this.bgColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_SnackProgressData>(
      valueListenable: notifier,
      builder: (context, data, _) {
        final percent =
            data.value == null
                ? null
                : '${(data.value! * 100).round().clamp(0, 100)}%';

        return Container(
          constraints: const BoxConstraints(maxWidth: 560, minHeight: 54),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IntrinsicHeight(
                child: Row(
                  children: [
                    Container(width: 3, color: data.accentColor),
                    const SizedBox(width: AppSpacing.smMd),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      child:
                          data.done
                              ? Icon(
                                Icons.check_circle_rounded,
                                color: data.accentColor,
                                size: 18,
                              )
                              : SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  value: data.value,
                                  strokeWidth: 2,
                                  color: data.accentColor,
                                ),
                              ),
                    ),
                    const SizedBox(width: AppSpacing.smMd),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.smMd,
                        ),
                        child: Text(
                          data.message,
                          style: AppTypography.platformName.copyWith(
                            color: textColor,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (percent != null)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.smMd),
                        child: Text(
                          percent,
                          style: AppTypography.compact.copyWith(
                            color: mutedColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (data.hasAction)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: _InlineActionButton(
                          label: data.actionLabel!,
                          onPressed: data.onAction!,
                          accentColor: AppColors.accentHighlight,
                          isDark: isDark,
                        ),
                      ),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                ),
              ),
              LinearProgressIndicator(
                value: data.value,
                minHeight: 2,
                backgroundColor: data.accentColor.withValues(
                  alpha: AppOpacity.hover,
                ),
                valueColor: AlwaysStoppedAnimation<Color>(data.accentColor),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The actual visual content of the Nocturne Cinematic snackbar.
/// Uses a custom container instead of SnackBar's default styling.
class _NocturneSnackContent extends StatefulWidget {
  final String message;
  final IconData? icon;
  final Color accentColor;
  final Color textColor;
  final Color mutedColor;
  final Color borderColor;
  final Color bgColor;
  final bool showSpinner;
  final bool isPremium;
  final bool isDark;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _NocturneSnackContent({
    required this.message,
    required this.icon,
    required this.accentColor,
    required this.textColor,
    required this.mutedColor,
    required this.borderColor,
    required this.bgColor,
    required this.showSpinner,
    required this.isPremium,
    required this.isDark,
    required this.duration,
    this.actionLabel,
    this.onAction,
  });

  bool get hasAction => actionLabel != null && onAction != null;

  @override
  State<_NocturneSnackContent> createState() => _NocturneSnackContentState();
}

class _NocturneSnackContentState extends State<_NocturneSnackContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    // Auto-dismiss progress fuse animation
    _progressController = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..forward();
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 520, minHeight: 48),
      decoration: BoxDecoration(
        color: widget.bgColor,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: widget.borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Main content row
          IntrinsicHeight(
            child: Row(
              children: [
                // Left accent bar — the signature element
                Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: widget.accentColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(3),
                      bottomLeft: Radius.circular(3),
                    ),
                  ),
                ),

                const SizedBox(width: AppSpacing.smMd),

                // Icon or spinner
                if (widget.showSpinner)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: widget.accentColor,
                      ),
                    ),
                  )
                else if (widget.icon != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    child: Icon(
                      widget.icon,
                      color: widget.accentColor,
                      size: 18,
                    ),
                  ),

                const SizedBox(width: AppSpacing.smMd),

                // Message text
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.smMd,
                    ),
                    child: Text(
                      widget.message,
                      style: AppTypography.platformName.copyWith(
                        color: widget.textColor,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),

                // Inline action pill — angular, crimson accent, part of the card
                if (widget.hasAction)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: _InlineActionButton(
                      label: widget.actionLabel!,
                      onPressed: widget.onAction!,
                      accentColor: AppColors.accentHighlight,
                      isDark: widget.isDark,
                    ),
                  ),

                // Premium glow badge (only for premium variant)
                if (widget.isPremium && !widget.hasAction)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.smMd),
                    child: Text(
                      'PRO',
                      style: AppTypography.mini.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: AppColors.accentHighlight,
                      ),
                    ),
                  ),

                const SizedBox(width: AppSpacing.xs),
              ],
            ),
          ),

          // Bottom progress fuse — crimson line burning down
          if (widget.duration.inMinutes < 1)
            AnimatedBuilder(
              animation: _progressController,
              builder: (context, _) {
                return Container(
                  height: 2,
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: 1.0 - _progressController.value,
                    child: Container(
                      decoration: BoxDecoration(
                        color: widget.accentColor.withValues(
                          alpha: AppOpacity.secondary,
                        ),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Angular pill action button rendered inline inside the Nocturne snackbar.
/// Crimson outline + tinted fill, matches the player/cinematic aesthetic.
class _InlineActionButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final Color accentColor;
  final bool isDark;

  const _InlineActionButton({
    required this.label,
    required this.onPressed,
    required this.accentColor,
    required this.isDark,
  });

  @override
  State<_InlineActionButton> createState() => _InlineActionButtonState();
}

class _InlineActionButtonState extends State<_InlineActionButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final bg =
        _hovering
            ? widget.accentColor.withValues(alpha: AppOpacity.pressed)
            : widget.accentColor.withValues(alpha: AppOpacity.hover);
    final border = widget.accentColor.withValues(
      alpha: _hovering ? AppOpacity.strong : AppOpacity.quarter,
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.smMd,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border, width: 1),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            widget.label,
            style: AppTypography.compact.copyWith(
              color: widget.accentColor,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}
