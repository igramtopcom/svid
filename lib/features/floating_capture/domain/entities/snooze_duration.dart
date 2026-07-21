/// Snooze duration options for the floating capture popup, per spec Q13.
///
/// When the user selects a snooze duration, the floating capture monitor
/// stops emitting popups for that period; the next URL copy after the
/// snooze elapses re-engages normal behavior.
enum SnoozeDuration {
  /// Snooze for 30 minutes.
  thirtyMinutes,

  /// Snooze for 1 hour.
  oneHour,

  /// Snooze for 4 hours.
  fourHours,

  /// Snooze for 1 day (24 hours from the moment of selection).
  ///
  /// Codex audit P1 #7: previously this variant was `untilEndOfDay` —
  /// at 23:50 the user got 10 minutes of snooze, not the spec-defined
  /// "1 day". The wireKey accepts the legacy "untilEndOfDay" string for
  /// backward compatibility (see [snoozeDurationFromWire]).
  oneDay,

  /// Snooze indefinitely until user re-enables capture in settings.
  untilManuallyResumed,
}

extension SnoozeDurationX on SnoozeDuration {
  /// Wire format used in IPC payloads — stable string keys (NOT enum index)
  /// so adding a new variant doesn't break existing serialized state.
  String get wireKey {
    switch (this) {
      case SnoozeDuration.thirtyMinutes:
        return 'thirtyMinutes';
      case SnoozeDuration.oneHour:
        return 'oneHour';
      case SnoozeDuration.fourHours:
        return 'fourHours';
      case SnoozeDuration.oneDay:
        return 'oneDay';
      case SnoozeDuration.untilManuallyResumed:
        return 'untilManuallyResumed';
    }
  }

  /// Resolve the absolute end time for this snooze, given a reference now.
  ///
  /// Returns null for [untilManuallyResumed] — that variant has no time-based
  /// expiry; capture stays paused until user toggles it back on.
  DateTime? resolveEnd(DateTime now) {
    switch (this) {
      case SnoozeDuration.thirtyMinutes:
        return now.add(const Duration(minutes: 30));
      case SnoozeDuration.oneHour:
        return now.add(const Duration(hours: 1));
      case SnoozeDuration.fourHours:
        return now.add(const Duration(hours: 4));
      case SnoozeDuration.oneDay:
        // 24 hours from now (spec §13). NOT "until midnight" — at
        // 23:50 the user expects ~24h of quiet, not 10 minutes.
        return now.add(const Duration(days: 1));
      case SnoozeDuration.untilManuallyResumed:
        return null;
    }
  }
}

/// Forward-compatible deserialization. Returns null for unknown wire keys
/// so callers can decide whether to silently ignore or surface as error.
///
/// Backward-compat: the legacy `untilEndOfDay` wireKey (Phase 1A.5,
/// before the Codex audit P1 #7 fix) is mapped to `oneDay` so existing
/// persisted snooze state migrates seamlessly.
SnoozeDuration? snoozeDurationFromWire(String? wire) {
  if (wire == null) return null;
  if (wire == 'untilEndOfDay') return SnoozeDuration.oneDay;
  for (final v in SnoozeDuration.values) {
    if (v.wireKey == wire) return v;
  }
  return null;
}
