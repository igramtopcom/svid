import 'package:ssvid/core/config/brand_config.dart';

/// Brand-aware license key fixtures for tests.
///
/// SSvid expects `SSVID-xxxx-xxxx-...` (45 chars).
/// VidCombo accepts 32-char hex (PHP), `VIDCOMBO-xxxx-...` (Go), or legacy `SSVID-xxxx-...` (Go).
/// Hard-coding either format in test fixtures fails the other brand under
/// `--dart-define=BRAND=...` so all premium-related tests pull from here.
class TestLicenseKeys {
  TestLicenseKeys._();

  /// A valid Go-backend key for the current brand.
  static String get valid {
    if (BrandConfig.current.brand == Brand.ssvid) {
      return 'SSVID-1234-5678-9abc-def0-1234-5678-9abc-def0';
    }
    // VidCombo Go-backend key (new format)
    return 'VIDCOMBO-1234-5678-9abc-def0-1234-5678-9abc-def0';
  }

  /// A second valid Go-backend key for the current brand.
  static String get validAlt {
    if (BrandConfig.current.brand == Brand.ssvid) {
      return 'SSVID-aaaa-bbbb-cccc-dddd-eeee-ffff-0000-1111';
    }
    return 'VIDCOMBO-aaaa-bbbb-cccc-dddd-eeee-ffff-0000-1111';
  }

  /// A third valid Go-backend key for the current brand.
  static String get validThird {
    if (BrandConfig.current.brand == Brand.ssvid) {
      return 'SSVID-bbbb-cccc-dddd-eeee-ffff-0000-1111-2222';
    }
    return 'VIDCOMBO-bbbb-cccc-dddd-eeee-ffff-0000-1111-2222';
  }

  /// A valid VidCombo legacy PHP key (32 hex chars).
  static String get validPhpLegacy => 'abcdef0123456789abcdef0123456789';
}
