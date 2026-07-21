import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/providers/database_provider.dart';

/// Normalizes a raw tag input: lowercase, trimmed, max 30 characters.
String normalizeTag(String raw) {
  final trimmed = raw.trim().toLowerCase();
  return trimmed.length > 30 ? trimmed.substring(0, 30) : trimmed;
}

/// Service for managing tags on downloads.
///
/// Operates directly on [AppDatabase] — pure async, no UI dependencies.
class TaggingService {
  final AppDatabase _db;

  TaggingService(this._db);

  /// Add a tag to a download.
  ///
  /// Normalizes [tag] (lowercase, trim, max 30 chars). Silently deduplicates.
  /// Returns the normalized tag, or `null` if the tag was empty after normalization.
  Future<String?> addTag(int downloadId, String rawTag) async {
    final tag = normalizeTag(rawTag);
    if (tag.isEmpty) return null;
    await _db.insertTag(downloadId, tag);
    return tag;
  }

  /// Remove a tag from a download. Normalizes [tag] before matching.
  Future<void> removeTag(int downloadId, String rawTag) async {
    final tag = normalizeTag(rawTag);
    if (tag.isEmpty) return;
    await _db.deleteTag(downloadId, tag);
  }

  /// Get all tags for a specific download (alphabetical order).
  Future<List<String>> getTagsForDownload(int downloadId) {
    return _db.getTagsForDownload(downloadId);
  }

  /// Get all distinct tags used across all downloads (alphabetical order).
  Future<List<String>> getAllTags() {
    return _db.getAllTags();
  }

  /// Get download IDs that have the given tag. Normalizes [tag] before query.
  Future<List<int>> getDownloadsByTag(String rawTag) {
    final tag = normalizeTag(rawTag);
    if (tag.isEmpty) return Future.value([]);
    return _db.getDownloadIdsByTag(tag);
  }

  /// Get a map of downloadId → list of tags (for efficient bulk lookup in filters).
  Future<Map<int, List<String>>> getAllTagsMap() {
    return _db.getAllTagsMap();
  }

  /// Stream of the full tags map.  Emits a new value whenever any tag is
  /// added or removed, enabling reactive UI without polling.
  Stream<Map<int, List<String>>> watchAllTagsMap() {
    return _db.watchAllTagsMap();
  }
}

// ---------------------------------------------------------------------------
// Riverpod providers
// ---------------------------------------------------------------------------

/// Provider for [AppDatabase] (registered in core/core.dart or main.dart).
/// Re-exported here for convenience; the actual provider is in app_database_provider.dart.
final taggingServiceProvider = Provider<TaggingService>((ref) {
  final db = ref.watch(databaseProvider);
  return TaggingService(db);
});

/// Reactive tags map: downloadId → list of tags.
///
/// Backed by [AppDatabase.watchAllTagsMap] so the provider rebuilds only when
/// the [DownloadTags] table actually changes — not on every DB emission.
/// Consumers should use `.valueOrNull ?? {}` to handle the initial loading state.
final tagsMapProvider = StreamProvider<Map<int, List<String>>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAllTagsMap();
});
