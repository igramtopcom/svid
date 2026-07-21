import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/window_position.dart';
import '../../domain/services/window_position_store.dart';

/// Production [WindowPositionStore] — versioned single JSON key under
/// SharedPreferences. Both the main engine's container and the popup
/// engine's instance read the same on-disk file, but only the popup
/// engine writes (it owns the drag listener), so cache staleness across
/// engines is a non-issue.
class SharedPreferencesWindowPositionStore implements WindowPositionStore {
  static const _kKey = 'floating_capture.window_position.v1';

  final SharedPreferences _prefs;

  SharedPreferencesWindowPositionStore(this._prefs);

  @override
  Future<WindowPosition?> read() async {
    final raw = _prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      return WindowPosition.fromJson(json);
    } catch (e, stack) {
      appLogger.warning(
        '[WindowPositionStore] failed to decode persisted position',
        e,
        stack,
      );
      return null;
    }
  }

  @override
  Future<void> write(WindowPosition position) async {
    await _prefs.setString(_kKey, jsonEncode(position.toJson()));
  }
}
