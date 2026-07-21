/// Navigation constants for top-bar tab navigation
///
/// Primary tabs: Downloads (0), Explore (1), Converter (3)
/// Utility screens: Settings (1000), Support (2000), Assistant (2001)
class NavigationConstants {
  NavigationConstants._();

  // Primary tabs (shown in top nav bar)
  static const int homeIndex = 0; // Downloads tab (default)
  static const int youtubeIndex = 1; // Explore tab (YouTube + subscriptions)
  static const int subscriptionsIndex = 2; // Legacy route alias into Explore
  static const int converterIndex = 3; // The Forge — converter + editor

  // Utility screens (shown from top-right icons)
  static const int settingsIndex = 1000;
  static const int supportIndex = 2000;
  static const int assistantIndex = 2001;
  static const int browserIndex = 3000;
  static const int premiumIndex = 1010;
  static const int sortingRulesIndex = 1011;
  static const int collectionsIndex = 1012;
  static const int activityCenterIndex = 1013;

  /// Whether index is a primary tab (shown in top nav)
  static bool isPrimaryTab(int index) =>
      index == homeIndex || index == youtubeIndex || index == converterIndex;

  /// Whether index is a utility screen
  static bool isUtilityScreen(int index) =>
      index == settingsIndex ||
      index == supportIndex ||
      index == assistantIndex ||
      index == browserIndex ||
      index == premiumIndex ||
      index == sortingRulesIndex ||
      index == collectionsIndex ||
      index == activityCenterIndex;

  /// Whether index is a downloads filter tab (1-999)
  static bool isDownloadFilterTab(int index) =>
      index >= 1 &&
      index < 1000 &&
      index != youtubeIndex &&
      index != subscriptionsIndex &&
      index != converterIndex;
}
