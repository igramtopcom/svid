import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import '../../../../core/core.dart';
import '../../domain/services/player_safety.dart';
import '../providers/player_providers.dart';
import '../screens/audio_player_screen.dart';

/// Mini Player - Compact floating audio player overlay
/// Appears at bottom-right corner for background audio playback
class MiniPlayer extends ConsumerStatefulWidget {
  final Player player;
  final String filename;
  final String? thumbnail;
  final VoidCallback onClose;

  const MiniPlayer({
    super.key,
    required this.player,
    required this.filename,
    this.thumbnail,
    required this.onClose,
  });

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer>
    with SingleTickerProviderStateMixin {
  Offset _position = const Offset(20, 20); // Bottom-right with margin
  bool _isDragging = false;
  bool _isHovered = false;

  // Entrance animation
  late final AnimationController _entranceController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    // Setup entrance animation (slide-up + fade from bottom-right)
    _entranceController = AnimationController(
      duration: AppTransitions.slow,
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: AppTransitions.curveEnter,
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: AppTransitions.curveEnter,
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: AppTransitions.curveEnter,
      ),
    );

    // Start entrance animation
    _entranceController.forward();

    // Restore saved position after first frame (needs MediaQuery context)
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSavedPosition());
  }

  void _loadSavedPosition() {
    if (!mounted) return;
    final service = ref.read(miniPlayerPositionServiceProvider);
    final saved = service.loadPosition();
    if (saved == null) return;
    final size = MediaQuery.of(context).size;
    setState(() {
      _position = service.clampPosition(saved, size);
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

  void _handleExpand(BuildContext context) async {
    final miniPlayerState = ref.read(miniPlayerStateProvider);
    if (miniPlayerState == null) return;
    final downloadEntity = miniPlayerState.downloadEntity;

    // Capture current position before expanding
    final currentPosition = _safeCurrentPosition(miniPlayerState.player);
    final wasPlaying = _safeCurrentPlaying();
    appLogger.info(
      'Expanding mini player: Capturing position at ${currentPosition.inSeconds}s',
    );

    // Unregister from mini player ID (don't dispose - we're transferring ownership)
    playerManager.unregisterPlayer(
      'mini_audio_${miniPlayerState.downloadId}',
      dispose: false,
    );

    // Clear mini player state (don't call onClose which would dispose)
    ref.read(miniPlayerStateProvider.notifier).state = null;

    // Navigate to fullscreen audio player with smooth expand animation
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) => AudioPlayerScreen(
              download: downloadEntity,
              existingPlayer: miniPlayerState.player,
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
              alignment: Alignment.bottomRight,
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
    final panelWidth = (viewport.width - 40).clamp(280.0, 400.0);
    final panelHeight = panelWidth < 360 ? 220.0 : 240.0;
    final displayPosition = Offset(
      _position.dx.clamp(
        20.0,
        (viewport.width - panelWidth - 20).clamp(20.0, viewport.width),
      ),
      _position.dy.clamp(
        20.0,
        (viewport.height - panelHeight - 20).clamp(20.0, viewport.height),
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
      child: SlideTransition(
        position: _slideAnimation,
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
                setState(() {
                  // Update position (invert delta for bottom-right anchoring)
                  _position = Offset(
                    (_position.dx - details.delta.dx).clamp(
                      20,
                      viewport.width - panelWidth - 20,
                    ),
                    (_position.dy - details.delta.dy).clamp(
                      20,
                      viewport.height - panelHeight - 20,
                    ),
                  );
                });
              },
              onPanEnd: (details) {
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
                  width: panelWidth,
                  height: panelHeight,
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
                              _isHovered
                                  ? AppOpacity.subtle
                                  : AppOpacity.divider,
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
                        // Background with album art or gradient
                        Positioned.fill(
                          child:
                              widget.thumbnail != null
                                  ? AppCachedImage(
                                    imageUrl: widget.thumbnail,
                                    width: panelWidth,
                                    height: panelHeight,
                                    fit: BoxFit.cover,
                                    borderRadius: BorderRadius.zero,
                                    errorWidget: _buildDefaultBackground(),
                                  )
                                  : _buildDefaultBackground(),
                        ),

                        // Dark overlay for better text contrast
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withValues(
                              alpha: AppOpacity.scrim,
                            ),
                          ),
                        ),

                        // Top bar with drag handle
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: AnimatedOpacity(
                            opacity: _isHovered || _isDragging ? 1.0 : 0.92,
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
                                  _miniIconButton(
                                    onPressed: () => _handleExpand(context),
                                    icon: Icons.open_in_full_rounded,
                                    tooltip: AppLocalizations.playerExpand,
                                  ),

                                  // Close button
                                  _miniIconButton(
                                    onPressed: widget.onClose,
                                    icon: Icons.close_rounded,
                                    tooltip: AppLocalizations.playerClose,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Playback controls at bottom
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: GestureDetector(
                            // Prevent parent drag gesture from interfering with controls
                            onPanStart: (_) {},
                            onPanUpdate: (_) {},
                            onPanEnd: (_) {},
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    Colors.black.withValues(
                                      alpha: AppOpacity.nearOpaque,
                                    ),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                              padding: const EdgeInsets.all(AppSpacing.smMd),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Progress bar
                                  StreamBuilder<Duration>(
                                    stream: widget.player.stream.position,
                                    builder: (context, posSnapshot) {
                                      final position =
                                          posSnapshot.data ?? Duration.zero;
                                      return StreamBuilder<Duration>(
                                        stream: widget.player.stream.duration,
                                        builder: (context, durSnapshot) {
                                          final duration =
                                              durSnapshot.data ?? Duration.zero;
                                          final progress =
                                              duration.inMilliseconds > 0
                                                  ? position.inMilliseconds /
                                                      duration.inMilliseconds
                                                  : 0.0;

                                          return Column(
                                            children: [
                                              SliderTheme(
                                                data: SliderThemeData(
                                                  trackHeight: 3,
                                                  thumbShape:
                                                      const RoundSliderThumbShape(
                                                        enabledThumbRadius: 6,
                                                      ),
                                                  overlayShape:
                                                      const RoundSliderOverlayShape(
                                                        overlayRadius: 12,
                                                      ),
                                                  activeTrackColor:
                                                      AppColors.accentHighlight,
                                                  inactiveTrackColor: AppColors
                                                      .darkMuted
                                                      .withValues(
                                                        alpha: AppOpacity.scrim,
                                                      ),
                                                  thumbColor:
                                                      AppColors.accentHighlight,
                                                ),
                                                child: Slider(
                                                  value: progress.clamp(
                                                    0.0,
                                                    1.0,
                                                  ),
                                                  onChanged: (value) {
                                                    final newPosition = Duration(
                                                      milliseconds:
                                                          (value *
                                                                  duration
                                                                      .inMilliseconds)
                                                              .round(),
                                                    );
                                                    _safePlayerCall(
                                                      () => widget.player.seek(
                                                        newPosition,
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                              Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: AppSpacing.sm,
                                                    ),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Text(
                                                      Formatters.formatDuration(
                                                        position,
                                                      ),
                                                      style: AppTypography
                                                          .compact
                                                          .copyWith(
                                                            color:
                                                                AppColors
                                                                    .darkLightText,
                                                          ),
                                                    ),
                                                    Text(
                                                      Formatters.formatDuration(
                                                        duration,
                                                      ),
                                                      style: AppTypography
                                                          .compact
                                                          .copyWith(
                                                            color:
                                                                AppColors
                                                                    .darkMetaText,
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      );
                                    },
                                  ),

                                  const SizedBox(height: AppSpacing.sm),

                                  // Playback controls
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      // Rewind 10s
                                      IconButton(
                                        onPressed: () {
                                          _safePlayerCall(() async {
                                            final pos =
                                                await widget
                                                    .player
                                                    .stream
                                                    .position
                                                    .first;
                                            if (!mounted) return;
                                            final newPos =
                                                pos -
                                                const Duration(seconds: 10);
                                            _safePlayerCall(
                                              () => widget.player.seek(
                                                newPos > Duration.zero
                                                    ? newPos
                                                    : Duration.zero,
                                              ),
                                            );
                                          });
                                        },
                                        icon: Icon(
                                          Icons.replay_10,
                                          color: AppColors.darkMetaText,
                                        ),
                                        iconSize: 20,
                                        tooltip:
                                            AppLocalizations.playerRewind10s,
                                      ),

                                      const SizedBox(width: AppSpacing.smMd),

                                      // Play/Pause
                                      StreamBuilder<bool>(
                                        stream: widget.player.stream.playing,
                                        initialData: _safeCurrentPlaying(),
                                        builder: (context, snapshot) {
                                          final isPlaying =
                                              snapshot.data ??
                                              _safeCurrentPlaying();
                                          return GestureDetector(
                                            onTap:
                                                () => _safePlayerCall(
                                                  widget.player.playOrPause,
                                                ),
                                            child: Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: AppColors.accentHighlight
                                                    .withValues(
                                                      alpha:
                                                          AppOpacity.nearOpaque,
                                                    ),
                                                border: Border.all(
                                                  color: AppColors.darkLightText
                                                      .withValues(
                                                        alpha:
                                                            AppOpacity
                                                                .secondary,
                                                      ),
                                                  width: 1.5,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(
                                                          alpha:
                                                              AppOpacity
                                                                  .overlay,
                                                        ),
                                                    blurRadius: 18,
                                                  ),
                                                ],
                                              ),
                                              child: Icon(
                                                isPlaying
                                                    ? Icons.pause
                                                    : Icons.play_arrow,
                                                size: 24,
                                                color: AppColors.darkLightText,
                                              ),
                                            ),
                                          );
                                        },
                                      ),

                                      const SizedBox(width: AppSpacing.smMd),

                                      // Forward 10s
                                      IconButton(
                                        onPressed: () {
                                          _safePlayerCall(() async {
                                            final pos =
                                                await widget
                                                    .player
                                                    .stream
                                                    .position
                                                    .first;
                                            if (!mounted) return;
                                            final newPos =
                                                pos +
                                                const Duration(seconds: 10);
                                            _safePlayerCall(
                                              () => widget.player.seek(newPos),
                                            );
                                          });
                                        },
                                        icon: Icon(
                                          Icons.forward_10,
                                          color: AppColors.darkMetaText,
                                        ),
                                        iconSize: 20,
                                        tooltip:
                                            AppLocalizations.playerForward10s,
                                      ),
                                    ],
                                  ),
                                ],
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
      ),
    );
  }

  Widget _buildDefaultBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surface2(context), AppColors.surface3(context)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note,
          size: 80,
          color: AppColors.accentHighlight.withValues(
            alpha: AppOpacity.overlay,
          ),
        ),
      ),
    );
  }

  Widget _miniIconButton({
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
