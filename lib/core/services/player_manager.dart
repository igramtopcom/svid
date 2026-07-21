import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import '../logging/app_logger.dart';

/// Global Player Manager
/// Manages all active player instances to prevent memory leaks and resource conflicts
/// Implements auto-pause policy: only one player can be actively playing at a time
class PlayerManager {
  // Singleton instance
  static final PlayerManager _instance = PlayerManager._internal();
  factory PlayerManager() => _instance;
  PlayerManager._internal();

  // Track all active players
  final Map<String, Player> _activePlayers = {};
  final Map<String, StreamSubscription<bool>> _playerSubscriptions = {};
  Player? _currentlyPlayingPlayer;

  /// When true, audio players keep playing when the window loses focus.
  bool backgroundAudioEnabled = true;

  // Track window focus state
  bool _windowBlurred = false;

  // Auto-dispose timers: player ID → Timer (fires after 5min paused+backgrounded)
  final Map<String, Timer> _autoDisposeTimers = {};

  // Preloaded player for gapless queue transitions
  Player? _preloadedPlayer;
  String? _preloadedPath;

  // Auto-dispose delay — exposed @visibleForTesting to allow fast tests
  @visibleForTesting
  Duration autoDisposeDelay = const Duration(minutes: 5);

  String? _playerIdFor(Player player) {
    for (final entry in _activePlayers.entries) {
      if (identical(entry.value, player)) {
        return entry.key;
      }
    }
    return null;
  }

  void _disposePlayerSafely(
    Player player, {
    required String id,
    required String reason,
  }) {
    try {
      unawaited(_guardPlayerDispose(player.dispose(), id: id, reason: reason));
    } catch (error) {
      _logPlayerDisposeError(error, id: id, reason: reason);
    }
  }

  Future<void> _guardPlayerDispose(
    Future<void> disposeFuture, {
    required String id,
    required String reason,
  }) async {
    try {
      await disposeFuture;
    } catch (error) {
      _logPlayerDisposeError(error, id: id, reason: reason);
    }
  }

  void _logPlayerDisposeError(
    Object error, {
    required String id,
    required String reason,
  }) {
    if (_isDisposedPlayerError(error)) {
      appLogger.debug('Player $id was already disposed during $reason');
      return;
    }

    appLogger.warning('Cannot dispose player $id during $reason: $error');
  }

  bool _isDisposedPlayerError(Object error) {
    final message = error.toString();
    return message.contains('[Player] has been disposed') ||
        message.contains('Player has been disposed');
  }

  void _forgetPlayer(String id, Player player) {
    if (identical(_activePlayers[id], player)) {
      _activePlayers.remove(id);
    }
    _playerSubscriptions.remove(id)?.cancel();
    _autoDisposeTimers.remove(id)?.cancel();
    if (_currentlyPlayingPlayer == player) {
      _currentlyPlayingPlayer = null;
    }
  }

  void _handlePlayerStreamError(String id, Player player, Object error) {
    if (_isDisposedPlayerError(error)) {
      appLogger.debug('Player $id stream closed after disposal');
    } else {
      appLogger.warning('Player $id stream error: $error');
    }
    _forgetPlayer(id, player);
  }

  // --- Player type helpers ---

  /// Returns true if [id] belongs to an audio player (not video).
  static bool isAudioPlayer(String id) =>
      id.startsWith('audio_') || id.startsWith('mini_audio_');

  /// Returns true if [id] belongs to a video player with a GPU-backed surface.
  static bool isVideoPlayer(String id) =>
      id.startsWith('video_') ||
      id.startsWith('pip_video_') ||
      id.startsWith('mini_video_');

  /// Register a new player instance
  /// Auto-pauses currently playing player if policy enabled
  void registerPlayer(String id, Player player, {bool autoPause = true}) {
    // Cancel any pending auto-dispose for this ID
    _autoDisposeTimers[id]?.cancel();
    _autoDisposeTimers.remove(id);

    // Dispose old player with same ID if exists
    if (_activePlayers.containsKey(id)) {
      final oldPlayer = _activePlayers[id];
      appLogger.warning(
        'Player with ID "$id" already exists, disposing old instance',
      );

      // Cancel old subscription
      _playerSubscriptions[id]?.cancel();
      _playerSubscriptions.remove(id);

      if (oldPlayer != null) {
        if (_currentlyPlayingPlayer == oldPlayer) {
          _currentlyPlayingPlayer = null;
        }
        _disposePlayerSafely(
          oldPlayer,
          id: id,
          reason: 'registerPlayer replacement',
        );
      }
    }

    // Register new player
    _activePlayers[id] = player;
    appLogger.debug('Registered player: $id (total: ${_activePlayers.length})');

    // Setup listener for play events
    if (autoPause) {
      final subscription = player.stream.playing.listen(
        (isPlaying) {
          if (isPlaying) {
            _handlePlayerStarted(id, player);
            // Cancel auto-dispose timer — player resumed
            _autoDisposeTimers[id]?.cancel();
            _autoDisposeTimers.remove(id);
          } else if (_windowBlurred) {
            // Player paused while window is blurred → start auto-dispose timer
            _startAutoDisposeTimer(id);
          }
        },
        onError: (Object error) => _handlePlayerStreamError(id, player, error),
      );
      _playerSubscriptions[id] = subscription;
    }
  }

  /// Handle when a player starts playing
  /// Auto-pauses other players based on policy
  void _handlePlayerStarted(String id, Player player) {
    if (_currentlyPlayingPlayer != null && _currentlyPlayingPlayer != player) {
      final previousPlayer = _currentlyPlayingPlayer!;
      final previousId = _playerIdFor(previousPlayer);
      appLogger.info('Auto-pausing previous player (new player: $id)');
      unawaited(
        previousPlayer.pause().catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          appLogger.warning(
            'Cannot auto-pause player ${previousId ?? '<unknown>'} (likely disposed): $error',
          );
          if (previousId != null) {
            _forgetPlayer(previousId, previousPlayer);
          } else if (_currentlyPlayingPlayer == previousPlayer) {
            _currentlyPlayingPlayer = null;
          }
        }),
      );
    }
    _currentlyPlayingPlayer = player;
  }

  /// Unregister and dispose a player
  void unregisterPlayer(String id, {bool dispose = true}) {
    // Cancel any pending auto-dispose timer
    _autoDisposeTimers[id]?.cancel();
    _autoDisposeTimers.remove(id);

    final player = _activePlayers.remove(id);

    // Cancel subscription
    _playerSubscriptions[id]?.cancel();
    _playerSubscriptions.remove(id);

    if (player != null) {
      if (_currentlyPlayingPlayer == player) {
        _currentlyPlayingPlayer = null;
      }
      if (dispose) {
        _disposePlayerSafely(player, id: id, reason: 'unregisterPlayer');
        appLogger.debug('Unregistered and disposed player: $id');
      } else {
        appLogger.debug('Unregistered player: $id (not disposed)');
      }
    }
  }

  /// Get player by ID
  Player? getPlayer(String id) {
    return _activePlayers[id];
  }

  /// Check if player exists
  bool hasPlayer(String id) {
    return _activePlayers.containsKey(id);
  }

  /// Pause all players (skip disposed ones)
  Future<void> pauseAll() async {
    appLogger.info('Pausing all players (${_activePlayers.length})');

    // Create copy to avoid concurrent modification
    final playersCopy = Map<String, Player>.from(_activePlayers);

    for (final entry in playersCopy.entries) {
      try {
        // Try to pause player - will throw if disposed
        await entry.value.pause();
      } catch (e) {
        // Player is disposed or error occurred
        appLogger.warning(
          'Cannot pause player ${entry.key} (likely disposed): $e',
        );
        // Remove problematic player from registry
        _forgetPlayer(entry.key, entry.value);
      }
    }
    _currentlyPlayingPlayer = null;
  }

  /// Pause video players only.
  ///
  /// Used before Windows suspend/background transitions to reduce
  /// DirectComposition/media_kit activity while preserving background audio.
  Future<void> pauseVideoPlayers({String reason = 'video-only pause'}) async {
    final playersCopy = Map<String, Player>.from(_activePlayers);
    final videoPlayers =
        playersCopy.entries.where((entry) => isVideoPlayer(entry.key)).toList();

    if (videoPlayers.isEmpty) return;

    appLogger.info(
      'Pausing ${videoPlayers.length} video player(s) for $reason',
    );

    for (final entry in videoPlayers) {
      try {
        await entry.value.pause();
      } catch (e) {
        appLogger.warning('Cannot pause video player ${entry.key}: $e');
        _forgetPlayer(entry.key, entry.value);
      }
    }

    if (_currentlyPlayingPlayer != null &&
        videoPlayers.any(
          (entry) => identical(entry.value, _currentlyPlayingPlayer),
        )) {
      _currentlyPlayingPlayer = null;
    }
  }

  /// Dispose all players
  void disposeAll() {
    appLogger.info('Disposing all players (${_activePlayers.length})');

    // Cancel all auto-dispose timers
    for (final timer in _autoDisposeTimers.values) {
      try {
        timer.cancel();
      } catch (e) {
        appLogger.warning('Error canceling auto-dispose timer: $e');
      }
    }
    _autoDisposeTimers.clear();

    // Cancel all subscriptions first
    for (final subscription in _playerSubscriptions.values) {
      try {
        subscription.cancel();
      } catch (e) {
        appLogger.warning('Error canceling subscription: $e');
      }
    }
    _playerSubscriptions.clear();

    // Dispose all players
    for (final entry in _activePlayers.entries) {
      appLogger.debug('Disposing player: ${entry.key}');
      _disposePlayerSafely(entry.value, id: entry.key, reason: 'disposeAll');
    }

    _activePlayers.clear();
    _currentlyPlayingPlayer = null;

    // Dispose preloaded player
    _clearPreloadedPlayer();
  }

  // --- Window focus hooks ---

  /// Called when the app window loses focus.
  ///
  /// Pauses all players only when [backgroundAudioEnabled] is false. Starts
  /// auto-dispose timers for all currently-paused players.
  Future<void> onWindowBlurred() async {
    _windowBlurred = true;
    appLogger.debug(
      'Window blurred — applying background audio policy '
      '(backgroundAudio=$backgroundAudioEnabled)',
    );

    final playersCopy = Map<String, Player>.from(_activePlayers);
    for (final entry in playersCopy.entries) {
      if (!backgroundAudioEnabled) {
        try {
          await entry.value.pause();
        } catch (e) {
          appLogger.warning('Cannot pause player ${entry.key}: $e');
          _activePlayers.remove(entry.key);
        }
      }
    }

    // Start auto-dispose timers for all registered players
    for (final id in _activePlayers.keys.toList()) {
      _startAutoDisposeTimer(id);
    }
  }

  /// Called when the app window regains focus.
  ///
  /// Cancels all pending auto-dispose timers so backgrounded players are not
  /// disposed immediately when the user returns to the app.
  void onWindowFocused() {
    _windowBlurred = false;
    appLogger.debug(
      'Window focused — cancelling ${_autoDisposeTimers.length} auto-dispose timers',
    );
    for (final timer in _autoDisposeTimers.values) {
      timer.cancel();
    }
    _autoDisposeTimers.clear();
  }

  void _startAutoDisposeTimer(String id) {
    _autoDisposeTimers[id]?.cancel();
    _autoDisposeTimers[id] = Timer(autoDisposeDelay, () {
      appLogger.info(
        'Auto-disposing player $id (backgrounded >${autoDisposeDelay.inMinutes}min while paused)',
      );
      _autoDisposeTimers.remove(id);
      unregisterPlayer(id);
    });
  }

  // --- Queue preloading ---

  /// Pre-initialize the next track's player for gapless queue transitions.
  ///
  /// Opens [filePath] in a new [Player] without starting playback. Caller
  /// should invoke [takePreloadedPlayer] when the current track ends to swap
  /// in the pre-initialized player.
  void preloadMedia(String filePath) {
    if (_preloadedPath == filePath) return; // already preloaded
    _clearPreloadedPlayer();
    final player = Player();
    _preloadedPlayer = player;
    _preloadedPath = filePath;
    unawaited(_openPreloadedPlayer(player, filePath));
  }

  Future<void> _openPreloadedPlayer(Player player, String filePath) async {
    try {
      await player.open(Media(filePath), play: false);
      if (identical(_preloadedPlayer, player) && _preloadedPath == filePath) {
        appLogger.debug('Preloaded media: $filePath');
      }
    } catch (error) {
      if (!_isDisposedPlayerError(error)) {
        appLogger.warning('Cannot preload media $filePath: $error');
      }
      if (identical(_preloadedPlayer, player) && _preloadedPath == filePath) {
        _preloadedPlayer = null;
        _preloadedPath = null;
        _disposePlayerSafely(player, id: 'preloaded', reason: 'preload failed');
      }
    }
  }

  /// Take ownership of the preloaded player for [filePath].
  ///
  /// Returns the pre-initialized [Player] if it was preloaded for [filePath],
  /// otherwise returns null. The caller is responsible for disposing the
  /// returned player.
  Player? takePreloadedPlayer(String filePath) {
    if (_preloadedPath != filePath || _preloadedPlayer == null) return null;
    final p = _preloadedPlayer;
    _preloadedPlayer = null;
    _preloadedPath = null;
    appLogger.debug('Swapping in preloaded player for: $filePath');
    return p;
  }

  void _clearPreloadedPlayer() {
    final player = _preloadedPlayer;
    if (player != null) {
      _disposePlayerSafely(player, id: 'preloaded', reason: 'clearPreloaded');
    }
    _preloadedPlayer = null;
    _preloadedPath = null;
  }

  // --- Getters / debug ---

  /// Get count of active players
  int get activePlayerCount => _activePlayers.length;

  /// Get currently playing player
  Player? get currentlyPlayingPlayer => _currentlyPlayingPlayer;

  /// Get all player IDs
  List<String> get playerIds => _activePlayers.keys.toList();

  /// Number of active auto-dispose timers (for testing / diagnostics)
  int get activeAutoDisposeTimerCount => _autoDisposeTimers.length;

  /// Whether a preloaded player is ready for [filePath]
  bool hasPreloadedPlayer(String filePath) =>
      _preloadedPath == filePath && _preloadedPlayer != null;

  /// Print debug info
  void printDebugInfo() {
    appLogger.debug('=== PlayerManager Debug Info ===');
    appLogger.debug('Active players: ${_activePlayers.length}');
    appLogger.debug('Player IDs: ${playerIds.join(', ')}');
    appLogger.debug(
      'Currently playing: ${_currentlyPlayingPlayer != null ? 'Yes' : 'No'}',
    );
    appLogger.debug('Background audio: $backgroundAudioEnabled');
    appLogger.debug('Window blurred: $_windowBlurred');
    appLogger.debug('Auto-dispose timers: ${_autoDisposeTimers.length}');
    appLogger.debug('Preloaded path: $_preloadedPath');
    appLogger.debug('===============================');
  }
}

/// Global instance for easy access
final playerManager = PlayerManager();
