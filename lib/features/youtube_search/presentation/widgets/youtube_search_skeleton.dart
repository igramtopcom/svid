import 'package:flutter/material.dart';
import '../../../../core/widgets/shimmer.dart';

/// Skeleton loading for YouTube search results — uniform compact rows.
class YouTubeSearchSkeleton extends StatelessWidget {
  final bool featured;
  final int itemCount;
  final bool shrinkWrap;

  const YouTubeSearchSkeleton({
    super.key,
    this.featured = true,
    this.itemCount = 8,
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    if (shrinkWrap) {
      return Shimmer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            itemCount,
            (_) => const _ResultItemSkeleton(),
          ),
        ),
      );
    }

    return Shimmer(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: itemCount,
        itemBuilder: (context, index) {
          return const _ResultItemSkeleton();
        },
      ),
    );
  }
}

/// Standard result item skeleton — matches YouTubeSearchResultItem layout.
class _ResultItemSkeleton extends StatelessWidget {
  const _ResultItemSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                // Title line 2 (shorter)
                SkeletonLine(height: 14, width: 200),
                const SizedBox(height: 10),
                // Channel name
                SkeletonLine(height: 11, width: 130),
                const SizedBox(height: 6),
                // Views + date
                SkeletonLine(height: 11, width: 170),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
