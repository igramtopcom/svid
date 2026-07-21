import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/brand_config.dart';
import '../../../../core/providers/backend_providers.dart';

const pdfConvPayPalCheckoutFlagKey = 'vidcombo_pdfconv_paypal_checkout';

/// Remote rollout gate for creating new PDFConv PayPal purchase intents.
///
/// The brand setting is only a static capability. Missing flags and failed
/// flag fetches stay closed; recovery of an existing intent is gated
/// separately by the capability so a kill switch cannot strand a buyer.
final pdfConvPayPalCheckoutEnabledProvider = Provider<bool>((ref) {
  if (!BrandConfig.current.hasPdfConvPayPalCheckout) return false;

  return ref
      .watch(featureFlagsProvider)
      .any((flag) => flag.key == pdfConvPayPalCheckoutFlagKey && flag.enabled);
});
