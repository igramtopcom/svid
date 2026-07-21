import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/config/brand_config.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/backend_client.dart';
import '../../domain/entities/checkout_session.dart';
import '../../domain/entities/license_device.dart';
import '../../domain/entities/license_info.dart';
import '../../domain/entities/payment_result.dart';
import '../../domain/entities/payment_status.dart';
import '../../domain/entities/payment_transaction.dart';
import '../../domain/entities/pricing_plan.dart';

/// Service for handling Stripe Checkout payment flow.
///
/// Flow:
/// 1. App calls backend → creates Stripe Checkout session
/// 2. Backend returns checkout URL
/// 3. App opens URL in browser (Stripe hosted page)
/// 4. User completes payment on Stripe
/// 5. Stripe redirects to success/cancel URL
/// 6. App polls backend for payment result + license key
///
/// Security: NO card data ever touches the Flutter app.
class StripePaymentService {
  final BackendClient _client;
  final Uuid _uuid;

  /// Injectable for testing. Production uses real [BackendClient].
  StripePaymentService(this._client, [Uuid? uuid]) : _uuid = uuid ?? const Uuid();

  /// Create a Stripe Checkout session and return the checkout URL.
  ///
  /// [billingCycle] specifies 'monthly' or 'yearly' subscription.
  /// [idempotencyKey] prevents duplicate charges on retry.
  /// Returns [CheckoutSession] with URL to open in browser.
  Future<CheckoutSession> createCheckoutSession({
    required String billingCycle,
    String? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? _uuid.v4();
    appLogger.info(
      'Creating Stripe checkout session '
      '(cycle: $billingCycle, idempotency: $key)',
    );

    final session = await _client.post<CheckoutSession>(
      '/premium/stripe/checkout',
      data: {
        'billingCycle': billingCycle,
        'idempotencyKey': key,
      },
      fromJson: (json) =>
          CheckoutSession.fromJson(json as Map<String, dynamic>),
    );

    appLogger.info('Checkout session created: ${session.sessionId}');
    return session;
  }

  /// Open the Stripe Checkout page in the system browser.
  ///
  /// Returns `true` if the URL was successfully launched.
  /// Note: Skips `canLaunchUrl` — it has false negatives on Windows
  /// for https URLs (Flutter team recommendation).
  Future<bool> openCheckoutPage(String checkoutUrl) async {
    try {
      final uri = Uri.parse(checkoutUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    } catch (e) {
      appLogger.error('Failed to launch checkout URL: $checkoutUrl', e);
      return false;
    }
  }

  /// Verify payment status by polling the backend.
  ///
  /// Called after user returns from Stripe Checkout.
  /// Returns [PaymentResult] with license key on success.
  Future<PaymentResult> verifyPayment(String sessionId) async {
    appLogger.info('Verifying payment for session: $sessionId');

    final result = await _client.get<PaymentResult>(
      '/premium/stripe/verify',
      queryParameters: {'sessionId': sessionId},
      fromJson: (json) =>
          PaymentResult.fromJson(json as Map<String, dynamic>),
    );

    if (result.isSuccess) {
      appLogger.info('Payment verified! License: ${result.licenseKey != null ? "***" : "none"}');
    } else {
      appLogger.warning('Payment not completed: ${result.status}');
    }

    return result;
  }

  /// Poll for payment completion with exponential backoff.
  ///
  /// Polls every [initialDelay] seconds, doubling up to [maxDelay].
  /// Stops after [maxAttempts] or when status is no longer pending.
  Future<PaymentResult> pollPaymentStatus(
    String sessionId, {
    Duration initialDelay = const Duration(seconds: 2),
    Duration maxDelay = const Duration(seconds: 10),
    int maxAttempts = 30,
    bool Function()? isCancelled,
  }) async {
    var delay = initialDelay;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      await Future<void>.delayed(delay);

      if (isCancelled?.call() ?? false) {
        return PaymentResult(
          status: PaymentStatus.cancelled,
          sessionId: sessionId,
          paymentMethod: 'stripe',
          createdAt: DateTime.now(),
        );
      }

      final result = await verifyPayment(sessionId);

      if (!result.isPending) {
        return result;
      }

      // Exponential backoff
      delay = Duration(
        milliseconds: (delay.inMilliseconds * 1.5).toInt().clamp(
              initialDelay.inMilliseconds,
              maxDelay.inMilliseconds,
            ),
      );
    }

    // Timed out waiting for payment
    return PaymentResult(
      status: PaymentStatus.pending,
      sessionId: sessionId,
      paymentMethod: 'stripe',
      createdAt: DateTime.now(),
      errorMessage: 'Payment verification timed out',
    );
  }

  /// Fetch full license info from the Go backend.
  ///
  /// Returns server-authoritative data: real device count, max devices,
  /// billing cycle, expiry, and registered device list.
  Future<LicenseInfo> fetchLicenseInfo() async {
    return _client.get<LicenseInfo>(
      '/premium/license',
      fromJson: (json) => LicenseInfo.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Fetch all devices registered to the current license.
  Future<List<LicenseDevice>> fetchDevices() async {
    return _client.get<List<LicenseDevice>>(
      '/premium/devices',
      fromJson: (json) => LicenseDevice.listFromJson(json),
    );
  }

  /// Fetch billing transaction history for the current device.
  Future<List<PaymentTransaction>> fetchTransactions() async {
    return _client.get<List<PaymentTransaction>>(
      '/premium/transactions',
      fromJson: (json) {
        // Backend returns paginated: { items: [...], total, page, ... }
        final map = json as Map<String, dynamic>;
        final items = map['items'] as List? ?? [];
        return items
            .map((e) => PaymentTransaction.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }

  /// Remove a device from the current license.
  ///
  /// The backend prevents removing the requesting device (self-removal).
  Future<void> removeDevice(String deviceId) async {
    await _client.deleteVoid('/premium/devices/$deviceId');
    appLogger.info('Device removed from license: ${deviceId.substring(0, 8)}...');
  }

  /// Whether the backend has crypto payments enabled (BTCPay configured).
  /// Updated after each [fetchPricingPlans] call.
  bool _cryptoEnabled = false;
  bool get cryptoEnabled => _cryptoEnabled;

  /// Fetch public pricing plans from backend.
  ///
  /// Response format: `{ "plans": [...], "cryptoEnabled": bool }`
  /// Falls back to hardcoded prices if the backend is unreachable.
  Future<List<PricingPlan>> fetchPricingPlans() async {
    final brand = BrandConfig.current.brand.name;
    try {
      final plans = await _client.get<List<PricingPlan>>(
        '/premium/plans',
        queryParameters: {'brand': brand},
        fromJson: (json) {
          final map = json as Map<String, dynamic>;
          _cryptoEnabled = map['cryptoEnabled'] as bool? ?? false;
          final list = map['plans'] as List;
          return list
              .map((e) => PricingPlan.fromJson(e as Map<String, dynamic>))
              .toList();
        },
      );
      return plans;
    } catch (e) {
      appLogger.warning('Failed to fetch pricing plans: $e');
      _cryptoEnabled = false;
      return _fallbackPlans;
    }
  }

  /// Hardcoded fallback prices (used when backend is unreachable).
  static List<PricingPlan> get _fallbackPlans {
    if (BrandConfig.current.brand == Brand.vidcombo) {
      return const [
        PricingPlan(billingCycle: 'monthly', amountCents: 699, currency: 'usd', interval: 'month', maxDevices: 5, isLifetime: false),
        PricingPlan(billingCycle: 'semiannual', amountCents: 2934, currency: 'usd', interval: 'six_months', maxDevices: 5, isLifetime: false),
        PricingPlan(billingCycle: 'yearly', amountCents: 4188, currency: 'usd', interval: 'year', maxDevices: 10, isLifetime: false),
      ];
    }
    return const [
      PricingPlan(billingCycle: 'monthly', amountCents: 799, currency: 'usd', interval: 'month', maxDevices: 5, isLifetime: false),
      PricingPlan(billingCycle: 'yearly', amountCents: 2999, currency: 'usd', interval: 'year', maxDevices: 10, isLifetime: false),
      PricingPlan(billingCycle: 'lifetime1', amountCents: 4999, currency: 'usd', interval: 'one_time', maxDevices: 1, isLifetime: true),
      PricingPlan(billingCycle: 'lifetime2', amountCents: 7999, currency: 'usd', interval: 'one_time', maxDevices: 3, isLifetime: true),
      PricingPlan(billingCycle: 'lifetime3', amountCents: 9900, currency: 'usd', interval: 'one_time', maxDevices: 10, isLifetime: true),
    ];
  }

  /// Open the Stripe Billing Portal in the system browser.
  ///
  /// The portal allows users to change plans, update payment methods,
  /// view invoices, and manage their subscription — all hosted by Stripe.
  /// Returns `true` if the portal was opened successfully.
  /// Returns `false` if the license has no Stripe customer (crypto/manual/PHP).
  Future<bool> openCustomerPortal() async {
    try {
      final result = await _client.post<Map<String, dynamic>>(
        '/premium/stripe/portal',
        data: {},
        fromJson: (json) => json as Map<String, dynamic>,
      );
      final url = result['url'] as String?;
      if (url == null || url.isEmpty) {
        appLogger.warning('Portal session returned empty URL');
        return false;
      }
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      appLogger.info('Stripe Billing Portal opened');
      return true;
    } catch (e) {
      appLogger.warning('Failed to open Stripe portal: $e');
      return false;
    }
  }

  /// Cancel an active subscription.
  ///
  /// The subscription will remain active until the end of the current
  /// billing period, then will not renew.
  Future<bool> cancelSubscription(String licenseKey) async {
    appLogger.info('Cancelling subscription for license: ${licenseKey.substring(0, licenseKey.length.clamp(0, 10))}...');

    try {
      await _client.post<Map<String, dynamic>>(
        '/premium/stripe/cancel',
        data: {'licenseKey': licenseKey},
        fromJson: (json) => json as Map<String, dynamic>,
      );
      appLogger.info('Subscription cancellation successful');
      return true;
    } catch (e) {
      appLogger.error('Failed to cancel subscription: $e');
      return false;
    }
  }
}
