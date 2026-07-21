import 'package:flutter/material.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';

class QuickActionChips extends StatelessWidget {
  final void Function(String message) onAction;

  const QuickActionChips({super.key, required this.onAction});

  static List<
    ({IconData icon, String Function() label, String Function() message})
  >
  get _actions => [
    (
      icon: Icons.build_outlined,
      label: () => AppLocalizations.assistantQuickTroubleshoot,
      message: () => AppLocalizations.assistantQuickTroubleshootMsg,
    ),
    (
      icon: Icons.high_quality_outlined,
      label: () => AppLocalizations.assistantQuickBestQuality,
      message: () => AppLocalizations.assistantQuickBestQualityMsg,
    ),
    (
      icon: Icons.playlist_add_check,
      label: () => AppLocalizations.assistantQuickBatchDownload,
      message: () => AppLocalizations.assistantQuickBatchDownloadMsg,
    ),
    (
      icon: Icons.error_outline,
      label: () => AppLocalizations.assistantQuickFailedDownload,
      message: () => AppLocalizations.assistantQuickFailedDownloadMsg,
    ),
    (
      icon: Icons.music_note_outlined,
      label: () => AppLocalizations.assistantQuickExtractAudio,
      message: () => AppLocalizations.assistantQuickExtractAudioMsg,
    ),
    (
      icon: Icons.speed,
      label: () => AppLocalizations.assistantQuickSpeedUp,
      message: () => AppLocalizations.assistantQuickSpeedUpMsg,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.smMd,
      runSpacing: AppSpacing.smMd,
      alignment: WrapAlignment.center,
      children:
          _actions.map((action) {
            return _GlassActionCard(
              icon: action.icon,
              label: action.label(),
              onTap: () => onAction(action.message()),
            );
          }).toList(),
    );
  }
}

class _GlassActionCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _GlassActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_GlassActionCard> createState() => _GlassActionCardState();
}

class _GlassActionCardState extends State<_GlassActionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final cardColor =
        _hovered ? AppColors.surface3(context) : AppColors.surface2(context);

    final borderColor =
        _hovered
            ? AppColors.accentHighlight.withValues(alpha: isDark ? 0.44 : 0.34)
            : AppColors.border(context).withValues(alpha: 0.72);

    final iconColor =
        _hovered ? AppColors.accentHighlight : AppColors.metaText(context);

    final textColor =
        _hovered
            ? Theme.of(context).colorScheme.onSurface
            : AppColors.metaText(context);

    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovered = false);
      },
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.smMd,
          ),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: borderColor),
            boxShadow:
                !isDark && _hovered
                    ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ]
                    : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 16, color: iconColor),
              const SizedBox(width: AppSpacing.sm),
              Text(
                widget.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: textColor,
                  fontWeight: _hovered ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
