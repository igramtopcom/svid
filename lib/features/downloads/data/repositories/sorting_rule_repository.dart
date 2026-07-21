import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/sorting_rule.dart';

const _kPrefsKey = 'sorting_rules_data';

/// Abstract contract for storing and retrieving [SortingRule]s.
abstract class SortingRuleRepository {
  Future<List<SortingRule>> getAllRules();
  Future<void> saveRules(List<SortingRule> rules);
}

/// [SharedPreferences]-backed implementation (JSON array under [_kPrefsKey]).
class SharedPrefsSortingRuleRepository implements SortingRuleRepository {
  final SharedPreferences _prefs;

  SharedPrefsSortingRuleRepository(this._prefs);

  @override
  Future<List<SortingRule>> getAllRules() async {
    final raw = _prefs.getString(_kPrefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => SortingRule.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> saveRules(List<SortingRule> rules) async {
    final encoded = jsonEncode(rules.map((r) => r.toJson()).toList());
    await _prefs.setString(_kPrefsKey, encoded);
  }
}
