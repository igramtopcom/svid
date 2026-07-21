import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/floating_capture/data/datasources/in_memory_window_position_store.dart';
import 'package:svid/features/floating_capture/domain/entities/window_position.dart';

void main() {
  group('WindowPosition entity', () {
    test('JSON round-trip preserves coordinates', () {
      const orig = WindowPosition(x: 123.5, y: 456.25);
      final round = WindowPosition.fromJson(orig.toJson());
      expect(round, orig);
    });

    test('integer coordinates from JSON parse as double', () {
      final loaded = WindowPosition.fromJson({'x': 100, 'y': 200});
      expect(loaded?.x, 100.0);
      expect(loaded?.y, 200.0);
    });

    test('missing x returns null (forward-compat)', () {
      expect(WindowPosition.fromJson({'y': 0}), isNull);
    });

    test('missing y returns null', () {
      expect(WindowPosition.fromJson({'x': 0}), isNull);
    });

    test('non-numeric coordinates return null', () {
      expect(
        WindowPosition.fromJson({'x': 'left', 'y': 100}),
        isNull,
      );
    });

    test('equality + hashCode', () {
      const a = WindowPosition(x: 1, y: 2);
      const b = WindowPosition(x: 1, y: 2);
      const c = WindowPosition(x: 1, y: 3);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('negative coordinates preserved (multi-monitor: secondary screen on left)',
        () {
      const p = WindowPosition(x: -1920, y: 100);
      final round = WindowPosition.fromJson(p.toJson());
      expect(round, p);
    });
  });

  group('InMemoryWindowPositionStore', () {
    test('starts null when no initial', () async {
      final store = InMemoryWindowPositionStore();
      expect(await store.read(), isNull);
    });

    test('initial position reflected', () async {
      final store = InMemoryWindowPositionStore(
        initial: const WindowPosition(x: 50, y: 60),
      );
      expect((await store.read())?.x, 50);
    });

    test('write replaces and is read back', () async {
      final store = InMemoryWindowPositionStore();
      const p = WindowPosition(x: 10, y: 20);
      await store.write(p);
      expect(await store.read(), p);
      expect(store.writes, [p]);
    });

    test('readCount tracks reads', () async {
      final store = InMemoryWindowPositionStore();
      await store.read();
      await store.read();
      expect(store.readCount, 2);
    });
  });
}
