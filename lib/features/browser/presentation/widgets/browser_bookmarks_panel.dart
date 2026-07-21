import '../../../../core/core.dart';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/browser_bookmark.dart';
import '../providers/browser_tab_providers.dart';

enum _BookmarkMenuOption { exportHtml, exportJson, importFile }

/// The Intelligence Archive — Nocturne Cinematic bookmarks panel.
///
/// Features: search, platform icons, hover actions, import/export,
/// organized grid of saved sites.
class BrowserBookmarksPanel {
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
                (context, scrollController) => _BookmarksContent(
                  scrollController: scrollController,
                  onNavigate: onNavigate,
                ),
          ),
    );
  }
}

class _BookmarksContent extends ConsumerStatefulWidget {
  final ScrollController scrollController;
  final void Function(String url)? onNavigate;

  const _BookmarksContent({required this.scrollController, this.onNavigate});

  @override
  ConsumerState<_BookmarksContent> createState() => _BookmarksContentState();
}

class _BookmarksContentState extends ConsumerState<_BookmarksContent> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<BrowserBookmark> _filterBookmarks(List<BrowserBookmark> bookmarks) {
    if (_searchQuery.isEmpty) return bookmarks;
    final q = _searchQuery.toLowerCase();
    return bookmarks
        .where(
          (b) =>
              b.title.toLowerCase().contains(q) ||
              b.url.toLowerCase().contains(q),
        )
        .toList();
  }

  Future<void> _onMenuSelected(
    _BookmarkMenuOption option,
    BuildContext ctx,
  ) async {
    final bookmarkService = ref.read(browserBookmarkServiceProvider);

    switch (option) {
      case _BookmarkMenuOption.exportHtml:
        final html = bookmarkService.exportToNetscapeHtml();
        final savePath = await FilePicker.platform.saveFile(
          dialogTitle: AppLocalizations.browserBookmarkExport,
          fileName: '${BrandConfig.current.brand.name}_bookmarks.html',
          allowedExtensions: ['html'],
          type: FileType.custom,
        );
        if (savePath == null) return;
        await File(savePath).writeAsString(html);
        if (ctx.mounted) {
          AppSnackBar.success(
            ctx,
            message: AppLocalizations.browserBookmarkExportSuccess,
          );
        }
      case _BookmarkMenuOption.exportJson:
        final json = bookmarkService.exportToJson();
        final savePath = await FilePicker.platform.saveFile(
          dialogTitle: AppLocalizations.browserBookmarkExport,
          fileName: '${BrandConfig.current.brand.name}_bookmarks.json',
          allowedExtensions: ['json'],
          type: FileType.custom,
        );
        if (savePath == null) return;
        await File(savePath).writeAsString(json);
        if (ctx.mounted) {
          AppSnackBar.success(
            ctx,
            message: AppLocalizations.browserBookmarkExportSuccess,
          );
        }
      case _BookmarkMenuOption.importFile:
        final result = await FilePicker.platform.pickFiles(
          dialogTitle: AppLocalizations.browserBookmarkImport,
          allowedExtensions: ['html', 'json'],
          type: FileType.custom,
        );
        if (result == null || result.files.isEmpty) return;
        final path = result.files.first.path;
        if (path == null) return;

        try {
          final content = await File(path).readAsString();
          final int added;
          if (path.toLowerCase().endsWith('.json')) {
            added = bookmarkService.importFromJson(content);
          } else {
            added = bookmarkService.importFromNetscapeHtml(content);
          }
          if (ctx.mounted) {
            if (added == 0) {
              AppSnackBar.info(
                ctx,
                message: AppLocalizations.browserBookmarkImportNone,
              );
            } else {
              AppSnackBar.success(
                ctx,
                message: AppLocalizations.browserBookmarkImportSuccess(added),
              );
            }
          }
        } catch (_) {
          if (ctx.mounted) {
            AppSnackBar.error(
              ctx,
              message: AppLocalizations.browserBookmarkImportError,
            );
          }
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bookmarkService = ref.watch(browserBookmarkServiceProvider);
    final allBookmarks = bookmarkService.bookmarks;
    final bookmarks = _filterBookmarks(allBookmarks);

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

        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.mdLg,
            AppSpacing.sm,
            AppSpacing.sm,
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
                  Icons.bookmark_rounded,
                  size: 15,
                  color: AppColors.accentHighlight,
                ),
              ),
              const SizedBox(width: AppSpacing.smMd),
              Text(
                AppLocalizations.browserBookmarks,
                style: AppTypography.appBarTitle.copyWith(
                  color: cs.onSurface,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (allBookmarks.isNotEmpty)
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
                    '${allBookmarks.length}',
                    style: AppTypography.compact.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withValues(alpha: AppOpacity.overlay),
                    ),
                  ),
                ),
              const Spacer(),
              // Import/Export menu
              PopupMenuButton<_BookmarkMenuOption>(
                tooltip: '',
                icon: Icon(
                  Icons.more_horiz_rounded,
                  size: 20,
                  color: cs.onSurface.withValues(alpha: AppOpacity.overlay),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                color: cs.surfaceContainerHigh,
                onSelected: (opt) => _onMenuSelected(opt, context),
                itemBuilder:
                    (_) => [
                      _buildMenuItem(
                        cs,
                        value: _BookmarkMenuOption.exportHtml,
                        icon: Icons.code_rounded,
                        label: AppLocalizations.browserBookmarksExportHtml,
                      ),
                      _buildMenuItem(
                        cs,
                        value: _BookmarkMenuOption.exportJson,
                        icon: Icons.data_object_rounded,
                        label: AppLocalizations.browserBookmarksExportJson,
                      ),
                      const PopupMenuDivider(height: 1),
                      _buildMenuItem(
                        cs,
                        value: _BookmarkMenuOption.importFile,
                        icon: Icons.file_upload_rounded,
                        label: AppLocalizations.browserBookmarkImport,
                      ),
                    ],
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
                hintText: AppLocalizations.browserBookmarksSearchHint,
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
              bookmarks.isEmpty
                  ? _buildEmptyState(cs, allBookmarks.isEmpty)
                  : ListView.builder(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.only(
                      top: AppSpacing.xs,
                      bottom: AppSpacing.md,
                    ),
                    itemCount: bookmarks.length,
                    itemBuilder: (context, index) {
                      final bookmark = bookmarks[index];
                      // Stable per-bookmark key — Dismissible swipe + delete reorders.
                      return _BookmarkItem(
                        key: ValueKey<String>('bookmark_${bookmark.id}'),
                        bookmark: bookmark,
                        onTap: () {
                          widget.onNavigate?.call(bookmark.url);
                          Navigator.of(context).pop();
                        },
                        onDelete: () {
                          bookmarkService.remove(bookmark.id);
                          setState(() {});
                        },
                      );
                    },
                  ),
        ),
      ],
    );
  }

  PopupMenuItem<_BookmarkMenuOption> _buildMenuItem(
    ColorScheme cs, {
    required _BookmarkMenuOption value,
    required IconData icon,
    required String label,
  }) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: cs.onSurface.withValues(alpha: AppOpacity.secondary),
          ),
          const SizedBox(width: AppSpacing.smMd),
          Text(
            label,
            style: AppTypography.platformName.copyWith(
              fontWeight: FontWeight.w400,
              color: cs.onSurface.withValues(alpha: AppOpacity.nearOpaque),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs, bool noBookmarks) {
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
              Icons.bookmark_border_rounded,
              size: 28,
              color: cs.onSurface.withValues(alpha: AppOpacity.subtle),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            noBookmarks
                ? AppLocalizations.browserNoBookmarks
                : 'No matching bookmarks',
            style: AppTypography.fileName.copyWith(
              color: cs.onSurface.withValues(alpha: AppOpacity.medium),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            noBookmarks
                ? 'Star pages to save them here'
                : 'Try a different search term',
            style: AppTypography.metadata.copyWith(
              color: cs.onSurface.withValues(alpha: AppOpacity.quarter),
            ),
          ),
        ],
      ),
    );
  }
}

/// Individual bookmark entry with platform icon and hover actions.
class _BookmarkItem extends StatefulWidget {
  final BrowserBookmark bookmark;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const _BookmarkItem({
    super.key,
    required this.bookmark,
    this.onTap,
    this.onDelete,
  });

  @override
  State<_BookmarkItem> createState() => _BookmarkItemState();
}

class _BookmarkItemState extends State<_BookmarkItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final platform = _detectPlatform(widget.bookmark.url);
    final hasPlatformIcon =
        platform.isNotEmpty && PlatformStyleHelper.hasSvgIcon(platform);
    final platformColor =
        platform.isNotEmpty
            ? PlatformStyleHelper.getColorForPlatform(platform)
            : AppColors.accentHighlight;

    return Dismissible(
      key: ValueKey(widget.bookmark.id),
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
                              Icons.bookmark_rounded,
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
                        widget.bookmark.title.isNotEmpty
                            ? widget.bookmark.title
                            : widget.bookmark.url,
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
                        _cleanUrl(widget.bookmark.url),
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
                // Delete button on hover
                AnimatedOpacity(
                  opacity: _isHovered ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 120),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: IconButton(
                      onPressed: widget.onDelete,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: cs.onSurface.withValues(alpha: AppOpacity.scrim),
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
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
}
