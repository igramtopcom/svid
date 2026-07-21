import '../entities/download_entity.dart';
import '../entities/download_priority.dart';
import '../entities/download_status.dart';

/// Suggests download priority based on user's historical download patterns.
///
/// Heuristic: platforms the user downloads from frequently get higher priority.
class SmartQueueService {
  /// Suggests a priority for a new download based on how often
  /// the user has downloaded from the same platform.
  ///
  /// - Platform downloaded ≥5 times → [DownloadPriority.high]
  /// - Platform downloaded ≥2 times → [DownloadPriority.normal]
  /// - Otherwise → [DownloadPriority.low]
  DownloadPriority suggestPriority(
    String platform,
    String mediaType,
    Map<String, int> platformHistory,
  ) {
    final count = platformHistory[platform] ?? 0;
    if (count >= 5) return DownloadPriority.high;
    if (count >= 2) return DownloadPriority.normal;
    return DownloadPriority.low;
  }

  /// Counts completed downloads per platform from download history.
  Map<String, int> computePlatformFrequency(List<DownloadEntity> downloads) {
    final frequency = <String, int>{};
    for (final d in downloads) {
      if (d.status == DownloadStatus.completed && d.platform.isNotEmpty) {
        frequency[d.platform] = (frequency[d.platform] ?? 0) + 1;
      }
    }
    return frequency;
  }

  /// Reorder [downloads] so that smaller files come first within each
  /// priority group (pending/queued only).
  ///
  /// Downloads with `totalBytes == 0` (unknown size) are placed after
  /// known-size downloads within the same group.
  List<DownloadEntity> reorderByFileSize(List<DownloadEntity> downloads) {
    final sorted = List<DownloadEntity>.from(downloads);
    sorted.sort((a, b) {
      final sizeA = a.totalBytes;
      final sizeB = b.totalBytes;
      // Unknown size → sort to end
      if (sizeA == 0 && sizeB == 0) return 0;
      if (sizeA == 0) return 1;
      if (sizeB == 0) return -1;
      return sizeA.compareTo(sizeB);
    });
    return sorted;
  }
}
