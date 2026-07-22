import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../../youtube_channel/domain/entities/subscribed_channel.dart';
import '../../../youtube_channel/presentation/providers/channel_subscriptions_provider.dart';
import '../providers/recent_searches_provider.dart';

/// Discovery view — landing state of YouTube Explore tab.
/// Sections: Category tabs → Recent Searches → Trending → Explore Categories → Subscriptions
class YouTubeDiscoveryView extends ConsumerWidget {
  final void Function(String query) onSearch;

  const YouTubeDiscoveryView({super.key, required this.onSearch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

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

              // Trending Now
              _DiscoverySurface(
                header: _SectionHeader(
                  icon: Icons.trending_up_rounded,
                  title: AppLocalizations.youtubeSearchPopularSearches,
                  color: AppColors.accentHighlight,
                ),
                child: _TrendingGrid(onSearch: onSearch),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Explore Categories
              _DiscoverySurface(
                header: _SectionHeader(
                  icon: Icons.explore_rounded,
                  title: AppLocalizations.youtubeSearchSuggestions,
                  color: cs.primary,
                ),
                child: _CategoriesGrid(onSearch: onSearch),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Subscriptions
              _SubscriptionsSection(onSearch: onSearch),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount =
            constraints.maxWidth > 800
                ? 4
                : (constraints.maxWidth > 500
                    ? 3
                    : (constraints.maxWidth > 360 ? 2 : 1));
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: AppSpacing.smMd,
            crossAxisSpacing: AppSpacing.smMd,
            childAspectRatio: 2.8,
          ),
          itemCount: _trendingTopics.length,
          itemBuilder: (context, index) {
            final item = _trendingTopics[index];
            return _TrendingCard(item: item, onTap: () => onSearch(item.title));
          },
        );
      },
    );
  }
}

class _TrendingItem {
  final String title;
  final IconData icon;
  final Color color;
  const _TrendingItem(this.title, this.icon, this.color);
}

class _TrendingCard extends StatefulWidget {
  final _TrendingItem item;
  final VoidCallback onTap;

  const _TrendingCard({required this.item, required this.onTap});

  @override
  State<_TrendingCard> createState() => _TrendingCardState();
}

class _TrendingCardState extends State<_TrendingCard> {
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
                      ? Border.all(
                        color:
                            _hovered
                                ? widget.item.color.withValues(
                                  alpha: AppOpacity.overlay,
                                )
                                : AppColors.homeDarkBorderSubtle,
                        width: _hovered ? 1.2 : 1,
                      )
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
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.smMd,
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: widget.item.color.withValues(
                      alpha: isDark ? AppOpacity.pressed : AppOpacity.hover,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Icon(
                    widget.item.icon,
                    size: 17,
                    color: widget.item.color,
                  ),
                ),
                const SizedBox(width: AppSpacing.smMd),
                Expanded(
                  child: Text(
                    widget.item.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 12,
                  color:
                      isDark
                          ? AppColors.homeDarkTextSecondary
                          : cs.onSurface.withValues(
                            alpha:
                                _hovered
                                    ? AppOpacity.overlay
                                    : AppOpacity.quarter,
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
// Explore Categories (with subtitles per Stitch design)
// =============================================================================

class _CategoriesGrid extends StatelessWidget {
  final void Function(String) onSearch;

  const _CategoriesGrid({required this.onSearch});

  static const _categories = [
    _CategoryItem(
      'Music',
      'New Releases',
      Icons.music_note_rounded,
      AppColors.lightStatusFailed,
    ),
    _CategoryItem(
      'Gaming',
      'Live Now',
      Icons.sports_esports_rounded,
      Color(0xFF7C3AED),
    ),
    _CategoryItem(
      'Education',
      'Learn Anything',
      Icons.school_rounded,
      AppColors.warningAmber,
    ),
    _CategoryItem(
      'Entertainment',
      'Trending',
      Icons.movie_rounded,
      Color(0xFFDB2777),
    ),
    _CategoryItem(
      'Sports',
      'Major Events',
      Icons.sports_soccer_rounded,
      AppColors.lightStatusCompleted,
    ),
    _CategoryItem(
      'Tech',
      'Future Tech',
      Icons.computer_rounded,
      Color(0xFF0891B2),
    ),
    _CategoryItem(
      'Film & Animation',
      'Art & Craft',
      Icons.animation_rounded,
      Color(0xFF9333EA),
    ),
    _CategoryItem(
      'News',
      'Global Updates',
      Icons.newspaper_rounded,
      Color(0xFF2563EB),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount =
            constraints.maxWidth > 800
                ? 4
                : (constraints.maxWidth > 500
                    ? 3
                    : (constraints.maxWidth > 360 ? 2 : 1));
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: AppSpacing.smMd,
            crossAxisSpacing: AppSpacing.smMd,
            childAspectRatio: 1.5,
          ),
          itemCount: _categories.length,
          itemBuilder: (context, index) {
            final cat = _categories[index];
            return _CategoryCard(
              category: cat,
              onTap: () => onSearch(cat.title),
            );
          },
        );
      },
    );
  }
}

class _CategoryItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  const _CategoryItem(this.title, this.subtitle, this.icon, this.color);
}

class _CategoryCard extends StatefulWidget {
  final _CategoryItem category;
  final VoidCallback onTap;

  const _CategoryCard({required this.category, required this.onTap});

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
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
                      ? Border.all(
                        color:
                            _hovered
                                ? widget.category.color.withValues(
                                  alpha: AppOpacity.overlay,
                                )
                                : AppColors.homeDarkBorderSubtle,
                        width: _hovered ? 1.2 : 1,
                      )
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: widget.category.color.withValues(
                      alpha: isDark ? AppOpacity.pressed : AppOpacity.hover,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Icon(
                    widget.category.icon,
                    size: 22,
                    color: widget.category.color,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  widget.category.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  widget.category.subtitle,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: AppOpacity.strong),
                    fontWeight: FontWeight.w500,
                    fontSize: 11.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
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
// Subscriptions
// =============================================================================

class _SubscriptionsSection extends ConsumerWidget {
  final void Function(String) onSearch;

  const _SubscriptionsSection({required this.onSearch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final subscriptions = ref.watch(subscribedChannelsStreamProvider);

    return subscriptions.when(
      data: (channels) {
        if (channels.isEmpty) return const SizedBox.shrink();
        return _DiscoverySurface(
          header: _SectionHeader(
            icon: Icons.subscriptions_rounded,
            title: AppLocalizations.youtubeSearchYourSubscriptions,
            color: cs.primary,
          ),
          child: SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: channels.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
              itemBuilder: (context, index) {
                final channel = channels[index];
                return _SubscriptionAvatar(
                  channel: channel,
                  onTap: () => onSearch(channel.channelName),
                );
              },
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _SubscriptionAvatar extends StatefulWidget {
  final SubscribedChannel channel;
  final VoidCallback onTap;

  const _SubscriptionAvatar({required this.channel, required this.onTap});

  @override
  State<_SubscriptionAvatar> createState() => _SubscriptionAvatarState();
}

class _SubscriptionAvatarState extends State<_SubscriptionAvatar> {
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
        child: SizedBox(
          width: 68,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color:
                        _hovered
                            ? AppColors.accentHighlight
                            : (theme.brightness == Brightness.dark
                                ? AppColors.homeDarkBorderStrong
                                : Colors.transparent),
                    width: 2,
                  ),
                ),
                child: ClipOval(
                  child:
                      widget.channel.thumbnail != null
                          ? CachedNetworkImage(
                            imageUrl: widget.channel.thumbnail!,
                            width: 46,
                            height: 46,
                            fit: BoxFit.cover,
                            memCacheWidth: 92,
                            memCacheHeight: 92,
                            placeholder:
                                (_, __) => Container(
                                  color: AppColors.surface2(context),
                                  child: Icon(
                                    Icons.person,
                                    size: 20,
                                    color: cs.onSurface.withValues(
                                      alpha: AppOpacity.quarter,
                                    ),
                                  ),
                                ),
                            errorWidget:
                                (_, __, ___) => Container(
                                  color: AppColors.surface2(context),
                                  child: Icon(
                                    Icons.person,
                                    size: 20,
                                    color: cs.onSurface.withValues(
                                      alpha: AppOpacity.quarter,
                                    ),
                                  ),
                                ),
                          )
                          : Container(
                            width: 46,
                            height: 46,
                            color: AppColors.surface2(context),
                            child: Icon(
                              Icons.person,
                              size: 20,
                              color: cs.onSurface.withValues(
                                alpha: AppOpacity.quarter,
                              ),
                            ),
                          ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                widget.channel.channelName,
                style: AppTypography.mini.copyWith(
                  color:
                      theme.brightness == Brightness.dark
                          ? AppColors.homeDarkTextSecondary
                          : cs.onSurface.withValues(
                            alpha: AppOpacity.secondary,
                          ),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
