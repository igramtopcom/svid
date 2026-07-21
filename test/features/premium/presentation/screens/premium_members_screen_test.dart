import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svid/core/config/brand_config.dart';
import 'package:svid/core/services/secure_credential_store.dart';
import 'package:svid/features/premium/data/datasources/premium_local_datasource.dart';
import 'package:svid/features/premium/domain/entities/premium_license.dart';
import 'package:svid/features/premium/domain/entities/premium_tier.dart';
import 'package:svid/features/premium/domain/services/premium_license_service.dart';
import 'package:svid/features/premium/presentation/providers/payment_providers.dart';
import 'package:svid/features/premium/presentation/providers/premium_providers.dart';
import 'package:svid/features/premium/presentation/screens/premium_members_screen.dart';
import 'package:svid/features/settings/presentation/providers/settings_provider.dart';

class _FakeSecureStorage {
  final Map<String, String> _store = {};

  Future<String?> read({required String key}) async => _store[key];

  Future<void> write({required String key, required String value}) async =>
      _store[key] = value;

  Future<void> delete({required String key}) async => _store.remove(key);
}

class _TestDatasource extends PremiumLocalDatasource {
  final _FakeSecureStorage _fakeSecure;

  _TestDatasource(SharedPreferences prefs)
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late _TestDatasource datasource;
  late PremiumLicenseService service;

  const licenseKey = 'SSVID-1234-5678-9abc-def0-1234-5678-9abc-def0';
  final license = PremiumLicense(
    tier: PremiumTier.premium,
    licenseKey: licenseKey,
    purchaseDate: DateTime(2026, 1, 1),
    lastVerified: DateTime(2026, 5, 1),
    paymentMethod: 'stripe',
    transactionId: 'txn_abc123456789',
    billingCycle: BillingCycle.monthly,
    expiresAt: DateTime(2026, 6, 1),
  );

  setUp(() async {
    BrandConfig.setForTest(Brand.ssvid);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    datasource = _TestDatasource(prefs);
    service = PremiumLicenseService(datasource);

    await datasource.saveMetadata(license.toJson());
    await datasource.saveLicenseKey(licenseKey);
  });

  tearDown(() => BrandConfig.setForTest(null));

  testWidgets(
    'desktop dashboard lays out without intrinsic LayoutBuilder errors',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            premiumLocalDatasourceProvider.overrideWithValue(datasource),
            premiumLicenseServiceProvider.overrideWithValue(service),
            pricingPlansProvider.overrideWith(
              (ref) async => const [
                PricingPlan(
                  billingCycle: 'monthly',
                  amountCents: 699,
                  currency: 'usd',
                  interval: 'month',
                  maxDevices: 5,
                  isLifetime: false,
                ),
              ],
            ),
            licenseInfoProvider.overrideWith((ref) async => null),
            devicesProvider.overrideWith((ref) async => const []),
            transactionsProvider.overrideWith((ref) async => const []),
          ],
          child: const MaterialApp(home: PremiumMembersScreen()),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'VidCombo PayPal member view uses fixed catalog and expiry copy',
    (tester) async {
      BrandConfig.setForTest(Brand.vidcombo);
      final pdfConvLicense = PremiumLicense(
        tier: PremiumTier.premium,
        licenseKey: 'VIDCOMBO-1234-5678-9abc-def0-1234-5678-9abc-def0',
        purchaseDate: DateTime(2026, 7, 17),
        lastVerified: DateTime(2026, 7, 17),
        paymentMethod: 'paypal_pdfconv',
        transactionId: '0cc27c14-f861-44df-a656-00a519d6f22b',
        billingCycle: BillingCycle.p30,
        expiresAt: DateTime(2026, 8, 16),
        isAutoRenew: false,
      );
      await datasource.saveMetadata(pdfConvLicense.toJson());
      await datasource.saveLicenseKey(pdfConvLicense.licenseKey!);
      var stripePricingReads = 0;

      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            premiumLocalDatasourceProvider.overrideWithValue(datasource),
            premiumLicenseServiceProvider.overrideWithValue(service),
            pricingPlansProvider.overrideWith((ref) async {
              stripePricingReads++;
              return const [];
            }),
            licenseInfoProvider.overrideWith((ref) async => null),
            devicesProvider.overrideWith((ref) async => const []),
            transactionsProvider.overrideWith((ref) async => const []),
          ],
          child: const MaterialApp(home: PremiumMembersScreen()),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(stripePricingReads, 0);
      expect(find.text(r'$10', findRichText: true), findsOneWidget);
      expect(find.text(r'$15', findRichText: true), findsOneWidget);
      expect(find.text(r'$25', findRichText: true), findsOneWidget);
      expect(find.text(r'$42', findRichText: true), findsOneWidget);
      expect(find.text(r'$9.90', findRichText: true), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              (widget.data ?? '').toLowerCase().contains('expireson'),
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              (widget.data ?? '').toLowerCase().contains('nextbilling'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
