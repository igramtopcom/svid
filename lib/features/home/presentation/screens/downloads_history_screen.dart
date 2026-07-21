import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/core.dart';
import '../../../downloads/domain/entities/download_entity.dart';
import '../../../downloads/domain/services/download_history_export_service.dart';
import '../../../downloads/presentation/providers/downloads_notifier.dart';
import '../../../downloads/presentation/providers/filter_provider.dart';
import '../../../downloads/presentation/providers/filtered_downloads_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../widgets/filter_chips.dart';
import '../widgets/downloads_list.dart';

/// Downloads History Screen - Filter tabs view (All/Video/Audio/Platform)
/// Design: Clean focus on downloads list with filter chips only
class DownloadsHistoryScreen extends ConsumerStatefulWidget {
  const DownloadsHistoryScreen({super.key});

  @override
  ConsumerState<DownloadsHistoryScreen> createState() => DownloadsHistoryScreenState();
}

class DownloadsHistoryScreenState extends ConsumerState<DownloadsHistoryScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Public method to focus search field (called from keyboard shortcut)
  void focusSearch() {
    _searchFocusNode.requestFocus();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase().trim();
    });
  }

  /// Filter downloads based on search query
  List<DownloadEntity> _filterDownloads(List<DownloadEntity> downloads) {
    if (_searchQuery.isEmpty) {
      return downloads;
    }

    return downloads.where((download) {
      final filename = download.filename.toLowerCase();
      final url = download.url.toLowerCase();
      final status = download.status.displayLabel.toLowerCase();
      final title = download.title?.toLowerCase() ?? '';
      final uploader = download.uploader?.toLowerCase() ?? '';

      return filename.contains(_searchQuery) ||
          url.contains(_searchQuery) ||
          status.contains(_searchQuery) ||
          title.contains(_searchQuery) ||
          uploader.contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filterState = ref.watch(filterProvider);
    final allDownloads = ref.watch(filteredDownloadsProvider);
    final downloadsState = ref.watch(downloadsNotifierProvider);
    final filteredDownloads = _filterDownloads(allDownloads);

    return Scaffold(
      body: Padding(
        padding: AppSpacing.edgeInsets.lg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    _getHeaderTitle(filterState.selectedTab),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Sort dropdown
                    if (downloadsState.downloads.isNotEmpty)
                      PopupMenuButton<SortOption>(
                        icon: Icon(
                          Icons.sort_rounded,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        tooltip: AppLocalizations.downloadsSortBy,
                        onSelected: (sort) =>
                            ref.read(filterProvider.notifier).updateSort(sort),
                        itemBuilder: (context) => SortOption.values.map((option) {
                          final isSelected = filterState.sortOption == option;
                          return PopupMenuItem<SortOption>(
                            value: option,
                            child: Row(
                              children: [
                                if (isSelected)
                                  Icon(Icons.check, size: 18,
                                      color: Theme.of(context).colorScheme.primary)
                                else
                                  const SizedBox(width: 18),
                                const SizedBox(width: 8),
                                Text(option.displayName),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    // Batch actions menu
                    if (downloadsState.downloads.isNotEmpty)
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_horiz),
                        tooltip: AppLocalizations.homeBatchActions,
                        onSelected: (action) {
                          switch (action) {
                            case 'clearCompleted':
                              _showClearCompletedDialog();
                            case 'clearFailed':
                              _showClearFailedDialog();
                            case 'pauseAll':
                              ref.read(downloadsNotifierProvider.notifier).pauseAllDownloads();
                              AppSnackBar.info(context, message: AppLocalizations.homePausedAll);
                            case 'resumeAll':
                              ref.read(downloadsNotifierProvider.notifier).resumeAllDownloads();
                              AppSnackBar.info(context, message: AppLocalizations.homeResumedAll);
                            case 'exportCsv':
                              _exportCsv();
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(value: 'exportCsv', child: Row(children: [
                            const Icon(Icons.file_download_outlined, size: 18),
                            const SizedBox(width: 8),
                            Text(AppLocalizations.csvExportMenuItem),
                          ])),
                          const PopupMenuDivider(),
                          PopupMenuItem(value: 'clearCompleted', child: Row(children: [
                            const Icon(Icons.check_circle_outline, size: 18),
                            const SizedBox(width: 8),
                            Text(AppLocalizations.homeClearCompleted),
                          ])),
                          PopupMenuItem(value: 'clearFailed', child: Row(children: [
                            const Icon(Icons.error_outline, size: 18),
                            const SizedBox(width: 8),
                            Text(AppLocalizations.homeClearFailed),
                          ])),
                          const PopupMenuDivider(),
                          PopupMenuItem(value: 'pauseAll', child: Row(children: [
                            const Icon(Icons.pause_circle_outline, size: 18),
                            const SizedBox(width: 8),
                            Text(AppLocalizations.homePauseAll),
                          ])),
                          PopupMenuItem(value: 'resumeAll', child: Row(children: [
                            const Icon(Icons.play_circle_outline, size: 18),
                            const SizedBox(width: 8),
                            Text(AppLocalizations.homeResumeAll),
                          ])),
                        ],
                      ),
                  ],
                ),
              ],
            ),

            const Gap.md(),

            // Platform Filter Chips
            const PlatformFilterChips(),

            const Gap.md(),

            // Search Field
            if (downloadsState.downloads.isNotEmpty)
              Container(
                margin: EdgeInsets.only(bottom: AppSpacing.md),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    hintText: AppLocalizations.homeSearchPlaceholder,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => _searchController.clear(),
                            tooltip: AppLocalizations.homeClearSearch,
                          )
                        : null,
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: AppRadius.borderRadius.input,
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: AppRadius.borderRadius.input,
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: AppOpacity.quarter),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: AppRadius.borderRadius.input,
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),

            // Downloads List (virtualized — items rendered on demand)
            Expanded(
              child: filteredDownloads.isEmpty && _searchQuery.isNotEmpty
                  ? _buildNoResultsState()
                  : DownloadsList(
                      downloads: filteredDownloads,
                      viewMode: ref.watch(settingsProvider).downloadsViewMode,
                      scrollable: true,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _getHeaderTitle(FilterTab tab) {
    switch (tab) {
      case FilterTab.all:
        return AppLocalizations.downloadsAllDownloads;
      case FilterTab.video:
        return AppLocalizations.downloadsVideoDownloads;
      case FilterTab.audio:
        return AppLocalizations.downloadsAudioDownloads;
      case FilterTab.image:
        return AppLocalizations.downloadsImageDownloads;
      case FilterTab.playlist:
        // TODO(ui-wording): add downloadsPlaylistDownloads i18n key.
        return 'Playlist';
    }
  }

  /// Show confirmation dialog for clearing completed downloads
  void _showClearCompletedDialog() {
    final completedCount = ref
        .read(downloadsNotifierProvider)
        .downloads
        .where((d) => d.isCompleted)
        .length;

    if (completedCount == 0) {
      AppSnackBar.info(context, message: AppLocalizations.homeNoCompletedDownloads);
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.homeClearCompletedTitle),
        content: Text(AppLocalizations.homeClearCompletedMessage(completedCount)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(downloadsNotifierProvider.notifier).deleteCompletedDownloads();
              AppSnackBar.success(context, message: AppLocalizations.homeCleared(completedCount));
            },
            child: Text(AppLocalizations.downloadsDeleteRecordOnly),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(downloadsNotifierProvider.notifier).deleteCompletedDownloads(deleteFiles: true);
              AppSnackBar.success(context, message: AppLocalizations.homeDeleted(completedCount));
            },
            child: Text(AppLocalizations.downloadsDeleteFileAndRecord),
          ),
        ],
      ),
    );
  }

  /// Show confirmation dialog for clearing failed downloads
  void _showClearFailedDialog() {
    final failedCount = ref
        .read(downloadsNotifierProvider)
        .downloads
        .where((d) => d.isFailed)
        .length;

    if (failedCount == 0) {
      AppSnackBar.info(context, message: AppLocalizations.homeNoFailedDownloads);
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.homeClearFailedTitle),
        content: Text(AppLocalizations.homeClearFailedMessage(failedCount)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(downloadsNotifierProvider.notifier).deleteFailedDownloads();
              AppSnackBar.success(context, message: AppLocalizations.homeCleared(failedCount));
            },
            child: Text(AppLocalizations.downloadsDeleteRecordOnly),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(downloadsNotifierProvider.notifier).deleteFailedDownloads(deleteFiles: true);
              AppSnackBar.success(context, message: AppLocalizations.homeDeleted(failedCount));
            },
            child: Text(AppLocalizations.downloadsDeleteFileAndRecord),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCsv() async {
    final downloads = ref.read(downloadsNotifierProvider).downloads;
    if (downloads.isEmpty) {
      if (mounted) AppSnackBar.info(context, message: AppLocalizations.csvExportNoDownloads);
      return;
    }

    try {
      const service = DownloadHistoryExportService();
      final csv = service.generateCsv(downloads);

      final downloadsDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final filePath = '${downloadsDir.path}/${BrandConfig.current.brand.name}_history_$timestamp.csv';
      await File(filePath).writeAsString(csv);

      if (!mounted) return;
      AppSnackBar.success(context, message: AppLocalizations.csvExportSuccess(filePath));

      // Platform-specific file reveal
      if (Platform.isMacOS) {
        ProcessHelper.revealInFileManager(
          filePath,
          fallbackDirectory: downloadsDir.path,
        ).ignore();
      } else if (Platform.isWindows) {
        ProcessHelper.revealInFileManager(
          filePath,
          fallbackDirectory: downloadsDir.path,
        ).ignore();
      } else if (Platform.isLinux) {
        ProcessHelper.openDirectoryInFileManager(downloadsDir.path).ignore();
      }
    } catch (_) {
      if (mounted) AppSnackBar.error(context, message: AppLocalizations.csvExportErrorFailed);
    }
  }

  Widget _buildNoResultsState() {
    return AppEmptyWidget(
      icon: Icons.search_off_rounded,
      title: AppLocalizations.homeNoResultsTitle,
      subtitle: AppLocalizations.homeNoResultsSubtitle,
    );
  }
}
