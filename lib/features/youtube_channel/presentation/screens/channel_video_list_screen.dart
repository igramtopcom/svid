import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../../home/presentation/widgets/cinematic_aurora_background.dart';
import '../providers/youtube_channel_provider.dart';
import '../widgets/channel_video_item.dart';
import '../widgets/channel_video_skeleton.dart';
import '../widgets/channel_info_header.dart';

/// The Dossier — Channel Intelligence (Nocturne Cinematic)
/// Design ref: Stitch screen aeb19b1031ea45b4b26f3cfbf57f0cc6
class ChannelVideoListScreen extends ConsumerStatefulWidget {
  final Function(List<String> urls)? onDownloadSelected;
  final bool embedded;
  final VoidCallback? onBack;

  const ChannelVideoListScreen({
    super.key,
    this.onDownloadSelected,
    this.embedded = false,
    this.onBack,
  });

  @override
  ConsumerState<ChannelVideoListScreen> createState() =>
      _ChannelVideoListScreenState();
}

class _ChannelVideoListScreenState
    extends ConsumerState<ChannelVideoListScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  bool _searchFocused = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    // Prefetch before the hard bottom so channel-video pagination feels
    // consistent with Home search sheet and Explore results.
    if (_scrollController.position.extentAfter <= 600) {
      ref.read(youtubeChannelProvider.notifier).loadMoreVideos();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(youtubeChannelProvider);
    final notifier = ref.read(youtubeChannelProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const lightHomeBg = Color(0xFFF9F9FF);
    final content = Stack(
      children: [
        Positioned.fill(
          child:
              isDark
                  ? (!widget.embedded
                      ? const CinematicAuroraBackground(
                        variant: AuroraVariant.archive,
                      )
                      : const ColoredBox(color: Colors.transparent))
                  : const ColoredBox(color: lightHomeBg),
        ),
        Column(
          children: [
            _buildTopBar(state, notifier, isDark),
            Expanded(
              child:
                  state.isLoading
                      ? _buildLoadingSkeleton(isDark)
                      : state.error != null
                      ? _buildErrorState(state, notifier, isDark)
                      : state.filteredVideos.isEmpty && state.videos.isEmpty
                      ? _buildEmptyState(isDark)
                      : _buildContent(state, notifier, isDark),
            ),
          ],
        ),
        if (state.hasSelection)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildOperationsBar(state, notifier, isDark),
          ),
      ],
    );

    if (widget.embedded) {
      return ColoredBox(
        color: isDark ? Colors.transparent : lightHomeBg,
        child: content,
      );
    }

    return Scaffold(
      backgroundColor: isDark ? Colors.transparent : lightHomeBg,
      body: content,
    );
  }

  /// Top bar — back arrow, channel title, sort + select controls
  Widget _buildTopBar(
    YouTubeChannelState state,
    YouTubeChannelNotifier notifier,
    bool isDark,
  ) {
    return Container(
      height: 44,
      padding: EdgeInsets.only(left: Platform.isMacOS ? 78 : 16, right: 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBg : AppColors.lightSurface2,
        gradient:
            isDark
                ? LinearGradient(colors: [AppColors.darkBase, AppColors.darkBg])
                : null,
      ),
      child: Row(
        children: [
          // Back arrow — subtle, functional
          _HoverIconButton(
            icon: Icons.arrow_back,
            isDark: isDark,
            onPressed:
                widget.embedded
                    ? (widget.onBack ?? () {})
                    : () => Navigator.of(context).pop(),
            tooltip: AppLocalizations.commonBack,
          ),
        ],
      ),
    );
  }

  Widget _buildSortMenu(
    YouTubeChannelState state,
    YouTubeChannelNotifier notifier,
    bool isDark,
  ) {
    return PopupMenuButton<VideoSortBy>(
      icon: Icon(
        Icons.sort,
        size: 18,
        color: isDark ? AppColors.darkMetaText : AppColors.lightMetaText,
      ),
      tooltip: AppLocalizations.youtubeChannelSortTooltip,
      color: isDark ? AppColors.darkBase : AppColors.lightBase,
      onSelected: (sortBy) => notifier.setSortBy(sortBy),
      itemBuilder:
          (context) =>
              VideoSortBy.values.map((sortBy) {
                final isActive = state.sortBy == sortBy;
                return PopupMenuItem(
                  value: sortBy,
                  child: Text(
                    sortBy.label(context),
                    style: AppTypography.metadata.copyWith(
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                      color:
                          isActive
                              ? (isDark
                                  ? AppColors.accentHighlight
                                  : AppColors.brand)
                              : (isDark
                                  ? AppColors.darkLightText
                                  : AppColors.darkSurface1),
                    ),
                  ),
                );
              }).toList(),
    );
  }

  Widget _buildSelectToggle(
    YouTubeChannelState state,
    YouTubeChannelNotifier notifier,
    bool isDark,
  ) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          if (state.isAllSelected) {
            notifier.deselectAll();
          } else {
            notifier.selectAll();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.smMd,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Custom checkbox
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color:
                      state.isAllSelected
                          ? AppColors.accentHighlight
                          : Colors.transparent,
                  border: Border.all(
                    color:
                        state.isAllSelected
                            ? AppColors.brand
                            : (isDark
                                ? AppColors.darkMuted
                                : AppColors.lightMuted),
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
                child:
                    state.isAllSelected
                        ? const Icon(Icons.check, size: 12, color: Colors.white)
                        : null,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                state.isAllSelected
                    ? AppLocalizations.youtubeChannelDeselectAll
                    : AppLocalizations.youtubeChannelSelectAll,
                style: AppTypography.statusBadge.copyWith(
                  color:
                      isDark
                          ? AppColors.darkLightText.withValues(
                            alpha: AppOpacity.strong,
                          )
                          : AppColors.lightMetaText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Main content: header + search + sort row + video list
  Widget _buildContent(
    YouTubeChannelState state,
    YouTubeChannelNotifier notifier,
    bool isDark,
  ) {
    return Column(
      children: [
        // Subject profile header
        if (state.channel != null) ChannelInfoHeader(channel: state.channel!),
        // Gradient accent line
        Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                AppColors.brand.withValues(
                  alpha: isDark ? AppOpacity.quarter : AppOpacity.pressed,
                ),
                Colors.transparent,
              ],
            ),
          ),
        ),
        // Search bar — The Archive
        _buildSearchBar(notifier, isDark),
        // Sort controls row
        _buildSortControls(state, notifier, isDark),
        // Video list — Intelligence Files
        Expanded(
          child:
              state.filteredVideos.isEmpty
                  ? _buildNoResults(isDark)
                  : _buildVideoList(state, isDark),
        ),
      ],
    );
  }

  Widget _buildSearchBar(YouTubeChannelNotifier notifier, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        0,
      ),
      child: Column(
        children: [
          Focus(
            onFocusChange:
                (focused) => setState(() => _searchFocused = focused),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => notifier.setSearchQuery(value),
              style: AppTypography.statusBadge.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w400,
                letterSpacing: 1.5,
                color:
                    isDark ? AppColors.darkLightText : AppColors.darkSurface1,
              ),
              decoration: InputDecoration(
                hintText: AppLocalizations.channelVideoListSearchHint,
                hintStyle: AppTypography.statusBadge.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w400,
                  letterSpacing: 1.5,
                  color: isDark ? AppColors.darkMetaText : AppColors.lightMuted,
                ),
                prefixIcon: Icon(
                  Icons.radar_outlined,
                  size: 18,
                  color: isDark ? AppColors.darkMetaText : AppColors.lightMuted,
                ),
                suffixIcon:
                    _searchController.text.isNotEmpty
                        ? IconButton(
                          icon: Icon(
                            Icons.clear,
                            size: 16,
                            color:
                                isDark
                                    ? AppColors.darkMuted
                                    : AppColors.lightMuted,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            notifier.setSearchQuery('');
                          },
                        )
                        : null,
                filled: true,
                fillColor:
                    isDark
                        ? (_searchFocused ? AppColors.darkBg : AppColors.darkBg)
                        : AppColors.lightElevated,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
              ),
            ),
          ),
          // Expanding wine-red underline on focus
          LayoutBuilder(
            builder: (context, constraints) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeInOut,
                height: 1,
                width: _searchFocused ? constraints.maxWidth : 0,
                color: AppColors.brand,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSortControls(
    YouTubeChannelState state,
    YouTubeChannelNotifier notifier,
    bool isDark,
  ) {
    final sorts = [
      (VideoSortBy.dateNewest, 'DATE', Icons.south),
      (VideoSortBy.durationLongest, 'DURATION', null),
      (VideoSortBy.viewsMost, 'VIEWS', null),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.smMd,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          ...sorts.map((entry) {
            final (sortBy, label, icon) = entry;
            final isActive = state.sortBy == sortBy;
            return Padding(
              padding: const EdgeInsets.only(right: AppSpacing.mdLg),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => notifier.setSortBy(sortBy),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: AppTypography.compact.copyWith(
                          fontFamily: 'monospace',
                          letterSpacing: 2.0,
                          fontWeight:
                              isActive ? FontWeight.w700 : FontWeight.w400,
                          color:
                              isActive
                                  ? (isDark
                                      ? AppColors.accentHighlight
                                      : AppColors.brand)
                                  : (isDark
                                      ? AppColors.darkMetaText
                                      : AppColors.lightMetaText),
                        ),
                      ),
                      if (icon != null && isActive) ...[
                        const SizedBox(width: AppSpacing.xxs),
                        Icon(
                          icon,
                          size: 12,
                          color:
                              isDark
                                  ? AppColors.accentHighlight
                                  : AppColors.brand,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          if (state.filteredVideos.isNotEmpty)
            _buildSortMenu(state, notifier, isDark),
          if (state.filteredVideos.isNotEmpty)
            _buildSelectToggle(state, notifier, isDark),
        ],
      ),
    );
  }

  Widget _buildVideoList(YouTubeChannelState state, bool isDark) {
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.only(bottom: state.hasSelection ? 100 : 24),
      itemCount: state.filteredVideos.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == state.filteredVideos.length) {
          return state.isLoadingMore
              ? Shimmer(
                key: const ValueKey('channel_videos_loading_more'),
                child: const ChannelVideoSkeleton(),
              )
              : const SizedBox.shrink(
                key: ValueKey('channel_videos_loading_done'),
              );
        }

        final video = state.filteredVideos[index];
        final isSelected = state.selectedVideoIds.contains(video.id);
        // Stable per-video key — see youtube_results_view.dart for rationale.
        // ListView.builder reuses State by index; loadMore appends items, so
        // without ValueKey the State under the cursor gets rebound to a different
        // video → MouseRegion fires on stale widget → mouse_tracker assertion.
        return ChannelVideoItem(
          key: ValueKey<String>('channel_video_${video.id}'),
          video: video,
          isSelected: isSelected,
          onSelectionChanged:
              (_) => ref
                  .read(youtubeChannelProvider.notifier)
                  .toggleSelection(video.id),
        );
      },
    );
  }

  /// Operations bar — rises when items selected
  Widget _buildOperationsBar(
    YouTubeChannelState state,
    YouTubeChannelNotifier notifier,
    bool isDark,
  ) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors:
              isDark
                  ? [
                    AppColors.brand.withValues(alpha: AppOpacity.hover),
                    AppColors.darkBg,
                  ]
                  : [
                    Colors.white.withValues(alpha: AppOpacity.nearOpaque),
                    Colors.white,
                  ],
        ),
        border: Border(
          top: BorderSide(
            color: AppColors.brand.withValues(
              alpha: isDark ? AppOpacity.subtle : AppOpacity.pressed,
            ),
          ),
        ),
      ),
      child: Row(
        children: [
          // Target count — surveillance brackets
          Text(
            '[${state.selectedVideoIds.length}_TARGETS_ACQUIRED]',
            style: AppTypography.sectionHeader.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
              letterSpacing: 3.0,
              color: isDark ? AppColors.accentHighlight : AppColors.brand,
            ),
          ),
          const Spacer(),
          // Extract button — wine-red gradient capsule
          _ExtractButton(
            count: state.selectedVideoIds.length,
            isDark: isDark,
            onPressed: () {
              final selectedVideos = notifier.getSelectedVideos();
              final urls = selectedVideos.map((v) => v.url).toList();
              if (!widget.embedded && Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
              widget.onDownloadSelected?.call(urls);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingSkeleton(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: 8,
      itemBuilder:
          (_, __) => const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.xs),
            child: ChannelVideoSkeleton(),
          ),
    );
  }

  Widget _buildErrorState(
    YouTubeChannelState state,
    YouTubeChannelNotifier notifier,
    bool isDark,
  ) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 36,
            color:
                isDark
                    ? AppColors.accentHighlight.withValues(
                      alpha: AppOpacity.secondary,
                    )
                    : AppColors.errorRed,
          ),
          const SizedBox(height: AppSpacing.smMd),
          Text(
            state.error!,
            textAlign: TextAlign.center,
            style: AppTypography.metadata.copyWith(
              color:
                  isDark
                      ? AppColors.darkLightText.withValues(
                        alpha: AppOpacity.strong,
                      )
                      : AppColors.lightMetaText,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _ExtractButton(
            count: 0,
            isDark: isDark,
            label: AppLocalizations.commonRetry,
            icon: Icons.refresh,
            onPressed: () {
              if (state.url.isNotEmpty) {
                notifier.loadChannel(state.url);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isDark)
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.brand.withValues(alpha: AppOpacity.hover),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                Icon(
                  Icons.movie_filter_outlined,
                  size: 40,
                  color: isDark ? AppColors.darkMetaText : AppColors.lightMuted,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'NO INTELLIGENCE FILES FOUND',
            style: AppTypography.sectionHeader.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 2.5,
              color:
                  isDark
                      ? AppColors.darkLightText.withValues(
                        alpha: AppOpacity.secondary,
                      )
                      : AppColors.lightMetaText,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            "This channel's archive is empty or still being indexed.",
            style: AppTypography.statusBadge.copyWith(
              fontWeight: FontWeight.w400,
              color:
                  isDark
                      ? AppColors.darkLightText.withValues(
                        alpha: AppOpacity.medium,
                      )
                      : AppColors.lightMetaText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_outlined,
            size: 32,
            color: isDark ? AppColors.darkMetaText : AppColors.lightMuted,
          ),
          const SizedBox(height: AppSpacing.smMd),
          Text(
            'No videos match filters',
            style: AppTypography.statusBadge.copyWith(
              fontWeight: FontWeight.w400,
              color:
                  isDark
                      ? AppColors.darkLightText.withValues(
                        alpha: AppOpacity.medium,
                      )
                      : AppColors.lightMetaText,
            ),
          ),
        ],
      ),
    );
  }
}

/// Hover-aware icon button for top bar
class _HoverIconButton extends StatefulWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback onPressed;
  final String? tooltip;

  const _HoverIconButton({
    required this.icon,
    required this.isDark,
    required this.onPressed,
    this.tooltip,
  });

  @override
  State<_HoverIconButton> createState() => _HoverIconButtonState();
}

class _HoverIconButtonState extends State<_HoverIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: widget.tooltip ?? '',
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color:
                  _hovered
                      ? (widget.isDark
                          ? AppColors.brand.withValues(
                            alpha: AppOpacity.pressed,
                          )
                          : AppColors.lightSurface2)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Icon(
              widget.icon,
              size: 18,
              color:
                  widget.isDark
                      ? (_hovered
                          ? BrandConfig.current.colors.gradientTail
                          : AppColors.darkMuted)
                      : AppColors.lightMetaText,
            ),
          ),
        ),
      ),
    );
  }
}

/// Wine-red gradient capsule button — "EXTRACT [N]"
class _ExtractButton extends StatefulWidget {
  final int count;
  final bool isDark;
  final VoidCallback onPressed;
  final String? label;
  final IconData? icon;

  const _ExtractButton({
    required this.count,
    required this.isDark,
    required this.onPressed,
    this.label,
    this.icon,
  });

  @override
  State<_ExtractButton> createState() => _ExtractButtonState();
}

class _ExtractButtonState extends State<_ExtractButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final buttonLabel = widget.label ?? 'EXTRACT [${widget.count}]';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.smMd,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            gradient: LinearGradient(
              colors:
                  widget.isDark
                      ? [AppColors.brand, AppColors.accentHighlight]
                      : [AppColors.brand, AppColors.accentHighlight],
            ),
            boxShadow:
                _hovered
                    ? [
                      BoxShadow(
                        color: AppColors.accentHighlight.withValues(
                          alpha: AppOpacity.medium,
                        ),
                        blurRadius: 30,
                      ),
                    ]
                    : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                buttonLabel,
                style: AppTypography.sectionHeader.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.0,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                widget.icon ?? Icons.download,
                size: 18,
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
