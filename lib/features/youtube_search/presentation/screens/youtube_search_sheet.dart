import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../../domain/entities/youtube_search_result.dart';
import '../providers/youtube_search_provider.dart';
import '../providers/recent_searches_provider.dart';
import '../providers/youtube_autocomplete_provider.dart';
import '../widgets/youtube_search_bar.dart';
import '../widgets/youtube_search_result_item.dart';
import '../widgets/youtube_search_skeleton.dart';
import '../widgets/autocomplete_suggestions.dart';
import '../widgets/search_filters_bar.dart';

/// Full-screen YouTube search sheet
class YouTubeSearchSheet extends ConsumerStatefulWidget {
  /// Callback when a video card is tapped — closes the dialog and downloads
  final void Function(String url)? onVideoSelected;

  /// Callback when the download button is tapped — downloads WITHOUT closing the dialog
  final void Function(String url)? onVideoDownload;

  /// Initial search keyword. When non-empty, the sheet pre-fills the
  /// search field and runs the search immediately so the user lands
  /// on results instead of an empty state. Wired by the home smart
  /// input when the user types a keyword in the URL field and submits.
  final String? initialKeyword;

  const YouTubeSearchSheet({
    super.key,
    this.onVideoSelected,
    this.onVideoDownload,
    this.initialKeyword,
  });

  /// Show the search sheet as a desktop dialog
  static Future<void> show(
    BuildContext context, {
    void Function(String url)? onVideoSelected,
    void Function(String url)? onVideoDownload,
    String? initialKeyword,
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
              child: YouTubeSearchSheet(
                onVideoSelected: onVideoSelected,
                onVideoDownload: onVideoDownload,
                initialKeyword: initialKeyword,
              ),
            ),
          ),
    );
  }

  @override
  ConsumerState<YouTubeSearchSheet> createState() => _YouTubeSearchSheetState();
}

class _YouTubeSearchSheetState extends ConsumerState<YouTubeSearchSheet> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    // Pre-fill BEFORE attaching the text-change listener so the
    // initial seed doesn't fire `_onSearchTextChanged` during
    // initState. The listener triggers
    // `AutocompleteNotifier.fetchSuggestions`, which mutates a
    // Riverpod provider — doing that during the build phase throws
    // `StateNotifierListenerError` (the crash spam in log.md
    // line 165-211 from the previous iteration).
    final initial = widget.initialKeyword?.trim() ?? '';
    if (initial.isNotEmpty) {
      _searchController.text = initial;
      _searchController.selection = TextSelection.collapsed(
        offset: initial.length,
      );
    }
    _searchController.addListener(_onSearchTextChanged);

    // Auto-focus search field, kick off the initial search after the
    // first frame so the search provider is safe to mutate.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocusNode.requestFocus();
      if (initial.isNotEmpty) {
        _onSearch();
      }
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchTextChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchTextChanged() {
    final query = _searchController.text;

    // Clear search state if text is empty
    if (query.trim().isEmpty) {
      ref.read(youtubeSearchProvider.notifier).clear();
      ref.read(youtubeAutocompleteProvider.notifier).clear();
      return;
    }

    // Trigger autocomplete suggestions
    ref.read(youtubeAutocompleteProvider.notifier).fetchSuggestions(query);
  }

  void _onScroll() {
    if (!mounted) return;
    if (!_scrollController.hasClients) return;

    // Start fetching before the user reaches the hard bottom. yt-dlp search
    // pagination re-queries a larger result window, so waiting until 80-100%
    // makes the sheet feel stalled even when the fetch is working.
    if (_scrollController.position.extentAfter <= 600) {
      ref.read(youtubeSearchProvider.notifier).loadMore();
    }
  }

  void _onSearch() {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      ref.read(youtubeSearchProvider.notifier).search(query);
      // Save to recent searches
      ref.read(recentSearchesProvider.notifier).addSearch(query);
    }
  }

  void _onRecentSearchTap(String keyword) {
    _searchController.text = keyword;
    _onSearch();
  }

  void _onVideoTap(YouTubeSearchResult video) {
    // Close dialog
    Navigator.of(context).pop();
    // Trigger callback with video URL
    widget.onVideoSelected?.call(video.url);
  }

  /// Download button: start download without closing the search dialog
  void _onVideoDownload(YouTubeSearchResult video) {
    widget.onVideoDownload?.call(video.url);
    AppSnackBar.success(
      context,
      message: AppLocalizations.youtubeSearchDownloadStarted,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final state = ref.watch(youtubeSearchProvider);
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
            _buildHeader(context, theme, isDark),

            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.smMd,
                AppSpacing.md,
                AppSpacing.smMd,
              ),
              child: YouTubeSearchBar(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onSearch: _onSearch,
                isLoading: state.isLoading,
              ),
            ),

            // Filters bar (only show when has results or searching)
            if (state.results.isNotEmpty || state.isLoading)
              SearchFiltersBar(
                filters: state.filters,
                onFiltersChanged: (filters) {
                  ref
                      .read(youtubeSearchProvider.notifier)
                      .updateFilters(filters);
                },
              ),

            // Ghost divider
            Container(
              height: 0.5,
              color:
                  isDark
                      ? AppColors.homeDarkBorderStrong
                      : theme.colorScheme.outlineVariant.withValues(
                        alpha: AppOpacity.quarter,
                      ),
            ),

            // Content
            Expanded(child: _buildContent(context, theme, isDark, state)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme, bool isDark) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.smMd),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBg : null,
        border: Border(
          bottom: BorderSide(
            color:
                isDark
                    ? AppColors.homeDarkBorderStrong
                    : theme.colorScheme.outlineVariant.withValues(
                      alpha: AppOpacity.quarter,
                    ),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // YouTube branding
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
                  Icons.play_arrow,
                  color: AppColors.darkLightText,
                  size: 18,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  AppLocalizations.youtubeSearchTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppColors.darkLightText,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.smMd),
          Text(
            AppLocalizations.youtubeSearchSearch,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w500,
              color:
                  isDark
                      ? AppColors.darkMetaText
                      : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
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

  Widget _buildContent(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    YouTubeSearchState state,
  ) {
    // Check if we should show autocomplete suggestions
    final autocompleteState = ref.watch(youtubeAutocompleteProvider);
    final currentText = _searchController.text.trim();

    final shouldShowAutocomplete =
        currentText.isNotEmpty &&
        currentText != state.query &&
        !state.isLoading &&
        (autocompleteState.suggestions.isNotEmpty ||
            autocompleteState.isLoading);

    // Show autocomplete suggestions
    if (shouldShowAutocomplete) {
      return AutocompleteSuggestions(
        onSuggestionTap: (suggestion) {
          _searchController.text = suggestion;
          _onSearch();
        },
      );
    }

    // Loading state — skeleton shimmer (no featured card in search dialog)
    if (state.isLoading) {
      return const YouTubeSearchSkeleton(featured: false);
    }

    // Initial-search error state. Pagination errors are rendered inline below
    // existing results so a transient fetch-more failure doesn't wipe the list.
    if (state.error != null && state.results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
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
                AppLocalizations.youtubeSearchFailed,
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
                          ? AppColors.darkMetaText
                          : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: _onSearch,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(AppLocalizations.downloadsRetry),
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

    // Empty state (no search yet)
    if (state.query.isEmpty) {
      return _buildEmptyState(theme, isDark);
    }

    // No results
    if (state.results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off,
                size: 48,
                color:
                    isDark
                        ? AppColors.darkMuted
                        : theme.colorScheme.outlineVariant,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                AppLocalizations.youtubeSearchNoVideos,
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
                AppLocalizations.youtubeSearchTip,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color:
                      isDark
                          ? AppColors.darkMetaText
                          : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Results list
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount:
          state.results.length +
          (state.isLoadingMore || state.error != null ? 1 : 0),
      itemBuilder: (context, index) {
        // Loading more — skeleton items
        if (index == state.results.length) {
          if (state.error != null) {
            return _buildLoadMoreError(theme, isDark);
          }
          return const Padding(
            key: ValueKey('youtube_sheet_loading_more'),
            padding: EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.md),
            child: YouTubeSearchSkeleton(
              featured: false,
              itemCount: 3,
              shrinkWrap: true,
            ),
          );
        }

        final video = state.results[index];
        // Stable per-URL key — see youtube_results_view.dart for rationale.
        // loadMore() appends items, so without ValueKey ListView reuses State
        // by index → MouseRegion fires on stale widget → mouse_tracker assertion.
        return YouTubeSearchResultItem(
          key: ValueKey<String>('yt_sheet_${video.url}'),
          video: video,
          onTap: () => _onVideoTap(video),
          onDownload:
              widget.onVideoDownload != null
                  ? () => _onVideoDownload(video)
                  : null,
        );
      },
    );
  }

  Widget _buildLoadMoreError(ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
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

  Widget _buildEmptyState(ThemeData theme, bool isDark) {
    final recentSearchesAsync = ref.watch(recentSearchesProvider);

    return recentSearchesAsync.when(
      loading:
          () => Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(
                isDark ? AppColors.accentHighlight : theme.colorScheme.primary,
              ),
            ),
          ),
      error: (_, __) => _buildEmptyStateContent(theme, isDark, null),
      data:
          (recentSearches) =>
              _buildEmptyStateContent(theme, isDark, recentSearches),
    );
  }

  Widget _buildEmptyStateContent(
    ThemeData theme,
    bool isDark,
    List<String>? recentSearches,
  ) {
    final hasRecentSearches =
        recentSearches != null && recentSearches.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.youtube_searched_for,
            size: 56,
            color:
                isDark
                    ? AppColors.darkMuted
                    : theme.colorScheme.outlineVariant,
          ),
          const SizedBox(height: AppSpacing.mdLg),
          Text(
            AppLocalizations.youtubeSearchSearchTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkLightText : null,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            AppLocalizations.youtubeSearchHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color:
                  isDark
                      ? AppColors.darkMetaText
                      : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Recent Searches Section
          if (hasRecentSearches) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppLocalizations.youtubeSearchRecentSearches,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkLightText : null,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    ref.read(recentSearchesProvider.notifier).clearAll();
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text(AppLocalizations.commonClearAll),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    textStyle: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.smMd),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children:
                  recentSearches.map((keyword) {
                    return _buildRecentSearchChip(theme, isDark, keyword);
                  }).toList(),
            ),
            const SizedBox(height: AppSpacing.lg),
            Container(
              height: 0.5,
              color:
                  isDark
                      ? AppColors.homeDarkBorderStrong
                      : theme.colorScheme.outlineVariant.withValues(
                        alpha: AppOpacity.quarter,
                      ),
            ),
            const SizedBox(height: AppSpacing.mdLg),
          ],

          // Suggestions
          Text(
            hasRecentSearches
                ? AppLocalizations.youtubeSearchSuggestions
                : AppLocalizations.youtubeSearchPopularSearches,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkMetaText : null,
            ),
          ),
          const SizedBox(height: AppSpacing.smMd),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            alignment: WrapAlignment.center,
            children: [
              _buildSuggestionChip(
                theme,
                isDark,
                AppLocalizations.youtubeSearchSuggestionMusic,
              ),
              _buildSuggestionChip(
                theme,
                isDark,
                AppLocalizations.youtubeSearchSuggestionTutorials,
              ),
              _buildSuggestionChip(
                theme,
                isDark,
                AppLocalizations.youtubeSearchSuggestionGaming,
              ),
              _buildSuggestionChip(
                theme,
                isDark,
                AppLocalizations.youtubeSearchSuggestionNews,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSearchChip(ThemeData theme, bool isDark, String keyword) {
    return InputChip(
      label: Text(
        keyword,
        style: theme.textTheme.titleSmall?.copyWith(
          color: isDark ? AppColors.darkLightText : null,
        ),
      ),
      avatar: Icon(
        Icons.history,
        size: 16,
        color: isDark ? AppColors.darkMetaText : null,
      ),
      deleteIcon: Icon(
        Icons.close,
        size: 14,
        color: isDark ? AppColors.darkMuted : null,
      ),
      onPressed: () => _onRecentSearchTap(keyword),
      onDeleted: () {
        ref.read(recentSearchesProvider.notifier).removeSearch(keyword);
      },
      backgroundColor:
          isDark
              ? AppColors.homeDarkCardBg
              : theme.colorScheme.surfaceContainerHighest,
      side:
          isDark
              ? BorderSide(color: AppColors.homeDarkBorderStrong, width: 0.5)
              : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
    );
  }

  Widget _buildSuggestionChip(ThemeData theme, bool isDark, String label) {
    return ActionChip(
      label: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: isDark ? AppColors.accentHighlight : null,
        ),
      ),
      avatar: Icon(
        Icons.search,
        size: 16,
        color: isDark ? AppColors.accentHighlight : null,
      ),
      onPressed: () {
        _searchController.text = label;
        _onSearch();
      },
      backgroundColor: isDark ? AppColors.homeDarkCardBg : null,
      side:
          isDark
              ? BorderSide(
                color: AppColors.brand.withValues(alpha: AppOpacity.scrim),
                width: 0.5,
              )
              : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
    );
  }
}
