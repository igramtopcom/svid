import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../data/repositories/sorting_rule_repository.dart';
import '../../domain/entities/sorting_rule.dart';
import '../../domain/services/sorting_rule_service.dart';

// ── Repository provider ──────────────────────────────────────────────────────

final sortingRuleRepositoryProvider = Provider<SortingRuleRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SharedPrefsSortingRuleRepository(prefs);
});

// ── Service provider ─────────────────────────────────────────────────────────

final sortingRuleServiceProvider = Provider<SortingRuleService>((ref) {
  return SortingRuleService();
});

// ── State ────────────────────────────────────────────────────────────────────

class SortingRulesNotifier extends StateNotifier<List<SortingRule>> {
  final SortingRuleRepository _repo;

  SortingRulesNotifier(this._repo) : super([]) {
    _load();
  }

  Future<void> _load() async {
    state = await _repo.getAllRules();
  }

  Future<void> addRule(SortingRule rule) async {
    state = [...state, rule];
    await _repo.saveRules(state);
  }

  Future<void> updateRule(SortingRule updated) async {
    state = [
      for (final r in state)
        if (r.id == updated.id) updated else r,
    ];
    await _repo.saveRules(state);
  }

  Future<void> deleteRule(String id) async {
    state = state.where((r) => r.id != id).toList();
    await _repo.saveRules(state);
  }

  Future<void> toggleEnabled(String id) async {
    state = [
      for (final r in state)
        if (r.id == id) r.copyWith(isEnabled: !r.isEnabled) else r,
    ];
    await _repo.saveRules(state);
  }

  /// Reorder: move item at [oldIndex] to [newIndex].
  Future<void> reorder(int oldIndex, int newIndex) async {
    final list = List<SortingRule>.from(state);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, item);
    // Reassign order values
    state = [
      for (int i = 0; i < list.length; i++) list[i].copyWith(order: i),
    ];
    await _repo.saveRules(state);
  }
}

final sortingRulesProvider =
    StateNotifierProvider<SortingRulesNotifier, List<SortingRule>>((ref) {
  final repo = ref.watch(sortingRuleRepositoryProvider);
  return SortingRulesNotifier(repo);
});
