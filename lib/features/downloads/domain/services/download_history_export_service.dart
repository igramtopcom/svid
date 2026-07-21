import '../entities/download_entity.dart';

/// Pure Dart service for exporting download history to RFC-4180 compliant CSV.
class DownloadHistoryExportService {
  const DownloadHistoryExportService();

  static const _columns = [
    'id',
    'filename',
    'url',
    'platform',
    'status',
    'savePath',
    'totalBytes',
    'downloadedBytes',
    'createdAt',
    'updatedAt',
    'errorMessage',
  ];

  /// Generate RFC-4180 compliant CSV from a list of downloads.
  String generateCsv(List<DownloadEntity> downloads) {
    final buffer = StringBuffer();

    // Header row
    buffer.writeln(_columns.join(','));

    // Data rows
    for (final d in downloads) {
      final row = [
        d.id.toString(),
        escapeCsv(d.filename),
        escapeCsv(d.url),
        escapeCsv(d.platform),
        escapeCsv(d.status.name),
        escapeCsv(d.savePath),
        d.totalBytes.toString(),
        d.downloadedBytes.toString(),
        d.createdAt.toIso8601String(),
        d.updatedAt.toIso8601String(),
        escapeCsv(d.errorMessage ?? ''),
      ];
      buffer.writeln(row.join(','));
    }

    return buffer.toString();
  }

  /// Escape a value for CSV (RFC-4180).
  /// Wraps in double-quotes if value contains comma, double-quote, or newline.
  /// Double-quotes within the value are escaped by doubling them.
  String escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n') || value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
