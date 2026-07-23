import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../providers/recent_searches_provider.dart';
import '../providers/youtube_trending_provider.dart';
import 'youtube_search_result_item.dart';

/// Discovery view — landing state of the Explore tab.
/// Sections: Category tabs → Recent Searches → Trending.
class YouTubeDiscoveryView extends ConsumerWidget {
  final void Function(String query) onSearch;

  /// Download a real trending video in place (wired to the Explore
  /// "download in place" flow). Null falls back to the curated topic grid.
  final void Function(String url)? onVideoDownload;

  const YouTubeDiscoveryView({
    super.key,
    required this.onSearch,
    this.onVideoDownload,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Category quick-tabs (horizontal scrollable)
              const SizedBox(height: AppSpacing.sm),
              _CategoryTabs(onSearch: onSearch),
              const SizedBox(height: AppSpacing.md),

              // Recent Searches
              _RecentSearchesSection(onSearch: onSearch),
              const SizedBox(height: AppSpacing.lg),

              // Trending Now — real YouTube trending for the user's region,
              // with a graceful fallback to curated topic shortcuts.
              _TrendingSection(
                onSearch: onSearch,
                onVideoDownload: onVideoDownload,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscoverySurface extends StatelessWidget {
  final Widget header;
  final Widget child;

  const _DiscoverySurface({required this.header, required this.child});

  @override
  Widget build(BuildContext context) {
    // No surrounding card/border — sections are just a heading + grid on the
    // page background. The previous box-in-box (section card wrapping item
    // cards) chopped the screen into a busy grid of lines, especially in dark
    // mode. The item tiles carry their own subtle separation now.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [header, const SizedBox(height: AppSpacing.smMd), child],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.sm),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Category Quick-Tabs (horizontal, per Stitch design)
// =============================================================================

class _CategoryTabs extends StatelessWidget {
  final void Function(String) onSearch;

  const _CategoryTabs({required this.onSearch});

  static const _tabs = [
    _TabItem('Music', Icons.music_note_rounded, AppColors.lightStatusFailed),
    _TabItem('Gaming', Icons.sports_esports_rounded, Color(0xFF7C3AED)),
    _TabItem('Education', Icons.school_rounded, AppColors.warningAmber),
    _TabItem('Entertainment', Icons.movie_rounded, Color(0xFFDB2777)),
    _TabItem('Tech', Icons.computer_rounded, Color(0xFF0891B2)),
    _TabItem(
      'Sports',
      Icons.sports_soccer_rounded,
      AppColors.lightStatusCompleted,
    ),
    _TabItem('Cooking', Icons.restaurant_menu_rounded, Color(0xFFEA580C)),
    _TabItem('News', Icons.newspaper_rounded, Color(0xFF2563EB)),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final tab = _tabs[index];
          return _CategoryTabChip(
            label: tab.label,
            icon: tab.icon,
            color: tab.color,
            isDark: isDark,
            onTap: () => onSearch(tab.label),
          );
        },
      ),
    );
  }
}

class _TabItem {
  final String label;
  final IconData icon;
  final Color color;
  const _TabItem(this.label, this.icon, this.color);
}

class _CategoryTabChip extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _CategoryTabChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_CategoryTabChip> createState() => _CategoryTabChipState();
}

class _CategoryTabChipState extends State<_CategoryTabChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovered = false);
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 150),
          offset:
              !widget.isDark && _hovered
                  ? const Offset(0, -0.015)
                  : Offset.zero,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color:
                  _hovered
                      ? (widget.isDark
                          ? AppColors.homeDarkCardHover
                          : widget.color.withValues(alpha: AppOpacity.pressed))
                      : (widget.isDark
                          ? AppColors.homeDarkCardBg
                          : AppColors.surface1(context)),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border:
                  widget.isDark
                      ? Border.all(
                        color:
                            _hovered
                                ? widget.color.withValues(
                                  alpha: AppOpacity.secondary,
                                )
                                : AppColors.homeDarkBorderSubtle,
                        width: _hovered ? 1.2 : 1,
                      )
                      : Border.all(color: AppColors.border(context)),
              boxShadow:
                  !widget.isDark && _hovered
                      ? const [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 16,
                          offset: Offset(0, 6),
                        ),
                      ]
                      : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 15, color: widget.color),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  widget.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Recent Searches
// =============================================================================

class _RecentSearchesSection extends ConsumerWidget {
  final void Function(String) onSearch;

  const _RecentSearchesSection({required this.onSearch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final recents = ref.watch(recentSearchesProvider);

    return recents.when(
      data: (searches) {
        if (searches.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 18,
                  color: AppColors.accentHighlight,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  AppLocalizations.youtubeSearchRecentSearches,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed:
                      () =>
                          ref.read(recentSearchesProvider.notifier).clearAll(),
                  icon: const Icon(Icons.clear_all_rounded, size: 16),
                  label: Text(AppLocalizations.commonClear),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.metaText(context),
                    textStyle: AppTypography.metadata.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children:
                  searches.take(8).map((search) {
                    return _RecentSearchChip(
                      label: search,
                      onTap: () => onSearch(search),
                      onDelete:
                          () => ref
                              .read(recentSearchesProvider.notifier)
                              .removeSearch(search),
                    );
                  }).toList(),
            ),
            const SizedBox(height: 28),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _RecentSearchChip extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _RecentSearchChip({
    required this.label,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_RecentSearchChip> createState() => _RecentSearchChipState();
}

class _RecentSearchChipState extends State<_RecentSearchChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovered = false);
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 150),
          offset: !isDark && _hovered ? const Offset(0, -0.015) : Offset.zero,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.only(
              left: AppSpacing.smMd,
              right: AppSpacing.xs,
              top: AppSpacing.sm,
              bottom: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color:
                  _hovered
                      ? (isDark
                          ? AppColors.homeDarkCardHover
                          : AppColors.surface1(context))
                      : (isDark
                          ? AppColors.homeDarkCardBg
                          : AppColors.surface1(context)),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border:
                  isDark
                      ? Border.all(color: AppColors.homeDarkBorderStrong)
                      : Border.all(color: AppColors.border(context)),
              boxShadow:
                  !isDark && _hovered
                      ? const [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 16,
                          offset: Offset(0, 6),
                        ),
                      ]
                      : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 14,
                  color: AppColors.metaText(context),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  widget.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: IconButton(
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.close_rounded, size: 14),
                    color: AppColors.metaText(context),
                    hoverColor: AppColors.accentHighlight.withValues(
                      alpha: AppOpacity.subtle,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Trending Now
// =============================================================================

/// Shows REAL YouTube trending videos for the user's region when available;
/// otherwise falls back to the curated topic shortcuts ([_TrendingGrid]).
class _TrendingSection extends ConsumerWidget {
  final void Function(String) onSearch;
  final void Function(String url)? onVideoDownload;

  const _TrendingSection({required this.onSearch, this.onVideoDownload});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final videos = ref.watch(youtubeTrendingProvider).valueOrNull ?? const [];

    if (videos.isNotEmpty && onVideoDownload != null) {
      final top = videos.take(8).toList();
      return _DiscoverySurface(
        header: _SectionHeader(
          icon: Icons.trending_up_rounded,
          title: AppLocalizations.youtubeSearchTrendingTitle,
          color: AppColors.accentHighlight,
        ),
        child: Column(
          children: [
            for (final v in top)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: YouTubeSearchResultItem(
                  video: v,
                  onTap: () => onVideoDownload!(v.url),
                  onDownload: () => onVideoDownload!(v.url),
                ),
              ),
          ],
        ),
      );
    }

    // Fallback (also while trending loads / on failure): curated shortcuts.
    return _DiscoverySurface(
      header: _SectionHeader(
        icon: Icons.trending_up_rounded,
        title: AppLocalizations.youtubeSearchPopularSearches,
        color: AppColors.accentHighlight,
      ),
      child: _TrendingGrid(onSearch: onSearch),
    );
  }
}

class _TrendingGrid extends StatelessWidget {
  final void Function(String) onSearch;

  const _TrendingGrid({required this.onSearch});

  static const _trendingTopics = [
    _TrendingItem('Lo-Fi Hip Hop', Icons.headphones_rounded, Color(0xFF7C3AED)),
    _TrendingItem(
      'AI & ChatGPT',
      Icons.auto_awesome_rounded,
      Color(0xFF2563EB),
    ),
    _TrendingItem(
      'Workout Music',
      Icons.fitness_center_rounded,
      AppColors.lightStatusFailed,
    ),
    _TrendingItem(
      'Nature Sounds',
      Icons.forest_rounded,
      AppColors.lightStatusCompleted,
    ),
    _TrendingItem(
      'Tech Reviews',
      Icons.devices_rounded,
      AppColors.warningAmber,
    ),
    _TrendingItem('Cooking Shows', Icons.restaurant_rounded, Color(0xFFEA580C)),
    _TrendingItem(
      'Travel Vlogs',
      Icons.flight_takeoff_rounded,
      Color(0xFF0891B2),
    ),
    _TrendingItem('Live Concerts', Icons.music_note_rounded, Color(0xFFDB2777)),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Compact chip wrap (not big cards): these are just search shortcuts, so
    // they read as a dense, balanced row of chips — consistent with the
    // category tabs and recent-search chips, no wasted card real estate.
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final item in _trendingTopics)
          _CategoryTabChip(
            label: item.title,
            icon: item.icon,
            color: item.color,
            isDark: isDark,
            onTap: () => onSearch(item.title),
          ),
      ],
    );
  }
}

class _TrendingItem {
  final String title;
  final IconData icon;
  final Color color;
  const _TrendingItem(this.title, this.icon, this.color);
}

