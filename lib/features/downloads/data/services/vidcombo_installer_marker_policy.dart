/// Pure decision logic for handling the `vidcombo_installer_ran.txt`
/// marker file. Extracted out of [StartupService] so the corner cases
/// (AV-locked marker → 3-strike force-accept → mtime fingerprint skip)
/// are unit-testable on any platform, not just Windows.
///
/// The caller owns all I/O (reading the marker, SharedPreferences,
/// deleting the file, mutating credentials). This function only decides
/// what should happen given the observed facts.
library;

/// Threshold of consecutive delete failures after which we accept that
/// the marker file is permanently locked (Defender / third-party AV /
/// permissions) and proceed with state reset anyway. Exposed for test
/// reuse — the production call site passes [kDefaultForceAcceptThreshold].
const int kDefaultForceAcceptThreshold = 3;

/// Captured facts about the marker file at this moment.
class MarkerObservation {
  const MarkerObservation({
    required this.markerExists,
    required this.markerMtimeMs,
    required this.lastProcessedMtimeMs,
    required this.currentFailCount,
    required this.deleteSucceeded,
  });

  /// Whether the marker file was present on disk at the start of this
  /// processing cycle.
  final bool markerExists;

  /// Millisecond-resolution mtime of the marker file, or null if the stat
  /// call itself failed (rare on Windows but handled defensively).
  final int? markerMtimeMs;

  /// Mtime of the marker that was last processed, persisted in
  /// SharedPreferences under the processed-mtime key. Null on a fresh
  /// install that never processed a marker before.
  final int? lastProcessedMtimeMs;

  /// Number of consecutive prior launches where we attempted to delete
  /// this marker and failed.
  final int currentFailCount;

  /// Whether the deletion attempt made during THIS processing cycle
  /// succeeded. Irrelevant if the caller short-circuited because the
  /// marker was already processed — in that case the caller should pass
  /// `false` and also pass [markerExists]=false (or rely on [skip] below).
  final bool deleteSucceeded;
}

/// What the caller should do next given a [MarkerObservation].
class MarkerDecision {
  const MarkerDecision({
    required this.skip,
    required this.resetState,
    required this.persistProcessedMtime,
    required this.nextFailCount,
    required this.clearFailCount,
  });

  /// If true, the caller should do NOTHING — no I/O, no prefs writes, no
  /// credential changes. Used when the marker is absent or already
  /// processed.
  final bool skip;

  /// The caller should wipe `vidcombo_legacy_import_done_v1`,
  /// `vidcombo_legacy_import_version`, and the stored `premium_license_key`
  /// so the legacy importer re-scans and the migrated key (from
  /// `vidcombo_migrated_key.txt`) can take effect on this launch.
  final bool resetState;

  /// If non-null, the caller should write this value to the processed-mtime
  /// SharedPreferences key. A null value means "do not change the existing
  /// stored mtime" — typically when we're backing off but the marker still
  /// hasn't been accepted yet.
  final int? persistProcessedMtime;

  /// If non-null, the caller should set the fail-count SharedPreferences
  /// key to this value. Takes precedence over [clearFailCount] when both
  /// are non-null (defensive — they should never conflict).
  final int? nextFailCount;

  /// If true, the caller should remove the fail-count SharedPreferences
  /// key. Used after a successful delete where the counter is no longer
  /// meaningful.
  final bool clearFailCount;
}

/// Decide what to do about the installer marker given current state.
///
/// The decision tree:
///
/// 1. Marker absent → `skip` (nothing to do).
/// 2. Marker present + mtime matches stored processed-mtime → `skip`.
///    This is the idempotency guard; it prevents the infinite reset loop
///    where a permanently-locked marker was force-accepted once but still
///    lives on disk. Without this, each subsequent launch would keep
///    wiping the user's premium license key.
/// 3. Marker present + not previously processed + delete succeeded →
///    `resetState` with mtime fingerprint + clear fail counter.
/// 4. Marker present + not previously processed + delete failed for the
///    N-th time where N < threshold → bump fail counter, skip state
///    reset (retry next launch).
/// 5. Marker present + not previously processed + delete failed for the
///    N-th time where N >= threshold → force-accept: `resetState` with
///    mtime fingerprint, keep fail counter as-is so the WARN stays
///    diagnosable in the log.
MarkerDecision decideInstallerMarkerAction(
  MarkerObservation obs, {
  int forceAcceptThreshold = kDefaultForceAcceptThreshold,
}) {
  if (!obs.markerExists) {
    return const MarkerDecision(
      skip: true,
      resetState: false,
      persistProcessedMtime: null,
      nextFailCount: null,
      clearFailCount: false,
    );
  }

  final alreadyProcessed = obs.markerMtimeMs != null &&
      obs.lastProcessedMtimeMs == obs.markerMtimeMs;
  if (alreadyProcessed) {
    return const MarkerDecision(
      skip: true,
      resetState: false,
      persistProcessedMtime: null,
      nextFailCount: null,
      clearFailCount: false,
    );
  }

  if (obs.deleteSucceeded) {
    return MarkerDecision(
      skip: false,
      resetState: true,
      persistProcessedMtime: obs.markerMtimeMs,
      nextFailCount: null,
      clearFailCount: true,
    );
  }

  final nextCount = obs.currentFailCount + 1;
  if (nextCount >= forceAcceptThreshold) {
    return MarkerDecision(
      skip: false,
      resetState: true,
      persistProcessedMtime: obs.markerMtimeMs,
      nextFailCount: nextCount,
      clearFailCount: false,
    );
  }

  return MarkerDecision(
    skip: false,
    resetState: false,
    persistProcessedMtime: null,
    nextFailCount: nextCount,
    clearFailCount: false,
  );
}
