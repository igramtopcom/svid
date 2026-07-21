/// Heuristic severity classifier for crash reports submitted to the Go
/// backend. Used by every error reporter (Sentry-on, Sentry-off) so the
/// `severity` column on `crash_reports` carries actual triage signal.
///
/// Audit 2026-04-27 found 100% of production crash groups labelled
/// "medium" because both reporters hard-coded that string. With every
/// crash treated equally severe, the dashboard's severity dimension was
/// useless for prioritisation. This classifier maps an exception's
/// `toString()` output (and optionally its stack trace) onto one of
/// four tiers:
///
/// - **critical**: data-integrity threats — SQLite corruption / lock,
///   filesystem write fail, OOM. The user can lose data.
/// - **high**: feature-blocking crashes the user notices — Player
///   disposed assertion, MissingPluginException, PlatformException,
///   "No host specified in URI" (legacy thumbnail path bug). App keeps
///   running but the affected feature is broken.
/// - **medium**: localised glitch / edge case. Default for things we
///   don't recognise.
/// - **low**: warnings only — RenderFlex overflow, deprecated API.
///
/// The match is substring-based against lower-cased messages so callers
/// can pass raw `Object.toString()` without normalisation.
library;

String classifyCrashSeverity(String errorMessage, String? stackTrace) {
  final lower = errorMessage.toLowerCase();
  final stack = (stackTrace ?? '').toLowerCase();

  // Critical: data integrity threats
  if (lower.contains('sqliteexception') ||
      lower.contains('database is locked') ||
      lower.contains('database disk image is malformed') ||
      lower.contains('out of memory') ||
      lower.contains('outofmemoryerror')) {
    return 'critical';
  }

  // High: feature-blocking crashes that the user notices
  if (lower.contains('has been disposed') ||
      lower.contains('missingpluginexception') ||
      lower.contains('platformexception') ||
      lower.contains('no host specified in uri') ||
      lower.contains('assertion failed') ||
      stack.contains('flutter_rust_bridge')) {
    return 'high';
  }

  // Low: warnings that don't kill flows
  if (lower.contains('renderflex overflowed') ||
      lower.contains('overflowed by') ||
      lower.contains('deprecated')) {
    return 'low';
  }

  // Default
  return 'medium';
}
