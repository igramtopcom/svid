import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/core/utils/lru_cache.dart';

void main() {
  group('LruCache', () {
    test('basic put / get', () {
      final c = LruCache<String, int>(3);
      c['a'] = 1;
      c['b'] = 2;
      expect(c['a'], 1);
      expect(c['b'], 2);
      expect(c['missing'], isNull);
      expect(c.length, 2);
    });

    test('eviction: oldest out at capacity', () {
      final c = LruCache<String, int>(3);
      c['a'] = 1;
      c['b'] = 2;
      c['c'] = 3;
      c['d'] = 4; // evicts 'a'
      expect(c['a'], isNull);
      expect(c['b'], 2);
      expect(c['c'], 3);
      expect(c['d'], 4);
      expect(c.length, 3);
    });

    test('get promotes to most-recent', () {
      final c = LruCache<String, int>(3);
      c['a'] = 1;
      c['b'] = 2;
      c['c'] = 3;
      // Touch 'a' so it becomes most-recent
      expect(c['a'], 1);
      // Adding 'd' should evict 'b' (oldest after promotion)
      c['d'] = 4;
      expect(c['a'], 1);
      expect(c['b'], isNull);
      expect(c['c'], 3);
      expect(c['d'], 4);
    });

    test('updating existing key does not exceed capacity', () {
      final c = LruCache<String, int>(2);
      c['a'] = 1;
      c['b'] = 2;
      c['a'] = 99; // overwrite — should not trigger eviction
      expect(c.length, 2);
      expect(c['a'], 99);
      expect(c['b'], 2);
    });

    test('remove and containsKey', () {
      final c = LruCache<String, int>(3);
      c['a'] = 1;
      expect(c.containsKey('a'), isTrue);
      c.remove('a');
      expect(c.containsKey('a'), isFalse);
      expect(c['a'], isNull);
    });

    test('clear empties the cache', () {
      final c = LruCache<String, int>(3);
      c['a'] = 1;
      c['b'] = 2;
      c.clear();
      expect(c.length, 0);
      expect(c['a'], isNull);
    });

    test('capacity assertion', () {
      expect(() => LruCache<String, int>(0), throwsA(isA<AssertionError>()));
      expect(() => LruCache<String, int>(-1), throwsA(isA<AssertionError>()));
    });
  });
}
