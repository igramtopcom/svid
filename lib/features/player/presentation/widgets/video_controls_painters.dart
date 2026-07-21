import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../downloads/domain/entities/video_info.dart';

/// YouTube-style segmented chapter progress bar.
/// Each chapter is a filled rectangle segment with gaps between them.
/// Active fill (primary color) up to current position, inactive fill (white 20%) for the rest.
class SegmentedChapterPainter extends CustomPainter {
  final List<ChapterInfo> chapters;
  final double totalDurationMs;
  final double currentPositionMs;
  final Color activeColor;

  static const double _gapWidth = 2.0;

  SegmentedChapterPainter({
    required this.chapters,
    required this.totalDurationMs,
    required this.currentPositionMs,
    required this.activeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (totalDurationMs <= 0 || chapters.isEmpty) return;

    final totalGapWidth = _gapWidth * (chapters.length - 1);
    final availableWidth = size.width - totalGapWidth;
    if (availableWidth <= 0) return;

    final inactivePaint = Paint()
      ..color = AppColors.darkMuted.withValues(alpha: AppOpacity.scrim);
    final activePaint = Paint()
      ..color = activeColor;
    final radius = Radius.circular(size.height / 2);

    double currentX = 0;

    for (int i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      final chapterStartMs = chapter.startTime * 1000;
      final chapterEndMs = chapter.endTime * 1000;
      final chapterDurationMs = chapterEndMs - chapterStartMs;
      final segmentWidth = (chapterDurationMs / totalDurationMs) * availableWidth;

      if (segmentWidth <= 0) continue;

      final segmentRect = RRect.fromLTRBR(
        currentX, 0, currentX + segmentWidth, size.height, radius,
      );

      // Draw inactive background
      canvas.drawRRect(segmentRect, inactivePaint);

      // Draw active fill based on current position
      if (currentPositionMs > chapterStartMs) {
        final progressInChapter = ((currentPositionMs - chapterStartMs) / chapterDurationMs).clamp(0.0, 1.0);
        final activeWidth = progressInChapter * segmentWidth;

        if (activeWidth > 0) {
          canvas.save();
          canvas.clipRRect(segmentRect);
          canvas.drawRect(
            Rect.fromLTWH(currentX, 0, activeWidth, size.height),
            activePaint,
          );
          canvas.restore();
        }
      }

      currentX += segmentWidth + _gapWidth;
    }
  }

  @override
  bool shouldRepaint(SegmentedChapterPainter oldDelegate) {
    return chapters != oldDelegate.chapters ||
        totalDurationMs != oldDelegate.totalDurationMs ||
        currentPositionMs != oldDelegate.currentPositionMs ||
        activeColor != oldDelegate.activeColor;
  }
}

/// Painter for A-B repeat range markers on the timeline.
class AbRepeatRangePainter extends CustomPainter {
  final Duration pointA;
  final Duration? pointB;
  final double totalDurationMs;
  final double trackHeight;

  AbRepeatRangePainter({
    required this.pointA,
    required this.pointB,
    required this.totalDurationMs,
    required this.trackHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (totalDurationMs <= 0) return;

    final markerPaint = Paint()
      ..color = AppColors.accentHighlight
      ..style = PaintingStyle.fill;

    final rangePaint = Paint()
      ..color = AppColors.accentHighlight.withValues(alpha: AppOpacity.quarter);

    // Point A marker (small triangle)
    final aPos = (pointA.inMilliseconds / totalDurationMs).clamp(0.0, 1.0) * size.width;
    _drawMarker(canvas, aPos, size.height, markerPaint);

    if (pointB != null) {
      // Point B marker
      final bPos = (pointB!.inMilliseconds / totalDurationMs).clamp(0.0, 1.0) * size.width;
      _drawMarker(canvas, bPos, size.height, markerPaint);

      // Fill region between A and B
      canvas.drawRect(
        Rect.fromLTRB(aPos, 0, bPos, size.height),
        rangePaint,
      );
    }
  }

  void _drawMarker(Canvas canvas, double x, double height, Paint paint) {
    // Diamond marker (rotated square) — Nocturne Cinematic style
    final centerY = height / 2;
    const size = 5.0;
    final path = Path()
      ..moveTo(x, centerY - size)
      ..lineTo(x + size, centerY)
      ..lineTo(x, centerY + size)
      ..lineTo(x - size, centerY)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(AbRepeatRangePainter oldDelegate) {
    return pointA != oldDelegate.pointA ||
        pointB != oldDelegate.pointB ||
        totalDurationMs != oldDelegate.totalDurationMs;
  }
}
