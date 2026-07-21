import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/capture_preferences.dart';
import '../../domain/services/capture_preferences_store.dart';

/// Production [CapturePreferencesStore] backed by [SharedPreferences].
/// Stores a single JSON blob under [_kKey]; corrupt or missing payload
/// falls back to [CapturePreferences.defaults] so first-run + downgrade
/// scenarios behave identically (capture defaults ON).
class SharedPreferencesCapturePreferencesStore
    implements CapturePreferencesStore {
  static const _kKey = 'floating_capture.preferences.v1';

  final SharedPreferences _prefs;

  SharedPreferencesCapturePreferencesStore(this._prefs);

  @override
  Future<CapturePreferences> read() async {
    final raw = _prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) return CapturePreferences.defaults;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return CapturePreferences.defaults;
      return CapturePreferences.fromJson(json);
    } catch (e, stack) {
      appLogger.warning(
        '[CapturePrefs] failed to decode persisted state, defaulting',
        e,
        stack,
      );
      return CapturePreferences.defaults;
    }
  }

  @override
  Future<void> write(CapturePreferences prefs) async {
    await _prefs.setString(_kKey, jsonEncode(prefs.toJson()));
  }
}
