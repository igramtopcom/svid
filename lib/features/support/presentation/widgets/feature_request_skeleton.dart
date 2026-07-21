import 'package:flutter/material.dart';
import '../../../../core/widgets/shimmer.dart';

/// Skeleton that mirrors feature request Card layout
/// Layout: Card > [Vote area (icon + count)] gap [Title+Status + Description]
class FeatureRequestSkeleton extends StatelessWidget {
  const FeatureRequestSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Vote area
            Column(
              children: [
                const SkeletonCircle(size: 36),
                const SizedBox(height: 4),
                SkeletonLine(height: 16, width: 24),
              ],
            ),
            const SizedBox(width: 16),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + status chip row
                  Row(
                    children: [
                      Expanded(child: SkeletonLine(height: 14)),
                      const SizedBox(width: 8),
                      const SkeletonBadge(width: 65),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Description lines
                  SkeletonLine(height: 11, width: double.infinity),
                  const SizedBox(height: 4),
                  SkeletonLine(height: 11, width: double.infinity),
                  const SizedBox(height: 4),
                  SkeletonLine(height: 11, width: 200),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
