import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/download_entity.dart';
import '../../domain/entities/download_status.dart';
import '../../domain/entities/sorting_rule.dart';
import '../../domain/services/sorting_rule_service.dart';

/// Provides a sample [DownloadEntity] for live rename preview.
final _kPreviewEntity = DownloadEntity(
  id: 0,
  url: 'https://youtube.com/watch?v=example',
  filename: 'Sample Video.mp4',
  savePath: '/Downloads/Sample Video.mp4',
  status: DownloadStatus.completed,
  totalBytes: 0,
  downloadedBytes: 0,
  speed: 0,
  platform: 'youtube',
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  title: 'Sample Video',
  uploader: 'Channel Name',
  uploadDate: '20260101',
  qualityLabel: '1080p',
);

/// Dialog for creating or editing a [SortingRule].
class AddEditSortingRuleDialog extends StatefulWidget {
  final SortingRule? existing;

  const AddEditSortingRuleDialog({super.key, this.existing});

  @override
  State<AddEditSortingRuleDialog> createState() =>
      _AddEditSortingRuleDialogState();
}

class _AddEditSortingRuleDialogState extends State<AddEditSortingRuleDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _platformCtrl;
  late final TextEditingController _extCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _destCtrl;
  late final TextEditingController _templateCtrl;

  final _formKey = GlobalKey<FormState>();
  final _service = SortingRuleService();

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    _nameCtrl = TextEditingController(text: r?.name ?? '');
    _platformCtrl = TextEditingController(text: r?.condition.platform ?? '');
    _extCtrl = TextEditingController(text: r?.condition.fileExtension ?? '');
    _urlCtrl = TextEditingController(text: r?.condition.urlContains ?? '');
    _destCtrl = TextEditingController(text: r?.destFolder ?? '');
    _templateCtrl = TextEditingController(text: r?.renameTemplate ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _platformCtrl.dispose();
    _extCtrl.dispose();
    _urlCtrl.dispose();
    _destCtrl.dispose();
    _templateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    InputDecoration nocturneInput(String label, {String? hint}) =>
        InputDecoration(
          labelText: label,
          hintText: hint,
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
            borderSide: BorderSide(color: AppColors.brand, width: 1.5),
          ),
        );

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
        isEdit ? 'sortingRules.editRule'.tr() : 'sortingRules.addRule'.tr(),
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.sizeOf(context).height * 0.70,
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
                  decoration: nocturneInput('sortingRules.ruleName'.tr()),
                  validator:
                      (v) =>
                          (v == null || v.trim().isEmpty)
                              ? 'sortingRules.nameRequired'.tr()
                              : null,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'sortingRules.conditions'.tr(),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _platformCtrl,
                        decoration: nocturneInput(
                          'sortingRules.platform'.tr(),
                          hint: 'youtube, tiktok…',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.smMd),
                    Expanded(
                      child: TextFormField(
                        controller: _extCtrl,
                        decoration: nocturneInput(
                          'sortingRules.fileExt'.tr(),
                          hint: 'mp4, mp3…',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _urlCtrl,
                  decoration: nocturneInput(
                    'sortingRules.urlContains'.tr(),
                    hint: 'playlist, shorts…',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _destCtrl,
                  decoration: nocturneInput(
                    'sortingRules.destFolder'.tr(),
                    hint: '/Users/me/Videos/YouTube',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _templateCtrl,
                  decoration: nocturneInput(
                    'sortingRules.renameTemplate'.tr(),
                    hint: '{title} - {uploader} ({date}).{ext}',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.xs),
                _buildPreview(context),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('sortingRules.cancel'.tr()),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brand,
            foregroundColor: Colors.white,
          ),
          onPressed: _submit,
          child: Text(
            isEdit ? 'sortingRules.save'.tr() : 'sortingRules.add'.tr(),
          ),
        ),
      ],
    );
  }

  Widget _buildPreview(BuildContext context) {
    final tmpl = _templateCtrl.text.trim();
    if (tmpl.isEmpty) return const SizedBox.shrink();
    final preview = _service.applyRename(tmpl, _kPreviewEntity);
    return Text(
      'preview: $preview',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final id =
        widget.existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final order = widget.existing?.order ?? 999;
    final rule = SortingRule(
      id: id,
      name: _nameCtrl.text.trim(),
      condition: SortingCondition(
        platform: _platformCtrl.text.trim(),
        fileExtension: _extCtrl.text.trim().replaceFirst('.', ''),
        urlContains: _urlCtrl.text.trim(),
      ),
      destFolder: _destCtrl.text.trim(),
      renameTemplate: _templateCtrl.text.trim(),
      order: order,
    );
    Navigator.pop(context, rule);
  }
}
