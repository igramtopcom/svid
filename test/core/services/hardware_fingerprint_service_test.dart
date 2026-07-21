import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/core/services/hardware_fingerprint_service.dart';

void main() {
  group('HardwareFingerprintService', () {
    group('generateLegacyFingerprint', () {
      test('produces deterministic output', () {
        final id1 = HardwareFingerprintService.generateLegacyFingerprint();
        final id2 = HardwareFingerprintService.generateLegacyFingerprint();
        expect(id1, equals(id2));
      });

      test('starts with desktop_ prefix', () {
        final id = HardwareFingerprintService.generateLegacyFingerprint();
        expect(id, startsWith('desktop_'));
      });

      test('contains hostname', () {
        final id = HardwareFingerprintService.generateLegacyFingerprint();
        expect(id, contains(Platform.localHostname));
      });

      test('contains 8-char hex hash', () {
        final id = HardwareFingerprintService.generateLegacyFingerprint();
        // Format: desktop_{8hexchars}_{hostname}
        final match = RegExp(r'^desktop_[0-9a-f]{8}_').hasMatch(id);
        expect(match, isTrue, reason: 'Legacy ID should match desktop_{hex8}_{hostname} format');
      });
    });

    group('generateFingerprint', () {
      test('produces deterministic output', () async {
        final id1 = await HardwareFingerprintService.generateFingerprint();
        final id2 = await HardwareFingerprintService.generateFingerprint();
        expect(id1, equals(id2));
      });

      test('starts with desktop_v2_ prefix', () async {
        final id = await HardwareFingerprintService.generateFingerprint();
        // May be null on CI without hardware access, but on real machine should work
        if (id != null) {
          expect(id, startsWith('desktop_v2_'));
        }
      });

      test('contains 16-char hex suffix', () async {
        final id = await HardwareFingerprintService.generateFingerprint();
        if (id != null) {
          final match = RegExp(r'^desktop_v2_[0-9a-f]{16}$').hasMatch(id);
          expect(match, isTrue, reason: 'Strong ID should match desktop_v2_{hex16} format');
        }
      });

      test('differs from legacy fingerprint', () async {
        final strong = await HardwareFingerprintService.generateFingerprint();
        final legacy = HardwareFingerprintService.generateLegacyFingerprint();
        if (strong != null) {
          expect(strong, isNot(equals(legacy)));
        }
      });

      test('is stable across multiple calls (not time-dependent)', () async {
        final results = <String?>[];
        for (var i = 0; i < 5; i++) {
          results.add(await HardwareFingerprintService.generateFingerprint());
        }
        // All should be identical
        expect(results.toSet().length, 1);
      });
    });

    group('platform UUID extraction', () {
      test('returns non-null on macOS', () async {
        final id = await HardwareFingerprintService.generateFingerprint();
        if (Platform.isMacOS) {
          expect(id, isNotNull, reason: 'macOS IOPlatformUUID should always be available');
          expect(id, isNotEmpty);
        }
      },
        skip: !Platform.isMacOS ? 'macOS-only test' : null,
      );

      test('returns non-null on Windows', () async {
        final id = await HardwareFingerprintService.generateFingerprint();
        if (Platform.isWindows) {
          expect(id, isNotNull, reason: 'Windows MachineGuid should always be available');
        }
      },
        skip: !Platform.isWindows ? 'Windows-only test' : null,
      );

      test('returns non-null on Linux', () async {
        final id = await HardwareFingerprintService.generateFingerprint();
        if (Platform.isLinux) {
          // /etc/machine-id exists on most Linux distros
          if (await File('/etc/machine-id').exists()) {
            expect(id, isNotNull);
          }
        }
      },
        skip: !Platform.isLinux ? 'Linux-only test' : null,
      );
    });

    group('dual-send migration logic', () {
      test('legacy and strong fingerprints are both valid for dual-send', () async {
        final legacy = HardwareFingerprintService.generateLegacyFingerprint();
        final strong = await HardwareFingerprintService.generateFingerprint();

        // Legacy should always exist
        expect(legacy, isNotNull);
        expect(legacy, isNotEmpty);

        // Both should be usable in a register request
        final data = <String, dynamic>{
          'hardware_id': strong ?? legacy,
        };
        if (strong != null) {
          data['legacy_hardware_id'] = legacy;
        }

        expect(data['hardware_id'], isNotNull);
        expect(data['hardware_id'], isNotEmpty);
        // If strong fingerprint available, legacy should be included
        if (strong != null) {
          expect(data['legacy_hardware_id'], isNotNull);
          expect(data['legacy_hardware_id'], isNot(equals(data['hardware_id'])));
        }
      });
    });
  });
}
