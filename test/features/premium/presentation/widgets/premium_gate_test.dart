import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssvid/core/services/secure_credential_store.dart';
import 'package:ssvid/features/premium/data/datasources/premium_local_datasource.dart';
import 'package:ssvid/features/premium/domain/entities/premium_feature.dart';
import 'package:ssvid/features/premium/domain/services/premium_license_service.dart';
import 'package:ssvid/features/premium/presentation/providers/premium_providers.dart';
import 'package:ssvid/features/premium/presentation/widgets/premium_gate.dart';
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

  Widget buildTestApp({
    required Widget child,
    List<Override> overrides = const [],
  }) {
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        premiumLocalDatasourceProvider.overrideWithValue(datasource),
        premiumLicenseServiceProvider.overrideWithValue(service),
        ...overrides,
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: child,
          ),
        ),
      ),
    );
  }

  group('PremiumGate', () {
    testWidgets('shows child normally when premium', (tester) async {
      // Activate premium first
      await service.activateLicense(TestLicenseKeys.valid);

      await tester.pumpWidget(buildTestApp(
        child: const PremiumGate(
          feature: PremiumFeature.advancedAnalytics,
          child: Text('Dashboard Content'),
        ),
      ));

      // Wait for async license load
      await tester.pumpAndSettle();

      expect(find.text('Dashboard Content'), findsOneWidget);
      // Lock icon should NOT be present
      expect(find.byIcon(Icons.lock_rounded), findsNothing);
    });

    testWidgets('shows lock overlay when free tier', (tester) async {
      await tester.pumpWidget(buildTestApp(
        child: const PremiumGate(
          feature: PremiumFeature.advancedAnalytics,
          child: Text('Dashboard Content'),
        ),
      ));

      await tester.pumpAndSettle();

      // Lock icon should be present
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      // Upgrade button (MaterialButton with gradient CTA) should be visible
      expect(find.byWidgetPredicate((w) => w is MaterialButton), findsOneWidget);
    });

    testWidgets('blurred child is still rendered behind overlay',
        (tester) async {
      await tester.pumpWidget(buildTestApp(
        child: const PremiumGate(
          feature: PremiumFeature.highQuality4K,
          child: Text('Sync Content'),
        ),
      ));

      await tester.pumpAndSettle();

      // Child text should still be in the widget tree (blurred but present)
      expect(find.text('Sync Content'), findsOneWidget);
      // ImageFiltered should be present (blur effect on child)
      expect(find.byType(ImageFiltered), findsOneWidget);
      // Opacity should be present (dimmed effect)
      expect(find.byType(Opacity), findsOneWidget);
    });

    testWidgets('shows custom featureLabel on overlay', (tester) async {
      await tester.pumpWidget(buildTestApp(
        child: const PremiumGate(
          feature: PremiumFeature.advancedPlayer,
          featureLabel: 'Custom Label',
          child: Text('Locked Content'),
        ),
      ));

      await tester.pumpAndSettle();

      expect(find.text('Custom Label'), findsOneWidget);
    });

    testWidgets('tapping upgrade button shows UpgradePromptDialog',
        (tester) async {
      await tester.pumpWidget(buildTestApp(
        child: const PremiumGate(
          feature: PremiumFeature.browserShield,
          child: Text('Vault Content'),
        ),
      ));

      await tester.pumpAndSettle();

      // Tap the upgrade FilledButton (FilledButton.icon creates _FilledButtonWithIcon,
      // so find.byType(FilledButton) won't match — use widgetPredicate instead)
      await tester.tap(find.byWidgetPredicate((w) => w is MaterialButton));
      await tester.pumpAndSettle();

      // Dialog should appear
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('child is interactive when premium', (tester) async {
      await service.activateLicense(TestLicenseKeys.valid);
      var tapped = false;

      await tester.pumpWidget(buildTestApp(
        child: PremiumGate(
          feature: PremiumFeature.scheduledDownloads,
          child: ElevatedButton(
            onPressed: () => tapped = true,
            child: const Text('Action'),
          ),
        ),
      ));

      await tester.pumpAndSettle();
      await tester.tap(find.text('Action'));

      expect(tapped, true);
    });

    testWidgets('child is NOT interactive when free (IgnorePointer)',
        (tester) async {
      var tapped = false;

      await tester.pumpWidget(buildTestApp(
        child: PremiumGate(
          feature: PremiumFeature.scheduledDownloads,
          child: ElevatedButton(
            onPressed: () => tapped = true,
            child: const Text('Action'),
          ),
        ),
      ));

      await tester.pumpAndSettle();

      // The child is behind IgnorePointer, so tapping should not trigger
      // Use warnIfMissed: false since it's behind the overlay
      await tester.tap(find.text('Action'), warnIfMissed: false);

      expect(tapped, false);
    });
  });
}
