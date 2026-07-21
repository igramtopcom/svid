import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../../core/core.dart';
import '../../domain/services/player_safety.dart';
import '../providers/player_providers.dart';
import '../screens/video_player_screen.dart';

/// Mini Video Player - Compact floating video player overlay (PiP)
/// Appears at bottom-right corner for picture-in-picture video playback
class MiniVideoPlayer extends ConsumerStatefulWidget {
  final Player player;
  final VideoController videoController;
  final String filename;
  final VoidCallback onClose;

  const MiniVideoPlayer({
    super.key,
    required this.player,
    required this.videoController,
    required this.filename,
    required this.onClose,
  });

  @override
  ConsumerState<MiniVideoPlayer> createState() => _MiniVideoPlayerState();
}

/// Min/max PiP dimensions (16:9 aspect ratio)
const double _kPipMinWidth = 240.0;
const double _kPipMaxWidth = 640.0;
const double _kPipAspectRatio = 16 / 9;

class _MiniVideoPlayerState extends ConsumerState<MiniVideoPlayer>
    with SingleTickerProviderStateMixin {
  Offset _position = const Offset(20, 20); // Bottom-right with margin
  double _width = 400;
  double _height = 240;
  bool _isDragging = false;
  bool _isResizing = false;
  bool _isHovered = false;

  // Entrance animation
  late final AnimationController _entranceController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Setup entrance animation (scale + fade from bottom-right)
    _entranceController = AnimationController(
      duration: AppTransitions.controls,
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: AppTransitions.curveEnter,
      ),
    );

    // Start entrance animation
    _entranceController.forward();

    // Restore saved position and size after first frame (needs MediaQuery context)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSavedPosition();
      _loadSavedSize();
    });
  }

  void _loadSavedPosition() {
    if (!mounted) return;
    final service = ref.read(miniPlayerPositionServiceProvider);
    final saved = service.loadPosition();
    if (saved == null) return;
    final size = MediaQuery.of(context).size;
    setState(() {
      _position = service.clampPosition(
        saved,
        size,
        width: _width,
        height: _height,
      );
    });
  }

  void _loadSavedSize() {
    if (!mounted) return;
    final service = ref.read(miniPlayerPositionServiceProvider);
    final saved = service.loadSize();
    if (saved == null) return;
    setState(() {
      _width = saved.width.clamp(_kPipMinWidth, _kPipMaxWidth);
      _height = _width / _kPipAspectRatio;
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  void _safePlayerCall(FutureOr<void> Function() action) {
    if (!mounted) return;
    PlayerSafety.safeCall(action);
  }

  T? _safePlayerState<T>(Player player, T Function(Player player) reader) {
    try {
      return reader(player);
    } catch (error, stackTrace) {
      if (PlayerSafety.isDisposedPlayerError(error)) return null;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  bool _safeCurrentPlaying() {
    return _safePlayerState(widget.player, (player) => player.state.playing) ??
        false;
  }

  Duration _safeCurrentPosition([Player? player]) {
    return _safePlayerState(
          player ?? widget.player,
          (player) => player.state.position,
        ) ??
        Duration.zero;
  }

  Duration _safeCurrentDuration() {
    return _safePlayerState(widget.player, (player) => player.state.duration) ??
        Duration.zero;
  }

  void _handleExpand(BuildContext context) async {
    final miniVideoPlayerState = ref.read(miniVideoPlayerStateProvider);
    if (miniVideoPlayerState == null) return;
    final downloadEntity = miniVideoPlayerState.downloadEntity;

    // Capture current position before expanding
    final currentPosition = _safeCurrentPosition(miniVideoPlayerState.player);
    final wasPlaying = _safeCurrentPlaying();
    appLogger.info(
      'Expanding PiP: Capturing position at ${currentPosition.inSeconds}s',
    );

    // Unregister from PiP ID (don't dispose - we're transferring ownership)
    playerManager.unregisterPlayer(
      'pip_video_${miniVideoPlayerState.downloadId}',
      dispose: false,
    );

    // Clear PiP state (don't call onClose which would dispose)
    ref.read(miniVideoPlayerStateProvider.notifier).state = null;

    // Navigate to fullscreen video player with smooth expand animation
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) => VideoPlayerScreen(
              download: downloadEntity,
              existingPlayer: miniVideoPlayerState.player,
              existingVideoController: miniVideoPlayerState.videoController,
              resumePosition: currentPosition,
              autoPlay: wasPlaying,
            ),
        transitionDuration: AppTransitions.controls,
        reverseTransitionDuration: AppTransitions.slow,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Smooth expand animation: fade + scale from bottom-right
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: AppTransitions.curveEnter,
            reverseCurve: AppTransitions.curveExit,
          );

          return FadeTransition(
            opacity: curvedAnimation,
            child: ScaleTransition(
              scale: Tween<double>(
                begin: 0.85,
                end: 1.0,
              ).animate(curvedAnimation),
              alignment: Alignment.bottomRight, // Scale from PiP position
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final availableWidth = viewport.width - 40;
    final maxVisibleWidth =
        availableWidth < _kPipMinWidth
            ? _kPipMinWidth
            : availableWidth.clamp(_kPipMinWidth, _kPipMaxWidth);
    final effectiveWidth = _width.clamp(_kPipMinWidth, maxVisibleWidth);
    final effectiveHeight = effectiveWidth / _kPipAspectRatio;
    final displayPosition = Offset(
      _position.dx.clamp(
        20.0,
        (viewport.width - effectiveWidth - 20).clamp(20.0, viewport.width),
      ),
      _position.dy.clamp(
        20.0,
        (viewport.height - effectiveHeight - 20).clamp(20.0, viewport.height),
      ),
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(AppRadius.card);
    final borderColor =
        _isHovered
            ? AppColors.accentHighlight.withValues(alpha: AppOpacity.nearOpaque)
            : AppColors.darkLightText.withValues(alpha: AppOpacity.subtle);
    final panelBg = isDark ? AppColors.homeDarkCardBg : AppColors.lightElevated;

    return Positioned(
      right: displayPosition.dx,
      bottom: displayPosition.dy,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          alignment: Alignment.bottomRight,
          child: GestureDetector(
            onPanStart: (details) {
              setState(() => _isDragging = true);
            },
            onPanUpdate: (details) {
              if (_isResizing) return; // Let resize handle consume its own drag
              setState(() {
                // Update position (invert delta for bottom-right anchoring)
                final wSize = MediaQuery.of(context).size;
                _position = Offset(
                  (_position.dx - details.delta.dx).clamp(
                    20.0,
                    wSize.width - effectiveWidth - 20,
                  ),
                  (_position.dy - details.delta.dy).clamp(
                    20.0,
                    wSize.height - effectiveHeight - 20,
                  ),
                );
              });
            },
            onPanEnd: (details) {
              if (_isResizing) return;
              setState(() => _isDragging = false);
              ref
                  .read(miniPlayerPositionServiceProvider)
                  .savePosition(_position);
            },
            child: MouseRegion(
              onEnter: (_) {
                if (mounted) setState(() => _isHovered = true);
              },
              onExit: (_) {
                if (mounted) setState(() => _isHovered = false);
              },
              child: AnimatedContainer(
                duration: AppTransitions.normal,
                width: effectiveWidth,
                height: effectiveHeight,
                decoration: BoxDecoration(
                  color: panelBg,
                  borderRadius: radius,
                  border: Border.all(
                    color: borderColor,
                    width: _isHovered ? 1.5 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.34 : 0.16,
                      ),
                      blurRadius: 24,
                      offset: const Offset(0, 14),
                    ),
                    BoxShadow(
                      color: AppColors.accentHighlight.withValues(
                        alpha:
                            _isHovered ? AppOpacity.subtle : AppOpacity.divider,
                      ),
                      blurRadius: 26,
                      spreadRadius: -10,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: radius,
                  child: Stack(
                    children: [
                      // Video player
                      Positioned.fill(
                        child: Video(
                          controller: widget.videoController,
                          controls: NoVideoControls,
                        ),
                      ),

                      // Top bar with drag handle
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: AnimatedOpacity(
                          opacity: _isHovered || _isDragging ? 1.0 : 0.0,
                          duration: AppTransitions.normal,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(
                                    alpha: AppOpacity.strong,
                                  ),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                            child: Row(
                              children: [
                                // Drag handle
                                Container(
                                  margin: const EdgeInsets.all(AppSpacing.xs),
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(
                                      alpha: AppOpacity.quarter,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.card,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.drag_indicator_rounded,
                                    color: AppColors.darkMetaText,
                                    size: 16,
                                  ),
                                ),

                                // Filename
                                Expanded(
                                  child: Text(
                                    widget.filename,
                                    style: AppTypography.metadata.copyWith(
                                      color: AppColors.darkLightText,
                                      fontWeight: AppTypography.semiBold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),

                                // Expand button
                                _pipIconButton(
                                  onPressed: () => _handleExpand(context),
                                  icon: Icons.open_in_full_rounded,
                                  tooltip: AppLocalizations.playerExpand,
                                ),

                                // Close button
                                _pipIconButton(
                                  onPressed: widget.onClose,
                                  icon: Icons.close_rounded,
                                  tooltip: AppLocalizations.playerClose,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Center play/pause button — always mounted; opacity-toggled.
                      // Conditional mounting on _isHovered can trigger mouse_tracker
                      // assertion failures during pointer dispatch.
                      Center(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 120),
                          opacity: _isHovered ? 1.0 : 0.0,
                          child: IgnorePointer(
                            ignoring: !_isHovered,
                            child: StreamBuilder<bool>(
                              stream: widget.player.stream.playing,
                              initialData: _safeCurrentPlaying(),
                              builder: (context, snapshot) {
                                final isPlaying =
                                    snapshot.data ?? _safeCurrentPlaying();
                                return GestureDetector(
                                  onTap:
                                      () => _safePlayerCall(
                                        widget.player.playOrPause,
                                      ),
                                  child: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.accentHighlight
                                          .withValues(
                                            alpha: AppOpacity.nearOpaque,
                                          ),
                                      border: Border.all(
                                        color: AppColors.darkLightText
                                            .withValues(
                                              alpha: AppOpacity.medium,
                                            ),
                                        width: 1.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: AppOpacity.overlay,
                                          ),
                                          blurRadius: 18,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      isPlaying
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                      size: 28,
                                      color: AppColors.darkLightText,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),

                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: StreamBuilder<Duration>(
                            stream: widget.player.stream.position,
                            initialData: _safeCurrentPosition(),
                            builder: (context, posSnapshot) {
                              return StreamBuilder<Duration>(
                                stream: widget.player.stream.duration,
                                initialData: _safeCurrentDuration(),
                                builder: (context, durSnapshot) {
                                  final position =
                                      posSnapshot.data ?? Duration.zero;
                                  final duration =
                                      durSnapshot.data ?? Duration.zero;
                                  final value =
                                      duration.inMilliseconds > 0
                                          ? (position.inMilliseconds /
                                                  duration.inMilliseconds)
                                              .clamp(0.0, 1.0)
                                          : 0.0;
                                  return LinearProgressIndicator(
                                    value: value,
                                    minHeight: 4,
                                    backgroundColor: Colors.white.withValues(
                                      alpha: AppOpacity.subtle,
                                    ),
                                    valueColor: AlwaysStoppedAnimation(
                                      AppColors.accentHighlight,
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),

                      // Resize handle — bottom-right corner
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (_) => setState(() => _isResizing = true),
                          onPanUpdate: (details) {
                            setState(() {
                              // Dragging right/down increases size; left/up decreases
                              final newWidth = (_width + details.delta.dx)
                                  .clamp(_kPipMinWidth, _kPipMaxWidth);
                              _width = newWidth;
                              _height = _width / _kPipAspectRatio;
                            });
                          },
                          onPanEnd: (_) {
                            setState(() => _isResizing = false);
                            ref
                                .read(miniPlayerPositionServiceProvider)
                                .saveSize(_width, _height);
                          },
                          child: AnimatedOpacity(
                            opacity: _isHovered || _isResizing ? 1.0 : 0.0,
                            duration: AppTransitions.normal,
                            child: const MouseRegion(
                              cursor: SystemMouseCursors.resizeDownRight,
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CustomPaint(
                                  painter: _ResizeHandlePainter(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pipIconButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String tooltip,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: Tooltip(
        message: tooltip,
        waitDuration: AppDurations.tooltipWaitDuration,
        child: Material(
          color: Colors.black.withValues(alpha: AppOpacity.quarter),
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: AppColors.darkLightText.withValues(
                    alpha: AppOpacity.subtle,
                  ),
                ),
              ),
              child: Icon(icon, color: AppColors.darkLightText, size: 17),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a small diagonal resize indicator (two lines) at the bottom-right.
class _ResizeHandlePainter extends CustomPainter {
  const _ResizeHandlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = AppColors.darkMuted.withValues(alpha: AppOpacity.strong)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;
    // Three diagonal lines typical of a resize grip
    for (int i = 1; i <= 3; i++) {
      final offset = i * 4.0;
      canvas.drawLine(
        Offset(size.width - offset, size.height),
        Offset(size.width, size.height - offset),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
