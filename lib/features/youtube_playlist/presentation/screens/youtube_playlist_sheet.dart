import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../providers/youtube_playlist_provider.dart';
import '../widgets/playlist_video_item.dart';
import '../widgets/playlist_video_skeleton.dart';

/// YouTube Playlist Browser — desktop dialog with URL input + lazy-loaded video list + multi-select
class YouTubePlaylistSheet extends ConsumerStatefulWidget {
  /// Invoked when the user confirms the selected videos. The
  /// optional [playlistId] / [playlistTitle] args carry the source
  /// playlist's identity (extracted from yt-dlp metadata) — the home
  /// batch flow stamps every download row with this id so the
  /// `FilterTab.playlist` view groups them automatically. The id is
  /// prefixed `yt_<youtube_list_id>` to leave the `user_*` namespace
  /// free for the future "Add to playlist" curated collections.
  final void Function(
    List<String> urls, {
    String? playlistId,
    String? playlistTitle,
  })?
  onDownloadSelected;

  /// Initial playlist URL — pre-fills the input and triggers
  /// `loadPlaylist` so the user lands on playlist content directly.
  final String? initialUrl;

  const YouTubePlaylistSheet({
    super.key,
    this.onDownloadSelected,
    this.initialUrl,
  });

  static Future<void> show(
    BuildContext context, {
    void Function(
      List<String> urls, {
      String? playlistId,
      String? playlistTitle,
    })?
    onDownloadSelected,
    String? initialUrl,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (context) => Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.xl,
            ),
            clipBehavior: Clip.antiAlias,
            backgroundColor: isDark ? AppColors.darkBase : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800, maxHeight: 720),
              child: YouTubePlaylistSheet(
                onDownloadSelected: onDownloadSelected,
                initialUrl: initialUrl,
              ),
            ),
          ),
    );
  }

  @override
  ConsumerState<YouTubePlaylistSheet> createState() =>
      _YouTubePlaylistSheetState();
}

class _YouTubePlaylistSheetState extends ConsumerState<YouTubePlaylistSheet> {
  final _urlController = TextEditingController();
  final _urlFocusNode = FocusNode();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    final initial = widget.initialUrl?.trim() ?? '';
    if (initial.isNotEmpty) {
      _urlController.text = initial;
      _urlController.selection = TextSelection.collapsed(
        offset: initial.length,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _urlFocusNode.requestFocus();
      if (initial.isNotEmpty) {
        // Auto-fetch playlist content so the sheet opens populated.
        ref.read(youtubePlaylistProvider.notifier).loadPlaylist(initial);
        _urlFocusNode.unfocus();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _urlController.dispose();
    _urlFocusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    final position = _scrollController.position;
    final threshold =
        position.maxScrollExtent * AppConstants.infiniteScrollThreshold;

    if (position.pixels >= threshold) {
      ref.read(youtubePlaylistProvider.notifier).loadMore();
    }
  }

  void _onSubmit() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    ref.read(youtubePlaylistProvider.notifier).loadPlaylist(url);
    _urlFocusNode.unfocus();
  }

  void _handleDownload() {
    final selectedVideos =
        ref.read(youtubePlaylistProvider.notifier).getSelectedVideos();
    final urls = selectedVideos.map((v) => v.url).toList();

    if (urls.isEmpty) return;

    // Capture playlist identity BEFORE pop — once the dialog detaches
    // its provider container scope can shrink and `state.playlist`
    // would round-trip through a default empty state.
    final playlist = ref.read(youtubePlaylistProvider).playlist;
    final rawPlaylistId = playlist?.id.trim();
    final playlistId =
        rawPlaylistId != null && rawPlaylistId.isNotEmpty
            ? 'yt_$rawPlaylistId'
            : null;
    final playlistTitle = playlist?.title;

    Navigator.of(context).pop();
    widget.onDownloadSelected?.call(
      urls,
      playlistId: playlistId,
      playlistTitle: playlistTitle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final state = ref.watch(youtubePlaylistProvider);
    final ghostColor = AppColors.darkMuted;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape):
            () => Navigator.of(context).pop(),
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            // Header
            _buildHeader(context, theme, isDark, state),

            // URL Input
            _buildUrlInput(theme, isDark, state),

            // Ghost divider
            Container(
              height: 0.5,
              color:
                  isDark
                      ? ghostColor.withValues(alpha: AppOpacity.subtle)
                      : theme.colorScheme.outlineVariant.withValues(
                        alpha: AppOpacity.quarter,
                      ),
            ),

            // Content area
            Expanded(child: _buildContent(theme, isDark, state)),

            // Bottom bar for download
            if (state.hasSelection) _buildDownloadBar(theme, isDark, state),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    YouTubePlaylistState state,
  ) {
    final ghostColor = AppColors.darkMuted;

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.smMd),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBg : null,
        border: Border(
          bottom: BorderSide(
            color:
                isDark
                    ? ghostColor.withValues(alpha: AppOpacity.subtle)
                    : theme.colorScheme.outlineVariant.withValues(
                      alpha: AppOpacity.quarter,
                    ),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.brand,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.playlist_play,
                  color: AppColors.darkLightText,
                  size: 18,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  AppLocalizations.youtubePlaylistTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppColors.darkLightText,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Select All / Deselect All
          if (state.videos.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                if (state.isAllSelected) {
                  ref.read(youtubePlaylistProvider.notifier).deselectAll();
                } else {
                  ref.read(youtubePlaylistProvider.notifier).selectAll();
                }
              },
              icon: Icon(
                state.isAllSelected
                    ? Icons.remove_done_rounded
                    : Icons.done_all_rounded,
                size: 16,
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accentHighlight,
                textStyle: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
              label: Text(
                state.isAllSelected
                    ? AppLocalizations.youtubePlaylistDeselectAll
                    : AppLocalizations.youtubePlaylistSelectAll,
              ),
            ),
          IconButton(
            icon: Icon(
              Icons.close,
              size: 20,
              color:
                  isDark
                      ? AppColors.darkMetaText
                      : theme.colorScheme.onSurfaceVariant,
            ),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: AppLocalizations.commonClose,
            hoverColor: AppColors.accentHighlight.withValues(
              alpha: AppOpacity.subtle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUrlInput(
    ThemeData theme,
    bool isDark,
    YouTubePlaylistState state,
  ) {
    final ghostColor = AppColors.darkMuted;
    final metadataColor = AppColors.darkMetaText;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.smMd,
        AppSpacing.md,
        AppSpacing.smMd,
      ),
      child: TextField(
        controller: _urlController,
        focusNode: _urlFocusNode,
        style: AppTypography.input.copyWith(
          color: isDark ? AppColors.darkLightText : theme.colorScheme.onSurface,
        ),
        decoration: InputDecoration(
          hintText: AppLocalizations.youtubePlaylistUrlPlaceholder,
          hintStyle: AppTypography.inputHint.copyWith(
            color:
                isDark
                    ? metadataColor.withValues(alpha: AppOpacity.secondary)
                    : theme.colorScheme.onSurface.withValues(
                      alpha: AppOpacity.scrim,
                    ),
          ),
          prefixIcon: Icon(
            Icons.link_rounded,
            size: 18,
            color:
                isDark
                    ? metadataColor
                    : theme.colorScheme.onSurface.withValues(
                      alpha: AppOpacity.medium,
                    ),
          ),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_urlController.text.isNotEmpty)
                IconButton(
                  icon: Icon(
                    Icons.clear_rounded,
                    size: 16,
                    color:
                        isDark
                            ? metadataColor
                            : theme.colorScheme.onSurface.withValues(
                              alpha: AppOpacity.medium,
                            ),
                  ),
                  onPressed: () {
                    _urlController.clear();
                    setState(() {});
                  },
                ),
              if (state.isLoading)
                Padding(
                  padding: EdgeInsets.all(AppSpacing.smMd),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(
                        AppColors.accentHighlight,
                      ),
                    ),
                  ),
                )
              else
                IconButton(
                  icon: Icon(
                    Icons.search_rounded,
                    size: 20,
                    color:
                        isDark
                            ? metadataColor
                            : theme.colorScheme.onSurface.withValues(
                              alpha: AppOpacity.overlay,
                            ),
                  ),
                  onPressed: _onSubmit,
                ),
            ],
          ),
          filled: true,
          fillColor: isDark ? AppColors.darkBg : AppColors.lightSurface2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
            borderSide: BorderSide(
              color:
                  isDark
                      ? ghostColor.withValues(alpha: AppOpacity.subtle)
                      : theme.colorScheme.outlineVariant.withValues(
                        alpha: AppOpacity.quarter,
                      ),
              width: 0.5,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
            borderSide: BorderSide(
              color: AppColors.accentHighlight,
              width: 1.5,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
            borderSide: BorderSide(color: theme.colorScheme.error, width: 1.5),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
            borderSide: BorderSide(color: theme.colorScheme.error, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.smMd,
          ),
          errorText: state.error,
        ),
        onSubmitted: (_) => _onSubmit(),
        onChanged: (_) => setState(() {}),
        enabled: !state.isLoading,
      ),
    );
  }

  Widget _buildContent(
    ThemeData theme,
    bool isDark,
    YouTubePlaylistState state,
  ) {
    final ghostColor = AppColors.darkMuted;
    final metadataColor = AppColors.darkMetaText;

    // Loading initial page
    if (state.isLoading && state.videos.isEmpty) {
      return Shimmer(
        child: ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          itemCount: 8,
          itemBuilder: (_, __) => const PlaylistVideoSkeleton(),
        ),
      );
    }

    // Error state
    if (state.error != null && state.videos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                AppLocalizations.youtubePlaylistLoadFailed,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                state.error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color:
                      isDark
                          ? metadataColor
                          : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: () {
                  ref.read(youtubePlaylistProvider.notifier).clearError();
                  _urlFocusNode.requestFocus();
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(AppLocalizations.youtubePlaylistTryAgain),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  foregroundColor: AppColors.darkLightText,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Empty state
    if (state.videos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.playlist_play,
                size: 48,
                color: isDark ? ghostColor : theme.colorScheme.outlineVariant,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                AppLocalizations.youtubePlaylistEmptyTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  color:
                      isDark
                          ? AppColors.darkLightText
                          : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                AppLocalizations.youtubePlaylistEmptyDescription,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color:
                      isDark
                          ? metadataColor
                          : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Video list with infinite scroll
    return ListView.builder(
      controller: _scrollController,
      itemCount: state.videos.length + (state.isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == state.videos.length) {
          return Shimmer(
            key: const ValueKey('playlist_loading_more'),
            child: const PlaylistVideoSkeleton(),
          );
        }

        final video = state.videos[index];
        final isSelected = state.selectedVideoIds.contains(video.id);

        // Stable per-video key — see youtube_results_view.dart for rationale.
        return PlaylistVideoItem(
          key: ValueKey<String>('playlist_video_${video.id}'),
          video: video,
          isSelected: isSelected,
          onSelectionChanged: (selected) {
            ref
                .read(youtubePlaylistProvider.notifier)
                .toggleSelection(video.id);
          },
        );
      },
    );
  }

  Widget _buildDownloadBar(
    ThemeData theme,
    bool isDark,
    YouTubePlaylistState state,
  ) {
    final count = state.selectedVideoIds.length;
    final ghostColor = AppColors.darkMuted;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.smMd,
        AppSpacing.md,
        AppSpacing.smMd,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBg : null,
        border: Border(
          top: BorderSide(
            color:
                isDark
                    ? ghostColor.withValues(alpha: AppOpacity.subtle)
                    : theme.colorScheme.outlineVariant.withValues(
                      alpha: AppOpacity.quarter,
                    ),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            AppLocalizations.youtubePlaylistSelectedCount(count),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.darkLightText : null,
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _handleDownload,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(
              AppLocalizations.youtubePlaylistDownloadSelected(count),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brand,
              foregroundColor: AppColors.darkLightText,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
