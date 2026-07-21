import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../../domain/entities/sorting_rule.dart';
import '../providers/sorting_rule_providers.dart';
import '../widgets/add_edit_sorting_rule_dialog.dart';

class SortingRulesScreen extends ConsumerWidget {
  const SortingRulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(sortingRulesProvider);
    final notifier = ref.read(sortingRulesProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBase,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBase,
        surfaceTintColor: Colors.transparent,
        title: Text('sortingRules.title'.tr()),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: FilledButton.icon(
              onPressed: () => _showAddDialog(context, ref),
              icon: const Icon(Icons.add, size: 18),
              label: Text('sortingRules.addRule'.tr()),
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
      body:
          rules.isEmpty
              ? _EmptyState(
                onAdd: () => _showAddDialog(context, ref),
                isDark: isDark,
              )
              : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: Text(
                      'sortingRules.hint'.tr(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: AppOpacity.overlay),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                      itemCount: rules.length,
                      onReorder:
                          (oldIndex, newIndex) =>
                              notifier.reorder(oldIndex, newIndex),
                      itemBuilder: (context, index) {
                        final rule = rules[index];
                        return _RuleCard(
                          key: ValueKey(rule.id),
                          rule: rule,
                          isDark: isDark,
                          onToggle: () => notifier.toggleEnabled(rule.id),
                          onEdit: () => _showEditDialog(context, ref, rule),
                          onDelete: () => _confirmDelete(context, ref, rule),
                        );
                      },
                    ),
                  ),
                ],
              ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<SortingRule>(
      context: context,
      builder: (_) => const AddEditSortingRuleDialog(),
    );
    if (!context.mounted) return;
    if (result != null) {
      await ref.read(sortingRulesProvider.notifier).addRule(result);
    }
  }

  Future<void> _showEditDialog(
    BuildContext context,
    WidgetRef ref,
    SortingRule rule,
  ) async {
    final result = await showDialog<SortingRule>(
      context: context,
      builder: (_) => AddEditSortingRuleDialog(existing: rule),
    );
    if (!context.mounted) return;
    if (result != null) {
      await ref.read(sortingRulesProvider.notifier).updateRule(result);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    SortingRule rule,
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
            title: Text('sortingRules.deleteTitle'.tr()),
            content: Text(
              'sortingRules.deleteConfirm'.tr(namedArgs: {'name': rule.name}),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('sortingRules.cancel'.tr()),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.errorRed,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('sortingRules.delete'.tr()),
              ),
            ],
          ),
    );
    if (!context.mounted) return;
    if (confirmed == true) {
      await ref.read(sortingRulesProvider.notifier).deleteRule(rule.id);
    }
  }
}

class _RuleCard extends StatelessWidget {
  final SortingRule rule;
  final bool isDark;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RuleCard({
    super.key,
    required this.rule,
    required this.isDark,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.smMd,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface1 : AppColors.lightElevated,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: isDark ? Border.all(color: AppColors.darkElevated) : null,
        boxShadow:
            isDark
                ? null
                : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: AppOpacity.divider),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.drag_handle,
            size: 18,
            color: theme.colorScheme.onSurface.withValues(
              alpha: AppOpacity.scrim,
            ),
          ),
          const SizedBox(width: AppSpacing.smMd),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color:
                  rule.isEnabled
                      ? AppColors.brand.withValues(alpha: AppOpacity.pressed)
                      : theme.colorScheme.onSurface.withValues(
                        alpha: AppOpacity.divider,
                      ),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Icon(
              Icons.sort,
              size: 18,
              color:
                  rule.isEnabled
                      ? AppColors.brand
                      : theme.colorScheme.onSurface.withValues(
                        alpha: AppOpacity.scrim,
                      ),
            ),
          ),
          const SizedBox(width: AppSpacing.smMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rule.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color:
                        rule.isEnabled
                            ? null
                            : theme.colorScheme.onSurface.withValues(
                              alpha: AppOpacity.medium,
                            ),
                  ),
                ),
                _buildSubtitle(context),
              ],
            ),
          ),
          BrandSwitch(value: rule.isEnabled, onChanged: (_) => onToggle()),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: onEdit,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              size: 18,
              color: AppColors.errorRed,
            ),
            onPressed: onDelete,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildSubtitle(BuildContext context) {
    final parts = <String>[];
    if (rule.condition.platform.isNotEmpty) parts.add(rule.condition.platform);
    if (rule.condition.fileExtension.isNotEmpty) {
      parts.add('.${rule.condition.fileExtension}');
    }
    if (rule.condition.urlContains.isNotEmpty) {
      parts.add('"${rule.condition.urlContains}"');
    }
    if (rule.renameTemplate.isNotEmpty) parts.add('→ ${rule.renameTemplate}');
    if (rule.destFolder.isNotEmpty) parts.add('📁 ${rule.destFolder}');
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join('  •  '),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(
          context,
        ).colorScheme.onSurface.withValues(alpha: AppOpacity.medium),
      ),
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  final bool isDark;

  const _EmptyState({required this.onAdd, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(
                alpha: AppOpacity.divider,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.sort,
              size: 28,
              color: theme.colorScheme.onSurface.withValues(
                alpha: AppOpacity.scrim,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'sortingRules.emptyTitle'.tr(),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'sortingRules.emptySubtitle'.tr(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(
                alpha: AppOpacity.overlay,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.mdLg),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: Text('sortingRules.addRule'.tr()),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brand,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
