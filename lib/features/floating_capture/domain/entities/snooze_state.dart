import 'snooze_duration.dart';

/// Persistent state describing the current snooze window.
///
/// Three logical states:
/// - **Inactive**: [endsAt] = null AND [duration] = null. Capture runs
///   normally.
/// - **Timed**: [endsAt] is in the future. Capture is paused until [endsAt]
///   (compared with [DateTime.now]).
/// - **Manual**: [duration] = [SnoozeDuration.untilManuallyResumed]. Capture
///   is paused indefinitely; only an explicit
///   `CaptureService.resumeFromSnooze()` clears it.
///
/// Persisted via [SnoozeStore]. The wire format keeps the duration's stable
/// `wireKey` (NOT enum index) so adding a new variant doesn't break
/// previously-saved state.
class SnoozeState {
  /// When the snooze ends. Null = not snoozed.
  /// For [duration] = untilManuallyResumed this is null too — the time is
  /// meaningless; only the [duration] field defines the indefinite state.
  final DateTime? endsAt;

  /// Which option the user picked. Null only when [endsAt] is also null
  /// (i.e., not snoozed).
  final SnoozeDuration? duration;

  const SnoozeState({this.endsAt, this.duration});

  /// Inactive (not snoozed) state. Used as initial state and after
  /// [CaptureService.resumeFromSnooze].
  static const SnoozeState inactive = SnoozeState();

  /// True if capture should be suppressed at the given moment.
  ///
  /// Manual snooze is always active until explicitly cleared.
  /// Timed snooze is active iff [now] is before [endsAt].
  bool isActive(DateTime now) {
    final dur = duration;
    if (dur == null) return false;
    if (dur == SnoozeDuration.untilManuallyResumed) return true;
    final e = endsAt;
    if (e == null) return false;
    return now.isBefore(e);
  }

  /// Convert to a JSON-serialisable map for [SnoozeStore].
  Map<String, dynamic> toJson() => {
        if (endsAt != null) 'endsAtMs': endsAt!.millisecondsSinceEpoch,
        if (duration != null) 'duration': duration!.wireKey,
      };

  /// Forward-compatible deserialization. Unknown duration wireKeys are
  /// dropped (state collapses to [inactive]) so a downgraded build won't
  /// crash on a future variant.
  static SnoozeState fromJson(Map<String, dynamic> json) {
    final wire = json['duration'] as String?;
    final dur = snoozeDurationFromWire(wire);
    if (dur == null) return SnoozeState.inactive;
    final ms = (json['endsAtMs'] as num?)?.toInt();
    return SnoozeState(
      endsAt: ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null,
      duration: dur,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SnoozeState &&
          other.endsAt == endsAt &&
          other.duration == duration);

  @override
  int get hashCode => Object.hash(endsAt, duration);

  @override
  String toString() => 'SnoozeState(endsAt: $endsAt, duration: $duration)';
}
