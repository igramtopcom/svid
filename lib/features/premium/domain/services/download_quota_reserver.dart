/// Defense-in-depth interface for reserving free-tier download quota.
///
/// Presentation code can still preflight quota for better UX, but download
/// use cases should also depend on this abstraction so new entry points cannot
/// accidentally bypass quota enforcement.
abstract interface class DownloadQuotaReserver {
  bool tryConsume({required bool isPremium, int count = 1});

  int currentPeriodCount();

  int remainingThisWeek({required bool isPremium});
}
