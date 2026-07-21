/// One row of the `user_playlist_items` join — surfaced as a domain
/// entity so the presentation layer doesn't need to know about Drift
/// types. The `downloadId` is hydrated against the in-memory
/// downloads list (kept by `downloadsNotifierProvider`) when
/// rendering — saves a round-trip per playlist row.
class UserPlaylistMembership {
  final int downloadId;
  final String playlistId;
  final String playlistTitle;

  /// 0-based position within the parent playlist.
  final int position;

  const UserPlaylistMembership({
    required this.downloadId,
    required this.playlistId,
    required this.playlistTitle,
    required this.position,
  });
}
