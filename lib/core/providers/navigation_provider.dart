import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Navigation state notifier
/// Manages which tab is currently selected in AppScaffold
/// Uses constant indices: 0=Home, 1-999=Filter tabs, 1000=Settings
class NavigationNotifier extends StateNotifier<int> {
  NavigationNotifier() : super(0);

  /// Navigate to Home tab (constant index 0)
  void navigateToHome() => state = 0;

  /// Navigate to specific tab by index
  /// Accepts any valid index (no upper limit validation)
  void navigateToTab(int index) {
    if (index >= 0) {
      state = index;
    }
  }
}

/// Navigation provider
/// Provides access to current tab index and navigation actions
final navigationProvider = StateNotifierProvider<NavigationNotifier, int>((ref) {
  return NavigationNotifier();
});
