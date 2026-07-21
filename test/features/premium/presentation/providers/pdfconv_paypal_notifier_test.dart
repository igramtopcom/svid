import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssvid/core/network/backend_client.dart';
import 'package:ssvid/core/services/secure_credential_store.dart';
import 'package:ssvid/features/premium/data/services/pdfconv_paypal_service.dart';
import 'package:ssvid/features/premium/data/services/pdfconv_pending_checkout_store.dart';
import 'package:ssvid/features/premium/domain/entities/pdfconv_paypal_plan.dart';
import 'package:ssvid/features/premium/domain/entities/pdfconv_purchase_intent.dart';
import 'package:ssvid/features/premium/presentation/providers/pdfconv_paypal_providers.dart';

const _idempotencyKey = '970b0341-fc86-47bc-9a57-e2ddd218d356';
const _newIdempotencyKey = 'c7071247-0aa3-4552-94d6-c2db6779032a';
const _intentId = '0cc27c14-f861-44df-a656-00a519d6f22b';
const _otherIntentId = '61d6eef8-8c3a-4f8b-a4ab-ab55ef0dc8eb';
final _approvalUrl = Uri.parse(
  'https://www.paypal.com/checkoutnow?token=ORDER-1',
);

PdfConvPurchaseIntent _intent({
  String purchaseIntentId = _intentId,
  PdfConvBillingStatus billingStatus = PdfConvBillingStatus.created,
  PdfConvEntitlementStatus entitlementStatus = PdfConvEntitlementStatus.pending,
  PdfConvPlanId planId = PdfConvPlanId.p30,
  Uri? approvalUrl,
  String? licenseKey,
  DateTime? licenseExpiresAt,
  bool retryable = false,
}) {
  return PdfConvPurchaseIntent(
    purchaseIntentId: purchaseIntentId,
    billingStatus: billingStatus,
    entitlementStatus: entitlementStatus,
    planId: planId,
    approvalUrl: approvalUrl,
    licenseKey: licenseKey,
    licenseExpiresAt: licenseExpiresAt,
    retryable: retryable,
  );
}

PdfConvPendingCheckout _marker({
  String? purchaseIntentId = _intentId,
  Uri? approvalUrl,
  String idempotencyKey = _idempotencyKey,
  PdfConvPlanId planId = PdfConvPlanId.p30,
  String buyerEmail = 'buyer@example.com',
}) {
  return PdfConvPendingCheckout(
    idempotencyKey: idempotencyKey,
    planId: planId,
    buyerEmail: buyerEmail,
    createdAt: DateTime.utc(2026, 7, 17),
    purchaseIntentId: purchaseIntentId,
    approvalUrl: approvalUrl,
  );
}

class _MemoryStore extends PdfConvPendingCheckoutStore {
  PdfConvPendingCheckout? marker;
  int writeCalls = 0;
  int clearCalls = 0;

  _MemoryStore(super.credentials);

  @override
  Future<PdfConvPendingCheckout?> read() async => marker;

  @override
  Future<void> write(PdfConvPendingCheckout checkout) async {
    writeCalls++;
    marker = checkout;
  }

  @override
  Future<void> clear() async {
    clearCalls++;
    marker = null;
  }
}

class _FakeService extends PdfConvPayPalService {
  _FakeService(super.client);

  int createCalls = 0;
  int statusCalls = 0;
  int captureCalls = 0;
  int openCalls = 0;
  PdfConvPlanId? createdPlan;
  String? createdEmail;
  String? createdIdempotencyKey;
  Uri? openedUrl;
  String nextIdempotencyKey = _idempotencyKey;

  Future<PdfConvPurchaseIntent> Function()? onCreate;
  Future<PdfConvPurchaseIntent> Function()? onStatus;
  Future<PdfConvPurchaseIntent> Function()? onCapture;

  @override
  String newIdempotencyKey() => nextIdempotencyKey;

  @override
  Future<PdfConvPurchaseIntent> createIntent({
    required PdfConvPlanId planId,
    required String buyerEmail,
    required String idempotencyKey,
  }) async {
    createCalls++;
    createdPlan = planId;
    createdEmail = buyerEmail;
    createdIdempotencyKey = idempotencyKey;
    return onCreate!();
  }

  @override
  Future<PdfConvPurchaseIntent> getIntentStatus(String purchaseIntentId) async {
    statusCalls++;
    return onStatus!();
  }

  @override
  Future<PdfConvPurchaseIntent> captureIntent(String purchaseIntentId) async {
    captureCalls++;
    return onCapture!();
  }

  @override
  Future<bool> openApprovalPage(Uri approvalUrl) async {
    openCalls++;
    openedUrl = approvalUrl;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BackendClient client;
  late SecureCredentialStore credentials;
  late _FakeService service;
  late _MemoryStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    credentials = SecureCredentialStore(prefs);
    client = BackendClient(credentials);
    service = _FakeService(client);
    store = _MemoryStore(credentials);
  });

  tearDown(() {
    client.dispose();
  });

  PdfConvPayPalNotifier notifier({
    Future<void> Function(PdfConvPurchaseIntent)? activate,
    bool Function()? canCreateIntent,
  }) {
    final result = PdfConvPayPalNotifier(
      service: service,
      store: store,
      activateLicense: activate ?? (_) async {},
      canCreateIntent: canCreateIntent,
      delay: (_) async {},
    );
    addTearDown(result.dispose);
    return result;
  }

  test(
    'persists draft before create and binds intent before browser',
    () async {
      PdfConvPendingCheckout? markerSeenByCreate;
      service.onCreate = () async {
        markerSeenByCreate = store.marker;
        return _intent(approvalUrl: _approvalUrl);
      };
      final subject = notifier();

      await subject.startCheckout(
        planId: PdfConvPlanId.p30,
        buyerEmail: ' Buyer@Example.com ',
        maxPollAttempts: 0,
      );

      expect(markerSeenByCreate?.purchaseIntentId, isNull);
      expect(markerSeenByCreate?.idempotencyKey, _idempotencyKey);
      expect(service.createdEmail, 'buyer@example.com');
      expect(service.createdIdempotencyKey, _idempotencyKey);
      expect(store.marker?.purchaseIntentId, _intentId);
      expect(store.marker?.approvalUrl, _approvalUrl);
      expect(service.openCalls, 1);
      expect(service.openedUrl, _approvalUrl);
    },
  );

  test('rollout gate blocks a new marker and create request', () async {
    final subject = notifier(canCreateIntent: () => false);

    await subject.startCheckout(
      planId: PdfConvPlanId.p30,
      buyerEmail: 'buyer@example.com',
      maxPollAttempts: 0,
    );

    expect(store.writeCalls, 0);
    expect(store.marker, isNull);
    expect(service.createCalls, 0);
    expect(service.openCalls, 0);
    expect(subject.state.phase, PdfConvCheckoutPhase.idle);
    expect(subject.state.error, contains('temporarily unavailable'));
  });

  test('rollout gate does not block recovery of a bound intent', () async {
    store.marker = _marker(approvalUrl: _approvalUrl);
    service.onStatus = () async => _intent(approvalUrl: _approvalUrl);
    final subject = notifier(canCreateIntent: () => false);

    await subject.recoverPendingCheckout(maxPollAttempts: 0);

    expect(service.statusCalls, 1);
    expect(service.createCalls, 0);
    expect(store.marker?.purchaseIntentId, _intentId);
    expect(subject.state.phase, PdfConvCheckoutPhase.waitingForApproval);
  });

  test('rollout gate blocks replay of an unbound draft', () async {
    store.marker = _marker(purchaseIntentId: null);
    final subject = notifier(canCreateIntent: () => false);

    await subject.recoverPendingCheckout();

    expect(service.createCalls, 0);
    expect(store.marker, isNotNull);
    expect(subject.state.error, contains('temporarily unavailable'));
  });

  test('same plan and canonical email resume the existing checkout', () async {
    store.marker = _marker(approvalUrl: _approvalUrl);
    service.onStatus = () async => _intent(approvalUrl: _approvalUrl);
    final subject = notifier();

    await subject.startCheckout(
      planId: PdfConvPlanId.p30,
      buyerEmail: ' Buyer@Example.com ',
      maxPollAttempts: 0,
    );

    expect(service.statusCalls, 1);
    expect(service.createCalls, 0);
    expect(service.openCalls, 1);
    expect(store.marker?.idempotencyKey, _idempotencyKey);
    expect(store.marker?.buyerEmail, 'buyer@example.com');
    expect(subject.state.error, isNull);
  });

  test('plan mismatch reconciles pending intent without opening it', () async {
    store.marker = _marker(planId: PdfConvPlanId.p7, approvalUrl: _approvalUrl);
    service.onStatus =
        () async =>
            _intent(planId: PdfConvPlanId.p7, approvalUrl: _approvalUrl);
    final subject = notifier();

    await subject.startCheckout(
      planId: PdfConvPlanId.lifetime,
      buyerEmail: 'buyer@example.com',
      maxPollAttempts: 0,
    );

    expect(service.statusCalls, 1);
    expect(service.createCalls, 0);
    expect(service.openCalls, 0);
    expect(store.marker?.planId, PdfConvPlanId.p7);
    expect(subject.state.pendingCheckout?.planId, PdfConvPlanId.p7);
    expect(subject.state.error, contains('Continue that payment'));
  });

  for (final billingStatus in [
    PdfConvBillingStatus.manualReview,
    PdfConvBillingStatus.fulfilled,
  ]) {
    test('plan mismatch keeps ${billingStatus.wireValue} old intent', () async {
      store.marker = _marker(planId: PdfConvPlanId.p7);
      service.onStatus =
          () async =>
              _intent(planId: PdfConvPlanId.p7, billingStatus: billingStatus);
      final subject = notifier();

      await subject.startCheckout(
        planId: PdfConvPlanId.lifetime,
        buyerEmail: 'buyer@example.com',
        maxPollAttempts: 0,
      );

      expect(service.statusCalls, 1);
      expect(service.createCalls, 0);
      expect(service.openCalls, 0);
      expect(store.marker?.planId, PdfConvPlanId.p7);
      expect(subject.state.error, contains('Continue that payment'));
      expect(
        subject.state.phase,
        billingStatus == PdfConvBillingStatus.manualReview
            ? PdfConvCheckoutPhase.manualReview
            : PdfConvCheckoutPhase.waitingForEntitlement,
      );
    });
  }

  test('email mismatch keeps the existing pending identity', () async {
    store.marker = _marker(buyerEmail: 'first@example.com');
    service.onStatus = () async => _intent();
    final subject = notifier();

    await subject.startCheckout(
      planId: PdfConvPlanId.p30,
      buyerEmail: 'second@example.com',
      maxPollAttempts: 0,
    );

    expect(service.statusCalls, 1);
    expect(service.createCalls, 0);
    expect(service.openCalls, 0);
    expect(store.marker?.buyerEmail, 'first@example.com');
    expect(subject.state.error, contains('changing the plan or email'));
  });

  test('terminal old intent is cleared before creating a new order', () async {
    store.marker = _marker(
      purchaseIntentId: _otherIntentId,
      planId: PdfConvPlanId.p7,
    );
    service.nextIdempotencyKey = _newIdempotencyKey;
    service.onStatus =
        () async => _intent(
          purchaseIntentId: _otherIntentId,
          planId: PdfConvPlanId.p7,
          billingStatus: PdfConvBillingStatus.expired,
        );
    service.onCreate =
        () async =>
            _intent(planId: PdfConvPlanId.lifetime, approvalUrl: _approvalUrl);
    final subject = notifier();

    await subject.startCheckout(
      planId: PdfConvPlanId.lifetime,
      buyerEmail: 'new@example.com',
      maxPollAttempts: 0,
    );

    expect(service.statusCalls, 1);
    expect(store.clearCalls, 1);
    expect(service.createCalls, 1);
    expect(service.createdPlan, PdfConvPlanId.lifetime);
    expect(service.createdEmail, 'new@example.com');
    expect(service.createdIdempotencyKey, _newIdempotencyKey);
    expect(service.openCalls, 1);
    expect(store.marker?.planId, PdfConvPlanId.lifetime);
    expect(store.marker?.buyerEmail, 'new@example.com');
  });

  test(
    'terminal capture clears old intent before creating a new order',
    () async {
      store.marker = _marker(
        purchaseIntentId: _otherIntentId,
        planId: PdfConvPlanId.p7,
      );
      service.nextIdempotencyKey = _newIdempotencyKey;
      service.onStatus =
          () async => _intent(
            purchaseIntentId: _otherIntentId,
            planId: PdfConvPlanId.p7,
            billingStatus: PdfConvBillingStatus.approved,
          );
      service.onCapture =
          () async => _intent(
            purchaseIntentId: _otherIntentId,
            planId: PdfConvPlanId.p7,
            billingStatus: PdfConvBillingStatus.denied,
          );
      service.onCreate =
          () async => _intent(
            planId: PdfConvPlanId.lifetime,
            approvalUrl: _approvalUrl,
          );
      final subject = notifier();

      await subject.startCheckout(
        planId: PdfConvPlanId.lifetime,
        buyerEmail: 'new@example.com',
        maxPollAttempts: 0,
      );

      expect(service.statusCalls, 1);
      expect(service.captureCalls, 1);
      expect(store.clearCalls, 1);
      expect(service.createCalls, 1);
      expect(service.createdPlan, PdfConvPlanId.lifetime);
      expect(service.openCalls, 1);
      expect(store.marker?.planId, PdfConvPlanId.lifetime);
      expect(store.marker?.buyerEmail, 'new@example.com');
    },
  );

  test(
    'rollout gate clears a terminal old intent without a new order',
    () async {
      store.marker = _marker(
        purchaseIntentId: _otherIntentId,
        planId: PdfConvPlanId.p7,
      );
      service.onStatus =
          () async => _intent(
            purchaseIntentId: _otherIntentId,
            planId: PdfConvPlanId.p7,
            billingStatus: PdfConvBillingStatus.expired,
          );
      final subject = notifier(canCreateIntent: () => false);

      await subject.startCheckout(
        planId: PdfConvPlanId.lifetime,
        buyerEmail: 'new@example.com',
        maxPollAttempts: 0,
      );

      expect(service.statusCalls, 1);
      expect(store.clearCalls, 1);
      expect(store.marker, isNull);
      expect(service.createCalls, 0);
      expect(service.openCalls, 0);
      expect(subject.state.phase, PdfConvCheckoutPhase.idle);
      expect(subject.state.error, contains('temporarily unavailable'));
    },
  );

  test('concurrent selections cannot create a second order', () async {
    store.marker = _marker(
      purchaseIntentId: _otherIntentId,
      planId: PdfConvPlanId.p7,
    );
    service.nextIdempotencyKey = _newIdempotencyKey;
    service.onStatus = () async {
      if (service.statusCalls == 1) {
        return _intent(
          purchaseIntentId: _otherIntentId,
          planId: PdfConvPlanId.p7,
          billingStatus: PdfConvBillingStatus.expired,
        );
      }
      return _intent(planId: PdfConvPlanId.lifetime, approvalUrl: _approvalUrl);
    };
    service.onCreate =
        () async =>
            _intent(planId: PdfConvPlanId.lifetime, approvalUrl: _approvalUrl);
    final subject = notifier();

    final first = subject.startCheckout(
      planId: PdfConvPlanId.lifetime,
      buyerEmail: 'buyer@example.com',
      maxPollAttempts: 0,
    );
    final second = subject.startCheckout(
      planId: PdfConvPlanId.p90,
      buyerEmail: 'buyer@example.com',
      maxPollAttempts: 0,
    );
    await Future.wait([first, second]);

    expect(service.createCalls, 1);
    expect(service.statusCalls, 2);
    expect(service.openCalls, 1);
    expect(store.marker?.planId, PdfConvPlanId.lifetime);
    expect(subject.state.pendingCheckout?.planId, PdfConvPlanId.lifetime);
    expect(subject.state.error, contains('Continue that payment'));
  });

  test('completed old intent does not create or open a new order', () async {
    store.marker = _marker(planId: PdfConvPlanId.p7);
    service.onStatus =
        () async => _intent(
          planId: PdfConvPlanId.p7,
          billingStatus: PdfConvBillingStatus.approved,
        );
    service.onCapture =
        () async => _intent(
          planId: PdfConvPlanId.p7,
          billingStatus: PdfConvBillingStatus.fulfilled,
          entitlementStatus: PdfConvEntitlementStatus.granted,
          licenseKey: 'VIDCOMBO-1234-5678-9ABC-DEF0-1234-5678-9ABC-DEF0',
          licenseExpiresAt: DateTime.utc(2026, 7, 24),
        );
    var activationCalls = 0;
    final subject = notifier(activate: (_) async => activationCalls++);

    await subject.startCheckout(
      planId: PdfConvPlanId.lifetime,
      buyerEmail: 'buyer@example.com',
      maxPollAttempts: 0,
    );

    expect(activationCalls, 1);
    expect(service.statusCalls, 1);
    expect(service.captureCalls, 1);
    expect(service.createCalls, 0);
    expect(service.openCalls, 0);
    expect(store.marker, isNull);
    expect(subject.state.phase, PdfConvCheckoutPhase.completed);
  });

  test('transport failure retains mismatched marker as a conflict', () async {
    store.marker = _marker(planId: PdfConvPlanId.p7);
    service.onStatus = () async => throw StateError('network unavailable');
    final subject = notifier();

    await subject.startCheckout(
      planId: PdfConvPlanId.p90,
      buyerEmail: 'buyer@example.com',
      maxPollAttempts: 0,
    );

    expect(service.statusCalls, 1);
    expect(service.createCalls, 0);
    expect(service.openCalls, 0);
    expect(store.marker?.planId, PdfConvPlanId.p7);
    expect(subject.state.error, contains('Continue that payment'));
  });

  test(
    'startup replays draft with the original identity without opening browser',
    () async {
      store.marker = _marker(purchaseIntentId: null);
      service.onCreate = () async => _intent(approvalUrl: _approvalUrl);
      final subject = notifier();

      await subject.recoverPendingCheckout(maxPollAttempts: 0);

      expect(service.createCalls, 1);
      expect(service.createdPlan, PdfConvPlanId.p30);
      expect(service.createdEmail, 'buyer@example.com');
      expect(service.createdIdempotencyKey, _idempotencyKey);
      expect(store.marker?.purchaseIntentId, _intentId);
      expect(service.openCalls, 0);

      expect(await subject.reopenApprovalPage(), isTrue);
      expect(service.createCalls, 1);
      expect(service.openCalls, 1);
      expect(service.openedUrl, _approvalUrl);
    },
  );

  test('failed create resumes with the persisted idempotency key', () async {
    service.onCreate = () async => throw StateError('temporary outage');
    final subject = notifier();

    await subject.startCheckout(
      planId: PdfConvPlanId.p30,
      buyerEmail: 'buyer@example.com',
      maxPollAttempts: 0,
    );

    expect(store.marker?.idempotencyKey, _idempotencyKey);
    expect(service.createCalls, 1);

    service.onCreate = () async => _intent(approvalUrl: _approvalUrl);
    expect(await subject.reopenApprovalPage(), isTrue);

    expect(service.createCalls, 2);
    expect(service.createdIdempotencyKey, _idempotencyKey);
    expect(service.openCalls, 1);
    expect(store.marker?.purchaseIntentId, _intentId);
  });

  test(
    'failed new create cannot reopen a stale terminal approval URL',
    () async {
      store.marker = _marker(
        planId: PdfConvPlanId.p7,
        approvalUrl: _approvalUrl,
      );
      service.onStatus =
          () async => _intent(
            planId: PdfConvPlanId.p7,
            billingStatus: PdfConvBillingStatus.expired,
            approvalUrl: _approvalUrl,
          );
      final subject = notifier();

      await subject.recoverPendingCheckout();
      expect(store.marker, isNull);
      expect(subject.state.intent?.approvalUrl, _approvalUrl);

      service.nextIdempotencyKey = _newIdempotencyKey;
      service.onCreate = () async => throw StateError('temporary outage');
      await subject.startCheckout(
        planId: PdfConvPlanId.lifetime,
        buyerEmail: 'new@example.com',
        maxPollAttempts: 0,
      );

      expect(service.createCalls, 1);
      expect(service.openCalls, 0);
      expect(subject.state.intent, isNull);
      expect(store.marker?.planId, PdfConvPlanId.lifetime);
      expect(await subject.reopenApprovalPage(), isFalse);
      expect(service.createCalls, 2);
      expect(service.openCalls, 0);
    },
  );

  test('fulfilled billing with pending entitlement never activates', () async {
    store.marker = _marker();
    service.onStatus =
        () async => _intent(billingStatus: PdfConvBillingStatus.fulfilled);
    var activationCalls = 0;
    final subject = notifier(activate: (_) async => activationCalls++);

    await subject.recoverPendingCheckout(maxPollAttempts: 0);

    expect(activationCalls, 0);
    expect(store.marker, isNotNull);
    expect(subject.state.phase, PdfConvCheckoutPhase.waitingForEntitlement);
  });

  test(
    'rollout gate does not block capture and activation of a bound intent',
    () async {
      store.marker = _marker(approvalUrl: _approvalUrl);
      service.onStatus =
          () async => _intent(
            billingStatus: PdfConvBillingStatus.approved,
            approvalUrl: _approvalUrl,
          );
      service.onCapture =
          () async => _intent(
            billingStatus: PdfConvBillingStatus.fulfilled,
            entitlementStatus: PdfConvEntitlementStatus.granted,
            licenseKey: 'VIDCOMBO-1234-5678-9ABC-DEF0-1234-5678-9ABC-DEF0',
            licenseExpiresAt: DateTime.utc(2026, 8, 16),
          );
      final activated = <PdfConvPurchaseIntent>[];
      final subject = notifier(
        activate: (intent) async => activated.add(intent),
        canCreateIntent: () => false,
      );

      await subject.recoverPendingCheckout();

      expect(service.captureCalls, 1);
      expect(activated, hasLength(1));
      expect(store.marker, isNull);
      expect(subject.state.phase, PdfConvCheckoutPhase.completed);
    },
  );

  test('deep-link refresh polls through async settlement grant', () async {
    store.marker = _marker();
    service.onStatus = () async {
      if (service.statusCalls == 1) {
        return _intent(billingStatus: PdfConvBillingStatus.approved);
      }
      return _intent(
        billingStatus: PdfConvBillingStatus.fulfilled,
        entitlementStatus: PdfConvEntitlementStatus.granted,
        licenseKey: 'VIDCOMBO-1234-5678-9ABC-DEF0-1234-5678-9ABC-DEF0',
        licenseExpiresAt: DateTime.utc(2026, 8, 16),
      );
    };
    service.onCapture =
        () async => _intent(
          billingStatus: PdfConvBillingStatus.fulfilled,
          entitlementStatus: PdfConvEntitlementStatus.pending,
        );
    final activated = <PdfConvPurchaseIntent>[];
    final subject = notifier(
      activate: (intent) async => activated.add(intent),
      canCreateIntent: () => false,
    );

    await subject.refreshPendingCheckout(maxPollAttempts: 2);

    expect(service.statusCalls, 2);
    expect(service.captureCalls, 1);
    expect(activated, hasLength(1));
    expect(store.marker, isNull);
    expect(subject.state.phase, PdfConvCheckoutPhase.completed);
  });

  test(
    'concurrent wake events share one status and capture operation',
    () async {
      store.marker = _marker();
      final statusGate = Completer<PdfConvPurchaseIntent>();
      service.onStatus = () => statusGate.future;
      service.onCapture =
          () async =>
              _intent(billingStatus: PdfConvBillingStatus.capturePending);
      final subject = notifier();

      final first = subject.refreshPendingCheckout(maxPollAttempts: 0);
      final second = subject.refreshPendingCheckout(maxPollAttempts: 0);
      await Future<void>.delayed(Duration.zero);
      expect(service.statusCalls, 1);

      statusGate.complete(
        _intent(billingStatus: PdfConvBillingStatus.approved),
      );
      await Future.wait([first, second]);

      expect(service.statusCalls, 1);
      expect(service.captureCalls, 1);
      expect(store.marker, isNotNull);
    },
  );

  test('local activation failure preserves recovery marker', () async {
    store.marker = _marker();
    service.onStatus =
        () async => _intent(
          billingStatus: PdfConvBillingStatus.fulfilled,
          entitlementStatus: PdfConvEntitlementStatus.granted,
          licenseKey: 'VIDCOMBO-1234-5678-9ABC-DEF0-1234-5678-9ABC-DEF0',
          licenseExpiresAt: DateTime.utc(2026, 8, 16),
        );
    final subject = notifier(
      activate: (_) async => throw StateError('storage unavailable'),
    );

    await subject.recoverPendingCheckout();

    expect(store.marker, isNotNull);
    expect(store.clearCalls, 0);
    expect(subject.state.activationError, contains('storage unavailable'));
  });

  test('definitive billing failure clears marker without activation', () async {
    store.marker = _marker();
    service.onStatus =
        () async => _intent(billingStatus: PdfConvBillingStatus.expired);
    var activationCalls = 0;
    final subject = notifier(activate: (_) async => activationCalls++);

    await subject.recoverPendingCheckout();

    expect(activationCalls, 0);
    expect(store.marker, isNull);
    expect(subject.state.phase, PdfConvCheckoutPhase.terminal);
  });

  test(
    'mismatched status identity is rejected and marker is retained',
    () async {
      store.marker = _marker();
      service.onStatus = () async => _intent(purchaseIntentId: _otherIntentId);
      final subject = notifier();

      await subject.recoverPendingCheckout(maxPollAttempts: 0);

      expect(store.marker, isNotNull);
      expect(subject.state.error, contains('persisted purchase identity'));
    },
  );

  test('mismatched capture identity cannot activate', () async {
    store.marker = _marker();
    service.onStatus =
        () async => _intent(billingStatus: PdfConvBillingStatus.approved);
    service.onCapture =
        () async => _intent(
          purchaseIntentId: _otherIntentId,
          billingStatus: PdfConvBillingStatus.fulfilled,
          entitlementStatus: PdfConvEntitlementStatus.granted,
          licenseKey: 'VIDCOMBO-1234-5678-9ABC-DEF0-1234-5678-9ABC-DEF0',
          licenseExpiresAt: DateTime.utc(2026, 8, 16),
        );
    var activationCalls = 0;
    final subject = notifier(activate: (_) async => activationCalls++);

    await subject.recoverPendingCheckout(maxPollAttempts: 0);

    expect(activationCalls, 0);
    expect(store.marker, isNotNull);
    expect(subject.state.error, contains('persisted purchase identity'));
  });

  test('reopen uses the persisted approval URL', () async {
    store.marker = _marker(approvalUrl: _approvalUrl);
    final subject = notifier();

    expect(await subject.reopenApprovalPage(), isTrue);

    expect(service.openCalls, 1);
    expect(service.openedUrl, _approvalUrl);
  });
}
