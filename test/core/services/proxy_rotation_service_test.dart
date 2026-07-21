import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/services/proxy_rotation_service.dart';

void main() {
  group('ProxyRotationService', () {
    // -------------------------------------------------------------------------
    // Construction
    // -------------------------------------------------------------------------
    group('construction', () {
      test('filters out empty and whitespace-only entries', () {
        final svc = ProxyRotationService(
          proxies: ['http://p1:8080', '', '  ', 'http://p2:8080'],
        );
        expect(svc.count, 2);
        expect(svc.all, ['http://p1:8080', 'http://p2:8080']);
      });

      test('hasProxies is false when list is empty', () {
        expect(ProxyRotationService(proxies: []).hasProxies, isFalse);
      });

      test('hasProxies is true when list has entries', () {
        final svc = ProxyRotationService(proxies: ['http://p:8080']);
        expect(svc.hasProxies, isTrue);
      });
    });

    // -------------------------------------------------------------------------
    // nextProxy — sync round-robin
    // -------------------------------------------------------------------------
    group('nextProxy', () {
      test('returns null when proxy list is empty', () {
        expect(ProxyRotationService(proxies: []).nextProxy(), isNull);
      });

      test('returns the only proxy when list has one entry', () {
        final svc = ProxyRotationService(proxies: ['http://p1:8080']);
        expect(svc.nextProxy(), 'http://p1:8080');
        // Second call still returns the same proxy
        expect(svc.nextProxy(), 'http://p1:8080');
      });

      test('cycles through proxies in round-robin order', () {
        final svc = ProxyRotationService(
          proxies: ['http://p1:8080', 'http://p2:8080', 'http://p3:8080'],
        );
        expect(svc.nextProxy(), 'http://p1:8080');
        expect(svc.nextProxy(), 'http://p2:8080');
        expect(svc.nextProxy(), 'http://p3:8080');
        // Wraps around
        expect(svc.nextProxy(), 'http://p1:8080');
      });

      test('skips proxies marked unhealthy', () {
        final svc = ProxyRotationService(
          proxies: ['http://p1:8080', 'http://p2:8080', 'http://p3:8080'],
        );
        svc.markUnhealthy('http://p1:8080');
        svc.markUnhealthy('http://p2:8080');
        // Only p3 is healthy
        expect(svc.nextProxy(), 'http://p3:8080');
      });

      test('resets health and returns first proxy when all are unhealthy', () {
        final svc = ProxyRotationService(
          proxies: ['http://p1:8080', 'http://p2:8080'],
        );
        svc.markUnhealthy('http://p1:8080');
        svc.markUnhealthy('http://p2:8080');
        // Falls back to first proxy and clears unhealthy marks
        final result = svc.nextProxy();
        expect(result, isNotNull);
        // Health is reset
        expect(svc.healthyCount, 2);
      });
    });

    // -------------------------------------------------------------------------
    // nextHealthyProxy — async with health check
    // -------------------------------------------------------------------------
    group('nextHealthyProxy', () {
      test('returns null for empty proxy list', () async {
        final svc = ProxyRotationService(proxies: []);
        expect(await svc.nextHealthyProxy(), isNull);
      });

      test('returns proxy that passes health check', () async {
        final svc = ProxyRotationService(
          proxies: ['http://p1:8080', 'http://p2:8080'],
          checker: (url) async => url == 'http://p2:8080', // only p2 passes
        );
        expect(await svc.nextHealthyProxy(), 'http://p2:8080');
      });

      test('marks failing proxy as unhealthy', () async {
        final svc = ProxyRotationService(
          proxies: ['http://p1:8080', 'http://p2:8080'],
          checker: (url) async => url != 'http://p1:8080',
        );
        await svc.nextHealthyProxy();
        expect(svc.unhealthySet, contains('http://p1:8080'));
      });

      test('falls back to first proxy when all fail health check', () async {
        final svc = ProxyRotationService(
          proxies: ['http://p1:8080', 'http://p2:8080'],
          checker: (_) async => false, // all fail
        );
        final result = await svc.nextHealthyProxy();
        expect(result, isNotNull);
        // After fallback, health is reset
        expect(svc.healthyCount, 2);
      });
    });

    // -------------------------------------------------------------------------
    // Health state management
    // -------------------------------------------------------------------------
    group('markUnhealthy / resetHealth', () {
      test('markUnhealthy decrements healthyCount', () {
        final svc = ProxyRotationService(
          proxies: ['http://p1:8080', 'http://p2:8080', 'http://p3:8080'],
        );
        expect(svc.healthyCount, 3);
        svc.markUnhealthy('http://p2:8080');
        expect(svc.healthyCount, 2);
      });

      test('resetHealth restores all proxies to healthy', () {
        final svc = ProxyRotationService(
          proxies: ['http://p1:8080', 'http://p2:8080'],
        );
        svc.markUnhealthy('http://p1:8080');
        svc.markUnhealthy('http://p2:8080');
        svc.resetHealth();
        expect(svc.healthyCount, 2);
        expect(svc.unhealthySet, isEmpty);
      });
    });

    // -------------------------------------------------------------------------
    // checkAll
    // -------------------------------------------------------------------------
    group('checkAll', () {
      test('marks failing proxies as unhealthy concurrently', () async {
        final checked = <String>[];
        final svc = ProxyRotationService(
          proxies: ['http://p1:8080', 'http://p2:8080', 'http://p3:8080'],
          checker: (url) async {
            checked.add(url);
            return url != 'http://p2:8080'; // p2 fails
          },
        );
        await svc.checkAll();
        expect(svc.unhealthySet, {'http://p2:8080'});
        expect(svc.healthyCount, 2);
        // All 3 were probed
        expect(checked, containsAll(['http://p1:8080', 'http://p2:8080', 'http://p3:8080']));
      });

      test('resets all marks when every proxy fails', () async {
        final svc = ProxyRotationService(
          proxies: ['http://p1:8080', 'http://p2:8080'],
          checker: (_) async => false,
        );
        await svc.checkAll();
        // Defensive reset: shouldn't lock user out
        expect(svc.unhealthySet, isEmpty);
      });
    });
  });

  // ---------------------------------------------------------------------------
  // randomProxy helper
  // ---------------------------------------------------------------------------
  group('randomProxy', () {
    test('returns null for empty list', () {
      expect(randomProxy([]), isNull);
    });

    test('returns null for all-blank list', () {
      expect(randomProxy(['', '  ']), isNull);
    });

    test('returns a value from the list', () {
      final proxies = ['http://p1:8080', 'http://p2:8080'];
      final result = randomProxy(proxies);
      expect(proxies, contains(result));
    });

    test('always returns the only element for single-item list', () {
      expect(randomProxy(['http://only:9999']), 'http://only:9999');
    });
  });
}
