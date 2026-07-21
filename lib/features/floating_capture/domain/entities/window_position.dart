/// User-saved screen position of the floating capture popup.
///
/// Captures only the top-left coordinate — the popup size is fixed by
/// spec (300×420 collapsed) and changes are tracked in a separate
/// expansion-state field if/when expanded mode ships.
///
/// Persisted via [WindowPositionStore] when the user drags the popup
/// (per [WindowListener.onWindowMoved] in `floating_window_main.dart`).
/// Restored on the next spawn so the popup respects the user's
/// arrangement.
///
/// First-run / never-dragged state is `null` — the spawn site falls
/// back to the spec Q19 "follow mouse cursor" default.
class WindowPosition {
  final double x;
  final double y;

  const WindowPosition({required this.x, required this.y});

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  /// Forward-compatible: missing or wrong-typed coordinates fall back
  /// to a "no saved position" signal (returns null) so a downgraded
  /// build doesn't crash on a future shape.
  static WindowPosition? fromJson(Map<String, dynamic> json) {
    final x = json['x'];
    final y = json['y'];
    if (x is! num || y is! num) return null;
    return WindowPosition(x: x.toDouble(), y: y.toDouble());
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WindowPosition && other.x == x && other.y == y);

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'WindowPosition(x: $x, y: $y)';
}
