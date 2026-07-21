import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// Applies the libmpv `hwdec` hint to a [Player] instance — enabling
/// platform-native hardware video decode (VideoToolbox on macOS,
/// D3D11VA on Windows, VAAPI on Linux) when the user has opted in
/// via Settings → Player → Hardware Decoding.
///
/// Spike status: this exists to ship the wiring + telemetry hook so
/// users can opt in and report results. It is **default OFF** —
/// libmpv's `hwdec=auto-safe` is widely safe but a "broad default-on"
/// without a runtime smoke across CPU generations is the kind of
/// change that has historically caused green-screen / no-video on
/// older Intel Macs and certain WMR Windows configurations. We
/// expand to default-on only after telemetry from opt-in users
/// shows the hint stable across the fleet.
///
/// References:
/// * mpv docs — https://mpv.io/manual/master/#options-hwdec
/// * media_kit setProperty — public API on the native backend
///   (`player.platform.setProperty(name, value)`).
class PlayerHardwareDecodeService {
  PlayerHardwareDecodeService._();

  /// Apply the hint to [player]. No-op on:
  /// - web (no native libmpv)
  /// - already-disposed players
  /// - any throw from setProperty (we never want a misconfigured
  ///   user setting to crash playback startup; if the property is
  ///   rejected the user just keeps software decode and a debug log
  ///   shows up).
  ///
  /// [enabled] true → `hwdec=auto-safe` (mpv's recommended best-effort
  /// mode that falls back to software decode when a codec is not
  /// hardware-accelerable). false → `hwdec=no` so the toggle works
  /// both ways without leaking previous state when the user disables
  /// after enabling.
  static Future<void> apply(Player player, {required bool enabled}) async {
    final platform = player.platform;
    if (platform == null) {
      debugPrint(
        '[PlayerHwDecode] platform null (web / disposed) — skipping hint',
      );
      return;
    }
    final value = enabled ? 'auto-safe' : 'no';
    try {
      // ignore: invalid_use_of_visible_for_testing_member, avoid_dynamic_calls
      // The native backend exposes setProperty publicly; the dynamic
      // dispatch here is intentional because [PlatformPlayer] is the
      // shared base and the public method only lives on the native
      // implementation. Wrapping in try/catch makes the dynamic call
      // safe regardless.
      await (platform as dynamic).setProperty('hwdec', value);
      debugPrint(
        '[PlayerHwDecode] hwdec=$value applied (enabled=$enabled)',
      );
    } catch (e, st) {
      debugPrint(
        '[PlayerHwDecode] setProperty failed — falling back to software '
        'decode. Error: $e\n$st',
      );
    }
  }
}
