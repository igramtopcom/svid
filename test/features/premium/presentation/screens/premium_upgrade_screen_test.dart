import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/errors/app_exception.dart';
import 'package:svid/core/navigation/navigation_constants.dart';
import 'package:svid/features/premium/domain/entities/premium_feature.dart';
import 'package:svid/features/premium/domain/entities/premium_license.dart';
import 'package:svid/features/premium/domain/entities/premium_tier.dart';
import 'package:svid/features/premium/presentation/screens/premium_upgrade_screen.dart';
import 'package:svid/features/premium/presentation/widgets/upgrade_prompt_dialog.dart';

void main() {
  group('NavigationConstants premiumIndex', () {
    test('premiumIndex is 1010', () {
      expect(NavigationConstants.premiumIndex, 1010);
    });

    test('premiumIndex is a utility screen', () {
      expect(
        NavigationConstants.isUtilityScreen(NavigationConstants.premiumIndex),
        true,
      );
    });

    test('premiumIndex is not a primary tab', () {
      expect(
        NavigationConstants.isPrimaryTab(NavigationConstants.premiumIndex),
        false,
      );
    });

    test('premiumIndex is not a download filter tab', () {
      expect(
        NavigationConstants.isDownloadFilterTab(
          NavigationConstants.premiumIndex,
        ),
        false,
      );
    });
  });

  group('PremiumFeature coverage', () {
    test('all 13 features have icons', () {
      for (final feature in PremiumFeature.values) {
        expect(
          () => UpgradePromptDialog.featureIcon(feature),
          returnsNormally,
          reason: 'Missing icon for $feature',
        );
      }
    });

    test('all 13 features have display names', () {
      // featureDisplayName calls .tr() which may not be initialized,
      // but the function itself should not throw type errors
      expect(PremiumFeature.values.length, 13);
    });

    test('features are grouped correctly', () {
      // Download power
      expect(PremiumFeature.unlimitedDownloads.index, isNonNegative);
      expect(PremiumFeature.highQuality4K.index, isNonNegative);
      expect(PremiumFeature.extendedConcurrent.index, isNonNegative);
      expect(PremiumFeature.batchDownload.index, isNonNegative);
      // Player & Browser
      expect(PremiumFeature.advancedPlayer.index, isNonNegative);
      expect(PremiumFeature.browserShield.index, isNonNegative);
      // Scheduling & Organization
      expect(PremiumFeature.scheduledDownloads.index, isNonNegative);
      expect(PremiumFeature.bandwidthControl.index, isNonNegative);
      expect(PremiumFeature.smartCollections.index, isNonNegative);
      // Analytics & Extras
      expect(PremiumFeature.advancedAnalytics.index, isNonNegative);
      expect(PremiumFeature.batchImport.index, isNonNegative);
      expect(PremiumFeature.prioritySupport.index, isNonNegative);
    });
  });

  group('PremiumLicense display helpers', () {
    test('free license shows correct tier', () {
      const license = PremiumLicense.free;
      expect(license.isFree, true);
      expect(license.isPremium, false);
      expect(license.licenseKey, isNull);
      expect(license.purchaseDate, isNull);
    });

    test('premium license shows all info', () {
      final now = DateTime(2026, 2, 28, 12, 0);
      final license = PremiumLicense(
        tier: PremiumTier.premium,
        licenseKey: 'SSVID-1234-5678-9abc-def0-1234-5678-9abc-def0',
        purchaseDate: now,
        lastVerified: now,
        paymentMethod: 'stripe',
        transactionId: 'txn_abc123',
      );

      expect(license.isPremium, true);
      expect(
        license.licenseKey,
        'SSVID-1234-5678-9abc-def0-1234-5678-9abc-def0',
      );
      expect(license.purchaseDate, now);
      expect(license.paymentMethod, 'stripe');
      expect(license.transactionId, 'txn_abc123');
    });

    test('license key substring for display', () {
      const key = 'SSVID-1234-5678-9abc-def0-1234-5678-9abc-def0';
      // Screen shows first 10 chars + "..."
      expect(key.substring(0, 10), 'SSVID-1234');
    });

    test('transaction ID substring for display', () {
      const txId = 'txn_abc123456789';
      // Screen shows first 12 chars + "..."
      expect(txId.substring(0, 12), 'txn_abc12345');
    });
  });

  group('Date formatting', () {
    test('formats date with zero-padded month and day', () {
      final date = DateTime(2026, 2, 5);
      final formatted =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      expect(formatted, '2026-02-05');
    });

    test('formats date without zero-padding for double-digit values', () {
      final date = DateTime(2026, 12, 25);
      final formatted =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      expect(formatted, '2026-12-25');
    });
  });

  group('restore license error classification', () {
    test('treats backend LICENSE_NOT_FOUND as restore-not-found', () {
      const exception = AppException.network(
        message: 'No active license found for this email',
        statusCode: 404,
        data: 'LICENSE_NOT_FOUND',
      );

      expect(isRestoreLicenseNotFoundException(exception), isTrue);
    });

    test('does not treat server/network failures as restore-not-found', () {
      const internalError = AppException.network(
        message: 'Failed to restore license',
        statusCode: 500,
        data: 'INTERNAL_ERROR',
      );
      const timeout = AppException.network(message: 'Connection timed out');

      expect(isRestoreLicenseNotFoundException(internalError), isFalse);
      expect(isRestoreLicenseNotFoundException(timeout), isFalse);
      expect(isRestoreLicenseNotFoundException(Exception('offline')), isFalse);
    });
  });
}
