import 'package:flutter/material.dart';
import '../../../../core/widgets/shimmer.dart';

/// Skeleton that mirrors PlaylistVideoItem layout
/// Layout: [Checkbox] gap [Thumbnail 160x90] gap [Title + Channel + Views]
class PlaylistVideoSkeleton extends StatelessWidget {
  const PlaylistVideoSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Checkbox placeholder
          const SkeletonBox(width: 24, height: 24, radius: 4),
          const SizedBox(width: 12),
          // Thumbnail
          const SkeletonBox(width: 160, height: 90),
          const SizedBox(width: 16),
          // Text info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title line 1
                SkeletonLine(height: 14, width: double.infinity),
                const SizedBox(height: 6),
                // Title line 2
                SkeletonLine(height: 14, width: 150),
                const SizedBox(height: 10),
                // Channel
                SkeletonLine(height: 11, width: 110),
                const SizedBox(height: 6),
                // Views
                SkeletonLine(height: 11, width: 80),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
