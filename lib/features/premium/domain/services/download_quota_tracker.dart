import 'package:shared_preferences/shared_preferences.dart';

import '../entities/premium_limits.dart';

/// Tracks weekly download count for free-tier quota enforcement.
///
/// Uses [SharedPreferences] to persist count + ISO-week period across app
/// restarts. Auto-resets when the UTC ISO week changes.
class DownloadQuotaTracker {
  static const _countKey = 'download_quota_week_count';
  static const _periodKey = 'download_quota_week_start_utc';
  static const _legacyCountKey = 'download_quota_count';
  static const _legacyDateKey = 'download_quota_date';

  final SharedPreferences _prefs;
  final DateTime Function() _clock;

  DownloadQuotaTracker(this._prefs, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// Current ISO-week start as YYYY-MM-DD (UTC).
  ///
  /// UTC is deliberate: it preserves the previous anti-bypass behavior where
  /// changing the local timezone does not reset quota early.
  String _currentPeriodStr() {
    final now = _clock().toUtc();
    final utcDate = DateTime.utc(now.year, now.month, now.day);
    final weekStart = utcDate.subtract(Duration(days: utcDate.weekday - 1));
    return weekStart.toIso8601String().substring(0, 10);
  }

  /// Number of downloads started in the current weekly period.
  int currentPeriodCount() {
    final storedPeriod = _prefs.getString(_periodKey);
    if (storedPeriod != _currentPeriodStr()) return 0;
    return _prefs.getInt(_countKey) ?? 0;
  }

  /// Whether a new download can be started given the user's tier.
  bool canStartDownload({required bool isPremium}) {
    if (isPremium) return true;
    return currentPeriodCount() < PremiumLimits.freeWeeklyDownloads;
  }

  /// Remaining downloads this week. Returns -1 for unlimited (premium).
  int remainingThisWeek({required bool isPremium}) {
    if (isPremium) return -1;
    return (PremiumLimits.freeWeeklyDownloads - currentPeriodCount()).clamp(
      0,
      PremiumLimits.freeWeeklyDownloads,
    );
  }

  /// Atomically check quota and reserve [count] slots.
  ///
  /// Returns true if reservation succeeded. This combines check + increment
  /// in one synchronous operation to prevent race conditions between
  /// concurrent download starts (SharedPreferences updates in-memory cache
  /// synchronously; only disk write is async).
  bool tryConsume({required bool isPremium, int count = 1}) {
    if (isPremium) return true;

    final period = _currentPeriodStr();
    final storedPeriod = _prefs.getString(_periodKey);

    int current;
    if (storedPeriod != period) {
      current = 0;
      _prefs.setString(_periodKey, period);
    } else {
      current = _prefs.getInt(_countKey) ?? 0;
    }

    if (current + count > PremiumLimits.freeWeeklyDownloads) return false;

    _prefs.setInt(_countKey, current + count);
    return true;
  }

  /// Sync local quota with server-reported consumed count for this week.
  ///
  /// Currently not used by VidCombo PHP because that backend reports legacy
  /// daily counts; startup deliberately ignores it.
  void syncFromServer(int consumed) {
    final period = _currentPeriodStr();
    _prefs.setString(_periodKey, period);
    _prefs.setInt(
      _countKey,
      consumed.clamp(0, PremiumLimits.freeWeeklyDownloads),
    );
  }

  /// Force reset the weekly counter (e.g., on license deactivation).
  Future<void> reset() async {
    await _prefs.remove(_countKey);
    await _prefs.remove(_periodKey);
    await _prefs.remove(_legacyCountKey);
    await _prefs.remove(_legacyDateKey);
  }
}
