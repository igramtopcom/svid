import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svid/core/config/brand_config.dart';
import 'package:svid/core/services/secure_credential_store.dart';
import 'package:svid/features/premium/data/datasources/premium_local_datasource.dart';
import 'package:svid/features/premium/domain/entities/premium_feature.dart';
import 'package:svid/features/premium/domain/entities/premium_license.dart';
import 'package:svid/features/premium/domain/entities/premium_tier.dart';
import 'package:svid/features/premium/domain/services/premium_license_service.dart';

import '../../../../helpers/brand_test_keys.dart';

/// Fake secure storage for testing (in-memory)
class _FakeSecureStorage {
  final Map<String, String> _store = {};

  Future<String?> read({required String key}) async => _store[key];
  Future<void> write({required String key, required String value}) async =>
      _store[key] = value;
  Future<void> delete({required String key}) async => _store.remove(key);
}

/// Test datasource that uses fake secure storage
class _TestPremiumLocalDatasource extends PremiumLocalDatasource {
  final _FakeSecureStorage _fakeSecure;

  _TestPremiumLocalDatasource(SharedPreferences prefs)
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
  late _TestPremiumLocalDatasource datasource;
  late PremiumLicenseService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    datasource = _TestPremiumLocalDatasource(prefs);
    service = PremiumLicenseService(datasource);
  });

  group('PremiumLicenseService', () {
    group('getLicense', () {
      test('returns free license when no data stored', () async {
        final license = await service.getLicense();
        expect(license.isFree, true);
        expect(license.licenseKey, isNull);
      });

      test('returns stored premium license', () async {
        final now = DateTime(2026, 2, 28);
        await datasource.saveMetadata({
          'tier': 'premium',
          'purchaseDate': now.toIso8601String(),
          'lastVerified': now.toIso8601String(),
          'paymentMethod': 'stripe',
        });
        await datasource.saveLicenseKey(TestLicenseKeys.validAlt);

        final license = await service.getLicense();
        expect(license.isPremium, true);
        expect(license.licenseKey, TestLicenseKeys.validAlt);
        expect(license.paymentMethod, 'stripe');
      });
    });

    group('activateLicense', () {
      test('activates valid license key', () async {
        final now = DateTime(2026, 2, 28);
        final license = await service.activateLicense(
          TestLicenseKeys.valid,
          paymentMethod: 'stripe',
          transactionId: 'pi_test',
          now: now,
        );

        expect(license.isPremium, true);
        expect(license.licenseKey, TestLicenseKeys.valid);
        expect(license.purchaseDate, now);
        expect(license.lastVerified, now);
        expect(license.paymentMethod, 'stripe');
        expect(license.transactionId, 'pi_test');
      });

      test('persists license to storage', () async {
        await service.activateLicense(
          TestLicenseKeys.validAlt,
          now: DateTime(2026, 2, 28),
        );

        // Read back from storage
        final loaded = await service.getLicense();
        expect(loaded.isPremium, true);
        expect(loaded.licenseKey, TestLicenseKeys.validAlt);
      });

      test('persists one-time payment as non-renewing', () async {
        await service.activateLicense(
          TestLicenseKeys.valid,
          paymentMethod: 'paypal_pdfconv',
          billingCycle: BillingCycle.p30,
          isAutoRenew: false,
          now: DateTime(2026, 7, 17),
        );

        final loaded = await service.getLicense();
        expect(loaded.paymentMethod, 'paypal_pdfconv');
        expect(loaded.billingCycle, BillingCycle.p30);
        expect(loaded.isAutoRenew, isFalse);
      });

      test('throws FormatException for invalid key', () async {
        expect(
          () => service.activateLicense('invalid-key'),
          throwsA(isA<FormatException>()),
        );
      });

      test('throws for empty key', () async {
        expect(
          () => service.activateLicense(''),
          throwsA(isA<FormatException>()),
        );
      });

      test('throws for key with wrong prefix', () async {
        // 'ABCD-1234-5678-9ABC-DEF0' is malformed under both brands:
        // - SSvid: wrong prefix + wrong group count
        // - VidCombo: not a 32-char hex string
        expect(
          () => service.activateLicense('ABCD-1234-5678-9ABC-DEF0'),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('deactivateLicense', () {
      test('reverts to free tier', () async {
        await service.activateLicense(
          TestLicenseKeys.valid,
          now: DateTime(2026, 2, 28),
        );

        final result = await service.deactivateLicense();
        expect(result.isFree, true);
        expect(result.licenseKey, isNull);
      });

      test('clears storage completely', () async {
        await service.activateLicense(
          TestLicenseKeys.valid,
          now: DateTime(2026, 2, 28),
        );
        await service.deactivateLicense();

        final loaded = await service.getLicense();
        expect(loaded.isFree, true);
        expect(loaded.licenseKey, isNull);
      });
    });

    group('softDeactivateLicense', () {
      test('reverts to free tier but preserves stored key', () async {
        await service.activateLicense(
          TestLicenseKeys.valid,
          now: DateTime(2026, 2, 28),
        );

        final result = await service.softDeactivateLicense();
        expect(result.isFree, true);

        // Key must survive a soft demote so the user auto-recovers.
        expect(await datasource.getLicenseKey(), TestLicenseKeys.valid);
        // Metadata is cleared → getLicense() reports free.
        expect(datasource.getMetadata(), isNull);
        final loaded = await service.getLicense();
        expect(loaded.isFree, true);
      });
    });

    group('updateVerification', () {
      test('updates lastVerified timestamp', () async {
        await service.activateLicense(
          TestLicenseKeys.valid,
          now: DateTime(2026, 2, 20),
        );

        final later = DateTime(2026, 2, 28);
        final updated = await service.updateVerification(now: later);
        expect(updated.lastVerified, later);
        expect(updated.isPremium, true);
      });

      test('returns free license unchanged if not premium', () async {
        final result = await service.updateVerification();
        expect(result.isFree, true);
      });
    });

    group('updateLicenseMetadata', () {
      test('updates billingCycle and expiresAt on existing license', () async {
        // Activate without metadata (simulates manual key entry)
        await service.activateLicense(
          TestLicenseKeys.valid,
          now: DateTime(2026, 3, 28),
        );

        // Verify metadata is initially null
        var license = await service.getLicense();
        expect(license.billingCycle, isNull);
        expect(license.expiresAt, isNull);

        // Sync metadata from backend
        final expiresAt = DateTime(2126, 3, 28);
        final updated = await service.updateLicenseMetadata(
          billingCycle: BillingCycle.lifetime1,
          expiresAt: expiresAt,
          isAutoRenew: false,
          now: DateTime(2026, 3, 28, 12),
        );

        expect(updated.billingCycle, BillingCycle.lifetime1);
        expect(updated.expiresAt, expiresAt);
        expect(updated.isAutoRenew, false);
        expect(updated.lastVerified, DateTime(2026, 3, 28, 12));
        expect(updated.isPremium, true);

        // Verify persisted to storage
        license = await service.getLicense();
        expect(license.billingCycle, BillingCycle.lifetime1);
        expect(license.expiresAt, expiresAt);
        expect(license.isAutoRenew, false);
      });

      test('preserves existing fields when updating partially', () async {
        await service.activateLicense(
          TestLicenseKeys.valid,
          paymentMethod: 'stripe',
          billingCycle: BillingCycle.monthly,
          now: DateTime(2026, 3, 1),
        );

        // Update only expiresAt
        final updated = await service.updateLicenseMetadata(
          expiresAt: DateTime(2026, 4, 1),
        );

        expect(updated.billingCycle, BillingCycle.monthly); // preserved
        expect(updated.expiresAt, DateTime(2026, 4, 1)); // updated
        expect(updated.paymentMethod, 'stripe'); // preserved
      });

      test('returns free license unchanged if not premium', () async {
        final result = await service.updateLicenseMetadata(
          billingCycle: BillingCycle.yearly,
        );
        expect(result.isFree, true);
        expect(result.billingCycle, isNull);
      });
    });

    group('isFeatureAvailable', () {
      test('returns true for all features when premium', () {
        final license = PremiumLicense(
          tier: PremiumTier.premium,
          expiresAt: DateTime(2026, 7, 1),
        );
        for (final feature in PremiumFeature.values) {
          expect(
            service.isFeatureAvailable(
              feature,
              license,
              now: DateTime(2026, 6, 1),
            ),
            true,
          );
        }
      });

      test('returns false for all features when free', () {
        for (final feature in PremiumFeature.values) {
          expect(
            service.isFeatureAvailable(feature, PremiumLicense.free),
            false,
          );
        }
      });

      test('VidCombo null-expiry premium is trusted for at most 30 days', () {
        BrandConfig.setForTest(Brand.vidcombo);
        addTearDown(() => BrandConfig.setForTest(null));

        final license = PremiumLicense(
          tier: PremiumTier.premium,
          purchaseDate: DateTime(2026, 1),
          lastVerified: DateTime(2026, 1),
        );

        expect(
          service.isFeatureAvailable(
            PremiumFeature.unlimitedDownloads,
            license,
            now: DateTime(2026, 1, 30),
          ),
          true,
        );
        expect(
          service.isFeatureAvailable(
            PremiumFeature.unlimitedDownloads,
            license,
            now: DateTime(2026, 2, 1),
          ),
          false,
        );
      });

      test('VidCombo lifetime null-expiry premium remains perpetual', () {
        BrandConfig.setForTest(Brand.vidcombo);
        addTearDown(() => BrandConfig.setForTest(null));

        final license = PremiumLicense(
          tier: PremiumTier.premium,
          billingCycle: BillingCycle.lifetime,
          purchaseDate: DateTime(2026, 1),
          lastVerified: DateTime(2026, 1),
        );

        expect(
          service.isFeatureAvailable(
            PremiumFeature.unlimitedDownloads,
            license,
            now: DateTime(2027, 1),
          ),
          true,
        );
      });

      test('PDFConv fixed-term premium has no post-expiry grace', () {
        final expiresAt = DateTime.utc(2026, 7, 17);
        final license = PremiumLicense(
          tier: PremiumTier.premium,
          paymentMethod: 'paypal_pdfconv',
          billingCycle: BillingCycle.p7,
          expiresAt: expiresAt,
          isAutoRenew: false,
        );

        expect(
          service.isFeatureAvailable(
            PremiumFeature.unlimitedDownloads,
            license,
            now: expiresAt.add(const Duration(seconds: 1)),
          ),
          false,
        );
      });

      test('auto-renewing premium retains payment-retry grace', () {
        final expiresAt = DateTime.utc(2026, 7, 17);
        final license = PremiumLicense(
          tier: PremiumTier.premium,
          paymentMethod: 'stripe',
          billingCycle: BillingCycle.monthly,
          expiresAt: expiresAt,
          isAutoRenew: true,
        );

        expect(
          service.isFeatureAvailable(
            PremiumFeature.unlimitedDownloads,
            license,
            now: expiresAt.add(const Duration(days: 7)),
          ),
          true,
        );
        expect(
          service.isFeatureAvailable(
            PremiumFeature.unlimitedDownloads,
            license,
            now: expiresAt.add(const Duration(days: 8)),
          ),
          false,
        );
      });
    });

    group(
      'isValidLicenseKey (SSvid format)',
      () {
        // These tests assert the SSvid 9-group hex format. VidCombo uses a
        // 32-char hex string instead, so this group is brand-coupled and
        // only runs under BRAND=ssvid.
        test('valid key formats', () {
          expect(
            PremiumLicenseService.isValidLicenseKey(
              'SSVID-1234-5678-9abc-def0-1234-5678-9abc-def0',
            ),
            true,
          );
          expect(
            PremiumLicenseService.isValidLicenseKey(
              'SSVID-aaaa-bbbb-cccc-dddd-eeee-ffff-0000-1111',
            ),
            true,
          );
          expect(
            PremiumLicenseService.isValidLicenseKey(
              'SSVID-0000-0000-0000-0000-0000-0000-0000-0000',
            ),
            true,
          );
        });

        test('invalid key formats', () {
          expect(PremiumLicenseService.isValidLicenseKey(''), false);
          expect(PremiumLicenseService.isValidLicenseKey('SSVID-'), false);
          expect(
            PremiumLicenseService.isValidLicenseKey('SSVID-1234-5678-9ABC'),
            false,
          ); // too few groups
          expect(
            PremiumLicenseService.isValidLicenseKey(
              'SSVID-1234-5678-9ABC-DEF0',
            ),
            false,
          ); // only 4 groups (old format)
          expect(
            PremiumLicenseService.isValidLicenseKey(
              'ABCD-1234-5678-9abc-def0-1234-5678-9abc-def0',
            ),
            false,
          ); // wrong prefix
          expect(
            PremiumLicenseService.isValidLicenseKey(
              'SSVID-ZZZZ-5678-9abc-def0-1234-5678-9abc-def0',
            ),
            false,
          ); // non-hex Z
          expect(
            PremiumLicenseService.isValidLicenseKey(
              'SSVID-12345-5678-9abc-def0-1234-5678-9abc-def0',
            ),
            false,
          ); // 5 digits in first group
        });
      },
      skip:
          BrandConfig.current.brand != Brand.svid
              ? 'SSvid-specific license format'
              : null,
    );

    group(
      'isValidLicenseKey (VidCombo format)',
      () {
        // VidCombo accepts 32-char hex (PHP), VIDCOMBO-XXXX (Go), and
        // legacy SSVID-XXXX (Go pre-separation). Brand-coupled.
        test('valid 32-char hex keys (PHP legacy)', () {
          expect(
            PremiumLicenseService.isValidLicenseKey(
              'abcdef0123456789abcdef0123456789',
            ),
            true,
          );
          expect(
            PremiumLicenseService.isValidLicenseKey(
              '11112222333344445555666677778888',
            ),
            true,
          );
          expect(
            PremiumLicenseService.isValidLicenseKey(
              'ABCDEF0123456789ABCDEF0123456789',
            ),
            true,
          );
        });

        test('valid 32-char uppercase alphanumeric keys (PHP manual)', () {
          expect(
            PremiumLicenseService.isValidLicenseKey(
              'ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ',
            ),
            true,
          );
          expect(
            PremiumLicenseService.isValidLicenseKey(
              'OXPS0123456789ABCDEFOXPS01234567',
            ),
            true,
          );
        });

        test('valid VIDCOMBO-XXXX keys (Go backend)', () {
          expect(
            PremiumLicenseService.isValidLicenseKey(
              'VIDCOMBO-1234-5678-9abc-def0-1234-5678-9abc-def0',
            ),
            true,
          );
          expect(
            PremiumLicenseService.isValidLicenseKey(
              'VIDCOMBO-aaaa-bbbb-cccc-dddd-eeee-ffff-0000-1111',
            ),
            true,
          );
        });

        test('valid SSVID-XXXX keys (Go legacy compat)', () {
          expect(
            PremiumLicenseService.isValidLicenseKey(
              'SSVID-1234-5678-9abc-def0-1234-5678-9abc-def0',
            ),
            true,
          );
        });

        test('invalid key formats', () {
          expect(PremiumLicenseService.isValidLicenseKey(''), false);
          expect(PremiumLicenseService.isValidLicenseKey('short'), false);
          expect(
            PremiumLicenseService.isValidLicenseKey('a' * 31),
            false,
            reason: '31 chars — wrong length',
          );
          expect(
            PremiumLicenseService.isValidLicenseKey('a' * 33),
            false,
            reason: '33 chars — wrong length',
          );
          expect(
            PremiumLicenseService.isValidLicenseKey('${'a' * 31}-'),
            false,
            reason: 'contains a non-alphanumeric character',
          );
        });

        test('permissive 32-char gate accepts any-case alphanumeric '
            '(server checkkey.php is the real validator, not the client)', () {
          // Narrowing this to hex/uppercase-only would risk locking out a paying
          // user whose real PHP key uses another form (AP-1). A doomed key just
          // fails server-side, so the client gate stays permissive on purpose.
          expect(
            PremiumLicenseService.isValidLicenseKey('z' * 32),
            true,
            reason: '32 lowercase letters must pass the local gate',
          );
          expect(
            PremiumLicenseService.isValidLicenseKey(
              'AbCdEf0123456789aBcDeF0123456789',
            ),
            true,
            reason: 'mixed-case alphanumeric must pass the local gate',
          );
        });
      },
      skip:
          BrandConfig.current.brand != Brand.vidcombo
              ? 'VidCombo-specific license format'
              : null,
    );
  });

  group('PremiumLocalDatasource', () {
    test('getMetadata returns null when empty', () {
      expect(datasource.getMetadata(), isNull);
    });

    test('saveMetadata and getMetadata round-trip', () async {
      final metadata = {'tier': 'premium', 'paymentMethod': 'crypto'};
      await datasource.saveMetadata(metadata);

      final loaded = datasource.getMetadata();
      expect(loaded, isNotNull);
      expect(loaded!['tier'], 'premium');
      expect(loaded['paymentMethod'], 'crypto');
    });

    test('getMetadata handles corrupt JSON gracefully', () async {
      await prefs.setString('premium_license_metadata', 'not valid json');
      expect(datasource.getMetadata(), isNull);
    });

    test('clearAll removes metadata and key', () async {
      await datasource.saveMetadata({'tier': 'premium'});
      await datasource.saveLicenseKey(TestLicenseKeys.valid);

      await datasource.clearAll();

      expect(datasource.getMetadata(), isNull);
      // _TestPremiumLocalDatasource overrides clearAll via deleteLicenseKey
      // which operates on _FakeSecureStorage, so this should be null
      expect(await datasource.getLicenseKey(), isNull);
    });

    test('clearMetadataKeepKey removes metadata but keeps key', () async {
      await datasource.saveMetadata({'tier': 'premium'});
      await datasource.saveLicenseKey(TestLicenseKeys.valid);

      await datasource.clearMetadataKeepKey();

      expect(datasource.getMetadata(), isNull);
      // Key is preserved for auto-recovery.
      expect(await datasource.getLicenseKey(), TestLicenseKeys.valid);
    });
  });

  group('hasStoredKey — startup self-heal gate (P1)', () {
    test('false when nothing stored', () async {
      expect(await service.hasStoredKey(), false);
    });

    test('true after activation', () async {
      await service.activateLicense(TestLicenseKeys.valid);
      expect(await service.hasStoredKey(), true);
    });

    test(
      'SOFT demote keeps key -> hasStoredKey true (self-heal may recover)',
      () async {
        await service.activateLicense(TestLicenseKeys.valid);
        await service.softDeactivateLicense();
        expect((await service.getLicense()).isFree, true);
        expect(
          await service.hasStoredKey(),
          true,
          reason: 'soft demote preserves the key for auto-recovery',
        );
      },
    );

    test('explicit Deactivate (clearAll) removes key -> hasStoredKey false '
        '(startup self-heal must NOT re-promote)', () async {
      await service.activateLicense(TestLicenseKeys.valid);
      await service.deactivateLicense();
      expect(
        await service.hasStoredKey(),
        false,
        reason:
            'full wipe deletes the key -> self-heal gate skips, so an '
            'explicit user Deactivate is not reversed on next startup',
      );
    });
  });
}
