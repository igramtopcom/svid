import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svid/features/downloads/data/repositories/collection_repository.dart';
import 'package:svid/features/downloads/domain/entities/collection_entity.dart';
import 'package:svid/features/downloads/presentation/providers/collection_providers.dart';
import 'package:svid/features/downloads/presentation/screens/collections_screen.dart';
import 'package:svid/core/services/secure_credential_store.dart';
import 'package:svid/features/premium/data/datasources/premium_local_datasource.dart';
import 'package:svid/features/premium/domain/services/premium_license_service.dart';
import 'package:svid/features/premium/presentation/providers/premium_providers.dart';
import 'package:svid/features/settings/presentation/providers/settings_provider.dart';

import '../../../../helpers/brand_test_keys.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeSecureStorage {
  final Map<String, String> _store = {};
  Future<String?> read({required String key}) async => _store[key];
  Future<void> write({required String key, required String value}) async =>
      _store[key] = value;
  Future<void> delete({required String key}) async => _store.remove(key);
}

class _TestDatasource extends PremiumLocalDatasource {
  final _FakeSecureStorage _fakeSecure;

  _TestDatasource(SharedPreferences prefs)
      : _fakeSecure = _FakeSecureStorage(),
        super(prefs, SecureCredentialStore(prefs));

  @override
  Future<String?> getLicenseKey() async =>
      _fakeSecure.read(key: 'premium_license_key');
  @override
  Future<void> saveLicenseKey(String key) async =>
      _fakeSecure.write(key: 'premium_license_key', value: key);
  @override
  Future<void> deleteLicenseKey() async =>
      _fakeSecure.delete(key: 'premium_license_key');
}

class _FakeCollectionRepository implements CollectionRepository {
  final List<CollectionEntity> _collections;
  _FakeCollectionRepository([this._collections = const []]);

  @override
  Future<List<CollectionEntity>> getAll() async => _collections;
  @override
  Future<void> saveAll(List<CollectionEntity> collections) async {}
}

// ── Test helper ───────────────────────────────────────────────────────────────

void main() {
  late SharedPreferences prefs;
  late _TestDatasource datasource;
  late PremiumLicenseService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    datasource = _TestDatasource(prefs);
    service = PremiumLicenseService(datasource);
  });

  Widget buildApp({
    List<CollectionEntity> collections = const [],
    List<Override> extraOverrides = const [],
  }) {
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        premiumLocalDatasourceProvider.overrideWithValue(datasource),
        premiumLicenseServiceProvider.overrideWithValue(service),
        collectionRepositoryProvider
            .overrideWithValue(_FakeCollectionRepository(collections)),
        // Bypass downloads notifier dependency for counts
        collectionCountsProvider.overrideWith((ref) => {}),
        ...extraOverrides,
      ],
      child: const MaterialApp(
        home: CollectionsScreen(),
      ),
    );
  }

  group('CollectionsScreen PremiumGate — free user', () {
    testWidgets('sees lock overlay', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    });

    testWidgets('sees lock icon in gate overlay', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Redesigned gate uses lock_rounded as the primary icon
      expect(
        find.byIcon(Icons.lock_rounded),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('content is rendered behind IgnorePointer (blurred)',
        (tester) async {
      await tester.pumpWidget(buildApp(collections: [
        CollectionEntity(
          id: 'test-id',
          name: 'Favorites',
          description: '',
          filter: const CollectionFilter(),
          createdAt: DateTime(2026, 1, 1),
        ),
      ]));
      await tester.pumpAndSettle();

      // Lock visible → gated
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      // PremiumGate wraps child in IgnorePointer(ignoring: true) when locked
      // Redesigned gate has 2 IgnorePointer layers (blurred content + glass frost)
      final ignorePointers = tester
          .widgetList<IgnorePointer>(find.byType(IgnorePointer))
          .where((w) => w.ignoring)
          .toList();
      expect(ignorePointers.length, greaterThanOrEqualTo(1));
    });
  });

  group('CollectionsScreen PremiumGate — premium user', () {
    setUp(() async {
      await service.activateLicense(TestLicenseKeys.valid);
    });

    testWidgets('no lock overlay', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.lock_rounded), findsNothing);
    });

    testWidgets('add button visible in app bar', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // AppBar action button has Icons.add
      expect(find.byIcon(Icons.add), findsAtLeastNWidgets(1));
    });

    testWidgets('collections list renders items', (tester) async {
      final col = CollectionEntity(
        id: 'col-1',
        name: 'My Videos',
        description: 'Test desc',
        filter: const CollectionFilter(),
        createdAt: DateTime(2026, 1, 1),
      );
      await tester.pumpWidget(buildApp(collections: [col]));
      await tester.pumpAndSettle();

      expect(find.text('My Videos'), findsOneWidget);
    });

    testWidgets('empty state shows when no collections', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.folder_special_outlined), findsWidgets);
    });
  });
}
