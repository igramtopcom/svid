import '../../../downloads/domain/entities/download_entity.dart';
import '../../../downloads/presentation/providers/playlist_library_provider.dart';

/// Result of [selectPlaylistQueueSeed] — the queue list the playback
/// notifier should ingest plus the index of the tapped item inside
/// that list. An empty queue is the signal "no playlist context, clear
/// any stale queue from a previous playlist tap" — the playback tab
/// renders its empty state from there.
class PlaylistQueueSeed {
  final List<DownloadEntity> queue;
  final int startIndex;

  const PlaylistQueueSeed.empty() : queue = const [], startIndex = 0;

  const PlaylistQueueSeed({required this.queue, required this.startIndex});
}

/// Build the queue seed for a single-tap on [me]. When [me] belongs
/// to a YouTube source playlist (`playlistId` prefix `yt_`) the
/// siblings are pulled from [all], sorted by `playlistIndex` (with
/// filename as tiebreaker) so the up-next sequence mirrors the
/// original YouTube playlist order. Singleton playlists (only one
/// member tagged with the same id) are treated as no-context to
/// avoid an "up-next of one" that misleads users.
///
/// Pure function — no Riverpod, no UI deps — so the
/// downloads-list → queue contract is unit-testable in isolation
/// without spinning a WidgetTester.
PlaylistQueueSeed selectPlaylistQueueSeed({
  required DownloadEntity me,
  required List<DownloadEntity> all,
}) {
  final pid = me.playlistId;
  if (pid == null || pid.isEmpty || !pid.startsWith('yt_')) {
    return const PlaylistQueueSeed.empty();
  }

  final siblings = all.where((d) => d.playlistId == pid).toList();
  if (siblings.length <= 1) {
    return const PlaylistQueueSeed.empty();
  }

  siblings.sort((a, b) {
    final ai = a.playlistIndex ?? 999999;
    final bi = b.playlistIndex ?? 999999;
    if (ai != bi) return ai.compareTo(bi);
    return a.filename.compareTo(b.filename);
  });

  final foundIndex = siblings.indexWhere((d) => d.id == me.id);
  return PlaylistQueueSeed(
    queue: siblings,
    startIndex: foundIndex < 0 ? 0 : foundIndex,
  );
}

/// Build the queue seed from the richer playlist library surface
/// (source playlists + user-created playlists). [activePlaylistKey]
/// wins when the user is inside a playlist detail screen; otherwise
/// the first matching multi-item playlist is used.
PlaylistQueueSeed selectPlaylistLibraryQueueSeed({
  required DownloadEntity me,
  required List<PlaylistLibraryItem> playlists,
  String? activePlaylistKey,
}) {
  if (playlists.isEmpty) return const PlaylistQueueSeed.empty();

  final ordered = <PlaylistLibraryItem>[];
  if (activePlaylistKey != null) {
    ordered.addAll(playlists.where((p) => p.key == activePlaylistKey));
  }
  ordered.addAll(playlists.where((p) => p.key != activePlaylistKey));

  for (final playlist in ordered) {
    if (playlist.count <= 1) continue;
    final index = playlist.downloads.indexWhere((d) => d.id == me.id);
    if (index < 0) continue;
    return PlaylistQueueSeed(queue: playlist.downloads, startIndex: index);
  }

  return const PlaylistQueueSeed.empty();
}
