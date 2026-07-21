import '../../../downloads/domain/entities/download_entity.dart';
import 'download_list_helpers.dart';

/// Decision the grouped card emits when the user activates fullscreen
/// (double-tap, expand button, keyboard activate). Pulled out of the
/// widget so the routing rule — image carousel vs video queue —
/// can be unit-tested without spinning up a Navigator / Riverpod
/// container, and so a single source of truth governs every entry
/// point on the card (`onDoubleTap`, fullscreen IconButton, etc.).
sealed class GroupedCardOpenAction {
  const GroupedCardOpenAction();
}

/// Open the image-viewer carousel. The first image is the focused
/// frame; the rest are siblings in the swipe carousel.
class OpenImageCarousel extends GroupedCardOpenAction {
  final DownloadEntity first;
  final List<DownloadEntity> carousel;

  const OpenImageCarousel({required this.first, required this.carousel});
}

/// Open the video player with a playback queue seeded from the group.
/// The caller is expected to push the queue into
/// `playbackQueueProvider` BEFORE navigating to `VideoPlayerScreen`,
/// because the player widget reads queue state on init rather than
/// taking it as a constructor argument.
class OpenVideoQueue extends GroupedCardOpenAction {
  final DownloadEntity first;
  final List<DownloadEntity> queue;

  const OpenVideoQueue({required this.first, required this.queue});
}

/// Pure decision function — translate a [GroupedItemKind] + the
/// group's downloads into the routing action. The widget hands its
/// `widget.group.kind` and `widget.group.downloads` here and gets
/// back a typed action it dispatches on; that means navigation
/// behavior diverges by kind (image vs video) without the widget
/// itself growing a switch every time a new kind is added.
///
/// Throws [ArgumentError] if [downloads] is empty — a grouped card
/// without any underlying downloads should never reach activation.
GroupedCardOpenAction decideGroupedCardOpenAction({
  required GroupedItemKind kind,
  required List<DownloadEntity> downloads,
}) {
  if (downloads.isEmpty) {
    throw ArgumentError.value(
      downloads,
      'downloads',
      'Grouped card cannot be opened with an empty download list',
    );
  }
  final first = downloads.first;
  return switch (kind) {
    GroupedItemKind.imageCarousel => OpenImageCarousel(
        first: first,
        carousel: downloads,
      ),
    // Both YouTube source playlists (`yt_*`) and user-curated
    // playlists (`user_*`) are video collections — they share the
    // same player + queue surface. Routing them to ImageViewerScreen
    // is the V2 regression `f2e04405` introduced when this widget was
    // reused for non-image groups.
    GroupedItemKind.ytSourcePlaylist || GroupedItemKind.userPlaylist =>
      OpenVideoQueue(first: first, queue: downloads),
  };
}
