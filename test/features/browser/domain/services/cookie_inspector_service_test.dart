import 'package:flutter_test/flutter_test.dart';

import 'package:svid/features/browser/domain/services/cookie_inspector_service.dart';

void main() {
  late CookieInspectorService service;

  setUp(() {
    service = CookieInspectorService();
  });

  // ---------------------------------------------------------------------------
  // parseCookies
  // ---------------------------------------------------------------------------
  group('parseCookies', () {
    test('parses a single valid Netscape cookie line', () {
      const input =
          '.youtube.com\tTRUE\t/\tTRUE\t1700000000\tSID\tabc123';

      final result = service.parseCookies(input);

      expect(result, hasLength(1));
      expect(result.first.domain, '.youtube.com');
      expect(result.first.isSubdomain, isTrue);
      expect(result.first.path, '/');
      expect(result.first.isSecure, isTrue);
      expect(result.first.name, 'SID');
      expect(result.first.value, 'abc123');
      expect(result.first.expiresAt, isNotNull);
    });

    test('parses multiple cookie lines', () {
      const input = '.youtube.com\tTRUE\t/\tTRUE\t1700000000\tSID\tabc\n'
          '.google.com\tFALSE\t/accounts\tFALSE\t1700000000\tHSID\txyz';

      final result = service.parseCookies(input);

      expect(result, hasLength(2));
      expect(result[0].name, 'SID');
      expect(result[1].name, 'HSID');
      expect(result[1].domain, '.google.com');
      expect(result[1].isSubdomain, isFalse);
      expect(result[1].path, '/accounts');
      expect(result[1].isSecure, isFalse);
    });

    test('skips comment lines starting with #', () {
      const input = '# Netscape HTTP Cookie File\n'
          '# This is auto-generated\n'
          '.youtube.com\tTRUE\t/\tTRUE\t1700000000\tSID\tabc';

      final result = service.parseCookies(input);

      expect(result, hasLength(1));
      expect(result.first.name, 'SID');
    });

    test('skips empty lines', () {
      const input = '\n\n.youtube.com\tTRUE\t/\tTRUE\t1700000000\tSID\tabc\n\n';

      final result = service.parseCookies(input);

      expect(result, hasLength(1));
    });

    test('skips lines with fewer than 7 tab-separated fields', () {
      const input = '.youtube.com\tTRUE\t/\tTRUE\t1700000000\tSID\n'
          'incomplete\tline\n'
          '.google.com\tTRUE\t/\tTRUE\t1700000000\tHSID\tval';

      final result = service.parseCookies(input);

      // First line has only 6 fields (no value), second has 2 fields — both skipped
      expect(result, hasLength(1));
      expect(result.first.name, 'HSID');
    });

    test('handles tab-separated values correctly (FALSE for subdomains and secure)',
        () {
      const input =
          'example.com\tFALSE\t/path\tFALSE\t0\tmycookie\tmyvalue';

      final result = service.parseCookies(input);

      expect(result, hasLength(1));
      expect(result.first.isSubdomain, isFalse);
      expect(result.first.isSecure, isFalse);
    });

    test('parses expiration timestamp 0 as no expiry (session cookie)', () {
      const input = '.example.com\tTRUE\t/\tTRUE\t0\tsession\tval';

      final result = service.parseCookies(input);

      expect(result, hasLength(1));
      expect(result.first.expiresAt, isNull);
    });

    test('parses valid expiration timestamp into DateTime', () {
      // 1700000000 seconds since epoch = 2023-11-14T22:13:20Z
      const input = '.example.com\tTRUE\t/\tTRUE\t1700000000\ttest\tval';

      final result = service.parseCookies(input);
      final expected = DateTime.fromMillisecondsSinceEpoch(
        1700000000 * 1000,
        isUtc: true,
      ).toLocal();

      expect(result.first.expiresAt, equals(expected));
    });

    test('value containing tabs is preserved via sublist join', () {
      const input =
          '.example.com\tTRUE\t/\tTRUE\t1700000000\tdata\tpart1\tpart2\tpart3';

      final result = service.parseCookies(input);

      expect(result, hasLength(1));
      expect(result.first.value, 'part1\tpart2\tpart3');
    });

    test('returns empty list for empty string', () {
      final result = service.parseCookies('');
      expect(result, isEmpty);
    });

    test('returns empty list for whitespace-only string', () {
      final result = service.parseCookies('   \n  \n   ');
      expect(result, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // CookieEntry computed properties
  // ---------------------------------------------------------------------------
  group('CookieEntry.isExpired', () {
    test('returns true when expiresAt is in the past', () {
      final entry = CookieEntry(
        name: 'old',
        value: 'v',
        domain: '.example.com',
        path: '/',
        isSecure: false,
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );

      expect(entry.isExpired, isTrue);
    });

    test('returns false when expiresAt is in the future', () {
      final entry = CookieEntry(
        name: 'fresh',
        value: 'v',
        domain: '.example.com',
        path: '/',
        isSecure: false,
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      );

      expect(entry.isExpired, isFalse);
    });

    test('returns false when expiresAt is null (session cookie)', () {
      const entry = CookieEntry(
        name: 'sess',
        value: 'v',
        domain: '.example.com',
        path: '/',
        isSecure: false,
      );

      expect(entry.isExpired, isFalse);
    });
  });

  group('CookieEntry.isExpiringSoon', () {
    test('returns true when expiry is within 3 days and not yet expired', () {
      final entry = CookieEntry(
        name: 'soon',
        value: 'v',
        domain: '.example.com',
        path: '/',
        isSecure: false,
        expiresAt: DateTime.now().add(const Duration(days: 2)),
      );

      expect(entry.isExpiringSoon, isTrue);
    });

    test('returns false when expiry is beyond 3 days', () {
      final entry = CookieEntry(
        name: 'far',
        value: 'v',
        domain: '.example.com',
        path: '/',
        isSecure: false,
        expiresAt: DateTime.now().add(const Duration(days: 10)),
      );

      expect(entry.isExpiringSoon, isFalse);
    });

    test('returns false when already expired', () {
      final entry = CookieEntry(
        name: 'dead',
        value: 'v',
        domain: '.example.com',
        path: '/',
        isSecure: false,
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      );

      expect(entry.isExpiringSoon, isFalse);
    });

    test('returns false when expiresAt is null', () {
      const entry = CookieEntry(
        name: 'sess',
        value: 'v',
        domain: '.example.com',
        path: '/',
        isSecure: false,
      );

      expect(entry.isExpiringSoon, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // countByDomain
  // ---------------------------------------------------------------------------
  group('countByDomain', () {
    test('groups cookie counts by domain correctly', () {
      final entries = [
        _cookie(domain: '.youtube.com', name: 'a'),
        _cookie(domain: '.youtube.com', name: 'b'),
        _cookie(domain: '.google.com', name: 'c'),
      ];

      final counts = service.countByDomain(entries);

      expect(counts, {'.youtube.com': 2, '.google.com': 1});
    });

    test('returns empty map for empty list', () {
      expect(service.countByDomain([]), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // findAuthCookies
  // ---------------------------------------------------------------------------
  group('findAuthCookies', () {
    test('identifies known auth cookies (SID, sessionid, auth_token)', () {
      final entries = [
        _cookie(name: 'SID', value: 'google-sid'),
        _cookie(name: 'sessionid', value: 'instagram-sess'),
        _cookie(name: 'auth_token', value: 'twitter-auth'),
        _cookie(name: 'random_pref', value: 'not-auth'),
      ];

      final auth = service.findAuthCookies(entries);

      expect(auth, hasLength(3));
      expect(auth.map((e) => e.name).toList(),
          containsAll(['SID', 'sessionid', 'auth_token']));
    });

    test('returns empty list when no auth cookies are present', () {
      final entries = [
        _cookie(name: 'theme', value: 'dark'),
        _cookie(name: 'lang', value: 'en'),
        _cookie(name: 'pref_volume', value: '80'),
      ];

      expect(service.findAuthCookies(entries), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // isSessionHealthy
  // ---------------------------------------------------------------------------
  group('isSessionHealthy', () {
    test('returns true when at least one non-expired auth cookie exists', () {
      final entries = [
        _cookie(
          name: 'SID',
          value: 'valid',
          expiresAt: DateTime.now().add(const Duration(days: 30)),
        ),
        _cookie(name: 'pref', value: 'dark'),
      ];

      expect(service.isSessionHealthy(entries), isTrue);
    });

    test('returns false when no auth cookies are present', () {
      final entries = [
        _cookie(name: 'pref', value: 'dark'),
        _cookie(name: 'lang', value: 'en'),
      ];

      expect(service.isSessionHealthy(entries), isFalse);
    });

    test('returns false when all auth cookies are expired', () {
      final entries = [
        _cookie(
          name: 'SID',
          value: 'old',
          expiresAt: DateTime.now().subtract(const Duration(days: 5)),
        ),
        _cookie(
          name: 'HSID',
          value: 'old2',
          expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      ];

      expect(service.isSessionHealthy(entries), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // summarize
  // ---------------------------------------------------------------------------
  group('summarize', () {
    test('produces correct summary for healthy session', () {
      final futureExpiry = DateTime.now().add(const Duration(days: 30));
      final entries = [
        _cookie(name: 'SID', value: 'g1', expiresAt: futureExpiry),
        _cookie(name: 'HSID', value: 'g2', expiresAt: futureExpiry),
        _cookie(name: 'theme', value: 'dark'),
      ];

      final summary = service.summarize('youtube', entries);

      expect(summary.platform, 'youtube');
      expect(summary.totalCookies, 3);
      expect(summary.authCookieCount, 2);
      expect(summary.isHealthy, isTrue);
      expect(summary.expiringSoonCount, 0);
      expect(summary.earliestExpiry, futureExpiry);
    });

    test('reports mixed healthy and expired auth cookies correctly', () {
      final validExpiry = DateTime.now().add(const Duration(days: 30));
      final expiredDate = DateTime.now().subtract(const Duration(days: 1));
      final entries = [
        _cookie(name: 'SID', value: 'valid', expiresAt: validExpiry),
        _cookie(name: 'HSID', value: 'expired', expiresAt: expiredDate),
        _cookie(name: 'pref', value: 'x'),
      ];

      final summary = service.summarize('youtube', entries);

      expect(summary.totalCookies, 3);
      // Only non-expired auth cookies counted
      expect(summary.authCookieCount, 1);
      expect(summary.isHealthy, isTrue);
      // earliestExpiry should be the valid one (expired ones are excluded)
      expect(summary.earliestExpiry, validExpiry);
    });

    test('counts expiring-soon cookies', () {
      final soonExpiry = DateTime.now().add(const Duration(days: 1));
      final farExpiry = DateTime.now().add(const Duration(days: 30));
      final entries = [
        _cookie(name: 'SID', value: 'auth', expiresAt: farExpiry),
        _cookie(name: 'tracking', value: 'x', expiresAt: soonExpiry),
        _cookie(name: 'pref', value: 'y', expiresAt: soonExpiry),
      ];

      final summary = service.summarize('youtube', entries);

      expect(summary.expiringSoonCount, 2);
      // Earliest non-expired expiry is soonExpiry
      expect(summary.earliestExpiry, soonExpiry);
    });

    test('empty entries produce zeroed summary', () {
      final summary = service.summarize('youtube', []);

      expect(summary.platform, 'youtube');
      expect(summary.totalCookies, 0);
      expect(summary.authCookieCount, 0);
      expect(summary.expiringSoonCount, 0);
      expect(summary.isHealthy, isFalse);
      expect(summary.earliestExpiry, isNull);
    });
  });
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------
CookieEntry _cookie({
  String name = 'cookie',
  String value = 'val',
  String domain = '.example.com',
  String path = '/',
  bool isSecure = false,
  DateTime? expiresAt,
  bool isSubdomain = false,
}) {
  return CookieEntry(
    name: name,
    value: value,
    domain: domain,
    path: path,
    isSecure: isSecure,
    expiresAt: expiresAt,
    isSubdomain: isSubdomain,
  );
}
