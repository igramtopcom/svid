import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/config/brand_config.dart';

void main() {
  group('BrandConfig', () {
    test('init resolves a valid brand from BRAND env var', () {
      // Brand resolves at compile time via --dart-define=BRAND. Under the
      // default test run BRAND is unset → svid; under multi-brand CI
      // BRAND=vidcombo flips it. The invariant is that current is always
      // a non-null brand whose appName matches.
      BrandConfig.init();
      expect(BrandConfig.current.brand, isNotNull);
      expect(BrandConfig.current.appName, isNotEmpty);
      if (BrandConfig.current.brand == Brand.svid) {
        expect(BrandConfig.current.appName, 'Svid');
      } else if (BrandConfig.current.brand == Brand.vidcombo) {
        expect(BrandConfig.current.appName, 'VidCombo');
      }
    });

    test('Brand.fromString parses valid brands', () {
      expect(Brand.fromString('svid'), Brand.svid);
      expect(Brand.fromString('vidcombo'), Brand.vidcombo);
      expect(Brand.fromString('SVID'), Brand.svid);
      expect(Brand.fromString('VIDCOMBO'), Brand.vidcombo);
    });

    test('Brand.fromString defaults to svid for unknown', () {
      expect(Brand.fromString('unknown'), Brand.svid);
      expect(Brand.fromString(''), Brand.svid);
    });
  });

  group('SvidBrand', () {
    late BrandConfig config;

    setUp(() {
      config = const SvidBrand();
    });

    test('identity properties', () {
      expect(config.brand, Brand.svid);
      expect(config.appName, 'Svid');
      expect(config.databaseName, 'svid');
      expect(config.urlScheme, 'svid');
      expect(config.bundleId, 'com.svid.app');
      expect(config.methodChannelPrefix, 'com.svid.app');
    });

    test('backend properties', () {
      expect(config.backendType, BackendType.go);
      expect(config.backendBaseUrl, contains('api.svid.app'));
      expect(config.backendAppName, 'appSvid');
      expect(config.extractionApiUrl, contains('api.svid.app'));
      expect(config.websiteUrl, 'https://svid.app');
      expect(config.versionCheckUrl, isNotNull);
    });

    test('payment properties', () {
      expect(config.hasStripeCheckout, isTrue);
      expect(config.hasPdfConvPayPalCheckout, isFalse);
      expect(config.canAutoDownloadUpdate, isTrue);
    });

    test('all features are free (free-unlimited app)', () {
      expect(config.allFeaturesFree, isTrue);
    });

    test('license key validation — new SVID- format', () {
      expect(
        config.isValidLicenseKey(
          'SVID-1234-5678-9abc-def0-1234-5678-9abc-def0',
        ),
        isTrue,
      );
      expect(
        config.isValidLicenseKey(
          'SVID-ABCD-EF01-2345-6789-abcd-ef01-2345-6789',
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

    test('license key validation — rejects foreign SSVID- keys', () {
      // Svid is an independent product from the separate ssvid.app product.
      // It must NOT accept ssvid's SSVID- keys — only its own SVID- format.
      expect(
        config.isValidLicenseKey(
          'SSVID-1234-5678-9abc-def0-1234-5678-9abc-def0',
        ),
        isFalse,
      );
      expect(
        config.isValidLicenseKey(
          'SSVID-ABCD-EF01-2345-6789-abcd-ef01-2345-6789',
        ),
        isFalse,
      );
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

    test('keeps its paid tier (allFeaturesFree is false)', () {
      expect(config.allFeaturesFree, isFalse);
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

    test('colors differ from Svid', () {
      final svid = const SvidBrand();
      expect(config.colors.brand, isNot(equals(svid.colors.brand)));
      expect(
        config.darkColorScheme.primary,
        isNot(equals(svid.darkColorScheme.primary)),
      );
    });
  });

  group('Brand isolation', () {
    test('database names differ', () {
      expect(
        const SvidBrand().databaseName,
        isNot(equals(const VidComboBrand().databaseName)),
      );
    });

    test('regression: database names must NOT contain extension', () {
      // Bug c8bbba91 — databaseName included `.db` which then concatenated to
      // `svid.db.db` in app_database.dart, splitting users' data into orphan
      // files. The base class _resolve() asserts this invariant; this test
      // catches future regressions early via direct getter inspection.
      expect(const SvidBrand().databaseName, isNot(contains('.')));
      expect(const VidComboBrand().databaseName, isNot(contains('.')));
      expect(const SvidBrand().databaseName, equals('svid'));
      expect(const VidComboBrand().databaseName, equals('vidcombo'));
    });

    test('bundle IDs differ', () {
      expect(
        const SvidBrand().bundleId,
        isNot(equals(const VidComboBrand().bundleId)),
      );
    });

    test('URL schemes differ', () {
      expect(
        const SvidBrand().urlScheme,
        isNot(equals(const VidComboBrand().urlScheme)),
      );
    });

    test('backend types differ', () {
      expect(
        const SvidBrand().backendType,
        isNot(equals(const VidComboBrand().backendType)),
      );
    });

    test('license key patterns — brand separation', () {
      const svid = SvidBrand();
      const vidcombo = VidComboBrand();

      // VIDCOMBO- key should not validate as Svid
      const vidcomboGoKey = 'VIDCOMBO-1234-5678-9abc-def0-1234-5678-9abc-def0';
      expect(vidcombo.isValidLicenseKey(vidcomboGoKey), isTrue);
      expect(svid.isValidLicenseKey(vidcomboGoKey), isFalse);

      // VidCombo PHP key (32 hex) should not validate as Svid
      const vidcomboPhpKey = 'ABCDEF01234567890ABCDEF012345678';
      expect(vidcombo.isValidLicenseKey(vidcomboPhpKey), isTrue);
      expect(svid.isValidLicenseKey(vidcomboPhpKey), isFalse);

      // SVID- is Svid's primary format; it must NOT validate as VidCombo.
      const svidKey = 'SVID-1234-5678-9abc-def0-1234-5678-9abc-def0';
      expect(svid.isValidLicenseKey(svidKey), isTrue);
      expect(vidcombo.isValidLicenseKey(svidKey), isFalse);

      // Foreign SSVID- key (the separate ssvid product): Svid REJECTS it — Svid
      // is independent and only knows SVID-. VidCombo still accepts it via its
      // own pre-existing Go-legacy compat (unrelated to the svid rebrand).
      const foreignSsvidKey = 'SSVID-1234-5678-9abc-def0-1234-5678-9abc-def0';
      expect(svid.isValidLicenseKey(foreignSsvidKey), isFalse);
      expect(vidcombo.isValidLicenseKey(foreignSsvidKey), isTrue);
    });
  });
}
