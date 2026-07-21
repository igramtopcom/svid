// ignore_for_file: deprecated_member_use

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:svid/core/services/pii_scrubber.dart';

void main() {
  group('scrubString — pattern coverage', () {
    test('redacts URLs', () {
      expect(
        scrubString('Loaded https://api.ssvid.app/v1/users/abc'),
        contains('[URL_REDACTED]'),
      );
    });

    test('redacts entire macOS user paths (greedy through subdirs)', () {
      final result = scrubString(
        'Failed to read /Users/kynnd/Projects/secret-app/file.mp4 next',
      );
      expect(result, contains('[PATH_REDACTED]'));
      // The full path should be consumed — no `secret-app` leaks through.
      expect(result, isNot(contains('secret-app')));
      expect(result, isNot(contains('Projects')));
      expect(result, isNot(contains('kynnd')));
      // Trailing context preserved.
      expect(result, contains('next'));
    });

    test('redacts entire Linux user paths (greedy through subdirs)', () {
      final result = scrubString('Failed to read /home/kynnd/private/x done');
      expect(result, contains('[PATH_REDACTED]'));
      expect(result, isNot(contains('private')));
      expect(result, contains('done'));
    });

    test('redacts entire Windows user paths (greedy through subdirs)', () {
      final result = scrubString(
        r'Failed to read C:\Users\kynnd\private\x.mp4 done',
      );
      expect(result, contains('[PATH_REDACTED]'));
      expect(result, isNot(contains('private')));
      expect(result, contains('done'));
    });

    test('redacts media filenames', () {
      expect(
        scrubString('Saved myvid.mp4 successfully'),
        contains('[MEDIA_REDACTED]'),
      );
      expect(scrubString('Wrote song.mp3'), contains('[MEDIA_REDACTED]'));
    });

    test('redacts 32-char hex license keys', () {
      const key = '985168ae6f117474b5f5c57609d69276';
      expect(scrubString('Activating $key'), contains('[LICENSE_REDACTED]'));
    });

    test('redacts UUIDs', () {
      const uuid = '019df813-b2f0-75e3-8c5c-652ec67b70b4';
      expect(scrubString('ticket=$uuid'), contains('[UUID_REDACTED]'));
    });

    test('redacts JWTs', () {
      const jwt =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4ifQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';
      expect(scrubString('Bearer $jwt'), contains('[JWT_REDACTED]'));
    });

    test('redacts Stripe ids', () {
      expect(
        scrubString('charge sk_live_AbcDef1234567890XyzWvu'),
        contains('[STRIPE_ID_REDACTED]'),
      );
      expect(
        scrubString('publishable pk_test_1234567890abcdefghij'),
        contains('[STRIPE_ID_REDACTED]'),
      );
    });

    test('redacts SSvid API keys (snk_*)', () {
      expect(
        scrubString('X-API-Key: snk_AbCdEfGh12345678QwErTy'),
        contains('[API_KEY_REDACTED]'),
      );
    });

    test('redacts email addresses', () {
      expect(
        scrubString('user@example.com clicked'),
        contains('[EMAIL_REDACTED]'),
      );
    });

    test('does NOT redact ordinary words that resemble patterns', () {
      // Short hex (not 32 chars) — must not match license regex.
      expect(scrubString('color #abc123'), 'color #abc123');
      // Plain dotted text — must not match JWT.
      expect(scrubString('a.b.c'), 'a.b.c');
      // Word containing @ that's not an email — must not redact.
      expect(scrubString('see @docs'), 'see @docs');
    });
  });

  group('scrubHttpUrl — route templating', () {
    test('strips query string entirely', () {
      final scrubbed = scrubHttpUrl(
        Uri.parse(
          'https://api.ssvid.app/v1/license/activate?key=ABC&device=XYZ',
        ),
      );
      expect(scrubbed, isNot(contains('key=')));
      expect(scrubbed, isNot(contains('device=')));
      expect(scrubbed, equals('https://api.ssvid.app/v1/license/activate'));
    });

    test('replaces UUID path segment with {id}', () {
      final scrubbed = scrubHttpUrl(
        Uri.parse(
          'https://api.ssvid.app/v1/tickets/019df813-b2f0-75e3-8c5c-652ec67b70b4',
        ),
      );
      expect(scrubbed, equals('https://api.ssvid.app/v1/tickets/{id}'));
    });

    test('replaces 32-char hex license segment with {license}', () {
      final scrubbed = scrubHttpUrl(
        Uri.parse(
          'https://api.ssvid.app/v1/license/985168ae6f117474b5f5c57609d69276',
        ),
      );
      expect(scrubbed, equals('https://api.ssvid.app/v1/license/{license}'));
    });

    test('replaces email path segment with {email}', () {
      final scrubbed = scrubHttpUrl(
        Uri.parse('https://api.ssvid.app/v1/users/user@example.com'),
      );
      expect(scrubbed, equals('https://api.ssvid.app/v1/users/{email}'));
    });

    test('keeps static path segments unchanged', () {
      final scrubbed = scrubHttpUrl(
        Uri.parse('https://api.ssvid.app/v1/crashes'),
      );
      expect(scrubbed, equals('https://api.ssvid.app/v1/crashes'));
    });

    test('handles mixed segments', () {
      final scrubbed = scrubHttpUrl(
        Uri.parse(
          'https://api.ssvid.app/v1/users/019df813-b2f0-75e3-8c5c-652ec67b70b4/tickets/abc123def456abc123def456abc123de',
        ),
      );
      expect(
        scrubbed,
        equals('https://api.ssvid.app/v1/users/{id}/tickets/{license}'),
      );
    });

    test('VidCombo PHP query is stripped', () {
      final scrubbed = scrubHttpUrl(
        Uri.parse(
          'https://vidcombo.example.com/checkkey.php?device_id=xyz&license_key=985168ae6f117474b5f5c57609d69276',
        ),
      );
      expect(scrubbed, equals('https://vidcombo.example.com/checkkey.php'));
      expect(scrubbed, isNot(contains('license_key')));
      expect(scrubbed, isNot(contains('device_id')));
    });
  });

  group('piiScrubber — walks all event surfaces', () {
    test('scrubs message', () {
      final event = SentryEvent(
        message: SentryMessage('See https://api.ssvid.app/v1/x'),
      );
      final scrubbed = piiScrubber(event);
      expect(scrubbed.message!.formatted, contains('[URL_REDACTED]'));
    });

    test('scrubs tags', () {
      final event = SentryEvent(
        tags: const {'context': 'user@example.com clicked'},
      );
      final scrubbed = piiScrubber(event);
      expect(scrubbed.tags!['context'], contains('[EMAIL_REDACTED]'));
    });

    test('scrubs extras (top level + nested map)', () {
      final event = SentryEvent(
        extra: <String, dynamic>{
          'url': 'https://api.ssvid.app/v1/x',
          'meta': <String, dynamic>{
            'license': '985168ae6f117474b5f5c57609d69276',
          },
        },
      );
      final scrubbed = piiScrubber(event);
      expect(scrubbed.extra!['url'], contains('[URL_REDACTED]'));
      expect(
        (scrubbed.extra!['meta'] as Map)['license'],
        contains('[LICENSE_REDACTED]'),
      );
    });

    test('scrubs breadcrumb data', () {
      final event = SentryEvent(
        breadcrumbs: [
          Breadcrumb(
            message: 'Loaded',
            data: <String, dynamic>{'url': 'https://api.ssvid.app/v1/x'},
          ),
        ],
      );
      final scrubbed = piiScrubber(event);
      expect(
        scrubbed.breadcrumbs!.first.data!['url'],
        contains('[URL_REDACTED]'),
      );
    });

    test('scrubs SentryUser email and name, drops ipAddress', () {
      final event = SentryEvent(
        user: SentryUser(
          email: 'user@example.com',
          name: 'kynnd@gmail.com test',
          ipAddress: '1.2.3.4',
        ),
      );
      final scrubbed = piiScrubber(event);
      expect(scrubbed.user!.email, contains('[EMAIL_REDACTED]'));
      expect(scrubbed.user!.name, contains('[EMAIL_REDACTED]'));
      expect(
        scrubbed.user!.ipAddress,
        isNull,
        reason:
            'critical: SentryUser.copyWith preserves null arg as '
            'this.ipAddress, so the scrubber MUST construct a new '
            'SentryUser explicitly. Regression here would silently leak IPs.',
      );
    });

    test('scrubs SentryUser id and username', () {
      final event = SentryEvent(
        user: SentryUser(
          id: '019df813-b2f0-75e3-8c5c-652ec67b70b4',
          username: 'kynnd@gmail.com',
        ),
      );
      final scrubbed = piiScrubber(event);
      expect(scrubbed.user!.id, contains('[UUID_REDACTED]'));
      expect(scrubbed.user!.username, contains('[EMAIL_REDACTED]'));
    });

    test('IP-only user → replaced with [REDACTED] sentinel, IP cleared', () {
      // Edge case: user came in with ONLY ipAddress (no id/username/email).
      // SentryEvent.copyWith(user: null) preserves the original via
      // `user ?? this.user`, so we MUST return a non-null sentinel user
      // to actually redact the IP. Test guards against regression where a
      // future refactor returns null for this case.
      final event = SentryEvent(user: SentryUser(ipAddress: '1.2.3.4'));
      final scrubbed = piiScrubber(event);
      expect(
        scrubbed.user,
        isNotNull,
        reason:
            'must NOT return null user — copyWith would preserve '
            'original IP-carrying user',
      );
      expect(
        scrubbed.user!.ipAddress,
        isNull,
        reason: 'IP must be dropped from outgoing event',
      );
      expect(
        scrubbed.user!.id,
        '[REDACTED]',
        reason: 'sentinel id signals to dev that user was redacted',
      );
    });

    test('scrubs SentryRequest url, headers, queryString, cookies', () {
      final event = SentryEvent(
        request: SentryRequest(
          url: 'https://api.ssvid.app/v1/license/activate',
          method: 'POST',
          queryString: 'license_key=985168ae6f117474b5f5c57609d69276',
          cookies: 'session=abc; csrf=xyz',
          headers: const {
            'Authorization': 'Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4In0.aaaa',
            'X-API-Key': 'snk_AbCdEfGh12345678QwErTy',
            'Content-Type': 'application/json',
          },
        ),
      );
      final scrubbed = piiScrubber(event);
      // URL itself goes through full URL scrub.
      expect(scrubbed.request!.url, contains('[URL_REDACTED]'));
      // Auth headers: redacted entirely.
      expect(scrubbed.request!.headers['Authorization'], '[REDACTED]');
      expect(scrubbed.request!.headers['X-API-Key'], '[REDACTED]');
      // Non-auth headers: pass through.
      expect(scrubbed.request!.headers['Content-Type'], 'application/json');
      // Query string and cookies: cleared (must NOT contain license/session).
      expect(scrubbed.request!.queryString, isNull);
      expect(scrubbed.request!.cookies, isNull);
    });

    test('contexts: scrubs custom map entries with PII', () {
      final ctx = Contexts();
      ctx['custom'] = <String, dynamic>{
        'license': '985168ae6f117474b5f5c57609d69276',
        'email': 'user@example.com',
      };
      ctx['note'] = 'Visited https://api.ssvid.app/v1/x';
      final event = SentryEvent(contexts: ctx);
      final scrubbed = piiScrubber(event);
      final customMap = scrubbed.contexts['custom'] as Map;
      expect(customMap['license'], contains('[LICENSE_REDACTED]'));
      expect(customMap['email'], contains('[EMAIL_REDACTED]'));
      expect(scrubbed.contexts['note'], contains('[URL_REDACTED]'));
    });
  });
}
