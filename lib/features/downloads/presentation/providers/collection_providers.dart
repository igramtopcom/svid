import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../data/repositories/collection_repository.dart';
import '../../domain/entities/collection_entity.dart';
import '../../domain/entities/download_entity.dart';
import 'downloads_notifier.dart';
import '../../domain/services/tagging_service.dart';

// ── Repository ───────────────────────────────────────────────────────────────

final collectionRepositoryProvider = Provider<CollectionRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SharedPrefsCollectionRepository(prefs);
});

// ── Notifier ─────────────────────────────────────────────────────────────────

class CollectionNotifier extends StateNotifier<List<CollectionEntity>> {
  final CollectionRepository _repo;

  CollectionNotifier(this._repo) : super([]) {
    _load();
  }

  Future<void> _load() async {
    state = await _repo.getAll();
  }

  Future<void> addCollection(CollectionEntity collection) async {
    state = [...state, collection];
    await _repo.saveAll(state);
  }

  Future<void> updateCollection(CollectionEntity updated) async {
    state = [
      for (final c in state)
        if (c.id == updated.id) updated else c,
    ];
    await _repo.saveAll(state);
  }

  Future<void> deleteCollection(String id) async {
    state = state.where((c) => c.id != id).toList();
    await _repo.saveAll(state);
  }
}

final collectionsProvider =
    StateNotifierProvider<CollectionNotifier, List<CollectionEntity>>((ref) {
  final repo = ref.watch(collectionRepositoryProvider);
  return CollectionNotifier(repo);
});

// ── Collection item counts ────────────────────────────────────────────────────

/// Map of collectionId → item count.
/// Recomputes when downloads list OR tags map changes.
final collectionCountsProvider = Provider<Map<String, int>>((ref) {
  final collections = ref.watch(collectionsProvider);
  final downloads = ref.watch(
    downloadsNotifierProvider.select((s) => s.downloads),
  );
  final tagsMap = ref.watch(tagsMapProvider).valueOrNull ?? {};

  return {
    for (final c in collections)
      c.id: c.itemCount(downloads, tagsMap),
  };
});

/// Downloads belonging to a specific collection [collectionId].
final collectionDownloadsProvider =
    Provider.family<List<DownloadEntity>, String>((ref, collectionId) {
  final collections = ref.watch(collectionsProvider);
  final collection = collections.firstWhere(
    (c) => c.id == collectionId,
    orElse: () => CollectionEntity(
      id: collectionId,
      name: '',
      filter: const CollectionFilter(),
      createdAt: DateTime.now(),
    ),
  );
  final downloads = ref.watch(
    downloadsNotifierProvider.select((s) => s.downloads),
  );
  final tagsMap = ref.watch(tagsMapProvider).valueOrNull ?? {};
  return downloads.where((d) => collection.matchesFilter(d, tagsMap)).toList();
});
