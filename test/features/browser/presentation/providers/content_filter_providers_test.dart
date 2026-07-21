import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssvid/features/browser/presentation/providers/content_filter_providers.dart';

void main() {
  group('content_filter_providers', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('adBlockEnabledProvider defaults to true', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final value = container.read(adBlockEnabledProvider);
      expect(value, isTrue);
    });

    test('popupBlockEnabledProvider defaults to true', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final value = container.read(popupBlockEnabledProvider);
      expect(value, isTrue);
    });

    test('adBlockServiceProvider returns AdBlockService', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(adBlockServiceProvider);
      expect(service, isNotNull);
    });

    test('popupBlockerServiceProvider returns PopupBlockerService', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(popupBlockerServiceProvider);
      expect(service, isNotNull);
    });

    test('adBlockEnabledProvider toggle flips state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(adBlockEnabledProvider), isTrue);

      await container.read(adBlockEnabledProvider.notifier).toggle();
      expect(container.read(adBlockEnabledProvider), isFalse);

      await container.read(adBlockEnabledProvider.notifier).toggle();
      expect(container.read(adBlockEnabledProvider), isTrue);
    });

    test('popupBlockEnabledProvider toggle flips state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(popupBlockEnabledProvider), isTrue);

      await container.read(popupBlockEnabledProvider.notifier).toggle();
      expect(container.read(popupBlockEnabledProvider), isFalse);
    });

    test('adBlockEnabledProvider setValue sets state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(adBlockEnabledProvider.notifier).setValue(false);
      expect(container.read(adBlockEnabledProvider), isFalse);

      await container.read(adBlockEnabledProvider.notifier).setValue(true);
      expect(container.read(adBlockEnabledProvider), isTrue);
    });

    // ==================== NEW PROVIDERS ====================

    test('phishingDetectionEnabledProvider defaults to true', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(phishingDetectionEnabledProvider), isTrue);
    });

    test('httpsEnforcementEnabledProvider defaults to true', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(httpsEnforcementEnabledProvider), isTrue);
    });

    test('fingerprintProtectionEnabledProvider defaults to true', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(fingerprintProtectionEnabledProvider), isTrue);
    });

    test('phishingDetectionServiceProvider returns service', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(phishingDetectionServiceProvider);
      expect(service, isNotNull);
    });

    test('httpsEnforcementServiceProvider returns service', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(httpsEnforcementServiceProvider);
      expect(service, isNotNull);
    });

    test('fingerprintProtectionServiceProvider returns service', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(fingerprintProtectionServiceProvider);
      expect(service, isNotNull);
    });

    test('phishingDetectionEnabledProvider toggle flips state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(phishingDetectionEnabledProvider), isTrue);
      await container
          .read(phishingDetectionEnabledProvider.notifier)
          .toggle();
      expect(container.read(phishingDetectionEnabledProvider), isFalse);
    });

    test('httpsEnforcementEnabledProvider toggle flips state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(httpsEnforcementEnabledProvider), isTrue);
      await container
          .read(httpsEnforcementEnabledProvider.notifier)
          .toggle();
      expect(container.read(httpsEnforcementEnabledProvider), isFalse);
    });

    test('fingerprintProtectionEnabledProvider toggle flips state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(fingerprintProtectionEnabledProvider), isTrue);
      await container
          .read(fingerprintProtectionEnabledProvider.notifier)
          .toggle();
      expect(container.read(fingerprintProtectionEnabledProvider), isFalse);
    });
  });
}
