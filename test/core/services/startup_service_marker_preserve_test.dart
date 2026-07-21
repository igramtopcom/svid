import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/services/startup_service.dart';

/// Unit tests for [StartupService.shouldWipeCredentialOnMarkerReset].
///
/// Regression guard for the 1.7.0 production bug where the VidCombo installer
/// marker handshake silently wiped Go-backend Stripe license keys on every
/// update. Three paid users reported license disappearance within 2 days of
/// 1.7.0 ship (PHP feedback #76, #79; Go ticket 847c59b7). The contract:
///
///   * Legacy 32-char hex PHP keys → wipe (installer is about to re-supply
///     them via `%TEMP%\vidcombo_migrated_key.txt`).
///   * Go-backend keys SVID-*/VIDCOMBO-* → preserve (Stripe-paid, no
///     migration handoff, silent removal demotes paying users).
///   * Null / empty / unknown format → fail-safe (null/empty = no-op wipe,
///     unknown = preserve so a future key format never silently breaks).
void main() {
  group('shouldWipeCredentialOnMarkerReset — preserve Go-backend keys', () {
    test('preserves a canonical VidCombo Go-backend key (48 chars)', () {
      // Format: VIDCOMBO-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX (48)
      const key = 'VIDCOMBO-A1B2-C3D4-E5F6-7890-ABCD-EF12-3456-7890';
      expect(key.length, 48);
      expect(
        StartupService.shouldWipeCredentialOnMarkerReset(key),
        isFalse,
        reason: 'Stripe-paid VidCombo users must keep their key across updates',
      );
    });

    test('preserves a canonical Svid Go-backend key (44 chars)', () {
      // Format: SVID-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX (44)
      const key = 'SVID-A1B2-C3D4-E5F6-7890-ABCD-EF12-3456-7890';
      expect(key.length, 44);
      expect(
        StartupService.shouldWipeCredentialOnMarkerReset(key),
        isFalse,
        reason: 'Svid Go-backend keys must survive the marker reset',
      );
    });
  });

  group(
    'Step B legacy-key import gate — shares the marker-wipe decision',
    () {
      // Step B of `_initializeVidCombo` reads
      // `%TEMP%\vidcombo_migrated_key.txt` (the legacy 32-hex PHP key the
      // Inno installer extracted from `settings1.gs`) and writes it into
      // the credential store. It MUST skip that write when a Go-backend
      // key is already present — otherwise Step A's careful preservation
      // is undone one line later by an unconditional overwrite.
      //
      // The fix is to reuse `shouldWipeCredentialOnMarkerReset` as the
      // gate, so both the wipe and the import path stay in lockstep.
      // These tests are the contract that locks that lockstep in place.

      test(
        'overwrites when existing slot is empty (canonical first-launch)',
        () {
          expect(
            StartupService.shouldWipeCredentialOnMarkerReset(null),
            isTrue,
          );
        },
      );

      test(
        'overwrites when existing slot holds a legacy 32-hex PHP key',
        () {
          // Two consecutive installer runs both supply migrated keys;
          // honouring the most recent one is the intended behavior for
          // the legacy migration path. shouldWipe must return true.
          const phpKey = 'A3B9EE755909C2E2836D4ED651834303';
          expect(
            StartupService.shouldWipeCredentialOnMarkerReset(phpKey),
            isTrue,
          );
        },
      );

      test(
        'skips overwrite when existing slot holds a Stripe VIDCOMBO key',
        () {
          // The production regression: paying user with Go-backend key
          // also has an old `settings1.gs` on disk; Step B would
          // overwrite the Stripe key with the legacy 32-hex. Gate must
          // refuse the overwrite.
          const goKey = 'VIDCOMBO-A1B2-C3D4-E5F6-7890-ABCD-EF12-3456-7890';
          expect(
            StartupService.shouldWipeCredentialOnMarkerReset(goKey),
            isFalse,
            reason: 'Step B reuses this gate; refusing the wipe = '
                'refusing the legacy-key import overwrite.',
          );
        },
      );

      test(
        'skips overwrite when existing slot holds a legacy SVID Go key',
        () {
          const goKey = 'SVID-A1B2-C3D4-E5F6-7890-ABCD-EF12-3456-7890';
          expect(
            StartupService.shouldWipeCredentialOnMarkerReset(goKey),
            isFalse,
          );
        },
      );

      test(
        'skips overwrite on unknown format (fail-safe)',
        () {
          // Future-format / corrupted entry — preserve so a schema change
          // never silently demotes paying users before tests catch it.
          expect(
            StartupService.shouldWipeCredentialOnMarkerReset(
              'FUTURE-FORMAT-2027-xyz',
            ),
            isFalse,
          );
        },
      );
    },
  );

  group('shouldWipeCredentialOnMarkerReset — wipe legacy PHP keys', () {
    test('wipes a canonical 32-char uppercase hex PHP key', () {
      // Old BLUEBYTE settings1.gs `lisenceKey` shape — installer will
      // re-supply via vidcombo_migrated_key.txt in STEP B.
      const key = 'A3B9EE755909C2E2836D4ED651834303';
      expect(key.length, 32);
      expect(
        StartupService.shouldWipeCredentialOnMarkerReset(key),
        isTrue,
      );
    });

    test('wipes a 32-char lowercase hex PHP key', () {
      const key = 'a3b9ee755909c2e2836d4ed651834303';
      expect(
        StartupService.shouldWipeCredentialOnMarkerReset(key),
        isTrue,
      );
    });

    test('wipes a 32-char mixed-case hex PHP key', () {
      const key = 'A3b9Ee755909C2e2836D4eD651834303';
      expect(
        StartupService.shouldWipeCredentialOnMarkerReset(key),
        isTrue,
      );
    });
  });

  group('shouldWipeCredentialOnMarkerReset — null and empty', () {
    test('returns true for null (nothing to lose, no-op in practice)', () {
      expect(
        StartupService.shouldWipeCredentialOnMarkerReset(null),
        isTrue,
      );
    });

    test('returns true for empty string', () {
      expect(
        StartupService.shouldWipeCredentialOnMarkerReset(''),
        isTrue,
      );
    });
  });

  group('shouldWipeCredentialOnMarkerReset — unknown format fail-safe', () {
    test('preserves a key that is not 32-hex and not Go-backend prefix', () {
      // Hypothetical future format / corrupted entry / partial key. The
      // fail-safe is "preserve unless we recognise it as legacy PHP" so a
      // schema change doesn't silently demote users before tests catch it.
      const key = 'UNKNOWN-FORMAT-2026-xyz';
      expect(
        StartupService.shouldWipeCredentialOnMarkerReset(key),
        isFalse,
      );
    });

    test('preserves a 32-char string that is NOT pure hex', () {
      // 32 chars but contains non-hex characters → not a PHP key.
      const key = 'ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ';
      expect(key.length, 32);
      expect(
        StartupService.shouldWipeCredentialOnMarkerReset(key),
        isFalse,
        reason: 'Length match alone is not enough — must also be hex',
      );
    });

    test('preserves SVID- prefix with wrong length (treat as unknown)', () {
      // Future-proofing: if Go backend changes key length, we should NOT
      // wipe based on prefix alone. Exact-length check is intentional.
      const key = 'SVID-TOO-SHORT';
      expect(key.length, isNot(44));
      expect(
        StartupService.shouldWipeCredentialOnMarkerReset(key),
        isFalse,
      );
    });

    test('preserves VIDCOMBO- prefix with wrong length', () {
      const key = 'VIDCOMBO-TOO-SHORT';
      expect(key.length, isNot(48));
      expect(
        StartupService.shouldWipeCredentialOnMarkerReset(key),
        isFalse,
      );
    });

    test('preserves a 31-char (off-by-one short) hex string', () {
      const key = 'A3B9EE755909C2E2836D4ED65183430'; // 31 chars
      expect(key.length, 31);
      expect(
        StartupService.shouldWipeCredentialOnMarkerReset(key),
        isFalse,
      );
    });

    test('preserves a 33-char (off-by-one long) hex string', () {
      const key = 'A3B9EE755909C2E2836D4ED6518343030'; // 33 chars
      expect(key.length, 33);
      expect(
        StartupService.shouldWipeCredentialOnMarkerReset(key),
        isFalse,
      );
    });
  });
}
