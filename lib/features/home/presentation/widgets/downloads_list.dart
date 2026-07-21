import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../../../../core/navigation/right_panel_provider.dart';
import '../../../downloads/domain/entities/download_entity.dart';
import '../../../downloads/domain/entities/user_playlist_membership.dart';
import '../../../downloads/presentation/providers/batch_selection_provider.dart';
import '../../../downloads/presentation/providers/downloads_notifier.dart';
import '../../../downloads/presentation/providers/user_playlist_memberships_provider.dart';
import 'download_list_helpers.dart';
import 'download_list_item.dart';
import 'download_grouped_image_card.dart';
import 'download_grid_card.dart';

/// Downloads List - Shows all downloads with inline status updates
/// Real-time progress, queue positions, and smart actions
/// Supports list and grid view modes via [viewMode] parameter.
class DownloadsList extends ConsumerWidget {
  final List<DownloadEntity> downloads;
  final String viewMode;

  /// When true, uses proper scrollable list (virtualized).
  /// When false (default), uses shrinkWrap for embedding in SingleChildScrollView.
  final bool scrollable;

  /// Called when the user taps "Paste URL" in the empty state.
  final VoidCallback? onNewDownload;

  /// Called when the user taps "Open Browser" in the empty state.
  final VoidCallback? onOpenBrowser;

  /// When true, the list paints its own manager panel chrome. Home V2
  /// wraps toolbar + filters + list in one shared panel, so it disables
  /// this to avoid nested cards.
  final bool useOuterPanel;

  /// User playlist grouping is useful in the global history list, but
  /// playlist detail already receives a scoped download list from Home.
  /// Re-grouping there with the global membership snapshot can pull in
  /// siblings from other playlists.
  final bool groupUserPlaylists;

  /// Optional context action shown when this list is scoped to a
  /// user-curated playlist detail.
  final ValueChanged<DownloadEntity>? onRemoveFromPlaylist;
  final ValueChanged<DownloadEntity>? onMovePlaylistItemUp;
  final ValueChanged<DownloadEntity>? onMovePlaylistItemDown;

  const DownloadsList({
    super.key,
    required this.downloads,
    this.viewMode = 'list',
    this.scrollable = false,
    this.onNewDownload,
    this.onOpenBrowser,
    this.useOuterPanel = true,
    this.groupUserPlaylists = true,
    this.onRemoveFromPlaylist,
    this.onMovePlaylistItemUp,
    this.onMovePlaylistItemDown,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (downloads.isEmpty) {
      return DownloadEmptyState(
        onNewDownload: onNewDownload,
        onOpenBrowser: onOpenBrowser,
      );
    }

    // Memberships drive user-curated playlist headers. AsyncValue
    // resolves quickly (small N), so empty-list fallback while
    // loading is acceptable — the list re-renders the moment the
    // first snapshot arrives.
    final memberships =
        groupUserPlaylists
            ? ref.watch(userPlaylistMembershipsProvider).valueOrNull ?? const []
            : const <UserPlaylistMembership>[];
    final listItems = buildDownloadListItems(
      downloads,
      memberships: memberships,
    );
    final focusedIndex = ref.watch(focusedDownloadIndexProvider);

    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        return _handleKeyEvent(event, ref, listItems, focusedIndex);
      },
      child: AnimatedSwitcher(
        duration: AppTransitions.controls,
        child:
            viewMode == 'grid'
                ? _buildGridView(context, listItems)
                : _buildListView(context, ref, listItems),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(
    KeyDownEvent event,
    WidgetRef ref,
    List<DownloadListItem> listItems,
    int? focusedIndex,
  ) {
    final key = event.logicalKey;

    // Arrow navigation
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.keyJ) {
      final next =
          (focusedIndex == null)
              ? 0
              : (focusedIndex + 1).clamp(0, listItems.length - 1);
      ref.read(focusedDownloadIndexProvider.notifier).state = next;
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyK) {
      final prev =
          (focusedIndex == null)
              ? 0
              : (focusedIndex - 1).clamp(0, listItems.length - 1);
      ref.read(focusedDownloadIndexProvider.notifier).state = prev;
      return KeyEventResult.handled;
    }

    // No item focused — ignore other keys
    if (focusedIndex == null || focusedIndex >= listItems.length) {
      return KeyEventResult.ignored;
    }

    final item = listItems[focusedIndex];
    final download = switch (item) {
      SingleItem(download: final d) => d,
      GroupedItem(downloads: final dl) => dl.first,
    };

    // Space — toggle selection
    if (key == LogicalKeyboardKey.space) {
      final current = ref.read(batchSelectionProvider);
      ref.read(batchSelectionProvider.notifier).state =
          current.contains(download.id)
              ? (Set.from(current)..remove(download.id))
              : {...current, download.id};
      return KeyEventResult.handled;
    }

    // Enter — open detail panel
    if (key == LogicalKeyboardKey.enter) {
      seedPlaybackQueue(ref, download);
      ref.read(rightPanelProvider.notifier).showDetail(download);
      return KeyEventResult.handled;
    }

    // Escape — clear focus / exit selection mode
    if (key == LogicalKeyboardKey.escape) {
      final selectedIds = ref.read(batchSelectionProvider);
      if (selectedIds.isNotEmpty) {
        ref.read(batchSelectionProvider.notifier).state = const {};
      } else {
        ref.read(focusedDownloadIndexProvider.notifier).state = null;
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Widget _buildListView(
    BuildContext context,
    WidgetRef ref,
    List<DownloadListItem> listItems,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelBorder =
        isDark
            ? AppColors.homeDarkBorderSubtle
            : Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: AppOpacity.hover);

    // Scrollable mode: virtualized ListView (no shrinkWrap, proper recycling)
    if (scrollable) {
      final list = ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: ListView.builder(
          key: const ValueKey('list_view_scrollable'),
          padding: EdgeInsets.zero,
          itemCount: listItems.length,
          itemBuilder:
              (context, index) => _buildListItem(
                context,
                ref,
                listItems,
                index,
                inset: false,
                showDivider: index < listItems.length - 1,
              ),
        ),
      );

      if (!useOuterPanel) return list;

      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xs,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isDark ? AppColors.homeDarkCardBg : Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: panelBorder, width: 1),
            boxShadow:
                isDark
                    ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.24),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                        spreadRadius: -16,
                      ),
                    ]
                    : null,
          ),
          child: list,
        ),
      );
    }

    // Embedded Home mode: keep reorder support, but render the list as one
    // manager surface instead of separate floating cards.
    final list = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: ReorderableListView.builder(
        key: const ValueKey('list_view'),
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: true,
        proxyDecorator:
            (child, index, animation) =>
                Material(color: Colors.transparent, child: child),
        onReorder: (int oldIndex, int newIndex) {
          if (newIndex > oldIndex) newIndex -= 1;
          final reordered = List<DownloadListItem>.from(listItems);
          final moved = reordered.removeAt(oldIndex);
          reordered.insert(newIndex, moved);
          final orderedIds =
              reordered
                  .whereType<SingleItem>()
                  .map((e) => e.download.id)
                  .toList();
          ref
              .read(downloadsNotifierProvider.notifier)
              .reorderDownloads(orderedIds);
        },
        itemCount: listItems.length,
        itemBuilder:
            (context, index) => _buildListItem(
              context,
              ref,
              listItems,
              index,
              inset: false,
              showDivider: index < listItems.length - 1,
            ),
      ),
    );

    if (!useOuterPanel) return list;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xs,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? AppColors.homeDarkCardBg : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: panelBorder, width: 1),
          boxShadow:
              isDark
                  ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.24),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                      spreadRadius: -16,
                    ),
                  ]
                  : null,
        ),
        child: list,
      ),
    );
  }

  Widget _buildListItem(
    BuildContext context,
    WidgetRef ref,
    List<DownloadListItem> listItems,
    int index, {
    bool inset = true,
    bool showDivider = false,
  }) {
    final item = listItems[index];
    final focusedIndex = ref.watch(focusedDownloadIndexProvider);
    final isFocused = focusedIndex == index;
    final child = switch (item) {
      SingleItem(download: final d) => DownloadItemCard(
        download: d,
        isKeyboardFocused: isFocused,
        inPanel: !inset,
        onRemoveFromPlaylist: onRemoveFromPlaylist,
        onMovePlaylistItemUp:
            _canMovePlaylistItem(d, -1) ? onMovePlaylistItemUp : null,
        onMovePlaylistItemDown:
            _canMovePlaylistItem(d, 1) ? onMovePlaylistItemDown : null,
      ),
      final GroupedItem g => DownloadGroupedImageCard(
        group: g,
        inPanel: !inset,
      ),
    };
    final key = switch (item) {
      SingleItem(download: final d) => ValueKey<int>(d.id),
      final GroupedItem g => ValueKey<String>(
        'group_${g.kind.name}_${g.groupId}',
      ),
    };
    final row = Padding(
      padding:
          inset
              ? EdgeInsets.only(
                left: AppSpacing.xl,
                right: AppSpacing.xl,
                bottom:
                    index < listItems.length - 1
                        ? AppSpacing.xxs
                        : AppSpacing.sm,
              )
              : EdgeInsets.zero,
      child: child,
    );

    if (!showDivider) {
      return KeyedSubtree(key: key, child: row);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor =
        isDark
            ? AppColors.homeDarkBorderStrong.withValues(
              alpha: inset ? AppOpacity.subtle : AppOpacity.nearOpaque,
            )
            : Theme.of(context).colorScheme.onSurface.withValues(
              alpha: inset ? AppOpacity.subtle : AppOpacity.hover,
            );
    return KeyedSubtree(
      key: key,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row,
          Padding(
            padding: const EdgeInsets.only(left: kDownloadThumbWidth + 36),
            child: Divider(height: 1, thickness: 1, color: dividerColor),
          ),
        ],
      ),
    );
  }

  Widget _buildGridView(
    BuildContext context,
    List<DownloadListItem> listItems,
  ) {
    return LayoutBuilder(
      key: const ValueKey('grid_view'),
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth < 600
                ? 2
                : constraints.maxWidth < 900
                ? 3
                : 4;
        final horizontalPadding =
            useOuterPanel ? AppSpacing.xl : AppSpacing.smMd;
        final totalHorizontalPadding = horizontalPadding * 2;
        final totalSpacing = AppSpacing.md * (columns - 1);
        final itemWidth =
            (constraints.maxWidth - totalHorizontalPadding - totalSpacing) /
            columns;
        final thumbnailHeight = itemWidth * 9 / 16;
        final contentHeight = constraints.maxWidth < 600 ? 126.0 : 116.0;
        final mainAxisExtent = thumbnailHeight + contentHeight;
        return GridView.builder(
          shrinkWrap: !scrollable,
          physics: scrollable ? null : const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            4,
            horizontalPadding,
            12,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: mainAxisExtent,
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
          ),
          itemCount: listItems.length,
          itemBuilder:
              (context, index) => switch (listItems[index]) {
                SingleItem(download: final d) => DownloadGridCard(
                  key: ValueKey<int>(d.id),
                  download: d,
                  onRemoveFromPlaylist: onRemoveFromPlaylist,
                  onMovePlaylistItemUp:
                      _canMovePlaylistItem(d, -1) ? onMovePlaylistItemUp : null,
                  onMovePlaylistItemDown:
                      _canMovePlaylistItem(d, 1)
                          ? onMovePlaylistItemDown
                          : null,
                ),
                GroupedItem() => DownloadGridCard(
                  key: ValueKey<String>(
                    'grid_group_${(listItems[index] as GroupedItem).kind.name}_${(listItems[index] as GroupedItem).groupId}',
                  ),
                  download: (listItems[index] as GroupedItem).first,
                  carouselDownloads:
                      (listItems[index] as GroupedItem).downloads,
                  onRemoveFromPlaylist: onRemoveFromPlaylist,
                ),
              },
        );
      },
    );
  }

  bool _canMovePlaylistItem(DownloadEntity download, int delta) {
    final callback = delta < 0 ? onMovePlaylistItemUp : onMovePlaylistItemDown;
    if (callback == null || downloads.length < 2) return false;
    final currentIndex = downloads.indexWhere((d) => d.id == download.id);
    if (currentIndex < 0) return false;
    final targetIndex = currentIndex + delta;
    return targetIndex >= 0 && targetIndex < downloads.length;
  }
}

