import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../../../../core/providers/backend_providers.dart';

class CreateTicketDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;

  /// Optional pre-fill values for escalation from diagnostics.
  final String? initialSubject;
  final String? initialMessage;
  final String? initialCategory;

  const CreateTicketDialog({
    super.key,
    required this.onCreated,
    this.initialSubject,
    this.initialMessage,
    this.initialCategory,
  });

  @override
  ConsumerState<CreateTicketDialog> createState() => _CreateTicketDialogState();
}

class _CreateTicketDialogState extends ConsumerState<CreateTicketDialog> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  String _category = 'general';
  bool _isSubmitting = false;
  bool _attachDiagnosticLog = true;

  // Resolved at runtime via getter — labels resolve through AppLocalizations
  // so they're locale-aware (instead of hardcoded English).
  static List<(String, String)> get _categories => [
    ('general', AppLocalizations.createTicketCategoryGeneral),
    ('billing', AppLocalizations.createTicketCategoryBilling),
    ('technical', AppLocalizations.createTicketCategoryTechnical),
    ('feature_request', AppLocalizations.createTicketCategoryFeatureRequest),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialSubject != null) {
      _subjectController.text = widget.initialSubject!;
    }
    if (widget.initialMessage != null) {
      _messageController.text = widget.initialMessage!;
    }
    if (widget.initialCategory != null) {
      _category = widget.initialCategory!;
    }
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CallbackShortcuts(
      bindings: {
        SingleActivator(
          LogicalKeyboardKey.enter,
          meta: Platform.isMacOS,
          control: !Platform.isMacOS,
        ): () {
          if (!_isSubmitting) _submit();
        },
      },
      child: AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xl,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.dialog),
          side: BorderSide(color: AppColors.border(context)),
        ),
        backgroundColor: AppColors.surface1(context),
        titlePadding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          0,
        ),
        contentPadding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          0,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.brand.withValues(alpha: AppOpacity.subtle),
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: AppColors.accentHighlight.withValues(alpha: 0.24),
                ),
              ),
              child: Icon(
                Icons.mail_outlined,
                size: 22,
                color: AppColors.accentHighlight,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.supportNewTicket,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    AppLocalizations.createTicketSubtitleDirectLine,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: AppOpacity.secondary,
                      ),
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _subjectController,
                  style: theme.textTheme.bodyMedium,
                  decoration: _inputDecoration(
                    context,
                    AppLocalizations.supportSubject,
                  ),
                  validator:
                      (v) =>
                          (v == null || v.trim().isEmpty)
                              ? AppLocalizations.supportSubjectRequired
                              : null,
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  value: _category,
                  style: theme.textTheme.bodyMedium,
                  dropdownColor: AppColors.surface1(context),
                  decoration: _inputDecoration(
                    context,
                    AppLocalizations.supportCategory,
                  ),
                  items:
                      _categories
                          .map(
                            (c) => DropdownMenuItem(
                              value: c.$1,
                              child: Text(c.$2),
                            ),
                          )
                          .toList(),
                  onChanged: (v) => setState(() => _category = v ?? 'general'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _messageController,
                  style: theme.textTheme.bodyMedium,
                  decoration: _inputDecoration(
                    context,
                    AppLocalizations.supportMessage,
                    alignLabelWithHint: true,
                  ),
                  maxLines: 5,
                  minLines: 3,
                  validator:
                      (v) =>
                          (v == null || v.trim().isEmpty)
                              ? AppLocalizations.supportMessageRequired
                              : null,
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: _attachDiagnosticLog,
                        onChanged:
                            (v) => setState(
                              () => _attachDiagnosticLog = v ?? true,
                            ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: GestureDetector(
                        onTap:
                            () => setState(
                              () =>
                                  _attachDiagnosticLog = !_attachDiagnosticLog,
                            ),
                        child: Text(
                          AppLocalizations.bugReportAttachDiagnosticLogs,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.mdLg,
                vertical: AppSpacing.smMd,
              ),
            ),
            child: Text(AppLocalizations.commonCancel),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentHighlight,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.accentHighlight.withValues(
                alpha: AppOpacity.medium,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.smMd,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
            ),
            child:
                _isSubmitting
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                    : Text(
                      AppLocalizations.supportSubmit,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(
    BuildContext context,
    String label, {
    bool alignLabelWithHint = false,
    String? hintText,
  }) {
    final theme = Theme.of(context);
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      alignLabelWithHint: alignLabelWithHint,
      filled: true,
      fillColor: AppColors.surface2(context),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        borderSide: BorderSide(color: AppColors.border(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        borderSide: BorderSide(color: AppColors.border(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        borderSide: BorderSide(color: AppColors.accentHighlight, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        borderSide: const BorderSide(color: AppColors.errorRed),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        borderSide: const BorderSide(color: AppColors.errorRed, width: 2),
      ),
      labelStyle: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      String? diagnosticLog;
      if (_attachDiagnosticLog) {
        diagnosticLog = await appLogger.getRecentLogs();
      }

      final service = ref.read(backendServiceProvider);
      final result = await service.createTicket(
        subject: _subjectController.text.trim(),
        category: _category,
        message: _messageController.text.trim(),
        diagnosticLog: diagnosticLog,
      );

      result.when(
        success: (_) {
          widget.onCreated();
          if (mounted) Navigator.of(context).pop();
        },
        failure: (e) {
          appLogger.error('Create ticket submit failed', e);
          if (mounted) {
            AppSnackBar.error(
              context,
              message: AppLocalizations.errorFeedbackHint('unknown'),
            );
          }
        },
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
