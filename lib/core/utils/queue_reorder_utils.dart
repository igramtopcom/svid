import '../../features/downloads/domain/entities/download_entity.dart';
import '../../features/downloads/domain/entities/download_status.dart';

/// Threshold below which the network is considered "slow" (2 MB/s).
const _kSlowBandwidthThreshold = 2 * 1024 * 1024; // 2 MB/s in bytes

/// Reorders [pending] downloads so smaller files dispatch first when bandwidth
/// is below [_kSlowBandwidthThreshold].
///
/// Rules:
/// - Only reorders when [bandwidthBps] < 2 MB/s.
/// - Higher-priority downloads always precede lower-priority ones (priority groups
///   are never mixed). Within a priority group, smallest [totalBytes] comes first.
/// - Downloads with unknown size ([totalBytes] == 0) sort to the end of their group.
/// - Already-active or completed downloads are not reordered (only pending/queued).
/// - Preserves original order when bandwidth is sufficient (fast path returns identity).
List<DownloadEntity> reorderForBandwidth(
  List<DownloadEntity> pending,
  int bandwidthBps,
) {
  if (pending.isEmpty || bandwidthBps >= _kSlowBandwidthThreshold) return pending;

  final sorted = List<DownloadEntity>.from(pending);
  sorted.sort((a, b) {
    // Higher priority first (high=1 > normal=0 > low=-1)
    final priorityCmp = b.priority.compareTo(a.priority);
    if (priorityCmp != 0) return priorityCmp;

    // Within same priority: smallest file first (unknown size → end)
    final sizeA = a.totalBytes;
    final sizeB = b.totalBytes;
    if (sizeA == 0 && sizeB == 0) return 0;
    if (sizeA == 0) return 1;
    if (sizeB == 0) return -1;
    return sizeA.compareTo(sizeB);
  });
  return sorted;
}

/// Returns true if [downloads] contains any pending/queued item.
bool hasPendingDownloads(List<DownloadEntity> downloads) =>
    downloads.any((d) => d.status == DownloadStatus.pending || d.status == DownloadStatus.queued);
