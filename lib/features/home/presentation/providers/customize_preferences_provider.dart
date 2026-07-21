/// V2 — Tier 2 customization toggle (popover deep customize).
///
/// Per UI Spec §5.6 the user can opt into "Tuỳ chỉnh chuyên sâu trước khi
/// tải" inside the preset popover footer. When ON, every download click
/// opens [DownloadConfigDialog] (Rule 3'). When OFF, default Rule 3
/// silent auto-download applies. The toggle is sticky across launches —
/// stored in SharedPreferences key `popover_deep_customize`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../settings/presentation/providers/settings_provider.dart';

/// SharedPreferences key — keep in sync with [popoverDeepCustomizeKey] for
/// any external migration tooling.
const String popoverDeepCustomizeKey = 'popover_deep_customize';

/// Notifier exposing the Tier 2 toggle. Keeps the SharedPrefs write
/// synchronous-ish: state flips immediately, persistence is awaited but
/// non-blocking for the UI.
class CustomizePreferencesNotifier extends StateNotifier<bool> {
  CustomizePreferencesNotifier(this._prefs)
      : super(_prefs.getBool(popoverDeepCustomizeKey) ?? false);

  final SharedPreferences _prefs;

  /// Set the toggle ON or OFF and persist immediately.
  Future<void> setDeepCustomize(bool value) async {
    if (state == value) return;
    state = value;
    await _prefs.setBool(popoverDeepCustomizeKey, value);
  }

  Future<void> toggle() => setDeepCustomize(!state);
}

/// `true` when Tier 2 popover-deep-customize is enabled.
final popoverDeepCustomizeProvider =
    StateNotifierProvider<CustomizePreferencesNotifier, bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return CustomizePreferencesNotifier(prefs);
});
