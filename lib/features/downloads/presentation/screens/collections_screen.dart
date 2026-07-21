import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../../domain/entities/collection_entity.dart';
import '../providers/collection_providers.dart';
import '../widgets/add_edit_collection_dialog.dart';
import 'collection_detail_screen.dart';
import '../../../premium/domain/entities/premium_feature.dart';
import '../../../premium/presentation/widgets/premium_gate.dart';

class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collections = ref.watch(collectionsProvider);
    final counts = ref.watch(collectionCountsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBase,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBase,
        surfaceTintColor: Colors.transparent,
        title: Text('collections.title'.tr()),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: FilledButton.icon(
              onPressed: () => _showAddDialog(context, ref),
              icon: const Icon(Icons.add, size: 18),
              label: Text('collections.addCollection'.tr()),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
              ),
            ),
          ),
        ],
      ),
      body: PremiumGate(
        feature: PremiumFeature.smartCollections,
        child:
            collections.isEmpty
                ? _buildEmptyState(context, ref, isDark, theme)
                : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: collections.length,
                  separatorBuilder:
                      (_, __) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final collection = collections[index];
                    final count = counts[collection.id] ?? 0;
                    return _CollectionCard(
                      collection: collection,
                      count: count,
                      isDark: isDark,
                      onTap:
                          () => Navigator.push(
                            context,
                            AppTransitions.pageRoute(
                              CollectionDetailScreen(
                                collectionId: collection.id,
                              ),
                            ),
                          ),
                      onEdit: () => _showEditDialog(context, ref, collection),
                      onDelete: () => _confirmDelete(context, ref, collection),
                    );
                  },
                ),
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    ThemeData theme,
  ) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: AppOpacity.pressed),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.folder_special_outlined,
              size: 28,
              color: AppColors.brand,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'collections.emptyTitle'.tr(),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'collections.emptySubtitle'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(
                alpha: AppOpacity.overlay,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.mdLg),
          FilledButton.icon(
            onPressed: () => _showAddDialog(context, ref),
            icon: const Icon(Icons.add, size: 18),
            label: Text('collections.addCollection'.tr()),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brand,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<CollectionEntity>(
      context: context,
      builder: (_) => const AddEditCollectionDialog(),
    );
    if (!context.mounted) return;
    if (result != null) {
      await ref.read(collectionsProvider.notifier).addCollection(result);
    }
  }

  Future<void> _showEditDialog(
    BuildContext context,
    WidgetRef ref,
    CollectionEntity collection,
  ) async {
    final result = await showDialog<CollectionEntity>(
      context: context,
      builder: (_) => AddEditCollectionDialog(existing: collection),
    );
    if (!context.mounted) return;
    if (result != null) {
      await ref.read(collectionsProvider.notifier).updateCollection(result);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    CollectionEntity collection,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor:
                isDark ? AppColors.darkSurface1 : AppColors.lightElevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              side:
                  isDark
                      ? BorderSide(color: AppColors.darkElevated)
                      : BorderSide.none,
            ),
            title: Text('collections.deleteTitle'.tr()),
            content: Text(
              'collections.deleteConfirm'.tr(
                namedArgs: {'name': collection.name},
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('collections.cancel'.tr()),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.errorRed,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('collections.delete'.tr()),
              ),
            ],
          ),
    );
    if (!context.mounted) return;
    if (confirmed == true) {
      await ref
          .read(collectionsProvider.notifier)
          .deleteCollection(collection.id);
    }
  }
}

class _CollectionCard extends StatefulWidget {
  final CollectionEntity collection;
  final int count;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CollectionCard({
    required this.collection,
    required this.count,
    required this.isDark,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_CollectionCard> createState() => _CollectionCardState();
}

class _CollectionCardState extends State<_CollectionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovered = false);
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.smMd,
          ),
          decoration: BoxDecoration(
            color:
                widget.isDark
                    ? AppColors.darkSurface1
                    : AppColors.lightElevated,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color:
                  _hovered
                      ? AppColors.accentHighlight.withValues(
                        alpha: AppOpacity.scrim,
                      )
                      : widget.isDark
                      ? AppColors.darkElevated
                      : Colors.transparent,
            ),
            boxShadow:
                widget.isDark
                    ? null
                    : [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: AppOpacity.divider,
                        ),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: AppOpacity.pressed),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Icon(
                  Icons.folder_special_outlined,
                  size: 20,
                  color: AppColors.brand,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.collection.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (widget.collection.description.isNotEmpty)
                      Text(
                        widget.collection.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: AppOpacity.overlay,
                          ),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color:
                      widget.isDark
                          ? AppColors.darkElevated
                          : AppColors.lightSurface2,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Text(
                  '${widget.count}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Edit/Delete actions — always mounted; opacity-toggled on hover.
              // Conditional mounting on _hovered triggers mouse_tracker.dart:203
              // assertion when ListView rebuilds during pointer dispatch.
              const SizedBox(width: AppSpacing.sm),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: _hovered ? 1.0 : 0.0,
                child: IgnorePointer(
                  ignoring: !_hovered,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: widget.onEdit,
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: AppColors.errorRed,
                        ),
                        onPressed: widget.onDelete,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: theme.colorScheme.onSurface.withValues(
                  alpha: AppOpacity.scrim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
