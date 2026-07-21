import 'package:flutter/material.dart';
import '../../../../core/widgets/shimmer.dart';

/// Skeleton that mirrors ticket Card + ListTile layout
/// Layout: Card > [StatusIcon 28px] [Title + Subtitle] [StatusChip]
class TicketSkeleton extends StatelessWidget {
  const TicketSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Status icon
            const SkeletonCircle(size: 28),
            const SizedBox(width: 16),
            // Title + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonLine(height: 14, width: double.infinity),
                  const SizedBox(height: 6),
                  SkeletonLine(height: 11, width: 160),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Status chip
            const SkeletonBadge(width: 70),
          ],
        ),
      ),
    );
  }
}
