import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/collection_entity.dart';

const _kPrefsKey = 'collections_data';

/// Abstract contract for persisting [CollectionEntity]s.
abstract class CollectionRepository {
  Future<List<CollectionEntity>> getAll();
  Future<void> saveAll(List<CollectionEntity> collections);
}

/// [SharedPreferences]-backed implementation (JSON array under [_kPrefsKey]).
class SharedPrefsCollectionRepository implements CollectionRepository {
  final SharedPreferences _prefs;

  SharedPrefsCollectionRepository(this._prefs);

  @override
  Future<List<CollectionEntity>> getAll() async {
    final raw = _prefs.getString(_kPrefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => CollectionEntity.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> saveAll(List<CollectionEntity> collections) async {
    final encoded =
        jsonEncode(collections.map((c) => c.toJson()).toList());
    await _prefs.setString(_kPrefsKey, encoded);
  }
}
