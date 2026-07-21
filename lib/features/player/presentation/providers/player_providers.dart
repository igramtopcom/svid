import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../data/repositories/player_repository_impl.dart';
import '../../domain/repositories/player_repository.dart';
import '../../domain/services/mini_player_position_service.dart';
import '../../domain/services/player_prefs_service.dart';
import '../../domain/services/player_safety.dart';
import '../../domain/services/watch_progress_service.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../downloads/domain/entities/download_entity.dart';
import '../../../downloads/presentation/providers/download_providers.dart';

/// Provider for PlayerRepository
final playerRepositoryProvider = Provider<PlayerRepository>((ref) {
  return PlayerRepositoryImpl();
});

/// Provider for WatchProgressService (playback resume + watched flag)
final watchProgressServiceProvider = Provider<WatchProgressService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final repo = ref.watch(downloadRepositoryProvider);
  return WatchProgressService(prefs, repository: repo);
});

/// Provider for PlayerPrefsService (per-file speed/volume/subtitle preferences)
final playerPrefsServiceProvider = Provider<PlayerPrefsService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return PlayerPrefsService(prefs);
});

/// Provider for MiniPlayerPositionService (shared by video and audio PiP)
final miniPlayerPositionServiceProvider = Provider<MiniPlayerPositionService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return MiniPlayerPositionService(prefs);
});

/// Provider for media_kit Player instance
/// This is used for video and audio playback
final mediaPlayerProvider = Provider.autoDispose<Player>((ref) {
  final player = Player();

  // Dispose player when no longer needed
  ref.onDispose(() {
    unawaited(
      player.dispose().catchError((Object error) {
        if (PlayerSafety.isDisposedPlayerError(error)) return;
        debugPrint('[mediaPlayerProvider] dispose failed: $error');
      }),
    );
  });

  return player;
});

/// Provider for managing player state (for a specific file)
final currentMediaProvider = StateProvider<String?>((ref) => null);

/// Provider for tracking current position
final playerPositionProvider = StateProvider<Duration>((ref) => Duration.zero);

/// Provider for tracking total duration
final playerDurationProvider = StateProvider<Duration>((ref) => Duration.zero);

/// Provider for tracking volume
final playerVolumeProvider = StateProvider<double>((ref) => 1.0);

/// Provider for tracking playback speed
final playbackSpeedProvider = StateProvider<double>((ref) => 1.0);

/// Provider for tracking fullscreen state
final isFullscreenProvider = StateProvider<bool>((ref) => false);

/// Provider for tracking controls visibility
final showControlsProvider = StateProvider<bool>((ref) => true);

/// Provider for tracking buffering state
final isBufferingProvider = StateProvider<bool>((ref) => false);

/// Aspect ratio mode for video player
enum AspectRatioMode {
  fit,    // Fit with black bars (maintain aspect ratio)
  fill,   // Fill screen (may crop video)
  stretch, // Stretch to fill (distort aspect ratio)
  original; // 1:1 pixel mapping

  String get label {
    switch (this) {
      case AspectRatioMode.fit:
        return 'Fit';
      case AspectRatioMode.fill:
        return 'Fill';
      case AspectRatioMode.stretch:
        return 'Stretch';
      case AspectRatioMode.original:
        return 'Original';
    }
  }

  IconData get icon {
    switch (this) {
      case AspectRatioMode.fit:
        return Icons.fit_screen;
      case AspectRatioMode.fill:
        return Icons.crop_free;
      case AspectRatioMode.stretch:
        return Icons.aspect_ratio;
      case AspectRatioMode.original:
        return Icons.crop_original;
    }
  }
}

/// Provider for aspect ratio mode
final aspectRatioModeProvider = StateProvider<AspectRatioMode>((ref) => AspectRatioMode.fit);

/// Provider for current subtitle track selection
/// Uses SubtitleTrack from media_kit
final currentSubtitleTrackProvider = StateProvider<SubtitleTrack>((ref) => SubtitleTrack.no());

/// Provider for current audio track selection
/// Uses AudioTrack from media_kit (AudioTrack.no() = default track)
final currentAudioTrackProvider = StateProvider<AudioTrack>((ref) => AudioTrack.no());

/// Provider for subtitle delay in milliseconds (range: -5000 to +5000, default 0)
final subtitleDelayProvider = StateProvider<int>((ref) => 0);

/// Provider for whether chapter panel is open
final chaptersPanelOpenProvider = StateProvider<bool>((ref) => false);

/// Cinema Mode — immersive viewing with enhanced vignette, minimal chrome
final cinemaModeProvider = StateProvider<bool>((ref) => false);

/// A-B Repeat point A (start of loop)
final abRepeatPointAProvider = StateProvider<Duration?>((ref) => null);

/// A-B Repeat point B (end of loop)
final abRepeatPointBProvider = StateProvider<Duration?>((ref) => null);

/// Whether A-B repeat is currently active (both points set)
final isAbRepeatActiveProvider = Provider<bool>((ref) {
  return ref.watch(abRepeatPointAProvider) != null &&
      ref.watch(abRepeatPointBProvider) != null;
});

/// Subtitle font size (default: 32.0, range: 16-64)
final subtitleFontSizeProvider = StateProvider<double>((ref) => 32.0);

/// Subtitle text color (default: white)
final subtitleTextColorProvider = StateProvider<Color>((ref) => const Color(0xFFFFFFFF));

/// Subtitle background color (default: semi-transparent black)
final subtitleBackgroundColorProvider = StateProvider<Color>((ref) => const Color(0xAA000000));

/// Subtitle background enabled (default: true)
final subtitleBackgroundEnabledProvider = StateProvider<bool>((ref) => true);

/// Subtitle bottom padding / position (default: 24.0, range: 0-100)
final subtitleBottomPaddingProvider = StateProvider<double>((ref) => 24.0);

/// Computed SubtitleViewConfiguration from subtitle style providers
final subtitleViewConfigProvider = Provider<SubtitleViewConfiguration>((ref) {
  final fontSize = ref.watch(subtitleFontSizeProvider);
  final textColor = ref.watch(subtitleTextColorProvider);
  final bgColor = ref.watch(subtitleBackgroundColorProvider);
  final bgEnabled = ref.watch(subtitleBackgroundEnabledProvider);
  final bottomPadding = ref.watch(subtitleBottomPaddingProvider);

  return SubtitleViewConfiguration(
    style: TextStyle(
      height: 1.4,
      fontSize: fontSize,
      letterSpacing: 0.0,
      wordSpacing: 0.0,
      color: textColor,
      fontWeight: FontWeight.normal,
      backgroundColor: bgEnabled ? bgColor : Colors.transparent,
    ),
    textAlign: TextAlign.center,
    padding: EdgeInsets.fromLTRB(16.0, 0.0, 16.0, bottomPadding),
  );
});

/// Provider for mini player state (for audio)
final miniPlayerStateProvider = StateProvider<MiniPlayerState?>((ref) => null);

/// Provider for mini video player state (for video PiP)
final miniVideoPlayerStateProvider = StateProvider<MiniVideoPlayerState?>((ref) => null);

/// Mini Player State (for audio)
class MiniPlayerState {
  final Player player;
  final String filename;
  final String? thumbnail;
  final DownloadEntity downloadEntity;
  final String downloadId; // Consistent ID for player management

  MiniPlayerState({
    required this.player,
    required this.filename,
    this.thumbnail,
    required this.downloadEntity,
    required this.downloadId,
  });
}

/// Mini Video Player State (for video PiP)
class MiniVideoPlayerState {
  final Player player;
  final VideoController videoController;
  final String filename;
  final DownloadEntity downloadEntity;
  final String downloadId; // Consistent ID for player management
  final Duration? resumePosition; // Position to resume from when expanding

  MiniVideoPlayerState({
    required this.player,
    required this.videoController,
    required this.filename,
    required this.downloadEntity,
    required this.downloadId,
    this.resumePosition,
  });

  /// Create a copy with updated resume position
  MiniVideoPlayerState copyWithPosition(Duration position) {
    return MiniVideoPlayerState(
      player: player,
      videoController: videoController,
      filename: filename,
      downloadEntity: downloadEntity,
      downloadId: downloadId,
      resumePosition: position,
    );
  }
}
