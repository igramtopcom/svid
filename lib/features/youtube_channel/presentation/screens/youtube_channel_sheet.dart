import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../providers/youtube_channel_provider.dart';
import '../widgets/channel_video_item.dart';
import '../widgets/channel_video_skeleton.dart';

/// YouTube Channel browser — Nocturne Cinematic "Intelligence Terminal" dialog
class YouTubeChannelSheet extends ConsumerStatefulWidget {
  final Function(List<String> urls)? onDownloadSelected;

  /// Initial channel URL. When provided the sheet pre-fills the input
  /// and triggers `loadChannel` so the user lands on the channel
  /// content directly.
  final String? initialUrl;

  const YouTubeChannelSheet({
    super.key,
    this.onDownloadSelected,
    this.initialUrl,
  });

  /// Show the channel browser as a desktop dialog
  static Future<void> show(
    BuildContext context, {
    Function(List<String> urls)? onDownloadSelected,
    String? initialUrl,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: isDark
          ? Colors.black.withValues(alpha: AppOpacity.strong)
          : Colors.black.withValues(alpha: AppOpacity.scrim),
      builder: (context) => Dialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xl),
        clipBehavior: Clip.antiAlias,
        backgroundColor: isDark
            ? AppColors.darkBg
            : AppColors.lightBase,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: isDark
              ? BorderSide(
                  color: AppColors.darkMuted.withValues(alpha: AppOpacity.subtle),
                )
              : BorderSide.none,
        ),
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: 800, maxHeight: 720),
          child: YouTubeChannelSheet(
            onDownloadSelected: onDownloadSelected,
            initialUrl: initialUrl,
          ),
        ),
      ),
    );
  }

  @override
  ConsumerState<YouTubeChannelSheet> createState() =>
      _YouTubeChannelSheetState();
}

class _YouTubeChannelSheetState
    extends ConsumerState<YouTubeChannelSheet> {
  final _urlController = TextEditingController();
  final _urlFocusNode = FocusNode();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final initial = widget.initialUrl?.trim() ?? '';
    if (initial.isNotEmpty) {
      _urlController.text = initial;
      _urlController.selection =
          TextSelection.collapsed(offset: initial.length);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (initial.isEmpty) {
        ref.read(youtubeChannelProvider.notifier).clear();
      } else {
        // Pre-loaded URL → trigger channel fetch immediately so the
        // user sees content without manually pressing Enter.
        ref.read(youtubeChannelProvider.notifier).loadChannel(initial);
      }
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _urlController.dispose();
    _urlFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent *
            AppConstants.infiniteScrollThreshold) {
      ref.read(youtubeChannelProvider.notifier).loadMoreVideos();
    }
  }

  void _onSubmit() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    ref.read(youtubeChannelProvider.notifier).loadChannel(url);
    _urlFocusNode.unfocus();
  }

  void _handleDownload() {
    final notifier = ref.read(youtubeChannelProvider.notifier);
    final selectedVideos = notifier.getSelectedVideos();
    final urls = selectedVideos.map((v) => v.url).toList();

    if (urls.isEmpty) return;

    Navigator.of(context).pop();
    widget.onDownloadSelected?.call(urls);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(youtubeChannelProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            _buildHeader(state, isDark),
            _buildUrlInput(state, isDark),
            // Gradient accent line
            Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    AppColors.brand
                        .withValues(alpha: isDark ? AppOpacity.quarter : AppOpacity.pressed),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            Expanded(child: _buildContent(state, isDark)),
            if (state.hasSelection)
              _buildDownloadBar(state, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(YouTubeChannelState state, bool isDark) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        gradient: isDark
            ? LinearGradient(
                colors: [AppColors.darkBase, AppColors.darkBg],
              )
            : null,
        color: isDark ? null : AppColors.lightSurface2,
      ),
      child: Row(
        children: [
          // Terminal icon
          Icon(
            Icons.terminal_outlined,
            size: 16,
            color: isDark
                ? AppColors.brand
                : AppColors.brand.withValues(alpha: AppOpacity.strong),
          ),
          const SizedBox(width: AppSpacing.smMd),
          // Title + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppLocalizations.youtubeChannelBrowse.toUpperCase(),
                  style: AppTypography.compact.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.0,
                    color: isDark
                        ? AppColors.accentHighlight
                        : AppColors.brand,
                  ),
                ),
                if (state.channel != null)
                  Text(
                    AppLocalizations.youtubeChannelChannelInfo(
                      state.channel!.title,
                      state.filteredVideos.length,
                    ),
                    style: AppTypography.mini.copyWith(
                      fontFamily: 'monospace',
                      color: isDark
                          ? AppColors.darkMetaText
                          : AppColors.lightMetaText,
                    ),
                  ),
              ],
            ),
          ),
          // Sort
          if (state.filteredVideos.isNotEmpty)
            PopupMenuButton<VideoSortBy>(
              icon: Icon(
                Icons.sort,
                size: 18,
                color: isDark
                    ? AppColors.darkMetaText
                    : AppColors.lightMetaText,
              ),
              tooltip: AppLocalizations.youtubeChannelSortTooltip,
              color: isDark ? AppColors.darkBase : AppColors.lightBase,
              onSelected: (sortBy) {
                ref
                    .read(youtubeChannelProvider.notifier)
                    .setSortBy(sortBy);
              },
              itemBuilder: (context) =>
                  VideoSortBy.values.map((sortBy) {
                final isActive = state.sortBy == sortBy;
                return PopupMenuItem(
                  value: sortBy,
                  child: Text(
                    sortBy.label(context),
                    style: AppTypography.metadata.copyWith(
                      fontWeight:
                          isActive ? FontWeight.w700 : FontWeight.w400,
                      color: isActive
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
            ),
          // Select all / deselect
          if (state.filteredVideos.isNotEmpty)
            _buildSelectToggle(state, isDark),
          // Close button
          _CloseButton(
            isDark: isDark,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectToggle(YouTubeChannelState state, bool isDark) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          final notifier = ref.read(youtubeChannelProvider.notifier);
          if (state.isAllSelected) {
            notifier.deselectAll();
          } else {
            notifier.selectAll();
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: state.isAllSelected
                      ? AppColors.accentHighlight
                      : Colors.transparent,
                  border: Border.all(
                    color: state.isAllSelected
                        ? AppColors.brand
                        : (isDark
                            ? AppColors.darkMuted
                            : AppColors.lightMuted),
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: state.isAllSelected
                    ? const Icon(Icons.check,
                        size: 10, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                state.isAllSelected
                    ? AppLocalizations.youtubeChannelDeselectAll
                    : AppLocalizations.youtubeChannelSelectAll,
                style: AppTypography.compact.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.darkMetaText
                      : AppColors.lightMetaText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUrlInput(YouTubeChannelState state, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.smMd, AppSpacing.md, AppSpacing.smMd),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _urlController,
              focusNode: _urlFocusNode,
              style: AppTypography.metadata.copyWith(
                fontFamily: 'monospace',
                color: isDark
                    ? AppColors.darkLightText
                    : AppColors.darkSurface1,
              ),
              decoration: InputDecoration(
                hintText:
                    AppLocalizations.youtubeChannelUrlPlaceholder,
                hintStyle: AppTypography.metadata.copyWith(
                  fontFamily: 'monospace',
                  color: isDark
                      ? AppColors.darkMetaText
                      : AppColors.lightMuted,
                ),
                prefixIcon: Icon(
                  Icons.link,
                  size: 18,
                  color: isDark
                      ? AppColors.darkMetaText
                      : AppColors.lightMuted,
                ),
                filled: true,
                fillColor: isDark
                    ? AppColors.darkSurface1
                    : AppColors.lightElevated,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.smMd,
                  vertical: AppSpacing.smMd,
                ),
                errorText: state.error,
                errorStyle: AppTypography.compact.copyWith(
                  color: isDark
                      ? const Color(0xFFFFB4AB)
                      : AppColors.errorRed,
                ),
              ),
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _onSubmit(),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Browse button — wine-red capsule
          _BrowseButton(
            isDark: isDark,
            isLoading: state.isLoading,
            onPressed: _onSubmit,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(YouTubeChannelState state, bool isDark) {
    // Loading
    if (state.isLoading && state.videos.isEmpty) {
      return Shimmer(
        child: ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          itemCount: 6,
          itemBuilder: (_, __) => const ChannelVideoSkeleton(),
        ),
      );
    }

    // Error
    if (state.error != null && state.videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 36,
              color: isDark
                  ? AppColors.accentHighlight.withValues(alpha: AppOpacity.overlay)
                  : AppColors.errorRed,
            ),
            const SizedBox(height: AppSpacing.smMd),
            Text(
              AppLocalizations.youtubeChannelLoadFailed,
              style: AppTypography.buttonPrimary.copyWith(
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppColors.darkLightText
                    : AppColors.darkSurface1,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              state.error!,
              textAlign: TextAlign.center,
              style: AppTypography.statusBadge.copyWith(
                fontWeight: FontWeight.w400,
                color: isDark
                    ? AppColors.darkMetaText
                    : AppColors.lightMetaText,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  if (state.url.isNotEmpty) {
                    ref
                        .read(youtubeChannelProvider.notifier)
                        .loadChannel(state.url);
                  }
                },
                child: Text(
                  AppLocalizations.downloadsRetry.toUpperCase(),
                  style: AppTypography.compact.copyWith(
                    fontFamily: 'monospace',
                    letterSpacing: 2.0,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? BrandConfig.current.colors.gradientTail
                        : AppColors.brand,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Empty — no URL entered yet
    if (state.videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 100,
              height: 100,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (isDark)
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppColors.brand.withValues(alpha: AppOpacity.divider),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  Icon(
                    Icons.person_search_outlined,
                    size: 36,
                    color: isDark
                        ? AppColors.darkMetaText
                        : AppColors.lightMuted,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              AppLocalizations.youtubeChannelEmptyTitle.toUpperCase(),
              style: AppTypography.sectionHeader.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 2.0,
                color: isDark
                    ? AppColors.darkLightText
                    : AppColors.lightMetaText,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              AppLocalizations.youtubeChannelEmptyDescription,
              textAlign: TextAlign.center,
              style: AppTypography.statusBadge.copyWith(
                fontWeight: FontWeight.w400,
                color: isDark
                    ? AppColors.darkMetaText
                    : AppColors.lightMetaText,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // URL format hints — monospace tags
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: ['@username', '/channel/ID', '/c/name']
                  .map((hint) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.smMd, vertical: AppSpacing.xs),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.darkBase
                              : AppColors.lightSurface3,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          hint,
                          style: AppTypography.compact.copyWith(
                            fontFamily: 'monospace',
                            color: isDark
                                ? AppColors.darkMetaText
                                : AppColors.lightMetaText,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ),
      );
    }

    // Video list with channel header
    return Column(
      children: [
        // Compact channel header
        if (state.channel != null)
          _buildChannelHeader(state, isDark),
        // Gradient line
        Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                AppColors.brand
                    .withValues(alpha: isDark ? AppOpacity.subtle : AppOpacity.hover),
                Colors.transparent,
              ],
            ),
          ),
        ),
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
          child: SizedBox(
            height: 38,
            child: TextField(
              style: AppTypography.statusBadge.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w400,
                letterSpacing: 1.0,
                color: isDark
                    ? AppColors.darkLightText
                    : AppColors.darkSurface1,
              ),
              decoration: InputDecoration(
                hintText:
                    AppLocalizations.youtubeChannelSearchVideos,
                hintStyle: AppTypography.statusBadge.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w400,
                  color: isDark
                      ? AppColors.darkMetaText
                      : AppColors.lightMuted,
                ),
                prefixIcon: Icon(
                  Icons.radar_outlined,
                  size: 16,
                  color: isDark
                      ? AppColors.darkMetaText
                      : AppColors.lightMuted,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 38,
                  maxHeight: 38,
                ),
                suffixIcon: state.searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          size: 14,
                          color: isDark
                              ? AppColors.darkMetaText
                              : AppColors.lightMuted,
                        ),
                        onPressed: () {
                          ref
                              .read(youtubeChannelProvider.notifier)
                              .setSearchQuery('');
                        },
                      )
                    : null,
                suffixIconConstraints: const BoxConstraints(
                  minHeight: 38,
                  maxHeight: 38,
                ),
                filled: true,
                fillColor: isDark
                    ? AppColors.darkSurface1
                    : AppColors.lightElevated,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.fromLTRB(
                  AppSpacing.smMd,
                  -8,
                  AppSpacing.smMd,
                  0,
                ),
                isDense: false,
              ),
              textAlignVertical: TextAlignVertical.center,
              onChanged: (value) {
                ref
                    .read(youtubeChannelProvider.notifier)
                    .setSearchQuery(value);
              },
            ),
          ),
        ),
        // Video list
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: state.filteredVideos.length +
                (state.hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == state.filteredVideos.length) {
                return state.isLoadingMore
                    ? Shimmer(
                        key: const ValueKey('channel_sheet_loading_more'),
                        child: const ChannelVideoSkeleton())
                    : const SizedBox.shrink(
                        key: ValueKey('channel_sheet_loading_done'),
                      );
              }

              final video = state.filteredVideos[index];
              final isSelected =
                  state.selectedVideoIds.contains(video.id);

              // Stable per-video key — see youtube_results_view.dart for rationale.
              return ChannelVideoItem(
                key: ValueKey<String>('channel_sheet_video_${video.id}'),
                video: video,
                isSelected: isSelected,
                onSelectionChanged: (selected) {
                  ref
                      .read(youtubeChannelProvider.notifier)
                      .toggleSelection(video.id);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildChannelHeader(
      YouTubeChannelState state, bool isDark) {
    final channel = state.channel!;

    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.smMd, AppSpacing.md, AppSpacing.smMd),
      color: isDark ? AppColors.darkBg : AppColors.lightSurface2,
      child: Row(
        children: [
          // Avatar — 48px with grayscale noir filter
          SizedBox(
            width: 48,
            height: 48,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: ColorFiltered(
                colorFilter: isDark
                    ? const ColorFilter.matrix(<double>[
                        0.33, 0.33, 0.33, 0, 0,
                        0.33, 0.33, 0.33, 0, 0,
                        0.33, 0.33, 0.33, 0, 0,
                        0, 0, 0, 1, 0,
                      ])
                    : const ColorFilter.mode(
                        Colors.transparent, BlendMode.multiply),
                child: channel.highQualityThumbnail != null
                    ? Image.network(
                        channel.highQualityThumbnail!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _buildAvatarPlaceholder(isDark),
                      )
                    : _buildAvatarPlaceholder(isDark),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.smMd),
          // Channel info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  channel.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.fileName.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: isDark
                        ? AppColors.darkLightText
                        : AppColors.darkSurface1,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                // Stats in surveillance brackets
                Text(
                  '[${channel.formattedSubscriberCount.toUpperCase()} \u00b7 ${AppLocalizations.youtubeChannelVideosCount(state.videos.length).toUpperCase()}]',
                  style: AppTypography.mini.copyWith(
                    fontFamily: 'monospace',
                    letterSpacing: 1.0,
                    color: isDark
                        ? AppColors.darkMetaText
                        : AppColors.lightMetaText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadBar(YouTubeChannelState state, bool isDark) {
    final count = state.selectedVideoIds.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.smMd, AppSpacing.md, AppSpacing.smMd),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [
                  AppColors.brand.withValues(alpha: AppOpacity.divider),
                  AppColors.darkBg,
                ]
              : [
                  Colors.white.withValues(alpha: AppOpacity.nearOpaque),
                  Colors.white,
                ],
        ),
        border: Border(
          top: BorderSide(
            color: AppColors.brand
                .withValues(alpha: isDark ? AppOpacity.subtle : AppOpacity.pressed),
          ),
        ),
      ),
      child: Row(
        children: [
          // Target count — surveillance brackets
          Text(
            '[${count}_SELECTED]',
            style: AppTypography.sectionHeader.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
              letterSpacing: 2.0,
              color: isDark
                  ? AppColors.accentHighlight
                  : AppColors.brand,
            ),
          ),
          const Spacer(),
          // Download capsule button
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _handleDownload,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.mdLg, vertical: AppSpacing.smMd),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  gradient: LinearGradient(
                    colors: [
                      AppColors.brand,
                      AppColors.accentHighlight,
                    ],
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.download,
                        size: 16, color: Colors.white),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      AppLocalizations.youtubeChannelDownloadCount(
                          count),
                      style: AppTypography.sectionHeader.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarPlaceholder(bool isDark) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkElevated : AppColors.lightSurface3,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.person_outline,
        size: 24,
        color: isDark ? AppColors.darkMuted : AppColors.lightMuted,
      ),
    );
  }
}

/// Close button with hover effect
class _CloseButton extends StatefulWidget {
  final bool isDark;
  final VoidCallback onPressed;

  const _CloseButton({required this.isDark, required this.onPressed});

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Tooltip(
          message: AppLocalizations.commonClose,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: _hovered
                  ? (widget.isDark
                      ? AppColors.brand.withValues(alpha: AppOpacity.pressed)
                      : AppColors.lightSurface2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Icon(
              Icons.close,
              size: 18,
              color: widget.isDark
                  ? (_hovered
                      ? BrandConfig.current.colors.gradientTail
                      : AppColors.darkMetaText)
                  : AppColors.lightMetaText,
            ),
          ),
        ),
      ),
    );
  }
}

/// Browse button — wine-red style
class _BrowseButton extends StatefulWidget {
  final bool isDark;
  final bool isLoading;
  final VoidCallback onPressed;

  const _BrowseButton({
    required this.isDark,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  State<_BrowseButton> createState() => _BrowseButtonState();
}

class _BrowseButtonState extends State<_BrowseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.isLoading
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.isLoading ? null : widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.smMd),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            color: _hovered && !widget.isLoading
                ? AppColors.accentHighlight
                : AppColors.brand,
          ),
          child: widget.isLoading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.search,
                        size: 16, color: Colors.white),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      AppLocalizations.youtubeChannelBrowseButton,
                      style: AppTypography.sectionHeader.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
