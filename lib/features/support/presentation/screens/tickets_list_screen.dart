import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/skeleton_list.dart';
import '../providers/support_providers.dart';
import '../widgets/create_ticket_dialog.dart';
import '../widgets/ticket_skeleton.dart';
import 'ticket_chat_screen.dart';

class TicketsListScreen extends ConsumerWidget {
  const TicketsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(ticketsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pageBg = isDark ? AppColors.homeDarkAppBg : AppColors.lightBase;

    return Scaffold(
      backgroundColor: pageBg,
      body: Column(
        children: [
          Container(
            height: 56,
            padding: EdgeInsets.only(
              left: Platform.isMacOS ? 78 : 8,
              right: 16,
            ),
            decoration: BoxDecoration(
              color:
                  isDark
                      ? AppColors.homeDarkCardBg
                      : AppColors.surface1(context),
              border: Border(
                bottom: BorderSide(
                  color:
                      isDark
                          ? AppColors.homeDarkBorderSubtle
                          : AppColors.border(context),
                ),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  AppLocalizations.supportYourTickets,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed:
                      () => showDialog(
                        context: context,
                        builder:
                            (_) => CreateTicketDialog(
                              onCreated: () => ref.invalidate(ticketsProvider),
                            ),
                      ),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(
                    AppLocalizations.supportNewTicket,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentHighlight,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.smMd,
                    ),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: ColoredBox(
              color: pageBg,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: ticketsAsync.when(
                    data: (tickets) {
                      if (tickets.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.inbox_outlined,
                                size: 48,
                                color: theme.colorScheme.outline.withValues(
                                  alpha: AppOpacity.scrim,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                AppLocalizations.supportNoTickets,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                AppLocalizations.supportNoTicketsSubtitle,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return Column(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color:
                                  isDark
                                      ? AppColors.homeDarkCardBg
                                      : AppColors.surface1(context),
                              border: Border(
                                bottom: BorderSide(
                                  color:
                                      isDark
                                          ? AppColors.homeDarkBorderSubtle
                                          : AppColors.border(context),
                                ),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.md,
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 100,
                                  child: _tableHeader(theme, 'Status'),
                                ),
                                Expanded(
                                  flex: 4,
                                  child: _tableHeader(theme, 'Subject'),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: _tableHeader(theme, 'Category'),
                                ),
                                SizedBox(
                                  width: 100,
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: _tableHeader(theme, 'Updated'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Ticket rows
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.sm,
                              ),
                              itemCount: tickets.length,
                              itemBuilder: (context, index) {
                                final ticket = tickets[index];
                                // Stable per-ticket key — _TicketRow has hover State
                                // that must not get rebound on list mutations.
                                return _TicketRow(
                                  key: ValueKey<String>(
                                    'ticket_row_${ticket.id}',
                                  ),
                                  subject: ticket.subject,
                                  category: ticket.category,
                                  status: ticket.status,
                                  updatedAt: ticket.updatedAt,
                                  onTap:
                                      () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder:
                                              (_) => TicketChatScreen(
                                                ticketId: ticket.id,
                                              ),
                                        ),
                                      ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                    loading:
                        () => SkeletonList(
                          itemCount: 8,
                          padding: const EdgeInsets.all(AppSpacing.mdLg),
                          itemBuilder: (_, __) => const TicketSkeleton(),
                        ),
                    error:
                        (error, _) => Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.cloud_off,
                                size: 40,
                                color: theme.colorScheme.error.withValues(
                                  alpha: AppOpacity.secondary,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.smMd),
                              Text(
                                AppLocalizations.supportLoadError,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              TextButton.icon(
                                onPressed:
                                    () => ref.invalidate(ticketsProvider),
                                icon: const Icon(Icons.refresh, size: 18),
                                label: Text(AppLocalizations.commonRetry),
                              ),
                            ],
                          ),
                        ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeader(ThemeData theme, String text) {
    return Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant.withValues(
          alpha: AppOpacity.overlay,
        ),
        letterSpacing: 0,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _TicketRow extends StatefulWidget {
  final String subject;
  final String category;
  final String status;
  final String updatedAt;
  final VoidCallback onTap;

  const _TicketRow({
    super.key,
    required this.subject,
    required this.category,
    required this.status,
    required this.updatedAt,
    required this.onTap,
  });

  @override
  State<_TicketRow> createState() => _TicketRowState();
}

class _TicketRowState extends State<_TicketRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
          decoration: BoxDecoration(
            color:
                _hovered
                    ? (isDark
                        ? AppColors.homeDarkCardHover
                        : AppColors.surface2(context))
                    : (isDark
                        ? AppColors.homeDarkCardBg
                        : AppColors.surface1(context)),
            border: Border(
              bottom: BorderSide(
                color:
                    isDark
                        ? AppColors.homeDarkBorderSubtle
                        : AppColors.border(context),
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              SizedBox(width: 100, child: _StatusBadge(status: widget.status)),
              Expanded(
                flex: 4,
                child: Text(
                  widget.subject,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  _formatCategory(widget.category),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: AppOpacity.nearOpaque,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 100,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _formatRelativeTime(widget.updatedAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: AppOpacity.secondary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatCategory(String category) {
    return category
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  String _formatRelativeTime(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final diff = DateTime.now().difference(date);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${date.month}/${date.day}/${date.year}';
    } catch (_) {
      return dateStr;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (label, statusColor) = switch (status) {
      'open' => (AppLocalizations.supportStatusOpen, AppColors.accentHighlight),
      'in_progress' => (
        AppLocalizations.supportStatusInProgress,
        AppColors.statusInProgress,
      ),
      'waiting_for_customer' => (
        AppLocalizations.supportStatusWaiting,
        AppColors.warningAmber,
      ),
      'resolved' => (
        AppLocalizations.supportStatusResolved,
        AppColors.successGreen,
      ),
      'closed' => (
        AppLocalizations.supportStatusClosed,
        AppColors.statusQueued,
      ),
      _ => (status.replaceAll('_', ' '), AppColors.statusQueued),
    };

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: isDark ? 0.18 : 0.12),
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(
            color: statusColor.withValues(alpha: isDark ? 0.34 : 0.26),
          ),
        ),
        child: Text(
          label,
          style: AppTypography.compact.copyWith(
            color: statusColor,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}
