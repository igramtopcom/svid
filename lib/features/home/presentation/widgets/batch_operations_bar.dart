import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../../downloads/presentation/providers/batch_selection_provider.dart';
import '../../../downloads/presentation/providers/downloads_notifier.dart';
import '../../../downloads/presentation/widgets/add_to_playlist_dialog.dart';

/// Sticky action bar that appears at the bottom of the downloads list when
/// one or more items are selected (via long-press).
///
/// Shows:
///  - selected-count chip + Select All / Deselect All
///  - Delete / Move / Rename action buttons
class BatchOperationsBar extends ConsumerWidget {
  const BatchOperationsBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIds = ref.watch(batchSelectionProvider);
    if (selectedIds.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = selectedIds.length;
    final downloads = ref.watch(downloadsNotifierProvider).downloads;
    final hasRetryable = downloads.any(
      (d) => selectedIds.contains(d.id) && d.canRetry,
    );

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBg : AppColors.lightBase,
        border: Border(
          top: BorderSide(
            color:
                isDark
                    ? AppColors.darkMuted.withValues(alpha: AppOpacity.subtle)
                    : Colors.black.withValues(alpha: AppOpacity.divider),
          ),
        ),
        boxShadow:
            isDark
                ? [
                  BoxShadow(
                    color: AppColors.brand.withValues(alpha: AppOpacity.hover),
                    blurRadius: 24,
                    offset: const Offset(0, -4),
                    spreadRadius: -4,
                  ),
                ]
                : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: AppOpacity.hover),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.smMd,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            // Count badge — angular wine-red
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: AppColors.brand,
                borderRadius: BorderRadius.circular(AppRadius.card),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brand.withValues(alpha: AppOpacity.scrim),
                    blurRadius: 8,
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: Text(
                AppLocalizations.batchOpsSelected(count),
                style: AppTypography.statusBadge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),

            const SizedBox(width: AppSpacing.sm),

            // Clear selection
            TextButton(
              onPressed:
                  () => ref.read(batchSelectionProvider.notifier).state = {},
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: isDark ? AppColors.darkMetaText : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
              ),
              child: Text(
                AppLocalizations.batchOpsDeselectAll,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),

            const SizedBox(width: AppSpacing.sm),

            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ActionButton(
                        icon: Icons.playlist_add_rounded,
                        label: AppLocalizations.playlistRowMenuAddTo,
                        onPressed:
                            () => _onAddToPlaylist(
                              context,
                              ref,
                              selectedIds.toList(),
                            ),
                      ),
                      const SizedBox(width: AppSpacing.xs),

                      // Retry (only when selected items include failed downloads)
                      if (hasRetryable) ...[
                        _ActionButton(
                          icon: Icons.refresh_rounded,
                          label: AppLocalizations.batchOpsRetry,
                          color: AppColors.successGreen,
                          onPressed:
                              () =>
                                  _onRetry(context, ref, selectedIds.toList()),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                      ],

                      // Delete
                      _ActionButton(
                        icon: Icons.delete_outline_rounded,
                        label: AppLocalizations.batchOpsDelete,
                        color: AppColors.errorRed,
                        onPressed:
                            () => _onDelete(context, ref, selectedIds.toList()),
                      ),
                      const SizedBox(width: AppSpacing.xs),

                      // Move
                      _ActionButton(
                        icon: Icons.drive_file_move_rounded,
                        label: AppLocalizations.batchOpsMove,
                        onPressed:
                            () => _onMove(context, ref, selectedIds.toList()),
                      ),
                      const SizedBox(width: AppSpacing.xs),

                      // Rename
                      _ActionButton(
                        icon: Icons.edit_rounded,
                        label: AppLocalizations.batchOpsRename,
                        onPressed:
                            () => _onRename(context, ref, selectedIds.toList()),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onAddToPlaylist(
    BuildContext context,
    WidgetRef ref,
    List<int> ids,
  ) async {
    final playlistName = await AddToPlaylistDialog.show(
      context,
      downloadIds: ids,
    );
    if (!context.mounted || playlistName == null) return;

    ref.read(batchSelectionProvider.notifier).state = {};
    AppSnackBar.success(
      context,
      message: AppLocalizations.playlistAddSuccess(ids.length, playlistName),
    );
  }

  Future<void> _onRetry(
    BuildContext context,
    WidgetRef ref,
    List<int> ids,
  ) async {
    final (succeeded, failed) = await ref
        .read(downloadsNotifierProvider.notifier)
        .bulkRetry(ids);

    ref.read(batchSelectionProvider.notifier).state = {};

    if (context.mounted) {
      if (failed > 0) {
        AppSnackBar.warning(
          context,
          message: AppLocalizations.batchOpsPartialFailure(succeeded, failed),
        );
      } else {
        AppSnackBar.success(
          context,
          message: AppLocalizations.batchOpsSuccessRetry(succeeded),
        );
      }
    }
  }

  Future<void> _onDelete(
    BuildContext context,
    WidgetRef ref,
    List<int> ids,
  ) async {
    final deleteFiles = await _showDeleteConfirmDialog(context, ids.length);
    if (deleteFiles == null || !context.mounted) return;

    await ref
        .read(downloadsNotifierProvider.notifier)
        .bulkDelete(ids, deleteFiles: deleteFiles);

    ref.read(batchSelectionProvider.notifier).state = {};

    if (context.mounted) {
      AppSnackBar.success(
        context,
        message: AppLocalizations.batchOpsSuccessDelete(ids.length),
      );
    }
  }

  Future<void> _onMove(
    BuildContext context,
    WidgetRef ref,
    List<int> ids,
  ) async {
    final path = await _showMoveDialog(context);
    if (path == null || path.isEmpty || !context.mounted) return;

    await ref.read(downloadsNotifierProvider.notifier).bulkMove(ids, path);

    ref.read(batchSelectionProvider.notifier).state = {};

    if (context.mounted) {
      AppSnackBar.success(
        context,
        message: AppLocalizations.batchOpsSuccessMove(ids.length),
      );
    }
  }

  Future<void> _onRename(
    BuildContext context,
    WidgetRef ref,
    List<int> ids,
  ) async {
    final pattern = await _showRenameDialog(context);
    if (pattern == null || pattern.isEmpty || !context.mounted) return;

    await ref.read(downloadsNotifierProvider.notifier).bulkRename(ids, pattern);

    ref.read(batchSelectionProvider.notifier).state = {};

    if (context.mounted) {
      AppSnackBar.success(
        context,
        message: AppLocalizations.batchOpsSuccessRename(ids.length),
      );
    }
  }

  /// Returns [true] = delete from disk, [false] = remove from list only,
  /// [null] = cancelled.
  Future<bool?> _showDeleteConfirmDialog(
    BuildContext context,
    int count,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        final tt = Theme.of(ctx).textTheme;
        return AlertDialog(
          backgroundColor: isDark ? AppColors.darkBase : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
            side:
                isDark
                    ? BorderSide(
                      color: AppColors.darkMuted.withValues(
                        alpha: AppOpacity.subtle,
                      ),
                    )
                    : BorderSide.none,
          ),
          title: Text(
            AppLocalizations.batchOpsDeleteConfirmTitle(count),
            style: tt.headlineSmall?.copyWith(
              color: isDark ? AppColors.darkLightText : null,
            ),
          ),
          content: Text(
            AppLocalizations.batchOpsDeleteConfirmBody,
            style: tt.bodyMedium?.copyWith(
              color: isDark ? AppColors.darkMetaText : null,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                AppLocalizations.batchOpsDeleteConfirmKeepFiles,
                style: AppTypography.metadata,
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.errorRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
              ),
              child: Text(AppLocalizations.batchOpsDelete),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _showMoveDialog(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final tt = Theme.of(ctx).textTheme;
        return AlertDialog(
          backgroundColor: isDark ? AppColors.darkBase : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
            side:
                isDark
                    ? BorderSide(
                      color: AppColors.darkMuted.withValues(
                        alpha: AppOpacity.subtle,
                      ),
                    )
                    : BorderSide.none,
          ),
          title: Text(
            AppLocalizations.batchOpsMoveDialogTitle,
            style: tt.headlineSmall?.copyWith(
              color: isDark ? AppColors.darkLightText : null,
            ),
          ),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: '/path/to/folder'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
              ),
              child: Text(AppLocalizations.commonOk),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _showRenameDialog(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder: (ctx, setState) {
              final tt = Theme.of(ctx).textTheme;
              return AlertDialog(
                backgroundColor: isDark ? AppColors.darkBase : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  side:
                      isDark
                          ? BorderSide(
                            color: AppColors.darkMuted.withValues(
                              alpha: AppOpacity.subtle,
                            ),
                          )
                          : BorderSide.none,
                ),
                title: Text(
                  AppLocalizations.batchOpsRenameDialogTitle,
                  style: tt.headlineSmall?.copyWith(
                    color: isDark ? AppColors.darkLightText : null,
                  ),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.batchOpsRenamePatternHint,
                      ),
                      onChanged: (_) => setState(() {}),
                      autofocus: true,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      AppLocalizations.batchOpsRenamePatternHelp,
                      style: tt.labelSmall?.copyWith(
                        color:
                            isDark
                                ? AppColors.darkMetaText
                                : Theme.of(ctx).colorScheme.onSurface
                                    .withValues(alpha: AppOpacity.overlay),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(AppLocalizations.commonCancel),
                  ),
                  FilledButton(
                    onPressed:
                        controller.text.trim().isEmpty
                            ? null
                            : () => Navigator.pop(ctx, controller.text.trim()),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                      ),
                    ),
                    child: Text(AppLocalizations.commonOk),
                  ),
                ],
              );
            },
          ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveColor =
        color ?? (isDark ? AppColors.darkLightText : AppColors.brand);
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14, color: effectiveColor),
      label: Text(
        label,
        style: AppTypography.statusBadge.copyWith(color: effectiveColor),
      ),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
    );
  }
}
