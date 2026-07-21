import 'dart:ui';

/// Pure geometry helpers for desktop window placement.
///
/// Keep this free of plugin calls so Windows multi-monitor and work-area
/// edge cases can be covered with normal unit tests.
class WindowGeometryService {
  WindowGeometryService._();

  static Rect visibleRect({
    required Size displaySize,
    Offset? visiblePosition,
    Size? visibleSize,
  }) {
    final origin = visiblePosition ?? Offset.zero;
    final size = visibleSize ?? displaySize;
    return origin & size;
  }

  static Rect chooseDisplayForWindow({
    required Rect windowBounds,
    required List<Rect> displayBounds,
    required Rect fallback,
  }) {
    if (displayBounds.isEmpty) return fallback;

    final center = windowBounds.center;
    for (final display in displayBounds) {
      if (display.contains(center)) return display;
    }

    Rect best = fallback;
    double bestArea = -1;
    for (final display in displayBounds) {
      final overlap = display.intersect(windowBounds);
      final area = overlap.isEmpty ? 0.0 : overlap.width * overlap.height;
      if (area > bestArea) {
        bestArea = area;
        best = display;
      }
    }
    return bestArea > 0 ? best : fallback;
  }

  static Offset bottomRightPosition({
    required Rect visibleBounds,
    required Size windowSize,
    double marginRight = 20,
    double marginBottom = 20,
  }) {
    final raw = Offset(
      visibleBounds.right - windowSize.width - marginRight,
      visibleBounds.bottom - windowSize.height - marginBottom,
    );
    return clampPosition(
      position: raw,
      windowSize: windowSize,
      visibleBounds: visibleBounds,
      margin: marginRight < marginBottom ? marginRight : marginBottom,
    );
  }

  static Offset avoidOverlaps({
    required Offset preferredPosition,
    required Size windowSize,
    required Rect visibleBounds,
    required List<Rect> avoidBounds,
    double gap = 12,
    double margin = 20,
  }) {
    final preferred = clampPosition(
      position: preferredPosition,
      windowSize: windowSize,
      visibleBounds: visibleBounds,
      margin: margin,
    );
    final preferredRect = preferred & windowSize;
    final relevantAvoids =
        avoidBounds.where((rect) => rect.overlaps(visibleBounds)).toList();
    if (relevantAvoids.isEmpty ||
        !_overlapsAny(preferredRect, relevantAvoids)) {
      return preferred;
    }

    relevantAvoids.sort((a, b) {
      final areaA = _overlapArea(preferredRect, a);
      final areaB = _overlapArea(preferredRect, b);
      return areaB.compareTo(areaA);
    });
    final primaryAvoid = relevantAvoids.first;

    final candidates = <Offset>[
      Offset(preferred.dx, primaryAvoid.top - windowSize.height - gap),
      Offset(primaryAvoid.left - windowSize.width - gap, preferred.dy),
      Offset(primaryAvoid.right + gap, preferred.dy),
      Offset(preferred.dx, primaryAvoid.bottom + gap),
      Offset(
        primaryAvoid.left - windowSize.width - gap,
        primaryAvoid.top - windowSize.height - gap,
      ),
    ];

    Offset best = preferred;
    var bestOverlap = _totalOverlapArea(preferredRect, relevantAvoids);
    for (final candidate in candidates) {
      final safe = clampPosition(
        position: candidate,
        windowSize: windowSize,
        visibleBounds: visibleBounds,
        margin: margin,
      );
      final safeRect = safe & windowSize;
      final overlap = _totalOverlapArea(safeRect, relevantAvoids);
      if (overlap == 0) return safe;
      if (overlap < bestOverlap) {
        best = safe;
        bestOverlap = overlap;
      }
    }

    return best;
  }

  static Offset clampPosition({
    required Offset position,
    required Size windowSize,
    required Rect visibleBounds,
    double margin = 20,
  }) {
    final minX = visibleBounds.left + margin;
    final minY = visibleBounds.top + margin;
    final maxX = visibleBounds.right - windowSize.width - margin;
    final maxY = visibleBounds.bottom - windowSize.height - margin;

    final safeX =
        maxX >= minX
            ? position.dx.clamp(minX, maxX).toDouble()
            : visibleBounds.left +
                ((visibleBounds.width - windowSize.width) / 2);
    final safeY =
        maxY >= minY
            ? position.dy.clamp(minY, maxY).toDouble()
            : visibleBounds.top +
                ((visibleBounds.height - windowSize.height) / 2);

    return Offset(safeX, safeY);
  }

  static bool _overlapsAny(Rect rect, List<Rect> others) {
    return others.any(rect.overlaps);
  }

  static double _totalOverlapArea(Rect rect, List<Rect> others) {
    return others.fold(0, (sum, other) => sum + _overlapArea(rect, other));
  }

  static double _overlapArea(Rect a, Rect b) {
    final overlap = a.intersect(b);
    return overlap.isEmpty ? 0 : overlap.width * overlap.height;
  }
}
