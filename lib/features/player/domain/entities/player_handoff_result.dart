/// Playback state returned when moving between player surfaces.
///
/// Used by sidebar/fullscreen/PiP transitions to preserve the exact frame
/// and play/pause rhythm without relying on periodic watch-progress saves.
class PlayerHandoffResult {
  final Duration position;
  final bool isPlaying;
  final bool restoreSidebar;

  const PlayerHandoffResult({
    required this.position,
    required this.isPlaying,
    this.restoreSidebar = true,
  });
}
