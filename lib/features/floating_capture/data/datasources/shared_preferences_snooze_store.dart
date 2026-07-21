import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/snooze_state.dart';
import '../../domain/services/snooze_store.dart';

/// Production [SnoozeStore] backed by [SharedPreferences]. Stores a single
/// JSON blob under [_kKey] — versioned so future schema changes can ship
/// alongside a migration without trampling existing data.
class SharedPreferencesSnoozeStore implements SnoozeStore {
  static const _kKey = 'floating_capture.snooze_state.v1';

  final SharedPreferences _prefs;

  SharedPreferencesSnoozeStore(this._prefs);

  @override
  Future<SnoozeState> read() async {
    final raw = _prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) return SnoozeState.inactive;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return SnoozeState.inactive;
      return SnoozeState.fromJson(json);
    } catch (e, stack) {
      // Corrupted prefs blob — treat as inactive and overwrite next write.
      appLogger.warning(
        '[SnoozeStore] failed to decode persisted state, falling back to inactive',
        e,
        stack,
      );
      return SnoozeState.inactive;
    }
  }

  @override
  Future<void> write(SnoozeState state) async {
    if (state == SnoozeState.inactive) {
      // Clear the key entirely so a downgraded build sees "no snooze"
      // rather than encountering a payload it doesn't understand.
      await _prefs.remove(_kKey);
      return;
    }
    final json = jsonEncode(state.toJson());
    await _prefs.setString(_kKey, json);
  }
}
