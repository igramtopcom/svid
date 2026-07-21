import 'dart:io';
import 'package:path/path.dart' as p;
import '../entities/download_entity.dart';
import '../entities/sorting_rule.dart';
import '../../../../core/logging/app_logger.dart';

/// Pure Dart service for evaluating and applying sorting rules.
///
/// No external dependencies — easily unit-testable.
class SortingRuleService {
  /// Return the first enabled rule that matches [download], or null.
  SortingRule? findMatchingRule(
    DownloadEntity download,
    List<SortingRule> rules,
  ) {
    final sorted = List<SortingRule>.from(rules)
      ..sort((a, b) => a.order.compareTo(b.order));

    for (final rule in sorted) {
      if (!rule.isEnabled) continue;
      if (matchesRule(download, rule)) return rule;
    }
    return null;
  }

  /// Returns true if [download] satisfies all non-empty conditions in [rule].
  bool matchesRule(DownloadEntity download, SortingRule rule) {
    final cond = rule.condition;

    if (cond.platform.isNotEmpty &&
        download.platform.toLowerCase() != cond.platform.toLowerCase()) {
      return false;
    }

    if (cond.fileExtension.isNotEmpty) {
      final ext = p.extension(download.filename).replaceFirst('.', '').toLowerCase();
      if (ext != cond.fileExtension.toLowerCase()) return false;
    }

    if (cond.urlContains.isNotEmpty &&
        !download.url.toLowerCase().contains(cond.urlContains.toLowerCase())) {
      return false;
    }

    return true;
  }

  /// Substitute template variables and return the final filename.
  ///
  /// Variables: {title}, {uploader}, {date}, {download_date}, {platform},
  ///            {quality}, {ext}
  ///
  /// If [renameTemplate] is empty, returns the original filename unchanged.
  String applyRename(String renameTemplate, DownloadEntity download) {
    if (renameTemplate.trim().isEmpty) return download.filename;

    final ext = p.extension(download.filename); // includes leading "."
    final extNoDot = ext.replaceFirst('.', '');

    String result = renameTemplate
        .replaceAll('{title}', _sanitize(download.title ?? download.filename))
        .replaceAll('{uploader}', _sanitize(download.uploader ?? ''))
        .replaceAll('{date}', _sanitize(download.uploadDate ?? ''))
        .replaceAll(
            '{download_date}',
            _sanitize(
                _formatDate(download.updatedAt)))
        .replaceAll('{platform}', _sanitize(download.platform))
        .replaceAll('{quality}', _sanitize(download.qualityLabel ?? ''))
        .replaceAll('{ext}', extNoDot);

    // Ensure the extension is preserved
    if (!result.endsWith(ext) && ext.isNotEmpty) {
      // Strip any trailing dot and append correct extension
      result = result.replaceAll(RegExp(r'\.$'), '');
      result = '$result$ext';
    }

    return result.isEmpty ? download.filename : result;
  }

  /// Apply a sorting rule to [download]: move to destFolder and/or rename.
  ///
  /// Returns the new absolute file path after applying the rule, or the
  /// original path if no change was made.
  ///
  /// Does NOT throw — logs and returns original path on failure.
  Future<String> applyRule(DownloadEntity download, SortingRule rule) async {
    final currentPath = p.join(download.savePath, download.filename);
    final currentDir = download.savePath;

    // Compute new filename
    final newFilename = rule.renameTemplate.isNotEmpty
        ? applyRename(rule.renameTemplate, download)
        : p.basename(currentPath);

    // Compute new directory
    final newDir =
        rule.destFolder.isNotEmpty ? rule.destFolder : currentDir;

    final newPath = p.join(newDir, newFilename);
    if (newPath == currentPath) return currentPath;

    try {
      final src = File(currentPath);
      if (!await src.exists()) {
        appLogger.warning(
            '[SortingRule] Source file not found: $currentPath');
        return currentPath;
      }

      await Directory(newDir).create(recursive: true);

      // Avoid overwrite collision — append (1), (2) etc.
      final resolvedPath = await _resolveConflict(newPath);
      await src.rename(resolvedPath);

      appLogger.info(
          '[SortingRule] Applied rule "${rule.name}": $currentPath → $resolvedPath');
      return resolvedPath;
    } catch (e) {
      appLogger.warning('[SortingRule] Failed to apply rule: $e');
      return currentPath;
    }
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  String _sanitize(String raw) {
    // Remove characters forbidden in filenames on macOS/Windows
    return raw
        .replaceAll(RegExp(r'[/\\:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _formatDate(DateTime dt) =>
      '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}';

  Future<String> _resolveConflict(String targetPath) async {
    if (!await File(targetPath).exists()) return targetPath;
    final dir = p.dirname(targetPath);
    final ext = p.extension(targetPath);
    final base = p.basenameWithoutExtension(targetPath);
    int counter = 1;
    while (true) {
      final candidate = p.join(dir, '$base ($counter)$ext');
      if (!await File(candidate).exists()) return candidate;
      counter++;
      if (counter > 999) return targetPath; // safety
    }
  }
}
