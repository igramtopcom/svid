import '../../../../core/utils/validators.dart';

/// Result of parsing batch URL input.
class BatchImportResult {
  final List<String> validUrls;
  final List<String> skippedLines;
  final int duplicateCount;

  const BatchImportResult({
    required this.validUrls,
    required this.skippedLines,
    required this.duplicateCount,
  });

  bool get hasValidUrls => validUrls.isNotEmpty;

  /// Total non-blank lines processed.
  /// Total non-blank lines processed (valid + invalid + duplicates).
  int get totalLines => validUrls.length + skippedLines.length + duplicateCount;
}

/// Pure Dart service for parsing and validating batch URL imports.
///
/// Splits multi-line text by newlines, trims each line, validates URLs,
/// deduplicates, and returns a [BatchImportResult].
class BatchImportService {
  const BatchImportService();

  /// Parse a multi-line text block into valid, deduplicated URLs.
  BatchImportResult parseUrls(String text) {
    if (text.trim().isEmpty) {
      return const BatchImportResult(
        validUrls: [],
        skippedLines: [],
        duplicateCount: 0,
      );
    }

    final lines = text.split('\n').map((line) => line.trim()).toList();
    final validUrls = <String>[];
    final skippedLines = <String>[];
    final seen = <String>{};
    int duplicateCount = 0;

    for (final line in lines) {
      // Skip blank lines entirely (not counted as skipped)
      if (line.isEmpty) continue;

      if (!Validators.isDownloadableUrl(line)) {
        skippedLines.add(line);
        continue;
      }

      // Deduplicate (case-sensitive, preserve first occurrence)
      if (seen.contains(line)) {
        duplicateCount++;
        continue;
      }

      seen.add(line);
      validUrls.add(line);
    }

    return BatchImportResult(
      validUrls: validUrls,
      skippedLines: skippedLines,
      duplicateCount: duplicateCount,
    );
  }
}
