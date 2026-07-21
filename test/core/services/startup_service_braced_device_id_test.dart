import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/core/services/startup_service.dart';

/// Unit tests for [StartupService.bracedDeviceIdFor] — the BLUEBYTE legacy
/// device-id format derivation that BOTH the VidCombo SYNC path and the
/// background-refresh path (FIX #5) now share before any demotion.
///
/// The legacy BLUEBYTE VidCombo registered devices under the Windows GUID
/// format `{UPPERCASE-GUID}` (with braces), while the raw platform UUID is
/// lowercase-without-braces. Without the braced retry, a legacy braced-device
/// subscriber's lowercase id returns non-premium from PHP, so the bg refresh
/// would deterministically demote the same device that a cache hit just showed
/// as premium — every single cache-hit boot. Pinning the format here keeps the
/// two recovery paths in lockstep (mirror parity).
void main() {
  group('StartupService.bracedDeviceIdFor', () {
    test('lowercase raw id → braced + uppercased', () {
      expect(
        StartupService.bracedDeviceIdFor(
          '985168ae-f117-4744-b5f5-c57609d69276',
        ),
        '{985168AE-F117-4744-B5F5-C57609D69276}',
      );
    });

    test('mixed-case raw id → fully uppercased + braced', () {
      expect(
        StartupService.bracedDeviceIdFor(
          '985168Ae-F117-4744-b5F5-c57609D69276',
        ),
        '{985168AE-F117-4744-B5F5-C57609D69276}',
      );
    });

    test('already-braced id → null (no pointless retry against same id)', () {
      // The first checkkey already used this exact id; retrying it is a wasted
      // round-trip and would never recover anything new.
      expect(
        StartupService.bracedDeviceIdFor(
          '{985168AE-F117-4744-B5F5-C57609D69276}',
        ),
        isNull,
      );
    });

    test('null raw id → null', () {
      expect(StartupService.bracedDeviceIdFor(null), isNull);
    });

    test('empty raw id → null', () {
      expect(StartupService.bracedDeviceIdFor(''), isNull);
    });

    test('braces + uppercase are both load-bearing (case-sensitive backend)', () {
      // The PHP backend may use a case-sensitive MySQL collation / utf8_bin
      // column, so the recovered form must be uppercase AND brace-wrapped.
      final result = StartupService.bracedDeviceIdFor('abc-def');
      expect(result, startsWith('{'));
      expect(result, endsWith('}'));
      expect(result, '{ABC-DEF}');
    });
  });
}
