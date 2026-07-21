import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/brand_config.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/providers/backend_providers.dart';
import '../../../../core/services/analytics_service.dart';
import '../../data/services/crypto_payment_service.dart';
import '../../data/services/stripe_payment_service.dart';
import '../../domain/entities/checkout_session.dart';
import '../../domain/entities/crypto_currency.dart';
import '../../domain/entities/crypto_invoice.dart';
import '../../domain/entities/license_device.dart';
import '../../domain/entities/license_info.dart';
import '../../domain/entities/payment_result.dart';
import '../../domain/entities/payment_transaction.dart';
import '../../domain/entities/premium_feature.dart';
import '../../domain/entities/premium_license.dart';
import '../../domain/entities/pricing_plan.dart';
import '../../domain/services/premium_license_service.dart';
import 'premium_providers.dart';

export '../../domain/entities/license_device.dart';
export '../../domain/entities/license_info.dart';
export '../../domain/entities/pricing_plan.dart';

/// Whether a license key was created by the Go backend (brand-prefixed format)
/// vs the PHP backend (32-char hex). Svid `SVID-` (44), VidCombo
/// `VIDCOMBO-` (48).
bool _isGoBackendKey(String key) {
  if (key.startsWith('SVID-') && key.length == 44) return true;
  if (key.startsWith('VIDCOMBO-') && key.length == 48) return true;
  return false;
}

/// Stripe payment service provider
final stripePaymentServiceProvider = Provider<StripePaymentService>((ref) {
  final client = ref.watch(backendClientProvider);
  return StripePaymentService(client);
});

/// Crypto payment service provider
final cryptoPaymentServiceProvider = Provider<CryptoPaymentService>((ref) {
  final client = ref.watch(backendClientProvider);
  return CryptoPaymentService(client);
});

/// Selected billing cycle for checkout
final selectedBillingCycleProvider = StateProvider<BillingCycle>(
  (ref) =>
      BrandConfig.current.brand == Brand.vidcombo
          ? BillingCycle.p30
          : BillingCycle.monthly,
);

/// Pricing plans fetched from backend (with fallback)
final pricingPlansProvider = FutureProvider<List<PricingPlan>>((ref) {
  final service = ref.watch(stripePaymentServiceProvider);
  return service.fetchPricingPlans();
});

/// Server-authoritative license info (device count, max devices, billing details).
///
/// Returns `null` for VidCombo users with PHP-created licenses (no Go backend record).
/// Auto-disposes when the members screen is left.
final licenseInfoProvider = FutureProvider.autoDispose<LicenseInfo?>((
  ref,
) async {
  // Only fetch from Go backend — PHP VidCombo licenses don't have this endpoint
  final license = ref.watch(premiumLicenseProvider);
  if (license.isFree) return null;

  // VidCombo PHP licenses: skip unless it's a Go-created key
  if (BrandConfig.current.backendType == BackendType.php) {
    final key = license.licenseKey;
    if (key == null || !_isGoBackendKey(key)) {
      return null;
    }
  }

  final service = ref.watch(stripePaymentServiceProvider);
  try {
    return await service.fetchLicenseInfo();
  } catch (_) {
    return null; // Offline / 404 — graceful fallback to local data
  }
});

/// Devices registered to the current license (fetched from Go backend).
///
/// Returns empty list on error or for PHP-only licenses.
final devicesProvider = FutureProvider.autoDispose<List<LicenseDevice>>((
  ref,
) async {
  final license = ref.watch(premiumLicenseProvider);
  if (license.isFree) return [];

  if (BrandConfig.current.backendType == BackendType.php) {
    final key = license.licenseKey;
    if (key == null || !_isGoBackendKey(key)) {
      return [];
    }
  }

  final service = ref.watch(stripePaymentServiceProvider);
  try {
    return await service.fetchDevices();
  } catch (_) {
    return [];
  }
});

/// Billing transaction history (fetched from Go backend).
///
/// Returns empty list on error or for PHP-only licenses.
final transactionsProvider =
    FutureProvider.autoDispose<List<PaymentTransaction>>((ref) async {
      final license = ref.watch(premiumLicenseProvider);
      if (license.isFree) return [];

      if (BrandConfig.current.backendType == BackendType.php) {
        final key = license.licenseKey;
        if (key == null || !_isGoBackendKey(key)) {
          return [];
        }
      }

      final service = ref.watch(stripePaymentServiceProvider);
      try {
        return await service.fetchTransactions();
      } catch (_) {
        return [];
      }
    });

/// Whether the backend has crypto payments enabled (BTCPay configured).
/// Derived from the last [pricingPlansProvider] fetch — reads the flag
/// that [StripePaymentService.fetchPricingPlans] caches after parsing.
/// Crypto is disabled by default — only enabled when backend explicitly sets flag.
final cryptoEnabledProvider = Provider<bool>((ref) {
  // Ensure plans have been fetched first (triggers the API call).
  ref.watch(pricingPlansProvider);
  final service = ref.watch(stripePaymentServiceProvider);
  return service.cryptoEnabled;
});

/// Outcome of the post-payment activation step. Callers use this to
/// decide whether to clear the persisted `pending_payment_session`
/// recovery marker — clearing on failure leaves the user paid-but-stuck.
enum ActivationOutcome { success, failure }

/// State for the payment checkout flow
class PaymentState {
  final bool isLoading;
  final CheckoutSession? session;
  final CryptoInvoice? invoice;
  final PaymentResult? result;
  final String? error;

  /// Non-null when payment succeeded but license storage failed.
  /// Distinct from [error] (which covers payment failures) so the UI can
  /// show a targeted "Activation Failed — Retry" dialog.
  final String? activationError;

  /// License key pending activation (stored for retry without re-paying).
  final String? pendingLicenseKey;

  /// Number of activation retry attempts so far (resets on reset()).
  final int activationRetryCount;

  /// True when license activation completes successfully (triggers success dialog).
  final bool isActivationSuccess;

  const PaymentState({
    this.isLoading = false,
    this.session,
    this.invoice,
    this.result,
    this.error,
    this.activationError,
    this.pendingLicenseKey,
    this.activationRetryCount = 0,
    this.isActivationSuccess = false,
  });

  static const initial = PaymentState();

  bool get isSuccess => result?.isActivatable == true || isActivationSuccess;
  bool get isPending =>
      result?.isPending == true ||
      result?.isAwaitingLicense == true ||
      (isLoading && result == null);
  bool get isAwaitingLicense => result?.isAwaitingLicense == true;
  bool get isFailed => result?.isFailed == true || error != null;

  PaymentState copyWith({
    bool? isLoading,
    CheckoutSession? session,
    CryptoInvoice? invoice,
    PaymentResult? result,
    String? error,
    String? activationError,
    String? pendingLicenseKey,
    int? activationRetryCount,
    bool? isActivationSuccess,
    bool clearSession = false,
    bool clearInvoice = false,
    bool clearResult = false,
    bool clearError = false,
    bool clearActivationError = false,
    bool clearPendingLicenseKey = false,
  }) {
    return PaymentState(
      isLoading: isLoading ?? this.isLoading,
      session: clearSession ? null : (session ?? this.session),
      invoice: clearInvoice ? null : (invoice ?? this.invoice),
      result: clearResult ? null : (result ?? this.result),
      error: clearError ? null : (error ?? this.error),
      activationError:
          clearActivationError
              ? null
              : (activationError ?? this.activationError),
      pendingLicenseKey:
          clearPendingLicenseKey
              ? null
              : (pendingLicenseKey ?? this.pendingLicenseKey),
      activationRetryCount: activationRetryCount ?? this.activationRetryCount,
      isActivationSuccess: isActivationSuccess ?? this.isActivationSuccess,
    );
  }
}

/// Payment flow state notifier
class PaymentNotifier extends StateNotifier<PaymentState> {
  final StripePaymentService _stripeService;
  final CryptoPaymentService _cryptoService;
  final PremiumNotifier _premiumNotifier;
  final PremiumLicenseService _premiumLicenseService;
  final AnalyticsService _analytics;

  /// Maximum number of activation retries before showing "contact support".
  static const maxActivationRetries = 3;

  PaymentNotifier(
    this._stripeService,
    this._cryptoService,
    this._premiumNotifier,
    this._premiumLicenseService,
    this._analytics,
  ) : super(PaymentState.initial);

  bool _isAlreadyPremiumError(Object error) {
    if (error is! AppException) return false;
    return error.maybeWhen(
      network:
          (_, statusCode, data) =>
              statusCode == 409 && data == 'ALREADY_PREMIUM',
      orElse: () => false,
    );
  }

  String? _activatableLicenseKey(PaymentResult result) {
    final key = result.licenseKey;
    if (result.isActivatable && key != null && key.isNotEmpty) {
      return key;
    }
    return null;
  }

  bool _shouldKeepSessionMarker(PaymentResult result) {
    return result.isPending || result.isAwaitingLicense;
  }

  bool _localEntitlementActive() {
    return _premiumLicenseService.isFeatureAvailable(
      PremiumFeature.unlimitedDownloads,
      _premiumNotifier.state,
    );
  }

  /// Pull server-authoritative entitlement and hydrate local premium state.
  ///
  /// Used to reconcile a server-premium / local-free device (the PAY-1
  /// HTTP 409 ALREADY_PREMIUM case + the pre-checkout entitlement guard).
  ///
  /// This deliberately does NOT call [PremiumNotifier.refreshLicense]:
  /// `refreshLicense` is the premium-LOSS detector — it early-returns for free
  /// users and requires an already-stored key, so it cannot promote a keyless
  /// local-free device. The server-pulling path that actually hydrates a
  /// local-free user is `GET /premium/license` ([StripePaymentService.fetchLicenseInfo]),
  /// then an ACTIVATION sink (never a demote sink — demote-safety stays intact).
  ///
  /// Returns `true` when the server confirmed premium AND local state was
  /// hydrated to active premium.
  ///
  /// Public so the SSvid startup self-heal ([StartupService._initializeGo])
  /// can re-promote a server-premium / local-free device after a previous
  /// soft-demote (offline grace, transient backend hiccup) wiped the live
  /// premium flag but kept the device entitled server-side. The caller MUST
  /// gate on free so this never touches an already-premium user.
  Future<bool> reconcileServerEntitlement() async {
    try {
      final info = await _stripeService.fetchLicenseInfo();
      if (!info.isPremium) return false;

      final key = info.licenseKey;
      if (key.isNotEmpty) {
        await _premiumNotifier.activateLicenseFromBackend(
          key,
          billingCycle: info.billingCycle.isNotEmpty ? info.billingCycle : null,
          expiresAt: info.expiresAt,
        );
      } else {
        await _premiumNotifier.activateVerifiedPremiumFromBackend(
          billingCycle: info.billingCycle.isNotEmpty ? info.billingCycle : null,
          expiresAt: info.expiresAt,
        );
      }
      return _localEntitlementActive();
    } catch (_) {
      // Lookup/activation failure — caller decides how to proceed.
      return false;
    }
  }

  /// Activate a license key, catching storage failures separately from payment
  /// failures. On Keychain/storage error, sets [PaymentState.activationError]
  /// and [PaymentState.pendingLicenseKey] so the UI can prompt a targeted retry
  /// dialog WITHOUT requiring the user to re-pay.
  ///
  /// Returns the outcome so callers can gate side-effects (notably:
  /// `pending_payment_session` MUST only be cleared on success — clearing
  /// before/independent of activation creates a paid-but-no-license recovery
  /// hole. See memory:feedback_recovery_marker_ordering.
  Future<ActivationOutcome> _handleActivation(
    String licenseKey, {
    required String paymentMethod,
    String? transactionId,
    BillingCycle? billingCycle,
    DateTime? expiresAt,
  }) async {
    try {
      await _premiumNotifier.activateLicense(
        licenseKey,
        paymentMethod: paymentMethod,
        transactionId: transactionId,
        billingCycle: billingCycle,
        expiresAt: expiresAt,
      );
      if (!mounted) return ActivationOutcome.success;
      state = state.copyWith(isActivationSuccess: true);
      _analytics.track('premium_checkout_completed', {
        'payment_method': paymentMethod,
        if (billingCycle != null) 'billing_cycle': billingCycle.name,
      });
      return ActivationOutcome.success;
    } catch (e) {
      if (!mounted) return ActivationOutcome.failure;
      state = state.copyWith(
        activationError: e is AppException ? e.userMessage : e.toString(),
        pendingLicenseKey: licenseKey,
      );
      return ActivationOutcome.failure;
    }
  }

  /// Start Stripe checkout in system browser (primary flow for all brands).
  ///
  /// 1. Creates checkout session via backend
  /// 2. Persists session ID for crash recovery
  /// 3. Opens system browser with Stripe hosted page
  /// 4. Polls backend for payment completion (10 min timeout)
  /// 5. On success, activates license
  ///
  /// Option B re-check safety net (no deep link — the success page never
  /// hands a token back to the app):
  /// - In-app polling (Step 4 detects a completed payment in 3-15s)
  /// - In-session "I already paid" re-check via [checkPendingSession]
  /// - Startup recovery (re-checks the persisted session on the next launch)
  Future<void> startStripeCheckout(
    BillingCycle billingCycle, {
    required Future<void> Function(String sessionId) onPersistSession,
    required Future<void> Function() onClearSession,
  }) async {
    if (!BrandConfig.current.hasStripeCheckout) {
      state = state.copyWith(
        error:
            'Stripe checkout not available for ${BrandConfig.current.appName}',
      );
      return;
    }

    // Pre-checkout entitlement guard. If this device is already premium —
    // either locally or per the server — route to Members instead of opening
    // a duplicate Stripe checkout. The server fetch is FAIL-OPEN: any lookup
    // error proceeds with checkout so a genuine first purchase is never
    // blocked by a transient backend hiccup.
    if (_localEntitlementActive() || await reconcileServerEntitlement()) {
      if (!mounted) return;
      // No error banner: the screen watches premiumLicenseProvider and
      // rebuilds into PremiumMembersScreen now that local state is active.
      state = state.copyWith(isLoading: false, clearError: true);
      return;
    }
    if (!mounted) return;

    _checkoutCancelled = false;
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearResult: true,
      clearInvoice: true,
    );
    _analytics.track('premium_checkout_started', {
      'billing_cycle': billingCycle.name,
      'payment_method': 'stripe',
    });

    PaymentResult? result;
    try {
      // Step 1: Create checkout session
      final session = await _stripeService.createCheckoutSession(
        billingCycle: billingCycle.name,
      );
      if (!mounted) return;
      state = state.copyWith(session: session);

      // Step 2: Persist session ID BEFORE opening browser (crash recovery)
      await onPersistSession(session.sessionId);
      if (!mounted) return;

      // Step 3: Open system browser
      final launched = await _stripeService.openCheckoutPage(
        session.checkoutUrl,
      );
      if (!mounted) return;
      if (!launched) {
        await onClearSession();
        if (!mounted) return;
        state = state.copyWith(
          isLoading: false,
          error: 'Could not open payment page',
        );
        return;
      }

      // Step 4: Poll for payment completion (10 min = ~60 attempts with backoff)
      // This is the LONGEST async window in the entire app — 10 minutes —
      // and the most likely place a user-induced dispose (close window,
      // navigate away) can race the result. Guard before every state mutation.
      result = await _stripeService.pollPaymentStatus(
        session.sessionId,
        initialDelay: const Duration(seconds: 2),
        maxDelay: const Duration(seconds: 10),
        maxAttempts: 60,
        isCancelled: () => _checkoutCancelled,
      );
      if (!mounted) return;
      state = state.copyWith(result: result, isLoading: false);
    } catch (e) {
      if (!mounted) return;
      if (_isAlreadyPremiumError(e)) {
        // Backend rejected the duplicate checkout with HTTP 409
        // ALREADY_PREMIUM: this device is server-premium but local-free.
        // Hydrate from the SERVER (not local storage) so build()'s isActive
        // becomes true and routes to PremiumMembersScreen. The old
        // _premiumNotifier.refresh() only reloaded LOCAL storage, leaving the
        // user stranded on an error banner.
        await reconcileServerEntitlement();
        if (!mounted) return;
        // Routed to Members on success; clear loading + any banner regardless
        // (do NOT surface ALREADY_PREMIUM as an error).
        state = state.copyWith(isLoading: false, clearError: true);
        return;
      }
      state = state.copyWith(isLoading: false, error: e.toString());
      return;
    }

    // Step 5: Activate license FIRST, clear pending session ONLY on success.
    // Wrong order (clear → activate) creates a recovery hole: if activation
    // throws between clear and complete, next startup sees no marker, no
    // retry, user paid Stripe with nothing to show. See memory:
    // feedback_recovery_marker_ordering.
    final licenseKey = _activatableLicenseKey(result);
    if (licenseKey != null) {
      final outcome = await _handleActivation(
        licenseKey,
        paymentMethod: 'stripe',
        transactionId: result.transactionId,
        billingCycle: billingCycle,
        expiresAt: result.expiresAt,
      );
      if (outcome == ActivationOutcome.success) {
        await onClearSession();
      }
      // failure: pendingLicenseKey persisted in state + session marker kept
      // → user can retry via retryActivation OR next startup recovers via
      // _recoverPendingPayment.
    } else if (_shouldKeepSessionMarker(result)) {
      // Poll timed out (10 min) with status still pending — user may
      // complete payment in the Stripe-hosted page AFTER our timeout.
      // Also covers completed-without-license-key: payment likely succeeded
      // but backend has not linked/fetched the key yet, so keep retry state.
      // Keep the session marker so startup recovery on a later launch
      // can re-verify and activate. Clearing here would strand a
      // late-completing payer (paid + no license + no recovery).
    } else {
      // Payment expired / failed / unsuccessful — no license to activate,
      // clear the session marker so we don't infinite-recover a dead session.
      await onClearSession();
    }
  }

  /// Recover a pending payment session (called on app startup).
  ///
  /// Verifies the session with backend — if paid, activates license.
  /// If still pending or expired, clears the pending state.
  Future<void> recoverPendingSession(
    String sessionId, {
    required Future<void> Function() onClearSession,
  }) async {
    await checkPendingSession(sessionId, onClearSession: onClearSession);
  }

  /// Re-check a persisted Stripe checkout session without clearing the marker
  /// unless the session is definitively dead or activation has succeeded.
  Future<void> checkPendingSession(
    String sessionId, {
    required Future<void> Function() onClearSession,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final result = await _stripeService.verifyPayment(sessionId);
      state = state.copyWith(result: result, isLoading: false);

      final licenseKey = _activatableLicenseKey(result);
      if (licenseKey != null) {
        // Activate FIRST, clear marker ONLY on success — see
        // feedback_recovery_marker_ordering. Failure path keeps the
        // session marker so the next startup recovery attempt re-runs.
        final outcome = await _handleActivation(
          licenseKey,
          paymentMethod: 'stripe',
          transactionId: result.transactionId,
          expiresAt: result.expiresAt,
        );
        if (outcome == ActivationOutcome.success) {
          await onClearSession();
        }
      } else if (!_shouldKeepSessionMarker(result)) {
        // Expired or failed payment — no license to activate, clear marker.
        await onClearSession();
      }
      // If still pending or awaiting license, leave session persisted for the
      // next manual/startup check.
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Reopen the checkout page for an existing session.
  Future<bool> reopenCheckoutPage() async {
    final session = state.session;
    if (session == null) return false;
    return _stripeService.openCheckoutPage(session.checkoutUrl);
  }

  /// Start the crypto checkout flow.
  ///
  /// 1. Creates BTCPay invoice via backend with [billingCycle]
  /// 2. Returns invoice with address + QR (UI displays it)
  /// 3. Starts polling for blockchain confirmations
  /// 4. On confirmation, activates subscription license (separate error path)
  Future<void> startCryptoCheckout(
    CryptoCurrency currency,
    BillingCycle billingCycle,
  ) async {
    if (!BrandConfig.current.hasStripeCheckout) {
      state = state.copyWith(
        error: 'Payment not available for ${BrandConfig.current.appName}',
      );
      return;
    }

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearResult: true,
      clearSession: true,
    );

    PaymentResult? result;
    try {
      // Step 1: Create invoice
      final invoice = await _cryptoService.createInvoice(
        currency: currency,
        billingCycle: billingCycle.name,
      );
      state = state.copyWith(invoice: invoice, isLoading: false);

      // Step 2: Poll for confirmation (UI shows QR + address meanwhile)
      result = await _cryptoService.pollForConfirmation(invoice.invoiceId);
      state = state.copyWith(result: result);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return;
    }

    // Step 3: Activate license — separate error path from payment.
    final licenseKey = _activatableLicenseKey(result);
    if (licenseKey != null) {
      await _handleActivation(
        licenseKey,
        paymentMethod: 'crypto',
        transactionId: result.transactionId,
        billingCycle: billingCycle,
        expiresAt: result.expiresAt,
      );
    }
  }

  /// Check the status of an existing crypto invoice.
  Future<void> checkCryptoInvoice(String invoiceId) async {
    state = state.copyWith(isLoading: true, clearError: true);

    PaymentResult? result;
    try {
      result = await _cryptoService.checkInvoiceStatus(invoiceId);
      state = state.copyWith(result: result, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return;
    }

    final licenseKey = _activatableLicenseKey(result);
    if (licenseKey != null) {
      final cycle =
          result.billingCycle != null
              ? BillingCycle.fromString(result.billingCycle!)
              : BillingCycle.monthly;
      await _handleActivation(
        licenseKey,
        paymentMethod: 'crypto',
        transactionId: result.transactionId,
        billingCycle: cycle,
        expiresAt: result.expiresAt,
      );
    }
  }

  /// Retry activating a pending license key without re-paying.
  ///
  /// Increments [PaymentState.activationRetryCount]. After
  /// [maxActivationRetries] attempts, the UI should guide the user to
  /// contact support.
  Future<void> retryActivation() async {
    final key = state.pendingLicenseKey;
    if (key == null) return;
    if (state.activationRetryCount >= maxActivationRetries) return;

    state = state.copyWith(
      isLoading: true,
      clearActivationError: true,
      activationRetryCount: state.activationRetryCount + 1,
    );

    final result = state.result;
    // Infer payment method: crypto when invoice is present, else stripe.
    final paymentMethod = state.invoice != null ? 'crypto' : 'stripe';
    final billingCycleStr = result?.billingCycle;
    final billingCycle =
        billingCycleStr != null
            ? BillingCycle.fromString(billingCycleStr)
            : BillingCycle.monthly;

    try {
      await _premiumNotifier.activateLicense(
        key,
        paymentMethod: paymentMethod,
        transactionId: result?.transactionId,
        billingCycle: billingCycle,
        expiresAt: result?.expiresAt,
      );
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        isActivationSuccess: true,
        clearPendingLicenseKey: true,
        clearActivationError: true,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        activationError: e is AppException ? e.userMessage : e.toString(),
      );
    }
  }

  /// Cancel the active subscription.
  ///
  /// For Stripe-purchased subscriptions, cancels via Stripe API first.
  /// For non-Stripe keys (manual, deep link, crypto), cancels locally only.
  Future<bool> cancelSubscription(String licenseKey) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final license = _premiumNotifier.state;

      // Only hit Stripe API for Stripe-purchased subscriptions
      if (license.paymentMethod == 'stripe') {
        final success = await _stripeService.cancelSubscription(licenseKey);
        if (!mounted) return success;
        if (!success) {
          state = state.copyWith(isLoading: false);
          return false;
        }
      }

      // Cancel locally (marks as cancelled, stays active until expiry)
      await _premiumNotifier.cancelSubscription();
      if (!mounted) return true;
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  bool _checkoutCancelled = false;

  /// Cancel any in-flight checkout polling and reset payment state.
  void reset() {
    _checkoutCancelled = true;
    state = PaymentState.initial;
  }
}

/// Payment state provider
final paymentProvider = StateNotifierProvider<PaymentNotifier, PaymentState>((
  ref,
) {
  final stripeService = ref.watch(stripePaymentServiceProvider);
  final cryptoService = ref.watch(cryptoPaymentServiceProvider);
  final premiumNotifier = ref.watch(premiumLicenseProvider.notifier);
  final premiumLicenseService = ref.watch(premiumLicenseServiceProvider);
  final analytics = ref.watch(analyticsServiceProvider);
  return PaymentNotifier(
    stripeService,
    cryptoService,
    premiumNotifier,
    premiumLicenseService,
    analytics,
  );
});

/// Derived: is payment in progress?
final isPaymentInProgressProvider = Provider<bool>((ref) {
  return ref.watch(paymentProvider).isLoading;
});
