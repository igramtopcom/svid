/// Projection of a user-curated playlist (v20 C-lite). Backed by the
/// `user_playlists` table — title is non-null because the dialog
/// requires non-empty input on creation. yt_* source playlists do
/// not appear here; those remain a derived property of
/// `downloads.playlistId` and are queried separately.
///
/// Member count is recomputed on every fetch (never cached) so the
/// dialog row badge stays in sync with concurrent add/remove writes.
class UserPlaylistSummary {
  /// Stable id, always prefixed `user_<uuid>`.
  final String playlistId;

  /// Display title — required at creation, never empty.
  final String title;

  /// Member count at query time.
  final int count;

  const UserPlaylistSummary({
    required this.playlistId,
    required this.title,
    required this.count,
  });
}
