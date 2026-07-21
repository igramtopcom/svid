import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/network/backend_dtos.dart';
import '../../../../core/widgets/skeleton_list.dart';
import '../providers/assistant_providers.dart';
import 'chat_session_skeleton.dart';

/// History view — "The Case Files"
/// Full view with search, filter chips, session list (70%) + reading pane (30%)
class HistoryPanel extends ConsumerWidget {
  final void Function(String sessionId) onSessionTap;
  final VoidCallback onClose;

  const HistoryPanel({super.key, required this.onSessionTap, required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      color: isDark ? AppColors.darkBg : AppColors.lightBase,
      child: Row(
        children: [
          // Left (70%): Session list
          Expanded(
            flex: 7,
            child: Column(
              children: [
                _SearchAndFilterBar(isDark: isDark),
                Expanded(child: _SessionList(onSessionTap: onSessionTap, isDark: isDark)),
              ],
            ),
          ),
          // Right (30%): Reading pane
          _ReadingPane(isDark: isDark, onSessionTap: onSessionTap),
        ],
      ),
    );
  }
}

class _SearchAndFilterBar extends ConsumerWidget {
  final bool isDark;
  const _SearchAndFilterBar({required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentFilter = ref.watch(assistantHistoryFilterProvider);

    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.mdLg, AppSpacing.smMd, AppSpacing.mdLg, AppSpacing.smMd),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: AppOpacity.divider)
                : Colors.black.withValues(alpha: AppOpacity.divider),
          ),
        ),
      ),
      child: Row(
        children: [
          // Search field
          SizedBox(
            width: 220,
            height: 34,
            child: TextField(
              onChanged: (v) => ref.read(assistantSearchQueryProvider.notifier).state = v,
              decoration: InputDecoration(
                hintText: AppLocalizations.assistantSearchHistory,
                hintStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.metaText(context),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: AppColors.metaText(context),
                ),
                filled: true,
                fillColor: isDark ? AppColors.darkSurface1 : AppColors.lightElevated,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  borderSide: BorderSide(
                    color: isDark ? AppColors.darkElevated : AppColors.lightSurface3,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  borderSide: BorderSide(
                    color: isDark ? AppColors.darkElevated : AppColors.lightSurface3,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  borderSide: BorderSide(color: AppColors.brand, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const SizedBox(width: AppSpacing.smMd),
          // Filter chips
          _FilterChip(
            label: AppLocalizations.assistantFilterAll,
            isActive: currentFilter == AssistantHistoryFilter.all,
            isDark: isDark,
            onTap: () => ref.read(assistantHistoryFilterProvider.notifier).state =
                AssistantHistoryFilter.all,
          ),
          const SizedBox(width: AppSpacing.sm),
          _FilterChip(
            label: AppLocalizations.assistantFilterActive,
            isActive: currentFilter == AssistantHistoryFilter.active,
            isDark: isDark,
            onTap: () => ref.read(assistantHistoryFilterProvider.notifier).state =
                AssistantHistoryFilter.active,
          ),
          const SizedBox(width: AppSpacing.sm),
          _FilterChip(
            label: AppLocalizations.assistantFilterEscalated,
            isActive: currentFilter == AssistantHistoryFilter.escalated,
            isDark: isDark,
            onTap: () => ref.read(assistantHistoryFilterProvider.notifier).state =
                AssistantHistoryFilter.escalated,
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isActive,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.smMd, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.accentHighlight
              : (isDark ? AppColors.darkSurface1 : AppColors.lightElevated),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: isActive
              ? null
              : Border.all(
                  color: isDark ? AppColors.darkElevated : AppColors.lightSurface3,
                ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            color: isActive
                ? Colors.white
                : AppColors.metaText(context),
          ),
        ),
      ),
    );
  }
}

class _SessionList extends ConsumerWidget {
  final void Function(String sessionId) onSessionTap;
  final bool isDark;

  const _SessionList({required this.onSessionTap, required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(aiSessionsProvider);
    final searchQuery = ref.watch(assistantSearchQueryProvider);
    final filter = ref.watch(assistantHistoryFilterProvider);
    final selectedId = ref.watch(selectedHistorySessionProvider);
    final theme = Theme.of(context);

    return sessionsAsync.when(
      data: (sessions) {
        var filtered = sessions.where((s) {
          // Apply search
          if (searchQuery.isNotEmpty) {
            final q = searchQuery.toLowerCase();
            if (!s.title.toLowerCase().contains(q)) return false;
          }
          // Apply filter
          if (filter == AssistantHistoryFilter.active && s.status != 'active') return false;
          if (filter == AssistantHistoryFilter.escalated && s.status != 'escalated') return false;
          return true;
        }).toList();

        if (filtered.isEmpty) {
          return _buildEmptyState(context, theme);
        }

        final grouped = _groupSessions(filtered);
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          itemCount: grouped.length,
          itemBuilder: (context, index) {
            final group = grouped[index];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.mdLg, AppSpacing.md, AppSpacing.mdLg, AppSpacing.sm),
                  child: Text(
                    group.label,
                    style: AppTypography.statusBadge.copyWith(
                      letterSpacing: 0.5,
                      color: AppColors.metaText(context),
                    ),
                  ),
                ),
                ...group.sessions.map((session) => _SessionCard(
                      session: session,
                      isDark: isDark,
                      isSelected: session.id == selectedId,
                      onTap: () {
                        ref.read(selectedHistorySessionProvider.notifier).state = session.id;
                      },
                      onDoubleTap: () => onSessionTap(session.id),
                    )),
              ],
            );
          },
        );
      },
      loading: () => SkeletonList(
        itemCount: 12,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        itemBuilder: (_, __) => const ChatSessionSkeleton(),
      ),
      error: (_, __) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 32,
              color: AppColors.metaText(context),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: () => ref.invalidate(aiSessionsProvider),
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(AppLocalizations.commonRetry),
              style: TextButton.styleFrom(foregroundColor: AppColors.accentHighlight),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_outlined,
            size: 40,
            color: AppColors.metaText(context),
          ),
          const SizedBox(height: AppSpacing.smMd),
          Text(
            AppLocalizations.assistantNoSessions,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.metaText(context),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            AppLocalizations.assistantNoSessionsSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.metaText(context),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  List<_SessionGroup> _groupSessions(List<SessionListResponse> sessions) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    final todayList = <SessionListResponse>[];
    final yesterdayList = <SessionListResponse>[];
    final weekList = <SessionListResponse>[];
    final olderList = <SessionListResponse>[];

    for (final session in sessions) {
      try {
        final date = DateTime.parse(session.updatedAt);
        if (date.isAfter(today)) {
          todayList.add(session);
        } else if (date.isAfter(yesterday)) {
          yesterdayList.add(session);
        } else if (date.isAfter(weekAgo)) {
          weekList.add(session);
        } else {
          olderList.add(session);
        }
      } catch (_) {
        olderList.add(session);
      }
    }

    return [
      if (todayList.isNotEmpty) _SessionGroup(AppLocalizations.assistantToday, todayList),
      if (yesterdayList.isNotEmpty) _SessionGroup(AppLocalizations.assistantYesterday, yesterdayList),
      if (weekList.isNotEmpty) _SessionGroup(AppLocalizations.assistantThisWeek, weekList),
      if (olderList.isNotEmpty) _SessionGroup(AppLocalizations.assistantOlder, olderList),
    ];
  }
}

class _SessionGroup {
  final String label;
  final List<SessionListResponse> sessions;
  _SessionGroup(this.label, this.sessions);
}

class _SessionCard extends StatefulWidget {
  final SessionListResponse session;
  final bool isDark;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  const _SessionCard({
    required this.session,
    required this.isDark,
    required this.isSelected,
    required this.onTap,
    required this.onDoubleTap,
  });

  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEscalated = widget.session.status == 'escalated';
    final isActive = widget.session.status == 'active';

    final cardColor = widget.isSelected
        ? (widget.isDark ? AppColors.darkSurface1 : AppColors.lightElevated)
        : (_hovered
            ? (widget.isDark ? AppColors.darkSurface1 : AppColors.lightSurface2)
            : Colors.transparent);

    Color? leftAccent;
    if (isActive && !isEscalated) leftAccent = AppColors.brand;
    if (isEscalated) leftAccent = AppColors.warningAmber;

    return MouseRegion(
      onEnter: (_) { if (mounted) setState(() => _hovered = true); },
      onExit: (_) { if (mounted) setState(() => _hovered = false); },
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.smMd, vertical: AppSpacing.xxs),
          padding: const EdgeInsets.all(AppSpacing.smMd),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: widget.isSelected
                ? Border.all(
                    color: widget.isDark
                        ? AppColors.darkElevated
                        : AppColors.lightSurface3,
                  )
                : null,
          ),
          child: Row(
            children: [
              // Left accent bar
              if (leftAccent != null)
                Container(
                  width: 3,
                  height: 36,
                  margin: const EdgeInsets.only(right: AppSpacing.smMd),
                  decoration: BoxDecoration(
                    color: leftAccent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              // Icon
              Icon(
                isEscalated ? Icons.support_agent : Icons.chat_bubble_outline,
                size: 18,
                color: isEscalated
                    ? AppColors.warningAmber
                    : AppColors.muted(context),
              ),
              const SizedBox(width: AppSpacing.smMd),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.session.title.isNotEmpty
                          ? widget.session.title
                          : AppLocalizations.assistantChat,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: widget.isDark
                            ? AppColors.darkLightText
                            : AppColors.darkSurface1,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      _formatRelativeTime(widget.session.updatedAt),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.metaText(context),
                      ),
                    ),
                  ],
                ),
              ),
              // Status badge
              if (isEscalated)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
                  decoration: BoxDecoration(
                    color: AppColors.warningAmber.withValues(alpha: AppOpacity.pressed),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Text(
                    AppLocalizations.assistantEscalated,
                    style: AppTypography.compact.copyWith(
                      color: AppColors.warningAmber,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
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

/// Reading pane showing selected session preview
class _ReadingPane extends ConsumerWidget {
  final bool isDark;
  final void Function(String sessionId) onSessionTap;

  const _ReadingPane({required this.isDark, required this.onSessionTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedHistorySessionProvider);
    final theme = Theme.of(context);

    final bgColor = isDark ? AppColors.darkBg : AppColors.lightElevated;
    final textPrimary = isDark ? AppColors.darkLightText : AppColors.darkSurface1;
    final textSecondary = AppColors.metaText(context);
    final textTertiary = AppColors.metaText(context);

    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          left: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: AppOpacity.divider)
                : Colors.black.withValues(alpha: AppOpacity.divider),
          ),
        ),
      ),
      child: selectedId == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.touch_app_outlined,
                    size: 32,
                    color: textTertiary,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    AppLocalizations.assistantSelectSession,
                    style: theme.textTheme.bodySmall?.copyWith(color: textTertiary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : _ReadingPaneContent(
              sessionId: selectedId,
              isDark: isDark,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              textTertiary: textTertiary,
              onContinue: () => onSessionTap(selectedId),
            ),
    );
  }
}

class _ReadingPaneContent extends ConsumerWidget {
  final String sessionId;
  final bool isDark;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final VoidCallback onContinue;

  const _ReadingPaneContent({
    required this.sessionId,
    required this.isDark,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(aiSessionDetailProvider(sessionId));
    final theme = Theme.of(context);

    return sessionAsync.when(
      data: (session) {
        final messages = session.messages ?? [];
        return Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.title.isNotEmpty ? session.title : AppLocalizations.assistantChat,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 12, color: textTertiary),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        AppLocalizations.assistantMessageCount(messages.length),
                        style: theme.textTheme.labelSmall?.copyWith(color: textTertiary),
                      ),
                      const SizedBox(width: AppSpacing.smMd),
                      Icon(Icons.access_time, size: 12, color: textTertiary),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        _formatDate(session.createdAt),
                        style: theme.textTheme.labelSmall?.copyWith(color: textTertiary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: isDark
                  ? Colors.white.withValues(alpha: AppOpacity.divider)
                  : Colors.black.withValues(alpha: AppOpacity.divider),
            ),
            // Messages preview
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.smMd),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final msg = messages[index];
                  final isUser = msg.role == 'user';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          isUser ? Icons.person : Icons.auto_awesome,
                          size: 14,
                          color: isUser ? textSecondary : AppColors.accentHighlight,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            msg.content,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.metadata.copyWith(
                              color: textSecondary,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Continue button
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onContinue,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentHighlight,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.smMd),
                  ),
                  child: Text(AppLocalizations.assistantContinueConversation),
                ),
              ),
            ),
          ],
        );
      },
      loading: () => Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.accentHighlight,
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final diff = DateTime.now().difference(date);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return dateStr;
    }
  }
}
