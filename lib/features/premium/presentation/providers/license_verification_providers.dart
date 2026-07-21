import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/backend_providers.dart';
import '../../data/services/license_activation_handler.dart';
import '../../data/services/license_verification_service.dart';
import 'pdfconv_paypal_providers.dart';
import 'premium_providers.dart';

/// License verification service provider
final licenseVerificationServiceProvider = Provider<LicenseVerificationService>(
  (ref) {
    final client = ref.watch(backendClientProvider);
    final licenseService = ref.watch(premiumLicenseServiceProvider);
    return LicenseVerificationService(client, licenseService);
  },
);

/// License activation handler provider (deep-link: ssvid://activate?key=...).
///
/// The handler routes activation through PremiumNotifier.activateLicense
/// (via [activateViaNotifier] callback) so Riverpod premium state updates
/// and downstream side-effects (tombstone clear, UI refresh) fire correctly.
/// The handler stays in the data layer; the callback wires presentation in
/// without an upward import.
final licenseActivationHandlerProvider = Provider<LicenseActivationHandler>((
  ref,
) {
  final verificationService = ref.watch(licenseVerificationServiceProvider);
  final handler = LicenseActivationHandler(
    verificationService: verificationService,
    onPaymentComplete:
        () => ref.read(pdfConvPayPalProvider.notifier).refreshPendingCheckout(),
    activateViaNotifier:
        (key, {paymentMethod, billingCycle, expiresAt}) => ref
            .read(premiumLicenseProvider.notifier)
            .activateLicense(
              key,
              paymentMethod: paymentMethod,
              billingCycle: billingCycle,
              expiresAt: expiresAt,
            ),
  );
  ref.onDispose(handler.dispose);
  return handler;
});

/// Whether license needs re-verification (> 7 days since last check)
final licenseNeedsVerificationProvider = Provider<bool>((ref) {
  final license = ref.watch(premiumLicenseProvider);
  return license.needsVerification();
});

/// Whether license is within offline grace period
final licenseGracePeriodActiveProvider = Provider<bool>((ref) {
  final license = ref.watch(premiumLicenseProvider);
  return license.isPremium && license.isWithinGracePeriod();
});
