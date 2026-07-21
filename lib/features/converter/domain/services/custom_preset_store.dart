import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../entities/conversion_config.dart';
import '../entities/conversion_preset.dart';

/// Persists user-created conversion presets in SharedPreferences.
///
/// Stored as a JSON array under [_storageKey]. Each entry serializes the
/// preset's id, name, icon, description, and the wrapped [ConversionConfig]
/// (which has its own JSON round-trip helpers). Custom presets always live
/// in [PresetCategory.custom] and are never premium-locked — the user just
/// saved them, so they own them.
class CustomPresetStore {
  static const String _storageKey = 'converter.customPresets';

  final SharedPreferences _prefs;

  CustomPresetStore(this._prefs);

  /// Load all custom presets. Returns an empty list if none exist or the
  /// stored payload is corrupt (corruption is logged via the rethrown decode
  /// error so callers can decide how to surface it; the public API treats it
  /// as "no presets" for graceful degradation).
  List<ConversionPreset> loadAll() {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(_fromJson)
          .whereType<ConversionPreset>()
          .toList();
    } catch (_) {
      // Corrupted store — fail safe by returning empty so the UI still works.
      return const [];
    }
  }

  /// Persist [presets] as the full custom-preset list, replacing any existing
  /// stored value. Used by both add and remove flows so callers don't have to
  /// reason about partial updates.
  Future<void> saveAll(List<ConversionPreset> presets) async {
    final encoded = jsonEncode(presets.map(_toJson).toList());
    await _prefs.setString(_storageKey, encoded);
  }

  /// Add [preset] to the stored list and return the updated list. If a preset
  /// with the same id already exists it is replaced (rename/edit semantics).
  Future<List<ConversionPreset>> add(ConversionPreset preset) async {
    final current = loadAll().toList();
    final existing = current.indexWhere((p) => p.id == preset.id);
    if (existing >= 0) {
      current[existing] = preset;
    } else {
      current.add(preset);
    }
    await saveAll(current);
    return current;
  }

  /// Remove the preset with [id] and return the updated list.
  Future<List<ConversionPreset>> remove(String id) async {
    final current = loadAll().where((p) => p.id != id).toList();
    await saveAll(current);
    return current;
  }

  // ────────────────────────────────────────────────────────────────
  // Serialization helpers
  // ────────────────────────────────────────────────────────────────

  Map<String, dynamic> _toJson(ConversionPreset preset) {
    return {
      'id': preset.id,
      'name': preset.name,
      'icon': preset.icon,
      'description': preset.description,
      'config': preset.config.toJsonString(),
    };
  }

  ConversionPreset? _fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final icon = json['icon'];
    final description = json['description'];
    final configStr = json['config'];
    if (id is! String ||
        name is! String ||
        icon is! String ||
        description is! String ||
        configStr is! String) {
      return null;
    }
    try {
      final config = ConversionConfig.fromJsonString(configStr);
      return ConversionPreset(
        id: id,
        name: name,
        icon: icon,
        description: description,
        config: config,
        category: PresetCategory.custom,
      );
    } catch (_) {
      // Skip individual entries with corrupt config payloads.
      return null;
    }
  }
}
