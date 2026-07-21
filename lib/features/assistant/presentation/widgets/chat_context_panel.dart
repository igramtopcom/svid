import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/network/backend_dtos.dart';
import '../providers/assistant_providers.dart';

/// Right-side context panel for chat view (340px)
/// Shows session info, suggested actions, escalation link, related sessions
class ChatContextPanel extends ConsumerWidget {
  final String sessionId;
  final VoidCallback? onEscalate;

  const ChatContextPanel({super.key, required this.sessionId, this.onEscalate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(aiSessionDetailProvider(sessionId));
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? AppColors.darkBg : AppColors.lightSurface2;
    final cardColor = isDark ? AppColors.darkSurface1 : AppColors.lightElevated;
    final borderColor =
        isDark
            ? Colors.white.withValues(alpha: AppOpacity.divider)
            : Colors.black.withValues(alpha: AppOpacity.divider);
    final textPrimary =
        isDark ? AppColors.darkLightText : AppColors.darkSurface1;
    final textSecondary = AppColors.muted(context);
    final textTertiary = AppColors.metaText(context);

    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(left: BorderSide(color: borderColor)),
      ),
      child: sessionAsync.when(
        data:
            (session) => _buildContent(
              context,
              session: session,
              cardColor: cardColor,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              textTertiary: textTertiary,
              isDark: isDark,
              theme: theme,
            ),
        loading:
            () => Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accentHighlight,
              ),
            ),
        error: (_, __) => const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context, {
    required SessionResponse session,
    required Color cardColor,
    required Color textPrimary,
    required Color textSecondary,
    required Color textTertiary,
    required bool isDark,
    required ThemeData theme,
  }) {
    final messageCount = session.messages?.length ?? 0;
    final isEscalated = session.status == 'escalated';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Session Info Card
          _SectionLabel(
            text: AppLocalizations.assistantSessionInfo,
            color: textTertiary,
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border:
                  isDark
                      ? null
                      : Border.all(
                        color: Colors.black.withValues(
                          alpha: AppOpacity.divider,
                        ),
                      ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Topic
                Text(
                  session.title.isNotEmpty
                      ? session.title
                      : AppLocalizations.assistantChat,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.smMd),
                // Metadata
                _MetadataRow(
                  icon: Icons.chat_bubble_outline,
                  label: AppLocalizations.assistantMessageCount(messageCount),
                  color: textSecondary,
                ),
                const SizedBox(height: AppSpacing.sm),
                _MetadataRow(
                  icon: Icons.access_time,
                  label: _formatDate(session.createdAt),
                  color: textSecondary,
                ),
                if (isEscalated) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _MetadataRow(
                    icon: Icons.support_agent,
                    label: AppLocalizations.assistantEscalated,
                    color: AppColors.warningAmber,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // Suggested Actions
          _SectionLabel(
            text: AppLocalizations.assistantSuggestedActions,
            color: textTertiary,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _SuggestedChip(
                label: AppLocalizations.assistantQuickBestQuality,
                isDark: isDark,
              ),
              _SuggestedChip(
                label: AppLocalizations.assistantQuickTroubleshoot,
                isDark: isDark,
              ),
              _SuggestedChip(
                label: AppLocalizations.assistantQuickSpeedUp,
                isDark: isDark,
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),

          // Escalation
          if (!isEscalated && onEscalate != null) ...[
            _SectionLabel(
              text: AppLocalizations.assistantEscalate,
              color: textTertiary,
            ),
            const SizedBox(height: AppSpacing.sm),
            InkWell(
              onTap: onEscalate,
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.smMd),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border:
                      isDark
                          ? null
                          : Border.all(
                            color: Colors.black.withValues(
                              alpha: AppOpacity.divider,
                            ),
                          ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.support_agent,
                      size: 18,
                      color: AppColors.warningAmber,
                    ),
                    const SizedBox(width: AppSpacing.smMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.assistantEscalateTitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                          Text(
                            AppLocalizations.assistantEscalateDescription,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: textTertiary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 18, color: textTertiary),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return dateStr;
    }
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color color;

  const _SectionLabel({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppTypography.statusBadge.copyWith(
        letterSpacing: 0.5,
        color: color,
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MetadataRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.metadata.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _SuggestedChip extends StatelessWidget {
  final String label;
  final bool isDark;

  const _SuggestedChip({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.smMd,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface1 : AppColors.lightSurface2,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: isDark ? AppColors.darkElevated : AppColors.lightSurface3,
        ),
      ),
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: AppColors.muted(context)),
      ),
    );
  }
}
