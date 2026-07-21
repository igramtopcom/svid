import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../../../../core/providers/backend_providers.dart';

class RatingDialog extends ConsumerStatefulWidget {
  const RatingDialog({super.key});

  @override
  ConsumerState<RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends ConsumerState<RatingDialog> {
  int _rating = 0;
  final _reviewController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.enter, meta: Platform.isMacOS, control: !Platform.isMacOS):
            () { if (!_isSubmitting && _rating > 0) _submit(); },
      },
      child: AlertDialog(
      title: Text(AppLocalizations.ratingTitle),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocalizations.ratingSubtitle,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            // Star rating
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final starIndex = index + 1;
                return IconButton(
                  iconSize: 40,
                  onPressed: () => setState(() => _rating = starIndex),
                  icon: Icon(
                    starIndex <= _rating ? Icons.star : Icons.star_border,
                    color: starIndex <= _rating ? Colors.amber : Theme.of(context).colorScheme.outline,
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reviewController,
              decoration: InputDecoration(
                labelText: AppLocalizations.ratingReview,
                hintText: AppLocalizations.ratingReviewHint,
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
              minLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: Text(AppLocalizations.commonCancel),
        ),
        FilledButton(
          onPressed: _isSubmitting || _rating == 0 ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(AppLocalizations.ratingSubmit),
        ),
      ],
    ));
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);

    try {
      final service = ref.read(backendServiceProvider);
      final result = await service.submitRating(
        rating: _rating,
        review: _reviewController.text.trim().isEmpty ? null : _reviewController.text.trim(),
      );

      result.when(
        success: (_) {
          if (mounted) {
            Navigator.of(context).pop();
            AppSnackBar.success(context, message: AppLocalizations.ratingSuccess);
          }
        },
        failure: (e) {
          appLogger.error('Rating submit failed', e);
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
