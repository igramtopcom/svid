import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../../../core/providers/backend_providers.dart';
import '../../../youtube_channel/presentation/screens/subscriptions_screen.dart';
import '../providers/recent_searches_provider.dart';
import '../providers/youtube_autocomplete_provider.dart';
import '../providers/youtube_explore_provider.dart';
import '../widgets/youtube_discovery_view.dart';
import '../widgets/youtube_results_view.dart';

class YouTubeExploreScreen extends ConsumerStatefulWidget {
  final void Function(String url) onVideoDownload;
  final void Function(List<String> urls)? onBatchDownloadSelected;
  final ExploreSection initialSection;

  const YouTubeExploreScreen({
    super.key,
    required this.onVideoDownload,
    this.onBatchDownloadSelected,
    this.initialSection = ExploreSection.discovery,
  });

  @override
  ConsumerState<YouTubeExploreScreen> createState() =>
      _YouTubeExploreScreenState();
}

class _YouTubeExploreScreenState extends ConsumerState<YouTubeExploreScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _searchInputKey = GlobalKey();
  final _layerLink = LayerLink();
  OverlayEntry? _autocompleteOverlay;
  double _autocompleteWidth = 500;
  int _highlightedIndex = -1;
  List<String> _currentItems = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchTextChanged);
    _searchFocusNode.addListener(_onFocusChanged);
    if (widget.initialSection != ExploreSection.discovery) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(youtubeExploreProvider.notifier)
            .switchSection(widget.initialSection);
      });
    }
  }

  @override
  void dispose() {
    _removeAutocompleteOverlay();
    _searchController.removeListener(_onSearchTextChanged);
    _searchFocusNode.removeListener(_onFocusChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchTextChanged() {
    final text = _searchController.text.trim();
    if (text.isNotEmpty) {
      ref.read(youtubeAutocompleteProvider.notifier).fetchSuggestions(text);
      _showAutocompleteOverlay();
    } else {
      ref.read(youtubeAutocompleteProvider.notifier).clear();
      _removeAutocompleteOverlay();
    }
    _highlightedIndex = -1;
    setState(() {});
  }

  void _onFocusChanged() {
    if (!_searchFocusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && !_searchFocusNode.hasFocus) {
          _removeAutocompleteOverlay();
        }
      });
    } else if (_searchController.text.trim().isNotEmpty) {
      _showAutocompleteOverlay();
    }
  }

  void _showAutocompleteOverlay() {
    _syncAutocompleteGeometry();
    if (_autocompleteOverlay != null) {
      _autocompleteOverlay!.markNeedsBuild();
      return;
    }
    _autocompleteOverlay = OverlayEntry(
      builder: (context) => _buildAutocompleteOverlay(),
    );
    Overlay.of(context).insert(_autocompleteOverlay!);
  }

  void _syncAutocompleteGeometry() {
    final renderObject = _searchInputKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;

    final fieldWidth = renderObject.size.width;
    _autocompleteWidth =
        fieldWidth < 320
            ? fieldWidth
            : fieldWidth.clamp(320.0, 720.0).toDouble();
  }

  void _removeAutocompleteOverlay() {
    _autocompleteOverlay?.remove();
    _autocompleteOverlay = null;
    _highlightedIndex = -1;
    _currentItems = [];
  }

  void _onSuggestionTap(String suggestion) {
    _searchController.text = suggestion;
    _searchController.selection = TextSelection.collapsed(
      offset: suggestion.length,
    );
    _removeAutocompleteOverlay();
    _performSearch(suggestion);
  }

  void _performSearch(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _removeAutocompleteOverlay();
    _searchFocusNode.unfocus();
    ref.read(analyticsServiceProvider).track('search_performed', {
      'platform': 'youtube',
    });
    ref.read(recentSearchesProvider.notifier).addSearch(trimmed);
    ref.read(youtubeExploreProvider.notifier).switchToSearch(trimmed);
  }

  void _onBackToDiscovery() {
    _searchController.clear();
    ref.read(youtubeAutocompleteProvider.notifier).clear();
    ref.read(youtubeExploreProvider.notifier).backToDiscovery();
  }

  void _onDiscoverySearch(String query) {
    _searchController.text = query;
    _searchController.selection = TextSelection.collapsed(offset: query.length);
    _performSearch(query);
  }

  void _switchSection(ExploreSection section) {
    _removeAutocompleteOverlay();
    _searchFocusNode.unfocus();
    ref.read(youtubeExploreProvider.notifier).switchSection(section);
  }

  Future<void> _pasteFromClipboard() async {
    final text = (await ClipboardService.getText())?.trim();
    if (text == null || text.isEmpty) return;
    _searchController.text = text;
    _searchController.selection = TextSelection.collapsed(offset: text.length);
    _searchFocusNode.requestFocus();
  }

  Widget _buildExploreCommandBar(
    BuildContext context, {
    required bool isDark,
    required bool isResults,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final panelBg =
        isDark ? AppColors.homeDarkCardBg : AppColors.surface1(context);
    final borderColor = AppColors.border(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.smMd,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: panelBg,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: borderColor),
              boxShadow:
                  isDark
                      ? null
                      : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 820;
                final searchInput = _buildSearchInput(context, isDark);
                final searchButton = _buildSearchButton(context, isDark);
                final backButton =
                    isResults
                        ? Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.sm),
                          child: IconButton(
                            onPressed: _onBackToDiscovery,
                            icon: Icon(
                              Icons.arrow_back_rounded,
                              size: 18,
                              color:
                                  isDark
                                      ? AppColors.homeDarkTextSecondary
                                      : cs.onSurface.withValues(
                                        alpha: AppOpacity.overlay,
                                      ),
                            ),
                            tooltip: AppLocalizations.youtubeSearchBack,
                            style: IconButton.styleFrom(
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              minimumSize: const Size(36, 36),
                              backgroundColor:
                                  isDark
                                      ? AppColors.homeDarkAppBg
                                      : AppColors.lightSurface2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.button,
                                ),
                                side: BorderSide(
                                  color:
                                      isDark
                                          ? AppColors.homeDarkBorderStrong
                                          : cs.outlineVariant.withValues(
                                            alpha: AppOpacity.scrim,
                                          ),
                                ),
                              ),
                            ),
                          ),
                        )
                        : null;

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          if (backButton != null) backButton,
                          Expanded(child: searchInput),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.smMd),
                      SizedBox(width: double.infinity, child: searchButton),
                    ],
                  );
                }

                return Row(
                  children: [
                    if (backButton != null) backButton,
                    Expanded(child: searchInput),
                    const SizedBox(width: AppSpacing.smMd),
                    searchButton,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchInput(BuildContext context, bool isDark) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const commandBarHeight = 52.0;
    final textColor = isDark ? AppColors.darkLightText : cs.onSurface;
    final secondaryText =
        isDark
            ? AppColors.homeDarkTextSecondary
            : cs.onSurface.withValues(alpha: AppOpacity.secondary);
    final fieldBg = isDark ? AppColors.homeDarkAppBg : AppColors.lightSurface2;
    final fieldBorder =
        isDark ? AppColors.homeDarkInputBorder : AppColors.border(context);

    return CompositedTransformTarget(
      link: _layerLink,
      child: SizedBox(
        key: _searchInputKey,
        height: commandBarHeight,
        child: Focus(
          onKeyEvent: _handleKeyEvent,
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            decoration: InputDecoration(
              hintText: AppLocalizations.youtubeSearchPlaceholder,
              hintStyle: AppTypography.input.copyWith(color: secondaryText),
              prefixIcon: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Icon(
                  Icons.search_rounded,
                  size: 22,
                  color:
                      isDark
                          ? AppColors.homeDarkTextSecondary
                          : cs.onSurfaceVariant,
                ),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 44,
                maxHeight: commandBarHeight,
              ),
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: AppSpacing.smMd),
                child: Container(
                  decoration: BoxDecoration(
                    color:
                        isDark
                            ? AppColors.homeDarkCardBg
                            : AppColors.surface3(context),
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    border: Border.all(
                      color:
                          isDark
                              ? AppColors.homeDarkBorderStrong
                              : cs.outlineVariant.withValues(
                                alpha: AppOpacity.scrim,
                              ),
                    ),
                  ),
                  child: IconButton(
                    icon: Icon(
                      _searchController.text.isNotEmpty
                          ? Icons.clear_rounded
                          : Icons.content_paste_rounded,
                      size: 16,
                      color:
                          isDark
                              ? AppColors.homeDarkTextSecondary
                              : cs.onSurfaceVariant,
                    ),
                    onPressed: () {
                      if (_searchController.text.isNotEmpty) {
                        _searchController.clear();
                        _searchFocusNode.requestFocus();
                      } else {
                        _pasteFromClipboard();
                      }
                    },
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 28,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
              filled: true,
              fillColor: fieldBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.input),
                borderSide: BorderSide(color: fieldBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.input),
                borderSide: BorderSide(color: fieldBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.input),
                borderSide: BorderSide(
                  color: AppColors.accentHighlight,
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.md,
              ),
              isDense: true,
            ),
            textAlignVertical: TextAlignVertical.center,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _performSearch(_searchController.text),
            style: AppTypography.input.copyWith(color: textColor),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchButton(BuildContext context, bool isDark) {
    final theme = Theme.of(context);
    const commandBarHeight = 52.0;
    return SizedBox(
      height: commandBarHeight,
      child: FilledButton.icon(
        onPressed: () => _performSearch(_searchController.text),
        icon: const Icon(Icons.search_rounded, size: 18),
        label: Text(
          AppLocalizations.youtubeSearchSearch,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return isDark ? AppColors.accentHighlight : AppColors.brandDark;
            }
            return AppColors.brand;
          }),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          iconColor: const WidgetStatePropertyAll(Colors.white),
          minimumSize: const WidgetStatePropertyAll(
            Size(152, commandBarHeight),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.mdLg),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
          ),
        ),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_autocompleteOverlay == null || _currentItems.isEmpty) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _highlightedIndex = (_highlightedIndex + 1) % _currentItems.length;
      });
      _autocompleteOverlay?.markNeedsBuild();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _highlightedIndex =
            _highlightedIndex <= 0
                ? _currentItems.length - 1
                : _highlightedIndex - 1;
      });
      _autocompleteOverlay?.markNeedsBuild();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _removeAutocompleteOverlay();
      setState(() {});
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        _highlightedIndex >= 0 &&
        _highlightedIndex < _currentItems.length) {
      _onSuggestionTap(_currentItems[_highlightedIndex]);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final exploreState = ref.watch(youtubeExploreProvider);
    final isResults = exploreState.mode == ExploreMode.searchResults;
    final activeSection = exploreState.section;
    final pageBg = isDark ? AppColors.homeDarkAppBg : AppColors.lightBase;

    ref.listen(youtubeAutocompleteProvider, (_, __) {
      _autocompleteOverlay?.markNeedsBuild();
    });
    ref.listen(recentSearchesProvider, (_, __) {
      _autocompleteOverlay?.markNeedsBuild();
    });

    return Scaffold(
      backgroundColor: pageBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: ColoredBox(color: pageBg)),
          Column(
            children: [
              _buildExploreCommandBar(
                context,
                isDark: isDark,
                isResults: isResults,
              ),
              if (!isResults)
                _ExploreSectionTabs(
                  activeSection: activeSection,
                  onSectionChanged: _switchSection,
                  isDark: isDark,
                ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child:
                      isResults
                          ? YouTubeResultsView(
                            key: const ValueKey('results'),
                            onVideoDownload: widget.onVideoDownload,
                          )
                          : activeSection == ExploreSection.subscriptions
                          ? SubscriptionsScreen(
                            key: const ValueKey('subscriptions'),
                            embedded: true,
                            onDownloadSelected: widget.onBatchDownloadSelected,
                          )
                          : YouTubeDiscoveryView(
                            key: const ValueKey('discovery'),
                            onSearch: _onDiscoverySearch,
                          ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAutocompleteOverlay() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final autocomplete = ref.watch(youtubeAutocompleteProvider);
    final recentSearches = ref.watch(recentSearchesProvider);
    final radius = BrandConfig.current.cardRadius;

    final suggestions = autocomplete.suggestions;
    final recents = recentSearches.valueOrNull ?? [];
    _currentItems =
        suggestions.isNotEmpty
            ? suggestions.take(8).toList()
            : recents.take(5).toList();

    final hasContent = _currentItems.isNotEmpty;
    if (!hasContent && !autocomplete.isLoading) {
      return const SizedBox.shrink();
    }

    _syncAutocompleteGeometry();

    return Positioned(
      width: _autocompleteWidth,
      child: CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        offset: const Offset(0, 60),
        child: Material(
          color: Colors.transparent,
          elevation: isDark ? 18 : 10,
          borderRadius: BorderRadius.circular(radius),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 400),
            decoration: BoxDecoration(
              color:
                  isDark
                      ? AppColors.homeDarkCardBg
                      : AppColors.surface1(context),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color:
                    isDark
                        ? AppColors.homeDarkBorderStrong
                        : cs.outlineVariant.withValues(alpha: AppOpacity.scrim),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.34 : 0.12),
                  blurRadius: isDark ? 24 : 18,
                  offset: const Offset(0, 12),
                  spreadRadius: -10,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child:
                  autocomplete.isLoading && suggestions.isEmpty
                      ? Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: AppSpacing.smMd),
                            Text(
                              AppLocalizations.commonLoading,
                              style: AppTypography.metadata.copyWith(
                                color:
                                    isDark
                                        ? AppColors.homeDarkTextSecondary
                                        : cs.onSurfaceVariant,
                                fontWeight: AppTypography.medium,
                              ),
                            ),
                          ],
                        ),
                      )
                      : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.md,
                              AppSpacing.smMd,
                              AppSpacing.md,
                              AppSpacing.xs,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  suggestions.isEmpty
                                      ? Icons.history_rounded
                                      : Icons.auto_awesome_rounded,
                                  size: 14,
                                  color:
                                      isDark
                                          ? AppColors.homeDarkTextMuted
                                          : cs.onSurfaceVariant,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Text(
                                  suggestions.isEmpty
                                      ? AppLocalizations
                                          .youtubeSearchRecentSearches
                                      : AppLocalizations
                                          .youtubeSearchSuggestions,
                                  style: AppTypography.metadata.copyWith(
                                    color:
                                        isDark
                                            ? AppColors.homeDarkTextMuted
                                            : cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 286),
                            child: ListView.builder(
                              shrinkWrap: true,
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.xs,
                              ),
                              itemCount: _currentItems.length,
                              itemBuilder: (context, index) {
                                final item = _currentItems[index];
                                final isHighlighted =
                                    index == _highlightedIndex;
                                final isSuggestion = suggestions.isNotEmpty;
                                return _SuggestionTile(
                                  text: item,
                                  icon:
                                      isSuggestion
                                          ? Icons.search_rounded
                                          : Icons.history_rounded,
                                  isHighlighted: isHighlighted,
                                  onTap: () => _onSuggestionTap(item),
                                );
                              },
                            ),
                          ),
                          if (_currentItems.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.sm,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    isDark
                                        ? AppColors.homeDarkAppBg
                                        : AppColors.surface2(context),
                                border: Border(
                                  top: BorderSide(
                                    color:
                                        isDark
                                            ? AppColors.homeDarkBorderStrong
                                            : cs.outlineVariant.withValues(
                                              alpha: AppOpacity.quarter,
                                            ),
                                    width: 0.5,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.keyboard_rounded,
                                    size: 14,
                                    color:
                                        isDark
                                            ? AppColors.homeDarkTextSecondary
                                            : cs.onSurfaceVariant.withValues(
                                              alpha: AppOpacity.secondary,
                                            ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Text(
                                    '↑↓ navigate  ↵ select  esc close',
                                    style: AppTypography.mini.copyWith(
                                      color:
                                          isDark
                                              ? AppColors.homeDarkTextMuted
                                              : cs.onSurfaceVariant.withValues(
                                                alpha: AppOpacity.secondary,
                                              ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExploreSectionTabs extends StatelessWidget {
  final ExploreSection activeSection;
  final ValueChanged<ExploreSection> onSectionChanged;
  final bool isDark;

  const _ExploreSectionTabs({
    required this.activeSection,
    required this.onSectionChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.smMd,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showDescription = constraints.maxWidth >= 720;
              return Row(
                children: [
                  _ExploreSectionButton(
                    icon: Icons.explore_rounded,
                    label: AppLocalizations.youtubeTabTitle,
                    isSelected: activeSection == ExploreSection.discovery,
                    isDark: isDark,
                    onTap: () => onSectionChanged(ExploreSection.discovery),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _ExploreSectionButton(
                    icon: Icons.subscriptions_rounded,
                    label: AppLocalizations.navSubscriptions,
                    isSelected: activeSection == ExploreSection.subscriptions,
                    isDark: isDark,
                    onTap: () => onSectionChanged(ExploreSection.subscriptions),
                  ),
                  if (showDescription) ...[
                    const Spacer(),
                    Flexible(
                      child: Text(
                        AppLocalizations.youtubeTabDescription,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.metadata.copyWith(
                          color:
                              isDark
                                  ? AppColors.homeDarkTextMuted
                                  : cs.onSurfaceVariant.withValues(
                                    alpha: AppOpacity.overlay,
                                  ),
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ExploreSectionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _ExploreSectionButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = AppColors.accentHighlight;
    final bg =
        isSelected
            ? accent.withValues(alpha: isDark ? AppOpacity.pressed : 0.10)
            : (isDark ? AppColors.homeDarkCardBg : AppColors.surface1(context));
    final border =
        isSelected
            ? accent.withValues(alpha: AppOpacity.secondary)
            : (isDark
                ? AppColors.homeDarkBorderSubtle
                : cs.outlineVariant.withValues(alpha: AppOpacity.scrim));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: AnimatedContainer(
        duration: AppTransitions.fast,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.smMd),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: border, width: isSelected ? 1.2 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color:
                  isSelected
                      ? accent
                      : (isDark
                          ? AppColors.homeDarkTextSecondary
                          : cs.onSurfaceVariant),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: AppTypography.buttonSecondary.copyWith(
                color:
                    isSelected
                        ? accent
                        : (isDark
                            ? AppColors.homeDarkTextSecondary
                            : cs.onSurface),
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool isHighlighted;
  final VoidCallback onTap;

  const _SuggestionTile({
    required this.text,
    required this.icon,
    this.isHighlighted = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = AppColors.accentHighlight;
    final foreground = isDark ? AppColors.darkLightText : cs.onSurface;
    final muted =
        isDark
            ? AppColors.homeDarkTextMuted
            : cs.onSurfaceVariant.withValues(alpha: AppOpacity.overlay);

    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.smMd,
        ),
        decoration: BoxDecoration(
          color:
              isHighlighted
                  ? accent.withValues(alpha: isDark ? 0.12 : 0.08)
                  : null,
          border: Border(
            left: BorderSide(
              width: 2,
              color: isHighlighted ? accent : Colors.transparent,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isHighlighted ? accent : muted),
            const SizedBox(width: AppSpacing.smMd),
            Expanded(
              child: Text(
                text,
                style: AppTypography.input.copyWith(
                  color:
                      isHighlighted
                          ? foreground
                          : foreground.withValues(alpha: isDark ? 0.88 : 0.9),
                  fontWeight:
                      isHighlighted
                          ? AppTypography.semiBold
                          : AppTypography.regular,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.north_west_rounded,
              size: 14,
              color:
                  isHighlighted
                      ? accent
                      : muted.withValues(alpha: AppOpacity.medium),
            ),
          ],
        ),
      ),
    );
  }
}
