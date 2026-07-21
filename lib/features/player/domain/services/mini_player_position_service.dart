import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the PiP (picture-in-picture) mini-player position across sessions.
///
/// Position is stored as bottom-right offset (matches [Positioned.right] /
/// [Positioned.bottom]). On restore, the position is clamped to the current
/// window size so PiP is always reachable after a window resize.
class MiniPlayerPositionService {
  static const String _xKey = 'mini_player_position_x';
  static const String _yKey = 'mini_player_position_y';
  static const String _widthKey = 'mini_player_size_w';
  static const String _heightKey = 'mini_player_size_h';

  final SharedPreferences _prefs;

  MiniPlayerPositionService(this._prefs);

  /// Persist [position] (right, bottom offsets) to SharedPreferences.
  Future<void> savePosition(Offset position) async {
    await _prefs.setDouble(_xKey, position.dx);
    await _prefs.setDouble(_yKey, position.dy);
  }

  /// Return the saved position, or `null` if none is stored.
  Offset? loadPosition() {
    final dx = _prefs.getDouble(_xKey);
    final dy = _prefs.getDouble(_yKey);
    if (dx == null || dy == null) return null;
    return Offset(dx, dy);
  }

  /// Persist [width] × [height] to SharedPreferences.
  Future<void> saveSize(double width, double height) async {
    await _prefs.setDouble(_widthKey, width);
    await _prefs.setDouble(_heightKey, height);
  }

  /// Return the saved size, or `null` if none is stored.
  Size? loadSize() {
    final w = _prefs.getDouble(_widthKey);
    final h = _prefs.getDouble(_heightKey);
    if (w == null || h == null) return null;
    return Size(w, h);
  }

  /// Clamp [position] so the mini-player (of [width] × [height]) stays fully
  /// visible within [windowSize] with a minimum [margin] on every edge.
  ///
  /// Because the position is a bottom-right offset, the valid range is:
  ///   dx ∈ [margin, windowSize.width  − width  − margin]
  ///   dy ∈ [margin, windowSize.height − height − margin]
  Offset clampPosition(
    Offset position,
    Size windowSize, {
    double width = 400,
    double height = 240,
    double margin = 20,
  }) {
    final maxDx = (windowSize.width - width - margin).clamp(margin, double.infinity);
    final maxDy = (windowSize.height - height - margin).clamp(margin, double.infinity);
    return Offset(
      position.dx.clamp(margin, maxDx),
      position.dy.clamp(margin, maxDy),
    );
  }
}
