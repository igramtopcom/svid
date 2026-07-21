/// Service that determines whether the current time falls within a "quiet
/// hours" window and computes the effective bandwidth cap to apply.
class QuietHoursService {
  const QuietHoursService();

  /// Returns `true` when [now] is inside the quiet-hours window defined by
  /// [startHour] and [endHour] (both 0–23, local time).
  ///
  /// Handles overnight windows (e.g., 22:00–07:00) correctly.
  bool isQuietHour({
    required DateTime now,
    required int startHour,
    required int endHour,
  }) {
    final h = now.hour;
    if (startHour <= endHour) {
      // Same-day window (e.g., 09:00–17:00)
      return h >= startHour && h < endHour;
    } else {
      // Overnight window (e.g., 22:00–07:00)
      return h >= startHour || h < endHour;
    }
  }

  /// Returns the effective global bandwidth cap in KB/s:
  /// - If quiet hours is enabled AND [now] is inside the window → [quietKbps].
  /// - Otherwise → [normalKbps] (0 = unlimited).
  int getEffectiveLimitKbps({
    required DateTime now,
    required bool enabled,
    required int startHour,
    required int endHour,
    required int quietKbps,
    required int normalKbps,
  }) {
    if (!enabled) return normalKbps;
    return isQuietHour(now: now, startHour: startHour, endHour: endHour)
        ? quietKbps
        : normalKbps;
  }
}
