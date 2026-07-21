import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/config/brand_config.dart';

void main() {
  group('BrandConfig', () {
    test('init resolves a valid brand from BRAND env var', () {
      // Brand resolves at compile time via --dart-define=BRAND. Under the
      // default test run BRAND is unset → ssvid; under multi-brand CI
      // BRAND=vidcombo flips it. The invariant is that current is always
      // a non-null brand whose appName matches.
      BrandConfig.init();
      expect(BrandConfig.current.brand, isNotNull);
      expect(BrandConfig.current.appName, isNotEmpty);
      if (BrandConfig.current.brand == Brand.ssvid) {
        expect(BrandConfig.current.appName, 'SSvid');
      } else if (BrandConfig.current.brand == Brand.vidcombo) {
        expect(BrandConfig.current.appName, 'VidCombo');
      }
    });

    test('Brand.fromString parses valid brands', () {
      expect(Brand.fromString('ssvid'), Brand.ssvid);
      expect(Brand.fromString('vidcombo'), Brand.vidcombo);
      expect(Brand.fromString('SSVID'), Brand.ssvid);
      expect(Brand.fromString('VIDCOMBO'), Brand.vidcombo);
    });

    test('Brand.fromString defaults to ssvid for unknown', () {
      expect(Brand.fromString('unknown'), Brand.ssvid);
      expect(Brand.fromString(''), Brand.ssvid);
    });
  });

  group('SSvidBrand', () {
    late BrandConfig config;

    setUp(() {
      config = const SSvidBrand();
    });

    test('identity properties', () {
      expect(config.brand, Brand.ssvid);
      expect(config.appName, 'SSvid');
      expect(config.databaseName, 'ssvid');
      expect(config.urlScheme, 'ssvid');
      expect(config.bundleId, 'com.ssvid.app');
      expect(config.methodChannelPrefix, 'com.ssvid.app');
    });

    test('backend properties', () {
      expect(config.backendType, BackendType.go);
      expect(config.backendBaseUrl, contains('api.ssvid.app'));
      expect(config.backendAppName, 'appSSvid');
      expect(config.extractionApiUrl, contains('api.ssvid.app'));
      expect(config.websiteUrl, 'https://ssvid.app');
      expect(config.versionCheckUrl, isNotNull);
    });

    test('payment properties', () {
      expect(config.hasStripeCheckout, isTrue);
      expect(config.hasPdfConvPayPalCheckout, isFalse);
      expect(config.canAutoDownloadUpdate, isTrue);
    });

    test('license key validation', () {
      expect(
        config.isValidLicenseKey(
          'SSVID-1234-5678-9abc-def0-1234-5678-9abc-def0',
        ),
        isTrue,
      );
      expect(
        config.isValidLicenseKey(
          'SSVID-ABCD-EF01-2345-6789-abcd-ef01-2345-6789',
        ),
        isTrue,
      );
      expect(config.isValidLicenseKey('invalid'), isFalse);
      expect(
        config.isValidLicenseKey('ABCDEF01234567890ABCDEF012345678'),
        isFalse,
      );
      expect(config.isValidLicenseKey(''), isFalse);
    });

    test('colors are non-null', () {
      expect(config.colors.brand.toARGB32(), isNonZero);
      expect(config.colors.accentHighlight.toARGB32(), isNonZero);
      expect(config.lightColorScheme.primary.toARGB32(), isNonZero);
      expect(config.darkColorScheme.primary.toARGB32(), isNonZero);
    });
  });

  group('VidComboBrand', () {
    late BrandConfig config;

    setUp(() {
      config = const VidComboBrand();
    });

    test('identity properties', () {
      expect(config.brand, Brand.vidcombo);
      expect(config.appName, 'VidCombo');
      expect(config.databaseName, 'vidcombo');
      expect(config.urlScheme, 'vidcombo');
      expect(config.bundleId, 'com.tinasoft.vidcombo');
      expect(config.methodChannelPrefix, 'com.tinasoft.vidcombo');
    });

    test('backend properties', () {
      expect(config.backendType, BackendType.php);
      expect(config.backendBaseUrl, contains('api.vidcombo.net'));
      expect(config.backendAppName, 'appVidcombo');
      expect(config.extractionApiUrl, contains('api.vidcombo.net'));
      expect(config.websiteUrl, 'https://vidcombo.net');
      expect(config.versionCheckUrl, isNull);
    });

    test('payment properties', () {
      expect(config.hasStripeCheckout, isTrue);
      expect(config.hasPdfConvPayPalCheckout, isTrue);
      expect(config.canAutoDownloadUpdate, isTrue);
    });

    test('license key validation — 32-char hex (PHP legacy)', () {
      expect(
        config.isValidLicenseKey('ABCDEF01234567890ABCDEF012345678'),
        isTrue,
      );
      expect(
        config.isValidLicenseKey('abcdef01234567890abcdef012345678'),
        isTrue,
      );
      expect(
        config.isValidLicenseKey('12345678901234567890123456789012'),
        isTrue,
      );
      expect(config.isValidLicenseKey('short'), isFalse);
      expect(config.isValidLicenseKey(''), isFalse);
      // 33 chars — too long
      expect(
        config.isValidLicenseKey('ABCDEF012345678901234567890123456'),
        isFalse,
      );
    });

    test(
      'AP-1 regression: lowercase 32-hex legacy key activates (import/gate parity)',
      () {
        // The import/credential path (startup_service) accepts `^[0-9A-Fa-f]{32}$`,
        // so the activation gate must also accept lowercase hex — otherwise an imported
        // lowercase legacy key persists then fails isValidLicenseKey silently and never activates.
        const lowercaseHexKey = 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6';
        expect(
          RegExp(r'^[0-9A-Fa-f]{32}$').hasMatch(lowercaseHexKey),
          isTrue,
          reason: 'sanity: this is the exact form startup_service imports',
        );
        expect(
          config.isValidLicenseKey(lowercaseHexKey),
          isTrue,
          reason:
              'activation gate must accept the same lowercase-hex key the importer admits',
        );
        // Mixed case (case-insensitive) also activates.
        expect(
          config.isValidLicenseKey('A1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6'),
          isTrue,
        );
      },
    );

    test('license key validation — VIDCOMBO-XXXX (Go backend)', () {
      expect(
        config.isValidLicenseKey(
          'VIDCOMBO-1234-5678-9abc-def0-1234-5678-9abc-def0',
        ),
        isTrue,
      );
      expect(
        config.isValidLicenseKey(
          'VIDCOMBO-aaaa-bbbb-cccc-dddd-eeee-ffff-0000-1111',
        ),
        isTrue,
      );
    });

    test('license key validation — legacy SSVID-XXXX (Go pre-separation)', () {
      // VidCombo also accepts legacy SSVID- keys created before brand separation
      expect(
        config.isValidLicenseKey(
          'SSVID-1234-5678-9abc-def0-1234-5678-9abc-def0',
        ),
        isTrue,
      );
    });

    test('colors differ from SSvid', () {
      final ssvid = const SSvidBrand();
      expect(config.colors.brand, isNot(equals(ssvid.colors.brand)));
      expect(
        config.darkColorScheme.primary,
        isNot(equals(ssvid.darkColorScheme.primary)),
      );
    });
  });

  group('Brand isolation', () {
    test('database names differ', () {
      expect(
        const SSvidBrand().databaseName,
        isNot(equals(const VidComboBrand().databaseName)),
      );
    });

    test('regression: database names must NOT contain extension', () {
      // Bug c8bbba91 — databaseName included `.db` which then concatenated to
      // `ssvid.db.db` in app_database.dart, splitting users' data into orphan
      // files. The base class _resolve() asserts this invariant; this test
      // catches future regressions early via direct getter inspection.
      expect(const SSvidBrand().databaseName, isNot(contains('.')));
      expect(const VidComboBrand().databaseName, isNot(contains('.')));
      expect(const SSvidBrand().databaseName, equals('ssvid'));
      expect(const VidComboBrand().databaseName, equals('vidcombo'));
    });

    test('bundle IDs differ', () {
      expect(
        const SSvidBrand().bundleId,
        isNot(equals(const VidComboBrand().bundleId)),
      );
    });

    test('URL schemes differ', () {
      expect(
        const SSvidBrand().urlScheme,
        isNot(equals(const VidComboBrand().urlScheme)),
      );
    });

    test('backend types differ', () {
      expect(
        const SSvidBrand().backendType,
        isNot(equals(const VidComboBrand().backendType)),
      );
    });

    test('license key patterns — brand separation', () {
      const ssvid = SSvidBrand();
      const vidcombo = VidComboBrand();

      // VIDCOMBO- key should not validate as SSvid
      const vidcomboGoKey = 'VIDCOMBO-1234-5678-9abc-def0-1234-5678-9abc-def0';
      expect(vidcombo.isValidLicenseKey(vidcomboGoKey), isTrue);
      expect(ssvid.isValidLicenseKey(vidcomboGoKey), isFalse);

      // VidCombo PHP key (32 hex) should not validate as SSvid
      const vidcomboPhpKey = 'ABCDEF01234567890ABCDEF012345678';
      expect(vidcombo.isValidLicenseKey(vidcomboPhpKey), isTrue);
      expect(ssvid.isValidLicenseKey(vidcomboPhpKey), isFalse);

      // SSVID- key validates for SSvid (primary) and VidCombo (legacy compat)
      const ssvidKey = 'SSVID-1234-5678-9abc-def0-1234-5678-9abc-def0';
      expect(ssvid.isValidLicenseKey(ssvidKey), isTrue);
      expect(vidcombo.isValidLicenseKey(ssvidKey), isTrue); // legacy compat
    });
  });
}
