import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../domain/entities/youtube_search_result.dart';
import '../providers/youtube_explore_provider.dart';
import '../providers/youtube_search_provider.dart';
import 'search_filters_bar.dart';
import 'video_detail_panel.dart';
import 'youtube_search_result_item.dart';
import 'youtube_search_skeleton.dart';

/// Search results view — 70/30 split layout.
/// Left: scrollable results list. Right: video detail panel.
class YouTubeResultsView extends ConsumerStatefulWidget {
  final void Function(String url) onVideoDownload;

  const YouTubeResultsView({super.key, required this.onVideoDownload});

  @override
  ConsumerState<YouTubeResultsView> createState() => _YouTubeResultsViewState();
}

class _YouTubeResultsViewState extends ConsumerState<YouTubeResultsView> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    // Prefetch while there is still enough content below the viewport. This
    // keeps the Explore results list aligned with the Home search sheet and
    // hides yt-dlp's larger-window pagination cost behind scrolling.
    if (_scrollController.position.extentAfter <= 600) {
      ref.read(youtubeSearchProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final searchState = ref.watch(youtubeSearchProvider);
    final exploreState = ref.watch(youtubeExploreProvider);
    final selectedVideoUrl = exploreState.selectedVideo?.url;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: Column(
            children: [
              _ExploreResultsSurface(
                isDark: isDark,
                child: Column(
                  children: [
                    SearchFiltersBar(
                      filters: searchState.filters,
                      onFiltersChanged: (filters) {
                        ref
                            .read(youtubeSearchProvider.notifier)
                            .updateFilters(filters);
                      },
                    ),
                    if (!searchState.isLoading &&
                        searchState.results.isNotEmpty)
                      _ResultsCountStrip(
                        count: searchState.results.length,
                        isDark: isDark,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.smMd),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final showDetailPanel = constraints.maxWidth >= 1080;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: showDetailPanel ? 65 : 100,
                          child: _ExploreResultsSurface(
                            isDark: isDark,
                            clip: true,
                            child: _buildResultsList(
                              context,
                              searchState,
                              selectedVideoUrl,
                            ),
                          ),
                        ),
                        if (showDetailPanel) ...[
                          const SizedBox(width: AppSpacing.smMd),
                          Expanded(
                            flex: 35,
                            child: _ExploreResultsSurface(
                              isDark: isDark,
                              clip: true,
                              child:
                                  exploreState.selectedVideo != null
                                      ? VideoDetailPanel(
                                        video: exploreState.selectedVideo!,
                                        videoDetail: exploreState.videoDetail,
                                        isLoading: exploreState.isLoadingDetail,
                                        error: exploreState.detailError,
                                        onDownload:
                                            () => widget.onVideoDownload(
                                              exploreState.selectedVideo!.url,
                                            ),
                                        onClose:
                                            () =>
                                                ref
                                                    .read(
                                                      youtubeExploreProvider
                                                          .notifier,
                                                    )
                                                    .clearSelection(),
                                      )
                                      : _buildEmptyPanel(context),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultsList(
    BuildContext context,
    YouTubeSearchState searchState,
    String? selectedVideoUrl,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Loading state
    if (searchState.isLoading) {
      return const YouTubeSearchSkeleton();
    }

    // Error state
    if (searchState.error != null && searchState.results.isEmpty) {
      return Center(
        child: _ResultStatePanel(
          icon: Icons.error_outline_rounded,
          title: AppLocalizations.youtubeSearchFailed,
          subtitle: AppLocalizations.youtubeSearchTip,
          isDark: isDark,
          iconColor: cs.error,
        ),
      );
    }

    // Empty state
    if (searchState.results.isEmpty) {
      return Center(
        child: _ResultStatePanel(
          icon: Icons.search_off_rounded,
          title: AppLocalizations.youtubeSearchNoVideos,
          subtitle: AppLocalizations.youtubeSearchTip,
          isDark: isDark,
        ),
      );
    }

    // Uniform results list — all items use the same compact row style.
    // ValueKey on each item is critical: ListView.builder reuses StatefulWidget
    // State by index by default. When loadMore() appends items, indexes shift
    // and the State instance under the cursor gets rebound to a different
    // video → MouseRegion onEnter/onExit fires on a stale widget → mouse_tracker
    // assertion failure. Stable per-URL keys force Flutter to track State by
    // identity, not position.
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.smMd,
        AppSpacing.smMd,
        AppSpacing.smMd,
        AppSpacing.lg,
      ),
      itemCount:
          searchState.results.length +
          (searchState.isLoadingMore || searchState.error != null ? 1 : 0),
      itemBuilder: (context, index) {
        // Loading more indicator
        if (index == searchState.results.length) {
          if (searchState.error != null) {
            return _buildLoadMoreError(context, isDark);
          }
          return const Padding(
            key: ValueKey('youtube_search_loading_more'),
            padding: EdgeInsets.fromLTRB(0, 8, 0, AppSpacing.md),
            child: YouTubeSearchSkeleton(itemCount: 3, shrinkWrap: true),
          );
        }

        final video = searchState.results[index];
        final isSelected = video.url == selectedVideoUrl;
        final itemKey = ValueKey<String>('yt_search_${video.url}');

        // Channel result — render as channel card (no download)
        if (video.isChannel) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ChannelResultCard(
              key: itemKey,
              video: video,
              isSelected: isSelected,
              isDark: isDark,
              onTap: () => _onVideoTap(video),
            ),
          );
        }

        // Uniform result row with Command Center selected state
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            key: itemKey,
            decoration: BoxDecoration(
              color:
                  isSelected
                      ? (isDark
                          ? AppColors.homeDarkCardSelected
                          : cs.primaryContainer.withValues(
                            alpha: AppOpacity.subtle,
                          ))
                      : null,
              border: Border(
                left: BorderSide(
                  color: isSelected ? AppColors.brand : Colors.transparent,
                  width: 3,
                ),
                bottom: BorderSide(
                  color:
                      isDark
                          ? AppColors.homeDarkBorderStrong
                          : AppColors.border(context),
                  width: 0.5,
                ),
              ),
            ),
            child: YouTubeSearchResultItem(
              video: video,
              onTap: () => _onVideoTap(video),
              onDownload: () => widget.onVideoDownload(video.url),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadMoreError(BuildContext context, bool isDark) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, AppSpacing.md),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: () {
            final notifier = ref.read(youtubeSearchProvider.notifier);
            notifier.clearError();
            notifier.loadMore();
          },
          icon: Icon(
            Icons.refresh_rounded,
            size: 16,
            color: isDark ? AppColors.accentHighlight : null,
          ),
          label: Text(AppLocalizations.downloadsRetry),
          style: OutlinedButton.styleFrom(
            foregroundColor:
                isDark ? AppColors.accentHighlight : theme.colorScheme.primary,
            side: BorderSide(
              color:
                  isDark
                      ? AppColors.accentHighlight.withValues(
                        alpha: AppOpacity.quarter,
                      )
                      : theme.colorScheme.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }

  void _onVideoTap(YouTubeSearchResult video) {
    ref.read(youtubeExploreProvider.notifier).selectVideo(video);
  }

  Widget _buildEmptyPanel(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color:
                isDark ? AppColors.homeDarkAppBg : AppColors.surface2(context),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color:
                  isDark
                      ? AppColors.homeDarkBorderStrong
                      : cs.outlineVariant.withValues(alpha: AppOpacity.scrim),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.accentHighlight.withValues(
                    alpha: AppOpacity.subtle,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Icon(
                  Icons.playlist_play_rounded,
                  size: 30,
                  color: AppColors.accentHighlight.withValues(
                    alpha: AppOpacity.overlay,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                AppLocalizations.youtubeSearchSelectVideo,
                style: AppTypography.metadata.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                  color: isDark ? AppColors.darkLightText : cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                AppLocalizations.youtubeSearchSelectVideoHint,
                style: theme.textTheme.labelSmall?.copyWith(
                  color:
                      isDark
                          ? AppColors.homeDarkTextSecondary
                          : cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExploreResultsSurface extends StatelessWidget {
  final bool isDark;
  final Widget child;
  final bool clip;

  const _ExploreResultsSurface({
    required this.isDark,
    required this.child,
    this.clip = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final borderColor =
        isDark
            ? AppColors.homeDarkBorderStrong
            : cs.outlineVariant.withValues(alpha: AppOpacity.scrim);

    final surface = Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.homeDarkCardBg : AppColors.surface1(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.05),
            blurRadius: isDark ? 24 : 18,
            offset: const Offset(0, 8),
            spreadRadius: isDark ? -12 : 0,
          ),
        ],
      ),
      child: child,
    );

    if (!clip) return surface;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: surface,
    );
  }
}

class _ResultsCountStrip extends StatelessWidget {
  final int count;
  final bool isDark;

  const _ResultsCountStrip({required this.count, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color:
                isDark
                    ? AppColors.homeDarkBorderStrong
                    : cs.outlineVariant.withValues(alpha: AppOpacity.quarter),
            width: 0.5,
          ),
        ),
      ),
      child: Text(
        AppLocalizations.youtubeSearchResultsCount(count),
        style: AppTypography.compact.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: isDark ? AppColors.homeDarkTextSecondary : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ResultStatePanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isDark;
  final Color? iconColor;

  const _ResultStatePanel({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isDark,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final effectiveIconColor =
        iconColor ??
        (isDark
            ? AppColors.homeDarkTextSecondary
            : cs.onSurface.withValues(alpha: AppOpacity.scrim));

    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      margin: const EdgeInsets.all(AppSpacing.xl),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: isDark ? AppColors.homeDarkAppBg : AppColors.surface2(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color:
              isDark
                  ? AppColors.homeDarkBorderStrong
                  : cs.outlineVariant.withValues(alpha: AppOpacity.scrim),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.05),
            blurRadius: isDark ? 22 : 16,
            offset: const Offset(0, 8),
            spreadRadius: isDark ? -12 : 0,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: effectiveIconColor.withValues(alpha: AppOpacity.subtle),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Icon(
              icon,
              size: 28,
              color: effectiveIconColor.withValues(alpha: AppOpacity.overlay),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: isDark ? AppColors.darkLightText : cs.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color:
                  isDark
                      ? AppColors.homeDarkTextSecondary
                      : cs.onSurface.withValues(alpha: AppOpacity.overlay),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Channel result card — shows avatar + channel name, no download button.
class _ChannelResultCard extends StatefulWidget {
  final YouTubeSearchResult video;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _ChannelResultCard({
    super.key,
    required this.video,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_ChannelResultCard> createState() => _ChannelResultCardState();
}

class _ChannelResultCardState extends State<_ChannelResultCard> {
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.smMd,
          ),
          decoration: BoxDecoration(
            color:
                widget.isSelected
                    ? (widget.isDark
                        ? AppColors.homeDarkCardSelected
                        : cs.primaryContainer.withValues(
                          alpha: AppOpacity.subtle,
                        ))
                    : (_hovered
                        ? (widget.isDark
                            ? AppColors.homeDarkCardHover
                            : AppColors.lightSurface2)
                        : (widget.isDark
                            ? AppColors.homeDarkCardBg
                            : Colors.white)),
            border:
                widget.isDark
                    ? Border(
                      left: BorderSide(
                        color:
                            widget.isSelected
                                ? AppColors.brand
                                : Colors.transparent,
                        width: 3,
                      ),
                      bottom: BorderSide(
                        color: AppColors.homeDarkBorderStrong,
                        width: 0.5,
                      ),
                    )
                    : Border.all(
                      color:
                          _hovered
                              ? const Color(0xFFD1D5DB)
                              : const Color(0xFFE5E7EB),
                    ),
            borderRadius: BorderRadius.circular(AppRadius.card),
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
            children: [
              // Channel avatar (circular)
              ClipOval(
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child:
                      widget.video.thumbnail != null
                          ? CachedNetworkImage(
                            imageUrl: widget.video.thumbnail!,
                            fit: BoxFit.cover,
                            memCacheWidth: 112,
                            memCacheHeight: 112,
                            placeholder:
                                (_, __) => Container(
                                  color:
                                      widget.isDark
                                          ? AppColors.homeDarkCardBg
                                          : AppColors.lightSurface2,
                                  child: Icon(
                                    Icons.person_rounded,
                                    size: 24,
                                    color: cs.onSurface.withValues(
                                      alpha: AppOpacity.quarter,
                                    ),
                                  ),
                                ),
                            errorWidget:
                                (_, __, ___) => Container(
                                  color:
                                      widget.isDark
                                          ? AppColors.homeDarkCardBg
                                          : AppColors.lightSurface2,
                                  child: Icon(
                                    Icons.person_rounded,
                                    size: 24,
                                    color: cs.onSurface.withValues(
                                      alpha: AppOpacity.quarter,
                                    ),
                                  ),
                                ),
                          )
                          : Container(
                            color:
                                widget.isDark
                                    ? AppColors.homeDarkCardBg
                                    : AppColors.lightSurface2,
                            child: Icon(
                              Icons.person_rounded,
                              size: 24,
                              color: cs.onSurface.withValues(
                                alpha: AppOpacity.quarter,
                              ),
                            ),
                          ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Channel info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.video.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Icon(
                          Icons.person_rounded,
                          size: 14,
                          color:
                              widget.isDark
                                  ? AppColors.homeDarkTextSecondary
                                  : cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          AppLocalizations.youtubeSearchChannel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color:
                                widget.isDark
                                    ? AppColors.homeDarkTextSecondary
                                    : cs.onSurface.withValues(
                                      alpha: AppOpacity.overlay,
                                    ),
                          ),
                        ),
                        if (widget.video.formattedViewCount.isNotEmpty) ...[
                          Text(
                            ' · ${widget.video.formattedViewCount}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color:
                                  widget.isDark
                                      ? AppColors.homeDarkTextSecondary
                                      : cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (widget.video.description != null &&
                        widget.video.description!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        widget.video.description!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              widget.isDark
                                  ? AppColors.homeDarkTextSecondary
                                  : cs.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
