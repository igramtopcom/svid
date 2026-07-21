import '../../../../core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/browser_history_entry.dart';
import '../../domain/services/browser_history_service.dart';
import '../providers/browser_tab_providers.dart';

/// The Investigation Log — Nocturne Cinematic history panel.
///
/// Features: date-grouped sections, platform detection with branded icons,
/// search with highlighted results, hover actions, swipe-to-delete.
class BrowserHistoryPanel extends ConsumerStatefulWidget {
  final void Function(String url)? onNavigate;

  const BrowserHistoryPanel({super.key, this.onNavigate});

  @override
  ConsumerState<BrowserHistoryPanel> createState() =>
      _BrowserHistoryPanelState();

  /// Show as a modal bottom sheet with Nocturne styling.
  static void show(
    BuildContext context, {
    void Function(String url)? onNavigate,
  }) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
      ),
      builder:
          (_) => DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            expand: false,
            builder:
                (context, scrollController) => _BrowserHistoryContent(
                  scrollController: scrollController,
                  onNavigate: onNavigate,
                ),
          ),
    );
  }
}

class _BrowserHistoryPanelState extends ConsumerState<BrowserHistoryPanel> {
  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _BrowserHistoryContent extends ConsumerStatefulWidget {
  final ScrollController scrollController;
  final void Function(String url)? onNavigate;

  const _BrowserHistoryContent({
    required this.scrollController,
    this.onNavigate,
  });

  @override
  ConsumerState<_BrowserHistoryContent> createState() =>
      _BrowserHistoryContentState();
}

class _BrowserHistoryContentState
    extends ConsumerState<_BrowserHistoryContent> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final historyService = ref.watch(browserHistoryServiceProvider);
    final entries =
        _searchQuery.isEmpty
            ? historyService.entries
            : historyService.search(_searchQuery);

    final grouped = _groupByDate(entries);

    return Column(
      children: [
        // Drag handle
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(
              top: AppSpacing.smMd,
              bottom: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: AppOpacity.subtle),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // Header with title + actions
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.mdLg,
            AppSpacing.sm,
            AppSpacing.smMd,
            AppSpacing.xs,
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.accentHighlight.withValues(
                    alpha: AppOpacity.pressed,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Icon(
                  Icons.schedule_rounded,
                  size: 15,
                  color: AppColors.accentHighlight,
                ),
              ),
              const SizedBox(width: AppSpacing.smMd),
              Text(
                AppLocalizations.browserHistory,
                style: AppTypography.appBarTitle.copyWith(
                  color: cs.onSurface,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (entries.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: AppOpacity.hover),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Text(
                    '${entries.length}',
                    style: AppTypography.compact.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withValues(alpha: AppOpacity.overlay),
                    ),
                  ),
                ),
              const Spacer(),
              if (historyService.entries.isNotEmpty)
                TextButton.icon(
                  onPressed:
                      () => _showClearConfirmation(context, historyService),
                  icon: Icon(
                    Icons.delete_sweep_rounded,
                    size: 16,
                    color: cs.error.withValues(alpha: AppOpacity.strong),
                  ),
                  label: Text(
                    AppLocalizations.browserClearHistory,
                    style: AppTypography.metadata.copyWith(
                      color: cs.error.withValues(alpha: AppOpacity.strong),
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.smMd,
                      vertical: AppSpacing.xs,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ),

        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: SizedBox(
            height: 36,
            child: TextField(
              controller: _searchController,
              style: Theme.of(context).textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: AppLocalizations.browserUrlPlaceholder,
                hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface.withValues(alpha: AppOpacity.scrim),
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: cs.onSurface.withValues(alpha: AppOpacity.scrim),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.smMd,
                  vertical: AppSpacing.sm,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: cs.surfaceContainerHigh,
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),
        ),

        // Divider
        Divider(
          height: 1,
          color: cs.onSurface.withValues(alpha: AppOpacity.divider),
        ),

        // List
        Expanded(
          child:
              entries.isEmpty
                  ? _buildEmptyState(cs)
                  : ListView.builder(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    itemCount: grouped.length,
                    itemBuilder: (context, index) {
                      final group = grouped[index];
                      // Stable per-group key — group order changes on filter/refresh.
                      return _DateGroup(
                        key: ValueKey<String>('history_group_${group.label}'),
                        label: group.label,
                        entries: group.entries,
                        onNavigate: (url) {
                          widget.onNavigate?.call(url);
                          Navigator.of(context).pop();
                        },
                        onDelete: (entry) {
                          historyService.remove(entry.id);
                          setState(() {});
                        },
                      );
                    },
                  ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: AppOpacity.divider),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Icon(
              Icons.schedule_rounded,
              size: 28,
              color: cs.onSurface.withValues(alpha: AppOpacity.subtle),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            AppLocalizations.browserNoHistory,
            style: AppTypography.fileName.copyWith(
              color: cs.onSurface.withValues(alpha: AppOpacity.medium),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Browsed pages will appear here',
            style: AppTypography.metadata.copyWith(
              color: cs.onSurface.withValues(alpha: AppOpacity.quarter),
            ),
          ),
        ],
      ),
    );
  }

  void _showClearConfirmation(
    BuildContext context,
    BrowserHistoryService service,
  ) {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: cs.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            title: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: cs.error, size: 22),
                const SizedBox(width: AppSpacing.smMd),
                Text(
                  AppLocalizations.browserClearHistory,
                  style: AppTypography.appBarTitle,
                ),
              ],
            ),
            content: Text(
              AppLocalizations.browserClearHistoryConfirm,
              style: AppTypography.platformName.copyWith(
                fontWeight: FontWeight.w400,
                color: cs.onSurface.withValues(alpha: AppOpacity.strong),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(AppLocalizations.browserBack),
              ),
              FilledButton(
                onPressed: () {
                  service.clearAll();
                  Navigator.of(ctx).pop();
                  setState(() {});
                },
                style: FilledButton.styleFrom(
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                ),
                child: Text(AppLocalizations.browserClearHistory),
              ),
            ],
          ),
    );
  }

  /// Group entries by date: Today, Yesterday, This Week, Older.
  List<_HistoryGroup> _groupByDate(List<BrowserHistoryEntry> entries) {
    if (entries.isEmpty) return [];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    final todayList = <BrowserHistoryEntry>[];
    final yesterdayList = <BrowserHistoryEntry>[];
    final weekList = <BrowserHistoryEntry>[];
    final olderList = <BrowserHistoryEntry>[];

    for (final entry in entries) {
      final date = DateTime(
        entry.visitedAt.year,
        entry.visitedAt.month,
        entry.visitedAt.day,
      );
      if (date == today) {
        todayList.add(entry);
      } else if (date == yesterday) {
        yesterdayList.add(entry);
      } else if (date.isAfter(weekAgo)) {
        weekList.add(entry);
      } else {
        olderList.add(entry);
      }
    }

    final groups = <_HistoryGroup>[];
    if (todayList.isNotEmpty) {
      groups.add(_HistoryGroup(
        label: AppLocalizations.browserHistoryToday.toUpperCase(),
        entries: todayList,
      ));
    }
    if (yesterdayList.isNotEmpty) {
      groups.add(_HistoryGroup(
        label: AppLocalizations.browserHistoryYesterday.toUpperCase(),
        entries: yesterdayList,
      ));
    }
    if (weekList.isNotEmpty) {
      groups.add(_HistoryGroup(
        label: AppLocalizations.browserHistoryThisWeek.toUpperCase(),
        entries: weekList,
      ));
    }
    if (olderList.isNotEmpty) {
      groups.add(_HistoryGroup(
        label: AppLocalizations.browserHistoryOlder.toUpperCase(),
        entries: olderList,
      ));
    }
    return groups;
  }
}

class _HistoryGroup {
  final String label;
  final List<BrowserHistoryEntry> entries;
  const _HistoryGroup({required this.label, required this.entries});
}

/// A date section with label header and list of history entries.
class _DateGroup extends StatelessWidget {
  final String label;
  final List<BrowserHistoryEntry> entries;
  final void Function(String url) onNavigate;
  final void Function(BrowserHistoryEntry entry) onDelete;

  const _DateGroup({
    super.key,
    required this.label,
    required this.entries,
    required this.onNavigate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date section header
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.mdLg,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Text(
            label,
            style: AppTypography.compact.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withValues(alpha: AppOpacity.scrim),
              letterSpacing: 0,
            ),
          ),
        ),
        ...entries.map(
          (entry) => _HistoryItem(
            entry: entry,
            onTap: () => onNavigate(entry.url),
            onDelete: () => onDelete(entry),
          ),
        ),
      ],
    );
  }
}

/// Individual history entry with platform icon, hover actions, swipe-to-delete.
class _HistoryItem extends StatefulWidget {
  final BrowserHistoryEntry entry;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const _HistoryItem({required this.entry, this.onTap, this.onDelete});

  @override
  State<_HistoryItem> createState() => _HistoryItemState();
}

class _HistoryItemState extends State<_HistoryItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final platform = _detectPlatform(widget.entry.url);
    final hasPlatformIcon =
        platform.isNotEmpty && PlatformStyleHelper.hasSvgIcon(platform);
    final platformColor =
        platform.isNotEmpty
            ? PlatformStyleHelper.getColorForPlatform(platform)
            : cs.onSurface.withValues(alpha: AppOpacity.scrim);

    return Dismissible(
      key: ValueKey(widget.entry.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => widget.onDelete?.call(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.mdLg),
        color: cs.error.withValues(alpha: AppOpacity.subtle),
        child: Icon(Icons.delete_rounded, color: cs.error, size: 20),
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            color:
                _isHovered
                    ? cs.onSurface.withValues(alpha: AppOpacity.divider)
                    : Colors.transparent,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.mdLg,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                // Platform icon
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: platformColor.withValues(alpha: AppOpacity.pressed),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Center(
                    child:
                        hasPlatformIcon
                            ? PlatformIcon(platform: platform, size: 14)
                            : Icon(
                              Icons.language_rounded,
                              size: 14,
                              color: platformColor,
                            ),
                  ),
                ),
                const SizedBox(width: AppSpacing.smMd),
                // Title + URL
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.entry.title.isNotEmpty
                            ? widget.entry.title
                            : widget.entry.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.platformName.copyWith(
                          color: cs.onSurface.withValues(
                            alpha: AppOpacity.nearOpaque,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        _cleanUrl(widget.entry.url),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.statusBadge.copyWith(
                          fontWeight: FontWeight.w400,
                          color: cs.onSurface.withValues(
                            alpha: AppOpacity.scrim,
                          ),
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // Time badge
                Text(
                  _formatRelativeTime(widget.entry.visitedAt),
                  style: AppTypography.compact.copyWith(
                    color: cs.onSurface.withValues(alpha: AppOpacity.scrim),
                  ),
                ),
                // Delete button on hover
                AnimatedOpacity(
                  opacity: _isHovered ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 120),
                  child: Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.xs),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: IconButton(
                        onPressed: widget.onDelete,
                        icon: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: cs.onSurface.withValues(
                            alpha: AppOpacity.scrim,
                          ),
                        ),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _cleanUrl(String url) {
    return url
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r'^www\.'), '');
  }

  static String _detectPlatform(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (host.contains('youtube') || host.contains('youtu.be')) return 'youtube';
    if (host.contains('facebook') || host.contains('fb.com')) return 'facebook';
    if (host.contains('instagram')) return 'instagram';
    if (host.contains('tiktok')) return 'tiktok';
    if (host.contains('twitter') || host == 'x.com') return 'x';
    if (host.contains('reddit')) return 'reddit';
    if (host.contains('pinterest')) return 'pinterest';
    if (host.contains('vimeo')) return 'vimeo';
    if (host.contains('soundcloud')) return 'soundcloud';
    if (host.contains('github')) return 'github';
    if (host.contains('bilibili')) return 'bilibili';
    if (host.contains('dailymotion')) return 'dailymotion';
    return '';
  }

  String _formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'NOW';
    if (diff.inMinutes < 60) return '${diff.inMinutes}M AGO';
    if (diff.inHours < 24) return '${diff.inHours}H AGO';
    if (diff.inDays < 7) return '${diff.inDays}D AGO';
    return '${dt.month}/${dt.day}';
  }
}
