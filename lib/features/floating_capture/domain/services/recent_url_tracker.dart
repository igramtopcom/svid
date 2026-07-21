import 'dart:collection';

/// Tracks URLs that have been **successfully actioned** (Download click,
/// Open-in-app click, or explicit dismiss) so a subsequent clipboard event
/// for the same URL within [cooldown] is silently skipped.
///
/// Anti-spam Layer 1 of the Phase 2A defense (spec §2 Shift 2). Distinct
/// from the popup-side dedupe (Layer 2) which prevents queue accumulation.
///
/// Marking happens on **action**, not on popup show — a failed download
/// retry within the cooldown window is therefore allowed (the user clearly
/// wants to act on this URL again).
///
/// Bounded by [maxEntries] (default 10) with oldest-out eviction. Cooldown
/// default is 2 minutes (overridable via Settings per spec §10 Q3).
class RecentUrlTracker {
  final Duration cooldown;
  final int maxEntries;
  final DateTime Function() _now;

  /// LinkedHashMap preserves insertion order — oldest entry is `_recent.keys.first`.
  final LinkedHashMap<String, DateTime> _recent = LinkedHashMap();

  RecentUrlTracker({
    this.cooldown = const Duration(minutes: 2),
    this.maxEntries = 10,
    DateTime Function()? now,
  })  : assert(maxEntries > 0, 'maxEntries must be positive'),
        _now = now ?? DateTime.now;

  /// Whether [url] was actioned within the cooldown window.
  bool isRecentlyActioned(String url) {
    _evictExpired();
    final t = _recent[url];
    if (t == null) return false;
    return _now().difference(t) < cooldown;
  }

  /// Mark [url] as just-actioned. Caller invokes this after the user
  /// successfully clicked a terminal action (Download / OpenInApp / Dismiss).
  void markActioned(String url) {
    _evictExpired();
    // Re-insert at end so it's the most-recent (LinkedHashMap preserves order).
    _recent.remove(url);
    if (_recent.length >= maxEntries) {
      _recent.remove(_recent.keys.first);
    }
    _recent[url] = _now();
  }

  /// Reset all tracked entries — wired to Settings "Reset cooldowns" button.
  void clear() => _recent.clear();

  /// Number of currently-tracked entries (post-eviction). Test-only helper.
  int get size {
    _evictExpired();
    return _recent.length;
  }

  void _evictExpired() {
    final now = _now();
    _recent.removeWhere((_, t) => now.difference(t) >= cooldown);
  }
}
