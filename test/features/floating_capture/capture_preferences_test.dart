import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/features/floating_capture/data/datasources/in_memory_capture_preferences_store.dart';
import 'package:ssvid/features/floating_capture/domain/entities/capture_preferences.dart';
import 'package:ssvid/features/floating_capture/domain/services/capture_preferences_store.dart';
import 'package:ssvid/features/floating_capture/presentation/providers/capture_preferences_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CapturePreferences entity', () {
    test('default is enabled (spec Q6)', () {
      expect(CapturePreferences.defaults.enabled, isTrue);
    });

    test('JSON round-trip preserves enabled flag', () {
      const orig = CapturePreferences(enabled: false);
      final round = CapturePreferences.fromJson(orig.toJson());
      expect(round, orig);
    });

    test('missing enabled field falls back to default (forward-compat)',
        () {
      final loaded = CapturePreferences.fromJson({});
      expect(loaded.enabled, CapturePreferences.defaults.enabled);
    });

    test('non-bool enabled value falls back to default', () {
      final loaded = CapturePreferences.fromJson({'enabled': 'yes'});
      expect(loaded.enabled, CapturePreferences.defaults.enabled);
    });

    test('copyWith preserves unchanged + replaces specified', () {
      const a = CapturePreferences(enabled: true);
      final b = a.copyWith(enabled: false);
      expect(b.enabled, isFalse);
      expect(a.enabled, isTrue, reason: 'original unchanged');
    });

    test('equality + hashCode', () {
      const a = CapturePreferences(enabled: true);
      const b = CapturePreferences(enabled: true);
      const c = CapturePreferences(enabled: false);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('InMemoryCapturePreferencesStore', () {
    test('starts with defaults when no initial', () async {
      final store = InMemoryCapturePreferencesStore();
      expect(await store.read(), CapturePreferences.defaults);
    });

    test('initial state reflected', () async {
      final store = InMemoryCapturePreferencesStore(
        initial: const CapturePreferences(enabled: false),
      );
      expect((await store.read()).enabled, isFalse);
    });

    test('write then read returns new state', () async {
      final store = InMemoryCapturePreferencesStore();
      const next = CapturePreferences(enabled: false);
      await store.write(next);
      expect(await store.read(), next);
      expect(store.writes, [next]);
    });

    test('readCount tracks reads', () async {
      final store = InMemoryCapturePreferencesStore();
      await store.read();
      await store.read();
      expect(store.readCount, 2);
    });
  });

  group('CapturePreferencesNotifier', () {
    /// Build a ProviderContainer with the in-memory store overriding the
    /// default SharedPreferences-backed one.
    ProviderContainer makeContainer({CapturePreferences? initial}) {
      final store = InMemoryCapturePreferencesStore(initial: initial);
      return ProviderContainer(
        overrides: [
          capturePreferencesStoreProvider
              .overrideWith((ref) => store),
        ],
      );
    }

    test('initial state is defaults until load completes', () async {
      final c = makeContainer(
        initial: const CapturePreferences(enabled: false),
      );
      addTearDown(c.dispose);

      // First read — load not yet awaited.
      expect(c.read(capturePreferencesNotifierProvider).enabled, isTrue);

      // Pump microtasks for async _load() to settle.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        c.read(capturePreferencesNotifierProvider).enabled,
        isFalse,
        reason: 'persisted value should override default after load',
      );
    });

    test('setEnabled updates state + persists to store', () async {
      final store = InMemoryCapturePreferencesStore();
      final c = ProviderContainer(
        overrides: [
          capturePreferencesStoreProvider.overrideWith((ref) => store),
        ],
      );
      addTearDown(c.dispose);

      await Future<void>.delayed(Duration.zero); // let initial load settle

      await c
          .read(capturePreferencesNotifierProvider.notifier)
          .setEnabled(false);

      expect(c.read(capturePreferencesNotifierProvider).enabled, isFalse);
      expect(store.writes.last.enabled, isFalse);
    });

    test('store throw on write keeps in-memory state (UI reflects intent)',
        () async {
      final flakyStore = _ThrowOnWriteStore();
      final c = ProviderContainer(
        overrides: [
          capturePreferencesStoreProvider.overrideWith((ref) => flakyStore),
        ],
      );
      addTearDown(c.dispose);

      await Future<void>.delayed(Duration.zero);

      // setEnabled should NOT throw to caller even if persistence fails.
      await c
          .read(capturePreferencesNotifierProvider.notifier)
          .setEnabled(false);

      expect(
        c.read(capturePreferencesNotifierProvider).enabled,
        isFalse,
        reason: 'state reflects user intent; persistence is best-effort',
      );
    });
  });
}

class _ThrowOnWriteStore implements CapturePreferencesStore {
  @override
  Future<CapturePreferences> read() async => CapturePreferences.defaults;

  @override
  Future<void> write(CapturePreferences prefs) async {
    throw StateError('persistence broken');
  }
}
