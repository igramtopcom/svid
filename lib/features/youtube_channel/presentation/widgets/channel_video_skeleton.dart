import 'package:flutter/material.dart';
import '../../../../core/widgets/shimmer.dart';

/// Skeleton matching Nocturne Cinematic ChannelVideoItem layout
/// Layout: [Thumbnail 160x90] gap [Title + Metadata] gap [Checkbox]
class ChannelVideoSkeleton extends StatelessWidget {
  const ChannelVideoSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Thumbnail
          const SkeletonBox(width: 160, height: 90, radius: 2),
          const SizedBox(width: 16),
          // Text info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SkeletonLine(height: 14, width: double.infinity),
                const SizedBox(height: 6),
                SkeletonLine(height: 14, width: 180),
                const SizedBox(height: 10),
                SkeletonLine(height: 10, width: 140),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Checkbox placeholder
          const SkeletonBox(width: 20, height: 20, radius: 2),
        ],
      ),
    );
  }
}
