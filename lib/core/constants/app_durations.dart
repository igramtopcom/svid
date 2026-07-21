/// Application duration constants
/// Centralized durations for animations, delays, and timeouts
class AppDurations {
  AppDurations._(); // Private constructor to prevent instantiation

  // ==================== ANIMATIONS ====================

  /// Duration for card hover animations
  static const cardHoverAnimation = Duration(milliseconds: 200);

  /// Duration for drawer slide animations
  static const drawerAnimation = Duration(milliseconds: 250);

  /// Duration for navigation bar animations
  static const navigationAnimation = Duration(milliseconds: 300);

  // ==================== DELAYS ====================

  /// Delay before auto-pasting URL from clipboard
  static const autoPasteTimeout = Duration(milliseconds: 1000);

  /// Debounce delay for window state saving
  static const windowStateSaveDelay = Duration(milliseconds: 500);

  // ==================== TOOLTIPS ====================

  /// Wait duration before showing tooltip
  static const tooltipWaitDuration = Duration(milliseconds: 500);

  // ==================== BATCH OPERATIONS ====================

  /// Delay between batch download operations to avoid race conditions
  static const batchDownloadDelay = Duration(milliseconds: 100);

  // ==================== NOTIFICATIONS ====================

  /// Duration for snackbar messages
  static const snackbarDuration = Duration(seconds: 2);
}
