/// Contract tests for the post-payment marker-ordering refactor in
/// PaymentNotifier (9358cd73). Pins the four critical paths that the
/// helper-only test suite did not cover:
///
///   1. Activation success → `onClearSession` called.
///   2. Activation failure → `onClearSession` NOT called (recovery preserved).
///   3. Poll timeout (PaymentStatus.pending) → `onClearSession` NOT called
///      (late payer can still recover on next startup).
///   4. Expired/failed payment (not pending, not success) → `onClearSession`
///      called (no infinite recovery on a dead session).
///
/// See memory:feedback_recovery_marker_ordering.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

// ── In-memory datasource: never throws (success activation). ─────────────────

class _InMemoryDatasource extends PremiumLocalDatasource {
  final Map<String, String> _secure = {};
  _InMemoryDatasource(SharedPreferences prefs)
    : super(prefs, SecureCredentialStore(prefs));

  @override
  Future<String?> getLicenseKey() async => _secure['premium_license_key'];
  @override
  Future<void> saveLicenseKey(String key) async =>
      _secure['premium_license_key'] = key;
  @override
  Future<void> deleteLicenseKey() async =>
      _secure.remove('premium_license_key');
}

// ── Datasource that throws on saveLicenseKey (Keychain locked). ──────────────

class _ThrowingDatasource extends _InMemoryDatasource {
  _ThrowingDatasource(super.prefs);
  @override
  Future<void> saveLicenseKey(String key) async =>
      throw Exception('Keychain write failed');
}

// ── Fake Stripe service with configurable poll result. ───────────────────────

class _FakeStripeService extends StripePaymentService {
  final PaymentResult pollResult;
  _FakeStripeService({
    required this.pollResult,
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
  }) async => pollResult;

  @override
  Future<PaymentResult> verifyPayment(String sessionId) async => pollResult;
}

// ── Test harness ─────────────────────────────────────────────────────────────

class _SessionTracker {
  bool cleared = false;
  String? persisted;

  Future<void> onPersist(String sessionId) async {
    persisted = sessionId;
  }

  Future<void> onClear() async {
    cleared = true;
  }
}

Future<({_SessionTracker tracker, ProviderContainer container})>
_runStripeFlow({
  required SharedPreferences prefs,
  required PaymentResult pollResult,
  required bool activationThrows,
}) async {
  final datasource =
      activationThrows
          ? _ThrowingDatasource(prefs)
          : _InMemoryDatasource(prefs);
  final premiumService = PremiumLicenseService(datasource);
  final stripe = _FakeStripeService(pollResult: pollResult, prefs: prefs);
  final tracker = _SessionTracker();

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      premiumLocalDatasourceProvider.overrideWithValue(datasource),
      premiumLicenseServiceProvider.overrideWithValue(premiumService),
      stripePaymentServiceProvider.overrideWithValue(stripe),
    ],
  );

  await container
      .read(paymentProvider.notifier)
      .startStripeCheckout(
        BillingCycle.monthly,
        onPersistSession: tracker.onPersist,
        onClearSession: tracker.onClear,
      );

  return (tracker: tracker, container: container);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('Stripe marker ordering — Codex review follow-up', () {
    test('1) activation SUCCESS clears the pending session marker', () async {
      final r = await _runStripeFlow(
        prefs: prefs,
        pollResult: PaymentResult(
          status: PaymentStatus.completed,
          sessionId: 'sess_test',
          licenseKey: 'SVID-1234-5678-9abc-def0-1234-5678-9abc-def0',
          paymentMethod: 'stripe',
          createdAt: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(days: 30)),
          billingCycle: 'monthly',
        ),
        activationThrows: false,
      );

      expect(
        r.tracker.cleared,
        isTrue,
        reason:
            'Successful activation must clear the recovery marker so the next '
            'startup does not infinite-recover an already-activated session.',
      );
      addTearDown(r.container.dispose);
    });

    test(
      '2) activation FAILURE keeps the pending session marker (recovery preserved)',
      () async {
        final r = await _runStripeFlow(
          prefs: prefs,
          pollResult: PaymentResult(
            status: PaymentStatus.completed,
            sessionId: 'sess_test',
            licenseKey: 'SVID-1234-5678-9abc-def0-1234-5678-9abc-def0',
            paymentMethod: 'stripe',
            createdAt: DateTime.now(),
            expiresAt: DateTime.now().add(const Duration(days: 30)),
            billingCycle: 'monthly',
          ),
          activationThrows: true,
        );

        expect(
          r.tracker.cleared,
          isFalse,
          reason:
              'Activation throw (e.g. Keychain locked) must leave the marker '
              'in place so _recoverPendingPayment can retry on next startup. '
              'Clearing it here strands a paid user with no license + no recovery.',
        );
        // pendingLicenseKey state must also be set for retryActivation.
        final state = r.container.read(paymentProvider);
        expect(state.activationError, isNotNull);
        expect(state.pendingLicenseKey, isNotNull);
        addTearDown(r.container.dispose);
      },
    );

    test(
      '3) poll TIMEOUT (PaymentStatus.pending) keeps the marker — late payer recovery',
      () async {
        final r = await _runStripeFlow(
          prefs: prefs,
          pollResult: PaymentResult(
            status: PaymentStatus.pending,
            sessionId: 'sess_test',
            paymentMethod: 'stripe',
            createdAt: DateTime.now(),
            errorMessage: 'Payment verification timed out',
          ),
          activationThrows: false,
        );

        expect(
          r.tracker.cleared,
          isFalse,
          reason:
              'Poll timeout returns PaymentStatus.pending. User may complete '
              'payment in the Stripe-hosted page AFTER our 10-min poll. Marker '
              'must persist so startup recovery can re-verify later. Codex '
              'review caught this in 9358cd73 follow-up.',
        );
        addTearDown(r.container.dispose);
      },
    );

    test(
      '4) expired/failed payment clears the marker — no infinite recovery on dead session',
      () async {
        final r = await _runStripeFlow(
          prefs: prefs,
          pollResult: PaymentResult(
            status: PaymentStatus.failed,
            sessionId: 'sess_test',
            paymentMethod: 'stripe',
            createdAt: DateTime.now(),
            errorMessage: 'Payment failed',
          ),
          activationThrows: false,
        );

        expect(
          r.tracker.cleared,
          isTrue,
          reason:
              'Truly failed/expired payment (not pending, not success) → no '
              'license to activate, no recovery possible → clear marker to '
              'avoid infinite-recover on every startup.',
        );
        addTearDown(r.container.dispose);
      },
    );

    test(
      '5) completed without license key keeps marker — paid user awaits license',
      () async {
        final r = await _runStripeFlow(
          prefs: prefs,
          pollResult: PaymentResult(
            status: PaymentStatus.completed,
            sessionId: 'sess_test',
            paymentMethod: 'stripe',
            createdAt: DateTime.now(),
          ),
          activationThrows: false,
        );

        expect(
          r.tracker.cleared,
          isFalse,
          reason:
              'PUL-1: completed+null licenseKey is not a failed/dead session. '
              'The marker must stay so backend key-link races recover.',
        );
        expect(r.container.read(paymentProvider).isPending, isTrue);
        expect(r.container.read(paymentProvider).isSuccess, isFalse);
        addTearDown(r.container.dispose);
      },
    );

    test(
      '6) manual check keeps marker for completed without key and clears after key',
      () async {
        final datasource = _InMemoryDatasource(prefs);
        final premiumService = PremiumLicenseService(datasource);
        final tracker = _SessionTracker();

        final waitingContainer = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            premiumLocalDatasourceProvider.overrideWithValue(datasource),
            premiumLicenseServiceProvider.overrideWithValue(premiumService),
            stripePaymentServiceProvider.overrideWithValue(
              _FakeStripeService(
                pollResult: PaymentResult(
                  status: PaymentStatus.completed,
                  sessionId: 'sess_waiting',
                  paymentMethod: 'stripe',
                  createdAt: DateTime.now(),
                ),
                prefs: prefs,
              ),
            ),
          ],
        );
        addTearDown(waitingContainer.dispose);

        await waitingContainer
            .read(paymentProvider.notifier)
            .checkPendingSession(
              'sess_waiting',
              onClearSession: tracker.onClear,
            );
        expect(tracker.cleared, isFalse);

        final resolvedContainer = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            premiumLocalDatasourceProvider.overrideWithValue(datasource),
            premiumLicenseServiceProvider.overrideWithValue(premiumService),
            stripePaymentServiceProvider.overrideWithValue(
              _FakeStripeService(
                pollResult: PaymentResult(
                  status: PaymentStatus.completed,
                  sessionId: 'sess_resolved',
                  licenseKey: 'SVID-1234-5678-9abc-def0-1234-5678-9abc-def0',
                  paymentMethod: 'stripe',
                  createdAt: DateTime.now(),
                  expiresAt: DateTime.now().add(const Duration(days: 30)),
                  billingCycle: 'monthly',
                ),
                prefs: prefs,
              ),
            ),
          ],
        );
        addTearDown(resolvedContainer.dispose);

        await resolvedContainer
            .read(paymentProvider.notifier)
            .checkPendingSession(
              'sess_resolved',
              onClearSession: tracker.onClear,
            );
        expect(tracker.cleared, isTrue);
      },
    );
  });

  group('PremiumNotifier activation contract', () {
    test(
      '5) activateLicense propagates storage failure — outer await/try-catch '
      'must surface it (no silent swallow / false-success)',
      () async {
        final datasource = _ThrowingDatasource(prefs);
        final service = PremiumLicenseService(datasource);
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            premiumLocalDatasourceProvider.overrideWithValue(datasource),
            premiumLicenseServiceProvider.overrideWithValue(service),
          ],
        );
        addTearDown(container.dispose);

        expect(
          () => container
              .read(premiumLicenseProvider.notifier)
              .activateLicense('SVID-1234-5678-9abc-def0-1234-5678-9abc-def0'),
          throwsA(isA<Exception>()),
          reason:
              'PremiumNotifier.activateLicense MUST throw on Keychain failure '
              'so callers (premium_upgrade_screen restore success branch, '
              'payment_providers._handleActivation) can surface activation '
              'failure instead of showing false-success.',
        );
      },
    );
  });
}
