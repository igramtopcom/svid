import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../downloads/domain/entities/download_entity.dart';
import '../../../downloads/domain/entities/download_status.dart';
import '../../../downloads/presentation/providers/downloads_notifier.dart';

/// Filters active downloads for browser overlay display.
/// Includes downloading, pending, queued, postProcessing statuses.
final browserActiveDownloadsProvider = Provider<List<DownloadEntity>>((ref) {
  final state = ref.watch(downloadsNotifierProvider);
  return state.downloads
      .where((d) =>
          d.status == DownloadStatus.downloading ||
          d.status == DownloadStatus.pending ||
          d.status == DownloadStatus.queued ||
          d.status == DownloadStatus.postProcessing)
      .toList();
});

/// Total download speed across all active downloads (bytes/sec).
final browserTotalSpeedProvider = Provider<int>((ref) {
  final active = ref.watch(browserActiveDownloadsProvider);
  return active.fold<int>(0, (sum, d) => sum + d.speed);
});

/// Count of active downloads.
final browserActiveCountProvider = Provider<int>((ref) {
  return ref.watch(browserActiveDownloadsProvider).length;
});
