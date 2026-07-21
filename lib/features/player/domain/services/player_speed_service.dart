/// Pure-Dart service for playback speed presets and formatting.
/// All methods are static so they can be unit-tested without Flutter bindings.
class PlayerSpeedService {
  const PlayerSpeedService._();

  /// Standard speed presets shown in the speed-picker sheet.
  static const List<double> presets = [0.5, 1.0, 1.25, 1.5, 2.0];

  static const double minSpeed = 0.25;
  static const double maxSpeed = 4.0;

  /// Returns a human-readable label, e.g. `1.0 → '1x'`, `1.25 → '1.25x'`.
  static String formatLabel(double speed) {
    final rounded = double.parse(speed.toStringAsFixed(2));
    if (rounded == rounded.truncateToDouble()) {
      return '${rounded.truncate()}x';
    }
    // Remove trailing zeros after decimal (e.g. "1.250" → "1.25")
    return '${rounded.toString().replaceAll(RegExp(r'0+$'), '')}x';
  }

  /// Clamp [speed] to [minSpeed]..[maxSpeed].
  static double clamp(double speed) => speed.clamp(minSpeed, maxSpeed);

  /// Increase speed by 0.25, clamped to max.
  static double increase(double speed) => clamp(speed + 0.25);

  /// Decrease speed by 0.25, clamped to min.
  static double decrease(double speed) => clamp(speed - 0.25);
}
