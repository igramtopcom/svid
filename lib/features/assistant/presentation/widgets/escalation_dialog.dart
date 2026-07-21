import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../../../../core/providers/backend_providers.dart';

class EscalationDialog extends ConsumerStatefulWidget {
  final String sessionId;
  final void Function(String? ticketId) onEscalated;

  const EscalationDialog({
    super.key,
    required this.sessionId,
    required this.onEscalated,
  });

  @override
  ConsumerState<EscalationDialog> createState() => _EscalationDialogState();
}

class _EscalationDialogState extends ConsumerState<EscalationDialog> {
  final _subjectController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _subjectController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      backgroundColor:
          isDark ? AppColors.darkSurface1 : AppColors.lightElevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(
          color: isDark ? AppColors.darkElevated : AppColors.lightSurface3,
        ),
      ),
      title: Text(
        AppLocalizations.assistantEscalateTitle,
        style: theme.textTheme.titleMedium?.copyWith(
          color: isDark ? AppColors.darkLightText : AppColors.darkSurface1,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.assistantEscalateDescription,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _subjectController,
              decoration: InputDecoration(
                labelText: AppLocalizations.assistantEscalateSubject,
                hintText: AppLocalizations.assistantEscalateSubjectHint,
                labelStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  borderSide: BorderSide(
                    color:
                        isDark
                            ? AppColors.darkElevated
                            : AppColors.lightSurface3,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  borderSide: BorderSide(
                    color:
                        isDark
                            ? AppColors.darkElevated
                            : AppColors.lightSurface3,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  borderSide: BorderSide(
                    color: AppColors.accentHighlight,
                    width: 2,
                  ),
                ),
              ),
              autofocus: true,
              onSubmitted: (_) {
                if (!_isSubmitting) _escalate();
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: Text(
            AppLocalizations.commonCancel,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _escalate,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.warningAmber,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
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
                  : Text(AppLocalizations.assistantEscalateConfirm),
        ),
      ],
    );
  }

  Future<void> _escalate() async {
    final subject = _subjectController.text.trim();
    if (subject.isEmpty) {
      AppSnackBar.warning(
        context,
        message: AppLocalizations.assistantEscalateSubjectHint,
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final service = ref.read(backendServiceProvider);
      final result = await service.escalateSession(widget.sessionId, subject);

      result.when(
        success: (data) {
          widget.onEscalated(data.ticketId);
          if (mounted) Navigator.of(context).pop();
        },
        failure: (e) {
          if (mounted) {
            AppSnackBar.error(
              context,
              message: AppLocalizations.assistantLoadError,
            );
          }
        },
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
