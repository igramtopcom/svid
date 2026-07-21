import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../../downloads/domain/entities/download_entity.dart';
import '../../../downloads/domain/entities/download_status.dart';
import '../../../downloads/presentation/providers/downloads_notifier.dart';
import '../providers/browser_download_providers.dart';

/// Compact download status bar at the bottom of browser screen.
///
/// Three states:
/// - **Hidden**: No active downloads → overlay not rendered
/// - **Collapsed**: Single row with active count + total speed
/// - **Expanded**: Shows individual downloads with progress bars + actions
///
/// Auto-collapses after 3 seconds of no user interaction.
class BrowserDownloadOverlay extends ConsumerStatefulWidget {
  /// Called when user taps "View All Downloads" to navigate to downloads screen.
  final VoidCallback? onViewAllDownloads;

  const BrowserDownloadOverlay({super.key, this.onViewAllDownloads});

  @override
  ConsumerState<BrowserDownloadOverlay> createState() =>
      _BrowserDownloadOverlayState();
}

class _BrowserDownloadOverlayState
    extends ConsumerState<BrowserDownloadOverlay> {
  bool _isExpanded = false;
  Timer? _autoCollapseTimer;

  // Gesture-dismiss state
  bool _isDismissed = false;
  double _panAccum = 0.0;
  static const double _kDismissThreshold = 60.0;

  // Local display order for drag-to-reorder (list of download IDs)
  final List<int> _localOrder = [];

  @override
  void dispose() {
    _autoCollapseTimer?.cancel();
    super.dispose();
  }

  void _startAutoCollapseTimer() {
    _autoCollapseTimer?.cancel();
    _autoCollapseTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isExpanded) {
        setState(() => _isExpanded = false);
      }
    });
  }

  void _mergeActiveDownloads(List<DownloadEntity> activeDownloads) {
    final activeIds = activeDownloads.map((d) => d.id).toSet();
    // Remove IDs no longer active
    _localOrder.removeWhere((id) => !activeIds.contains(id));
    // Append new IDs at end
    for (final d in activeDownloads) {
      if (!_localOrder.contains(d.id)) _localOrder.add(d.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = ref.watch(browserActiveCountProvider);

    // Hidden: no active downloads
    if (activeCount == 0) {
      _autoCollapseTimer?.cancel();
      _isDismissed = false; // reset so overlay appears on next download
      _localOrder.clear();
      return const SizedBox.shrink();
    }

    final activeDownloads = ref.watch(browserActiveDownloadsProvider);
    final totalSpeed = ref.watch(browserTotalSpeedProvider);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark
            ? AppColors.homeDarkBorderStrong
            : cs.outline.withValues(alpha: AppOpacity.divider);

    // Listen for new downloads to reappear after dismiss
    ref.listen<int>(browserActiveCountProvider, (prev, next) {
      if ((prev == null || prev == 0) && next > 0 && _isDismissed) {
        setState(() => _isDismissed = false);
      }
    });

    // Sync local order list with current active downloads
    _mergeActiveDownloads(activeDownloads);

    if (_isDismissed) return const SizedBox.shrink();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: AppColors.surface2(context),
        border: Border(top: BorderSide(color: borderColor)),
        boxShadow:
            isDark
                ? null
                : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Collapsed bar — always visible when active downloads exist
          _buildCollapsedBar(cs, activeCount, totalSpeed),

          // Expanded list — shows individual downloads
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState:
                _isExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: _buildExpandedList(cs, activeDownloads),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsedBar(ColorScheme cs, int activeCount, int totalSpeed) {
    return GestureDetector(
      // Swipe down to dismiss overlay
      onVerticalDragUpdate: (details) {
        if (details.delta.dy > 0) {
          // Only downward drag counts
          _panAccum += details.delta.dy;
        }
      },
      onVerticalDragEnd: (_) {
        if (_panAccum >= _kDismissThreshold) {
          setState(() {
            _isDismissed = true;
            _isExpanded = false;
            _panAccum = 0.0;
          });
          _autoCollapseTimer?.cancel();
        } else {
          _panAccum = 0.0;
        }
      },
      onVerticalDragCancel: () => _panAccum = 0.0,
      child: InkWell(
        onTap: () {
          setState(() => _isExpanded = !_isExpanded);
          if (_isExpanded) {
            _startAutoCollapseTimer();
          } else {
            _autoCollapseTimer?.cancel();
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.smMd,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              // Download icon with count badge
              Badge(
                label: Text('$activeCount', style: AppTypography.compact),
                child: Icon(
                  Icons.download_rounded,
                  size: 20,
                  color: AppColors.accentHighlight,
                ),
              ),
              const SizedBox(width: AppSpacing.smMd),

              // Active count text
              Expanded(
                child: Text(
                  AppLocalizations.browserDownloadActiveCount(activeCount),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.metadata.copyWith(
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
              ),

              const SizedBox(width: AppSpacing.sm),

              // Total speed
              if (totalSpeed > 0)
                Text(
                  '${Formatters.formatSpeed(totalSpeed)}/s',
                  style: AppTypography.metadata.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.accentHighlight,
                  ),
                ),

              const SizedBox(width: AppSpacing.sm),

              // Expand/collapse icon
              Icon(
                _isExpanded
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_up_rounded,
                size: 18,
                color: cs.onSurface.withValues(alpha: AppOpacity.overlay),
              ),
            ],
          ),
        ),
      ),
    ); // GestureDetector
  }

  Widget _buildExpandedList(
    ColorScheme cs,
    List<DownloadEntity> activeDownloads,
  ) {
    // Build lookup map for quick access
    final downloadMap = {for (final d in activeDownloads) d.id: d};

    // Ordered IDs (max 5)
    final orderedIds =
        _localOrder.where((id) => downloadMap.containsKey(id)).take(5).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(
          height: 1,
          color: cs.outline.withValues(alpha: AppOpacity.subtle),
        ),

        // Drag-to-reorder list
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: orderedIds.length,
          itemBuilder: (context, index) {
            final d = downloadMap[orderedIds[index]]!;
            return KeyedSubtree(
              key: ValueKey(d.id),
              child: _buildDownloadItem(cs, d),
            );
          },
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex -= 1;
              final id = orderedIds.removeAt(oldIndex);
              orderedIds.insert(newIndex, id);
              // Apply reordered slice back into _localOrder
              int cursor = 0;
              for (int i = 0; i < _localOrder.length; i++) {
                if (downloadMap.containsKey(_localOrder[i])) {
                  _localOrder[i] = orderedIds[cursor++];
                  if (cursor >= orderedIds.length) break;
                }
              }
            });
          },
        ),

        // View All Downloads button
        if (widget.onViewAllDownloads != null)
          InkWell(
            onTap: widget.onViewAllDownloads,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.smMd,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.list_rounded,
                    size: 16,
                    color: AppColors.accentHighlight,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    AppLocalizations.browserDownloadViewAll,
                    style: AppTypography.metadata.copyWith(
                      fontWeight: FontWeight.w500,
                      color: AppColors.accentHighlight,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDownloadItem(ColorScheme cs, DownloadEntity download) {
    final filename = download.title ?? download.filename;
    final isDownloading = download.status == DownloadStatus.downloading;
    final isPostProcessing = download.status == DownloadStatus.postProcessing;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.smMd,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          // Filename (truncated)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.statusBadge.copyWith(
                    fontWeight: FontWeight.w400,
                    color: cs.onSurface,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),

                // Progress bar
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: isPostProcessing ? null : download.progress,
                          minHeight: 3,
                          backgroundColor: cs.onSurface.withValues(
                            alpha: AppOpacity.pressed,
                          ),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isPostProcessing
                                ? cs.tertiary
                                : AppColors.accentHighlight,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),

                    // Percentage or status
                    Flexible(
                      child: Text(
                        isPostProcessing
                            ? AppLocalizations.browserDownloadConverting
                            : isDownloading
                            ? '${download.progressPercentage.toStringAsFixed(0)}%'
                            : download.status == DownloadStatus.queued
                            ? AppLocalizations.browserDownloadQueued
                            : download.status.displayLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.compact.copyWith(
                          color: cs.onSurface.withValues(
                            alpha: AppOpacity.secondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // Speed per download
                if (isDownloading && download.speed > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxs),
                    child: Text(
                      '${Formatters.formatSpeed(download.speed)}/s',
                      style: AppTypography.compact.copyWith(
                        color: cs.onSurface.withValues(
                          alpha: AppOpacity.medium,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: AppSpacing.sm),

          // Action buttons
          if (isDownloading)
            _buildActionButton(
              cs,
              Icons.pause_rounded,
              AppLocalizations.browserDownloadPause,
              () => ref
                  .read(downloadsNotifierProvider.notifier)
                  .pauseDownload(download.id),
            ),

          if (download.status == DownloadStatus.paused)
            _buildActionButton(
              cs,
              Icons.play_arrow_rounded,
              AppLocalizations.browserDownloadResume,
              () => ref
                  .read(downloadsNotifierProvider.notifier)
                  .resumeDownload(download.id),
            ),

          _buildActionButton(
            cs,
            Icons.close_rounded,
            AppLocalizations.browserDownloadCancel,
            () => ref
                .read(downloadsNotifierProvider.notifier)
                .cancelDownload(download.id),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    ColorScheme cs,
    IconData icon,
    String tooltip,
    VoidCallback onPressed,
  ) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 14),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        color: cs.onSurface.withValues(alpha: AppOpacity.secondary),
      ),
    );
  }
}
