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
import 'package:svid/features/premium/presentation/providers/premium_providers.dart';
import 'package:svid/features/premium/presentation/screens/premium_welcome_screen.dart';
import 'package:svid/features/settings/presentation/providers/settings_provider.dart';

class _MemoryPremiumDatasource extends PremiumLocalDatasource {
  String? _licenseKey;

  _MemoryPremiumDatasource(SharedPreferences prefs)
    : super(prefs, SecureCredentialStore(prefs));

  @override
  Future<String?> getLicenseKey() async => _licenseKey;

  @override
  Future<void> saveLicenseKey(String key) async => _licenseKey = key;

  @override
  Future<void> deleteLicenseKey() async => _licenseKey = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => BrandConfig.setForTest(null));

  testWidgets('one-time PDFConv plan uses expiry copy instead of renewal', (
    tester,
  ) async {
    BrandConfig.setForTest(Brand.vidcombo);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final datasource = _MemoryPremiumDatasource(prefs);
    final service = PremiumLicenseService(datasource);
    const licenseKey = 'VIDCOMBO-1234-5678-9abc-def0-1234-5678-9abc-def0';
    final license = PremiumLicense(
      tier: PremiumTier.premium,
      licenseKey: licenseKey,
      purchaseDate: DateTime.utc(2026, 7, 17),
      lastVerified: DateTime.utc(2026, 7, 17),
      paymentMethod: 'paypal_pdfconv',
      transactionId: '0cc27c14-f861-44df-a656-00a519d6f22b',
      billingCycle: BillingCycle.p30,
      expiresAt: DateTime.utc(2026, 8, 16),
      isAutoRenew: false,
    );
    await datasource.saveMetadata(license.toJson());
    await datasource.saveLicenseKey(licenseKey);
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          premiumLocalDatasourceProvider.overrideWithValue(datasource),
          premiumLicenseServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(home: PremiumWelcomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('PayPal'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && (widget.data ?? '').contains('expiresOn'),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && (widget.data ?? '').contains('renewsOn'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
