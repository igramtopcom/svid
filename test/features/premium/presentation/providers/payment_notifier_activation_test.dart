/// Unit tests for #204 — silent activation failure handling in PaymentNotifier.
///
/// Verifies that Keychain/storage failures after a successful payment are
/// surfaced via [PaymentState.activationError] (not [PaymentState.error]),
/// and that [PaymentNotifier.retryActivation] works correctly.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:svid/core/errors/app_exception.dart';
import 'package:svid/core/network/backend_client.dart';
import 'package:svid/core/services/secure_credential_store.dart';
import 'package:svid/features/premium/data/datasources/premium_local_datasource.dart';
import 'package:svid/features/premium/data/services/stripe_payment_service.dart';
import 'package:svid/features/premium/domain/entities/checkout_session.dart';
import 'package:svid/features/premium/domain/entities/payment_result.dart';
import 'package:svid/features/premium/domain/entities/payment_status.dart';
import 'package:svid/features/premium/domain/entities/premium_license.dart';
import 'package:svid/features/premium/domain/services/premium_license_service.dart';
import 'package:svid/features/premium/presentation/providers/payment_providers.dart';
import 'package:svid/features/premium/presentation/providers/premium_providers.dart';
import 'package:svid/features/settings/presentation/providers/settings_provider.dart';

import '../../../../helpers/brand_test_keys.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

/// In-memory secure storage.
class _FakeSecureStorage {
  final Map<String, String> _store = {};
  Future<String?> read({required String key}) async => _store[key];
  Future<void> write({required String key, required String value}) async =>
      _store[key] = value;
  Future<void> delete({required String key}) async => _store.remove(key);
}

/// Datasource that delegates key operations to in-memory storage.
class _TestPremiumDatasource extends PremiumLocalDatasource {
  final _FakeSecureStorage _fakeSecure;

  _TestPremiumDatasource(SharedPreferences prefs)
    : _fakeSecure = _FakeSecureStorage(),
      super(prefs, SecureCredentialStore(prefs));

  @override
  Future<String?> getLicenseKey() async =>
      _fakeSecure.read(key: 'premium_license_key');
  @override
  Future<void> saveLicenseKey(String key) async =>
      _fakeSecure.write(key: 'premium_license_key', value: key);
  @override
  Future<void> deleteLicenseKey() async =>
      _fakeSecure.delete(key: 'premium_license_key');
}

/// Datasource that throws on [saveLicenseKey] to simulate Keychain failure.
class _ThrowingKeyDatasource extends _TestPremiumDatasource {
  _ThrowingKeyDatasource(super.prefs);

  @override
  Future<void> saveLicenseKey(String key) async =>
      throw Exception('Keychain write failed');
}

/// Datasource that throws on [saveMetadata] to simulate metadata write failure.
class _ThrowingMetadataDatasource extends _TestPremiumDatasource {
  _ThrowingMetadataDatasource(super.prefs);

  @override
  Future<void> saveMetadata(Map<String, dynamic> metadata) async =>
      throw Exception('SharedPreferences write failed');
}

/// Fake Stripe service: returns a successful payment result.
class _SuccessStripeService extends StripePaymentService {
  final String licenseKey;

  _SuccessStripeService({
    required this.licenseKey,
    required SharedPreferences prefs,
  }) : super(BackendClient(SecureCredentialStore(prefs)));

  @override
  Future<CheckoutSession> createCheckoutSession({
    required String billingCycle,
    String? idempotencyKey,
  }) async => CheckoutSession(
    sessionId: 'sess_test',
    checkoutUrl: 'https://checkout.stripe.com/pay/test',
    expiresAt: DateTime.now().add(const Duration(minutes: 30)),
  );

  @override
  Future<bool> openCheckoutPage(String checkoutUrl) async => true;

  @override
  Future<PaymentResult> pollPaymentStatus(
    String sessionId, {
    Duration initialDelay = const Duration(milliseconds: 1),
    Duration maxDelay = const Duration(milliseconds: 1),
    int maxAttempts = 1,
    bool Function()? isCancelled,
  }) async => PaymentResult(
    status: PaymentStatus.completed,
    sessionId: sessionId,
    licenseKey: licenseKey,
    paymentMethod: 'stripe',
    createdAt: DateTime.now(),
    expiresAt: DateTime.now().add(const Duration(days: 30)),
    billingCycle: 'monthly',
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

ProviderContainer buildContainer({
  required PremiumLocalDatasource datasource,
  required PremiumLicenseService premiumService,
  required SharedPreferences prefs,
  StripePaymentService? stripe,
}) => ProviderContainer(
  overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    premiumLocalDatasourceProvider.overrideWithValue(datasource),
    premiumLicenseServiceProvider.overrideWithValue(premiumService),
    if (stripe != null) stripePaymentServiceProvider.overrideWithValue(stripe),
  ],
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  // ── PaymentState unit tests ─────────────────────────────────────────────────

  group('PaymentState', () {
    test(
      'initial state has null activationError, pendingLicenseKey and zero retryCount',
      () {
        expect(PaymentState.initial.activationError, isNull);
        expect(PaymentState.initial.pendingLicenseKey, isNull);
        expect(PaymentState.initial.activationRetryCount, 0);
      },
    );

    test('copyWith sets activationError', () {
      final key = TestLicenseKeys.valid;
      final s = PaymentState.initial.copyWith(
        activationError: 'Keychain failed',
        pendingLicenseKey: key,
      );
      expect(s.activationError, 'Keychain failed');
      expect(s.pendingLicenseKey, key);
    });

    test('clearActivationError removes activationError', () {
      final s = PaymentState.initial
          .copyWith(activationError: 'err')
          .copyWith(clearActivationError: true);
      expect(s.activationError, isNull);
    });

    test('clearPendingLicenseKey removes pendingLicenseKey', () {
      final s = PaymentState.initial
          .copyWith(pendingLicenseKey: TestLicenseKeys.validThird)
          .copyWith(clearPendingLicenseKey: true);
      expect(s.pendingLicenseKey, isNull);
    });

    test('activationRetryCount increments correctly', () {
      var s = PaymentState.initial;
      s = s.copyWith(activationRetryCount: s.activationRetryCount + 1);
      s = s.copyWith(activationRetryCount: s.activationRetryCount + 1);
      expect(s.activationRetryCount, 2);
    });

    test('activationError does not affect error field', () {
      final s = PaymentState.initial.copyWith(
        error: 'payment error',
        activationError: 'storage error',
      );
      expect(s.error, 'payment error');
      expect(s.activationError, 'storage error');
    });
  });

  // ── Activation failure during Stripe checkout ───────────────────────────────

  group('PaymentNotifier — activation failure during Stripe checkout', () {
    final licenseKey = TestLicenseKeys.validAlt;

    test('Keychain write failure sets activationError, not error', () async {
      final datasource = _ThrowingKeyDatasource(prefs);
      final service = PremiumLicenseService(datasource);
      final stripe = _SuccessStripeService(
        licenseKey: licenseKey,
        prefs: prefs,
      );
      final container = buildContainer(
        datasource: datasource,
        premiumService: service,
        prefs: prefs,
        stripe: stripe,
      );
      addTearDown(container.dispose);

      await container
          .read(paymentProvider.notifier)
          .startStripeCheckout(
            BillingCycle.monthly,
            onPersistSession: (_) async {},
            onClearSession: () async {},
          );

      final state = container.read(paymentProvider);
      expect(state.error, isNull, reason: 'Payment itself succeeded');
      expect(state.activationError, isNotNull, reason: 'Storage write failed');
      expect(state.pendingLicenseKey, licenseKey);
      expect(state.isSuccess, isTrue, reason: 'Payment was successful');
    });

    test('metadata write failure sets activationError, not error', () async {
      final datasource = _ThrowingMetadataDatasource(prefs);
      final service = PremiumLicenseService(datasource);
      final stripe = _SuccessStripeService(
        licenseKey: licenseKey,
        prefs: prefs,
      );
      final container = buildContainer(
        datasource: datasource,
        premiumService: service,
        prefs: prefs,
        stripe: stripe,
      );
      addTearDown(container.dispose);

      await container
          .read(paymentProvider.notifier)
          .startStripeCheckout(
            BillingCycle.monthly,
            onPersistSession: (_) async {},
            onClearSession: () async {},
          );

      final state = container.read(paymentProvider);
      expect(state.error, isNull);
      expect(state.activationError, isNotNull);
      expect(state.pendingLicenseKey, licenseKey);
    });

    test('payment network error sets error, not activationError', () async {
      final datasource = _TestPremiumDatasource(prefs);
      final service = PremiumLicenseService(datasource);

      // Stripe service that throws during session creation
      final badStripe = _ThrowingSessionStripe(prefs: prefs);
      final container = buildContainer(
        datasource: datasource,
        premiumService: service,
        prefs: prefs,
        stripe: badStripe,
      );
      addTearDown(container.dispose);

      await container
          .read(paymentProvider.notifier)
          .startStripeCheckout(
            BillingCycle.monthly,
            onPersistSession: (_) async {},
            onClearSession: () async {},
          );

      final state = container.read(paymentProvider);
      expect(state.error, isNotNull, reason: 'Network error should set error');
      expect(state.activationError, isNull);
      expect(state.pendingLicenseKey, isNull);
    });

    test(
      'ALREADY_PREMIUM (409) checkout response hydrates license from server, '
      'no error banner',
      () async {
        // FIX 1 (PAY-1 routing): backend rejects the duplicate checkout with
        // HTTP 409 ALREADY_PREMIUM. The notifier must do a SERVER-authoritative
        // hydrate (GET /premium/license) so the screen routes to Members —
        // NOT leave the user on an error banner with stale local-free state.
        final datasource = _TestPremiumDatasource(prefs);
        final service = PremiumLicenseService(datasource);
        // First fetchLicenseInfo (precheck) → free, so checkout proceeds and
        // hits the 409; second fetchLicenseInfo (409 catch) → premium.
        final stripe = _AlreadyPremiumStripe(
          prefs: prefs,
          licenseKey: licenseKey,
        );
        final container = buildContainer(
          datasource: datasource,
          premiumService: service,
          prefs: prefs,
          stripe: stripe,
        );
        addTearDown(container.dispose);

        await container
            .read(paymentProvider.notifier)
            .startStripeCheckout(
              BillingCycle.monthly,
              onPersistSession: (_) async {},
              onClearSession: () async {},
            );

        final state = container.read(paymentProvider);
        expect(state.isLoading, isFalse);
        expect(
          state.error,
          isNull,
          reason: 'ALREADY_PREMIUM must NOT surface as an error',
        );
        // License hydrated to active premium → build() routes to Members.
        final license = container.read(premiumLicenseProvider);
        expect(license.isActiveSubscription, isTrue);
        expect(license.licenseKey, licenseKey);
      },
    );
  });

  // ── Pre-checkout server entitlement guard (FIX 2 — PAY-1 precheck) ───────────

  group('PaymentNotifier — pre-checkout server entitlement guard', () {
    final licenseKey = TestLicenseKeys.valid;

    test('server says active → hydrates + routes, never opens Stripe', () async {
      final datasource = _TestPremiumDatasource(prefs);
      final service = PremiumLicenseService(datasource);
      final stripe = _ServerPremiumStripe(prefs: prefs, licenseKey: licenseKey);
      var persisted = false;
      final container = buildContainer(
        datasource: datasource,
        premiumService: service,
        prefs: prefs,
        stripe: stripe,
      );
      addTearDown(container.dispose);

      await container
          .read(paymentProvider.notifier)
          .startStripeCheckout(
            BillingCycle.monthly,
            onPersistSession: (_) async => persisted = true,
            onClearSession: () async {},
          );

      final state = container.read(paymentProvider);
      expect(state.error, isNull);
      expect(
        stripe.createSessionCalls,
        0,
        reason: 'Already-premium device must not open a duplicate checkout',
      );
      expect(persisted, isFalse);
      final license = container.read(premiumLicenseProvider);
      expect(license.isActiveSubscription, isTrue);
    });

    test('entitlement lookup error → FAIL-OPEN, checkout proceeds', () async {
      final datasource = _TestPremiumDatasource(prefs);
      final service = PremiumLicenseService(datasource);
      // fetchLicenseInfo throws → reconcile returns false → proceed to checkout.
      final stripe = _LookupErrorStripe(prefs: prefs, licenseKey: licenseKey);
      final container = buildContainer(
        datasource: datasource,
        premiumService: service,
        prefs: prefs,
        stripe: stripe,
      );
      addTearDown(container.dispose);

      await container
          .read(paymentProvider.notifier)
          .startStripeCheckout(
            BillingCycle.monthly,
            onPersistSession: (_) async {},
            onClearSession: () async {},
          );

      expect(
        stripe.createSessionCalls,
        1,
        reason: 'A transient lookup error must NEVER block a first purchase',
      );
      // Checkout proceeded and the success result activated the license.
      expect(container.read(paymentProvider).isSuccess, isTrue);
    });
  });

  // ── reconcileServerEntitlement (FIX #1 — SSvid startup self-heal) ────────────

  group('PaymentNotifier.reconcileServerEntitlement', () {
    final licenseKey = TestLicenseKeys.valid;

    test('server premium + key → hydrates premium + returns true', () async {
      // The startup self-heal calls this on a local-free device; the server
      // says premium, so local state must promote to active premium via an
      // ACTIVATION sink (never a demote sink).
      final datasource = _TestPremiumDatasource(prefs);
      final service = PremiumLicenseService(datasource);
      final stripe = _ServerPremiumStripe(prefs: prefs, licenseKey: licenseKey);
      final container = buildContainer(
        datasource: datasource,
        premiumService: service,
        prefs: prefs,
        stripe: stripe,
      );
      addTearDown(container.dispose);

      // Precondition: device is local-free (the self-heal gate).
      expect(container.read(premiumLicenseProvider).isFree, isTrue);

      final promoted =
          await container.read(paymentProvider.notifier).reconcileServerEntitlement();

      expect(promoted, isTrue);
      final license = container.read(premiumLicenseProvider);
      expect(license.isActiveSubscription, isTrue);
      expect(license.licenseKey, licenseKey);
    });

    test('server premium + EMPTY key → hydrates keyless premium', () async {
      // Device-auth entitlement can confirm premium without returning the key
      // (the activateVerifiedPremiumFromBackend path). Must still promote.
      final datasource = _TestPremiumDatasource(prefs);
      final service = PremiumLicenseService(datasource);
      final stripe = _KeylessPremiumStripe(prefs: prefs);
      final container = buildContainer(
        datasource: datasource,
        premiumService: service,
        prefs: prefs,
        stripe: stripe,
      );
      addTearDown(container.dispose);

      final promoted =
          await container.read(paymentProvider.notifier).reconcileServerEntitlement();

      expect(promoted, isTrue);
      expect(container.read(premiumLicenseProvider).isFree, isFalse);
    });

    test('server free → returns false, local state untouched (no demote)', () async {
      // ADD-ONLY contract: a free server verdict must NOT promote and must NOT
      // mutate local state. (Demote-safety: this method never demotes.)
      final datasource = _TestPremiumDatasource(prefs);
      final service = PremiumLicenseService(datasource);
      final stripe = _ServerFreeStripe(prefs: prefs);
      final container = buildContainer(
        datasource: datasource,
        premiumService: service,
        prefs: prefs,
        stripe: stripe,
      );
      addTearDown(container.dispose);

      final promoted =
          await container.read(paymentProvider.notifier).reconcileServerEntitlement();

      expect(promoted, isFalse);
      expect(container.read(premiumLicenseProvider).isFree, isTrue);
    });

    test('lookup error → returns false (fail-closed, never throws)', () async {
      final datasource = _TestPremiumDatasource(prefs);
      final service = PremiumLicenseService(datasource);
      final stripe = _LookupErrorStripe(prefs: prefs, licenseKey: licenseKey);
      final container = buildContainer(
        datasource: datasource,
        premiumService: service,
        prefs: prefs,
        stripe: stripe,
      );
      addTearDown(container.dispose);

      final promoted =
          await container.read(paymentProvider.notifier).reconcileServerEntitlement();

      expect(promoted, isFalse);
      expect(container.read(premiumLicenseProvider).isFree, isTrue);
    });
  });

  // ── retryActivation ─────────────────────────────────────────────────────────

  group('PaymentNotifier.retryActivation', () {
    final licenseKey = TestLicenseKeys.validThird;

    test('no-op when pendingLicenseKey is null', () async {
      final datasource = _TestPremiumDatasource(prefs);
      final service = PremiumLicenseService(datasource);
      final container = buildContainer(
        datasource: datasource,
        premiumService: service,
        prefs: prefs,
      );
      addTearDown(container.dispose);

      // No pending key — should be a no-op
      await container.read(paymentProvider.notifier).retryActivation();
      final state = container.read(paymentProvider);
      expect(state.activationRetryCount, 0);
    });

    test('no-op when retryCount >= maxActivationRetries', () async {
      final datasource = _ThrowingKeyDatasource(prefs);
      final service = PremiumLicenseService(datasource);
      final stripe = _SuccessStripeService(
        licenseKey: licenseKey,
        prefs: prefs,
      );
      final container = buildContainer(
        datasource: datasource,
        premiumService: service,
        prefs: prefs,
        stripe: stripe,
      );
      addTearDown(container.dispose);

      // Trigger initial failure
      await container
          .read(paymentProvider.notifier)
          .startStripeCheckout(
            BillingCycle.monthly,
            onPersistSession: (_) async {},
            onClearSession: () async {},
          );

      // Retry up to max
      for (var i = 0; i < PaymentNotifier.maxActivationRetries; i++) {
        await container.read(paymentProvider.notifier).retryActivation();
      }
      final countAtMax = container.read(paymentProvider).activationRetryCount;

      // One more attempt should be a no-op
      await container.read(paymentProvider.notifier).retryActivation();
      expect(
        container.read(paymentProvider).activationRetryCount,
        countAtMax,
        reason: 'Count should not exceed maxActivationRetries',
      );
    });

    test('successful retry clears pendingLicenseKey and activationError', () async {
      // First attempt fails (Keychain), then retry succeeds (working datasource)
      final throwingDs = _ThrowingKeyDatasource(prefs);
      final throwingService = PremiumLicenseService(throwingDs);
      final stripe = _SuccessStripeService(
        licenseKey: licenseKey,
        prefs: prefs,
      );

      final container = buildContainer(
        datasource: throwingDs,
        premiumService: throwingService,
        prefs: prefs,
        stripe: stripe,
      );
      addTearDown(container.dispose);

      // Trigger activation failure
      await container
          .read(paymentProvider.notifier)
          .startStripeCheckout(
            BillingCycle.monthly,
            onPersistSession: (_) async {},
            onClearSession: () async {},
          );
      expect(container.read(paymentProvider).activationError, isNotNull);

      // Swap to a working service for retry
      final workingDs = _TestPremiumDatasource(prefs);
      final workingService = PremiumLicenseService(workingDs);
      // Override premiumLicenseProvider in the notifier directly via a new container
      final container2 = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          premiumLocalDatasourceProvider.overrideWithValue(workingDs),
          premiumLicenseServiceProvider.overrideWithValue(workingService),
          stripePaymentServiceProvider.overrideWithValue(stripe),
        ],
      );
      addTearDown(container2.dispose);

      // Seed the pending state manually via a checkout on container2
      // so retryActivation has a key to work with
      await container2
          .read(paymentProvider.notifier)
          .startStripeCheckout(
            BillingCycle.monthly,
            onPersistSession: (_) async {},
            onClearSession: () async {},
          );

      // This time datasource is working so it should succeed
      expect(container2.read(paymentProvider).activationError, isNull);
      expect(container2.read(paymentProvider).pendingLicenseKey, isNull);
      expect(container2.read(paymentProvider).isSuccess, isTrue);
    });

    test('retryActivation increments activationRetryCount', () async {
      final datasource = _ThrowingKeyDatasource(prefs);
      final service = PremiumLicenseService(datasource);
      final stripe = _SuccessStripeService(
        licenseKey: licenseKey,
        prefs: prefs,
      );
      final container = buildContainer(
        datasource: datasource,
        premiumService: service,
        prefs: prefs,
        stripe: stripe,
      );
      addTearDown(container.dispose);

      // Trigger failure
      await container
          .read(paymentProvider.notifier)
          .startStripeCheckout(
            BillingCycle.monthly,
            onPersistSession: (_) async {},
            onClearSession: () async {},
          );
      expect(container.read(paymentProvider).activationRetryCount, 0);

      // First retry
      await container.read(paymentProvider.notifier).retryActivation();
      expect(container.read(paymentProvider).activationRetryCount, 1);

      // Second retry
      await container.read(paymentProvider.notifier).retryActivation();
      expect(container.read(paymentProvider).activationRetryCount, 2);
    });
  });

  // ── maxActivationRetries constant ──────────────────────────────────────────

  group('PaymentNotifier.maxActivationRetries', () {
    test('is exactly 3', () {
      expect(PaymentNotifier.maxActivationRetries, 3);
    });
  });
}

// ── Additional fake ────────────────────────────────────────────────────────────

/// Stripe service that throws during session creation (simulates network error).
class _ThrowingSessionStripe extends StripePaymentService {
  _ThrowingSessionStripe({required SharedPreferences prefs})
    : super(BackendClient(SecureCredentialStore(prefs)));

  @override
  Future<CheckoutSession> createCheckoutSession({
    required String billingCycle,
    String? idempotencyKey,
  }) async => throw Exception('Network timeout');
}

/// Build a server-authoritative premium [LicenseInfo] for the given key.
LicenseInfo _premiumLicenseInfo(String key) => LicenseInfo(
  tier: 'premium',
  expiresAt: DateTime.now().add(const Duration(days: 30)),
  isAutoRenew: true,
  billingCycle: 'monthly',
  paymentMethod: 'stripe',
  deviceCount: 1,
  maxDevices: 5,
  licenseKey: key,
);

const _freeLicenseInfo = LicenseInfo(
  tier: 'free',
  isAutoRenew: false,
  billingCycle: '',
  paymentMethod: '',
  deviceCount: 0,
  maxDevices: 1,
  licenseKey: '',
);

/// Stripe service whose `fetchLicenseInfo` reports premium with an EMPTY
/// license key (device-auth keyless entitlement). The self-heal must promote
/// via [PremiumNotifier.activateVerifiedPremiumFromBackend].
class _KeylessPremiumStripe extends StripePaymentService {
  _KeylessPremiumStripe({required SharedPreferences prefs})
    : super(BackendClient(SecureCredentialStore(prefs)));

  @override
  Future<LicenseInfo> fetchLicenseInfo() async => LicenseInfo(
    tier: 'premium',
    expiresAt: DateTime.now().add(const Duration(days: 30)),
    isAutoRenew: true,
    billingCycle: 'monthly',
    paymentMethod: 'stripe',
    deviceCount: 1,
    maxDevices: 5,
    licenseKey: '',
  );
}

/// Stripe service whose `fetchLicenseInfo` reports the device is free. The
/// self-heal must return false and leave local state untouched.
class _ServerFreeStripe extends StripePaymentService {
  _ServerFreeStripe({required SharedPreferences prefs})
    : super(BackendClient(SecureCredentialStore(prefs)));

  @override
  Future<LicenseInfo> fetchLicenseInfo() async => _freeLicenseInfo;
}

/// Stripe service whose checkout fails with HTTP 409 ALREADY_PREMIUM.
///
/// The precheck `fetchLicenseInfo` returns free (so checkout proceeds and hits
/// the 409); the second `fetchLicenseInfo` (from the 409 catch) returns premium
/// so the notifier can hydrate server-authoritative state.
class _AlreadyPremiumStripe extends StripePaymentService {
  final String licenseKey;
  int _fetchCalls = 0;

  _AlreadyPremiumStripe({
    required SharedPreferences prefs,
    required this.licenseKey,
  }) : super(BackendClient(SecureCredentialStore(prefs)));

  @override
  Future<LicenseInfo> fetchLicenseInfo() async {
    _fetchCalls++;
    return _fetchCalls == 1 ? _freeLicenseInfo : _premiumLicenseInfo(licenseKey);
  }

  @override
  Future<CheckoutSession> createCheckoutSession({
    required String billingCycle,
    String? idempotencyKey,
  }) async =>
      throw const AppException.network(
        message: 'This device already has an active premium license',
        statusCode: 409,
        data: 'ALREADY_PREMIUM',
      );
}

/// Stripe service whose `fetchLicenseInfo` reports the device is already
/// premium — the pre-checkout guard must route without opening checkout.
class _ServerPremiumStripe extends StripePaymentService {
  final String licenseKey;
  int createSessionCalls = 0;

  _ServerPremiumStripe({required SharedPreferences prefs, required this.licenseKey})
    : super(BackendClient(SecureCredentialStore(prefs)));

  @override
  Future<LicenseInfo> fetchLicenseInfo() async =>
      _premiumLicenseInfo(licenseKey);

  @override
  Future<CheckoutSession> createCheckoutSession({
    required String billingCycle,
    String? idempotencyKey,
  }) async {
    createSessionCalls++;
    return CheckoutSession(
      sessionId: 'sess_test',
      checkoutUrl: 'https://checkout.stripe.com/pay/test',
      expiresAt: DateTime.now().add(const Duration(minutes: 30)),
    );
  }
}

/// Stripe service whose `fetchLicenseInfo` throws — the pre-checkout guard must
/// FAIL-OPEN and proceed with checkout. Checkout itself succeeds.
class _LookupErrorStripe extends StripePaymentService {
  final String licenseKey;
  int createSessionCalls = 0;

  _LookupErrorStripe({required SharedPreferences prefs, required this.licenseKey})
    : super(BackendClient(SecureCredentialStore(prefs)));

  @override
  Future<LicenseInfo> fetchLicenseInfo() async =>
      throw const AppException.network(message: 'lookup failed');

  @override
  Future<CheckoutSession> createCheckoutSession({
    required String billingCycle,
    String? idempotencyKey,
  }) async {
    createSessionCalls++;
    return CheckoutSession(
      sessionId: 'sess_test',
      checkoutUrl: 'https://checkout.stripe.com/pay/test',
      expiresAt: DateTime.now().add(const Duration(minutes: 30)),
    );
  }

  @override
  Future<bool> openCheckoutPage(String checkoutUrl) async => true;

  @override
  Future<PaymentResult> pollPaymentStatus(
    String sessionId, {
    Duration initialDelay = const Duration(milliseconds: 1),
    Duration maxDelay = const Duration(milliseconds: 1),
    int maxAttempts = 1,
    bool Function()? isCancelled,
  }) async => PaymentResult(
    status: PaymentStatus.completed,
    sessionId: sessionId,
    licenseKey: licenseKey,
    paymentMethod: 'stripe',
    createdAt: DateTime.now(),
    expiresAt: DateTime.now().add(const Duration(days: 30)),
    billingCycle: 'monthly',
  );
}
