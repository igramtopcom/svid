import 'package:shared_preferences/shared_preferences.dart';

/// Manages update check scheduling with configurable cooldown.
///
/// Uses SharedPreferences to persist last check timestamp.
/// Default cooldown: 2 hours.
class UpdateScheduleService {
  static const String _lastCheckKey = 'last_ytdlp_update_check';
  static const Duration defaultCooldown = Duration(hours: 2);

  final SharedPreferences _prefs;
  final DateTime Function() _clock;

  UpdateScheduleService(
    this._prefs, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Returns true if enough time has elapsed since last check.
  bool shouldCheckForUpdate({Duration cooldown = defaultCooldown}) {
    final lastCheckStr = _prefs.getString(_lastCheckKey);
    if (lastCheckStr == null) return true; // Never checked

    try {
      final lastCheck = DateTime.parse(lastCheckStr);
      final elapsed = _clock().difference(lastCheck);
      return elapsed >= cooldown;
    } catch (_) {
      return true; // Corrupted data → allow check
    }
  }

  /// Record the current time as last check time.
  Future<void> recordCheckTime() async {
    await _prefs.setString(_lastCheckKey, _clock().toIso8601String());
  }

  /// Get the last check time (for display purposes).
  DateTime? getLastCheckTime() {
    final lastCheckStr = _prefs.getString(_lastCheckKey);
    if (lastCheckStr == null) return null;
    try {
      return DateTime.parse(lastCheckStr);
    } catch (_) {
      return null;
    }
  }
}
