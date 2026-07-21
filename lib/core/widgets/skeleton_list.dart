import 'package:flutter/material.dart';
import 'shimmer.dart';

/// Generic skeleton list wrapper
/// Wraps N skeleton items in a single Shimmer animation for performance
class SkeletonList extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsetsGeometry? padding;
  final double spacing;

  const SkeletonList({
    super.key,
    this.itemCount = 6,
    required this.itemBuilder,
    this.padding,
    this.spacing = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding ?? const EdgeInsets.symmetric(vertical: 8),
        itemCount: itemCount,
        separatorBuilder: (_, __) => SizedBox(height: spacing),
        itemBuilder: itemBuilder,
      ),
    );
  }
}

/// Generic skeleton grid wrapper
/// Wraps N skeleton cards in a single Shimmer animation for performance
class SkeletonGrid extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final SliverGridDelegate gridDelegate;
  final EdgeInsetsGeometry? padding;

  const SkeletonGrid({
    super.key,
    this.itemCount = 6,
    required this.itemBuilder,
    required this.gridDelegate,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding ?? const EdgeInsets.all(16),
        gridDelegate: gridDelegate,
        itemCount: itemCount,
        itemBuilder: itemBuilder,
      ),
    );
  }
}
