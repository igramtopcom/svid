import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../presentation/providers/settings_provider.dart';

class FormatPreset {
  final String name;
  final int maxResolution;
  final String videoCodec;
  final String audioCodec;
  final String containerFormat;
  final String fpsPreference;
  final DateTime createdAt;

  const FormatPreset({
    required this.name,
    required this.maxResolution,
    required this.videoCodec,
    required this.audioCodec,
    required this.containerFormat,
    required this.fpsPreference,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'maxResolution': maxResolution,
        'videoCodec': videoCodec,
        'audioCodec': audioCodec,
        'containerFormat': containerFormat,
        'fpsPreference': fpsPreference,
        'createdAt': createdAt.toIso8601String(),
      };

  factory FormatPreset.fromJson(Map<String, dynamic> json) => FormatPreset(
        name: json['name'] as String,
        maxResolution: json['maxResolution'] as int,
        videoCodec: json['videoCodec'] as String,
        audioCodec: json['audioCodec'] as String,
        containerFormat: json['containerFormat'] as String,
        fpsPreference: json['fpsPreference'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class FormatPresetsNotifier extends StateNotifier<List<FormatPreset>> {
  static const _key = 'format_presets';
  final SharedPreferences _prefs;

  FormatPresetsNotifier(this._prefs) : super([]) {
    _load();
  }

  void _load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    final list = (jsonDecode(raw) as List)
        .map((e) => FormatPreset.fromJson(e as Map<String, dynamic>))
        .toList();
    state = list;
  }

  Future<void> _save() async {
    await _prefs.setString(
        _key, jsonEncode(state.map((e) => e.toJson()).toList()));
  }

  Future<void> add(FormatPreset preset) async {
    state = [...state, preset];
    await _save();
  }

  Future<void> remove(String name) async {
    state = state.where((p) => p.name != name).toList();
    await _save();
  }
}

final formatPresetsProvider =
    StateNotifierProvider<FormatPresetsNotifier, List<FormatPreset>>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return FormatPresetsNotifier(prefs);
});
