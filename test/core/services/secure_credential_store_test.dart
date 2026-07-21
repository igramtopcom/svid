import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake FlutterSecureStorage that uses in-memory map.
/// Tests can toggle [shouldThrow] to simulate platform failures.
class _FakeSecureStorage {
  final Map<String, String> _store = {};
  bool shouldThrow = false;

  Future<String?> read(String key) async {
    if (shouldThrow) throw Exception('Secure storage unavailable');
    return _store[key];
  }

  Future<void> write(String key, String value) async {
    if (shouldThrow) throw Exception('Secure storage unavailable');
    _store[key] = value;
  }

  Future<void> delete(String key) async {
    if (shouldThrow) throw Exception('Secure storage unavailable');
    _store.remove(key);
  }
}

/// Testable credential store that uses fake secure storage.
/// Reimplements the same logic as SecureCredentialStore but with injectable fakes.
class _TestableCredentialStore {
  final SharedPreferences prefs;
  final _FakeSecureStorage secure;

  static const _migrationDoneKey = 'secure_storage_migrated';
  static const _secretKeys = [
    'backend_api_key',
    'device_id',
    'premium_license_key',
  ];

  _TestableCredentialStore(this.prefs, this.secure);

  Future<void> migrateIfNeeded() async {
    if (prefs.getBool(_migrationDoneKey) == true) return;

    var allMigrated = true;
    for (final key in _secretKeys) {
      final value = prefs.getString(key);
      if (value == null || value.isEmpty) continue;
      try {
        await secure.write(key, value);
        await prefs.remove(key);
      } catch (_) {
        allMigrated = false;
      }
    }

    if (allMigrated) {
      await prefs.setBool(_migrationDoneKey, true);
    }
  }

  Future<String?> read(String key) async {
    try {
      final value = await secure.read(key);
      if (value != null && value.isNotEmpty) return value;
    } catch (_) {}
    return prefs.getString(key);
  }

  Future<void> write(String key, String value) async {
    try {
      await secure.write(key, value);
      if (prefs.containsKey(key)) {
        await prefs.remove(key);
      }
      return;
    } catch (_) {}
    await prefs.setString(key, value);
  }

  Future<void> delete(String key) async {
    try {
      await secure.delete(key);
    } catch (_) {}
    await prefs.remove(key);
  }

  Future<bool> containsKey(String key) async {
    try {
      final value = await secure.read(key);
      if (value != null && value.isNotEmpty) return true;
    } catch (_) {}
    return prefs.containsKey(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late _FakeSecureStorage fakeSecure;
  late _TestableCredentialStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    fakeSecure = _FakeSecureStorage();
    store = _TestableCredentialStore(prefs, fakeSecure);
  });

  group('SecureCredentialStore logic', () {
    group('read', () {
      test('returns value from secure storage when available', () async {
        fakeSecure._store['test_key'] = 'secure_value';
        final result = await store.read('test_key');
        expect(result, 'secure_value');
      });

      test('falls back to SharedPreferences when secure storage empty', () async {
        await prefs.setString('test_key', 'prefs_value');
        final result = await store.read('test_key');
        expect(result, 'prefs_value');
      });

      test('falls back to SharedPreferences when secure storage throws', () async {
        await prefs.setString('test_key', 'fallback_value');
        fakeSecure.shouldThrow = true;
        final result = await store.read('test_key');
        expect(result, 'fallback_value');
      });

      test('returns null when key not in either store', () async {
        final result = await store.read('nonexistent');
        expect(result, isNull);
      });

      test('prefers secure storage over SharedPreferences', () async {
        fakeSecure._store['key'] = 'secure';
        await prefs.setString('key', 'prefs');
        final result = await store.read('key');
        expect(result, 'secure');
      });
    });

    group('write', () {
      test('writes to secure storage and removes from SharedPreferences', () async {
        await prefs.setString('key', 'old_prefs_value');
        await store.write('key', 'new_value');
        expect(fakeSecure._store['key'], 'new_value');
        expect(prefs.getString('key'), isNull);
      });

      test('falls back to SharedPreferences when secure storage throws', () async {
        fakeSecure.shouldThrow = true;
        await store.write('key', 'fallback_value');
        expect(fakeSecure._store['key'], isNull);
        expect(prefs.getString('key'), 'fallback_value');
      });

      test('writes to secure storage on success', () async {
        await store.write('api_key', 'snk_test123');
        expect(fakeSecure._store['api_key'], 'snk_test123');
      });
    });

    group('delete', () {
      test('deletes from both stores', () async {
        fakeSecure._store['key'] = 'value';
        await prefs.setString('key', 'value');
        await store.delete('key');
        expect(fakeSecure._store.containsKey('key'), isFalse);
        expect(prefs.containsKey('key'), isFalse);
      });

      test('still deletes from SharedPreferences when secure storage throws', () async {
        await prefs.setString('key', 'value');
        fakeSecure.shouldThrow = true;
        await store.delete('key');
        expect(prefs.containsKey('key'), isFalse);
      });
    });

    group('containsKey', () {
      test('returns true when in secure storage', () async {
        fakeSecure._store['key'] = 'value';
        expect(await store.containsKey('key'), isTrue);
      });

      test('returns true when in SharedPreferences only', () async {
        await prefs.setString('key', 'value');
        expect(await store.containsKey('key'), isTrue);
      });

      test('returns false when in neither', () async {
        expect(await store.containsKey('key'), isFalse);
      });

      test('returns false for empty string in secure storage', () async {
        fakeSecure._store['key'] = '';
        expect(await store.containsKey('key'), isFalse);
      });
    });

    group('migrateIfNeeded', () {
      test('migrates secrets from SharedPreferences to secure storage', () async {
        await prefs.setString('backend_api_key', 'snk_test');
        await prefs.setString('device_id', 'dev_123');
        await prefs.setString('premium_license_key', 'lic_abc');

        await store.migrateIfNeeded();

        // Should be in secure storage
        expect(fakeSecure._store['backend_api_key'], 'snk_test');
        expect(fakeSecure._store['device_id'], 'dev_123');
        expect(fakeSecure._store['premium_license_key'], 'lic_abc');

        // Should be removed from SharedPreferences
        expect(prefs.getString('backend_api_key'), isNull);
        expect(prefs.getString('device_id'), isNull);
        expect(prefs.getString('premium_license_key'), isNull);

        // Migration flag set
        expect(prefs.getBool('secure_storage_migrated'), isTrue);
      });

      test('skips when already migrated', () async {
        await prefs.setBool('secure_storage_migrated', true);
        await prefs.setString('backend_api_key', 'should_not_migrate');

        await store.migrateIfNeeded();

        // Should NOT have been moved to secure storage
        expect(fakeSecure._store['backend_api_key'], isNull);
        // Should still be in SharedPreferences
        expect(prefs.getString('backend_api_key'), 'should_not_migrate');
      });

      test('skips empty values', () async {
        await prefs.setString('backend_api_key', '');

        await store.migrateIfNeeded();

        expect(fakeSecure._store.containsKey('backend_api_key'), isFalse);
        expect(prefs.getBool('secure_storage_migrated'), isTrue);
      });

      test('does not set flag when secure storage fails (will retry next launch)', () async {
        await prefs.setString('backend_api_key', 'snk_test');
        await prefs.setString('device_id', 'dev_123');
        fakeSecure.shouldThrow = true;

        await store.migrateIfNeeded();

        // Secrets should stay in SharedPreferences (fallback)
        expect(prefs.getString('backend_api_key'), 'snk_test');
        expect(prefs.getString('device_id'), 'dev_123');

        // Migration flag NOT set (will retry next launch)
        expect(prefs.getBool('secure_storage_migrated'), isNull);
      });

      test('migrates only existing keys, ignores missing ones', () async {
        // Only set one key
        await prefs.setString('device_id', 'dev_456');

        await store.migrateIfNeeded();

        expect(fakeSecure._store.length, 1);
        expect(fakeSecure._store['device_id'], 'dev_456');
        expect(prefs.getBool('secure_storage_migrated'), isTrue);
      });

      test('is idempotent — second call is a no-op', () async {
        await prefs.setString('backend_api_key', 'snk_test');

        await store.migrateIfNeeded();
        expect(fakeSecure._store['backend_api_key'], 'snk_test');

        // Write something new to prefs after migration
        await prefs.setString('backend_api_key', 'snk_new');

        // Second call should skip (flag is set)
        await store.migrateIfNeeded();

        // Secure storage should still have original
        expect(fakeSecure._store['backend_api_key'], 'snk_test');
        // Prefs should still have the new one (not migrated again)
        expect(prefs.getString('backend_api_key'), 'snk_new');
      });
    });

    group('end-to-end: write then read across stores', () {
      test('write to secure → read from secure', () async {
        await store.write('key', 'value');
        final result = await store.read('key');
        expect(result, 'value');
      });

      test('fallback write → fallback read', () async {
        fakeSecure.shouldThrow = true;
        await store.write('key', 'value');
        final result = await store.read('key');
        expect(result, 'value');
      });

      test('write secure → secure fails on read → falls back to null', () async {
        await store.write('key', 'value');
        expect(fakeSecure._store['key'], 'value');
        expect(prefs.containsKey('key'), isFalse); // cleaned up from prefs

        fakeSecure.shouldThrow = true;
        // Now secure throws, prefs is empty → null
        final result = await store.read('key');
        expect(result, isNull);
      });

      test('delete removes from both, subsequent read returns null', () async {
        await store.write('key', 'value');
        await prefs.setString('key', 'prefs_backup');
        await store.delete('key');
        final result = await store.read('key');
        expect(result, isNull);
      });
    });
  });
}
