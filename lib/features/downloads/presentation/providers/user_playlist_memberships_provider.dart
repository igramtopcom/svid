import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/user_playlist_membership.dart';
import 'download_providers.dart';

/// Live `user_playlist_items` rows for FilterTab.playlist rendering.
/// Backed by a Drift custom-stream so the list repaints whenever the
/// underlying join changes — no manual invalidate from add/remove
/// call sites required.
///
/// Returns the *current* membership snapshot synchronously after the
/// first emission (asyncData). Callers that don't tolerate a brief
/// loading state can fall back to an empty list while the first
/// query is in flight.
final userPlaylistMembershipsProvider =
    StreamProvider<List<UserPlaylistMembership>>((ref) async* {
  final repo = ref.watch(downloadRepositoryProvider);

  // Initial snapshot before the change-stream fires its first event.
  final first = await repo.getUserPlaylistMemberships();
  yield first.when(
    success: (list) => list,
    failure: (_) => const [],
  );

  // Subsequent emissions on every change. The stream itself only
  // ticks (no payload), so we re-query for the typed list each tick.
  await for (final _ in repo.watchUserPlaylistChanges()) {
    final r = await repo.getUserPlaylistMemberships();
    yield r.when(
      success: (list) => list,
      failure: (_) => const [],
    );
  }
});
