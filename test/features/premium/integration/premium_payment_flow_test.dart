/// Integration test: Free → Stripe Payment → Premium activated flow.
///
/// Tests the complete flow using fakes (no real network calls):
/// 1. User starts free (isPremiumProvider = false)
/// 2. PaymentNotifier.startStripeCheckout() runs the system browser flow
/// 3. On success, PremiumLicenseService activates the license
/// 4. isPremiumProvider becomes true
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ssvid/core/network/backend_client.dart';
import 'package:ssvid/core/services/secure_credential_store.dart';
import 'package:ssvid/features/premium/data/datasources/premium_local_datasource.dart';
import 'package:ssvid/features/premium/data/services/stripe_payment_service.dart';
import 'package:ssvid/features/premium/domain/entities/checkout_session.dart';
import 'package:ssvid/features/premium/domain/entities/payment_result.dart';
import 'package:ssvid/features/premium/domain/entities/payment_status.dart';
import 'package:ssvid/features/premium/domain/entities/premium_license.dart';
import 'package:ssvid/features/premium/domain/entities/premium_tier.dart';
import 'package:ssvid/features/premium/domain/services/premium_license_service.dart';
import 'package:ssvid/features/premium/presentation/providers/payment_providers.dart';
import 'package:ssvid/features/premium/presentation/providers/premium_providers.dart';
import 'package:ssvid/features/settings/presentation/providers/settings_provider.dart';

import '../../../helpers/brand_test_keys.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeSecureStorage {
  final Map<String, String> _store = {};
  Future<String?> read({required String key}) async => _store[key];
  Future<void> write({required String key, required String value}) async =>
      _store[key] = value;
  Future<void> delete({required String key}) async => _store.remove(key);
}

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

/// Fake Stripe service: returns controlled results, never touches the network.
class _FakeStripePaymentService extends StripePaymentService {
  final CheckoutSession? sessionToReturn;
  final PaymentResult? resultToReturn;
  final bool launchSuccess;
  String? lastBillingCycle;

  _FakeStripePaymentService({
    this.sessionToReturn,
    this.resultToReturn,
    this.launchSuccess = true,
    required SharedPreferences prefs,
  }) : super(BackendClient(SecureCredentialStore(prefs)));

  @override
  Future<CheckoutSession> createCheckoutSession({
    required String billingCycle,
    String? idempotencyKey,
  }) async {
    lastBillingCycle = billingCycle;
    if (sessionToReturn != null) return sessionToReturn!;
    throw Exception('No session configured in fake');
  }

  @override
  Future<bool> openCheckoutPage(String checkoutUrl) async => launchSuccess;

  @override
  Future<PaymentResult> pollPaymentStatus(
    String sessionId, {
    Duration initialDelay = const Duration(milliseconds: 1),
    Duration maxDelay = const Duration(milliseconds: 1),
    int maxAttempts = 1,
    bool Function()? isCancelled,
  }) async {
    if (resultToReturn != null) return resultToReturn!;
    return PaymentResult(
      status: PaymentStatus.failed,
      sessionId: sessionId,
      paymentMethod: 'stripe',
      createdAt: DateTime.now(),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

ProviderContainer buildContainer({
  required PremiumLocalDatasource datasource,
  required PremiumLicenseService premiumService,
  required SharedPreferences prefs,
  StripePaymentService? stripe,
}) {
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      premiumLocalDatasourceProvider.overrideWithValue(datasource),
      premiumLicenseServiceProvider.overrideWithValue(premiumService),
      if (stripe != null)
        stripePaymentServiceProvider.overrideWithValue(stripe),
    ],
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late _TestPremiumDatasource datasource;
  late PremiumLicenseService premiumService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    datasource = _TestPremiumDatasource(prefs);
    premiumService = PremiumLicenseService(datasource);
  });

  group('Premium Payment Flow Integration', () {
    test('new user starts as free tier', () async {
      final license = await premiumService.getLicense();
      expect(license.tier, PremiumTier.free);
      expect(license.isActiveSubscription, isFalse);
    });

    test('isPremiumProvider returns false for free user', () async {
      final container = buildContainer(
        datasource: datasource,
        premiumService: premiumService,
        prefs: prefs,
      );
      addTearDown(container.dispose);

      await Future<void>.delayed(Duration.zero);
      expect(container.read(isPremiumProvider), isFalse);
    });

    test('activateLicense transitions from free to premium', () async {
      final container = buildContainer(
        datasource: datasource,
        premiumService: premiumService,
        prefs: prefs,
      );
      addTearDown(container.dispose);

      await Future<void>.delayed(Duration.zero);
      expect(container.read(isPremiumProvider), isFalse);

      await container
          .read(premiumLicenseProvider.notifier)
          .activateLicense(TestLicenseKeys.valid);

      expect(container.read(isPremiumProvider), isTrue);
      expect(container.read(premiumLicenseProvider).tier, PremiumTier.premium);
    });

    test('successful Stripe checkout activates premium', () async {
      final licenseKey = TestLicenseKeys.validAlt;
      final futureExpiry = DateTime.now().add(const Duration(days: 30));

      final stripe = _FakeStripePaymentService(
        prefs: prefs,
        sessionToReturn: CheckoutSession(
          sessionId: 'sess_test_123',
          checkoutUrl: 'https://checkout.stripe.com/pay/test',
          expiresAt: DateTime.now().add(const Duration(minutes: 30)),
        ),
        resultToReturn: PaymentResult(
          status: PaymentStatus.completed,
          sessionId: 'sess_test_123',
          licenseKey: licenseKey,
          paymentMethod: 'stripe',
          createdAt: DateTime.now(),
          expiresAt: futureExpiry,
          billingCycle: 'monthly',
        ),
        launchSuccess: true,
      );

      final container = buildContainer(
        datasource: datasource,
        premiumService: premiumService,
        prefs: prefs,
        stripe: stripe,
      );
      addTearDown(container.dispose);

      await Future<void>.delayed(Duration.zero);
      expect(container.read(isPremiumProvider), isFalse);

      await container
          .read(paymentProvider.notifier)
          .startStripeCheckout(
              BillingCycle.monthly,
              onPersistSession: (_) async {},
              onClearSession: () async {},
            );

      final paymentState = container.read(paymentProvider);
      expect(paymentState.isSuccess, isTrue);
      expect(paymentState.error, isNull);

      expect(container.read(isPremiumProvider), isTrue);
      expect(
        container.read(premiumLicenseProvider).tier,
        PremiumTier.premium,
      );
      expect(stripe.lastBillingCycle, 'monthly');
    });

    test('yearly billing cycle passes through correctly', () async {
      final stripe = _FakeStripePaymentService(
        prefs: prefs,
        sessionToReturn: CheckoutSession(
          sessionId: 'sess_yearly',
          checkoutUrl: 'https://checkout.stripe.com/pay/yearly',
          expiresAt: DateTime.now().add(const Duration(minutes: 30)),
        ),
        resultToReturn: PaymentResult(
          status: PaymentStatus.completed,
          sessionId: 'sess_yearly',
          licenseKey: TestLicenseKeys.validThird,
          paymentMethod: 'stripe',
          createdAt: DateTime.now(),
          billingCycle: 'yearly',
        ),
        launchSuccess: true,
      );

      final container = buildContainer(
        datasource: datasource,
        premiumService: premiumService,
        prefs: prefs,
        stripe: stripe,
      );
      addTearDown(container.dispose);

      await container
          .read(paymentProvider.notifier)
          .startStripeCheckout(
              BillingCycle.yearly,
              onPersistSession: (_) async {},
              onClearSession: () async {},
            );

      expect(stripe.lastBillingCycle, 'yearly');
      expect(container.read(isPremiumProvider), isTrue);
    });

    test('failed payment keeps user on free tier', () async {
      final stripe = _FakeStripePaymentService(
        prefs: prefs,
        sessionToReturn: CheckoutSession(
          sessionId: 'sess_fail',
          checkoutUrl: 'https://checkout.stripe.com/pay/fail',
          expiresAt: DateTime.now().add(const Duration(minutes: 30)),
        ),
        resultToReturn: PaymentResult(
          status: PaymentStatus.failed,
          sessionId: 'sess_fail',
          paymentMethod: 'stripe',
          createdAt: DateTime.now(),
          errorMessage: 'Card declined',
        ),
        launchSuccess: true,
      );

      final container = buildContainer(
        datasource: datasource,
        premiumService: premiumService,
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

      final paymentState = container.read(paymentProvider);
      expect(paymentState.isSuccess, isFalse);
      expect(paymentState.isFailed, isTrue);
      expect(container.read(isPremiumProvider), isFalse);
    });

    test('cannot open checkout page → error state, still free', () async {
      final stripe = _FakeStripePaymentService(
        prefs: prefs,
        sessionToReturn: CheckoutSession(
          sessionId: 'sess_launch_fail',
          checkoutUrl: 'invalid_url',
          expiresAt: DateTime.now().add(const Duration(minutes: 30)),
        ),
        launchSuccess: false,
      );

      final container = buildContainer(
        datasource: datasource,
        premiumService: premiumService,
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
      expect(state.isSuccess, isFalse);
      expect(state.isLoading, isFalse);
      expect(container.read(isPremiumProvider), isFalse);
    });

    test('deactivating premium returns user to free tier', () async {
      final container = buildContainer(
        datasource: datasource,
        premiumService: premiumService,
        prefs: prefs,
      );
      addTearDown(container.dispose);

      // Activate through notifier so state updates immediately
      await container
          .read(premiumLicenseProvider.notifier)
          .activateLicense(TestLicenseKeys.valid);

      expect(container.read(isPremiumProvider), isTrue);

      await container.read(premiumLicenseProvider.notifier).deactivateLicense();

      expect(container.read(isPremiumProvider), isFalse);
      expect(container.read(premiumLicenseProvider).tier, PremiumTier.free);
    });

    test('license persists across container recreations', () async {
      {
        final c = buildContainer(
          datasource: datasource,
          premiumService: premiumService,
          prefs: prefs,
        );
        await c
            .read(premiumLicenseProvider.notifier)
            .activateLicense(TestLicenseKeys.valid);
        c.dispose();
      }

      // New service pointing to same datasource
      final service2 = PremiumLicenseService(datasource);
      final license = await service2.getLicense();
      expect(license.isActiveSubscription, isTrue);
    });

    test('invalid license key format rejected', () async {
      expect(
        PremiumLicenseService.isValidLicenseKey('INVALID-KEY'),
        isFalse,
      );
      // A brand-appropriate key from TestLicenseKeys must validate; this
      // exercises whichever license format the current brand defines.
      expect(
        PremiumLicenseService.isValidLicenseKey(TestLicenseKeys.valid),
        isTrue,
      );
    });
  });
}
