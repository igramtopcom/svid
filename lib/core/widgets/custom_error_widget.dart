import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../config/env_config.dart';
import '../services/clipboard_service.dart';
import '../services/error_reporter_service.dart';
import '../theme/app_colors.dart';
import 'app_snack_bar.dart';

/// Custom error widget displayed when a Flutter widget tree error occurs.
///
/// In debug mode: shows full stack trace (default Flutter red screen).
/// In release mode: shows a user-friendly message with action buttons.
class CustomErrorWidget extends StatelessWidget {
  final FlutterErrorDetails errorDetails;
  final ErrorReporterService? errorReporter;

  const CustomErrorWidget(
    this.errorDetails, {
    super.key,
    this.errorReporter,
  });

  @override
  Widget build(BuildContext context) {
    // Always log the error for diagnosis, even in release mode
    debugPrint('[ErrorWidget] ${errorDetails.exceptionAsString()}');
    debugPrint('[ErrorWidget] ${errorDetails.stack}');

    // In debug mode, use default error widget for developer info
    if (kDebugMode) {
      return ErrorWidget(errorDetails.exception);
    }

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                AppLocalizations.errorWidgetTitle,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.errorWidgetSubtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: AppOpacity.strong),
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _copyDetails(context),
                    icon: const Icon(Icons.copy, size: 18),
                    label: Text(AppLocalizations.errorWidgetCopyDetails),
                  ),
                  if (EnvConfig.isSentryConfigured) ...[
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: () => _sendFeedback(context),
                      icon: const Icon(Icons.send, size: 18),
                      label: Text(AppLocalizations.errorWidgetSendFeedback),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _copyDetails(BuildContext context) {
    final details = errorDetails.toString();
    ClipboardService.setText(details);

    AppSnackBar.info(context, message: AppLocalizations.errorWidgetDetailsCopied);
  }

  void _sendFeedback(BuildContext context) {
    errorReporter?.captureException(
      errorDetails.exception,
      stackTrace: errorDetails.stack,
      context: 'user_feedback_from_error_widget',
    );

    AppSnackBar.success(context, message: AppLocalizations.errorWidgetFeedbackSent);
  }
}
