import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as p;
import '../../../../core/core.dart';
import '../../../downloads/domain/entities/video_info.dart';
import '../providers/player_providers.dart';
import '../../../downloads/domain/entities/download_entity.dart';
import '../providers/trim_providers.dart';
import '../screens/video_player_screen.dart' show ExternalSubtitle;
import 'trim_export_dialog.dart';
import 'trim_range_painter.dart';
import '../../domain/services/thumbnail_preview_service.dart';
import '../../domain/services/player_speed_service.dart';
import '../../domain/services/player_chapter_service.dart';
import '../../domain/services/player_safety.dart';
import 'video_controls_painters.dart';
import 'subtitle_controls.dart';
import 'media_info_dialog.dart';
import '../../../premium/domain/entities/premium_feature.dart';
import '../../../premium/presentation/providers/premium_providers.dart';
import '../../../premium/presentation/widgets/upgrade_prompt_dialog.dart';

/// Custom video controls with timeline, volume, playback speed, and fullscreen
class VideoControls extends ConsumerStatefulWidget {
  final Player player;
  final VoidCallback onClose;
  final VoidCallback onOpenPiP;
  final List<ExternalSubtitle> externalSubtitles;
  final List<ChapterInfo> chapters;
  final DownloadEntity? download;
  final VoidCallback? onLoadSubtitleFile;
  final VoidCallback? onSearchSubtitlesOnline;
  final VoidCallback? onSkipNext;
  final VoidCallback? onSkipPrevious;
  final VoidCallback? onScreenshot;
  final VoidCallback? onToggleCinemaMode;
  final VoidCallback? onToggleEdit;
  final bool isEditMode;

  const VideoControls({
    super.key,
    required this.player,
    required this.onClose,
    required this.onOpenPiP,
    this.externalSubtitles = const [],
    this.chapters = const [],
    this.download,
    this.onLoadSubtitleFile,
    this.onSearchSubtitlesOnline,
    this.onSkipNext,
    this.onSkipPrevious,
    this.onScreenshot,
    this.onToggleCinemaMode,
    this.onToggleEdit,
    this.isEditMode = false,
  });

  @override
  ConsumerState<VideoControls> createState() => _VideoControlsState();
}

class _VideoControlsState extends ConsumerState<VideoControls> {
  Timer? _hideTimer;
  Timer? _mouseHideTimer;
  bool _isDragging = false;
  bool _isCursorVisible = true;

  // Gesture state
  bool _isLongPressing = false;
  double? _hoverX; // Mouse hover X position on timeline (null = not hovering)
  double _previousSpeed = 1.0;
  String? _seekFeedback; // "◀◀ 10s" or "10s ▶▶"
  Timer? _seekFeedbackTimer;

  // Thumbnail seek preview
  ThumbnailPreviewService? _thumbnailService;
  Uint8List? _hoverThumbnail;
  Timer? _thumbnailDebounceTimer;
  bool _thumbnailEnabled = false;

  // Stream subscriptions for proper cleanup
  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<Duration> _durationSubscription;
  late final StreamSubscription<bool> _bufferingSubscription;

  @override
  void initState() {
    super.initState();
    _startHideTimer();
    _setupStreamListeners();
    _initThumbnailService();
  }

  String? get _downloadFilePath {
    final d = widget.download;
    if (d == null || d.savePath.isEmpty || d.filename.isEmpty) return null;
    return p.join(d.savePath, d.filename);
  }

  void _initThumbnailService() {
    final path = _downloadFilePath;
    if (path == null) return;
    if (ThumbnailPreviewService.isAudioOnlyByExtension(path)) return;

    final tracks = _readPlayerState((player) => player.state.tracks.video);
    if (tracks == null) return;
    if (tracks.length == 1 && tracks.first.id == 'no') {
      return; // audio-only MediaKit signal
    }

    _thumbnailEnabled = true;
    _thumbnailService = ThumbnailPreviewService(
      ref.read(ffmpegDatasourceProvider),
    );
  }

  /// Setup stream listeners for player state
  void _setupStreamListeners() {
    // Position updates (throttled for performance)
    _positionSubscription = widget.player.stream.position.listen((pos) {
      if (mounted && !_isDragging) {
        ref.read(playerPositionProvider.notifier).state = pos;
        // A-B Repeat: seek back to point A when reaching point B
        final pointA = ref.read(abRepeatPointAProvider);
        final pointB = ref.read(abRepeatPointBProvider);
        if (pointA != null && pointB != null && pos >= pointB) {
          _safePlayerCall(() => widget.player.seek(pointA));
        }
      }
    });

    // Duration updates (infrequent)
    _durationSubscription = widget.player.stream.duration.listen((dur) {
      if (mounted) {
        ref.read(playerDurationProvider.notifier).state = dur;
        // Trigger thumbnail pre-warm once we know the duration
        if (dur > Duration.zero && _thumbnailEnabled) {
          final path = _downloadFilePath;
          if (path != null) {
            _thumbnailService?.prewarm(path, dur);
          }
        }
      }
    });

    // Buffering updates (infrequent)
    _bufferingSubscription = widget.player.stream.buffering.listen((buffering) {
      if (mounted) {
        ref.read(isBufferingProvider.notifier).state = buffering;
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _mouseHideTimer?.cancel();
    _seekFeedbackTimer?.cancel();
    _thumbnailDebounceTimer?.cancel();
    _thumbnailService?.dispose();

    // Cancel all stream subscriptions to prevent memory leaks
    _positionSubscription.cancel();
    _durationSubscription.cancel();
    _bufferingSubscription.cancel();

    super.dispose();
  }

  void _startHideTimer() {
    if (!mounted) return;
    _hideTimer?.cancel();
    // Don't auto-hide controls when trim mode is active
    if (ref.read(isTrimModeProvider)) return;
    // Cinema mode: faster auto-hide (1.5s) for immersive experience
    final isCinema = ref.read(cinemaModeProvider);
    final delay =
        isCinema
            ? const Duration(milliseconds: 1500)
            : const Duration(seconds: 3);
    _hideTimer = Timer(delay, () {
      if (!_isDragging && mounted) {
        ref.read(showControlsProvider.notifier).state = false;
      }
    });
  }

  void _showControls() {
    if (!mounted) return;
    ref.read(showControlsProvider.notifier).state = true;
    _startHideTimer();
    _handleMouseMove();
  }

  void _handleMouseMove() {
    if (!mounted) return;
    // Show cursor if hidden
    if (!_isCursorVisible) {
      setState(() => _isCursorVisible = true);
    }

    // Auto-hide cursor in fullscreen after 3s
    final isFullscreen = ref.read(isFullscreenProvider);
    if (isFullscreen) {
      _mouseHideTimer?.cancel();
      _mouseHideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && ref.read(isFullscreenProvider)) {
          setState(() => _isCursorVisible = false);
        }
      });
    }
  }

  /// Defensive wrapper for media_kit Player calls.
  ///
  /// `[Player] has been disposed` assertion was the #2 production crash
  /// group on v1.6.2/v1.6.3 (68 crashes / 8 devices, audit 2026-04-27).
  /// Stack always rooted in a tap or double-tap gesture: the gesture
  /// arena fires the recognizer's `_reset` timer AFTER the parent route
  /// has popped and disposed the Player. By the time `_togglePlayPause`
  /// runs, `widget.player` is already disposed.
  ///
  /// The widget's `mounted` check alone is not sufficient because the
  /// Player can be disposed externally (auto-dispose timer in
  /// PlayerManager, parent screen disposing it on route change) while
  /// this widget is still mounted. We catch the assertion here so a
  /// stale gesture doesn't tear down the app.
  void _safePlayerCall(FutureOr<void> Function() action) {
    if (!mounted) return;
    PlayerSafety.safeCall(action);
  }

  T? _readPlayerState<T>(T Function(Player player) reader) {
    try {
      return reader(widget.player);
    } catch (error, stackTrace) {
      if (PlayerSafety.isDisposedPlayerError(error)) return null;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  bool get _isPlayerPlaying =>
      _readPlayerState((player) => player.state.playing) ?? false;

  void _togglePlayPause() {
    _safePlayerCall(() => widget.player.playOrPause());
    _showControls();
  }

  void _seek(Duration position) {
    _safePlayerCall(() => widget.player.seek(position));
    _showControls();
  }

  void _seekForward() {
    final currentPosition = ref.read(playerPositionProvider);
    final newPosition = currentPosition + const Duration(seconds: 10);
    _seek(newPosition);
  }

  void _seekBackward() {
    final currentPosition = ref.read(playerPositionProvider);
    final newPosition = currentPosition - const Duration(seconds: 10);
    _seek(newPosition > Duration.zero ? newPosition : Duration.zero);
  }

  void _changeVolume(double volume) {
    _safePlayerCall(
      () => widget.player.setVolume(volume * 100), // media_kit uses 0-100
    );
    ref.read(playerVolumeProvider.notifier).state = volume;
    _showControls();
  }

  void _changeSpeed(double speed) {
    _safePlayerCall(() => widget.player.setRate(speed));
    ref.read(playbackSpeedProvider.notifier).state = speed;
    _showControls();
  }

  /// Shows a bottom-sheet speed preset picker (0.5x, 1x, 1.25x, 1.5x, 2x).
  void _showSpeedSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: AppOpacity.overlay),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final currentSpeed = ref.read(playbackSpeedProvider);
            return SafeArea(
              child: Container(
                margin: const EdgeInsets.all(AppSpacing.md),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.mdLg,
                  AppSpacing.smMd,
                  AppSpacing.mdLg,
                  AppSpacing.mdLg,
                ),
                decoration: BoxDecoration(
                  color: AppColors.homeDarkCardBg.withValues(
                    alpha: AppOpacity.nearOpaque,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: AppColors.darkLightText.withValues(
                      alpha: AppOpacity.subtle,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: AppOpacity.overlay),
                      blurRadius: 28,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.darkLightText.withValues(
                            alpha: AppOpacity.subtle,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const Gap.md(),
                    Row(
                      children: [
                        Icon(
                          Icons.speed_rounded,
                          color: AppColors.accentHighlight,
                          size: 20,
                        ),
                        const Gap.sm(),
                        Text(
                          AppLocalizations.playerPlaybackSpeed,
                          style: AppTypography.appBarTitle.copyWith(
                            color: AppColors.darkLightText,
                            fontWeight: AppTypography.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.smMd),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children:
                          PlayerSpeedService.presets.map((preset) {
                            final isSelected =
                                (currentSpeed - preset).abs() < 0.01;
                            return FilterChip(
                              label: Text(
                                PlayerSpeedService.formatLabel(preset),
                              ),
                              selected: isSelected,
                              showCheckmark: false,
                              selectedColor: AppColors.accentHighlight
                                  .withValues(alpha: AppOpacity.pressed),
                              backgroundColor: AppColors.darkLightText
                                  .withValues(alpha: AppOpacity.divider),
                              side: BorderSide(
                                color:
                                    isSelected
                                        ? AppColors.accentHighlight
                                        : AppColors.darkLightText.withValues(
                                          alpha: AppOpacity.subtle,
                                        ),
                              ),
                              labelStyle: AppTypography.metadata.copyWith(
                                color:
                                    isSelected
                                        ? AppColors.darkLightText
                                        : AppColors.darkMetaText,
                                fontWeight:
                                    isSelected
                                        ? AppTypography.bold
                                        : AppTypography.medium,
                              ),
                              onSelected: (_) {
                                _changeSpeed(preset);
                                Navigator.of(ctx).pop();
                              },
                            );
                          }).toList(),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _toggleFullscreen() async {
    if (!mounted) return;
    final isFullscreen = ref.read(isFullscreenProvider);
    ref.read(isFullscreenProvider.notifier).state = !isFullscreen;

    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      // Native window fullscreen for desktop
      await windowManager.setFullScreen(!isFullscreen);
    } else {
      // Fallback to system UI mode for mobile
      if (!isFullscreen) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    }
    if (!mounted) return;
    _showControls();
  }

  void _openPiP() {
    widget.onOpenPiP();
  }

  // === GESTURE HANDLERS ===

  /// Toggle controls visibility on tap
  void _onTap() {
    final showControls = ref.read(showControlsProvider);
    ref.read(showControlsProvider.notifier).state = !showControls;
    if (!showControls) {
      _startHideTimer();
    }
  }

  /// Double-tap to seek: left half = -10s, right half = +10s
  void _onDoubleTapDown(TapDownDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    final tapX = details.localPosition.dx;
    final isLeftSide = tapX < screenWidth / 2;

    final currentPosition = ref.read(playerPositionProvider);
    Duration newPosition;
    String feedback;

    if (isLeftSide) {
      newPosition = currentPosition - const Duration(seconds: 10);
      if (newPosition < Duration.zero) newPosition = Duration.zero;
      feedback = '◀◀ 10s';
    } else {
      newPosition = currentPosition + const Duration(seconds: 10);
      feedback = '10s ▶▶';
    }

    _safePlayerCall(() => widget.player.seek(newPosition));
    _showSeekFeedback(feedback);
    _showControls();
  }

  /// Show seek feedback overlay
  void _showSeekFeedback(String text) {
    setState(() => _seekFeedback = text);
    _seekFeedbackTimer?.cancel();
    _seekFeedbackTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _seekFeedback = null);
    });
  }

  /// Long press start: speed boost to 2x
  void _onLongPressStart(LongPressStartDetails details) {
    _previousSpeed = ref.read(playbackSpeedProvider);
    _safePlayerCall(() => widget.player.setRate(2.0));
    ref.read(playbackSpeedProvider.notifier).state = 2.0;
    setState(() => _isLongPressing = true);
    _showControls();
  }

  /// Long press end: restore previous speed
  void _onLongPressEnd(LongPressEndDetails details) {
    _safePlayerCall(() => widget.player.setRate(_previousSpeed));
    ref.read(playbackSpeedProvider.notifier).state = _previousSpeed;
    setState(() => _isLongPressing = false);
  }

  // === TRIM MODE ===

  void _toggleTrimMode() {
    final isTrimMode = ref.read(isTrimModeProvider);
    // Allow exiting trim mode without premium check
    if (!isTrimMode && !ref.read(isPremiumProvider)) {
      UpgradePromptDialog.showAndNavigate(
        context,
        ref,
        feature: PremiumFeature.advancedPlayer,
      );
      return;
    }
    if (isTrimMode) {
      // Exit trim mode — clear points, resume auto-hide
      ref.read(isTrimModeProvider.notifier).state = false;
      ref.read(trimStartProvider.notifier).state = null;
      ref.read(trimEndProvider.notifier).state = null;
      _startHideTimer();
    } else {
      // Enter trim mode — pause playback, keep controls visible
      ref.read(isTrimModeProvider.notifier).state = true;
      _safePlayerCall(widget.player.pause);
      _hideTimer?.cancel();
      ref.read(showControlsProvider.notifier).state = true;
    }
  }

  // === CHAPTER NAVIGATION ===

  /// Find the current chapter based on playback position
  ChapterInfo? _getCurrentChapter(Duration position) {
    final posSeconds = position.inMilliseconds / 1000.0;
    return PlayerChapterService.getCurrentChapter(widget.chapters, posSeconds);
  }

  /// Seek to the next chapter
  void seekToNextChapter() {
    final posSeconds = ref.read(playerPositionProvider).inMilliseconds / 1000.0;
    final start = PlayerChapterService.getNextChapterStart(
      widget.chapters,
      posSeconds,
    );
    if (start != null) _seek(Duration(milliseconds: (start * 1000).round()));
  }

  /// Seek to the previous chapter
  void seekToPreviousChapter() {
    final posSeconds = ref.read(playerPositionProvider).inMilliseconds / 1000.0;
    final start = PlayerChapterService.getPreviousChapterStart(
      widget.chapters,
      posSeconds,
    );
    if (start != null) {
      _seek(Duration(milliseconds: (start * 1000).round()));
    } else {
      _seek(Duration.zero);
    }
  }

  // === A-B REPEAT ===

  /// Toggle A-B repeat: no points -> set A, A only -> set B, both -> clear
  void toggleAbRepeatPoint() {
    // Premium gate: block setting new points (clearing always allowed)
    final pointA = ref.read(abRepeatPointAProvider);
    final pointB = ref.read(abRepeatPointBProvider);
    final isClearAction = pointA != null && pointB != null;
    if (!ref.read(isPremiumProvider) && !isClearAction) {
      UpgradePromptDialog.showAndNavigate(
        context,
        ref,
        feature: PremiumFeature.advancedPlayer,
      );
      return;
    }
    final position = ref.read(playerPositionProvider);

    if (pointA == null) {
      // Set point A
      ref.read(abRepeatPointAProvider.notifier).state = position;
      _showSeekFeedback('A: ${Formatters.formatDuration(position)}');
    } else if (pointB == null) {
      // Set point B (must be after A)
      if (position <= pointA) {
        _showSeekFeedback('B must be after A');
        return;
      }
      ref.read(abRepeatPointBProvider.notifier).state = position;
      _showSeekFeedback('B: ${Formatters.formatDuration(position)} (Loop)');
      // Seek to A to start the loop
      _safePlayerCall(() => widget.player.seek(pointA));
    } else {
      // Clear both points
      clearAbRepeat();
    }
    _showControls();
  }

  /// Clear A-B repeat points
  void clearAbRepeat() {
    ref.read(abRepeatPointAProvider.notifier).state = null;
    ref.read(abRepeatPointBProvider.notifier).state = null;
    _showSeekFeedback('A-B Cleared');
    _showControls();
  }

  @override
  Widget build(BuildContext context) {
    final showControls = ref.watch(showControlsProvider);
    final position = ref.watch(playerPositionProvider);
    final duration = ref.watch(playerDurationProvider);
    final volume = ref.watch(playerVolumeProvider);
    final playbackSpeed = ref.watch(playbackSpeedProvider);
    final isFullscreen = ref.watch(isFullscreenProvider);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _onTap,
      onDoubleTapDown: _onDoubleTapDown,
      onLongPressStart: _onLongPressStart,
      onLongPressEnd: _onLongPressEnd,
      child: MouseRegion(
        onHover: (_) => _showControls(),
        cursor:
            _isCursorVisible
                ? SystemMouseCursors.basic
                : SystemMouseCursors.none,
        child: Stack(
          children: [
            // Controls overlay (fades + slides in/out)
            AnimatedSlide(
              offset: showControls ? Offset.zero : const Offset(0, 0.02),
              duration: AppTransitions.controls,
              curve:
                  showControls
                      ? AppTransitions.curveEnter
                      : AppTransitions.curveExit,
              child: AnimatedOpacity(
                opacity: showControls ? 1.0 : 0.0,
                duration: AppTransitions.controls,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: AppOpacity.strong),
                        Colors.transparent,
                        Colors.black.withValues(alpha: AppOpacity.strong),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Column(
                      children: [
                        // Top bar
                        _buildTopBar(isFullscreen),

                        const Spacer(),

                        // Center play/pause button (only when controls visible)
                        if (showControls)
                          Center(
                            child: StreamBuilder<bool>(
                              stream: widget.player.stream.playing,
                              initialData: _isPlayerPlaying,
                              builder: (context, snapshot) {
                                final isPlaying =
                                    snapshot.data ?? _isPlayerPlaying;
                                return GestureDetector(
                                  onTap: _togglePlayPause,
                                  child: AnimatedContainer(
                                    duration: AppTransitions.fast,
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.black.withValues(
                                        alpha: AppOpacity.overlay,
                                      ),
                                      border: Border.all(
                                        color: AppColors.darkLightText
                                            .withValues(
                                              alpha: AppOpacity.secondary,
                                            ),
                                        width: 1.25,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: AppOpacity.strong,
                                          ),
                                          blurRadius: 22,
                                        ),
                                        BoxShadow(
                                          color: AppColors.accentHighlight
                                              .withValues(
                                                alpha: AppOpacity.subtle,
                                              ),
                                          blurRadius: 30,
                                          spreadRadius: -8,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      isPlaying
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                      size: 36,
                                      color: AppColors.darkLightText,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),

                        const Spacer(),

                        // Bottom controls
                        _buildBottomControls(
                          position,
                          duration,
                          volume,
                          playbackSpeed,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Seek feedback overlay (always visible when triggered)
            if (_seekFeedback != null)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.smMd,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: AppOpacity.strong),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Text(
                    _seekFeedback!,
                    style: AppTypography.appBarTitle.copyWith(
                      color: AppColors.darkLightText,
                      fontSize: 24,
                      fontWeight: AppTypography.bold,
                    ),
                  ),
                ),
              ),

            // Chapter panel (right-side overlay)
            _buildChapterPanel(position),

            // Long press speed boost indicator
            if (_isLongPressing)
              Positioned(
                top: 80,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(
                      alpha: AppOpacity.nearOpaque,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.fast_forward,
                        color: AppColors.darkLightText,
                        size: 20,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        '2x',
                        style: AppTypography.appBarTitle.copyWith(
                          color: AppColors.darkLightText,
                          fontWeight: AppTypography.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showSubtitleDelayDialog() {
    showDialog(
      context: context,
      builder: (ctx) => SubtitleDelayDialog(ref: ref),
    );
  }

  void _showSubtitleAppearanceDialog() {
    showDialog(
      context: context,
      builder: (ctx) => SubtitleAppearanceDialog(ref: ref),
    );
  }

  void _showMediaInfoDialog() {
    showDialog(
      context: context,
      builder:
          (ctx) =>
              MediaInfoDialog(player: widget.player, download: widget.download),
    );
  }

  void _fetchThumbnailAt(double hoverDx, Duration duration, double trackWidth) {
    if (!_thumbnailEnabled || _thumbnailService == null) return;
    final path = _downloadFilePath;
    if (path == null) return;
    if (duration <= Duration.zero) return;

    const sliderPadding = 24.0;
    final effectiveWidth = trackWidth - (sliderPadding * 2);
    final fraction = ((hoverDx - sliderPadding) / effectiveWidth).clamp(
      0.0,
      1.0,
    );
    final pos = Duration(
      milliseconds: (fraction * duration.inMilliseconds).round(),
    );

    _thumbnailService!.getFrameAt(path, pos).then((bytes) {
      if (mounted && _hoverX != null) {
        setState(() => _hoverThumbnail = bytes);
      }
    });
  }

  Widget _buildHoverTooltip(Duration duration, double trackWidth) {
    if (_hoverX == null || duration <= Duration.zero) {
      return const SizedBox.shrink();
    }

    final hasChapters = widget.chapters.isNotEmpty;
    final hasThumbnail = _thumbnailEnabled && _hoverThumbnail != null;

    // Require at least chapters or thumbnail to show anything
    if (!hasChapters && !hasThumbnail) return const SizedBox.shrink();

    // Convert hover position to time (account for 24px slider padding)
    const sliderPadding = 24.0;
    final effectiveWidth = trackWidth - (sliderPadding * 2);
    final hoverFraction = ((_hoverX! - sliderPadding) / effectiveWidth).clamp(
      0.0,
      1.0,
    );
    final hoverTimeMs = hoverFraction * duration.inMilliseconds;
    final hoverTimeSec = hoverTimeMs / 1000.0;
    final hoverDuration = Duration(milliseconds: hoverTimeMs.round());
    final timeStr = Formatters.formatDuration(hoverDuration);

    // Find chapter for hover position
    ChapterInfo? hoverChapter;
    if (hasChapters) {
      for (int i = widget.chapters.length - 1; i >= 0; i--) {
        if (hoverTimeSec >= widget.chapters[i].startTime) {
          hoverChapter = widget.chapters[i];
          break;
        }
      }
    }

    return IgnorePointer(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 200),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.darkBg,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: AppColors.darkMuted.withValues(alpha: AppOpacity.subtle),
            width: 0.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Thumbnail image (160x90, aspect-ratio preserved by FFmpeg scale=160:-1)
            if (hasThumbnail)
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Image.memory(
                  _hoverThumbnail!,
                  width: 160,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
            if (hasThumbnail && hoverChapter != null)
              const SizedBox(height: AppSpacing.xs),
            // Chapter title
            if (hoverChapter != null)
              Text(
                hoverChapter.title,
                style: AppTypography.statusBadge.copyWith(
                  color: AppColors.darkLightText,
                  fontWeight: AppTypography.medium,
                  letterSpacing: 0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: AppSpacing.xxs),
            // Time text always shown
            Text(
              timeStr,
              style: AppTypography.compact.copyWith(
                color: AppColors.darkMetaText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChapterPanel(Duration position) {
    final isOpen = ref.watch(chaptersPanelOpenProvider);
    if (!isOpen || widget.chapters.isEmpty) return const SizedBox.shrink();

    final currentChapter = _getCurrentChapter(position);

    final ghostColor = AppColors.darkMuted;
    final metaColor = AppColors.darkMetaText;
    final warmWhite = AppColors.darkLightText;
    final panelBg = AppColors.darkBg;
    final activeBg = AppColors.darkBase;

    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      width: 280,
      child: GestureDetector(
        onTap: () {}, // Absorb taps so panel doesn't close controls
        child: Container(
          decoration: BoxDecoration(
            color: panelBg,
            border: Border(
              left: BorderSide(
                color: ghostColor.withValues(alpha: AppOpacity.subtle),
                width: 0.5,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Text(
                      AppLocalizations.playerChapters,
                      style: AppTypography.compact.copyWith(
                        color: AppColors.accentHighlight,
                        fontWeight: AppTypography.bold,
                        letterSpacing: 0,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed:
                          () =>
                              ref
                                  .read(chaptersPanelOpenProvider.notifier)
                                  .state = false,
                      icon: Icon(Icons.close, color: ghostColor, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              Container(
                height: 0.5,
                color: ghostColor.withValues(alpha: AppOpacity.pressed),
              ),
              // Chapter list
              Expanded(
                child: ListView.builder(
                  itemCount: widget.chapters.length,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  itemBuilder: (context, index) {
                    final chapter = widget.chapters[index];
                    final isCurrent = currentChapter == chapter;
                    return InkWell(
                      onTap: () {
                        _seek(
                          Duration(
                            milliseconds: (chapter.startTime * 1000).round(),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.smMd,
                        ),
                        decoration: BoxDecoration(
                          color: isCurrent ? activeBg : null,
                          border: Border(
                            left: BorderSide(
                              color:
                                  isCurrent
                                      ? AppColors.accentHighlight
                                      : Colors.transparent,
                              width: 3,
                            ),
                            bottom: BorderSide(
                              color: ghostColor.withValues(
                                alpha: AppOpacity.divider,
                              ),
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            // Timestamp
                            SizedBox(
                              width: 52,
                              child: Text(
                                chapter.formattedStartTime,
                                style: AppTypography.statusBadge.copyWith(
                                  color:
                                      isCurrent
                                          ? AppColors.accentHighlight
                                          : metaColor,
                                  fontFamily: 'monospace',
                                  fontWeight:
                                      isCurrent
                                          ? AppTypography.bold
                                          : FontWeight.normal,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            // Title
                            Expanded(
                              child: Text(
                                chapter.title,
                                style: AppTypography.platformName.copyWith(
                                  color: isCurrent ? warmWhite : metaColor,
                                  fontWeight:
                                      isCurrent
                                          ? AppTypography.semiBold
                                          : FontWeight.normal,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isCurrent)
                              Icon(
                                Icons.play_arrow,
                                color: AppColors.accentHighlight,
                                size: 16,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(bool isFullscreen) {
    final actionButtons = <Widget>[
      // Chapters button (only shown when chapters exist)
      if (widget.chapters.isNotEmpty)
        _playerIconButton(
          onPressed: () {
            final isOpen = ref.read(chaptersPanelOpenProvider);
            ref.read(chaptersPanelOpenProvider.notifier).state = !isOpen;
          },
          icon:
              ref.watch(chaptersPanelOpenProvider)
                  ? Icons.bookmark
                  : Icons.bookmark_outline,
          active: ref.watch(chaptersPanelOpenProvider),
          tooltip: AppLocalizations.playerChapters,
        ),

      // A-B Repeat button
      _buildAbRepeatButton(),

      // Trim button
      _playerIconButton(
        onPressed: _toggleTrimMode,
        icon: Icons.content_cut,
        active: ref.watch(isTrimModeProvider),
        tooltip:
            ref.watch(isTrimModeProvider)
                ? AppLocalizations.playerExitTrimMode
                : AppLocalizations.playerTrimVideo,
      ),

      // Screenshot button
      if (widget.onScreenshot != null)
        _playerIconButton(
          onPressed: widget.onScreenshot,
          icon: Icons.camera_alt_outlined,
          tooltip: AppLocalizations.playerControlsScreenshotTooltip,
        ),

      // Edit mode button
      if (widget.onToggleEdit != null)
        _playerIconButton(
          onPressed: widget.onToggleEdit,
          icon: Icons.edit_rounded,
          active: widget.isEditMode,
          tooltip: AppLocalizations.playerControlsEditTooltip,
        ),

      // Cinema Mode button
      if (widget.onToggleCinemaMode != null)
        _playerIconButton(
          onPressed: () {
            widget.onToggleCinemaMode?.call();
          },
          icon: Icons.theaters,
          active: ref.watch(cinemaModeProvider),
          tooltip: AppLocalizations.playerControlsCinemaModeTooltip,
        ),

      // PiP button
      _playerIconButton(
        onPressed: _openPiP,
        icon: Icons.picture_in_picture_alt,
        tooltip: AppLocalizations.playerPictureInPicture,
      ),

      // Media info button
      _playerIconButton(
        onPressed: _showMediaInfoDialog,
        icon: Icons.info_outline,
        tooltip: AppLocalizations.mediaInfoTitle,
      ),

      // Settings button with selected indicators
      PopupMenuButton<String>(
        icon: Icon(Icons.settings, color: AppColors.darkMetaText),
        tooltip: AppLocalizations.playerSettings,
        onSelected: (value) {
          if (value.startsWith('speed_')) {
            final speed = double.parse(value.substring(6));
            _changeSpeed(speed);
          } else if (value.startsWith('aspect_')) {
            final mode = value.substring(7);
            AspectRatioMode newMode;
            switch (mode) {
              case 'fit':
                newMode = AspectRatioMode.fit;
                break;
              case 'fill':
                newMode = AspectRatioMode.fill;
                break;
              case 'stretch':
                newMode = AspectRatioMode.stretch;
                break;
              case 'original':
                newMode = AspectRatioMode.original;
                break;
              default:
                return;
            }
            ref.read(aspectRatioModeProvider.notifier).state = newMode;
          }
        },
        itemBuilder: (context) {
          final currentSpeed = ref.read(playbackSpeedProvider);
          final currentAspect = ref.read(aspectRatioModeProvider);
          return [
            PopupMenuItem(
              enabled: false,
              child: Text(
                AppLocalizations.playerPlaybackSpeed,
                style: AppTypography.metadata.copyWith(
                  fontWeight: AppTypography.bold,
                ),
              ),
            ),
            CheckedPopupMenuItem(
              value: 'speed_0.25',
              checked: currentSpeed == 0.25,
              child: const Text('0.25x'),
            ),
            CheckedPopupMenuItem(
              value: 'speed_0.5',
              checked: currentSpeed == 0.5,
              child: const Text('0.5x'),
            ),
            CheckedPopupMenuItem(
              value: 'speed_0.75',
              checked: currentSpeed == 0.75,
              child: const Text('0.75x'),
            ),
            CheckedPopupMenuItem(
              value: 'speed_1.0',
              checked: currentSpeed == 1.0,
              child: Text(AppLocalizations.playerSpeedNormal),
            ),
            CheckedPopupMenuItem(
              value: 'speed_1.25',
              checked: currentSpeed == 1.25,
              child: const Text('1.25x'),
            ),
            CheckedPopupMenuItem(
              value: 'speed_1.5',
              checked: currentSpeed == 1.5,
              child: const Text('1.5x'),
            ),
            CheckedPopupMenuItem(
              value: 'speed_2.0',
              checked: currentSpeed == 2.0,
              child: const Text('2.0x'),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              enabled: false,
              child: Text(
                AppLocalizations.playerAspectRatio,
                style: AppTypography.metadata.copyWith(
                  fontWeight: AppTypography.bold,
                ),
              ),
            ),
            CheckedPopupMenuItem(
              value: 'aspect_fit',
              checked: currentAspect == AspectRatioMode.fit,
              child: Text(AppLocalizations.playerAspectFit),
            ),
            CheckedPopupMenuItem(
              value: 'aspect_fill',
              checked: currentAspect == AspectRatioMode.fill,
              child: Text(AppLocalizations.playerAspectFill),
            ),
            CheckedPopupMenuItem(
              value: 'aspect_stretch',
              checked: currentAspect == AspectRatioMode.stretch,
              child: Text(AppLocalizations.playerAspectStretch),
            ),
            CheckedPopupMenuItem(
              value: 'aspect_original',
              checked: currentAspect == AspectRatioMode.original,
              child: Text(AppLocalizations.playerAspectOriginal),
            ),
          ];
        },
      ),
    ];

    return Padding(
      padding: AppSpacing.edgeInsets.md,
      child: Row(
        children: [
          // Back button
          _playerIconButton(
            onPressed: () {
              if (isFullscreen) {
                _toggleFullscreen();
              }
              widget.onClose();
            },
            icon: Icons.arrow_back,
            tooltip: AppLocalizations.playerBack,
          ),

          const Gap.sm(),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(children: actionButtons),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(
    Duration position,
    Duration duration,
    double volume,
    double playbackSpeed,
  ) {
    final currentChapter = _getCurrentChapter(position);
    final isTrimMode = ref.watch(isTrimModeProvider);
    final trimStart = ref.watch(trimStartProvider);
    final trimEnd = ref.watch(trimEndProvider);
    final canExport = ref.watch(canExportTrimProvider);
    final trimDuration = ref.watch(trimDurationProvider);

    return Padding(
      padding: AppSpacing.edgeInsets.md,
      child: Column(
        children: [
          // Current chapter name with smooth transition
          if (currentChapter != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  currentChapter.title,
                  key: ValueKey(currentChapter.title),
                  style: AppTypography.compact.copyWith(
                    color: AppColors.darkMetaText,
                    fontStyle: FontStyle.italic,
                    letterSpacing: 0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

          // Timeline slider with segmented chapter bar + bloom effect
          Container(
            decoration: BoxDecoration(
              // Timeline Bloom — crimson glow beneath the progress bar
              boxShadow: [
                BoxShadow(
                  color: AppColors.accentHighlight.withValues(
                    alpha: AppOpacity.subtle,
                  ),
                  blurRadius: 16,
                  spreadRadius: -2,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Text(
                  Formatters.formatDuration(position),
                  style: AppTypography.metadata.copyWith(
                    color: AppColors.darkLightText,
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final hasChapters =
                          widget.chapters.isNotEmpty &&
                          duration.inMilliseconds > 0;
                      return Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          // Main slider (transparent track when chapters overlay is shown)
                          SliderTheme(
                            data: SliderThemeData(
                              trackHeight: hasChapters ? 6 : 3,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 12,
                              ),
                              activeTrackColor:
                                  hasChapters
                                      ? Colors.transparent
                                      : AppColors.accentHighlight,
                              inactiveTrackColor:
                                  hasChapters
                                      ? Colors.transparent
                                      : AppColors.darkMetaText.withValues(
                                        alpha: AppOpacity.scrim,
                                      ),
                              thumbColor: AppColors.accentHighlight,
                            ),
                            child: MouseRegion(
                              onHover: (event) {
                                final dx = event.localPosition.dx;
                                setState(() => _hoverX = dx);
                                if (_thumbnailEnabled) {
                                  _thumbnailDebounceTimer?.cancel();
                                  _thumbnailDebounceTimer = Timer(
                                    const Duration(milliseconds: 100),
                                    () => _fetchThumbnailAt(
                                      dx,
                                      duration,
                                      constraints.maxWidth,
                                    ),
                                  );
                                }
                              },
                              onExit: (_) {
                                setState(() {
                                  _hoverX = null;
                                  _hoverThumbnail = null;
                                });
                                _thumbnailDebounceTimer?.cancel();
                              },
                              child: Slider(
                                value:
                                    duration.inMilliseconds > 0
                                        ? (position.inMilliseconds /
                                                duration.inMilliseconds)
                                            .clamp(0.0, 1.0)
                                        : 0.0,
                                onChanged: (value) {
                                  setState(() => _isDragging = true);
                                  final newPosition = Duration(
                                    milliseconds:
                                        (value * duration.inMilliseconds)
                                            .round(),
                                  );
                                  ref
                                      .read(playerPositionProvider.notifier)
                                      .state = newPosition;
                                },
                                onChangeEnd: (value) {
                                  final newPosition = Duration(
                                    milliseconds:
                                        (value * duration.inMilliseconds)
                                            .round(),
                                  );
                                  _seek(newPosition);
                                  setState(() => _isDragging = false);
                                },
                              ),
                            ),
                          ),
                          // Segmented chapter progress bar
                          if (hasChapters)
                            IgnorePointer(
                              child: Padding(
                                // Slider has ~24px padding on each side for the thumb
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.lg,
                                ),
                                child: SizedBox(
                                  width: constraints.maxWidth,
                                  height: 6,
                                  child: CustomPaint(
                                    painter: SegmentedChapterPainter(
                                      chapters: widget.chapters,
                                      totalDurationMs:
                                          duration.inMilliseconds.toDouble(),
                                      currentPositionMs:
                                          position.inMilliseconds.toDouble(),
                                      activeColor: AppColors.accentHighlight,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          // Trim range overlay
                          if (isTrimMode &&
                              trimStart != null &&
                              trimEnd != null &&
                              duration.inMilliseconds > 0)
                            IgnorePointer(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.lg,
                                ),
                                child: SizedBox(
                                  width: constraints.maxWidth,
                                  height: hasChapters ? 6 : 3,
                                  child: CustomPaint(
                                    painter: TrimRangePainter(
                                      startPosition: (trimStart.inMilliseconds /
                                              duration.inMilliseconds)
                                          .clamp(0.0, 1.0),
                                      endPosition: (trimEnd.inMilliseconds /
                                              duration.inMilliseconds)
                                          .clamp(0.0, 1.0),
                                      trackHeight: hasChapters ? 6.0 : 3.0,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          // A-B Repeat range overlay
                          if (ref.watch(abRepeatPointAProvider) != null &&
                              duration.inMilliseconds > 0)
                            IgnorePointer(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.lg,
                                ),
                                child: SizedBox(
                                  width: constraints.maxWidth,
                                  height: hasChapters ? 6 : 3,
                                  child: CustomPaint(
                                    painter: AbRepeatRangePainter(
                                      pointA:
                                          ref.watch(abRepeatPointAProvider)!,
                                      pointB: ref.watch(abRepeatPointBProvider),
                                      totalDurationMs:
                                          duration.inMilliseconds.toDouble(),
                                      trackHeight: hasChapters ? 6.0 : 3.0,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          // Hover tooltip (chapter text + optional thumbnail)
                          if (_hoverX != null)
                            Positioned(
                              left: (_hoverX! - 80).clamp(
                                0.0,
                                constraints.maxWidth - 168,
                              ),
                              top: -100,
                              child: _buildHoverTooltip(
                                duration,
                                constraints.maxWidth,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                Text(
                  Formatters.formatDuration(duration),
                  style: AppTypography.metadata.copyWith(
                    color: AppColors.darkLightText,
                  ),
                ),
              ],
            ),
          ), // Close timeline bloom Container

          const Gap.sm(),

          // Trim toolbar (visible only in trim mode)
          if (isTrimMode)
            _buildTrimToolbar(
              position,
              trimStart,
              trimEnd,
              trimDuration,
              canExport,
            ),

          // Control buttons
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;
              final leadingControls = <Widget>[
                // Skip previous (queue)
                if (widget.onSkipPrevious != null)
                  _playerIconButton(
                    onPressed: widget.onSkipPrevious,
                    icon: Icons.skip_previous,
                    tooltip: AppLocalizations.playbackQueueSkipPrevious,
                  ),

                // Play/Pause
                StreamBuilder<bool>(
                  stream: widget.player.stream.playing,
                  initialData: _isPlayerPlaying,
                  builder: (context, snapshot) {
                    final isPlaying = snapshot.data ?? _isPlayerPlaying;
                    return _playerIconButton(
                      onPressed: _togglePlayPause,
                      icon: isPlaying ? Icons.pause : Icons.play_arrow,
                      active: true,
                      tooltip:
                          isPlaying
                              ? AppLocalizations.playerPause
                              : AppLocalizations.playerPlay,
                    );
                  },
                ),

                // Skip next (queue)
                if (widget.onSkipNext != null)
                  _playerIconButton(
                    onPressed: widget.onSkipNext,
                    icon: Icons.skip_next,
                    tooltip: AppLocalizations.playbackQueueSkipNext,
                  ),

                // Seek backward
                _playerIconButton(
                  onPressed: _seekBackward,
                  icon: Icons.replay_10,
                  tooltip: AppLocalizations.playerRewind10s,
                ),

                // Seek forward
                _playerIconButton(
                  onPressed: _seekForward,
                  icon: Icons.forward_10,
                  tooltip: AppLocalizations.playerForward10s,
                ),

                // Volume
                _playerIconButton(
                  onPressed: () {
                    // Toggle mute
                    if (volume > 0) {
                      _changeVolume(0);
                    } else {
                      _changeVolume(1);
                    }
                  },
                  icon:
                      volume == 0
                          ? Icons.volume_off
                          : volume < 0.5
                          ? Icons.volume_down
                          : Icons.volume_up,
                  tooltip: AppLocalizations.playerVolume,
                ),

                // Volume slider
                SizedBox(
                  width: 100,
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 4,
                      ),
                      activeTrackColor: AppColors.accentHighlight,
                      inactiveTrackColor: AppColors.darkMetaText.withValues(
                        alpha: AppOpacity.scrim,
                      ),
                      thumbColor: AppColors.accentHighlight,
                    ),
                    child: Slider(value: volume, onChanged: _changeVolume),
                  ),
                ),

                // Subtitle track selector
                buildSubtitleButton(
                  player: widget.player,
                  ref: ref,
                  context: context,
                  externalSubtitles: widget.externalSubtitles,
                  onLoadSubtitleFile: widget.onLoadSubtitleFile,
                  onSearchSubtitlesOnline: widget.onSearchSubtitlesOnline,
                  onShowDelayDialog: _showSubtitleDelayDialog,
                  onShowAppearanceDialog: _showSubtitleAppearanceDialog,
                ),
              ];

              final trailingControls = <Widget>[
                // Playback speed badge — angular bordered capsule
                GestureDetector(
                  onTap: () => _showSpeedSheet(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: AppOpacity.quarter),
                      border: Border.all(
                        color: AppColors.darkMuted.withValues(
                          alpha: AppOpacity.secondary,
                        ),
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    child: Text(
                      PlayerSpeedService.formatLabel(playbackSpeed),
                      style: AppTypography.compact.copyWith(
                        color: AppColors.darkLightText,
                        fontWeight: AppTypography.bold,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),

                const Gap.sm(),

                // Fullscreen
                _playerIconButton(
                  onPressed: _toggleFullscreen,
                  icon:
                      ref.watch(isFullscreenProvider)
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                  tooltip:
                      ref.watch(isFullscreenProvider)
                          ? AppLocalizations.playerExitFullscreen
                          : AppLocalizations.playerFullscreen,
                ),
              ];

              final controls = <Widget>[
                ...leadingControls,
                if (compact) const SizedBox(width: AppSpacing.lg),
                if (!compact) const Spacer(),
                ...trailingControls,
              ];

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.smMd,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: AppOpacity.overlay),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: AppColors.darkLightText.withValues(
                      alpha: AppOpacity.subtle,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: AppOpacity.strong),
                      blurRadius: 22,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child:
                    compact
                        ? SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(children: controls),
                        )
                        : Row(children: controls),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _playerIconButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String tooltip,
    bool active = false,
  }) {
    final fg = active ? AppColors.darkLightText : AppColors.darkMetaText;
    final bg =
        active
            ? AppColors.accentHighlight.withValues(alpha: AppOpacity.pressed)
            : Colors.black.withValues(alpha: AppOpacity.quarter);
    final border =
        active
            ? AppColors.accentHighlight.withValues(alpha: AppOpacity.medium)
            : AppColors.darkLightText.withValues(alpha: AppOpacity.subtle);

    return Tooltip(
      message: tooltip,
      waitDuration: AppDurations.tooltipWaitDuration,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: border),
              ),
              child: Icon(icon, color: fg, size: 20),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrimToolbar(
    Duration position,
    Duration? trimStart,
    Duration? trimEnd,
    Duration? trimDuration,
    bool canExport,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          // In Point button
          _buildTrimPointButton(
            label: 'IN',
            time: trimStart,
            onPressed:
                () => ref.read(trimStartProvider.notifier).state = position,
            color: AppColors.accentHighlight,
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(Icons.arrow_forward, size: 14, color: AppColors.darkMetaText),
          const SizedBox(width: AppSpacing.sm),
          // Out Point button
          _buildTrimPointButton(
            label: 'OUT',
            time: trimEnd,
            onPressed:
                () => ref.read(trimEndProvider.notifier).state = position,
            color: AppColors.brand,
          ),
          const SizedBox(width: AppSpacing.smMd),
          // Duration chip
          if (trimDuration != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: AppColors.accentHighlight.withValues(
                  alpha: AppOpacity.subtle,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                Formatters.formatDuration(trimDuration),
                style: AppTypography.metadata.copyWith(
                  color: AppColors.accentHighlight,
                  fontWeight: AppTypography.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          const Spacer(),
          // Preview from in point
          if (trimStart != null)
            IconButton(
              onPressed: () {
                _safePlayerCall(() => widget.player.seek(trimStart));
                _safePlayerCall(widget.player.play);
              },
              icon: Icon(
                Icons.play_circle_outline,
                color: AppColors.darkLightText,
                size: 20,
              ),
              tooltip: AppLocalizations.playerTrimPreview,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          // Reset trim points
          if (trimStart != null || trimEnd != null)
            IconButton(
              onPressed: () {
                ref.read(trimStartProvider.notifier).state = null;
                ref.read(trimEndProvider.notifier).state = null;
              },
              icon: Icon(
                Icons.restart_alt,
                color: AppColors.darkMetaText,
                size: 20,
              ),
              tooltip: AppLocalizations.playerTrimReset,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          // Export button
          if (canExport && widget.download != null)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: FilledButton.icon(
                onPressed:
                    () => TrimExportDialog.show(
                      context,
                      video: widget.download!,
                      startTime: trimStart!,
                      endTime: trimEnd!,
                    ),
                icon: const Icon(Icons.content_cut, size: 16),
                label: Text(AppLocalizations.playerTrimExport),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  foregroundColor: AppColors.darkLightText,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.smMd,
                    vertical: AppSpacing.xs,
                  ),
                  textStyle: AppTypography.metadata,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAbRepeatButton() {
    final pointA = ref.watch(abRepeatPointAProvider);
    final pointB = ref.watch(abRepeatPointBProvider);
    final isActive = pointA != null && pointB != null;
    final hasPointA = pointA != null && pointB == null;

    String tooltip;
    Color iconColor;
    IconData icon;

    if (isActive) {
      tooltip = AppLocalizations.playerAbClear;
      iconColor = AppColors.accentHighlight;
      icon = Icons.repeat_one;
    } else if (hasPointA) {
      tooltip = AppLocalizations.playerAbSetPointB;
      iconColor = AppColors.accentHighlight.withValues(
        alpha: AppOpacity.strong,
      );
      icon = Icons.repeat_one;
    } else {
      tooltip = AppLocalizations.playerAbSetPointA;
      iconColor = AppColors.darkMuted;
      icon = Icons.repeat;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: toggleAbRepeatPoint,
          icon: Icon(icon, color: iconColor),
          tooltip: tooltip,
        ),
        // Badge showing current state
        if (hasPointA)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: AppColors.accentHighlight,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                'A',
                style: AppTypography.mini.copyWith(
                  color: AppColors.darkLightText,
                  fontSize: 9,
                  fontWeight: AppTypography.bold,
                ),
              ),
            ),
          ),
        if (isActive)
          Positioned(
            right: 2,
            top: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: AppColors.accentHighlight,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                'A-B',
                style: AppTypography.mini.copyWith(
                  color: AppColors.darkLightText,
                  fontSize: 9,
                  fontWeight: AppTypography.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTrimPointButton({
    required String label,
    required Duration? time,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(2),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: AppOpacity.pressed),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: color.withValues(alpha: AppOpacity.medium)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTypography.mini.copyWith(
                color: color,
                fontWeight: AppTypography.bold,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              time != null ? Formatters.formatDuration(time) : '--:--',
              style: AppTypography.metadata.copyWith(
                color: AppColors.darkLightText,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
