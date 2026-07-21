import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/notification_center_provider.dart';
import '../../../../core/services/notification_center_service.dart';
import '../../../downloads/domain/entities/download_entity.dart';
import '../../../downloads/domain/entities/download_status.dart';
import '../../../downloads/presentation/providers/downloads_notifier.dart';
import '../../domain/entities/activity_item.dart';
import 'activity_filter_provider.dart';

// ── KPI Stats ───────────────────────────────────────────────────────────────

/// Aggregate KPI statistics computed from all downloads.
class ActivityKpiStats {
  final int totalDownloads;
  final double successRate;
  final int totalBytesProcessed;
  final int activeCount;

  const ActivityKpiStats({
    this.totalDownloads = 0,
    this.successRate = 0,
    this.totalBytesProcessed = 0,
    this.activeCount = 0,
  });
}

/// Provides real-time KPI stats from the downloads list.
final activityKpiStatsProvider = Provider<ActivityKpiStats>((ref) {
  final downloads = ref.watch(
    downloadsNotifierProvider.select((s) => s.downloads),
  );

  if (downloads.isEmpty) return const ActivityKpiStats();

  final completed = downloads.where((d) => d.status == DownloadStatus.completed).length;
  final failed = downloads.where((d) => d.status == DownloadStatus.failed).length;
  final terminal = completed + failed;
  final rate = terminal > 0 ? (completed / terminal) * 100 : 0.0;

  final totalBytes = downloads
      .where((d) => d.status == DownloadStatus.completed)
      .fold<int>(0, (sum, d) => sum + d.totalBytes);

  final active = downloads.where((d) => d.status.isActive).length;

  return ActivityKpiStats(
    totalDownloads: downloads.length,
    successRate: rate,
    totalBytesProcessed: totalBytes,
    activeCount: active,
  );
});

// ── Merged Activity Stream ──────────────────────────────────────────────────

/// Merged + filtered list of all activity items (downloads + system notifications).
final filteredActivityItemsProvider = Provider<List<ActivityItem>>((ref) {
  final downloads = ref.watch(
    downloadsNotifierProvider.select((s) => s.downloads),
  );
  final sysNotifs = ref.watch(notificationsStreamProvider);
  final filter = ref.watch(activityFilterProvider);

  // Build merged list
  final items = <ActivityItem>[];

  // Add download items (apply tab + date + search filters)
  for (final d in downloads) {
    if (!_passesTabFilter(d, filter.selectedTab)) continue;
    if (!_passesDateFilter(d.updatedAt, filter.dateRange)) continue;
    if (!_passesSearchFilter(d, filter.searchQuery)) continue;
    items.add(ActivityItem.download(d));
  }

  // Add system notification items (only for "all" or "system" tab)
  if (filter.selectedTab == ActivityFilterTab.all ||
      filter.selectedTab == ActivityFilterTab.system) {
    final notifications = sysNotifs.valueOrNull ?? [];
    for (final n in notifications) {
      if (!_passesDateFilter(n.timestamp, filter.dateRange)) continue;
      if (filter.searchQuery.isNotEmpty) {
        final q = filter.searchQuery.toLowerCase();
        if (!n.title.toLowerCase().contains(q) &&
            !n.body.toLowerCase().contains(q)) {
          continue;
        }
      }
      // Skip download-type system notifications (they're already in downloads)
      if (n.type == AppNotificationType.downloadComplete ||
          n.type == AppNotificationType.downloadFailed) {
        continue;
      }
      items.add(ActivityItem.system(n));
    }
  }

  // Sort by timestamp descending (newest first)
  items.sort((a, b) => b.timestamp.compareTo(a.timestamp));

  return items;
});

bool _passesTabFilter(DownloadEntity d, ActivityFilterTab tab) {
  return switch (tab) {
    ActivityFilterTab.all => true,
    ActivityFilterTab.active => d.status.isActive ||
        d.status == DownloadStatus.paused ||
        d.status == DownloadStatus.waitingForNetwork,
    ActivityFilterTab.success => d.status == DownloadStatus.completed,
    ActivityFilterTab.errors => d.status == DownloadStatus.failed ||
        d.status == DownloadStatus.cancelled,
    ActivityFilterTab.system => false, // downloads never show in system tab
  };
}

bool _passesDateFilter(DateTime timestamp, ActivityDateRange range) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return switch (range) {
    ActivityDateRange.today => timestamp.isAfter(today),
    ActivityDateRange.last7Days =>
      timestamp.isAfter(now.subtract(const Duration(days: 7))),
    ActivityDateRange.last30Days =>
      timestamp.isAfter(now.subtract(const Duration(days: 30))),
    ActivityDateRange.allTime => true,
  };
}

bool _passesSearchFilter(DownloadEntity d, String query) {
  if (query.isEmpty) return true;
  final q = query.toLowerCase();
  return d.displayTitle.toLowerCase().contains(q) ||
      d.filename.toLowerCase().contains(q) ||
      (d.uploader?.toLowerCase().contains(q) ?? false) ||
      d.platform.toLowerCase().contains(q);
}

// ── Analytics Providers ─────────────────────────────────────────────────────

/// Activity heatmap: download counts grouped by day for last 28 days.
final activityHeatmapProvider = Provider<Map<DateTime, int>>((ref) {
  final downloads = ref.watch(
    downloadsNotifierProvider.select((s) => s.downloads),
  );

  final now = DateTime.now();
  final cutoff = now.subtract(const Duration(days: 28));
  final map = <DateTime, int>{};

  // Initialize all 28 days to 0
  for (int i = 0; i < 28; i++) {
    final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
    map[day] = 0;
  }

  // Count downloads per day
  for (final d in downloads) {
    if (d.createdAt.isBefore(cutoff)) continue;
    final day = DateTime(d.createdAt.year, d.createdAt.month, d.createdAt.day);
    map[day] = (map[day] ?? 0) + 1;
  }

  return map;
});

/// Format distribution: count of completed downloads by file extension category.
final formatDistributionProvider = Provider<Map<String, int>>((ref) {
  final downloads = ref.watch(
    downloadsNotifierProvider.select((s) => s.downloads),
  );

  final completed = downloads.where((d) => d.status == DownloadStatus.completed);
  final map = <String, int>{};

  for (final d in completed) {
    final ext = d.filename.split('.').last.toLowerCase();
    final category = _formatCategory(ext);
    map[category] = (map[category] ?? 0) + 1;
  }

  // Sort descending by count
  final sorted = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return Map.fromEntries(sorted);
});

String _formatCategory(String ext) {
  const videoExts = {'mp4', 'mkv', 'webm', 'avi', 'mov', 'flv', 'wmv', 'm4v'};
  const audioExts = {'mp3', 'flac', 'm4a', 'aac', 'ogg', 'opus', 'wav', 'wma'};
  const imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'};

  if (videoExts.contains(ext)) return ext.toUpperCase();
  if (audioExts.contains(ext)) return ext.toUpperCase();
  if (imageExts.contains(ext)) return 'Image';
  return 'Other';
}

/// Platform distribution: count of all downloads by source platform.
final platformDistributionProvider = Provider<Map<String, int>>((ref) {
  final downloads = ref.watch(
    downloadsNotifierProvider.select((s) => s.downloads),
  );

  final map = <String, int>{};
  for (final d in downloads) {
    final platform = d.platform.isNotEmpty && d.platform != 'unknown'
        ? d.platform
        : 'Other';
    map[platform] = (map[platform] ?? 0) + 1;
  }

  // Sort descending by count
  final sorted = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return Map.fromEntries(sorted);
});
