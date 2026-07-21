import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/collection_entity.dart';
import '../providers/downloads_notifier.dart';

/// Dialog for creating or editing a [CollectionEntity].
class AddEditCollectionDialog extends ConsumerStatefulWidget {
  final CollectionEntity? existing;

  const AddEditCollectionDialog({super.key, this.existing});

  @override
  ConsumerState<AddEditCollectionDialog> createState() =>
      _AddEditCollectionDialogState();
}

class _AddEditCollectionDialogState
    extends ConsumerState<AddEditCollectionDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late List<String> _platforms;
  late List<String> _statuses;

  final _formKey = GlobalKey<FormState>();

  static const _allStatuses = [
    'completed',
    'downloading',
    'paused',
    'failed',
    'pending',
    'cancelled',
  ];

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    _descCtrl = TextEditingController(text: c?.description ?? '');
    _platforms = List<String>.from(c?.filter.platforms ?? []);
    _statuses = List<String>.from(c?.filter.statuses ?? []);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    // Get known platforms from existing downloads
    final downloads = ref.watch(
      downloadsNotifierProvider.select((s) => s.downloads),
    );
    final knownPlatforms =
        downloads
            .map((d) => d.platform)
            .where((p) => p.isNotEmpty && p != 'unknown')
            .toSet()
            .toList()
          ..sort();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    Widget buildNocturneChip(String label, bool selected, VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.smMd),
          decoration: BoxDecoration(
            color:
                selected
                    ? AppColors.brand
                    : isDark
                    ? AppColors.darkSurface1.withValues(
                      alpha: AppOpacity.medium,
                    )
                    : AppColors.lightSurface2,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border:
                selected
                    ? null
                    : Border.all(
                      color:
                          isDark
                              ? AppColors.darkElevated
                              : cs.outlineVariant.withValues(
                                alpha: AppOpacity.overlay,
                              ),
                    ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color:
                  selected
                      ? Colors.white
                      : cs.onSurface.withValues(alpha: AppOpacity.strong),
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    return AlertDialog(
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      backgroundColor:
          isDark ? AppColors.darkSurface1 : AppColors.lightElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side:
            isDark
                ? BorderSide(color: AppColors.darkElevated)
                : BorderSide.none,
      ),
      title: Text(
        isEdit
            ? 'collections.editCollection'.tr()
            : 'collections.addCollection'.tr(),
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.sizeOf(context).height * 0.68,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'collections.collectionName'.tr(),
                    filled: true,
                    fillColor:
                        isDark
                            ? AppColors.darkSurface1.withValues(
                              alpha: AppOpacity.secondary,
                            )
                            : AppColors.lightSurface2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      borderSide: BorderSide(
                        color: AppColors.brand,
                        width: 1.5,
                      ),
                    ),
                  ),
                  validator:
                      (v) =>
                          (v == null || v.trim().isEmpty)
                              ? 'collections.nameRequired'.tr()
                              : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _descCtrl,
                  decoration: InputDecoration(
                    labelText: 'collections.description'.tr(),
                    filled: true,
                    fillColor:
                        isDark
                            ? AppColors.darkSurface1.withValues(
                              alpha: AppOpacity.secondary,
                            )
                            : AppColors.lightSurface2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      borderSide: BorderSide(
                        color: AppColors.brand,
                        width: 1.5,
                      ),
                    ),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: AppSpacing.md),

                // Platform filter
                if (knownPlatforms.isNotEmpty) ...[
                  Text(
                    'collections.filterPlatform'.tr(),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children:
                        knownPlatforms.map((p) {
                          final selected = _platforms.contains(p);
                          return buildNocturneChip(p, selected, () {
                            setState(() {
                              if (selected) {
                                _platforms.remove(p);
                              } else {
                                _platforms.add(p);
                              }
                            });
                          });
                        }).toList(),
                  ),
                  const SizedBox(height: AppSpacing.smMd),
                ],

                // Status filter
                Text(
                  'collections.filterStatus'.tr(),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children:
                      _allStatuses.map((s) {
                        final selected = _statuses.contains(s);
                        return buildNocturneChip(s, selected, () {
                          setState(() {
                            if (selected) {
                              _statuses.remove(s);
                            } else {
                              _statuses.add(s);
                            }
                          });
                        });
                      }).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('collections.cancel'.tr()),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brand,
            foregroundColor: Colors.white,
          ),
          onPressed: _submit,
          child: Text(
            isEdit ? 'collections.save'.tr() : 'collections.add'.tr(),
          ),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final id =
        widget.existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final result = CollectionEntity(
      id: id,
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      filter: CollectionFilter(
        platforms: List<String>.from(_platforms),
        statuses: List<String>.from(_statuses),
      ),
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
    );
    Navigator.pop(context, result);
  }
}
