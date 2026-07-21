import 'package:flutter/material.dart';

import '../../../../core/core.dart';
import '../../data/webview/app_webview.dart';
import '../../domain/services/phishing_detection_service.dart';

/// Utility for showing the phishing/suspicious URL warning dialog.
class BrowserPhishingDialog {
  BrowserPhishingDialog._();

  /// Show phishing warning dialog. User can proceed or go back.
  static void show({
    required BuildContext context,
    required String url,
    required PhishingCheckResult result,
    required PhishingDetectionService phishingService,
    required AppWebViewController? controller,
  }) {
    final reason = phishingService.getWarningReason(url);
    final isDangerous = result == PhishingCheckResult.dangerous;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          isDangerous ? Icons.dangerous_rounded : Icons.warning_amber_rounded,
          color: isDangerous ? Colors.red : Colors.orange,
          size: 48,
        ),
        title: Text(AppLocalizations.phishingWarningTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isDangerous
                ? AppLocalizations.phishingWarningDangerous
                : AppLocalizations.phishingWarningSuspicious),
            if (reason != null) ...[
              const SizedBox(height: 8),
              Text(
                reason,
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(ctx).colorScheme.error,
                    fontWeight: FontWeight.w500),
              ),
            ],
            const SizedBox(height: 8),
            SelectableText(
              url,
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                color: Colors.grey,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocalizations.phishingGoBack),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // Proceed by loading the URL
              controller?.loadUrl(url);
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(AppLocalizations.phishingProceed),
          ),
        ],
      ),
    );
  }
}
