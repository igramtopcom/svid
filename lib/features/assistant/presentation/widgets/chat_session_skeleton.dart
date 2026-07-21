import 'package:flutter/material.dart';
import '../../../../core/widgets/shimmer.dart';

/// Skeleton that mirrors session card layout in HistoryPanel
class ChatSessionSkeleton extends StatelessWidget {
  const ChatSessionSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          const SkeletonCircle(size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(height: 12, width: double.infinity),
                const SizedBox(height: 6),
                SkeletonLine(height: 10, width: 80),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
