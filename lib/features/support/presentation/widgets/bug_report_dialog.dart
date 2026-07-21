import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../../../../core/providers/backend_providers.dart';
import '../../../downloads/domain/entities/download_entity.dart';
import '../../../assistant/domain/services/error_diagnostics_service.dart';

class BugReportDialog extends ConsumerStatefulWidget {
  /// Optional download context — pre-fills the form with download error info.
  final DownloadEntity? downloadContext;

  const BugReportDialog({super.key, this.downloadContext});

  /// Show the dialog with optional download context for auto-fill.
  static Future<void> show(
    BuildContext context, {
    DownloadEntity? downloadContext,
  }) {
    return showDialog(
      context: context,
      builder: (_) => BugReportDialog(downloadContext: downloadContext),
    );
  }

  @override
  ConsumerState<BugReportDialog> createState() => _BugReportDialogState();
}

class _BugReportDialogState extends ConsumerState<BugReportDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _stepsController = TextEditingController();
  bool _isSubmitting = false;
  bool _attachDiagnosticLog = true;

  @override
  void initState() {
    super.initState();
    _prefillFromContext();
  }

  void _prefillFromContext() {
    final download = widget.downloadContext;
    if (download == null) return;

    final errorCode = download.errorCode;
    final platform = download.platform;

    // Title: "[platform] error_code — filename"
    final titleParts = <String>[];
    if (platform.isNotEmpty && platform != 'unknown') {
      titleParts.add('[$platform]');
    }
    if (errorCode != null) {
      titleParts.add(errorCode.name);
    } else {
      titleParts.add('Download failed');
    }
    titleParts.add('— ${download.title ?? download.filename}');
    _titleController.text = titleParts.join(' ');

    // Description: structured context
    final desc = StringBuffer();
    desc.writeln('**URL:** ${download.url}');
    desc.writeln('**Platform:** $platform');
    desc.writeln('**Status:** ${download.status.displayLabel}');
    if (errorCode != null) {
      desc.writeln('**Error Code:** ${errorCode.name}');
    }
    if (download.errorDetail != null) {
      desc.writeln('**Error Detail:** ${download.errorDetail}');
    }
    if (download.qualityLabel != null) {
      desc.writeln('**Quality:** ${download.qualityLabel}');
    }
    desc.writeln('**Download Method:** ${download.downloadMethod}');
    if (download.retryCount > 0) {
      desc.writeln('**Retry Count:** ${download.retryCount}');
    }

    // Include error diagnostics summary if available
    try {
      final diagnostics = ref.read(errorDiagnosticsProvider);
      if (errorCode != null) {
        final matching =
            diagnostics.patterns
                .where((p) => p.errorCode == errorCode)
                .toList();
        if (matching.isNotEmpty) {
          desc.writeln();
          desc.writeln('**Error Pattern:**');
          for (final pattern in matching) {
            final scope = pattern.platform ?? 'cross-platform';
            desc.writeln(
              '  - ${pattern.occurrences}x on $scope '
              '(${pattern.timeSpan}, '
              '${(pattern.healRate * 100).round()}% auto-healed)',
            );
          }
        }
      }
    } catch (_) {
      // Error diagnostics not available, skip
    }

    desc.writeln();
    desc.writeln('---');
    desc.writeln('*Auto-generated from failed download context*');

    _descriptionController.text = desc.toString();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _stepsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasContext = widget.downloadContext != null;

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
                color: AppColors.errorRed.withValues(alpha: AppOpacity.pressed),
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: AppColors.errorRed.withValues(alpha: 0.24),
                ),
              ),
              child: const Icon(
                Icons.bug_report_outlined,
                size: 22,
                color: AppColors.errorRed,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.bugReportTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    hasContext
                        ? AppLocalizations.bugReportSubtitleErrorContext
                        : AppLocalizations.bugReportSubtitleGeneric,
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
        content: SizedBox(
          width: 520,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Context banner for auto-filled reports
                if (hasContext) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.brand.withValues(
                        alpha: AppOpacity.subtle,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border(
                        left: BorderSide(
                          width: 2,
                          color: AppColors.accentHighlight,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_fix_high,
                          size: 14,
                          color: AppColors.accentHighlight,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            AppLocalizations.bugReportContextBanner,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.accentHighlight,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                TextFormField(
                  controller: _titleController,
                  style: theme.textTheme.bodyMedium,
                  decoration: _inputDecoration(
                    context,
                    AppLocalizations.bugReportTitleField,
                  ),
                  validator:
                      (v) =>
                          (v == null || v.trim().isEmpty)
                              ? AppLocalizations.bugReportTitleRequired
                              : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _descriptionController,
                  style: theme.textTheme.bodyMedium,
                  decoration: _inputDecoration(
                    context,
                    AppLocalizations.bugReportDescription,
                    alignLabelWithHint: true,
                  ),
                  maxLines: 6,
                  minLines: 3,
                  validator:
                      (v) =>
                          (v == null || v.trim().isEmpty)
                              ? AppLocalizations.bugReportDescriptionRequired
                              : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _stepsController,
                  style: theme.textTheme.bodyMedium,
                  decoration: _inputDecoration(
                    context,
                    AppLocalizations.bugReportSteps,
                    hintText: AppLocalizations.bugReportStepsHint,
                    alignLabelWithHint: true,
                  ),
                  maxLines: 4,
                  minLines: 2,
                ),
                const SizedBox(height: AppSpacing.md),
                // Diagnostic log toggle
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
                      AppLocalizations.bugReportSubmit,
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
      // Collect diagnostic log if enabled
      String? diagnosticLog;
      if (_attachDiagnosticLog) {
        diagnosticLog = await appLogger.getRecentLogs();
      }

      final service = ref.read(backendServiceProvider);
      final result = await service.submitBug(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        steps:
            _stepsController.text.trim().isEmpty
                ? null
                : _stepsController.text.trim(),
        diagnosticLog: diagnosticLog,
      );

      result.when(
        success: (_) {
          if (mounted) {
            Navigator.of(context).pop();
            AppSnackBar.success(
              context,
              message: AppLocalizations.bugReportSuccess,
            );
          }
        },
        failure: (e) {
          appLogger.error('Bug report submit failed', e);
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
