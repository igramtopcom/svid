import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../../../core/auth/presentation/widgets/platform_login_dialog.dart';
import '../../domain/services/cookie_inspector_service.dart';
import '../../domain/services/phishing_detection_service.dart';
import '../providers/browser_session_providers.dart';
import '../providers/content_filter_providers.dart';
import '../screens/cookie_management_screen.dart';

/// Security shield icon for the browser URL bar.
///
/// Shows green/orange/red based on HTTPS and phishing detection status.
class BrowserSecurityShield extends ConsumerWidget {
  final String currentUrl;

  const BrowserSecurityShield({super.key, required this.currentUrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (currentUrl.isEmpty ||
        currentUrl == 'about:blank' ||
        !ref.read(phishingDetectionEnabledProvider)) {
      return const SizedBox.shrink();
    }

    final phishingService = ref.read(phishingDetectionServiceProvider);
    final httpsService = ref.read(httpsEnforcementServiceProvider);

    final phishingResult = phishingService.checkUrl(currentUrl);
    final isInsecure = httpsService.isInsecure(currentUrl);

    IconData icon;
    Color color;
    String tooltip;

    if (phishingResult == PhishingCheckResult.dangerous) {
      icon = Icons.gpp_bad_rounded;
      color = Colors.red;
      tooltip = AppLocalizations.phishingWarningDangerous;
    } else if (phishingResult == PhishingCheckResult.suspicious) {
      icon = Icons.gpp_maybe_rounded;
      color = Colors.orange;
      tooltip = AppLocalizations.phishingWarningSuspicious;
    } else if (isInsecure) {
      icon = Icons.gpp_maybe_rounded;
      color = Colors.orange;
      tooltip = AppLocalizations.httpsInsecure;
    } else {
      icon = Icons.gpp_good_rounded;
      color = Colors.green;
      tooltip = AppLocalizations.httpsSecure;
    }

    return Tooltip(message: tooltip, child: Icon(icon, size: 18, color: color));
  }
}

/// Small colored dot indicating session health for the current platform.
///
/// Tapping navigates to the cookie management screen.
class BrowserSessionHealthDot extends StatelessWidget {
  final CookieSessionSummary summary;

  const BrowserSessionHealthDot({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    Color dotColor;
    String tooltip;

    if (!summary.isHealthy) {
      if (summary.totalCookies == 0) {
        dotColor = Colors.grey;
        tooltip = AppLocalizations.cookieManagementNoSession;
      } else {
        dotColor = Colors.red;
        tooltip = AppLocalizations.cookieManagementExpired;
      }
    } else if (summary.expiringSoonCount > 0) {
      dotColor = Colors.orange;
      tooltip = AppLocalizations.cookieManagementExpiringSoon;
    } else {
      dotColor = Colors.green;
      tooltip = AppLocalizations.cookieManagementHealthy;
    }

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CookieManagementScreen()),
          );
        },
        child: Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

/// Login URLs per platform for re-login from the warning banner.
const browserLoginUrls = {
  'youtube':
      'https://accounts.google.com/ServiceLogin?continue=https://www.youtube.com/',
  'facebook': 'https://www.facebook.com/login',
  'instagram': 'https://www.instagram.com/accounts/login',
  'tiktok': 'https://www.tiktok.com/login',
  'x': 'https://twitter.com/i/flow/login',
  'twitter': 'https://twitter.com/i/flow/login',
  'reddit': 'https://www.reddit.com/login',
  'pinterest': 'https://www.pinterest.com/login',
};

/// Banner warning about expiring session cookies for the current platform.
class BrowserExpiryWarningBanner extends ConsumerWidget {
  final AsyncValue<CookieSessionSummary?> healthAsync;
  final Set<String> dismissedPlatforms;
  final VoidCallback Function(String platform) onDismiss;

  const BrowserExpiryWarningBanner({
    super.key,
    required this.healthAsync,
    required this.dismissedPlatforms,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final summary = healthAsync.valueOrNull;
    if (summary == null) return const SizedBox.shrink();

    // Show banner only when cookies exist but are expiring soon
    if (!summary.isHealthy || summary.expiringSoonCount == 0) {
      return const SizedBox.shrink();
    }

    // Dismiss once per session per platform
    if (dismissedPlatforms.contains(summary.platform)) {
      return const SizedBox.shrink();
    }

    final loginUrl = browserLoginUrls[summary.platform];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.smMd,
        vertical: AppSpacing.sm,
      ),
      color: Colors.orange.withValues(alpha: AppOpacity.subtle),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: Colors.orange,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              AppLocalizations.cookieManagementExpiringSoonBanner(
                summary.platform,
              ),
              style: AppTypography.metadata.copyWith(color: cs.onSurface),
            ),
          ),
          if (loginUrl != null)
            TextButton(
              onPressed: () async {
                await showPlatformLoginDialog(
                  context: context,
                  platform: summary.platform,
                  loginUrl: loginUrl,
                );
                if (!context.mounted) return;
                ref.invalidate(browserSessionHealthProvider);
              },
              child: Text(
                AppLocalizations.cookieManagementRelogin,
                style: AppTypography.metadata,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: onDismiss(summary.platform),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
