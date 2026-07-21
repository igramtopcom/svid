import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Paints the trim range overlay on the video timeline.
///
/// Shows:
/// - Dimmed areas outside the selected range
/// - Orange highlight for the selected range
/// - Vertical handle lines at start/end positions
/// - Small circular handle indicators
class TrimRangePainter extends CustomPainter {
  /// Start position as fraction of total duration (0.0 to 1.0)
  final double startPosition;

  /// End position as fraction of total duration (0.0 to 1.0)
  final double endPosition;

  /// Height of the track area
  final double trackHeight;

  /// Color for the selected range
  final Color rangeColor;

  TrimRangePainter({
    required this.startPosition,
    required this.endPosition,
    required this.trackHeight,
    Color? rangeColor,
  }) : rangeColor = rangeColor ?? AppColors.accentHighlight;

  @override
  void paint(Canvas canvas, Size size) {
    if (startPosition >= endPosition) return;

    final startX = startPosition * size.width;
    final endX = endPosition * size.width;
    final centerY = size.height / 2;
    final trackTop = centerY - trackHeight / 2;
    final trackBottom = centerY + trackHeight / 2;

    // 1. Dim areas outside selection
    final dimPaint = Paint()..color = Colors.black.withValues(alpha: AppOpacity.medium);

    // Left dim
    if (startX > 0) {
      canvas.drawRect(
        Rect.fromLTRB(0, trackTop, startX, trackBottom),
        dimPaint,
      );
    }

    // Right dim
    if (endX < size.width) {
      canvas.drawRect(
        Rect.fromLTRB(endX, trackTop, size.width, trackBottom),
        dimPaint,
      );
    }

    // 2. Orange highlight for selected range
    final rangePaint = Paint()..color = rangeColor.withValues(alpha: AppOpacity.scrim);
    canvas.drawRect(
      Rect.fromLTRB(startX, trackTop, endX, trackBottom),
      rangePaint,
    );

    // 3. Handle lines at boundaries
    final handlePaint = Paint()
      ..color = rangeColor
      ..strokeWidth = 2.0;

    // Start handle line (extends above and below track)
    canvas.drawLine(
      Offset(startX, trackTop - 4),
      Offset(startX, trackBottom + 4),
      handlePaint,
    );

    // End handle line
    canvas.drawLine(
      Offset(endX, trackTop - 4),
      Offset(endX, trackBottom + 4),
      handlePaint,
    );

    // 4. Diamond handle indicators at top — Nocturne angular style
    final handleDiamondPaint = Paint()..color = rangeColor;
    _drawDiamond(canvas, Offset(startX, trackTop - 4), 4, handleDiamondPaint);
    _drawDiamond(canvas, Offset(endX, trackTop - 4), 4, handleDiamondPaint);
  }

  void _drawDiamond(Canvas canvas, Offset center, double size, Paint paint) {
    final path = Path()
      ..moveTo(center.dx, center.dy - size)
      ..lineTo(center.dx + size, center.dy)
      ..lineTo(center.dx, center.dy + size)
      ..lineTo(center.dx - size, center.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(TrimRangePainter oldDelegate) {
    return startPosition != oldDelegate.startPosition ||
        endPosition != oldDelegate.endPosition ||
        trackHeight != oldDelegate.trackHeight ||
        rangeColor != oldDelegate.rangeColor;
  }
}
