import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssvid/core/services/secure_credential_store.dart';
import 'package:ssvid/features/premium/data/datasources/premium_local_datasource.dart';
import 'package:ssvid/features/premium/domain/entities/premium_feature.dart';
import 'package:ssvid/features/premium/domain/entities/premium_license.dart';
import 'package:ssvid/features/premium/domain/services/premium_license_service.dart';
import 'package:ssvid/features/premium/presentation/providers/premium_providers.dart';
import 'package:ssvid/features/settings/presentation/providers/settings_provider.dart';

import '../../../../helpers/brand_test_keys.dart';

/// Fake secure storage for testing
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
  late SharedPreferences prefs;
  late _TestDatasource datasource;
  late PremiumLicenseService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    datasource = _TestDatasource(prefs);
    service = PremiumLicenseService(datasource);
  });

  group('PremiumNotifier', () {
    test('starts with free license', () async {
      final notifier = PremiumNotifier(service);
      // Initial state before load
      expect(notifier.state.isFree, true);

      // Wait for async load
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.isFree, true);
    });

    test('activateLicense updates state to premium', () async {
      final notifier = PremiumNotifier(service);
      await Future<void>.delayed(Duration.zero);

      await notifier.activateLicense(
        TestLicenseKeys.valid,
        paymentMethod: 'stripe',
      );

      expect(notifier.state.isPremium, true);
      expect(notifier.state.licenseKey, TestLicenseKeys.valid);
    });

    test(
      'backend re-verification preserves PDFConv payment metadata',
      () async {
        final notifier = PremiumNotifier(service);
        await Future<void>.delayed(Duration.zero);
        final originalExpiry = DateTime.utc(2026, 8, 16);
        await notifier.activateLicense(
          TestLicenseKeys.valid,
          paymentMethod: 'paypal_pdfconv',
          transactionId: '0cc27c14-f861-44df-a656-00a519d6f22b',
          billingCycle: BillingCycle.p30,
          expiresAt: originalExpiry,
          isAutoRenew: false,
        );

        final refreshedExpiry = DateTime.utc(2026, 8, 17);
        await notifier.activateLicenseFromBackend(
          TestLicenseKeys.valid,
          billingCycle: 'p30',
          expiresAt: refreshedExpiry,
          isAutoRenew: false,
        );

        expect(notifier.state.paymentMethod, 'paypal_pdfconv');
        expect(
          notifier.state.transactionId,
          '0cc27c14-f861-44df-a656-00a519d6f22b',
        );
        expect(notifier.state.billingCycle, BillingCycle.p30);
        expect(notifier.state.expiresAt, refreshedExpiry);
        expect(notifier.state.isAutoRenew, isFalse);
      },
    );

    test('deactivateLicense reverts to free', () async {
      final notifier = PremiumNotifier(service);
      await Future<void>.delayed(Duration.zero);

      await notifier.activateLicense(TestLicenseKeys.valid);
      await notifier.deactivateLicense();

      expect(notifier.state.isFree, true);
      expect(notifier.state.licenseKey, isNull);
    });

    test('updateVerification updates lastVerified', () async {
      final notifier = PremiumNotifier(service);
      await Future<void>.delayed(Duration.zero);

      await notifier.activateLicense(TestLicenseKeys.valid);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await notifier.updateVerification();

      // lastVerified should be updated
      expect(notifier.state.lastVerified, isNotNull);
    });

    test('refresh reloads from storage', () async {
      final notifier = PremiumNotifier(service);
      await Future<void>.delayed(Duration.zero);

      // Activate externally
      await service.activateLicense(TestLicenseKeys.validAlt);

      // Notifier state is stale
      expect(notifier.state.isFree, true);

      // Refresh reloads
      await notifier.refresh();
      expect(notifier.state.isPremium, true);
    });
  });

  group('Provider integration', () {
    test('isPremiumProvider returns false for free', () async {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          premiumLocalDatasourceProvider.overrideWithValue(datasource),
          premiumLicenseServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);

      // Keep alive
      container.listen(premiumLicenseProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);

      expect(container.read(isPremiumProvider), false);
    });

    test('isPremiumProvider returns true inside expiry grace window', () async {
      await service.activateLicense(
        TestLicenseKeys.valid,
        expiresAt: DateTime.now().subtract(const Duration(days: 3)),
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          premiumLocalDatasourceProvider.overrideWithValue(datasource),
          premiumLicenseServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);

      container.listen(premiumLicenseProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);

      expect(container.read(premiumLicenseProvider).isExpired, true);
      expect(container.read(isPremiumProvider), true);
    });

    test('backend-verified premium can activate without license key', () async {
      final notifier = PremiumNotifier(service);
      await Future<void>.delayed(Duration.zero);

      await notifier.activateVerifiedPremiumFromBackend();

      expect(notifier.state.isPremium, true);
      expect(notifier.state.licenseKey, isNull);
      final persisted = await service.getLicense();
      expect(persisted.isPremium, true);
      expect(persisted.licenseKey, isNull);
    });

    test('premiumFeatureProvider returns false for free tier', () async {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          premiumLocalDatasourceProvider.overrideWithValue(datasource),
          premiumLicenseServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);

      container.listen(premiumLicenseProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);

      for (final feature in PremiumFeature.values) {
        expect(container.read(premiumFeatureProvider(feature)), false);
      }
    });
  });

  group('PremiumFeature enum', () {
    test('has 13 values', () {
      expect(PremiumFeature.values.length, 13);
    });

    test('contains all expected features', () {
      final names = PremiumFeature.values.map((e) => e.name).toSet();
      expect(names.contains('unlimitedDownloads'), true);
      expect(names.contains('highQuality4K'), true);
      expect(names.contains('extendedConcurrent'), true);
      expect(names.contains('batchDownload'), true);
      expect(names.contains('advancedPlayer'), true);
      expect(names.contains('browserShield'), true);
      expect(names.contains('scheduledDownloads'), true);
      expect(names.contains('bandwidthControl'), true);
      expect(names.contains('smartCollections'), true);
      expect(names.contains('advancedAnalytics'), true);
      expect(names.contains('batchImport'), true);
      expect(names.contains('prioritySupport'), true);
      expect(names.contains('mediaConverter'), true);
    });
  });
}
