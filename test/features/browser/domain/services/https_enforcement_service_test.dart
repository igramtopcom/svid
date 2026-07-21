import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/browser/domain/services/https_enforcement_service.dart';

void main() {
  late HttpsEnforcementService service;

  setUp(() {
    service = HttpsEnforcementService();
  });

  group('HttpsEnforcementService', () {
    group('shouldUpgrade', () {
      test('returns true for HTTP URLs', () {
        expect(service.shouldUpgrade('http://example.com'), isTrue);
        expect(service.shouldUpgrade('http://www.google.com/search'), isTrue);
      });

      test('returns false for HTTPS URLs', () {
        expect(service.shouldUpgrade('https://example.com'), isFalse);
      });

      test('returns false for non-HTTP schemes', () {
        expect(service.shouldUpgrade('ftp://files.com'), isFalse);
        expect(service.shouldUpgrade('ws://socket.com'), isFalse);
      });

      test('returns false for localhost', () {
        expect(service.shouldUpgrade('http://localhost:3000'), isFalse);
        expect(service.shouldUpgrade('http://127.0.0.1:8080'), isFalse);
        expect(service.shouldUpgrade('http://0.0.0.0:5000'), isFalse);
      });

      test('returns false for private IPs (10.x)', () {
        expect(service.shouldUpgrade('http://10.0.0.1'), isFalse);
        expect(service.shouldUpgrade('http://10.255.255.255'), isFalse);
      });

      test('returns false for private IPs (192.168.x)', () {
        expect(service.shouldUpgrade('http://192.168.1.1'), isFalse);
        expect(service.shouldUpgrade('http://192.168.0.100'), isFalse);
      });

      test('returns false for private IPs (172.16-31.x)', () {
        expect(service.shouldUpgrade('http://172.16.0.1'), isFalse);
        expect(service.shouldUpgrade('http://172.31.255.255'), isFalse);
      });

      test('returns true for non-private 172.x IPs', () {
        expect(service.shouldUpgrade('http://172.15.0.1'), isTrue);
        expect(service.shouldUpgrade('http://172.32.0.1'), isTrue);
      });

      test('returns false for invalid URLs', () {
        expect(service.shouldUpgrade('not-a-url'), isFalse);
        expect(service.shouldUpgrade(''), isFalse);
      });
    });

    group('upgradeUrl', () {
      test('converts http to https', () {
        expect(
          service.upgradeUrl('http://example.com'),
          'https://example.com',
        );
        expect(
          service.upgradeUrl('http://www.google.com/search?q=test'),
          'https://www.google.com/search?q=test',
        );
      });

      test('does not change HTTPS URLs', () {
        expect(
          service.upgradeUrl('https://example.com'),
          'https://example.com',
        );
      });

      test('does not change localhost', () {
        expect(
          service.upgradeUrl('http://localhost:3000'),
          'http://localhost:3000',
        );
      });

      test('returns original for invalid URLs', () {
        expect(service.upgradeUrl('not-a-url'), 'not-a-url');
      });
    });

    group('isInsecure', () {
      test('returns true for HTTP URLs', () {
        expect(service.isInsecure('http://example.com'), isTrue);
      });

      test('returns false for HTTPS URLs', () {
        expect(service.isInsecure('https://example.com'), isFalse);
      });

      test('returns false for localhost HTTP', () {
        expect(service.isInsecure('http://localhost'), isFalse);
        expect(service.isInsecure('http://127.0.0.1'), isFalse);
      });

      test('returns false for non-HTTP schemes', () {
        expect(service.isInsecure('ftp://example.com'), isFalse);
      });

      test('returns false for private IPs', () {
        expect(service.isInsecure('http://192.168.1.1'), isFalse);
        expect(service.isInsecure('http://10.0.0.1'), isFalse);
      });
    });
  });
}
