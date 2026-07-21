import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/platform_detector.dart';
import '../../../player/presentation/providers/player_providers.dart';
import '../../domain/entities/download_entity.dart';
import '../../domain/entities/user_playlist_membership.dart';
import '../../domain/services/tagging_service.dart';
import 'downloads_notifier.dart';
import 'filter_provider.dart';
import 'user_playlist_memberships_provider.dart';
import 'user_playlists_provider.dart';

/// Filtered downloads provider
/// Returns downloads filtered by current FilterState (tab, platform, format) + sorted.
///
/// Uses `select()` to narrow the watch to `DownloadsState.downloads` only,
/// so changes to `activePlaylist`, `smartBoostedIds`, etc. do NOT trigger a rebuild.
final filteredDownloadsProvider = Provider<List<DownloadEntity>>((ref) {
  final allDownloads = ref.watch(
    downloadsNotifierProvider.select((s) => s.downloads),
  );
  final filterState = ref.watch(filterProvider);
  List<DownloadEntity> result;

  // Apply filters based on selected tab
  switch (filterState.selectedTab) {
    case FilterTab.all:
      if (filterState.selectedPlatform != null) {
        result =
            allDownloads
                .where(
                  (d) =>
                      d.platform == filterState.selectedPlatform!.toDbString(),
                )
                .toList();
      } else {
        result = List.of(allDownloads);
      }

    case FilterTab.video:
      final videos =
          allDownloads.where((d) => _isVideo(d.fileExtension)).toList();
      if (filterState.selectedPlatform != null) {
        result =
            videos
                .where(
                  (d) =>
                      d.platform == filterState.selectedPlatform!.toDbString(),
                )
                .toList();
      } else {
        result = videos;
      }

    case FilterTab.audio:
      final audios =
          allDownloads.where((d) => _isAudio(d.fileExtension)).toList();
      if (filterState.selectedPlatform != null) {
        result =
            audios
                .where(
                  (d) =>
                      d.platform == filterState.selectedPlatform!.toDbString(),
                )
                .toList();
      } else {
        result = audios;
      }

    case FilterTab.image:
      final images =
          allDownloads.where((d) => _isImage(d.fileExtension)).toList();
      if (filterState.selectedPlatform != null) {
        result =
            images
                .where(
                  (d) =>
                      d.platform == filterState.selectedPlatform!.toDbString(),
                )
                .toList();
      } else {
        result = images;
      }

    case FilterTab.playlist:
      // v20 Hybrid #1+#2 — union two membership sources:
      //   #1 Source-grouped: downloads with non-null `playlistId` on
      //      the row itself (yt_<list_id>, populated by the YouTube
      //      playlist sheet via `HomeBatchDownloadMixin`).
      //   #2 User-curated: downloads referenced by `user_playlist_items`
      //      (M:N memberships from the "Add to playlist" dialog).
      //
      // GroupedItem in `download_list_helpers.dart` then groups the
      // resulting rows by their playlist tag so a 50-video playlist
      // collapses into a single header — see that file for grouping
      // rules.
      final memberships =
          ref.watch(userPlaylistMembershipsProvider).valueOrNull ?? const [];
      final playlistDownloads = _playlistDownloadsFor(
        allDownloads,
        memberships,
      );
      if (filterState.selectedPlatform != null) {
        result =
            playlistDownloads
                .where(
                  (d) =>
                      d.platform == filterState.selectedPlatform!.toDbString(),
                )
                .toList();
      } else {
        result = playlistDownloads;
      }
  }

  // 3. Search filter (title, filename, uploader, userNote)
  if (filterState.searchQuery.isNotEmpty) {
    final query = filterState.searchQuery.toLowerCase();
    result =
        result
            .where(
              (d) =>
                  d.displayTitle.toLowerCase().contains(query) ||
                  d.filename.toLowerCase().contains(query) ||
                  (d.uploader?.toLowerCase().contains(query) ?? false) ||
                  (d.userNote.isNotEmpty &&
                      d.userNote.toLowerCase().contains(query)),
            )
            .toList();
  }

  // 4. Status filter
  if (filterState.statusFilters.isNotEmpty) {
    result =
        result
            .where((d) => filterState.statusFilters.contains(d.status))
            .toList();
  }

  // 5. Tag filter (AND logic: download must have ALL selected tags)
  if (filterState.selectedTags.isNotEmpty) {
    final tagsMap = ref.watch(tagsMapProvider).valueOrNull ?? {};
    result =
        result.where((d) {
          final tags = tagsMap[d.id] ?? [];
          return filterState.selectedTags.every(tags.contains);
        }).toList();
  }

  // 6. Watch filter
  if (filterState.watchFilter != WatchFilter.all) {
    final watchService = ref.read(watchProgressServiceProvider);
    result =
        result.where((d) {
          switch (filterState.watchFilter) {
            case WatchFilter.watched:
              return d.isWatched;
            case WatchFilter.watching:
              // Has partial progress but not fully watched
              return !d.isWatched &&
                  (watchService.getWatchFraction(d.id) ?? 0) > 0;
            case WatchFilter.unwatched:
              // Never opened (no progress at all and not watched)
              return !d.isWatched &&
                  (watchService.getWatchFraction(d.id) ?? 0) == 0;
            case WatchFilter.all:
              return true;
          }
        }).toList();
  }

  // Apply sort
  return _applySortOption(result, filterState.sortOption);
});

/// Apply sort option to downloads list
List<DownloadEntity> _applySortOption(
  List<DownloadEntity> downloads,
  SortOption sort,
) {
  final sorted = List<DownloadEntity>.from(downloads);
  switch (sort) {
    case SortOption.dateNewest:
      // Primary: queuePosition ASC (nulls last) — respects D&D manual order
      // Secondary: createdAt DESC — new downloads without a position float to top of unordered group
      sorted.sort((a, b) {
        final aPos = a.queuePosition;
        final bPos = b.queuePosition;
        if (aPos == null && bPos == null) {
          return b.createdAt.compareTo(a.createdAt);
        }
        if (aPos == null) return 1; // a has no position → sort after b
        if (bPos == null) return -1; // b has no position → sort after a
        final cmp = aPos.compareTo(bPos);
        return cmp != 0 ? cmp : b.createdAt.compareTo(a.createdAt);
      });
    case SortOption.dateOldest:
      sorted.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    case SortOption.nameAZ:
      sorted.sort(
        (a, b) => a.displayTitle.toLowerCase().compareTo(
          b.displayTitle.toLowerCase(),
        ),
      );
    case SortOption.nameZA:
      sorted.sort(
        (a, b) => b.displayTitle.toLowerCase().compareTo(
          a.displayTitle.toLowerCase(),
        ),
      );
    case SortOption.sizeLargest:
      sorted.sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
    case SortOption.sizeSmallest:
      sorted.sort((a, b) => a.totalBytes.compareTo(b.totalBytes));
    case SortOption.status:
      sorted.sort((a, b) => a.status.index.compareTo(b.status.index));
    case SortOption.durationLongest:
      sorted.sort((a, b) => (b.duration ?? 0).compareTo(a.duration ?? 0));
    case SortOption.durationShortest:
      sorted.sort((a, b) => (a.duration ?? 0).compareTo(b.duration ?? 0));
    case SortOption.viewsHighest:
      sorted.sort((a, b) => (b.viewCount ?? 0).compareTo(a.viewCount ?? 0));
    case SortOption.uploaderAZ:
      sorted.sort((a, b) => (a.uploader ?? '').compareTo(b.uploader ?? ''));
  }
  return sorted;
}

/// Check if file extension is video
bool _isVideo(String ext) {
  const videoExts = [
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.wmv',
    '.flv',
    '.webm',
    '.m4v',
  ];
  return videoExts.contains(ext.toLowerCase());
}

/// Check if file extension is audio
bool _isAudio(String ext) {
  const audioExts = [
    '.mp3',
    '.wav',
    '.flac',
    '.m4a',
    '.aac',
    '.ogg',
    '.wma',
    '.opus',
  ];
  return audioExts.contains(ext.toLowerCase());
}

/// Check if file extension is image
bool _isImage(String ext) {
  const imageExts = [
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.bmp',
    '.svg',
    '.heic',
    '.heif',
  ];
  return imageExts.contains(ext.toLowerCase());
}

/// Provider: Get available tabs based on downloads data
/// Only show tabs that have downloads
final availableTabsProvider = Provider<List<FilterTab>>((ref) {
  final allDownloads = ref.watch(
    downloadsNotifierProvider.select((s) => s.downloads),
  );

  if (allDownloads.isEmpty) {
    return [FilterTab.all]; // Always show All tab
  }

  final availableTabs = <FilterTab>[FilterTab.all]; // All is always available

  // Check for videos
  if (allDownloads.any((d) => _isVideo(d.fileExtension))) {
    availableTabs.add(FilterTab.video);
  }

  // Check for audios
  if (allDownloads.any((d) => _isAudio(d.fileExtension))) {
    availableTabs.add(FilterTab.audio);
  }

  // Check for images
  if (allDownloads.any((d) => _isImage(d.fileExtension))) {
    availableTabs.add(FilterTab.image);
  }

  final counts = ref.watch(downloadCountsProvider);
  if ((counts[FilterTab.playlist] ?? 0) > 0) {
    availableTabs.add(FilterTab.playlist);
  }

  return availableTabs;
});

/// Provider: Get available platforms based on downloads data
/// Returns list of platforms that have downloads
final availablePlatformsProvider = Provider<List<VideoPlatform>>((ref) {
  final allDownloads = ref.watch(
    downloadsNotifierProvider.select((s) => s.downloads),
  );

  if (allDownloads.isEmpty) return [];

  // Get unique platforms
  final platformStrings =
      allDownloads
          .map((d) => d.platform)
          .where((p) => p.isNotEmpty)
          .toSet()
          .toList();

  // Convert to VideoPlatform enum
  final platforms =
      platformStrings.map((p) => VideoPlatform.fromDbString(p)).toList();

  return platforms;
});

/// Provider: Get available platforms for current filter
/// When in specific tab (video/audio/image), only show platforms that have that type
final availablePlatformsForCurrentTabProvider = Provider<List<VideoPlatform>>((
  ref,
) {
  final allDownloads = ref.watch(
    downloadsNotifierProvider.select((s) => s.downloads),
  );
  final filterState = ref.watch(filterProvider);

  if (allDownloads.isEmpty) return [];

  List<DownloadEntity> relevantDownloads;

  switch (filterState.selectedTab) {
    case FilterTab.video:
      relevantDownloads =
          allDownloads.where((d) => _isVideo(d.fileExtension)).toList();
      break;
    case FilterTab.audio:
      relevantDownloads =
          allDownloads.where((d) => _isAudio(d.fileExtension)).toList();
      break;
    case FilterTab.image:
      relevantDownloads =
          allDownloads.where((d) => _isImage(d.fileExtension)).toList();
      break;
    case FilterTab.playlist:
      relevantDownloads = _playlistDownloadsFor(
        allDownloads,
        ref.watch(userPlaylistMembershipsProvider).valueOrNull ?? const [],
      );
      break;
    default:
      relevantDownloads = allDownloads;
  }

  // Get unique platforms from relevant downloads
  final platformStrings =
      relevantDownloads
          .map((d) => d.platform)
          .where((p) => p.isNotEmpty)
          .toSet()
          .toList();

  // Convert to VideoPlatform enum
  final platforms =
      platformStrings.map((p) => VideoPlatform.fromDbString(p)).toList();

  return platforms;
});

/// Provider: Download counts per tab (for sidebar badges)
final downloadCountsProvider = Provider<Map<FilterTab, int>>((ref) {
  final allDownloads = ref.watch(
    downloadsNotifierProvider.select((s) => s.downloads),
  );

  // Playlist tab counts unique playlists, not videos — two videos in
  // the same playlist contribute one to the badge ("3 playlists" not
  // "60 videos across 3"). Source and user-created playlists are
  // deliberately namespaced because they are different user surfaces
  // even if their raw ids ever collide.
  final ytPlaylistIds =
      allDownloads
          .where((d) => d.playlistId != null && d.playlistId!.isNotEmpty)
          .map((d) => 'source:${d.playlistId!}')
          .toSet();
  final memberships =
      ref.watch(userPlaylistMembershipsProvider).valueOrNull ?? const [];
  final userPlaylists =
      ref.watch(userPlaylistsProvider).valueOrNull ?? const [];
  final userPlaylistIds = {
    ...memberships.map((m) => 'user:${m.playlistId}'),
    ...userPlaylists.map((p) => 'user:${p.playlistId}'),
  };
  final allPlaylistIds = {...ytPlaylistIds, ...userPlaylistIds};

  return {
    FilterTab.all: allDownloads.length,
    FilterTab.video:
        allDownloads.where((d) => _isVideo(d.fileExtension)).length,
    FilterTab.audio:
        allDownloads.where((d) => _isAudio(d.fileExtension)).length,
    FilterTab.image:
        allDownloads.where((d) => _isImage(d.fileExtension)).length,
    FilterTab.playlist: allPlaylistIds.length,
  };
});

/// Provider: Download count per platform for current tab (for filter chip labels)
final platformCountsForCurrentTabProvider = Provider<Map<VideoPlatform, int>>((
  ref,
) {
  final allDownloads = ref.watch(
    downloadsNotifierProvider.select((s) => s.downloads),
  );
  final filterState = ref.watch(filterProvider);

  List<DownloadEntity> relevantDownloads;
  switch (filterState.selectedTab) {
    case FilterTab.video:
      relevantDownloads =
          allDownloads.where((d) => _isVideo(d.fileExtension)).toList();
    case FilterTab.audio:
      relevantDownloads =
          allDownloads.where((d) => _isAudio(d.fileExtension)).toList();
    case FilterTab.image:
      relevantDownloads =
          allDownloads.where((d) => _isImage(d.fileExtension)).toList();
    case FilterTab.playlist:
      relevantDownloads = _playlistDownloadsFor(
        allDownloads,
        ref.watch(userPlaylistMembershipsProvider).valueOrNull ?? const [],
      );
    default:
      relevantDownloads = allDownloads;
  }

  final counts = <VideoPlatform, int>{};
  for (final d in relevantDownloads) {
    if (d.platform.isNotEmpty) {
      final p = VideoPlatform.fromDbString(d.platform);
      counts[p] = (counts[p] ?? 0) + 1;
    }
  }
  return counts;
});

List<DownloadEntity> _playlistDownloadsFor(
  List<DownloadEntity> allDownloads,
  List<UserPlaylistMembership> memberships,
) {
  final userMemberIds = memberships.map((m) => m.downloadId).toSet();
  return allDownloads
      .where(
        (d) =>
            (d.playlistId != null && d.playlistId!.isNotEmpty) ||
            userMemberIds.contains(d.id),
      )
      .toList();
}
