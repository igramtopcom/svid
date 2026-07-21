import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../domain/entities/download_entity.dart';
import '../../domain/entities/user_playlist_membership.dart';
import '../../domain/entities/user_playlist_summary.dart';
import 'downloads_notifier.dart';
import 'user_playlist_memberships_provider.dart';
import 'user_playlists_provider.dart';

enum PlaylistLibraryKind { source, user }

class PlaylistLibraryItem {
  final String id;
  final String title;
  final PlaylistLibraryKind kind;
  final List<DownloadEntity> downloads;

  const PlaylistLibraryItem({
    required this.id,
    required this.title,
    required this.kind,
    required this.downloads,
  });

  String get key => '${kind.name}:$id';
  int get count => downloads.length;
  DownloadEntity get first => downloads.first;

  DateTime get updatedAt {
    if (downloads.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    return downloads
        .map(
          (d) => d.updatedAt.isAfter(d.createdAt) ? d.updatedAt : d.createdAt,
        )
        .fold<DateTime>(
          downloads.first.createdAt,
          (latest, date) => date.isAfter(latest) ? date : latest,
        );
  }
}

final activePlaylistContextProvider = StateProvider<String?>((_) => null);

final playlistLibraryProvider = Provider<List<PlaylistLibraryItem>>((ref) {
  final downloads = ref.watch(
    downloadsNotifierProvider.select((state) => state.downloads),
  );
  final memberships =
      ref.watch(userPlaylistMembershipsProvider).valueOrNull ?? const [];
  final userPlaylists =
      ref.watch(userPlaylistsProvider).valueOrNull ?? const [];

  return buildPlaylistLibraryItems(
    downloads: downloads,
    memberships: memberships,
    userPlaylists: userPlaylists,
  );
});

List<PlaylistLibraryItem> buildPlaylistLibraryItems({
  required List<DownloadEntity> downloads,
  required List<UserPlaylistMembership> memberships,
  List<UserPlaylistSummary> userPlaylists = const [],
}) {
  final items = <PlaylistLibraryItem>[];
  final byId = {for (final d in downloads) d.id: d};

  final sourceGroups = <String, List<DownloadEntity>>{};
  final sourceTitles = <String, String>{};
  for (final download in downloads) {
    final playlistId = download.playlistId?.trim();
    if (playlistId == null || playlistId.isEmpty) continue;
    sourceGroups.putIfAbsent(playlistId, () => []).add(download);
    final title = download.playlistTitle?.trim();
    if (title != null && title.isNotEmpty) {
      sourceTitles[playlistId] = title;
    }
  }

  for (final entry in sourceGroups.entries) {
    final group = [...entry.value]..sort(_comparePlaylistDownloads);
    if (group.isEmpty) continue;
    items.add(
      PlaylistLibraryItem(
        id: entry.key,
        title:
            sourceTitles[entry.key] ??
            _fallbackSourcePlaylistTitle(entry.key, group.first),
        kind: PlaylistLibraryKind.source,
        downloads: group,
      ),
    );
  }

  final userGroupsRaw =
      <String, List<({DownloadEntity download, int position, String title})>>{};
  final userOrder = userPlaylists.map((p) => p.playlistId).toList();
  final userTitles = {
    for (final playlist in userPlaylists) playlist.playlistId: playlist.title,
  };
  for (final membership in memberships) {
    final download = byId[membership.downloadId];
    if (!userGroupsRaw.containsKey(membership.playlistId)) {
      if (!userOrder.contains(membership.playlistId)) {
        userOrder.add(membership.playlistId);
      }
    }
    userTitles.putIfAbsent(
      membership.playlistId,
      () => membership.playlistTitle,
    );
    if (download == null) continue;
    userGroupsRaw.putIfAbsent(membership.playlistId, () => []).add((
      download: download,
      position: membership.position,
      title: membership.playlistTitle,
    ));
  }

  for (final playlistId in userOrder) {
    final raw = [...?userGroupsRaw[playlistId]];
    raw.sort((a, b) => a.position.compareTo(b.position));
    final downloads = raw.map((entry) => entry.download).toList();
    items.add(
      PlaylistLibraryItem(
        id: playlistId,
        title:
            userTitles[playlistId] ??
            (raw.isNotEmpty ? raw.first.title : AppLocalizations.playlistFallbackTitle),
        kind: PlaylistLibraryKind.user,
        downloads: downloads,
      ),
    );
  }

  items.sort((a, b) {
    if (a.kind != b.kind) {
      return a.kind == PlaylistLibraryKind.user ? -1 : 1;
    }
    return b.updatedAt.compareTo(a.updatedAt);
  });
  return items;
}

int _comparePlaylistDownloads(DownloadEntity a, DownloadEntity b) {
  final ai = a.playlistIndex ?? 999999;
  final bi = b.playlistIndex ?? 999999;
  if (ai != bi) return ai.compareTo(bi);
  return a.filename.compareTo(b.filename);
}

String _fallbackSourcePlaylistTitle(String playlistId, DownloadEntity first) {
  final cleaned =
      playlistId
          .replaceFirst(RegExp(r'^yt_'), '')
          .replaceAll(RegExp(r'[_\-]+'), ' ')
          .trim();
  if (cleaned.isNotEmpty) return cleaned;
  return first.uploader?.trim().isNotEmpty == true
      ? first.uploader!.trim()
      : 'YouTube Playlist';
}
