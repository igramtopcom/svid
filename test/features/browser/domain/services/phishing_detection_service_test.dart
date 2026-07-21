import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/browser/domain/services/phishing_detection_service.dart';

void main() {
  late PhishingDetectionService service;

  setUp(() {
    service = PhishingDetectionService();
  });

  group('PhishingDetectionService', () {
    group('checkUrl', () {
      test('returns safe for valid HTTPS URLs', () {
        expect(
          service.checkUrl('https://www.google.com'),
          PhishingCheckResult.safe,
        );
        expect(
          service.checkUrl('https://youtube.com/watch?v=abc'),
          PhishingCheckResult.safe,
        );
      });

      test('returns safe for non-HTTP schemes', () {
        expect(
          service.checkUrl('ftp://files.example.com'),
          PhishingCheckResult.safe,
        );
        expect(
          service.checkUrl('file:///home/user/doc.txt'),
          PhishingCheckResult.safe,
        );
      });

      test('returns safe for empty or invalid URLs', () {
        expect(service.checkUrl(''), PhishingCheckResult.safe);
        expect(service.checkUrl('not-a-url'), PhishingCheckResult.safe);
      });

      // IP address detection
      test('returns suspicious for IP-based URLs', () {
        expect(
          service.checkUrl('http://192.168.1.1/login'),
          PhishingCheckResult.suspicious,
        );
        expect(
          service.checkUrl('https://45.33.32.156/account'),
          PhishingCheckResult.suspicious,
        );
      });

      // Homograph attack detection
      test('returns dangerous for punycode domains (xn--)', () {
        expect(
          service.checkUrl('https://xn--pple-43d.com'),
          PhishingCheckResult.dangerous,
        );
      });

      test('returns dangerous for non-ASCII characters in domain', () {
        // URL with Cyrillic "о" (U+043E) instead of Latin "o"
        final cyrillicO = String.fromCharCode(0x043E);
        expect(
          service.checkUrl('https://g$cyrillicO${cyrillicO}gle.com'),
          PhishingCheckResult.dangerous,
        );
      });

      // Lookalike domain detection
      test('returns dangerous for lookalike brand domains', () {
        // edit distance 1 from "google"
        expect(
          service.checkUrl('https://gogle.com'),
          PhishingCheckResult.dangerous,
        );
        // edit distance 1 from "paypal"
        expect(
          service.checkUrl('https://paypa1.com'),
          PhishingCheckResult.dangerous,
        );
        // edit distance 2 from "amazon"
        expect(
          service.checkUrl('https://amazn.com'),
          PhishingCheckResult.dangerous,
        );
      });

      test('returns safe for exact brand domains', () {
        expect(
          service.checkUrl('https://google.com'),
          PhishingCheckResult.safe,
        );
        expect(
          service.checkUrl('https://www.paypal.com'),
          PhishingCheckResult.safe,
        );
      });

      // Phishing path patterns
      test('returns suspicious for phishing URL patterns', () {
        expect(
          service.checkUrl('https://example.com/login-verify'),
          PhishingCheckResult.suspicious,
        );
        expect(
          service.checkUrl('https://example.com/account-verify/user'),
          PhishingCheckResult.suspicious,
        );
        expect(
          service.checkUrl('https://example.com/secure-update'),
          PhishingCheckResult.suspicious,
        );
      });

      // Suspicious TLDs
      test('returns suspicious for suspicious TLDs', () {
        expect(
          service.checkUrl('https://free-movies.xyz'),
          PhishingCheckResult.suspicious,
        );
        expect(
          service.checkUrl('https://download.top'),
          PhishingCheckResult.suspicious,
        );
        expect(
          service.checkUrl('https://prize-winner.buzz'),
          PhishingCheckResult.suspicious,
        );
      });

      // Excessive subdomains
      test('returns suspicious for excessive subdomains', () {
        expect(
          service.checkUrl('https://a.b.c.d.example.com'),
          PhishingCheckResult.suspicious,
        );
      });

      test('returns safe for normal subdomain depth', () {
        expect(
          service.checkUrl('https://www.docs.example.com'),
          PhishingCheckResult.safe,
        );
      });
    });

    group('getWarningReason', () {
      test('returns null for safe URLs', () {
        expect(service.getWarningReason('https://www.google.com'), isNull);
      });

      test('returns reason for IP address', () {
        expect(
          service.getWarningReason('http://192.168.1.1/login'),
          'IP address URL',
        );
      });

      test('returns reason for lookalike domain', () {
        final reason = service.getWarningReason('https://gogle.com');
        expect(reason, contains('google'));
      });

      test('returns reason for suspicious TLD', () {
        expect(
          service.getWarningReason('https://free-stuff.xyz'),
          'Suspicious domain extension',
        );
      });

      test('returns reason for phishing path pattern', () {
        expect(
          service.getWarningReason('https://example.com/login-verify'),
          'Suspicious URL pattern',
        );
      });

      test('returns null for non-HTTP URLs', () {
        expect(service.getWarningReason('ftp://example.com'), isNull);
      });
    });

    group('_editDistance', () {
      test('computes correct Levenshtein distance', () {
        // Access via static method
        expect(PhishingDetectionService.editDistanceForTest('', ''), 0);
        expect(PhishingDetectionService.editDistanceForTest('abc', 'abc'), 0);
        expect(PhishingDetectionService.editDistanceForTest('abc', 'ab'), 1);
        expect(PhishingDetectionService.editDistanceForTest('abc', 'adc'), 1);
        expect(PhishingDetectionService.editDistanceForTest('kitten', 'sitting'), 3);
      });
    });
  });
}
