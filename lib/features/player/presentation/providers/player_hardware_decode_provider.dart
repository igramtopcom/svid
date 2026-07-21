import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../settings/presentation/providers/settings_provider.dart'
    show sharedPreferencesProvider;

/// SharedPreferences key for the hardware-decode opt-in toggle.
/// Kept narrow + stable so the value survives app upgrades; if the
/// flag is ever promoted to default-on we keep the same key with a
/// migration that flips false → true rather than introducing a
/// second key.
const String _hwDecodePrefsKey = 'player.enableHardwareDecode';

/// Whether the user has opted in to libmpv hardware video decode.
///
/// Default: `false`. We do NOT default-on without a runtime smoke
/// across older Intel Macs / WMR Windows configurations — see
/// [PlayerHardwareDecodeService] for the rationale. Spike phase: a
/// debug toggle (or future Settings UI item) flips this and the
/// next [Player] init applies `hwdec=auto-safe`. Existing players
/// pick up the change on next reopen, not mid-stream, because mpv's
/// hwdec swap mid-playback is a known source of green frames.
final hardwareDecodeEnabledProvider =
    StateNotifierProvider<HardwareDecodeNotifier, bool>(
  (ref) => HardwareDecodeNotifier(ref.watch(sharedPreferencesProvider)),
);

class HardwareDecodeNotifier extends StateNotifier<bool> {
  final SharedPreferences _prefs;

  HardwareDecodeNotifier(this._prefs)
      : super(_prefs.getBool(_hwDecodePrefsKey) ?? false);

  Future<void> set(bool value) async {
    await _prefs.setBool(_hwDecodePrefsKey, value);
    state = value;
  }
}
