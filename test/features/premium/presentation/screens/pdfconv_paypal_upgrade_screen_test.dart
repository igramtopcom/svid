import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svid/core/config/brand_config.dart';
import 'package:svid/core/network/backend_client.dart';
import 'package:svid/core/network/backend_dtos.dart';
import 'package:svid/core/providers/backend_providers.dart';
import 'package:svid/core/services/analytics_service.dart';
import 'package:svid/core/services/backend_service.dart';
import 'package:svid/core/services/secure_credential_store.dart';
import 'package:svid/features/premium/data/datasources/premium_local_datasource.dart';
import 'package:svid/features/premium/data/services/pdfconv_paypal_service.dart';
import 'package:svid/features/premium/data/services/pdfconv_pending_checkout_store.dart';
import 'package:svid/features/premium/domain/entities/pdfconv_paypal_plan.dart';
import 'package:svid/features/premium/domain/services/premium_license_service.dart';
import 'package:svid/features/premium/presentation/providers/payment_providers.dart';
import 'package:svid/features/premium/presentation/providers/pdfconv_paypal_providers.dart';
import 'package:svid/features/premium/presentation/providers/pdfconv_paypal_rollout_provider.dart';
import 'package:svid/features/premium/presentation/providers/premium_providers.dart';
import 'package:svid/features/premium/presentation/screens/premium_upgrade_screen.dart';
import 'package:svid/features/settings/presentation/providers/settings_provider.dart';

Finder _paypalText() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        ((widget.data ?? '').contains('paypalCheckout') ||
            (widget.data ?? '').contains('PayPal')),
  );
}

Future<void> _waitForLocalization(
  WidgetTester tester, {
  required Locale locale,
}) async {
  final expectedTitle =
      locale.languageCode == 'de'
          ? 'Wählen Sie Ihren Plan'
          : 'Choose Your Plan';
  for (var i = 0; i < 30; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    if (find.text(expectedTitle).evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('Localization did not load for ${locale.languageCode}');
}

class _NoopAnalyticsService extends AnalyticsService {
  _NoopAnalyticsService(super.backendService);

  @override
  void track(String eventName, [Map<String, dynamic>? properties]) {}

  @override
  Future<void> dispose() async {}
}

class _PendingPdfConvNotifier extends PdfConvPayPalNotifier {
  _PendingPdfConvNotifier(
    BackendClient client,
    SecureCredentialStore credentials,
  ) : super(
        service: PdfConvPayPalService(client),
        store: PdfConvPendingCheckoutStore(credentials),
        activateLicense: (_) async {},
      ) {
    state = PdfConvPayPalState(
      phase: PdfConvCheckoutPhase.waitingForApproval,
      pendingCheckout: PdfConvPendingCheckout(
        idempotencyKey: '970b0341-fc86-47bc-9a57-e2ddd218d356',
        planId: PdfConvPlanId.p30,
        buyerEmail: 'buyer@example.com',
        createdAt: DateTime.utc(2026, 7, 17),
        purchaseIntentId: '0cc27c14-f861-44df-a656-00a519d6f22b',
        approvalUrl: Uri.parse(
          'https://www.paypal.com/checkoutnow?token=ORDER-1',
        ),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  late SharedPreferences prefs;
  late PremiumLocalDatasource datasource;
  late PremiumLicenseService licenseService;
  late BackendClient backendClient;
  late AnalyticsService analyticsService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'secure_storage_unavailable_until':
          DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
    });
    prefs = await SharedPreferences.getInstance();
    datasource = PremiumLocalDatasource(prefs, SecureCredentialStore(prefs));
    licenseService = PremiumLicenseService(datasource);
    backendClient = BackendClient(SecureCredentialStore(prefs));
    analyticsService = _NoopAnalyticsService(BackendService(backendClient));
  });

  tearDown(() {
    backendClient.dispose();
    BrandConfig.setForTest(null);
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required Brand brand,
    List<PricingPlan> stripePlans = const [],
    bool hasPendingPdfConvCheckout = false,
    bool? pdfConvCheckoutEnabled,
    Size surfaceSize = const Size(1200, 900),
    Locale? locale,
  }) async {
    BrandConfig.setForTest(brand);
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Widget buildHost(BuildContext? localizationContext) {
      return ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          premiumLocalDatasourceProvider.overrideWithValue(datasource),
          premiumLicenseServiceProvider.overrideWithValue(licenseService),
          analyticsServiceProvider.overrideWithValue(analyticsService),
          pricingPlansProvider.overrideWith((ref) async => stripePlans),
          featureFlagsProvider.overrideWith(
            (ref) => [
              if (pdfConvCheckoutEnabled != null)
                FeatureFlagResponse(
                  key: pdfConvPayPalCheckoutFlagKey,
                  enabled: pdfConvCheckoutEnabled,
                ),
            ],
          ),
          if (hasPendingPdfConvCheckout)
            pdfConvPayPalProvider.overrideWith(
              (ref) => _PendingPdfConvNotifier(
                backendClient,
                SecureCredentialStore(prefs),
              ),
            ),
        ],
        child:
            localizationContext == null
                ? const MaterialApp(home: PremiumUpgradeScreen())
                : MaterialApp(
                  localizationsDelegates:
                      localizationContext.localizationDelegates,
                  supportedLocales: localizationContext.supportedLocales,
                  locale: localizationContext.locale,
                  home: const PremiumUpgradeScreen(),
                ),
      );
    }

    if (locale == null) {
      await tester.pumpWidget(buildHost(null));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      return;
    }

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('de')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        startLocale: locale,
        assetLoader: const RootBundleAssetLoader(),
        useOnlyLangCode: true,
        child: Builder(builder: buildHost),
      ),
    );
    await _waitForLocalization(tester, locale: locale);
  }

  testWidgets('VidCombo renders PDFConv catalog and PayPal email gate', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      brand: Brand.vidcombo,
      pdfConvCheckoutEnabled: true,
    );

    expect(find.text(r'$10'), findsOneWidget);
    expect(find.text(r'$15'), findsOneWidget);
    expect(find.text(r'$25'), findsOneWidget);
    expect(find.text(r'$42'), findsOneWidget);
    expect(find.text(r'$6.99'), findsNothing);
    expect(_paypalText(), findsOneWidget);

    await tester.tap(_paypalText());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pdfconv_paypal_email')), findsOneWidget);
    expect(find.byKey(const Key('pdfconv_paypal_continue')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('pdfconv_paypal_email')),
      'not-an-email',
    );
    await tester.tap(find.byKey(const Key('pdfconv_paypal_continue')));
    await tester.pump();

    expect(find.byKey(const Key('pdfconv_paypal_email')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('VidCombo keeps new checkout closed when flag is absent', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      brand: Brand.vidcombo,
      stripePlans: const [
        PricingPlan(
          billingCycle: 'monthly',
          amountCents: 699,
          currency: 'usd',
          interval: 'month',
          maxDevices: 5,
          isLifetime: false,
        ),
      ],
    );

    expect(find.text(r'$10'), findsNothing);
    expect(find.text(r'$6.99'), findsNothing);
    expect(_paypalText(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('VidCombo keeps new checkout closed when flag is disabled', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      brand: Brand.vidcombo,
      pdfConvCheckoutEnabled: false,
    );

    expect(find.text(r'$10'), findsNothing);
    expect(_paypalText(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SSvid keeps Stripe catalog and does not expose PayPal', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      brand: Brand.ssvid,
      pdfConvCheckoutEnabled: true,
      stripePlans: const [
        PricingPlan(
          billingCycle: 'monthly',
          amountCents: 699,
          currency: 'usd',
          interval: 'month',
          maxDevices: 5,
          isLifetime: false,
        ),
      ],
    );

    expect(find.text(r'$6.99'), findsOneWidget);
    expect(find.text(r'$10'), findsNothing);
    expect(_paypalText(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending PDFConv checkout exposes safe resume actions', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      brand: Brand.vidcombo,
      hasPendingPdfConvCheckout: true,
      pdfConvCheckoutEnabled: false,
    );

    expect(
      find.byKey(const Key('pdfconv_reopen_pending_payment')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('pdfconv_recheck_pending_payment')),
      findsOneWidget,
    );
    expect(find.text(r'$10'), findsNothing);
    expect(find.text(r'$6.99'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('VidCombo catalog fits the minimum desktop viewport', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      brand: Brand.vidcombo,
      pdfConvCheckoutEnabled: true,
      surfaceSize: const Size(1024, 768),
      locale: const Locale('de'),
    );

    expect(find.text(r'$10'), findsOneWidget);
    expect(find.text(r'$42'), findsOneWidget);
    expect(_paypalText(), findsOneWidget);
    final exception = tester.takeException();
    expect(
      exception,
      isNull,
      reason: exception is FlutterError ? exception.toStringDeep() : null,
    );
  });
}
