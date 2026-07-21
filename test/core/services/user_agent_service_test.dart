import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/services/user_agent_service.dart';
import 'package:svid/core/utils/platform_detector.dart';

void main() {
  group('UserAgentService', () {
    test('getRandomUserAgent returns a non-empty string', () {
      final service = UserAgentService();
      final ua = service.getRandomUserAgent();
      expect(ua, isNotEmpty);
    });

    test('getRandomUserAgent returns a valid browser UA string', () {
      final service = UserAgentService();
      final ua = service.getRandomUserAgent();
      expect(ua, contains('Mozilla/5.0'));
    });

    test('pool contains at least 10 user agents', () {
      expect(UserAgentService.poolSize, greaterThanOrEqualTo(10));
    });

    test('all user agents are valid Mozilla strings', () {
      for (final ua in UserAgentService.allUserAgents) {
        expect(ua, startsWith('Mozilla/5.0'));
        // Chrome/Edge use AppleWebKit, Firefox uses Gecko
        final hasWebKit = ua.contains('AppleWebKit/537.36');
        final hasGecko = ua.contains('Gecko/20100101');
        expect(hasWebKit || hasGecko, isTrue,
            reason: 'UA should contain AppleWebKit or Gecko engine: $ua');
      }
    });

    test('all user agents contain modern Chrome/Firefox/Edge versions', () {
      for (final ua in UserAgentService.allUserAgents) {
        final hasChrome = ua.contains('Chrome/');
        final hasFirefox = ua.contains('Firefox/');
        expect(hasChrome || hasFirefox, isTrue,
            reason: 'UA should contain Chrome or Firefox: $ua');
      }
    });

    test('pool contains UAs for Windows, macOS, and Linux', () {
      final agents = UserAgentService.allUserAgents;
      expect(agents.any((ua) => ua.contains('Windows NT')), isTrue);
      expect(agents.any((ua) => ua.contains('Macintosh')), isTrue);
      expect(agents.any((ua) => ua.contains('Linux')), isTrue);
    });

    test('pool contains Chrome, Firefox, and Edge UAs', () {
      final agents = UserAgentService.allUserAgents;
      expect(
        agents.any((ua) =>
            ua.contains('Chrome/') && !ua.contains('Edg/') && !ua.contains('Firefox/')),
        isTrue,
        reason: 'Pool should contain plain Chrome UAs',
      );
      expect(agents.any((ua) => ua.contains('Firefox/')), isTrue);
      expect(agents.any((ua) => ua.contains('Edg/')), isTrue);
    });

    test('injectable Random produces deterministic results', () {
      final service1 = UserAgentService(random: Random(42));
      final service2 = UserAgentService(random: Random(42));

      final ua1 = service1.getRandomUserAgent();
      final ua2 = service2.getRandomUserAgent();
      expect(ua1, equals(ua2));
    });

    test('different Random seeds produce different results', () {
      final service1 = UserAgentService(random: Random(1));
      final service2 = UserAgentService(random: Random(999));

      // With different seeds and 13 items, very likely to differ
      final results1 = List.generate(5, (_) => service1.getRandomUserAgent());
      final results2 = List.generate(5, (_) => service2.getRandomUserAgent());
      expect(results1, isNot(equals(results2)));
    });

    test('multiple calls return values from the pool', () {
      final service = UserAgentService();
      final allAgents = UserAgentService.allUserAgents;

      for (var i = 0; i < 50; i++) {
        final ua = service.getRandomUserAgent();
        expect(allAgents, contains(ua));
      }
    });

    test('allUserAgents returns unmodifiable list', () {
      final agents = UserAgentService.allUserAgents;
      expect(() => agents.add('test'), throwsA(isA<UnsupportedError>()));
    });

    test('no duplicate user agents in pool', () {
      final agents = UserAgentService.allUserAgents;
      final unique = agents.toSet();
      expect(unique.length, equals(agents.length));
    });
  });

  group('getUserAgentForPlatform', () {
    late UserAgentService service;

    setUp(() => service = UserAgentService());

    test('Instagram returns mobile Safari UA', () {
      final ua = service.getUserAgentForPlatform(VideoPlatform.instagram);
      expect(ua, contains('iPhone'));
      expect(ua, contains('Safari'));
    });

    test('TikTok returns mobile Safari UA', () {
      final ua = service.getUserAgentForPlatform(VideoPlatform.tiktok);
      expect(ua, contains('iPhone'));
    });

    test('Pinterest returns mobile Safari UA', () {
      final ua = service.getUserAgentForPlatform(VideoPlatform.pinterest);
      expect(ua, contains('iPhone'));
    });

    test('YouTube returns desktop Chrome UA', () {
      final ua = service.getUserAgentForPlatform(VideoPlatform.youtube);
      expect(ua, contains('Windows NT'));
      expect(ua, contains('Chrome/'));
    });

    test('Bilibili returns desktop Chrome UA', () {
      final ua = service.getUserAgentForPlatform(VideoPlatform.bilibili);
      expect(ua, contains('Chrome/'));
    });

    test('Vimeo returns desktop Chrome UA', () {
      final ua = service.getUserAgentForPlatform(VideoPlatform.vimeo);
      expect(ua, contains('Chrome/'));
    });

    test('unknown platform returns string from pool', () {
      final ua = service.getUserAgentForPlatform(VideoPlatform.unknown);
      expect(UserAgentService.allUserAgents, contains(ua));
    });

    test('all platforms return non-empty UA', () {
      for (final platform in VideoPlatform.values) {
        final ua = service.getUserAgentForPlatform(platform);
        expect(ua, isNotEmpty);
        expect(ua, contains('Mozilla/5.0'));
      }
    });
  });

  group('rotateUserAgent', () {
    test('returns UA from pool', () {
      final service = UserAgentService();
      final ua = service.rotateUserAgent();
      expect(UserAgentService.allUserAgents, contains(ua));
    });

    test('sequential calls return different UAs (cycles through pool)', () {
      final service = UserAgentService();
      final results = List.generate(
        UserAgentService.poolSize,
        (_) => service.rotateUserAgent(),
      );
      // After full cycle, should have covered all UAs
      expect(results.toSet().length, greaterThan(1));
    });

    test('two services start at same rotation index independently', () {
      final s1 = UserAgentService();
      final s2 = UserAgentService();
      expect(s1.rotateUserAgent(), equals(s2.rotateUserAgent()));
    });
  });

  group('getAcceptLanguage', () {
    test('returns non-empty string', () {
      final service = UserAgentService();
      final lang = service.getAcceptLanguage();
      expect(lang, isNotEmpty);
    });

    test('pool has at least 4 Accept-Language values', () {
      expect(UserAgentService.allAcceptLanguages.length, greaterThanOrEqualTo(4));
    });

    test('all values contain locale codes (language tag format)', () {
      for (final lang in UserAgentService.allAcceptLanguages) {
        // Each entry should contain a BCP-47 language tag like "en-US" or "vi-VN"
        expect(RegExp(r'[a-z]{2}-[A-Z]{2}').hasMatch(lang), isTrue,
            reason: 'Should contain a BCP-47 locale code: $lang');
      }
    });

    test('returns value from the pool', () {
      final service = UserAgentService();
      final lang = service.getAcceptLanguage();
      expect(UserAgentService.allAcceptLanguages, contains(lang));
    });
  });
}
