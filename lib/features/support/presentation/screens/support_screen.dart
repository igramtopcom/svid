import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/brand_config.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../providers/support_providers.dart';
import '../widgets/support_quick_actions.dart';
import 'ticket_chat_screen.dart';
import 'tickets_list_screen.dart';

/// Support Center — V2 utility surface.
///
/// Layout: Header → action cards → ticket history → FAQ + health summary.
class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  static const _contentMaxWidth = 1280.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pageBg = isDark ? AppColors.homeDarkAppBg : AppColors.lightBase;

    return Scaffold(
      backgroundColor: pageBg,
      body: ColoredBox(
        color: pageBg,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding =
                constraints.maxWidth < 720 ? AppSpacing.md : AppSpacing.xl;

            return SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeroHeader(context, theme),

                        SupportQuickActions(
                          onTicketCreated:
                              () => ref.invalidate(ticketsProvider),
                        ),

                        const SizedBox(height: AppSpacing.xxxl),

                        _buildTicketHistory(context, ref, theme),

                        const SizedBox(height: AppSpacing.xxxl),

                        _buildBottomSection(context, ref, theme),

                        const SizedBox(height: AppSpacing.xxl),

                        _buildFooter(theme),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ==================== HERO HEADER ====================

  Widget _buildHeroHeader(BuildContext context, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.xxl,
        bottom: AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 5,
                height: 24,
                decoration: BoxDecoration(
                  color: AppColors.accentHighlight,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: AppSpacing.smMd),
              Expanded(
                child: Text(
                  AppLocalizations.supportCenterTitle,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Get help, report issues, and track support conversations in one place.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color:
                  isDark
                      ? AppColors.homeDarkTextSecondary
                      : theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== TICKET HISTORY ====================

  Widget _buildTicketHistory(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
  ) {
    final ticketsAsync = ref.watch(ticketsProvider);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Text(
              AppLocalizations.supportYourTickets,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed:
                  () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const TicketsListScreen(),
                    ),
                  ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accentHighlight,
                textStyle: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              child: Text(AppLocalizations.supportSeeAll),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        // Table
        ticketsAsync.when(
          data: (tickets) {
            if (tickets.isEmpty) return _buildEmptyTickets(context, theme);
            final preview = tickets.take(5).toList();
            return Container(
              decoration: BoxDecoration(
                color:
                    isDark
                        ? AppColors.homeDarkCardBg
                        : AppColors.surface1(context),
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color:
                      isDark
                          ? AppColors.homeDarkBorderSubtle
                          : AppColors.border(context),
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tableWidth =
                      constraints.maxWidth < 720 ? 720.0 : constraints.maxWidth;

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: tableWidth),
                      child: Column(
                        children: [
                          // Table header
                          Container(
                            decoration: BoxDecoration(
                              color:
                                  isDark
                                      ? AppColors.homeDarkCardHover
                                      : AppColors.surface2(context),
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(AppRadius.card),
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
                                  flex: 3,
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
                                    child: _tableHeader(theme, 'Date'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Table rows
                          ...preview.map(
                            (ticket) => _TicketRow(
                              subject: ticket.subject,
                              status: ticket.status,
                              category: ticket.category,
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
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
          loading:
              () => Container(
                height: 200,
                decoration: BoxDecoration(
                  color:
                      isDark
                          ? AppColors.homeDarkCardBg
                          : AppColors.surface1(context),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color:
                        isDark
                            ? AppColors.homeDarkBorderSubtle
                            : AppColors.border(context),
                  ),
                ),
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          error:
              (_, __) => Container(
                height: 200,
                decoration: BoxDecoration(
                  color:
                      isDark
                          ? AppColors.homeDarkCardBg
                          : AppColors.surface1(context),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color:
                        isDark
                            ? AppColors.homeDarkBorderSubtle
                            : AppColors.border(context),
                  ),
                ),
                child: Center(
                  child: TextButton.icon(
                    onPressed: () => ref.invalidate(ticketsProvider),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(AppLocalizations.commonRetry),
                  ),
                ),
              ),
        ),
      ],
    );
  }

  Widget _tableHeader(ThemeData theme, String text) {
    return Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant.withValues(
          alpha: AppOpacity.secondary,
        ),
        letterSpacing: 0,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildEmptyTickets(BuildContext context, ThemeData theme) {
    return Container(
      height: 180,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color:
            theme.brightness == Brightness.dark
                ? AppColors.homeDarkCardBg
                : AppColors.surface1(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color:
              theme.brightness == Brightness.dark
                  ? AppColors.homeDarkBorderSubtle
                  : AppColors.border(context),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 40,
            color:
                theme.brightness == Brightness.dark
                    ? AppColors.homeDarkTextMuted
                    : theme.colorScheme.outline.withValues(
                      alpha: AppOpacity.medium,
                    ),
          ),
          const SizedBox(height: AppSpacing.smMd),
          Text(
            AppLocalizations.supportNoTickets,
            style: theme.textTheme.bodyMedium?.copyWith(
              color:
                  theme.brightness == Brightness.dark
                      ? AppColors.homeDarkTextSecondary
                      : theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            AppLocalizations.supportNoTicketsSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color:
                  theme.brightness == Brightness.dark
                      ? AppColors.homeDarkTextMuted
                      : theme.colorScheme.outline.withValues(
                        alpha: AppOpacity.strong,
                      ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== BOTTOM SECTION ====================

  Widget _buildBottomSection(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 800) {
          // Wide: side-by-side (60/40)
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: _buildFaqSection(theme)),
              const SizedBox(width: AppSpacing.xxl),
              Expanded(
                flex: 4,
                child: _buildAnalyticsAndCommunity(context, ref, theme),
              ),
            ],
          );
        }
        // Narrow: stacked
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFaqSection(theme),
            const SizedBox(height: AppSpacing.xl),
            _buildAnalyticsAndCommunity(context, ref, theme),
          ],
        );
      },
    );
  }

  Widget _buildFaqSection(ThemeData theme) {
    final faqItems = [
      (
        'How do I download 4K videos?',
        'Paste the video URL, select 4K quality from the format panel, and click Download. Requires ffmpeg for some platforms.',
      ),
      (
        'Why is my download slow?',
        'Download speeds depend on the source platform\'s throttling. Try updating yt-dlp or using a different proxy in Settings.',
      ),
      (
        'How do I update yt-dlp?',
        'Go to Settings \u2192 Binaries \u2192 click Update next to yt-dlp. The app downloads the latest version automatically.',
      ),
      (
        'Can I download entire playlists?',
        'Yes! Paste a playlist URL and ${BrandConfig.current.appName} will detect all videos. You can select which ones to download from the list.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Frequently asked questions',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        ...faqItems.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _FaqItem(question: item.$1, answer: item.$2),
          ),
        ),
      ],
    );
  }

  Widget _buildAnalyticsAndCommunity(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
  ) {
    final ticketsAsync = ref.watch(ticketsProvider);
    final ticketCount = ticketsAsync.whenOrNull(data: (t) => t.length) ?? 0;

    return Column(
      children: [
        // Analytics Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color:
                theme.brightness == Brightness.dark
                    ? AppColors.homeDarkCardBg
                    : AppColors.surface1(context),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color:
                  theme.brightness == Brightness.dark
                      ? AppColors.homeDarkBorderSubtle
                      : AppColors.border(context),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Support analytics',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$ticketCount',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Total tickets',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color:
                                theme.brightness == Brightness.dark
                                    ? AppColors.homeDarkTextMuted
                                    : theme.colorScheme.onSurfaceVariant
                                        .withValues(
                                          alpha: AppOpacity.secondary,
                                        ),
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '\u2014',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Avg response',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color:
                                theme.brightness == Brightness.dark
                                    ? AppColors.homeDarkTextMuted
                                    : theme.colorScheme.onSurfaceVariant
                                        .withValues(
                                          alpha: AppOpacity.secondary,
                                        ),
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Divider(
                height: 1,
                color:
                    theme.brightness == Brightness.dark
                        ? AppColors.homeDarkBorderSubtle
                        : theme.colorScheme.outlineVariant.withValues(
                          alpha: AppOpacity.quarter,
                        ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color:
                          theme.brightness == Brightness.dark
                              ? AppColors.homeDarkCardHover
                              : AppColors.surface2(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color:
                            theme.brightness == Brightness.dark
                                ? AppColors.homeDarkBorderStrong
                                : AppColors.border(context),
                      ),
                    ),
                    child: Text(
                      'v${AppConstants.appVersion}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color:
                            theme.brightness == Brightness.dark
                                ? AppColors.homeDarkTextSecondary
                                : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.smMd),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.successGreen,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Stable',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                      color:
                          theme.brightness == Brightness.dark
                              ? AppColors.homeDarkTextSecondary
                              : theme.colorScheme.onSurfaceVariant.withValues(
                                alpha: AppOpacity.nearOpaque,
                              ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Last sync: just now',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color:
                          theme.brightness == Brightness.dark
                              ? AppColors.homeDarkTextMuted
                              : theme.colorScheme.onSurfaceVariant.withValues(
                                alpha: AppOpacity.medium,
                              ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // Community CTA
        _buildCommunityCard(context, theme),
      ],
    );
  }

  Widget _buildCommunityCard(BuildContext context, ThemeData theme) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          color:
              theme.brightness == Brightness.dark
                  ? AppColors.homeDarkCardBg
                  : AppColors.surface1(context),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color:
                theme.brightness == Brightness.dark
                    ? AppColors.homeDarkBorderSubtle
                    : AppColors.border(context),
          ),
        ),
        alignment: Alignment.bottomLeft,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color:
                    theme.brightness == Brightness.dark
                        ? AppColors.homeDarkCardHover
                        : theme.colorScheme.onSurface.withValues(
                          alpha: AppOpacity.pressed,
                        ),
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: const Icon(Icons.groups_outlined, size: 20),
            ),
            const SizedBox(width: AppSpacing.smMd),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Join the ${BrandConfig.current.appName} community',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Real-time support and community',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color:
                          theme.brightness == Brightness.dark
                              ? AppColors.homeDarkTextMuted
                              : theme.colorScheme.onSurfaceVariant.withValues(
                                alpha: AppOpacity.secondary,
                              ),
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== FOOTER ====================

  Widget _buildFooter(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color:
                theme.brightness == Brightness.dark
                    ? AppColors.homeDarkBorderSubtle
                    : theme.colorScheme.outlineVariant.withValues(
                      alpha: AppOpacity.pressed,
                    ),
          ),
        ),
      ),
      child: Center(
        child: Text(
          '${BrandConfig.current.appName} support',
          style: theme.textTheme.labelSmall?.copyWith(
            color:
                theme.brightness == Brightness.dark
                    ? AppColors.homeDarkTextMuted
                    : theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: AppOpacity.scrim,
                    ),
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

// ==================== PRIVATE WIDGETS ====================

class _TicketRow extends StatefulWidget {
  final String subject;
  final String status;
  final String category;
  final String updatedAt;
  final VoidCallback onTap;

  const _TicketRow({
    required this.subject,
    required this.status,
    required this.category,
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
          color:
              _hovered
                  ? (isDark
                      ? AppColors.homeDarkCardHover
                      : AppColors.surface2(context))
                  : Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.mdLg,
          ),
          child: Row(
            children: [
              SizedBox(width: 100, child: _StatusBadge(status: widget.status)),
              Expanded(
                flex: 3,
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
                    color:
                        isDark
                            ? AppColors.homeDarkTextSecondary
                            : theme.colorScheme.onSurfaceVariant.withValues(
                              alpha: AppOpacity.nearOpaque,
                            ),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: 100,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _formatRelativeTime(widget.updatedAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          isDark
                              ? AppColors.homeDarkTextMuted
                              : theme.colorScheme.onSurfaceVariant.withValues(
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
        AppColors.statusQueued, // Slate
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

class _FaqItem extends StatefulWidget {
  final String question;
  final String answer;

  const _FaqItem({required this.question, required this.answer});

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> {
  bool _hovered = false;
  bool _expanded = false;

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
        onTap: () => setState(() => _expanded = !_expanded),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          decoration: BoxDecoration(
            color:
                isDark ? AppColors.homeDarkCardBg : AppColors.surface1(context),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color:
                  isDark
                      ? (_hovered || _expanded
                          ? AppColors.homeDarkBorderStrong
                          : AppColors.homeDarkBorderSubtle)
                      : (_hovered || _expanded
                          ? const Color(0xFFD1D5DB)
                          : AppColors.border(context)),
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.question,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color:
                              isDark
                                  ? AppColors.darkLightText
                                  : theme.colorScheme.onSurface.withValues(
                                    alpha: AppOpacity.nearOpaque,
                                  ),
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.expand_more,
                        size: 20,
                        color:
                            _hovered || _expanded
                                ? AppColors.accentHighlight
                                : (isDark
                                    ? AppColors.homeDarkTextSecondary
                                    : theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  child: Text(
                    widget.answer,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          isDark
                              ? AppColors.homeDarkTextSecondary
                              : theme.colorScheme.onSurfaceVariant,
                      height: 1.6,
                    ),
                  ),
                ),
                crossFadeState:
                    _expanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
