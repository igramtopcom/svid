import 'package:flutter/material.dart';
import '../constants/app_spacing.dart';
import '../theme/app_colors.dart';

/// Reusable empty state widget for lists and screens.
///
/// Usage:
/// ```dart
/// AppEmptyWidget(
///   icon: Icons.download_rounded,
///   title: 'No downloads yet',
///   subtitle: 'Paste a URL to get started',
///   action: TextButton(onPressed: ..., child: Text('Add URL')),
/// );
/// ```
class AppEmptyWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  /// Optional second action placed to the right of [action] in a Row.
  final Widget? secondaryAction;

  const AppEmptyWidget({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.secondaryAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedColor = theme.colorScheme.onSurface.withValues(
      alpha: AppOpacity.medium,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final boundedHeight = constraints.hasBoundedHeight;
        final compact = boundedHeight && constraints.maxHeight < 260;
        final iconSize = compact ? 40.0 : 56.0;
        final padding = compact ? AppSpacing.md : AppSpacing.xl;
        final titleGap = compact ? AppSpacing.sm : AppSpacing.md;
        final actionGap = compact ? AppSpacing.md : AppSpacing.lg;

        final content = Padding(
          padding: EdgeInsets.all(padding),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: iconSize, color: mutedColor),
                SizedBox(height: titleGap),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: mutedColor,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: mutedColor.withValues(alpha: AppOpacity.secondary),
                      height: 1.25,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (action != null) ...[
                  SizedBox(height: actionGap),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    alignment: WrapAlignment.center,
                    children: [
                      action!,
                      if (secondaryAction != null) secondaryAction!,
                    ],
                  ),
                ],
              ],
            ),
          ),
        );

        if (!boundedHeight) {
          return Center(child: content);
        }

        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(child: content),
            ),
          ),
        );
      },
    );
  }
}
