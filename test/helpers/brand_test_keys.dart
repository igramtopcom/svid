import 'package:svid/core/config/brand_config.dart';

/// Brand-aware license key fixtures for tests.
///
/// Svid expects `SVID-xxxx-xxxx-...` (44 chars).
/// VidCombo accepts 32-char hex (PHP) or `VIDCOMBO-xxxx-...` (Go).
/// Hard-coding either format in test fixtures fails the other brand under
/// `--dart-define=BRAND=...` so all premium-related tests pull from here.
class TestLicenseKeys {
  TestLicenseKeys._();

  /// A valid Go-backend key for the current brand.
  static String get valid {
    if (BrandConfig.current.brand == Brand.svid) {
      return 'SVID-1234-5678-9abc-def0-1234-5678-9abc-def0';
    }
    // VidCombo Go-backend key (new format)
    return 'VIDCOMBO-1234-5678-9abc-def0-1234-5678-9abc-def0';
  }

  /// A second valid Go-backend key for the current brand.
  static String get validAlt {
    if (BrandConfig.current.brand == Brand.svid) {
      return 'SVID-aaaa-bbbb-cccc-dddd-eeee-ffff-0000-1111';
    }
    return 'VIDCOMBO-aaaa-bbbb-cccc-dddd-eeee-ffff-0000-1111';
  }

  /// A third valid Go-backend key for the current brand.
  static String get validThird {
    if (BrandConfig.current.brand == Brand.svid) {
      return 'SVID-bbbb-cccc-dddd-eeee-ffff-0000-1111-2222';
    }
    return 'VIDCOMBO-bbbb-cccc-dddd-eeee-ffff-0000-1111-2222';
  }

  /// A valid VidCombo legacy PHP key (32 hex chars).
  static String get validPhpLegacy => 'abcdef0123456789abcdef0123456789';
}
