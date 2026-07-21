import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as p;
import '../../../../core/core.dart';
import '../../../../core/providers/backend_providers.dart';
import '../../../downloads/domain/entities/download_entity.dart';
import '../../../downloads/presentation/providers/downloads_notifier.dart';
import '../../domain/entities/player_handoff_result.dart';
import '../../domain/services/player_prefs_service.dart';
import '../../domain/services/player_safety.dart';
import '../../domain/services/player_speed_service.dart';
import '../../domain/services/player_hardware_decode_service.dart';
import '../providers/player_hardware_decode_provider.dart';
import '../providers/player_providers.dart';
import '../providers/playback_queue_providers.dart';
import '../providers/trim_providers.dart';
import '../widgets/player_edit_overlay.dart';
import '../widgets/video_controls.dart';
import '../widgets/on_screen_feedback.dart';
import '../widgets/subtitle_search_sheet.dart';
import '../widgets/keyboard_shortcuts_dialog.dart';
import 'audio_player_screen.dart';

/// External subtitle file discovered alongside the video
class ExternalSubtitle {
  final String path;
  final String langCode;
  final String langName;
  final String ext;

  const ExternalSubtitle({
    required this.path,
    required this.langCode,
    required this.langName,
    required this.ext,
  });
}

/// Video Player Screen with hardware-accelerated playback
/// Uses media_kit (libmpv backend) for native performance
class VideoPlayerScreen extends ConsumerStatefulWidget {
  final DownloadEntity download;

  /// Optional: Pass existing player when expanding from PiP to preserve playback
  final Player? existingPlayer;
  final VideoController? existingVideoController;
  final Duration? resumePosition;
  final bool autoPlay;

  /// When true, shows a "Downloading — Preview" banner and handles
  /// MediaKit errors gracefully (SnackBar instead of error overlay).
  final bool isPreview;

  const VideoPlayerScreen({
    super.key,
    required this.download,
    this.existingPlayer,
    this.existingVideoController,
    this.resumePosition,
    this.autoPlay = true,
    this.isPreview = false,
  });

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen>
    with SingleTickerProviderStateMixin {
  late final Player _player;
  late final VideoController _videoController;
  final FocusNode _focusNode = FocusNode();
  bool _isOpeningPiP = false;
  bool _disposed = false;
  bool _isEditMode = false;
  bool _isVideoReady =
      false; // Guard: don't render Video widget until media is opened
  List<ExternalSubtitle> _externalSubtitles = []; // Discovered subtitle files
  final _videoControlsKey = GlobalKey<ConsumerState<VideoControls>>();
  Timer? _watchProgressTimer; // Auto-save playback position every 5s
  StreamSubscription<bool>?
  _completedSubscription; // Listen for playback completion
  Timer? _savePrefDebounce; // Debounce per-file preference saves (1 s)

  // On-screen visual feedback
  FeedbackData? _currentFeedback;
  int _feedbackKey = 0; // Force rebuild on new feedback

  // Fade-out animation for smooth PiP transition
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Setup fade-out animation for PiP transition
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: 1.0, // Start fully visible
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    // Check if we're resuming from PiP with existing player
    if (widget.existingPlayer != null &&
        widget.existingVideoController != null) {
      _player = widget.existingPlayer!;
      _videoController = widget.existingVideoController!;
      _isVideoReady = true; // Already playing from PiP

      // Register player under fullscreen ID
      playerManager.registerPlayer('video_${widget.download.id}', _player);
      _startPlaybackLifecycleTracking();

      appLogger.info('VideoPlayerScreen: Using existing player from PiP');

      // Existing-player paths are surface handoffs (sidebar/PiP → fullscreen).
      // Make the fullscreen controls reflect the live player immediately and
      // enforce the captured play/pause intent after the route is mounted.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _disposed) return;
        _syncPlaybackProvidersFromState();
        unawaited(_prepareExistingPlayerHandoff());
      });
    } else {
      // Initialize new player
      _player = Player();
      _videoController = VideoController(_player);

      // Apply hardware-decode hint BEFORE _loadVideo() so the very
      // first frame benefits from videotoolbox / d3d11va / vaapi
      // when the user has opted in. mpv evaluates `hwdec` at codec
      // open time — fire-and-forget here would race the open() call
      // and the property could land too late, so the hint is
      // sequenced via `.then(_loadVideo)`. The catchError still
      // calls _loadVideo so a setProperty failure (older mpv,
      // platform stub) never blocks playback. Default off; enabling
      // lives in `hardwareDecodeEnabledProvider`.
      final hwdecEnabled = ref.read(hardwareDecodeEnabledProvider);
      PlayerHardwareDecodeService.apply(_player, enabled: hwdecEnabled)
          .then((_) {
            if (!mounted) return;
            _loadVideo();
          })
          .catchError((Object e, StackTrace st) {
            if (!mounted) return;
            _loadVideo();
          });
    }

    // Load saved preferences (global appearance first, then per-file overrides)
    _loadSubtitlePreferences();
    _loadPlayerPrefs();

    // Wire provider listeners to auto-save per-file prefs when state changes
    _setupPrefListeners();

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

    // media_kit can report the pre-seek position for a short window after
    // `open()`. One cheap retry keeps cold-open resume deterministic without
    // delaying normal playback.
    await Future<void>.delayed(const Duration(milliseconds: 90));
    if (!mounted || _disposed) return;
    final observed = _playerPosition;
    if (observed + const Duration(milliseconds: 800) < position) {
      await _player.seek(position);
      if (!mounted || _disposed) return;
      _syncPlaybackProvidersFromState();
    }

    appLogger.info(
      'VideoPlayerScreen: auto-resumed $source at ${position.inSeconds}s',
    );
  }

  /// Load persisted subtitle appearance preferences from SharedPreferences
  Future<void> _loadSubtitlePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fontSize = prefs.getDouble('subtitle_font_size');
      final textColor = prefs.getInt('subtitle_text_color');
      final bgColor = prefs.getInt('subtitle_bg_color');
      final bgEnabled = prefs.getBool('subtitle_bg_enabled');
      final bottomPad = prefs.getDouble('subtitle_bottom_padding');

      if (fontSize != null) {
        ref.read(subtitleFontSizeProvider.notifier).state = fontSize;
      }
      if (textColor != null) {
        ref.read(subtitleTextColorProvider.notifier).state = Color(textColor);
      }
      if (bgColor != null) {
        ref.read(subtitleBackgroundColorProvider.notifier).state = Color(
          bgColor,
        );
      }
      if (bgEnabled != null) {
        ref.read(subtitleBackgroundEnabledProvider.notifier).state = bgEnabled;
      }
      if (bottomPad != null) {
        ref.read(subtitleBottomPaddingProvider.notifier).state = bottomPad;
      }
    } catch (e) {
      appLogger.debug('Failed to load subtitle preferences: $e');
    }
  }

  /// Listen for per-file pref changes and debounce saves.
  void _setupPrefListeners() {
    ref.listenManual(playbackSpeedProvider, (_, __) => _scheduleSavePrefs());
    ref.listenManual(playerVolumeProvider, (_, __) => _scheduleSavePrefs());
    ref.listenManual(subtitleFontSizeProvider, (_, __) => _scheduleSavePrefs());
    ref.listenManual(subtitleDelayProvider, (_, __) => _scheduleSavePrefs());
    ref.listenManual(
      currentAudioTrackProvider,
      (_, __) => _scheduleSavePrefs(),
    );
    ref.listenManual(
      currentSubtitleTrackProvider,
      (_, __) => _scheduleSavePrefs(),
    );
  }

  /// Load per-file player preferences (speed, volume, tracks, font size, delay).
  /// Called after _loadSubtitlePreferences so per-file font size overrides global.
  void _loadPlayerPrefs() {
    final url = widget.download.url;
    if (url.isEmpty) return;

    ref
        .read(playerPrefsServiceProvider)
        .getPrefs(url)
        .then((prefs) {
          if (prefs == null || !mounted) return;

          if (prefs.speed != 1.0) {
            _safePlayer((player) => player.setRate(prefs.speed));
            ref.read(playbackSpeedProvider.notifier).state = prefs.speed;
          }
          if (prefs.volume != 1.0) {
            _safePlayer((player) => player.setVolume(prefs.volume * 100));
            ref.read(playerVolumeProvider.notifier).state = prefs.volume;
          }
          if (prefs.subtitleFontSize != 32.0) {
            ref.read(subtitleFontSizeProvider.notifier).state =
                prefs.subtitleFontSize;
          }
          if (prefs.subtitleDelay != 0) {
            ref.read(subtitleDelayProvider.notifier).state =
                prefs.subtitleDelay;
          }

          // Restore track selections once the player has loaded its track list
          final subId = prefs.subtitleTrackId;
          final audioId = prefs.audioTrackId;
          final needsTrackRestore =
              (subId != null && subId != 'no') ||
              (audioId != null && audioId != 'no');
          if (needsTrackRestore) {
            PlayerSafety.safeCall(() async {
              if (_disposed) return;
              final tracks = await _player.stream.tracks.first;
              if (!mounted || _disposed) return;
              if (subId != null && subId != 'no') {
                final t =
                    tracks.subtitle.where((t) => t.id == subId).firstOrNull;
                if (t != null) {
                  _safePlayer((player) => player.setSubtitleTrack(t));
                  ref.read(currentSubtitleTrackProvider.notifier).state = t;
                }
              }
              if (audioId != null && audioId != 'no') {
                final t =
                    tracks.audio.where((t) => t.id == audioId).firstOrNull;
                if (t != null) {
                  _safePlayer((player) => player.setAudioTrack(t));
                  ref.read(currentAudioTrackProvider.notifier).state = t;
                }
              }
            });
          }

          appLogger.debug(
            'Player prefs loaded for ${widget.download.filename}',
          );
        })
        .catchError((e) {
          appLogger.debug('Failed to load player prefs: $e');
        });
  }

  /// Schedule a debounced save of current per-file preferences (1 s delay).
  void _scheduleSavePrefs() {
    _savePrefDebounce?.cancel();
    _savePrefDebounce = Timer(const Duration(seconds: 1), _savePlayerPrefs);
  }

  /// Persist current per-file preferences immediately (fire-and-forget).
  void _savePlayerPrefs() {
    final url = widget.download.url;
    if (url.isEmpty) return;

    final prefs = PlayerPrefs(
      speed: ref.read(playbackSpeedProvider),
      volume: ref.read(playerVolumeProvider),
      subtitleTrackId: ref.read(currentSubtitleTrackProvider).id,
      audioTrackId: ref.read(currentAudioTrackProvider).id,
      subtitleFontSize: ref.read(subtitleFontSizeProvider),
      subtitleDelay: ref.read(subtitleDelayProvider),
    );

    ref.read(playerPrefsServiceProvider).savePrefs(url, prefs);
  }

  Future<void> _loadVideo() async {
    try {
      final filePath =
          '${widget.download.savePath}/${widget.download.filename}';
      final file = File(filePath);

      if (!await file.exists()) {
        if (mounted) {
          _showError('Video file not found: ${widget.download.filename}');
        }
        return;
      }

      // Register player with PlayerManager for lifecycle management
      playerManager.registerPlayer('video_${widget.download.id}', _player);

      // Load video with media_kit
      await _player.open(Media(filePath), play: false);
      if (!mounted || _disposed) return;

      await _applyInitialResumePosition();
      if (!mounted || _disposed) return;
      _syncPlaybackProvidersFromState();

      ref.read(analyticsServiceProvider).track('video_play', {
        'platform': widget.download.platform,
      });

      // Mark as ready AFTER media is opened — now safe to render Video widget
      // This prevents mpv crash from 0x0 rect during Navigator push animation
      if (mounted) {
        setState(() => _isVideoReady = true);
      }

      // Scan for external subtitle files alongside the video
      _scanForSubtitles(filePath);

      if (widget.autoPlay) {
        await _player.play();
        if (!mounted || _disposed) return;
        _syncPlaybackProvidersFromState();
      }

      // Update current media
      ref.read(currentMediaProvider.notifier).state = filePath;

      appLogger.info('Video loaded successfully: ${widget.download.filename}');

      _startPlaybackLifecycleTracking();
    } catch (e) {
      if (PlayerSafety.isDisposedPlayerError(e)) return;
      appLogger.error('Failed to load video', e);
      if (mounted) {
        if (widget.isPreview) {
          // Preview: file may not have enough data yet — show SnackBar and close
          AppSnackBar.warning(
            context,
            message: AppLocalizations.playerPreviewNotAvailable,
          );
          Navigator.of(context).maybePop();
        } else {
          _showError('Failed to load video: $e');
        }
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
          appLogger.warning('Video completion stream error: $error');
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
      // Read directly from player state (not provider) for most accurate position,
      // especially important on close/completion where provider may lag behind
      final position = _playerPosition;
      final duration = _playerDuration;
      if (duration.inMilliseconds <= 0) return;

      final watchService = ref.read(watchProgressServiceProvider);
      watchService.saveResumePoint(widget.download.id, position, duration);
    } catch (_) {
      // Silently fail — non-critical
    }
  }

  /// Scan for external subtitle files (yt-dlp convention: Video Title.en.srt)
  void _scanForSubtitles(String videoPath) {
    try {
      final videoFile = File(videoPath);
      final dir = videoFile.parent;
      final baseName = widget.download.filenameWithoutExtension;

      final subtitleExtensions = ['.srt', '.vtt', '.ass', '.ssa'];
      final found = <ExternalSubtitle>[];

      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;

        // Match pattern: baseName.LANG.ext or baseName.ext
        if (!name.startsWith(baseName)) continue;

        final suffix = name.substring(baseName.length);
        final hasSubExt = subtitleExtensions.any(
          (ext) => suffix.toLowerCase().endsWith(ext),
        );
        if (!hasSubExt) continue;

        // Extract language code from suffix (e.g., ".en.srt" → "en")
        final parts = suffix.split('.');
        String langCode = '';
        String langName = '';
        if (parts.length >= 3) {
          // .en.srt → parts = ['', 'en', 'srt']
          langCode = parts[parts.length - 2];
          langName = _languageCodeToName(langCode);
        } else {
          langName = 'Subtitle';
        }

        found.add(
          ExternalSubtitle(
            path: entity.path,
            langCode: langCode,
            langName: langName,
            ext: parts.last,
          ),
        );
      }

      if (found.isNotEmpty && mounted) {
        setState(() => _externalSubtitles = found);
        appLogger.info('Found ${found.length} external subtitle files');
      }
    } catch (e) {
      appLogger.debug('Subtitle scan failed: $e');
    }
  }

  static String _languageCodeToName(String code) {
    const map = {
      'en': 'English',
      'vi': 'Vietnamese',
      'zh': 'Chinese',
      'ja': 'Japanese',
      'ko': 'Korean',
      'es': 'Spanish',
      'fr': 'French',
      'de': 'German',
      'pt': 'Portuguese',
      'ru': 'Russian',
      'ar': 'Arabic',
      'hi': 'Hindi',
      'id': 'Indonesian',
      'th': 'Thai',
      'it': 'Italian',
    };
    return map[code.toLowerCase()] ?? code.toUpperCase();
  }

  /// Open file picker to load an external subtitle file (.srt/.vtt/.ass/.ssa)
  Future<void> _loadExternalSubtitleFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['srt', 'vtt', 'ass', 'ssa'],
        dialogTitle: AppLocalizations.subtitleAppearanceLoadFile,
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final name = result.files.single.name;
        final track = SubtitleTrack.uri(path, title: name);
        _safePlayer((player) => player.setSubtitleTrack(track));
        ref.read(currentSubtitleTrackProvider.notifier).state = track;
      }
    } catch (e) {
      appLogger.debug('Subtitle file picker failed: $e');
    }
  }

  /// Open the OpenSubtitles search sheet to find and download a subtitle file.
  void _searchSubtitlesOnline() {
    final filePath = '${widget.download.savePath}/${widget.download.filename}';
    SubtitleSearchSheet.show(
      context,
      videoFilePath: filePath,
      onSubtitleSaved: (srtPath) {
        // Reload external subtitles so the new file appears in the menu
        _scanForSubtitles(filePath);
        // Automatically load the new subtitle track
        final track = SubtitleTrack.uri(srtPath);
        _safePlayer((player) => player.setSubtitleTrack(track));
        ref.read(currentSubtitleTrackProvider.notifier).state = track;
      },
    );
  }

  void _showError(String message) {
    AppSnackBar.error(context, message: message);
  }

  /// Show on-screen visual feedback overlay
  void _showFeedback(FeedbackData data) {
    setState(() {
      _currentFeedback = data;
      _feedbackKey++;
    });
  }

  /// Capture a full-resolution screenshot of the current video frame
  Future<void> _captureScreenshot() async {
    final filePath = '${widget.download.savePath}/${widget.download.filename}';
    final position = _playerPosition;

    // Create screenshots directory
    final screenshotDir = Directory(
      p.join(widget.download.savePath, '${AppConstants.appName} Screenshots'),
    );
    if (!await screenshotDir.exists()) {
      await screenshotDir.create(recursive: true);
    }

    // Generate filename with timestamp
    final baseName = p.basenameWithoutExtension(widget.download.filename);
    final timeStr = Formatters.formatDuration(position).replaceAll(':', '-');
    final outputPath = p.join(screenshotDir.path, '${baseName}_$timeStr.jpg');

    final ffmpeg = ref.read(ffmpegDatasourceProvider);
    final result = await ffmpeg.captureScreenshot(
      filePath,
      position,
      outputPath,
    );

    if (result != null && mounted) {
      _showFeedback(
        FeedbackData(
          type: FeedbackType.screenshot,
          label: AppLocalizations.playerControlsScreenshotSaved,
          icon: Icons.camera_alt,
        ),
      );
      appLogger.info('Screenshot saved: $outputPath');
    } else if (mounted) {
      _showFeedback(
        FeedbackData(
          type: FeedbackType.screenshot,
          label: AppLocalizations.playerControlsScreenshotFailed,
          icon: Icons.error_outline,
        ),
      );
    }
  }

  /// Toggle cinema mode
  void _toggleCinemaMode() {
    final current = ref.read(cinemaModeProvider);
    ref.read(cinemaModeProvider.notifier).state = !current;
    _showFeedback(
      FeedbackData(type: FeedbackType.cinemaMode, value: !current ? 1.0 : 0.0),
    );
  }

  /// Step one frame forward or backward (≈33ms at 30fps)
  void _frameStep({required bool forward}) {
    if (_isPlayerPlaying) {
      _safePlayer((player) => player.pause());
    }
    final pos = _playerPosition;
    const frameDuration = Duration(milliseconds: 33);
    final newPos = forward ? pos + frameDuration : pos - frameDuration;
    _safePlayer(
      (player) => player.seek(newPos > Duration.zero ? newPos : Duration.zero),
    );
    _showFeedback(
      FeedbackData(
        type: FeedbackType.frameStep,
        icon: forward ? Icons.skip_next : Icons.skip_previous,
      ),
    );
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

      // Override Cmd/Ctrl+W to close player instead of hiding window
      if (event.logicalKey == LogicalKeyboardKey.keyW && hasModifier) {
        _onClose();
        return;
      }

      // Ignore other system shortcuts (let them bubble up to system)
      if (hasModifier) {
        return; // Let system handle Cmd/Ctrl+Q, Cmd/Ctrl+F, etc.
      }

      // Player-specific shortcuts (no modifiers)
      switch (event.logicalKey) {
        case LogicalKeyboardKey.space:
        case LogicalKeyboardKey.keyK:
          _safePlayer((player) => player.playOrPause());
          break;
        case LogicalKeyboardKey.arrowLeft:
          final currentPosition = ref.read(playerPositionProvider);
          final newPosition = currentPosition - const Duration(seconds: 5);
          _safePlayer(
            (player) => player.seek(
              newPosition > Duration.zero ? newPosition : Duration.zero,
            ),
          );
          break;
        case LogicalKeyboardKey.arrowRight:
          final currentPosition = ref.read(playerPositionProvider);
          final newPosition = currentPosition + const Duration(seconds: 5);
          _safePlayer((player) => player.seek(newPosition));
          break;
        case LogicalKeyboardKey.keyJ:
          final currentPosition = ref.read(playerPositionProvider);
          final newPosition = currentPosition - const Duration(seconds: 10);
          _safePlayer(
            (player) => player.seek(
              newPosition > Duration.zero ? newPosition : Duration.zero,
            ),
          );
          break;
        case LogicalKeyboardKey.keyL:
          final currentPosition = ref.read(playerPositionProvider);
          final newPosition = currentPosition + const Duration(seconds: 10);
          _safePlayer((player) => player.seek(newPosition));
          break;
        case LogicalKeyboardKey.arrowUp:
          final volume = ref.read(playerVolumeProvider);
          final newVolume = (volume + 0.1).clamp(0.0, 1.0);
          _safePlayer((player) => player.setVolume(newVolume * 100));
          ref.read(playerVolumeProvider.notifier).state = newVolume;
          _showFeedback(
            FeedbackData(type: FeedbackType.volume, value: newVolume),
          );
          break;
        case LogicalKeyboardKey.arrowDown:
          final volume = ref.read(playerVolumeProvider);
          final newVolume = (volume - 0.1).clamp(0.0, 1.0);
          _safePlayer((player) => player.setVolume(newVolume * 100));
          ref.read(playerVolumeProvider.notifier).state = newVolume;
          _showFeedback(
            FeedbackData(type: FeedbackType.volume, value: newVolume),
          );
          break;
        case LogicalKeyboardKey.keyM:
          final volume = ref.read(playerVolumeProvider);
          if (volume > 0) {
            _safePlayer((player) => player.setVolume(0));
            ref.read(playerVolumeProvider.notifier).state = 0;
            _showFeedback(
              const FeedbackData(type: FeedbackType.volume, value: 0),
            );
          } else {
            _safePlayer((player) => player.setVolume(100));
            ref.read(playerVolumeProvider.notifier).state = 1.0;
            _showFeedback(
              const FeedbackData(type: FeedbackType.volume, value: 1.0),
            );
          }
          break;
        case LogicalKeyboardKey.keyF:
          _toggleFullscreen();
          break;
        case LogicalKeyboardKey.escape:
          if (ref.read(isFullscreenProvider)) {
            _toggleFullscreen();
          } else {
            _onClose();
          }
          break;
        case LogicalKeyboardKey.slash:
          // ? key (Shift + /)
          if (event.character == '?') {
            _showKeyboardShortcuts();
          }
          break;
        case LogicalKeyboardKey.keyH:
          _showKeyboardShortcuts();
          break;
        case LogicalKeyboardKey.keyT:
          // Toggle trim mode
          final isTrimMode = ref.read(isTrimModeProvider);
          if (isTrimMode) {
            ref.read(isTrimModeProvider.notifier).state = false;
            ref.read(trimStartProvider.notifier).state = null;
            ref.read(trimEndProvider.notifier).state = null;
          } else {
            ref.read(isTrimModeProvider.notifier).state = true;
            _safePlayer((player) => player.pause());
            ref.read(showControlsProvider.notifier).state = true;
          }
          break;
        case LogicalKeyboardKey.keyI:
          // Set trim in point
          if (ref.read(isTrimModeProvider)) {
            ref.read(trimStartProvider.notifier).state = ref.read(
              playerPositionProvider,
            );
          }
          break;
        case LogicalKeyboardKey.keyO:
          // Set trim out point
          if (ref.read(isTrimModeProvider)) {
            ref.read(trimEndProvider.notifier).state = ref.read(
              playerPositionProvider,
            );
          }
          break;
        case LogicalKeyboardKey.keyA:
          // A-B Repeat: toggle point A → B → clear
          _toggleAbRepeatPoint();
          break;
        case LogicalKeyboardKey.keyX:
          // Clear A-B repeat immediately
          ref.read(abRepeatPointAProvider.notifier).state = null;
          ref.read(abRepeatPointBProvider.notifier).state = null;
          break;
        case LogicalKeyboardKey.keyZ:
          // Subtitle delay: Shift+Z = reset, Z = -100ms
          // Note: state is tracked; playback application requires media_kit to
          // expose a subtitle delay API (not available in v1.2.6).
          if (event.character == 'Z') {
            ref.read(subtitleDelayProvider.notifier).state = 0;
          } else {
            final current = ref.read(subtitleDelayProvider);
            ref.read(subtitleDelayProvider.notifier).state = (current - 100)
                .clamp(-5000, 5000);
          }
          break;
        case LogicalKeyboardKey.keyC:
          // Subtitle delay +100ms
          {
            final current = ref.read(subtitleDelayProvider);
            ref.read(subtitleDelayProvider.notifier).state = (current + 100)
                .clamp(-5000, 5000);
          }
          break;
        case LogicalKeyboardKey.keyN:
          // Next chapter
          _seekToNextChapter();
          break;
        case LogicalKeyboardKey.keyP:
          // Previous chapter
          _seekToPreviousChapter();
          break;
        case LogicalKeyboardKey.comma:
          if (event.character == '<') {
            // Shift+, — decrease speed
            final speed = ref.read(playbackSpeedProvider);
            final newSpeed = PlayerSpeedService.decrease(speed);
            _safePlayer((player) => player.setRate(newSpeed));
            ref.read(playbackSpeedProvider.notifier).state = newSpeed;
            _showFeedback(
              FeedbackData(
                type: FeedbackType.speed,
                label: PlayerSpeedService.formatLabel(newSpeed),
              ),
            );
          } else {
            // , alone — frame step backward (when paused)
            if (!_isPlayerPlaying) {
              _frameStep(forward: false);
            }
          }
          break;
        case LogicalKeyboardKey.period:
          if (event.character == '>') {
            // Shift+. — increase speed
            final speed = ref.read(playbackSpeedProvider);
            final newSpeed = PlayerSpeedService.increase(speed);
            _safePlayer((player) => player.setRate(newSpeed));
            ref.read(playbackSpeedProvider.notifier).state = newSpeed;
            _showFeedback(
              FeedbackData(
                type: FeedbackType.speed,
                label: PlayerSpeedService.formatLabel(newSpeed),
              ),
            );
          } else {
            // . alone — frame step forward (when paused)
            if (!_isPlayerPlaying) {
              _frameStep(forward: true);
            }
          }
          break;
        case LogicalKeyboardKey.keyS:
          // Screenshot capture
          _captureScreenshot();
          break;
        case LogicalKeyboardKey.keyG:
          // Toggle cinema mode
          _toggleCinemaMode();
          break;
        case LogicalKeyboardKey.keyE:
          // Toggle edit mode overlay
          setState(() => _isEditMode = !_isEditMode);
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
          _safePlayer((player) => player.seek(newPosition));
          break;
      }
    }
  }

  void _seekToNextChapter() {
    final chapters = widget.download.chapters;
    if (chapters.isEmpty) return;
    final posSeconds = ref.read(playerPositionProvider).inMilliseconds / 1000.0;
    for (final chapter in chapters) {
      if (chapter.startTime > posSeconds + 1.0) {
        _safePlayer(
          (player) => player.seek(
            Duration(milliseconds: (chapter.startTime * 1000).round()),
          ),
        );
        return;
      }
    }
  }

  void _seekToPreviousChapter() {
    final chapters = widget.download.chapters;
    if (chapters.isEmpty) return;
    final posSeconds = ref.read(playerPositionProvider).inMilliseconds / 1000.0;
    for (int i = chapters.length - 1; i >= 0; i--) {
      if (chapters[i].startTime < posSeconds - 3.0) {
        _safePlayer(
          (player) => player.seek(
            Duration(milliseconds: (chapters[i].startTime * 1000).round()),
          ),
        );
        return;
      }
    }
    _safePlayer((player) => player.seek(Duration.zero));
  }

  void _toggleAbRepeatPoint() {
    final pointA = ref.read(abRepeatPointAProvider);
    final pointB = ref.read(abRepeatPointBProvider);
    final position = ref.read(playerPositionProvider);

    if (pointA == null) {
      ref.read(abRepeatPointAProvider.notifier).state = position;
    } else if (pointB == null) {
      if (position > pointA) {
        ref.read(abRepeatPointBProvider.notifier).state = position;
        _safePlayer((player) => player.seek(pointA));
      }
    } else {
      ref.read(abRepeatPointAProvider.notifier).state = null;
      ref.read(abRepeatPointBProvider.notifier).state = null;
    }
  }

  void _showKeyboardShortcuts() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => const KeyboardShortcutsDialog(),
    );
  }

  Widget _buildVideoPlayer() {
    // Don't render Video widget until media is opened
    // Prevents mpv native crash from 0x0 texture rect during transitions
    if (!_isVideoReady) {
      return SizedBox.expand(
        child: Center(
          child: SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: AppColors.accentHighlight,
            ),
          ),
        ),
      );
    }

    final aspectRatioMode = ref.watch(aspectRatioModeProvider);
    final subConfig = ref.watch(subtitleViewConfigProvider);

    switch (aspectRatioMode) {
      case AspectRatioMode.fit:
        // Default: fit with aspect ratio preserved (black bars)
        return AspectRatio(
          aspectRatio: 16 / 9,
          child: Video(
            controller: _videoController,
            controls: NoVideoControls,
            subtitleViewConfiguration: subConfig,
            fit: BoxFit.contain,
          ),
        );

      case AspectRatioMode.fill:
        // Fill screen by cropping
        return SizedBox.expand(
          child: Video(
            controller: _videoController,
            controls: NoVideoControls,
            subtitleViewConfiguration: subConfig,
            fit: BoxFit.cover,
          ),
        );

      case AspectRatioMode.stretch:
        // Stretch to fill (distort)
        return SizedBox.expand(
          child: Video(
            controller: _videoController,
            controls: NoVideoControls,
            subtitleViewConfiguration: subConfig,
            fit: BoxFit.fill,
          ),
        );

      case AspectRatioMode.original:
        // Original size (1:1 pixels)
        return Video(
          controller: _videoController,
          controls: NoVideoControls,
          subtitleViewConfiguration: subConfig,
          fit: BoxFit.none,
        );
    }
  }

  void _toggleFullscreen() async {
    if (_disposed) return;
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
  }

  void _openPiP() async {
    if (_disposed) return;
    // Mark that we're opening PiP (so we don't dispose the player)
    _isOpeningPiP = true;

    // Exit fullscreen if active
    if (ref.read(isFullscreenProvider)) {
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        await windowManager.setFullScreen(false);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    }

    // Create PiP state with download entity
    final pipState = MiniVideoPlayerState(
      player: _player,
      videoController: _videoController,
      filename: widget.download.filename,
      downloadEntity: widget.download,
      downloadId: widget.download.id.toString(), // Use consistent ID as String
    );

    // Smooth transition: fade out this screen, then show PiP
    await _fadeController.reverse();
    if (!mounted || _disposed) return;

    // Set PiP state (triggers PiP entrance animation)
    ref.read(miniVideoPlayerStateProvider.notifier).state = pipState;

    // Close full player screen without animation (we already faded out)
    if (mounted) {
      Navigator.of(context).pop(_handoffResult());
    }
  }

  /// Called when playback finishes — auto-advance to next queue item.
  void _onPlaybackCompleted() {
    if (_disposed) return;
    // Mark as watched on natural end (covers short videos where onEnd is the reliable signal)
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

    // Replace current screen with new player for the queue item
    if (FileUtils.isVideoFile(download.filename)) {
      Navigator.of(context).pushReplacement(
        AppTransitions.pageRoute(VideoPlayerScreen(download: download)),
      );
    } else if (FileUtils.isAudioFile(download.filename)) {
      // Pop video player, push audio player
      Navigator.of(context).pop(_handoffResult());
      Navigator.of(
        context,
      ).push(AppTransitions.pageRoute(AudioPlayerScreen(download: download)));
    }
  }

  void _onClose() async {
    if (_disposed) return;
    // Save watch progress + player prefs before closing
    _saveWatchProgress();
    _savePrefDebounce?.cancel();
    _savePlayerPrefs();

    // Exit fullscreen if active
    if (ref.read(isFullscreenProvider)) {
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        await windowManager.setFullScreen(false);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    }

    // Reset providers
    ref.read(showControlsProvider.notifier).state = true;
    ref.read(isFullscreenProvider.notifier).state = false;

    if (mounted) {
      Navigator.of(context).pop(_handoffResult());
    }
  }

  PlayerHandoffResult _handoffResult() {
    return PlayerHandoffResult(
      position: _playerPosition,
      isPlaying: _isPlayerPlaying,
      restoreSidebar: !_isOpeningPiP,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _completedSubscription?.cancel();
    _watchProgressTimer?.cancel();
    _savePrefDebounce?.cancel();
    _focusNode.dispose();
    _fadeController.dispose();

    // Only dispose player if we're not opening PiP
    // (PiP will take ownership of the player instance)
    if (!_isOpeningPiP) {
      // Unregister and dispose player
      playerManager.unregisterPlayer('video_${widget.download.id}');
    } else {
      // Transfer ownership to PiP, don't dispose but unregister from manager
      playerManager.unregisterPlayer(
        'video_${widget.download.id}',
        dispose: false,
      );

      // Register under PiP ID
      playerManager.registerPlayer('pip_video_${widget.download.id}', _player);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFullscreen = ref.watch(isFullscreenProvider);
    final isBuffering = ref.watch(isBufferingProvider);
    final isCinemaMode = ref.watch(cinemaModeProvider);

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // Video player with double-click to fullscreen
              Center(
                child: GestureDetector(
                  onDoubleTap: _toggleFullscreen,
                  child: _buildVideoPlayer(),
                ),
              ),

              // Cinematic vignette overlay with brand-aware tint.
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: AppTransitions.slow,
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(-0.4, 0.0),
                        radius: 1.2,
                        colors: [
                          Colors.transparent,
                          AppColors.accentHighlight.withValues(
                            alpha: isCinemaMode ? 0.12 : 0.06,
                          ),
                          Colors.black.withValues(
                            alpha:
                                isCinemaMode
                                    ? AppOpacity.overlay
                                    : AppOpacity.subtle,
                          ),
                        ],
                        stops: const [0.25, 0.65, 1.0],
                      ),
                    ),
                  ),
                ),
              ),

              // Buffering indicator
              if (isBuffering)
                Center(
                  child: CircularProgressIndicator(
                    color: AppColors.accentHighlight,
                  ),
                ),

              // Custom controls overlay
              Positioned.fill(
                child: VideoControls(
                  key: _videoControlsKey,
                  player: _player,
                  onClose: _onClose,
                  onOpenPiP: _openPiP,
                  externalSubtitles: _externalSubtitles,
                  chapters: widget.download.chapters,
                  download: widget.download,
                  onLoadSubtitleFile: _loadExternalSubtitleFile,
                  onSearchSubtitlesOnline: _searchSubtitlesOnline,
                  onSkipNext: _skipNext,
                  onSkipPrevious: _skipPrevious,
                  onScreenshot: _captureScreenshot,
                  onToggleCinemaMode: _toggleCinemaMode,
                  onToggleEdit:
                      () => setState(() => _isEditMode = !_isEditMode),
                  isEditMode: _isEditMode,
                ),
              ),

              // Player edit overlay — slides in from right when edit mode active
              if (_isEditMode)
                Positioned.fill(
                  child: PlayerEditOverlay(
                    player: _player,
                    download: widget.download,
                    onClose: () => setState(() => _isEditMode = false),
                  ),
                ),

              // Preview banner — shown when viewing a file still being downloaded
              if (widget.isPreview)
                _PreviewDownloadBanner(downloadId: widget.download.id),

              // Video info overlay (top-left, synced with controls visibility)
              // Hidden in cinema mode for immersive experience
              if (!isFullscreen &&
                  !isCinemaMode &&
                  ref.watch(showControlsProvider))
                Positioned(
                  top: 60,
                  left: 16,
                  right: 16,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.smMd,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(
                            alpha: AppOpacity.strong,
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          border: Border.all(
                            color: Colors.white.withValues(
                              alpha: AppOpacity.subtle,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: AppOpacity.overlay,
                              ),
                              blurRadius: 24,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.download.filename,
                              style: AppTypography.buttonPrimary.copyWith(
                                color: AppColors.darkLightText,
                                fontWeight: AppTypography.semiBold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const Gap.xs(),
                            Text(
                              FileUtils.formatBytes(widget.download.totalBytes),
                              style: AppTypography.statusBadge.copyWith(
                                color: AppColors.darkMetaText,
                                fontWeight: AppTypography.medium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Cinema Mode floating timestamp (bottom-left, always visible in cinema mode)
              if (isCinemaMode)
                Positioned(
                  bottom: 16,
                  left: 16,
                  child: AnimatedOpacity(
                    opacity: ref.watch(showControlsProvider) ? 0.0 : 0.7,
                    duration: AppTransitions.normal,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(
                            alpha: AppOpacity.overlay,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: StreamBuilder<Duration>(
                          stream: _player.stream.position,
                          builder: (context, snapshot) {
                            final pos = snapshot.data ?? Duration.zero;
                            return Text(
                              Formatters.formatDuration(pos),
                              style: AppTypography.statusBadge.copyWith(
                                color: AppColors.darkMetaText,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w400,
                                letterSpacing: 0,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),

              // On-screen visual feedback overlay (center)
              if (_currentFeedback != null)
                Center(
                  child: OnScreenFeedback(
                    key: ValueKey(_feedbackKey),
                    data: _currentFeedback!,
                    onComplete: () {
                      if (mounted) setState(() => _currentFeedback = null);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Amber banner shown at the top of [VideoPlayerScreen] when [VideoPlayerScreen.isPreview]
/// is true. Reads live download progress from [downloadsNotifierProvider] and shows
/// a [LinearProgressIndicator] that updates as the file is written.
class _PreviewDownloadBanner extends ConsumerWidget {
  final int downloadId;

  const _PreviewDownloadBanner({required this.downloadId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(
      downloadsNotifierProvider.select((s) => s.downloads),
    );
    final download = downloads.where((d) => d.id == downloadId).firstOrNull;
    final progress = download?.progress ?? 0.0;
    final percent = (progress * 100).round();

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.homeDarkCardBg.withValues(
                alpha: AppOpacity.nearOpaque,
              ),
              border: Border(
                bottom: BorderSide(
                  color: AppColors.accentHighlight.withValues(
                    alpha: AppOpacity.secondary,
                  ),
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.sm,
              horizontal: AppSpacing.smMd,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.download_rounded,
                  size: 16,
                  color: AppColors.accentHighlight,
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    progress > 0
                        ? AppLocalizations.playerPreviewBannerLabel(percent)
                        : AppLocalizations.playerPreviewBannerNoProgress,
                    style: AppTypography.buttonPrimary.copyWith(
                      color: AppColors.darkLightText,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (progress > 0)
            LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.brand.withValues(
                alpha: AppOpacity.scrim,
              ),
              color: AppColors.accentHighlight,
              minHeight: 3,
            ),
        ],
      ),
    );
  }
}
