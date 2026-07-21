import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_durations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_transitions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/services/player_safety.dart';

/// Full-window PiP view shown when system PiP is active.
///
/// The entire app window is compact and always-on-top. This widget fills
/// the window with the video and smooth hover-activated controls.
///
/// Actions:
/// - **Double-click** / **back-to-app button**: restore SSvid with in-app PiP
/// - **Fullscreen button**: restore SSvid and open fullscreen player
/// - **Close**: dispose player and restore SSvid
class SystemPipView extends StatefulWidget {
  final Player player;
  final VideoController videoController;
  final String filename;

  /// Restore to SSvid with in-app PiP overlay.
  final VoidCallback onExpand;

  /// Restore to SSvid and navigate to fullscreen video player.
  final VoidCallback? onOpenPlayer;

  /// Close PiP entirely and restore SSvid.
  final VoidCallback onClose;

  const SystemPipView({
    super.key,
    required this.player,
    required this.videoController,
    required this.filename,
    required this.onExpand,
    this.onOpenPlayer,
    required this.onClose,
  });

  @override
  State<SystemPipView> createState() => _SystemPipViewState();
}

class _SystemPipViewState extends State<SystemPipView>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  Timer? _hideTimer;

  // Entrance animation
  late final AnimationController _entranceController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      duration: AppTransitions.controls,
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: AppTransitions.curveEnter,
    );
    _entranceController.forward();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _entranceController.dispose();
    super.dispose();
  }

  void _onHoverEnter() {
    _hideTimer?.cancel();
    if (mounted) setState(() => _isHovered = true);
  }

  void _onHoverExit() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isHovered = false);
    });
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _safePlayerCall(FutureOr<void> Function() action) {
    if (!mounted) return;
    PlayerSafety.safeCall(action);
  }

  T? _safePlayerState<T>(T Function(Player player) reader) {
    try {
      return reader(widget.player);
    } catch (error, stackTrace) {
      if (PlayerSafety.isDisposedPlayerError(error)) return null;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  bool _safeCurrentPlaying() {
    return _safePlayerState((player) => player.state.playing) ?? false;
  }

  Duration _safeCurrentPosition() {
    return _safePlayerState((player) => player.state.position) ?? Duration.zero;
  }

  Duration _safeCurrentDuration() {
    return _safePlayerState((player) => player.state.duration) ?? Duration.zero;
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MouseRegion(
          onEnter: (_) => _onHoverEnter(),
          onExit: (_) => _onHoverExit(),
          child: Stack(
            children: [
              // Video fills the entire window — double-tap to return to app
              Positioned.fill(
                child: GestureDetector(
                  onDoubleTap: widget.onExpand,
                  child: DragToMoveArea(
                    child: Video(
                      controller: widget.videoController,
                      controls: NoVideoControls,
                    ),
                  ),
                ),
              ),

              // Top bar: filename + actions (smooth fade)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: _isHovered ? 1.0 : 0.0,
                  duration: AppTransitions.normal,
                  child: IgnorePointer(
                    ignoring: !_isHovered,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(
                              alpha: AppOpacity.nearOpaque,
                            ),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.drag_indicator,
                            color: Colors.white54,
                            size: 14,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              widget.filename,
                              style: AppTypography.compact.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Back to app (restore with in-app PiP)
                          _buildIconButton(
                            Icons.open_in_new,
                            'Back to App',
                            widget.onExpand,
                          ),
                          // Fullscreen player (if callback provided)
                          if (widget.onOpenPlayer != null)
                            _buildIconButton(
                              Icons.open_in_full,
                              'Open Player',
                              widget.onOpenPlayer!,
                            ),
                          // Close
                          _buildIconButton(
                            Icons.close,
                            'Close',
                            widget.onClose,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Center play/pause (smooth fade)
              Center(
                child: AnimatedOpacity(
                  opacity: _isHovered ? 1.0 : 0.0,
                  duration: AppTransitions.normal,
                  child: IgnorePointer(
                    ignoring: !_isHovered,
                    child: StreamBuilder<bool>(
                      stream: widget.player.stream.playing,
                      initialData: _safeCurrentPlaying(),
                      builder: (context, snapshot) {
                        final isPlaying = snapshot.data ?? false;
                        return GestureDetector(
                          onTap:
                              () => _safePlayerCall(widget.player.playOrPause),
                          child: AnimatedContainer(
                            duration: AppTransitions.fast,
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(
                                alpha: AppOpacity.nearOpaque,
                              ),
                              border: Border.all(
                                color: AppColors.accentHighlight.withValues(
                                  alpha: AppOpacity.secondary,
                                ),
                                width: 1.25,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.accentHighlight.withValues(
                                    alpha: AppOpacity.pressed,
                                  ),
                                  blurRadius: 24,
                                  spreadRadius: -8,
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: AppOpacity.strong,
                                  ),
                                  blurRadius: 22,
                                ),
                              ],
                            ),
                            child: Icon(
                              isPlaying ? Icons.pause : Icons.play_arrow,
                              size: 32,
                              color: Colors.white.withValues(
                                alpha: AppOpacity.nearOpaque,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              // Bottom: progress bar + time (smooth fade)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedOpacity(
                  opacity: _isHovered ? 1.0 : 0.0,
                  duration: AppTransitions.normal,
                  child: IgnorePointer(
                    ignoring: !_isHovered,
                    child: _buildProgressBar(),
                  ),
                ),
              ),

              // Resize handle (bottom-right corner)
              Positioned(
                right: 0,
                bottom: 0,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeDownRight,
                  child: GestureDetector(
                    onPanStart:
                        (_) =>
                            windowManager.startResizing(ResizeEdge.bottomRight),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: AnimatedOpacity(
                        opacity: _isHovered ? 1.0 : 0.0,
                        duration: AppTransitions.fast,
                        child: const CustomPaint(
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
    );
  }

  Widget _buildIconButton(
    IconData icon,
    String tooltip,
    VoidCallback onPressed,
  ) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xxs),
      child: Tooltip(
        message: tooltip,
        waitDuration: AppDurations.tooltipWaitDuration,
        child: Material(
          color: Colors.white.withValues(alpha: AppOpacity.divider),
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: Colors.white.withValues(alpha: AppOpacity.subtle),
                ),
              ),
              child: Icon(
                icon,
                color: Colors.white.withValues(alpha: AppOpacity.nearOpaque),
                size: 15,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    return StreamBuilder<Duration>(
      stream: widget.player.stream.position,
      initialData: _safeCurrentPosition(),
      builder: (context, posSnap) {
        return StreamBuilder<Duration>(
          stream: widget.player.stream.duration,
          initialData: _safeCurrentDuration(),
          builder: (context, durSnap) {
            final pos = posSnap.data ?? Duration.zero;
            final dur = durSnap.data ?? Duration.zero;
            final progress =
                dur.inMilliseconds > 0
                    ? pos.inMilliseconds / dur.inMilliseconds
                    : 0.0;

            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: AppOpacity.secondary),
                    Colors.transparent,
                  ],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.smMd,
                AppSpacing.sm,
                AppSpacing.xs,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Seekable progress bar
                  GestureDetector(
                    onTapDown: (details) {
                      final box = context.findRenderObject() as RenderBox;
                      final ratio = details.localPosition.dx / box.size.width;
                      final seekTo = Duration(
                        milliseconds: (dur.inMilliseconds * ratio).toInt(),
                      );
                      _safePlayerCall(() => widget.player.seek(seekTo));
                    },
                    child: SizedBox(
                      height: 12,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          backgroundColor: Colors.white.withValues(
                            alpha: AppOpacity.subtle,
                          ),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.accentHighlight,
                          ),
                          minHeight: 4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  // Time display
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(pos),
                        style: AppTypography.mini.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      Text(
                        _formatDuration(dur),
                        style: AppTypography.mini.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Paints a small diagonal resize indicator at the bottom-right.
class _ResizeHandlePainter extends CustomPainter {
  const _ResizeHandlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.white.withValues(alpha: AppOpacity.overlay)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;
    for (int i = 1; i <= 2; i++) {
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
