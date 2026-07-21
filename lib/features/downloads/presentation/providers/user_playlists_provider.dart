import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/user_playlist_summary.dart';
import 'download_providers.dart';
import 'downloads_notifier.dart';

/// Live-derived list of user-curated playlists. Recomputed any time
/// the downloads stream produces a new list (covers add / remove /
/// rename via tag-rewrite). The dialog watches this so opening it
/// twice in a row reflects edits made in between.
///
/// Returns empty when no `user_*` row exists. Failures bubble up as
/// AsyncValue.error and are surfaced inline by the dialog.
final userPlaylistsProvider =
    FutureProvider<List<UserPlaylistSummary>>((ref) async {
  // Re-run on any downloads-list change. Cheap query, runs only when
  // the dialog is open (autoDispose is unnecessary here — provider
  // is cheap to keep alive given the sidebar may also display this).
  ref.watch(downloadsNotifierProvider);

  final repo = ref.watch(downloadRepositoryProvider);
  final result = await repo.getUserPlaylists();
  return result.when(
    success: (list) => list,
    failure: (e) => throw e,
  );
});
