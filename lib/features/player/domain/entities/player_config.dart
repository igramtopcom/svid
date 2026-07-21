import 'package:freezed_annotation/freezed_annotation.dart';

part 'player_config.freezed.dart';

/// Configuration for media player
@freezed
class PlayerConfig with _$PlayerConfig {
  const PlayerConfig._();

  const factory PlayerConfig({
    /// Auto-play on load
    @Default(true) bool autoPlay,

    /// Loop playback
    @Default(false) bool loop,

    /// Initial volume (0.0 to 1.0)
    @Default(1.0) double volume,

    /// Playback speed (0.25 to 4.0)
    @Default(1.0) double playbackSpeed,

    /// Enable hardware acceleration
    @Default(true) bool hardwareAcceleration,

    /// Enable subtitles if available
    @Default(true) bool enableSubtitles,

    /// Subtitle file path (external)
    String? subtitlePath,

    /// Buffer size in seconds
    @Default(10) int bufferSize,

    /// Seek precision in milliseconds
    @Default(5000) int seekStep,

    /// Show controls on start
    @Default(true) bool showControlsOnStart,

    /// Auto-hide controls timeout (seconds)
    @Default(3) int autoHideControlsTimeout,
  }) = _PlayerConfig;

  /// Default configuration
  static const PlayerConfig defaultConfig = PlayerConfig();

  /// Configuration for video playback
  static const PlayerConfig videoConfig = PlayerConfig(
    autoPlay: true,
    hardwareAcceleration: true,
    showControlsOnStart: true,
  );

  /// Configuration for audio playback
  static const PlayerConfig audioConfig = PlayerConfig(
    autoPlay: true,
    showControlsOnStart: false,
  );

  /// Configuration for continuous playback (playlist mode)
  static const PlayerConfig playlistConfig = PlayerConfig(
    autoPlay: true,
    loop: false,
  );

  /// Validate volume value
  bool get isVolumeValid => volume >= 0.0 && volume <= 1.0;

  /// Validate playback speed
  bool get isPlaybackSpeedValid => playbackSpeed >= 0.25 && playbackSpeed <= 4.0;
}
