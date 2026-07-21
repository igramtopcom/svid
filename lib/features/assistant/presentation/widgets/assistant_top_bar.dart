import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';

class AssistantTopBar extends StatelessWidget {
  final VoidCallback onHistoryTap;
  final VoidCallback? onNewChat;
  final VoidCallback? onBack;
  final String? sessionTitle;
  final Widget? trailing;
  final bool isHistoryView;

  const AssistantTopBar({
    super.key,
    required this.onHistoryTap,
    this.onNewChat,
    this.onBack,
    this.sessionTitle,
    this.trailing,
    this.isHistoryView = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isInChat = sessionTitle != null;
    final borderColor =
        isDark
            ? AppColors.homeDarkBorderStrong
            : AppColors.border(context).withValues(alpha: 0.76);

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.smMd),
      decoration: BoxDecoration(
        color: isDark ? AppColors.homeDarkCardBg : AppColors.surface1(context),
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          // Left: back button or logo
          if (isInChat || isHistoryView)
            IconButton(
              icon: Icon(
                Icons.arrow_back,
                size: 20,
                color: AppColors.metaText(context),
              ),
              tooltip: AppLocalizations.commonClose,
              onPressed: onBack,
            )
          else ...[
            const SizedBox(width: AppSpacing.sm),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.accentHighlight.withValues(
                  alpha: isDark ? 0.16 : 0.12,
                ),
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: AppColors.accentHighlight.withValues(
                    alpha: isDark ? 0.42 : 0.32,
                  ),
                ),
              ),
              child: Icon(
                Icons.auto_awesome,
                size: 14,
                color: AppColors.accentHighlight,
              ),
            ),
            const SizedBox(width: AppSpacing.smMd),
            Text(
              '${AppConstants.appName} AI',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],

          const Spacer(),

          // Center: session title (chat mode)
          if (isInChat)
            Expanded(
              flex: 3,
              child: Text(
                sessionTitle!,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else if (isHistoryView)
            Expanded(
              flex: 3,
              child: Text(
                AppLocalizations.assistantChatHistory,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
              ),
            ),

          const Spacer(),

          // Right: trailing or action buttons
          if (trailing != null)
            trailing!
          else if (!isInChat && !isHistoryView)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionIconButton(
                  icon: Icons.add_circle_outline,
                  tooltip: AppLocalizations.assistantNewChat,
                  onPressed: onNewChat,
                  isDark: isDark,
                ),
                _ActionIconButton(
                  icon: Icons.history,
                  tooltip: AppLocalizations.assistantChatHistory,
                  onPressed: onHistoryTap,
                  isDark: isDark,
                ),
              ],
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool isDark;

  const _ActionIconButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20, color: AppColors.metaText(context)),
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }
}
