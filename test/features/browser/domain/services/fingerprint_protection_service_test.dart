import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/browser/domain/services/fingerprint_protection_service.dart';

void main() {
  late FingerprintProtectionService service;

  setUp(() {
    service = FingerprintProtectionService();
  });

  group('FingerprintProtectionService', () {
    group('generateProtectionScript', () {
      test('returns non-empty JavaScript string', () {
        final script = service.generateProtectionScript();
        expect(script, isNotEmpty);
      });

      test('contains navigator.plugins spoofing', () {
        final script = service.generateProtectionScript();
        expect(script, contains('navigator'));
        expect(script, contains('plugins'));
      });

      test('contains hardwareConcurrency spoofing to 4', () {
        final script = service.generateProtectionScript();
        expect(script, contains('hardwareConcurrency'));
        expect(script, contains('4'));
      });

      test('contains colorDepth spoofing to 24', () {
        final script = service.generateProtectionScript();
        expect(script, contains('colorDepth'));
        expect(script, contains('24'));
      });

      test('contains getBattery blocking', () {
        final script = service.generateProtectionScript();
        expect(script, contains('getBattery'));
      });

      test('contains canvas fingerprint randomization', () {
        final script = service.generateProtectionScript();
        expect(script, contains('toDataURL'));
      });

      test('wraps in self-executing function', () {
        final script = service.generateProtectionScript();
        expect(script.trim(), startsWith('(function()'));
        expect(script.trim(), endsWith('})();'));
      });

      test('includes try-catch for safety', () {
        final script = service.generateProtectionScript();
        expect(script, contains('try'));
        expect(script, contains('catch'));
      });
    });
  });
}
