import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/browser/domain/services/ad_block_service.dart';

void main() {
  late AdBlockService service;

  setUp(() {
    service = AdBlockService();
  });

  group('AdBlockService.shouldBlock', () {
    test('blocks doubleclick.net', () {
      expect(service.shouldBlock('https://ad.doubleclick.net/serve'), isTrue);
    });

    test('blocks googlesyndication.com', () {
      expect(
        service.shouldBlock('https://pagead2.googlesyndication.com/pagead/js'),
        isTrue,
      );
    });

    test('blocks subdomain of blocked domain', () {
      expect(
        service.shouldBlock('https://cdn.criteo.com/js/ld/cc.js'),
        isTrue,
      );
    });

    test('blocks taboola.com', () {
      expect(
        service.shouldBlock('https://cdn.taboola.com/widget.js'),
        isTrue,
      );
    });

    test('blocks outbrain.com', () {
      expect(
        service.shouldBlock('https://widgets.outbrain.com/serve'),
        isTrue,
      );
    });

    test('does NOT block youtube.com', () {
      expect(service.shouldBlock('https://www.youtube.com/watch?v=abc'), isFalse);
    });

    test('does NOT block google.com', () {
      expect(service.shouldBlock('https://www.google.com/search?q=test'), isFalse);
    });

    test('does NOT block instagram.com', () {
      expect(service.shouldBlock('https://www.instagram.com/p/abc'), isFalse);
    });

    test('does NOT block reddit.com', () {
      expect(service.shouldBlock('https://www.reddit.com/r/test'), isFalse);
    });

    test('returns false for invalid URL', () {
      expect(service.shouldBlock('not-a-url'), isFalse);
    });

    test('returns false for empty URL', () {
      expect(service.shouldBlock(''), isFalse);
    });

    test('blocks google-analytics.com', () {
      expect(
        service.shouldBlock('https://www.google-analytics.com/analytics.js'),
        isTrue,
      );
    });

    test('blocks hotjar.com', () {
      expect(
        service.shouldBlock('https://static.hotjar.com/c/hotjar.js'),
        isTrue,
      );
    });

    test('blocks popads.net', () {
      expect(service.shouldBlock('https://c1.popads.net/pop.js'), isTrue);
    });

    test('blocks propellerads.com', () {
      expect(
        service.shouldBlock('https://cdn.propellerads.com/sdk.js'),
        isTrue,
      );
    });
  });

  group('AdBlockService.generateHideAdsScript', () {
    test('returns non-empty JavaScript', () {
      final script = service.generateHideAdsScript();
      expect(script, isNotEmpty);
    });

    test('contains brand-prefixed adblock style id', () {
      final script = service.generateHideAdsScript();
      expect(script, contains('-adblock'));
    });

    test('contains display: none rule', () {
      final script = service.generateHideAdsScript();
      expect(script, contains('display: none'));
    });

    test('is self-executing function', () {
      final script = service.generateHideAdsScript();
      expect(script.trim(), startsWith('(function()'));
    });
  });

  group('AdBlockService.blockedDomains', () {
    test('contains expected number of domains', () {
      expect(AdBlockService.blockedDomains.length, greaterThanOrEqualTo(25));
    });

    test('does not contain legitimate sites', () {
      expect(AdBlockService.blockedDomains, isNot(contains('youtube.com')));
      expect(AdBlockService.blockedDomains, isNot(contains('google.com')));
      expect(AdBlockService.blockedDomains, isNot(contains('facebook.com')));
    });
  });
}
