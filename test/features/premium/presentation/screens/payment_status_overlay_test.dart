/// Widget tests for the PAY-3 payment blocker overlay ([PaymentStatusOverlay]).
///
/// The overlay is the in-session safety net for Stripe payments under Option B
/// (no deep link). While the payment is pending / completed-without-key it MUST
/// stay open (canPop: false) so the user can re-check via "I already paid"
/// instead of starting a duplicate purchase, and it MUST auto-dismiss once the
/// payment reaches an activatable success state.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:svid/core/network/backend_client.dart';
import 'package:svid/core/services/analytics_service.dart';
import 'package:svid/core/services/backend_service.dart';
import 'package:svid/core/services/secure_credential_store.dart';
import 'package:svid/features/premium/data/services/crypto_payment_service.dart';
import 'package:svid/features/premium/data/services/stripe_payment_service.dart';
import 'package:svid/features/premium/domain/entities/checkout_session.dart';
import 'package:svid/features/premium/domain/entities/payment_result.dart';
import 'package:svid/features/premium/domain/entities/payment_status.dart';
import 'package:svid/features/premium/presentation/providers/payment_providers.dart';
import 'package:svid/features/premium/presentation/providers/premium_providers.dart';
import 'package:svid/features/premium/presentation/screens/premium_upgrade_screen.dart';
import 'package:svid/features/settings/presentation/providers/settings_provider.dart';

import '../../../../helpers/brand_test_keys.dart';

/// PaymentNotifier spy: lets a test seed an arbitrary [PaymentState] and counts
/// [checkPendingSession] invocations. On check, transitions to whatever the
/// test configured via [onCheck] so the overlay's auto-dismiss can be exercised.
class _SpyPaymentNotifier extends PaymentNotifier {
  int checkPendingCalls = 0;

  /// State to install when [checkPendingSession] is invoked (null = no change).
  final PaymentState? onCheck;

  _SpyPaymentNotifier(
    super.stripe,
    super.crypto,
    super.premium,
    super.premiumService,
    super.analytics, {
    required PaymentState initialState,
    this.onCheck,
  }) {
    state = initialState;
  }

  @override
  Future<void> checkPendingSession(
    String sessionId, {
    required Future<void> Function() onClearSession,
  }) async {
    checkPendingCalls++;
    if (onCheck != null) state = onCheck!;
  }

  // Avoid real url_launcher in tests.
  @override
  Future<bool> reopenCheckoutPage() async => true;
}

PaymentState _pendingState() => PaymentState.initial.copyWith(
  isLoading: false,
  session: CheckoutSession(
    sessionId: 'sess_test',
    checkoutUrl: 'https://checkout.stripe.com/pay/test',
    expiresAt: DateTime.now().add(const Duration(minutes: 30)),
  ),
  result: PaymentResult(
    status: PaymentStatus.pending,
    sessionId: 'sess_test',
    paymentMethod: 'stripe',
    createdAt: DateTime.now(),
  ),
);

/// Completed-without-license-key → isAwaitingLicense → overlay must stay open.
PaymentState _awaitingState() => PaymentState.initial.copyWith(
  isLoading: false,
  session: CheckoutSession(
    sessionId: 'sess_test',
    checkoutUrl: 'https://checkout.stripe.com/pay/test',
    expiresAt: DateTime.now().add(const Duration(minutes: 30)),
  ),
  result: PaymentResult(
    status: PaymentStatus.completed,
    sessionId: 'sess_test',
    paymentMethod: 'stripe',
    createdAt: DateTime.now(),
  ),
);

/// Activatable success (has license key) → overlay must auto-dismiss.
PaymentState _activatableState() => PaymentState.initial.copyWith(
  isLoading: false,
  result: PaymentResult(
    status: PaymentStatus.completed,
    sessionId: 'sess_test',
    licenseKey: TestLicenseKeys.valid,
    paymentMethod: 'stripe',
    createdAt: DateTime.now(),
    expiresAt: DateTime.now().add(const Duration(days: 30)),
    billingCycle: 'monthly',
  ),
);

Future<void> _pumpOverlay(
  WidgetTester tester, {
  required _SpyPaymentNotifier Function(Ref ref) build,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(_overlayPrefs),
        paymentProvider.overrideWith(build),
      ],
      child: const MaterialApp(
        home: Scaffold(body: PaymentStatusOverlay()),
      ),
    ),
  );
  await tester.pump();
}

late SharedPreferences _overlayPrefs;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  _SpyPaymentNotifier spyBuilder(
    Ref ref, {
    required PaymentState initial,
    PaymentState? onCheck,
  }) {
    final client = BackendClient(SecureCredentialStore(prefs));
    return _SpyPaymentNotifier(
      StripePaymentService(client),
      CryptoPaymentService(client),
      ref.watch(premiumLicenseProvider.notifier),
      ref.watch(premiumLicenseServiceProvider),
      // Hand-built (no timer) — overlay never tracks analytics anyway.
      AnalyticsService(BackendService(client)),
      initialState: initial,
      onCheck: onCheck,
    );
  }

  setUp(() async {
    // Seed the secure-storage "unavailable" TTL so SecureCredentialStore takes
    // the synchronous SharedPreferences fallback path instead of awaiting a
    // (MissingPluginException-throwing) FlutterSecureStorage probe on every read.
    SharedPreferences.setMockInitialValues({
      'secure_storage_unavailable_until':
          DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
    });
    prefs = await SharedPreferences.getInstance();
    _overlayPrefs = prefs;
  });

  final alreadyPaidButton = find.byKey(
    const Key('payment_overlay_already_paid'),
  );

  testWidgets(
    'overlay stays open while payment is pending after poll',
    (tester) async {
      await _pumpOverlay(
        tester,
        build: (ref) => spyBuilder(ref, initial: _pendingState()),
      );

      // Blocker is present and exposes the "I already paid" re-check action.
      expect(find.byType(PaymentStatusOverlay), findsOneWidget);
      expect(alreadyPaidButton, findsOneWidget);

      // Dispose the tree to stop the indeterminate progress ticker.
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'overlay stays open when completed-without-key (awaiting license)',
    (tester) async {
      await _pumpOverlay(
        tester,
        build: (ref) => spyBuilder(ref, initial: _awaitingState()),
      );

      expect(find.byType(PaymentStatusOverlay), findsOneWidget);
      expect(alreadyPaidButton, findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'tapping "I already paid" calls checkPendingSession exactly once',
    (tester) async {
      late _SpyPaymentNotifier spy;
      await _pumpOverlay(
        tester,
        build: (ref) {
          // onCheck=null → state unchanged → overlay stays open after the tap.
          spy = spyBuilder(ref, initial: _awaitingState());
          return spy;
        },
      );

      await tester.tap(alreadyPaidButton);
      // Flush the async checkPendingSession closure (credentials.read await).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(spy.checkPendingCalls, 1);
      expect(find.byType(PaymentStatusOverlay), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'overlay auto-dismisses when check yields an activatable success',
    (tester) async {
      // Open the overlay via showDialog so auto-dismiss (Navigator.pop) removes
      // it from the tree — matching production usage.
      late _SpyPaymentNotifier spy;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            paymentProvider.overrideWith((ref) {
              spy = spyBuilder(
                ref,
                initial: _awaitingState(),
                onCheck: _activatableState(),
              );
              return spy;
            }),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => const PaymentStatusOverlay(),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Bounded pumps — the overlay's CircularProgressIndicator animates forever
      // so pumpAndSettle would never settle.
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(PaymentStatusOverlay), findsOneWidget);

      // "I already paid" → check transitions to activatable success → dismiss.
      await tester.tap(alreadyPaidButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(spy.checkPendingCalls, 1);
      expect(find.byType(PaymentStatusOverlay), findsNothing);
    },
  );
}
