import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import '../../../../core/core.dart';
import '../../../downloads/domain/entities/download_entity.dart';
import '../../domain/entities/player_handoff_result.dart';
import '../../domain/services/player_safety.dart';
import '../../domain/services/playback_queue_service.dart';
import '../providers/player_providers.dart';
import '../providers/playback_queue_providers.dart';
import 'video_player_screen.dart';

/// Audio Player Screen.
/// V2 production surface: clear playback hierarchy without decorative glow.
/// Uses media_kit for audio playback.
class AudioPlayerScreen extends ConsumerStatefulWidget {
  final DownloadEntity download;

  /// Optional: Pass existing player when expanding from mini player
  final Player? existingPlayer;
  final Duration? resumePosition;
  final bool autoPlay;

  const AudioPlayerScreen({
    super.key,
    required this.download,
    this.existingPlayer,
    this.resumePosition,
    this.autoPlay = true,
  });

  @override
  ConsumerState<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends ConsumerState<AudioPlayerScreen>
    with SingleTickerProviderStateMixin {
  late final Player _player;
  bool _isOpeningMiniPlayer = false;
  bool _disposed = false;
  final FocusNode _focusNode = FocusNode();

  // Fade-out animation for smooth mini player transition
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  Timer? _watchProgressTimer; // Auto-save playback position every 5s

  // Stream subscriptions for proper cleanup
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription<bool>? _completedSubscription;

  @override
  void initState() {
    super.initState();

    // Setup fade-out animation for mini player transition
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: 1.0, // Start fully visible
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    // Check if we're resuming from mini player with existing player
    if (widget.existingPlayer != null) {
      _player = widget.existingPlayer!;

      // Register player under fullscreen ID
      playerManager.registerPlayer('audio_${widget.download.id}', _player);
      _startPlaybackLifecycleTracking();

      appLogger.info(
        'AudioPlayerScreen: Using existing player from mini player',
      );

      // Existing-player paths are surface handoffs (mini/right-panel →
      // fullscreen). Keep provider state and play/pause intent continuous.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _disposed) return;
        _syncPlaybackProvidersFromState();
        unawaited(_prepareExistingPlayerHandoff());
      });
    } else {
      // Initialize new player
      _player = Player();

      // Load audio file
      _loadAudio();
    }

    // Setup stream listeners
    _setupStreamListeners();

    // Request focus for keyboard shortcuts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  void _safePlayer(FutureOr<void> Function(Player player) action) {
    if (_disposed) return;
    PlayerSafety.safeCall(() {
      if (_disposed) return Future<void>.value();
      return action(_player);
    });
  }

  T? _readPlayerState<T>(T Function(Player player) reader) {
    if (_disposed) return null;
    try {
      return reader(_player);
    } catch (error, stackTrace) {
      if (PlayerSafety.isDisposedPlayerError(error)) return null;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  bool get _isPlayerPlaying =>
      _readPlayerState((player) => player.state.playing) ?? false;

  Duration get _playerPosition =>
      _readPlayerState((player) => player.state.position) ?? Duration.zero;

  Duration get _playerDuration =>
      _readPlayerState((player) => player.state.duration) ?? Duration.zero;

  void _syncPlaybackProvidersFromState() {
    if (!mounted || _disposed) return;
    final position = _playerPosition;
    final duration = _playerDuration;
    ref.read(playerPositionProvider.notifier).state = position;
    if (duration > Duration.zero) {
      ref.read(playerDurationProvider.notifier).state = duration;
    }
  }

  Future<void> _prepareExistingPlayerHandoff() async {
    try {
      await _seekToResumePosition(widget.resumePosition, source: 'handoff');
      if (!mounted || _disposed) return;

      if (widget.autoPlay) {
        await _player.play();
      } else if (_isPlayerPlaying) {
        await _player.pause();
      }
    } catch (error, stackTrace) {
      if (PlayerSafety.isDisposedPlayerError(error)) return;
      Error.throwWithStackTrace(error, stackTrace);
    }
    _syncPlaybackProvidersFromState();
  }

  Future<void> _seekToResumePosition(
    Duration? position, {
    required String source,
  }) async {
    if (position == null || position <= const Duration(milliseconds: 500)) {
      return;
    }

    final currentDeltaMs = (_playerPosition - position).inMilliseconds.abs();
    if (currentDeltaMs <= 800) {
      _syncPlaybackProvidersFromState();
      return;
    }

    await _player.seek(position);
    if (!mounted || _disposed) return;
    _syncPlaybackProvidersFromState();

    await Future<void>.delayed(const Duration(milliseconds: 90));
    if (!mounted || _disposed) return;
    final observed = _playerPosition;
    if (observed + const Duration(milliseconds: 800) < position) {
      await _player.seek(position);
      if (!mounted || _disposed) return;
      _syncPlaybackProvidersFromState();
    }

    appLogger.info(
      'AudioPlayerScreen: auto-resumed $source at ${position.inSeconds}s',
    );
  }

  void _setupStreamListeners() {
    // Position updates (throttled for performance)
    _positionSubscription = _player.stream.position.listen((pos) {
      if (mounted) {
        ref.read(playerPositionProvider.notifier).state = pos;
      }
    });

    // Duration updates (infrequent)
    _durationSubscription = _player.stream.duration.listen((dur) {
      if (mounted) {
        ref.read(playerDurationProvider.notifier).state = dur;
      }
    });

    // Buffering updates (infrequent)
    _bufferingSubscription = _player.stream.buffering.listen((buffering) {
      if (mounted) {
        ref.read(isBufferingProvider.notifier).state = buffering;
      }
    });
  }

  Future<void> _loadAudio() async {
    try {
      final filePath =
          '${widget.download.savePath}/${widget.download.filename}';
      final file = File(filePath);

      if (!await file.exists()) {
        if (mounted) {
          _showError('Audio file not found: ${widget.download.filename}');
        }
        return;
      }

      // Register player with PlayerManager for lifecycle management
      playerManager.registerPlayer('audio_${widget.download.id}', _player);

      // Load audio with media_kit
      await _player.open(Media(filePath), play: false);
      if (!mounted || _disposed) return;

      await _applyInitialResumePosition();

      if (!mounted || _disposed) return;
      _syncPlaybackProvidersFromState();

      if (widget.autoPlay) {
        await _player.play();
      }

      if (!mounted || _disposed) return;
      _syncPlaybackProvidersFromState();

      // Update current media
      ref.read(currentMediaProvider.notifier).state = filePath;

      appLogger.info('Audio loaded successfully: ${widget.download.filename}');

      _startPlaybackLifecycleTracking();
    } catch (e) {
      if (PlayerSafety.isDisposedPlayerError(e)) return;
      appLogger.error('Failed to load audio', e);
      if (mounted) {
        _showError('Failed to load audio: $e');
      }
    }
  }

  void _startPlaybackLifecycleTracking() {
    _watchProgressTimer?.cancel();
    _completedSubscription?.cancel();

    // Start periodic save of watch progress (every 5 seconds)
    _watchProgressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _saveWatchProgress();
    });

    // Listen for playback completion to auto-advance queue
    _completedSubscription = _player.stream.completed.listen(
      (completed) {
        if (completed && !_disposed) _onPlaybackCompleted();
      },
      onError: (Object error) {
        if (!PlayerSafety.isDisposedPlayerError(error)) {
          appLogger.warning('Audio completion stream error: $error');
        }
      },
    );
  }

  Future<void> _applyInitialResumePosition() async {
    final explicitPosition = widget.resumePosition;
    if (explicitPosition != null) {
      await _seekToResumePosition(explicitPosition, source: 'handoff');
      return;
    }

    try {
      final watchService = ref.read(watchProgressServiceProvider);
      final progress = watchService.getProgress(widget.download.id);
      if (progress == null) return;

      if (progress.fraction >= 0.90) return;
      if (progress.position <= const Duration(milliseconds: 500)) return;
      await _seekToResumePosition(progress.position, source: 'saved progress');
    } catch (e) {
      appLogger.debug('Failed to apply saved watch progress: $e');
    }
  }

  /// Save current playback position
  void _saveWatchProgress() {
    try {
      // Read directly from player state (not provider) for most accurate position
      final position = _playerPosition;
      final duration = _playerDuration;
      if (duration.inMilliseconds <= 0) return;

      final watchService = ref.read(watchProgressServiceProvider);
      watchService.saveResumePoint(widget.download.id, position, duration);
    } catch (_) {
      // Silently fail — non-critical
    }
  }

  void _showError(String message) {
    AppSnackBar.error(context, message: message);
  }

  void _togglePlayPause() {
    _safePlayer((player) => player.playOrPause());
  }

  void _seek(Duration position) {
    _safePlayer((player) => player.seek(position));
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
    _safePlayer((player) => player.setVolume(volume * 100));
    ref.read(playerVolumeProvider.notifier).state = volume;
  }

  void _changeSpeed(double speed) {
    _safePlayer((player) => player.setRate(speed));
    ref.read(playbackSpeedProvider.notifier).state = speed;
  }

  void _cycleSpeed() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final current = ref.read(playbackSpeedProvider);
    final currentIdx = speeds.indexWhere((s) => (s - current).abs() < 0.01);
    final nextIdx =
        currentIdx < 0 || currentIdx >= speeds.length - 1 ? 0 : currentIdx + 1;
    _changeSpeed(speeds[nextIdx]);
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      // Check for modifier keys (Cmd/Ctrl)
      final keysPressed = HardwareKeyboard.instance.logicalKeysPressed;
      final bool hasModifier =
          keysPressed.contains(LogicalKeyboardKey.metaLeft) ||
          keysPressed.contains(LogicalKeyboardKey.metaRight) ||
          keysPressed.contains(LogicalKeyboardKey.controlLeft) ||
          keysPressed.contains(LogicalKeyboardKey.controlRight);

      // Override Cmd/Ctrl+W to close player
      if (event.logicalKey == LogicalKeyboardKey.keyW && hasModifier) {
        _onClose();
        return;
      }

      // Ignore other system shortcuts
      if (hasModifier) return;

      // Player-specific shortcuts (no modifiers)
      switch (event.logicalKey) {
        case LogicalKeyboardKey.space:
        case LogicalKeyboardKey.keyK:
          _togglePlayPause();
          break;
        case LogicalKeyboardKey.arrowLeft:
          _seekBackward();
          break;
        case LogicalKeyboardKey.arrowRight:
          _seekForward();
          break;
        case LogicalKeyboardKey.keyJ:
          final pos = ref.read(playerPositionProvider);
          _seek(pos - const Duration(seconds: 10));
          break;
        case LogicalKeyboardKey.keyL:
          final pos = ref.read(playerPositionProvider);
          _seek(pos + const Duration(seconds: 10));
          break;
        case LogicalKeyboardKey.arrowUp:
          final vol = ref.read(playerVolumeProvider);
          _changeVolume((vol + 0.1).clamp(0.0, 1.0));
          break;
        case LogicalKeyboardKey.arrowDown:
          final vol = ref.read(playerVolumeProvider);
          _changeVolume((vol - 0.1).clamp(0.0, 1.0));
          break;
        case LogicalKeyboardKey.keyM:
          final vol = ref.read(playerVolumeProvider);
          _changeVolume(vol > 0 ? 0 : 1.0);
          break;
        case LogicalKeyboardKey.escape:
          _onClose();
          break;
        case LogicalKeyboardKey.comma:
          // < key - decrease speed
          if (event.character == '<') {
            final speed = ref.read(playbackSpeedProvider);
            _changeSpeed((speed - 0.25).clamp(0.25, 4.0));
          }
          break;
        case LogicalKeyboardKey.period:
          // > key - increase speed
          if (event.character == '>') {
            final speed = ref.read(playbackSpeedProvider);
            _changeSpeed((speed + 0.25).clamp(0.25, 4.0));
          }
          break;
        // Number keys 0-9 for seeking to percentage
        case LogicalKeyboardKey.digit0:
        case LogicalKeyboardKey.digit1:
        case LogicalKeyboardKey.digit2:
        case LogicalKeyboardKey.digit3:
        case LogicalKeyboardKey.digit4:
        case LogicalKeyboardKey.digit5:
        case LogicalKeyboardKey.digit6:
        case LogicalKeyboardKey.digit7:
        case LogicalKeyboardKey.digit8:
        case LogicalKeyboardKey.digit9:
          final digit = int.parse(event.character ?? '0');
          final duration = ref.read(playerDurationProvider);
          final newPosition = Duration(
            milliseconds: (duration.inMilliseconds * digit / 10).round(),
          );
          _seek(newPosition);
          break;
      }
    }
  }

  void _openMiniPlayer() async {
    if (_disposed) return;
    // Mark that we're opening mini player (so we don't dispose the player)
    _isOpeningMiniPlayer = true;

    // Create mini player state with download entity
    final miniPlayerState = MiniPlayerState(
      player: _player,
      filename: widget.download.filename,
      thumbnail: widget.download.thumbnail,
      downloadEntity: widget.download,
      downloadId: widget.download.id.toString(),
    );

    // Smooth transition: fade out this screen, then show mini player
    await _fadeController.reverse();
    if (!mounted || _disposed) return;

    // Set mini player state (triggers mini player entrance animation)
    ref.read(miniPlayerStateProvider.notifier).state = miniPlayerState;

    // Close full player screen
    if (mounted) {
      Navigator.of(context).pop(_handoffResult());
    }
  }

  /// Called when playback finishes — auto-advance to next queue item.
  void _onPlaybackCompleted() {
    if (_disposed) return;
    // Mark as watched on natural end (covers cases where timer missed 90% threshold)
    ref.read(watchProgressServiceProvider).onPlaybackEnd(widget.download.id);
    _saveWatchProgress();
    final nextDownload = ref.read(playbackQueueProvider.notifier).next();
    if (nextDownload != null && mounted) {
      _navigateToQueueItem(nextDownload);
    }
  }

  /// Skip to the next item in the playback queue.
  void _skipNext() {
    if (_disposed) return;
    _saveWatchProgress();
    final nextDownload = ref.read(playbackQueueProvider.notifier).next();
    if (nextDownload != null && mounted) {
      _navigateToQueueItem(nextDownload);
    }
  }

  /// Skip to the previous item in the playback queue.
  void _skipPrevious() {
    if (_disposed) return;
    _saveWatchProgress();
    final prevDownload = ref.read(playbackQueueProvider.notifier).previous();
    if (prevDownload != null && mounted) {
      _navigateToQueueItem(prevDownload);
    }
  }

  /// Navigate to a queue item by replacing the current player screen.
  void _navigateToQueueItem(DownloadEntity download) {
    // Stop current playback
    _safePlayer((player) => player.stop());

    if (FileUtils.isAudioFile(download.filename)) {
      Navigator.of(context).pushReplacement(
        AppTransitions.pageRoute(AudioPlayerScreen(download: download)),
      );
    } else if (FileUtils.isVideoFile(download.filename)) {
      // Pop audio player, push video player
      Navigator.of(context).pop(_handoffResult());
      Navigator.of(
        context,
      ).push(AppTransitions.pageRoute(VideoPlayerScreen(download: download)));
    }
  }

  void _onClose() {
    if (_disposed) return;
    // Save watch progress before closing
    _saveWatchProgress();

    if (mounted) {
      Navigator.of(context).pop(_handoffResult());
    }
  }

  PlayerHandoffResult _handoffResult() {
    return PlayerHandoffResult(
      position: _playerPosition,
      isPlaying: _isPlayerPlaying,
      restoreSidebar: !_isOpeningMiniPlayer,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _watchProgressTimer?.cancel();
    _focusNode.dispose();
    _fadeController.dispose();

    // Cancel stream subscriptions to prevent memory leaks
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _bufferingSubscription?.cancel();
    _completedSubscription?.cancel();

    // Only dispose player if we're not opening mini player
    if (!_isOpeningMiniPlayer) {
      playerManager.unregisterPlayer('audio_${widget.download.id}');
    } else {
      // Transfer ownership to mini player
      playerManager.unregisterPlayer(
        'audio_${widget.download.id}',
        dispose: false,
      );
      playerManager.registerPlayer('mini_audio_${widget.download.id}', _player);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(playerPositionProvider);
    final duration = ref.watch(playerDurationProvider);
    final volume = ref.watch(playerVolumeProvider);
    final playbackSpeed = ref.watch(playbackSpeedProvider);
    final isBuffering = ref.watch(isBufferingProvider);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageBg = isDark ? AppColors.homeDarkAppBg : AppColors.lightBase;

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Scaffold(
          backgroundColor: pageBg,
          body: Column(
            children: [
              _buildTopBar(cs, playbackSpeed),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                        vertical: AppSpacing.md,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildAlbumArt(),
                            const SizedBox(height: AppSpacing.xxl),
                            _buildTrackInfo(cs),
                            const SizedBox(height: AppSpacing.xxl),
                            _buildTimeline(position, duration, cs),
                            const SizedBox(height: AppSpacing.xl),
                            _buildTransportControls(cs),
                            const SizedBox(height: AppSpacing.lg),
                            _buildSecondaryControls(volume, cs),
                            if (isBuffering) ...[
                              const SizedBox(height: AppSpacing.md),
                              LinearProgressIndicator(
                                color: AppColors.accentHighlight,
                                backgroundColor: AppColors.surface2(context),
                                minHeight: 2,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _buildKeyboardHints(cs),
            ],
          ),
        ),
      ),
    );
  }

  /// Top bar — 52px, tonal surface, back + title + actions
  Widget _buildTopBar(ColorScheme cs, double speed) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 52,
      padding: EdgeInsets.only(
        left: Platform.isMacOS ? 78 : AppSpacing.sm,
        right: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.homeDarkCardBg : AppColors.surface1(context),
        border: Border(bottom: BorderSide(color: AppColors.border(context))),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _onClose,
            icon: const Icon(Icons.arrow_back, size: 20),
            tooltip: AppLocalizations.playerBack,
            style: IconButton.styleFrom(
              foregroundColor: cs.onSurface.withValues(
                alpha: AppOpacity.secondary,
              ),
            ),
          ),
          const Spacer(),
          // Subtle center label
          Text(
            AppLocalizations.playerAudioPlayerTitle,
            style: AppTypography.sectionHeader.copyWith(
              letterSpacing: 0,
              color: cs.onSurface.withValues(alpha: AppOpacity.medium),
            ),
          ),
          const Spacer(),
          // Speed indicator chip (tap to cycle)
          if (speed != 1.0)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: GestureDetector(
                onTap: _cycleSpeed,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: AppOpacity.subtle),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Text(
                    '${speed}x',
                    style: AppTypography.statusBadge.copyWith(
                      color: AppColors.accentHighlight,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          // Speed button
          IconButton(
            onPressed: _cycleSpeed,
            icon: const Icon(Icons.speed_rounded, size: 20),
            tooltip: AppLocalizations.playerPlaybackSpeed,
            style: IconButton.styleFrom(
              foregroundColor: cs.onSurface.withValues(
                alpha: AppOpacity.overlay,
              ),
            ),
          ),
          // Mini player button
          IconButton(
            onPressed: _openMiniPlayer,
            icon: const Icon(Icons.picture_in_picture_alt_rounded, size: 20),
            tooltip: AppLocalizations.playerOpenMiniPlayer,
            style: IconButton.styleFrom(
              foregroundColor: cs.onSurface.withValues(
                alpha: AppOpacity.overlay,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Album art hero — restrained, tokenized playback focus.
  Widget _buildAlbumArt() {
    return StreamBuilder<bool>(
      stream: _player.stream.playing,
      initialData: _isPlayerPlaying,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data ?? _isPlayerPlaying;
        final shortestSide = MediaQuery.sizeOf(context).shortestSide;
        final artSize = (shortestSide * 0.48).clamp(240.0, 360.0);
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
          width: artSize,
          height: artSize,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.border(context)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.34 : 0.12),
                blurRadius: isPlaying ? 32 : 18,
                offset: const Offset(0, 14),
              ),
              BoxShadow(
                color: AppColors.accentHighlight.withValues(
                  alpha: isPlaying ? AppOpacity.subtle : AppOpacity.divider,
                ),
                blurRadius: 28,
                spreadRadius: -8,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child:
                widget.download.thumbnail != null
                    ? AppCachedImage(
                      imageUrl: widget.download.thumbnail,
                      width: artSize,
                      height: artSize,
                      fit: BoxFit.cover,
                      errorWidget: _buildDefaultArtwork(isPlaying),
                    )
                    : _buildDefaultArtwork(isPlaying),
          ),
        );
      },
    );
  }

  Widget _buildDefaultArtwork(bool isPlaying) {
    return Container(
      color: AppColors.surface2(context),
      child: Center(
        child: AnimatedScale(
          scale: isPlaying ? 1.1 : 1.0,
          duration: const Duration(milliseconds: 300),
          child: Icon(
            Icons.music_note_rounded,
            size: 100,
            color: AppColors.brand.withValues(alpha: AppOpacity.medium),
          ),
        ),
      ),
    );
  }

  /// Track title + metadata — editorial typography
  Widget _buildTrackInfo(ColorScheme cs) {
    final ext = widget.download.filename.split('.').last.toUpperCase();
    final size = FileUtils.formatBytes(widget.download.totalBytes);

    return Column(
      children: [
        Text(
          widget.download.filename,
          style: AppTypography.appBarTitle.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
            height: 1.2,
            color: cs.onSurface,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.smMd),
        Text(
          '$ext  •  $size',
          style: AppTypography.statusBadge.copyWith(
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
            color: cs.onSurface.withValues(alpha: AppOpacity.scrim),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// Progress timeline — thin crimson bar, small thumb
  Widget _buildTimeline(Duration position, Duration duration, ColorScheme cs) {
    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: AppColors.accentHighlight,
            inactiveTrackColor: AppColors.surface2(context),
            thumbColor: AppColors.accentHighlight,
          ),
          child: Slider(
            value:
                duration.inMilliseconds > 0
                    ? (position.inMilliseconds / duration.inMilliseconds).clamp(
                      0.0,
                      1.0,
                    )
                    : 0.0,
            onChanged: (value) {
              final newPosition = Duration(
                milliseconds: (value * duration.inMilliseconds).round(),
              );
              _seek(newPosition);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                Formatters.formatDuration(position),
                style: AppTypography.statusBadge.copyWith(
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                  color: cs.onSurface.withValues(alpha: AppOpacity.scrim),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                Formatters.formatDuration(duration),
                style: AppTypography.statusBadge.copyWith(
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                  color: cs.onSurface.withValues(alpha: AppOpacity.scrim),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Transport controls — skip, rewind, play/pause hero, forward, skip
  Widget _buildTransportControls(ColorScheme cs) {
    final queueState = ref.watch(playbackQueueProvider);

    final controls = [
      if (queueState.hasPrevious)
        _transportButton(
          icon: Icons.skip_previous_rounded,
          onTap: _skipPrevious,
          tooltip: AppLocalizations.playbackQueueSkipPrevious,
          cs: cs,
        ),
      _transportButton(
        icon: Icons.replay_10_rounded,
        onTap: _seekBackward,
        tooltip: AppLocalizations.playerRewind10s,
        cs: cs,
      ),
      const SizedBox(width: AppSpacing.mdLg),
      _buildPlayButton(),
      const SizedBox(width: AppSpacing.mdLg),
      _transportButton(
        icon: Icons.forward_10_rounded,
        onTap: _seekForward,
        tooltip: AppLocalizations.playerForward10s,
        cs: cs,
      ),
      if (queueState.hasNext)
        _transportButton(
          icon: Icons.skip_next_rounded,
          onTap: _skipNext,
          tooltip: AppLocalizations.playbackQueueSkipNext,
          cs: cs,
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: controls,
            ),
          ),
        );
      },
    );
  }

  Widget _transportButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    required ColorScheme cs,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: AppDurations.tooltipWaitDuration,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.smMd),
          child: Icon(
            icon,
            size: 28,
            color: cs.onSurface.withValues(alpha: AppOpacity.medium),
          ),
        ),
      ),
    );
  }

  /// Play/Pause hero button — wine-red gradient circle with ambient glow
  Widget _buildPlayButton() {
    return StreamBuilder<bool>(
      stream: _player.stream.playing,
      initialData: _isPlayerPlaying,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data ?? _isPlayerPlaying;
        return Tooltip(
          message:
              isPlaying
                  ? AppLocalizations.playerPause
                  : AppLocalizations.playerPlay,
          waitDuration: AppDurations.tooltipWaitDuration,
          child: GestureDetector(
            onTap: _togglePlayPause,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.brand, // #8D021F
                    AppColors.brandDark, // Deeper wine
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brand.withValues(alpha: AppOpacity.scrim),
                    blurRadius: 30,
                  ),
                ],
              ),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
        );
      },
    );
  }

  /// Secondary controls — volume left, queue controls right
  Widget _buildSecondaryControls(double volume, ColorScheme cs) {
    final queueState = ref.watch(playbackQueueProvider);
    final volumeControls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => _changeVolume(volume > 0 ? 0 : 1.0),
          child: Tooltip(
            message: AppLocalizations.playerToggleMute,
            waitDuration: AppDurations.tooltipWaitDuration,
            child: Icon(
              volume == 0
                  ? Icons.volume_off_rounded
                  : volume < 0.5
                  ? Icons.volume_down_rounded
                  : Icons.volume_up_rounded,
              size: 18,
              color: cs.onSurface.withValues(alpha: AppOpacity.medium),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 120,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: AppColors.accentHighlight,
              inactiveTrackColor: AppColors.surface2(context),
              thumbColor: AppColors.accentHighlight,
            ),
            child: Slider(value: volume, onChanged: _changeVolume),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            '${(volume * 100).round()}%',
            style: AppTypography.compact.copyWith(
              color: cs.onSurface.withValues(alpha: AppOpacity.scrim),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );

    final queueControls = <Widget>[
      if (queueState.isNotEmpty) ...[
        _secondaryIcon(
          icon:
              queueState.shuffleEnabled
                  ? Icons.shuffle_on_rounded
                  : Icons.shuffle_rounded,
          isActive: queueState.shuffleEnabled,
          onTap: () => ref.read(playbackQueueProvider.notifier).toggleShuffle(),
          cs: cs,
        ),
        const SizedBox(width: AppSpacing.xs),
        _secondaryIcon(
          icon:
              queueState.repeatMode == QueueRepeatMode.repeatOne
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
          isActive: queueState.repeatMode != QueueRepeatMode.off,
          onTap:
              () => ref.read(playbackQueueProvider.notifier).cycleRepeatMode(),
          cs: cs,
        ),
      ],
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              volumeControls,
              if (queueControls.isNotEmpty)
                Row(mainAxisSize: MainAxisSize.min, children: queueControls),
            ],
          );
        }

        return Row(
          children: [
            // Volume — thin elegant slider
            volumeControls,
            const Spacer(),
            // Queue controls — shuffle + repeat (only when queue active)
            ...queueControls,
          ],
        );
      },
    );
  }

  Widget _secondaryIcon({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    required ColorScheme cs,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Icon(
          icon,
          size: 20,
          color:
              isActive
                  ? AppColors.accentHighlight
                  : cs.onSurface.withValues(alpha: AppOpacity.scrim),
        ),
      ),
    );
  }

  /// Ghost-text keyboard hints — barely visible, present for discovery
  Widget _buildKeyboardHints(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.smMd,
      ),
      child: Text(
        AppLocalizations.playerKeyboardShortcutsHint,
        style: AppTypography.compact.copyWith(
          letterSpacing: 0,
          color: cs.onSurface.withValues(alpha: AppOpacity.subtle),
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
