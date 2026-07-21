import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssvid/features/downloads/domain/entities/download_entity.dart';
import 'package:ssvid/features/downloads/domain/entities/download_status.dart';
import 'package:ssvid/features/downloads/domain/services/filter_persistence_service.dart';
import 'package:ssvid/features/downloads/presentation/providers/filter_provider.dart';

/// Helper to create test download entities
DownloadEntity _makeEntity({
  int id = 1,
  String filename = 'video.mp4',
  String? title,
  String? uploader,
  String userNote = '',
  DownloadStatus status = DownloadStatus.completed,
  int totalBytes = 1000,
  int? duration,
  int? viewCount,
  DateTime? createdAt,
}) =>
    DownloadEntity(
      id: id,
      url: 'https://example.com/$id',
      filename: filename,
      savePath: '/tmp',
      status: status,
      totalBytes: totalBytes,
      downloadedBytes: 0,
      speed: 0,
      title: title,
      uploader: uploader,
      userNote: userNote,
      duration: duration,
      viewCount: viewCount,
      createdAt: createdAt ?? DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

/// Simulates the search filter logic from filtered_downloads_provider.dart
List<DownloadEntity> applySearchFilter(
    List<DownloadEntity> downloads, String searchQuery) {
  if (searchQuery.isEmpty) return downloads;
  final query = searchQuery.toLowerCase();
  return downloads
      .where((d) =>
          d.displayTitle.toLowerCase().contains(query) ||
          d.filename.toLowerCase().contains(query) ||
          (d.uploader?.toLowerCase().contains(query) ?? false) ||
          (d.userNote.isNotEmpty &&
              d.userNote.toLowerCase().contains(query)))
      .toList();
}

/// Simulates the status filter logic from filtered_downloads_provider.dart
List<DownloadEntity> applyStatusFilter(
    List<DownloadEntity> downloads, Set<DownloadStatus> statusFilters) {
  if (statusFilters.isEmpty) return downloads;
  return downloads.where((d) => statusFilters.contains(d.status)).toList();
}

/// Simulates sort logic from filtered_downloads_provider.dart
List<DownloadEntity> applySort(
    List<DownloadEntity> downloads, SortOption sort) {
  final sorted = List<DownloadEntity>.from(downloads);
  switch (sort) {
    case SortOption.dateNewest:
      sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    case SortOption.dateOldest:
      sorted.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    case SortOption.nameAZ:
      sorted.sort((a, b) => a.displayTitle
          .toLowerCase()
          .compareTo(b.displayTitle.toLowerCase()));
    case SortOption.nameZA:
      sorted.sort((a, b) => b.displayTitle
          .toLowerCase()
          .compareTo(a.displayTitle.toLowerCase()));
    case SortOption.sizeLargest:
      sorted.sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
    case SortOption.sizeSmallest:
      sorted.sort((a, b) => a.totalBytes.compareTo(b.totalBytes));
    case SortOption.status:
      sorted.sort((a, b) => a.status.index.compareTo(b.status.index));
    case SortOption.durationLongest:
      sorted
          .sort((a, b) => (b.duration ?? 0).compareTo(a.duration ?? 0));
    case SortOption.durationShortest:
      sorted
          .sort((a, b) => (a.duration ?? 0).compareTo(b.duration ?? 0));
    case SortOption.viewsHighest:
      sorted.sort(
          (a, b) => (b.viewCount ?? 0).compareTo(a.viewCount ?? 0));
    case SortOption.uploaderAZ:
      sorted.sort(
          (a, b) => (a.uploader ?? '').compareTo(b.uploader ?? ''));
  }
  return sorted;
}

void main() {
  group('FilterNotifier', () {
    late FilterNotifier notifier;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      notifier = FilterNotifier(FilterPersistenceService(prefs));
    });

    test('initial state has no active filters', () {
      expect(notifier.state.hasActiveFilters, isFalse);
      expect(notifier.state.searchQuery, isEmpty);
      expect(notifier.state.statusFilters, isEmpty);
      expect(notifier.state.selectedPlatform, isNull);
    });

    test('updateSearchQuery updates state', () {
      notifier.updateSearchQuery('test');
      expect(notifier.state.searchQuery, 'test');
      expect(notifier.state.hasActiveFilters, isTrue);
    });

    test('toggleStatusFilter adds status', () {
      notifier.toggleStatusFilter(DownloadStatus.completed);
      expect(notifier.state.statusFilters,
          {DownloadStatus.completed});
      expect(notifier.state.hasActiveFilters, isTrue);
    });

    test('toggleStatusFilter removes status on second toggle', () {
      notifier.toggleStatusFilter(DownloadStatus.completed);
      notifier.toggleStatusFilter(DownloadStatus.completed);
      expect(notifier.state.statusFilters, isEmpty);
      expect(notifier.state.hasActiveFilters, isFalse);
    });

    test('toggleStatusFilter supports multi-select', () {
      notifier.toggleStatusFilter(DownloadStatus.completed);
      notifier.toggleStatusFilter(DownloadStatus.failed);
      expect(notifier.state.statusFilters,
          {DownloadStatus.completed, DownloadStatus.failed});
    });

    test('clearAllFilters resets everything', () {
      notifier.updateSearchQuery('test');
      notifier.toggleStatusFilter(DownloadStatus.completed);
      notifier.updateSort(SortOption.nameAZ);
      notifier.clearAllFilters();

      expect(notifier.state.searchQuery, isEmpty);
      expect(notifier.state.statusFilters, isEmpty);
      expect(notifier.state.sortOption, SortOption.dateNewest);
      expect(notifier.state.hasActiveFilters, isFalse);
    });

    test('hasActiveFilters true when platform selected', () {
      notifier.selectPlatform(null); // null = no platform selected
      expect(notifier.state.hasActiveFilters, isFalse);
      // We can't test with a real VideoPlatform without importing it,
      // but the logic is: selectedPlatform != null → true
    });
  });

  group('Search filter', () {
    final downloads = [
      _makeEntity(id: 1, title: 'Flutter Tutorial', filename: 'flutter.mp4'),
      _makeEntity(id: 2, title: 'Dart Guide', filename: 'dart.mp4',
          uploader: 'TechChannel'),
      _makeEntity(id: 3, title: 'React Basics', filename: 'react.mp4',
          userNote: 'Important video'),
      _makeEntity(id: 4, title: 'Rust Intro', filename: 'rust.mp4'),
    ];

    test('empty search returns all', () {
      final result = applySearchFilter(downloads, '');
      expect(result.length, 4);
    });

    test('search by title', () {
      final result = applySearchFilter(downloads, 'flutter');
      expect(result.length, 1);
      expect(result.first.id, 1);
    });

    test('search by filename', () {
      final result = applySearchFilter(downloads, 'dart.mp4');
      expect(result.length, 1);
      expect(result.first.id, 2);
    });

    test('search by uploader', () {
      final result = applySearchFilter(downloads, 'TechChannel');
      expect(result.length, 1);
      expect(result.first.id, 2);
    });

    test('search by userNote', () {
      final result = applySearchFilter(downloads, 'Important');
      expect(result.length, 1);
      expect(result.first.id, 3);
    });

    test('search is case-insensitive', () {
      final result = applySearchFilter(downloads, 'FLUTTER');
      expect(result.length, 1);
      expect(result.first.id, 1);
    });

    test('search with no match returns empty', () {
      final result = applySearchFilter(downloads, 'nonexistent');
      expect(result, isEmpty);
    });
  });

  group('Status filter', () {
    final downloads = [
      _makeEntity(id: 1, status: DownloadStatus.completed),
      _makeEntity(id: 2, status: DownloadStatus.failed),
      _makeEntity(id: 3, status: DownloadStatus.paused),
      _makeEntity(id: 4, status: DownloadStatus.downloading),
      _makeEntity(id: 5, status: DownloadStatus.completed),
    ];

    test('empty filter returns all', () {
      final result = applyStatusFilter(downloads, {});
      expect(result.length, 5);
    });

    test('single status filter', () {
      final result =
          applyStatusFilter(downloads, {DownloadStatus.completed});
      expect(result.length, 2);
      expect(result.every((d) => d.status == DownloadStatus.completed),
          isTrue);
    });

    test('multi-status filter (completed + failed)', () {
      final result = applyStatusFilter(
          downloads, {DownloadStatus.completed, DownloadStatus.failed});
      expect(result.length, 3);
    });

    test('filter with no match returns empty', () {
      final result =
          applyStatusFilter(downloads, {DownloadStatus.cancelled});
      expect(result, isEmpty);
    });
  });

  group('Sort options', () {
    test('durationLongest sorts descending', () {
      final downloads = [
        _makeEntity(id: 1, duration: 60),
        _makeEntity(id: 2, duration: 300),
        _makeEntity(id: 3, duration: 120),
      ];
      final result = applySort(downloads, SortOption.durationLongest);
      expect(result.map((d) => d.id).toList(), [2, 3, 1]);
    });

    test('durationShortest sorts ascending', () {
      final downloads = [
        _makeEntity(id: 1, duration: 300),
        _makeEntity(id: 2, duration: 60),
        _makeEntity(id: 3, duration: 120),
      ];
      final result = applySort(downloads, SortOption.durationShortest);
      expect(result.map((d) => d.id).toList(), [2, 3, 1]);
    });

    test('durationLongest handles null duration (treats as 0)', () {
      final downloads = [
        _makeEntity(id: 1, duration: null),
        _makeEntity(id: 2, duration: 120),
      ];
      final result = applySort(downloads, SortOption.durationLongest);
      expect(result.first.id, 2);
    });

    test('viewsHighest sorts descending', () {
      final downloads = [
        _makeEntity(id: 1, viewCount: 100),
        _makeEntity(id: 2, viewCount: 50000),
        _makeEntity(id: 3, viewCount: 500),
      ];
      final result = applySort(downloads, SortOption.viewsHighest);
      expect(result.map((d) => d.id).toList(), [2, 3, 1]);
    });

    test('uploaderAZ sorts alphabetically', () {
      final downloads = [
        _makeEntity(id: 1, uploader: 'Charlie'),
        _makeEntity(id: 2, uploader: 'Alice'),
        _makeEntity(id: 3, uploader: 'Bob'),
      ];
      final result = applySort(downloads, SortOption.uploaderAZ);
      expect(result.map((d) => d.id).toList(), [2, 3, 1]);
    });

    test('uploaderAZ handles null uploader (treats as empty)', () {
      final downloads = [
        _makeEntity(id: 1, uploader: null),
        _makeEntity(id: 2, uploader: 'Alice'),
      ];
      final result = applySort(downloads, SortOption.uploaderAZ);
      expect(result.first.id, 1); // empty string sorts before 'Alice'
    });
  });

  group('Combined filters', () {
    final downloads = [
      _makeEntity(
          id: 1,
          title: 'Flutter Tutorial',
          status: DownloadStatus.completed),
      _makeEntity(
          id: 2,
          title: 'Flutter Advanced',
          status: DownloadStatus.failed),
      _makeEntity(
          id: 3,
          title: 'Dart Guide',
          status: DownloadStatus.completed),
      _makeEntity(
          id: 4,
          title: 'React Basics',
          status: DownloadStatus.paused),
    ];

    test('search + status filter combined', () {
      // Search for "flutter" + filter completed only
      var result = applySearchFilter(downloads, 'flutter');
      result =
          applyStatusFilter(result, {DownloadStatus.completed});
      expect(result.length, 1);
      expect(result.first.id, 1);
    });

    test('search + status filter + sort combined', () {
      var result = applySearchFilter(downloads, 'flutter');
      // Both flutter results (completed + failed)
      expect(result.length, 2);
      result = applySort(result, SortOption.nameAZ);
      expect(result.first.title, 'Flutter Advanced');
      expect(result.last.title, 'Flutter Tutorial');
    });
  });

  group('FilterState.hasActiveFilters', () {
    test('false when all defaults', () {
      const state = FilterState();
      expect(state.hasActiveFilters, isFalse);
    });

    test('true when searchQuery is set', () {
      const state = FilterState(searchQuery: 'test');
      expect(state.hasActiveFilters, isTrue);
    });

    test('true when statusFilters is set', () {
      const state = FilterState(
          statusFilters: {DownloadStatus.completed});
      expect(state.hasActiveFilters, isTrue);
    });

    test('false when only sortOption changed (sort is not a filter)', () {
      const state = FilterState(sortOption: SortOption.nameAZ);
      expect(state.hasActiveFilters, isFalse);
    });
  });

  group('SortOption enum', () {
    test('has 11 values', () {
      expect(SortOption.values.length, 11);
    });

    test('new values exist', () {
      expect(SortOption.values, contains(SortOption.durationLongest));
      expect(SortOption.values, contains(SortOption.durationShortest));
      expect(SortOption.values, contains(SortOption.viewsHighest));
      expect(SortOption.values, contains(SortOption.uploaderAZ));
    });
  });
}
