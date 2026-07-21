/// Returns the user's remaining captures-per-day quota.
///
/// Per spec §6 + Q9:
/// - Premium users have unlimited captures → return -1 sentinel.
/// - Free users have a daily counter; once exhausted (returns 0) the popup
///   shows the upgrade UI variant but capture still works for the user to
///   read previews.
///
/// This service is a *policy*, not a storage layer — implementations may
/// consult any combination of premium-status, daily counter, A/B flag, etc.
/// The CaptureService just calls [remaining] before forwarding the quota
/// to the popup.
abstract class CaptureQuotaPolicy {
  /// Returns:
  /// - `-1` if the user is unlimited (premium).
  /// - `>= 0` if there's a daily cap; the value is captures left today.
  Future<int> remaining();

  /// Notify the policy that one capture happened (decrements the daily
  /// counter for free users; no-op for premium). Idempotent failure mode:
  /// if persistence fails, the counter just doesn't decrement — the user
  /// gets one extra capture, which is preferred over over-blocking.
  Future<void> recordCapture();
}

/// Default policy: unlimited captures. Used until the premium feature
/// integrates a real counter. Allows shipping the floating capture flow
/// without coupling to billing.
class UnlimitedCaptureQuotaPolicy implements CaptureQuotaPolicy {
  const UnlimitedCaptureQuotaPolicy();

  @override
  Future<int> remaining() async => -1;

  @override
  Future<void> recordCapture() async {}
}
