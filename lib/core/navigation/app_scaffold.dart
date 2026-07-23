import 'dart:async';
import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';
import '../binaries/binaries.dart';
import '../core.dart';
import '../services/network_monitor_service.dart';
import '../services/window_service.dart';
import '../services/keyboard_service.dart';
import '../services/tray_service.dart';
import '../services/windows_backdrop_service.dart';
import '../services/windows_power_event_service.dart';
import '../../features/assistant/presentation/screens/assistant_screen.dart';
import '../../features/browser/presentation/screens/browser_screen.dart';
import '../../features/browser/presentation/providers/browser_tab_providers.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/home/presentation/screens/downloads_history_screen.dart';
import '../../features/settings/presentation/providers/settings_provider.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/support/presentation/screens/support_screen.dart';
import '../../features/downloads/presentation/providers/downloads_notifier.dart';
import '../../features/downloads/presentation/providers/batch_selection_provider.dart';
import '../../features/downloads/presentation/providers/filter_provider.dart';
import '../../features/downloads/presentation/providers/filtered_downloads_provider.dart';
import '../../features/floating_capture/domain/entities/capture_download_request.dart';
import '../../features/floating_capture/presentation/providers/capture_download_coordinator_provider.dart';
import '../../features/floating_capture/presentation/providers/floating_capture_providers.dart';
import '../../features/floating_capture/presentation/providers/pending_capture_download_provider.dart';
import '../../features/floating_capture/presentation/providers/pending_capture_play_saved_file_provider.dart';
import '../../features/player/domain/services/system_pip_service.dart';
import '../../features/player/domain/services/player_overlay_lifecycle_service.dart';
import '../../features/player/presentation/providers/player_providers.dart';
import '../../features/player/presentation/widgets/mini_player.dart';
import '../../features/player/presentation/widgets/mini_video_player.dart';
import '../../features/player/presentation/widgets/system_pip_view.dart';
import '../../features/player/presentation/screens/video_player_screen.dart';
import '../../features/downloads/domain/entities/download_entity.dart';
import '../../features/home/presentation/widgets/download_list_helpers.dart';
import '../../features/premium/presentation/screens/premium_upgrade_screen.dart';
import '../../features/premium/presentation/providers/premium_providers.dart';
import '../../features/premium/presentation/providers/license_verification_providers.dart';
import '../../features/premium/domain/entities/premium_feature.dart';
import '../../features/downloads/presentation/screens/sorting_rules_screen.dart';
import '../../features/downloads/presentation/screens/collections_screen.dart';
import '../../features/activity_center/presentation/screens/activity_center_screen.dart';
import '../../features/downloads/domain/services/download_scheduler_service.dart';
import '../../features/converter/presentation/screens/forge_screen.dart';
import '../../features/youtube_search/presentation/screens/youtube_explore_screen.dart';
import 'navigation_constants.dart';
import '../../features/downloads/presentation/providers/batch_selection_provider.dart';
import 'left_nav_rail.dart';
import 'right_panel.dart';
import 'right_panel_provider.dart';
import 'window_top_strip.dart';

/// Main application scaffold — Split Panel layout
/// Top nav bar + content area (varies by active tab) + bottom player bar
class AppScaffold extends ConsumerStatefulWidget {
  const AppScaffold({super.key});

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold>
    with WindowListener, WidgetsBindingObserver {
  static const double _rightPanelCompactWidth = 320;
  static const double _rightPanelWideWidth = 360;
  static const double _minMainWidthWithRightPanel = 880;
  static const Duration _capturePopupHideFallbackTimeout = Duration(
    milliseconds: 800,
  );
  static const Duration _premiumEntitlementRefreshInterval = Duration(
    hours: 12,
  );
  static const Duration _premiumLocalExpiryTickInterval = Duration(minutes: 15);

  final GlobalKey<HomeScreenState> _homeScreenKey =
      GlobalKey<HomeScreenState>();
  final DownloadSchedulerService _scheduler = DownloadSchedulerService();
  final PlayerOverlayLifecycleService _overlayLifecycle =
      const PlayerOverlayLifecycleService();
  Timer? _premiumEntitlementRefreshTimer;
  Timer? _premiumLocalExpiryTimer;
  DateTime? _lastPremiumEntitlementRefreshAt;
  bool _premiumEntitlementRefreshInFlight = false;
  bool _browserVisited = false;
  bool _isDragging = false;
  bool _systemPipEntering = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      windowManager.addListener(this);
      _setupKeyboardCallbacks();
      _setupTrayCallbacks();
    }
    if (Platform.isWindows) {
      WindowsPowerEventService.instance.start(
        onEvent: _handleWindowsPowerEvent,
      );
    }

    _setupPlayerStateListeners();
    _setupCaptureDownloadListeners();
    _startDownloadScheduler();
    _startPremiumRefresh();
    _startPremiumEntitlementCadence();
  }

  /// Refresh premium subscription status from the backend on startup.
  /// Only runs for non-free users; throttled to once every 24 h.
  void _startPremiumRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final license = ref.read(premiumLicenseProvider);
      if (license.isPremium) {
        final vs = ref.read(licenseVerificationServiceProvider);
        final prefs = ref.read(sharedPreferencesProvider);
        ref
            .read(premiumLicenseProvider.notifier)
            .refreshLicense(
              verificationService: vs,
              prefs: prefs,
              quotaNotifier: ref.read(downloadQuotaNotifierProvider.notifier),
            );
      }
    });
  }

  void _startPremiumEntitlementCadence() {
    _premiumEntitlementRefreshTimer?.cancel();
    _premiumEntitlementRefreshTimer = Timer.periodic(
      _premiumEntitlementRefreshInterval,
      (_) => unawaited(_refreshPremiumEntitlement(reason: 'periodic')),
    );

    _premiumLocalExpiryTimer?.cancel();
    _premiumLocalExpiryTimer = Timer.periodic(
      _premiumLocalExpiryTickInterval,
      (_) => _invalidateLocalPremiumEntitlement(),
    );
  }

  Future<void> _refreshPremiumEntitlement({required String reason}) async {
    if (!mounted || _premiumEntitlementRefreshInFlight) return;
    final license = ref.read(premiumLicenseProvider);
    if (!license.isPremium) return;

    final now = DateTime.now();
    final last = _lastPremiumEntitlementRefreshAt;
    if (last != null &&
        now.difference(last) < _premiumEntitlementRefreshInterval) {
      return;
    }

    _premiumEntitlementRefreshInFlight = true;
    _lastPremiumEntitlementRefreshAt = now;
    try {
      appLogger.info('Running premium entitlement refresh ($reason)');
      await ref
          .read(premiumLicenseProvider.notifier)
          .refreshLicense(
            verificationService: ref.read(licenseVerificationServiceProvider),
            prefs: ref.read(sharedPreferencesProvider),
            quotaNotifier: ref.read(downloadQuotaNotifierProvider.notifier),
            now: now,
            ignoreCooldown: true,
          );
    } catch (e) {
      appLogger.debug('Premium entitlement refresh failed ($reason): $e');
    } finally {
      _premiumEntitlementRefreshInFlight = false;
      _invalidateLocalPremiumEntitlement();
    }
  }

  void _invalidateLocalPremiumEntitlement() {
    if (!mounted) return;
    ref.invalidate(isPremiumProvider);
    for (final feature in PremiumFeature.values) {
      ref.invalidate(premiumFeatureProvider(feature));
    }
  }

  void _startDownloadScheduler() {
    _scheduler.start(() {
      if (mounted) {
        ref
            .read(downloadsNotifierProvider.notifier)
            .checkAndStartScheduledDownloads();
      }
    });
  }

  void _setupPlayerStateListeners() {
    ref.listenManual(miniPlayerStateProvider, (previous, next) {
      if (previous != null && next != null && next.player != previous.player) {
        appLogger.info(
          'Disposing previous audio mini player after overlay replacement',
        );
        _overlayLifecycle.disposeReplacedAudioAfterFrame(
          downloadId: previous.downloadId,
          scheduleAfterFrame: _scheduleAfterFrame,
          unregisterPlayer: playerManager.unregisterPlayer,
        );
      }
    });

    ref.listenManual(miniVideoPlayerStateProvider, (previous, next) {
      if (previous != null && next != null && next.player != previous.player) {
        appLogger.info(
          'Disposing previous video PiP player after overlay replacement',
        );
        _overlayLifecycle.disposeReplacedVideoAfterFrame(
          downloadId: previous.downloadId,
          scheduleAfterFrame: _scheduleAfterFrame,
          unregisterPlayer: playerManager.unregisterPlayer,
        );
      }
    });
  }

  void _setupCaptureDownloadListeners() {
    ref.listenManual<CaptureDownloadRequest?>(pendingCaptureDownloadProvider, (
      _,
      next,
    ) {
      if (next == null) return;
      ref.read(pendingCaptureDownloadProvider.notifier).state = null;
      unawaited(_handleCaptureDownloadRequest(next));
    }, fireImmediately: true);

    ref.listenManual<String?>(pendingCapturePlaySavedFileProvider, (_, next) {
      if (next == null || next.isEmpty) return;
      ref.read(pendingCapturePlaySavedFileProvider.notifier).state = null;
      unawaited(_handleCapturePlaySavedFile(next));
    }, fireImmediately: true);

    ref.listenManual<DownloadsState>(downloadsNotifierProvider, (
      previous,
      next,
    ) {
      ref
          .read(captureDownloadCoordinatorProvider)
          .handleDownloadsStateChange(previous, next);
    });
  }

  void _scheduleAfterFrame(VoidCallback callback) {
    WidgetsBinding.instance.addPostFrameCallback((_) => callback());
  }

  Future<void> _waitForOverlayUnmount() async {
    await Future<void>.delayed(Duration.zero);
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<HomeScreenState?> _waitForHomeScreenState() async {
    for (var i = 0; i < 3; i++) {
      final state = _homeScreenKey.currentState;
      if (state != null) return state;
      await WidgetsBinding.instance.endOfFrame;
    }
    return _homeScreenKey.currentState;
  }

  Future<void> _handleCaptureDownloadRequest(
    CaptureDownloadRequest request,
  ) async {
    // Floating capture primary action should stay out-of-app whenever the
    // request can be resolved from app-level services. Only fall back to the
    // visible Home UI for explicit "Options" / manual-choice paths.
    if (request.directDownload) {
      final handled = await ref
          .read(captureDownloadCoordinatorProvider)
          .tryStartDirectDownload(request);
      if (handled) return;
    }

    await _routeCaptureDownloadToHome(request);
  }

  Future<void> _routeCaptureDownloadToHome(
    CaptureDownloadRequest request,
  ) async {
    // Once we need the main Home UI, the popup must retreat so it does not
    // cover the download dialog or fight the user's focus.
    try {
      await ref
          .read(floatingWindowProvider)
          .hide()
          .timeout(_capturePopupHideFallbackTimeout);
    } catch (e, s) {
      appLogger.warning('[Capture] hide popup before UI fallback failed', e, s);
    }

    if (SystemPipService.isActive) {
      await SystemPipService.exit();
      if (mounted) setState(() {});
    }

    try {
      await WindowService.show();
    } catch (e, s) {
      appLogger.warning('[Capture] focus main window failed', e, s);
    }

    _navigateToHome();
    final homeState = await _waitForHomeScreenState();
    if (homeState == null) {
      appLogger.warning(
        '[Capture] HomeScreen not mounted for download request',
      );
      return;
    }
    await homeState.handleCaptureDownloadRequest(request);
  }

  Future<void> _handleCapturePlaySavedFile(String path) async {
    final download = _findDownloadBySavedPath(path);
    if (download == null) {
      appLogger.warning(
        '[Capture] PlaySavedFile had no matching download: $path',
      );
      return;
    }

    final fullPath = p.join(download.savePath, download.filename);
    if (!File(fullPath).existsSync()) {
      ref
          .read(downloadsNotifierProvider.notifier)
          .revalidateFile(download.id, download.savePath, download.filename);
      appLogger.warning('[Capture] PlaySavedFile target missing: $fullPath');
      return;
    }

    try {
      await WindowService.show();
    } catch (e, s) {
      appLogger.warning('[Capture] focus main window for Play failed', e, s);
    }

    if (SystemPipService.isActive) {
      await SystemPipService.exit();
      if (mounted) setState(() {});
    }
    if (!mounted) return;

    final windowSize = MediaQuery.maybeOf(context)?.size;
    final panelWidth =
        (windowSize?.width ?? 0) >= 1500
            ? _rightPanelWideWidth
            : _rightPanelCompactWidth;
    final canShowRightPanel =
        windowSize != null &&
        windowSize.width >= panelWidth + _minMainWidthWithRightPanel;

    ref.read(batchSelectionProvider.notifier).state = const <int>{};
    ref
        .read(navigationProvider.notifier)
        .navigateToTab(NavigationConstants.homeIndex);

    if (canShowRightPanel) {
      ref.read(rightPanelProvider.notifier).showDetail(download);
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openFullscreenPlayer(download);
    });
  }

  DownloadEntity? _findDownloadBySavedPath(String path) {
    final target = p.normalize(path);
    for (final download in ref.read(downloadsNotifierProvider).downloads) {
      final candidate = p.normalize(
        p.join(download.savePath, download.filename),
      );
      if (p.equals(candidate, target)) return download;
    }
    return null;
  }

  void _openFullscreenPlayer(DownloadEntity download) {
    // openPlayerForDownload seeds the queue internally; do not double-seed.
    openPlayerForDownload(context, ref, download);
  }

  Future<void> _closeMiniAudioPlayer(MiniPlayerState state) {
    _saveOverlayResumePoint(
      player: state.player,
      downloadEntity: state.downloadEntity,
      downloadId: state.downloadId,
    );
    return _overlayLifecycle.closeAudioOverlay(
      downloadId: state.downloadId,
      clearState: () => ref.read(miniPlayerStateProvider.notifier).state = null,
      waitForOverlayUnmount: _waitForOverlayUnmount,
      unregisterPlayer: playerManager.unregisterPlayer,
    );
  }

  Future<void> _closeMiniVideoPlayer(MiniVideoPlayerState state) {
    _saveOverlayResumePoint(
      player: state.player,
      downloadEntity: state.downloadEntity,
      downloadId: state.downloadId,
    );
    return _overlayLifecycle.closeVideoOverlay(
      downloadId: state.downloadId,
      systemPipActive: SystemPipService.isActive,
      clearState:
          () => ref.read(miniVideoPlayerStateProvider.notifier).state = null,
      waitForOverlayUnmount: _waitForOverlayUnmount,
      exitSystemPip: SystemPipService.exit,
      unregisterPlayer: playerManager.unregisterPlayer,
    );
  }

  void _saveOverlayResumePoint({
    required Player player,
    required Object? downloadEntity,
    required String downloadId,
  }) {
    final parsedId = int.tryParse(downloadId);
    final id = downloadEntity is DownloadEntity ? downloadEntity.id : parsedId;
    if (id == null) return;

    try {
      final position = player.state.position;
      final duration = player.state.duration;
      if (duration.inMilliseconds <= 0) return;
      ref
          .read(watchProgressServiceProvider)
          .saveResumePoint(id, position, duration);
    } catch (error) {
      final message = error.toString();
      if (message.contains('[Player] has been disposed') ||
          message.contains('Player has been disposed')) {
        return;
      }
      appLogger.debug('Failed to save overlay resume point: $error');
    }
  }

  @override
  void dispose() {
    _scheduler.stop();
    _premiumEntitlementRefreshTimer?.cancel();
    _premiumLocalExpiryTimer?.cancel();
    if (Platform.isWindows) {
      WindowsPowerEventService.instance.stop();
    }
    WidgetsBinding.instance.removeObserver(this);
    appLogger.info('Disposing all active players on app close');
    playerManager.disposeAll();

    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _handleWindowsPowerEvent(WindowsPowerEvent event) async {
    if (!mounted) return;

    switch (event) {
      case WindowsPowerEvent.suspend:
        await _quiesceWindowsVideoSurfaces('windows suspend');
        break;
      case WindowsPowerEvent.resume:
        // Keep media paused after wake. Auto-resume can be loud/janky and can
        // immediately recreate GPU surfaces while the driver is still settling.
        appLogger.info('Windows resume detected - media remains paused');
        playerManager.onWindowFocused();
        break;
    }
  }

  Future<void> _quiesceWindowsVideoSurfaces(
    String reason, {
    bool closeOverlays = true,
  }) async {
    if (!Platform.isWindows || !mounted) return;

    final stopwatch = Stopwatch()..start();
    appLogger.warning(
      'Quiescing Windows video/DirectComposition surfaces: $reason',
    );
    try {
      if (closeOverlays) {
        final videoState = ref.read(miniVideoPlayerStateProvider);
        if (videoState != null) {
          await _closeMiniVideoPlayer(videoState);
        } else if (SystemPipService.isActive) {
          await SystemPipService.exit();
        }
      }
      await playerManager.pauseVideoPlayers(reason: reason);
    } catch (e) {
      appLogger.warning('Failed to quiesce Windows video surfaces: $e');
    } finally {
      stopwatch.stop();
      appLogger.info(
        'Windows video surface quiesce completed: reason=$reason '
        'duration_ms=${stopwatch.elapsedMilliseconds} close_overlays=$closeOverlays',
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        appLogger.info('App backgrounded - players continue in their state');
        break;
      case AppLifecycleState.resumed:
        appLogger.info('App resumed - players continue in their state');
        unawaited(_refreshPremiumEntitlement(reason: 'resume'));
        break;
      case AppLifecycleState.detached:
        appLogger.info('App detached - disposing all players');
        playerManager.disposeAll();
        break;
      case AppLifecycleState.hidden:
        // Phase 2D.3 (anh Quân Windows crash 2026-05-12): do NOT quiesce
        // GPU surfaces on lifecycle hidden. AppLifecycleState.hidden fires
        // on Windows whenever the floating capture popup spawns and grabs
        // foreground/visibility focus from the main app. Forcibly tearing
        // down DirectComposition/MediaKit surfaces concurrently with the
        // popup engine init races → access violation → process crash +
        // relaunch loop.
        //
        // Evidence: vidcombo_2026-05-12.log captured 11 cold-starts in
        // 8 minutes; every crash was preceded by the log line
        // "Quiescing Windows video/DirectComposition surfaces: windows
        // lifecycle hidden". macOS does not hit this code path so does
        // not crash.
        //
        // Real OS-level suspend (sleep/hibernate) is a DIFFERENT signal —
        // it arrives via WindowsPowerEvent.suspend (see line ~201) and
        // still quiesces correctly. The lifecycle-hidden path was an
        // over-eager mirror that did more harm than good.
        appLogger.info('App hidden - players continue (Phase 2D.3 fix)');
        break;
    }
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    if (Platform.isWindows) {
      unawaited(
        WindowsBackdropService.instance.syncThemeMode(
          ref.read(themeModeProvider),
        ),
      );
    }
  }

  void _setupKeyboardCallbacks() {
    KeyboardService.onQuitShortcut = () async {
      appLogger.info('Quit requested from keyboard shortcut');
      await WindowService.close();
    };

    // Cmd/Ctrl+W: close browser tab if on browser, else minimize
    KeyboardService.onCloseOrMinimize = () {
      final selectedIndex = ref.read(navigationProvider);
      if (selectedIndex == NavigationConstants.browserIndex) {
        final tabState = ref.read(browserTabsProvider);
        if (tabState.tabCount > 1) {
          final activeTab = tabState.activeTab;
          if (activeTab != null) {
            ref.read(browserTabsProvider.notifier).closeTab(activeTab.id);
            return;
          }
        }
      }
      WindowService.minimize();
    };

    KeyboardService.onSearchShortcut = () {
      appLogger.debug('Search shortcut triggered');
      _focusSearch();
    };
    KeyboardService.onNewDownloadShortcut = () {
      appLogger.debug('New download shortcut triggered');
      _navigateToHome();
    };
    KeyboardService.onSettingsShortcut = () {
      appLogger.debug('Settings shortcut triggered');
      _navigateToSettings();
    };
    KeyboardService.onPasteAndStartShortcut = () {
      appLogger.debug('Paste URL shortcut triggered');
      _navigateToHome();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _homeScreenKey.currentState?.pasteUrlAndStart();
      });
    };
    KeyboardService.onPauseAllShortcut = () {
      appLogger.debug('Pause all shortcut triggered');
      ref.read(downloadsNotifierProvider.notifier).pauseAllDownloads();
    };
    KeyboardService.onResumeAllShortcut = () {
      appLogger.debug('Resume all shortcut triggered');
      ref.read(downloadsNotifierProvider.notifier).resumeAllDownloads();
    };
    KeyboardService.onOpenPlayerShortcut = () {
      appLogger.debug('Open player shortcut triggered');
      _navigateToAllDownloads();
    };
    KeyboardService.onTogglePipShortcut = () {
      appLogger.debug('Toggle PiP shortcut triggered');
      _togglePip();
    };

    // Global shortcuts (system-scope — work even when Svid is in background)
    KeyboardService.onShowAndNewDownload = () {
      appLogger.debug('Global Cmd+Shift+D — show window + new download');
      WindowService.show();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateToHome();
        _homeScreenKey.currentState?.focusUrl();
      });
    };
    KeyboardService.onDownloadFromClipboardGlobal = () async {
      appLogger.debug('Global Cmd+Option+V — download from clipboard');
      _homeScreenKey.currentState?.pasteUrlAndStart();
    };
    KeyboardService.onToggleVisibility = () {
      appLogger.debug('Global Ctrl+Cmd+S — toggle window visibility');
      WindowService.toggle();
    };
  }

  void _togglePip() async {
    final videoState = ref.read(miniVideoPlayerStateProvider);
    if (videoState != null) {
      await _closeMiniVideoPlayer(videoState);
      return;
    }
    final audioState = ref.read(miniPlayerStateProvider);
    if (audioState != null) {
      await _closeMiniAudioPlayer(audioState);
    }
  }

  /// Restore from system PiP back to normal app with in-app PiP overlay.
  /// The video PiP state remains — it just switches from system compact
  /// window to the in-app MiniVideoPlayer overlay.
  void _restoreFromSystemPip() async {
    await SystemPipService.exit();
    if (mounted) setState(() {});
  }

  /// Restore from system PiP and open fullscreen video player.
  /// Transfers player ownership (no dispose) and navigates with expand animation.
  void _openPlayerFromSystemPip(MiniVideoPlayerState state) async {
    final downloadEntity = state.downloadEntity;
    final currentPosition = state.player.state.position;
    final wasPlaying = state.player.state.playing;
    appLogger.info(
      'System PiP → Player: position at ${currentPosition.inSeconds}s',
    );

    // Unregister from PiP ID without disposing (transferring ownership)
    playerManager.unregisterPlayer(
      'pip_video_${state.downloadId}',
      dispose: false,
    );

    // Clear PiP state before restoring window
    ref.read(miniVideoPlayerStateProvider.notifier).state = null;

    // Restore window from compact PiP
    await SystemPipService.exit();

    if (!mounted) return;

    // Navigate to fullscreen player with smooth expand animation
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) => VideoPlayerScreen(
              download: downloadEntity,
              existingPlayer: state.player,
              existingVideoController: state.videoController,
              resumePosition: currentPosition,
              autoPlay: wasPlaying,
            ),
        transitionDuration: AppTransitions.controls,
        reverseTransitionDuration: AppTransitions.slow,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
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

  /// Close system PiP and dispose the player.
  void _closeSystemPip(MiniVideoPlayerState state) async {
    await _closeMiniVideoPlayer(state);
  }

  void _setupTrayCallbacks() {
    final trayService = TrayService();
    trayService.onNewDownload = () {
      appLogger.debug('New download from tray');
      _navigateToHome();
    };
    trayService.onShowDownloads = () {
      appLogger.debug('Show downloads from tray');
      _navigateToAllDownloads();
    };
    trayService.onSettings = () {
      appLogger.debug('Settings from tray');
      _navigateToSettings();
    };
  }

  void _handleDrop(DropDoneDetails details) {
    setState(() => _isDragging = false);
    for (final file in details.files) {
      final path = file.path;

      // URL dropped from browser address bar
      if (path.startsWith('http://') || path.startsWith('https://')) {
        _navigateToHome();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _homeScreenKey.currentState?.setUrlAndStart(path);
        });
        return;
      }

      // .txt file dropped — read URLs and start first one
      if (path.endsWith('.txt')) {
        _handleDroppedTextFile(path);
        return;
      }
    }
  }

  Future<void> _handleDroppedTextFile(String filePath) async {
    try {
      final file = File(filePath);
      final content = await file.readAsString();
      final lines =
          content
              .split('\n')
              .map((l) => l.trim())
              .where((l) => l.startsWith('http://') || l.startsWith('https://'))
              .toList();

      if (lines.isEmpty) return;

      if (lines.length == 1) {
        _navigateToHome();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _homeScreenKey.currentState?.setUrlAndStart(lines.first);
        });
      } else {
        // Multiple URLs — set first one and let user see it
        _navigateToHome();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _homeScreenKey.currentState?.setUrlAndStart(lines.first);
        });
      }
    } catch (e) {
      appLogger.debug('Failed to read dropped text file: $e');
    }
  }

  void _focusSearch() {
    final selectedIndex = ref.read(navigationProvider);
    if (selectedIndex == NavigationConstants.homeIndex) {
      _homeScreenKey.currentState?.focusSearch();
    }
  }

  void _navigateToHome() {
    ref
        .read(navigationProvider.notifier)
        .navigateToTab(NavigationConstants.homeIndex);
    // Focus URL field after navigation completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _homeScreenKey.currentState?.focusUrl();
    });
  }

  void _navigateToAllDownloads() {
    ref.read(filterProvider.notifier).selectTab(FilterTab.all);
    ref.read(navigationProvider.notifier).navigateToTab(1);
  }

  void _navigateToSettings() {
    ref
        .read(navigationProvider.notifier)
        .navigateToTab(NavigationConstants.settingsIndex);
  }

  // WindowListener implementations
  @override
  void onWindowClose() async {
    appLogger.info('Window close requested');
    await WindowService.saveWindowState();
    await windowManager.destroy();
  }

  @override
  void onWindowResize() => WindowService.saveWindowStateDebounced();

  @override
  void onWindowMove() => WindowService.saveWindowStateDebounced();

  @override
  void onWindowMaximize() => WindowService.saveWindowStateDebounced();

  @override
  void onWindowUnmaximize() => WindowService.saveWindowStateDebounced();

  @override
  void onWindowFocus() {
    appLogger.debug('Window focused');
    playerManager.onWindowFocused();
    final settings = ref.read(settingsProvider);
    if (settings.autoClipboardDetection) {
      final selectedIndex = ref.read(navigationProvider);
      if (selectedIndex == NavigationConstants.homeIndex) {
        _homeScreenKey.currentState?.checkClipboardOnWindowFocus();
      }
    }
  }

  @override
  void onWindowBlur() {
    appLogger.debug('Window blurred');
    final settings = ref.read(settingsProvider);
    playerManager.backgroundAudioEnabled = settings.backgroundAudioEnabled;
    playerManager.onWindowBlurred();

    // Auto-compact to system PiP when user switches to another app
    final videoState = ref.read(miniVideoPlayerStateProvider);
    final systemPipOn = ref.read(settingsProvider).systemPipEnabled;
    if (videoState != null && systemPipOn && !SystemPipService.isActive) {
      _beginSystemPipEntry();
    }
  }

  void _beginSystemPipEntry() {
    if (_systemPipEntering) return;
    setState(() => _systemPipEntering = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        SystemPipService.enter().whenComplete(() {
          if (mounted) setState(() => _systemPipEntering = false);
        }),
      );
    });
  }

  @override
  void onWindowMinimize() => appLogger.debug('Window minimized');

  @override
  void onWindowRestore() => appLogger.debug('Window restored');

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(navigationProvider);
    final availableTabs = ref.watch(availableTabsProvider);
    // The right panel is now contextual: it appears only when a download is
    // selected (detail) or several are (multi-select) — not as a persistent
    // Quick-start sidebar.
    final panelState = ref.watch(rightPanelProvider);
    final batchSelection = ref.watch(batchSelectionProvider);
    final panelHasContent =
        batchSelection.isNotEmpty ||
        (panelState.mode == RightPanelMode.detail &&
            panelState.selectedDownload != null);
    final miniPlayerState = ref.watch(miniPlayerStateProvider);
    final miniVideoPlayerState = ref.watch(miniVideoPlayerStateProvider);

    // System PiP mode: compact always-on-top window showing only the video.
    // Activates when user switches to another app while in-app PiP is active.
    if (miniVideoPlayerState != null &&
        (_systemPipEntering || SystemPipService.isActive)) {
      return SystemPipView(
        player: miniVideoPlayerState.player,
        videoController: miniVideoPlayerState.videoController,
        filename: miniVideoPlayerState.filename,
        onExpand: () => _restoreFromSystemPip(),
        onOpenPlayer: () => _openPlayerFromSystemPip(miniVideoPlayerState),
        onClose: () => _closeSystemPip(miniVideoPlayerState),
      );
    }

    // Ensure browser is created when navigated to programmatically
    if (selectedIndex == NavigationConstants.browserIndex && !_browserVisited) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _browserVisited = true);
      });
    }

    return DropTarget(
      onDragDone: (details) => _handleDrop(details),
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      child: Scaffold(
        body: Stack(
          children: [
            // Main content — full-height left rail + content column.
            Row(
              children: [
                LeftNavRail(
                  selectedIndex: selectedIndex,
                  onDestinationSelected:
                      (index) => _handleNavigationTap(index, ref),
                  expanded:
                      MediaQuery.sizeOf(context).width >=
                      LeftNavRail.expandBreakpoint,
                ),
                Expanded(
                  child: Column(
                    children: [
                      // Slim window strip: drag + window controls.
                      const WindowTopStrip(),

                // yt-dlp update progress indicator (thin bar)
                Consumer(
                  builder: (context, ref, _) {
                    final updateProgress = ref.watch(
                      ytdlpUpdateProgressProvider,
                    );
                    if (updateProgress == null) return const SizedBox.shrink();

                    final cs = Theme.of(context).colorScheme;
                    return SizedBox(
                      height: 18,
                      child: Row(
                        children: [
                          const SizedBox(width: AppSpacing.smMd),
                          Text(
                            AppLocalizations.ytdlpUpdateProgressLabel,
                            style: AppTypography.compact.copyWith(
                              color: cs.onSurface.withValues(
                                alpha: AppOpacity.strong,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: LinearProgressIndicator(
                              value:
                                  updateProgress.progress > 0
                                      ? updateProgress.progress
                                      : null,
                              minHeight: 2,
                              backgroundColor: cs.surfaceContainerHighest,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                cs.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.smMd),
                        ],
                      ),
                    );
                  },
                ),

                // Content area — LayoutBuilder determines right-panel
                // width adaptively. The RightPanel lives OUTSIDE the
                // AnimatedSwitcher so the embedded player survives tab
                // switches (Settings, YouTube, etc.) instead of being
                // disposed and re-created on every navigation.
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final panelWidth =
                          constraints.maxWidth >= 1500
                              ? _rightPanelWideWidth
                              : _rightPanelCompactWidth;
                      final hasSpace =
                          constraints.maxWidth >=
                          panelWidth + _minMainWidthWithRightPanel;
                      final isDownloadTab =
                          selectedIndex == NavigationConstants.homeIndex ||
                          NavigationConstants.isDownloadFilterTab(
                            selectedIndex,
                          );

                      return Row(
                        children: [
                          Expanded(
                            child: Stack(
                              children: [
                                if (selectedIndex !=
                                        NavigationConstants.browserIndex &&
                                    selectedIndex !=
                                        NavigationConstants.homeIndex)
                                  ClipRect(
                                    child: AnimatedSwitcher(
                                      duration: AppTransitions.normal,
                                      switchInCurve: AppTransitions.curveEnter,
                                      switchOutCurve: AppTransitions.curveExit,
                                      transitionBuilder: _buildTransition,
                                      child: KeyedSubtree(
                                        key: ValueKey<int>(selectedIndex),
                                        child: _buildScreen(
                                          selectedIndex,
                                          availableTabs,
                                        ),
                                      ),
                                    ),
                                  ),
                                // Home persists offstage (like Browser) so its
                                // download flow (extract → picker → dispatch)
                                // stays callable from any tab — e.g. the Explore
                                // "Download" opens the picker in place instead
                                // of switching to the Home tab. It's already the
                                // default tab, so this doesn't change when it
                                // first mounts.
                                Offstage(
                                  offstage:
                                      selectedIndex !=
                                      NavigationConstants.homeIndex,
                                  child: HomeScreen(key: _homeScreenKey),
                                ),
                                if (_browserVisited)
                                  Offstage(
                                    offstage:
                                        selectedIndex !=
                                        NavigationConstants.browserIndex,
                                    child: const BrowserScreen(),
                                  ),
                              ],
                            ),
                          ),
                          Visibility(
                            visible:
                                isDownloadTab && hasSpace && panelHasContent,
                            maintainState: true,
                            maintainAnimation: true,
                            maintainSize: false,
                            child: SizedBox(
                              width: panelWidth,
                              child: RightPanel(
                                onDownloadUrl: (url) {
                                  _homeScreenKey.currentState?.setUrlAndStart(
                                    url,
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                    ],
                  ),
                ),
              ],
            ),

            // Floating Mini Audio Player (PiP)
            if (miniPlayerState != null)
              MiniPlayer(
                player: miniPlayerState.player,
                filename: miniPlayerState.filename,
                thumbnail: miniPlayerState.thumbnail,
                onClose: () {
                  unawaited(_closeMiniAudioPlayer(miniPlayerState));
                },
              ),

            // Floating Mini Video Player (in-app PiP overlay)
            if (miniVideoPlayerState != null)
              MiniVideoPlayer(
                player: miniVideoPlayerState.player,
                videoController: miniVideoPlayerState.videoController,
                filename: miniVideoPlayerState.filename,
                onClose: () {
                  unawaited(_closeMiniVideoPlayer(miniVideoPlayerState));
                },
              ),

            // Binary health banner
            Consumer(
              builder: (context, ref, _) {
                final missingBinaries = ref.watch(missingBinariesProvider);
                return missingBinaries.when(
                  data: (missing) {
                    if (missing.isEmpty) return const SizedBox.shrink();
                    final names = missing.map((b) => b.displayName).join(', ');
                    return Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Material(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          color: Theme.of(context).colorScheme.errorContainer,
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 16,
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onErrorContainer,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  AppLocalizations.binaryMissing(names),
                                  style: AppTypography.buttonSecondary.copyWith(
                                    color:
                                        Theme.of(
                                          context,
                                        ).colorScheme.onErrorContainer,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
            ),

            // Offline banner
            Consumer(
              builder: (context, ref, _) {
                final isOnline = ref.watch(isOnlineProvider);
                return isOnline.when(
                  data: (online) {
                    if (online) return const SizedBox.shrink();
                    return Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Material(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          color: Theme.of(context).colorScheme.error,
                          child: Row(
                            children: [
                              Icon(
                                Icons.wifi_off,
                                size: 16,
                                color: Theme.of(context).colorScheme.onError,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                AppLocalizations.offlineBanner,
                                style: AppTypography.buttonSecondary.copyWith(
                                  color: Theme.of(context).colorScheme.onError,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
            ),

            // Premium expiry warning banner
            Consumer(
              builder: (context, ref, _) {
                final license = ref.watch(premiumLicenseProvider);
                if (!license.isPremium) return const SizedBox.shrink();
                if (license.billingCycle?.isLifetime ?? false) {
                  return const SizedBox.shrink();
                }

                final daysLeft = license.daysRemaining;
                // No expiry date = perpetual or metadata not yet synced — skip warning
                if (daysLeft < 0) return const SizedBox.shrink();
                // Show warning when <= 7 days remain, or if expired but in grace period
                if (daysLeft > 7 && !license.isExpired) {
                  return const SizedBox.shrink();
                }

                final isExpired = license.isExpired;
                final cs = Theme.of(context).colorScheme;
                final warningColor = isExpired ? cs.error : Colors.orange;
                final message =
                    isExpired
                        ? 'Your premium subscription has expired. Renew to keep premium features.'
                        : 'Your subscription expires in $daysLeft day${daysLeft == 1 ? '' : 's'}. Renew to avoid interruption.';

                return Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Material(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.smMd,
                      ),
                      color:
                          isExpired ? cs.errorContainer : Colors.orange.shade50,
                      child: Row(
                        children: [
                          Icon(
                            isExpired
                                ? Icons.error_outline
                                : Icons.warning_amber_rounded,
                            size: 18,
                            color: warningColor,
                          ),
                          const SizedBox(width: AppSpacing.smMd),
                          Expanded(
                            child: Text(
                              message,
                              style: AppTypography.buttonSecondary.copyWith(
                                color:
                                    isExpired
                                        ? cs.onErrorContainer
                                        : Colors.orange.shade900,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          TextButton(
                            onPressed: () {
                              ref
                                  .read(navigationProvider.notifier)
                                  .navigateToTab(
                                    NavigationConstants.premiumIndex,
                                  );
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: warningColor,
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.smMd,
                                vertical: AppSpacing.sm,
                              ),
                            ),
                            child: Text(
                              'Renew',
                              style: AppTypography.buttonPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            // Drag & drop overlay
            if (_isDragging)
              Container(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: AppOpacity.pressed),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxl,
                      vertical: AppSpacing.xl,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primary
                              .withValues(alpha: AppOpacity.quarter),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.file_download_rounded,
                          size: 48,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: AppSpacing.smMd),
                        Text(
                          AppLocalizations.dragDropHint,
                          style: Theme.of(
                            context,
                          ).textTheme.titleMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScreen(int index, List<FilterTab> availableTabs) {
    // Wrap in opaque Material to prevent partially-visible old screens
    // from showing through during AnimatedSwitcher transitions
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: _buildScreenContent(index, availableTabs),
    );
  }

  Widget _buildScreenContent(int index, List<FilterTab> availableTabs) {
    // Downloads tab — main content only; the persistent RightPanel
    // is mounted at scaffold level (outside AnimatedSwitcher) so the
    // embedded player survives tab switches.
    if (index == NavigationConstants.homeIndex) {
      return HomeScreen(key: _homeScreenKey);
    }

    // Explore tab — inline YouTube discovery + search.
    if (index == NavigationConstants.youtubeIndex ||
        index == NavigationConstants.subscriptionsIndex) {
      return YouTubeExploreScreen(
        // Download in place: HomeScreen is mounted offstage, so its flow runs
        // here and the QuickDownloadSheet (when the user is on "Ask first") is
        // a modal over the whole app — it appears over Explore without a tab
        // switch. A saved preset auto-downloads in place, honoring the same
        // "Default download" setting as the Home tab.
        onVideoDownload: (url) {
          _homeScreenKey.currentState?.setUrlAndStart(url);
        },
      );
    }

    // Settings
    if (index == NavigationConstants.settingsIndex) {
      return const SettingsScreen();
    }

    // Support center — all brands use Go backend for operational services
    if (index == NavigationConstants.supportIndex) {
      return const SupportScreen();
    }

    // AI assistant — all brands use Go backend for AI features
    if (index == NavigationConstants.assistantIndex) {
      return const AssistantScreen();
    }

    // In-app browser — rendered via Offstage in build(), this is a fallback
    if (index == NavigationConstants.browserIndex) {
      return const SizedBox.shrink();
    }

    // Premium upgrade
    if (index == NavigationConstants.premiumIndex) {
      return const PremiumUpgradeScreen();
    }

    // Sorting rules
    if (index == NavigationConstants.sortingRulesIndex) {
      return const SortingRulesScreen();
    }

    // Collections
    if (index == NavigationConstants.collectionsIndex) {
      return const CollectionsScreen();
    }

    // Activity Center
    if (index == NavigationConstants.activityCenterIndex) {
      return const ActivityCenterScreen();
    }

    // The Forge — converter + editor
    if (index == NavigationConstants.converterIndex) {
      return const ForgeScreen();
    }

    // All other indices (1-999) are filter tabs — main content only;
    // persistent RightPanel is at scaffold level.
    return const DownloadsHistoryScreen();
  }

  void _handleNavigationTap(int index, WidgetRef ref) {
    if (index == NavigationConstants.browserIndex && !_browserVisited) {
      setState(() => _browserVisited = true);
    }
    ref.read(navigationProvider.notifier).navigateToTab(index);
  }

  Widget _buildTransition(Widget child, Animation<double> animation) {
    return AppTransitions.fadeSlideTransition(child, animation);
  }
}
