import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../downloads/data/datasources/ytdlp_datasource.dart';
import '../../../downloads/presentation/providers/download_providers.dart';
import '../../domain/entities/youtube_search_result.dart';
import 'youtube_search_provider.dart';

/// View mode for YouTube Explore tab
enum ExploreMode { discovery, searchResults }

/// Top-level section inside the unified Explore surface.
enum ExploreSection { discovery, subscriptions }

/// State for the YouTube Explore screen
class YouTubeExploreState {
  final ExploreMode mode;
  final ExploreSection section;
  final YouTubeSearchResult? selectedVideo;
  final YtDlpVideoInfo? videoDetail;
  final bool isLoadingDetail;
  final String? detailError;

  const YouTubeExploreState({
    this.mode = ExploreMode.discovery,
    this.section = ExploreSection.discovery,
    this.selectedVideo,
    this.videoDetail,
    this.isLoadingDetail = false,
    this.detailError,
  });

  YouTubeExploreState copyWith({
    ExploreMode? mode,
    ExploreSection? section,
    YouTubeSearchResult? selectedVideo,
    YtDlpVideoInfo? videoDetail,
    bool? isLoadingDetail,
    String? detailError,
    bool clearSelection = false,
    bool clearDetail = false,
    bool clearError = false,
  }) {
    return YouTubeExploreState(
      mode: mode ?? this.mode,
      section: section ?? this.section,
      selectedVideo:
          clearSelection ? null : (selectedVideo ?? this.selectedVideo),
      videoDetail: clearDetail ? null : (videoDetail ?? this.videoDetail),
      isLoadingDetail: isLoadingDetail ?? this.isLoadingDetail,
      detailError: clearError ? null : (detailError ?? this.detailError),
    );
  }
}

/// Notifier for YouTube Explore screen orchestration
class YouTubeExploreNotifier extends StateNotifier<YouTubeExploreState> {
  final Ref _ref;

  YouTubeExploreNotifier(this._ref) : super(const YouTubeExploreState());

  /// Switch to search results mode and trigger search
  void switchToSearch(String query) {
    if (query.trim().isEmpty) return;
    state = state.copyWith(
      mode: ExploreMode.searchResults,
      section: ExploreSection.discovery,
      clearSelection: true,
      clearDetail: true,
      clearError: true,
    );
    _ref.read(youtubeSearchProvider.notifier).search(query);
  }

  /// Return to discovery mode
  void backToDiscovery() {
    state = const YouTubeExploreState();
    _ref.read(youtubeSearchProvider.notifier).clear();
  }

  /// Switch between Explore sections without leaving the unified tab.
  void switchSection(ExploreSection section) {
    if (state.section == section && state.mode == ExploreMode.discovery) return;
    state = state.copyWith(
      mode: ExploreMode.discovery,
      section: section,
      clearSelection: true,
      clearDetail: true,
      clearError: true,
      isLoadingDetail: false,
    );
    _ref.read(youtubeSearchProvider.notifier).clear();
  }

  /// Select a video and lazy-load its full details (formats).
  /// Channels don't need detail extraction.
  void selectVideo(YouTubeSearchResult video) {
    final needsDetail = !video.isChannel;
    state = state.copyWith(
      selectedVideo: video,
      isLoadingDetail: needsDetail,
      clearDetail: true,
      clearError: true,
    );
    if (needsDetail) {
      _loadVideoDetail(video.url);
    }
  }

  /// Clear the selected video
  void clearSelection() {
    state = state.copyWith(
      clearSelection: true,
      clearDetail: true,
      isLoadingDetail: false,
      clearError: true,
    );
  }

  /// YouTube player client fallback chain used when the default
  /// `ios,web` client fails with a user-induced error class
  /// (loginRequired / formatNotAvailable). Mirrors the chain in
  /// `ExtractVideoInfoUseCase._clientChain` so the Explore detail
  /// load recovers from the same SABR / bot-detection conditions
  /// the home pipeline handles. Production telemetry showed
  /// `loginRequired` accounting for ~64% of bug reports — the
  /// home pipeline's chain caught most of these, while the
  /// Explore detail surface fell through to a raw error because
  /// this chain was missing from the Dart provider path.
  ///
  /// `mweb,web` first because Windows smoke showed the default
  /// `ios,web` client failing the bot gate while mweb succeeded
  /// with the same in-app cookies; `tv_embedded` remains last
  /// because it has the most limited catalogue.
  static const _clientChain = [
    'mweb,web',
    'android',
    'android_creator',
    'tv_embedded',
  ];

  /// Per-attempt timeout in seconds. EXACT mirror of
  /// `ExtractVideoInfoUseCase._clientTimeouts` so the two surfaces
  /// share a single tuning surface. Index map:
  ///   [0] ios,web (default)   → 30s
  ///   [1] android             → 45s
  ///   [2] android_creator     → 60s
  ///   [3] tv_embedded         → 90s  (last-resort, slowest API)
  static const _clientTimeouts = [30, 45, 60, 75, 90];

  /// Load full per-video detail for the technical metadata panel.
  ///
  /// History: production telemetry (admin dashboard, 2026-05-12)
  /// showed YouTube `loginRequired` errors at ~64% of all bug
  /// reports. The home download pipeline transparently recovered
  /// most of them via `ExtractVideoInfoUseCase._runFallbackChain`
  /// (multi-client chain + cookies-from-browser retry), while
  /// the Explore detail surface routed through this provider
  /// fell through to a raw `loginRequired` error visible at
  /// `log.md:36`. Anh's office-IP test + Bob's customer report
  /// (Z7Cl... URL Windows 10 v1.6.5) confirm the gap is widely
  /// hit, not isolated.
  ///
  /// The flow below now mirrors the home pipeline's defense
  /// layers AT THE DART PROVIDER LEVEL because the detail panel
  /// consumes raw `YtDlpVideoInfo` (bitrate, vcodec, fps) not
  /// the domain `VideoInfo`. Refactoring the panel to consume
  /// the domain entity is the proper long-term move; for now
  /// this provider replicates the chain so the surface stops
  /// being the weak link.
  ///
  /// Attempt sequence:
  ///   0. default (`ios,web`) client + Settings-configured
  ///      cookies-from-browser (null if user has not configured).
  ///   1. default client + auto-detected cookies-from-browser
  ///      fallback — covers users who haven't visited Settings.
  ///   2. `android` client + same cookies — usually bypasses the
  ///      web-client bot check.
  ///   3. `android_creator` client + same cookies.
  ///   4. `tv_embedded` client + same cookies — last resort,
  ///      lax restrictions but limited formats.
  ///
  /// Any attempt that succeeds short-circuits the rest. Any
  /// attempt that throws an error class outside the recoverable
  /// set (network, timeout, jsRuntimeUnavailable, circuit-breaker
  /// open) short-circuits the rest too — those errors are NOT
  /// helped by a client swap and burning further attempts just
  /// makes the user wait.
  Future<void> _loadVideoDetail(String url) async {
    final datasource = _ref.read(ytdlpDataSourceProvider);
    final cookiesFromBrowser = _ref.read(cookiesFromBrowserProvider);
    final cookiesFromBrowserFallbackChain = _ref.read(
      cookiesFromBrowserFallbackChainProvider,
    );

    YtDlpVideoInfo? info;
    Object? lastError;
    var lastAttemptLabel = 'ios,web (default)';
    // Tracks which browser cookies (if any) ended up succeeding, so
    // the multi-client chain below reuses the same auth context.
    String? cookiesForChain = cookiesFromBrowser;

    // Attempt 0 — default client, primary cookies (or none).
    try {
      info = await datasource.extractInfo(
        url,
        cookiesFromBrowser: cookiesFromBrowser,
        timeoutSecs: _clientTimeouts[0],
      );
    } catch (e) {
      lastError = e;
    }

    // Attempts 1..N — iterate the platform-aware browser fallback
    // chain (Codex round 2 review 2026-05-13). Pre-fix this used a
    // single fallback browser and on Windows would pick locked
    // Chrome first and die. Empty chain (no browser detected) →
    // skipped silently.
    if (info == null && cookiesFromBrowser == null) {
      for (final candidate in cookiesFromBrowserFallbackChain) {
        if (info != null) break;
        if (!_isRecoverableViaBrowserCookies(lastError)) break;
        lastAttemptLabel = 'ios,web + cookies=$candidate';
        debugPrint(
          '🔄 [YouTubeExplore] Retrying detail load with '
          'cookies-from-browser=$candidate after '
          '${lastError.runtimeType}',
        );
        try {
          info = await datasource.extractInfo(
            url,
            cookiesFromBrowser: candidate,
            timeoutSecs: _clientTimeouts[0],
          );
          cookiesForChain = candidate;
          lastError = null;
        } catch (e) {
          lastError = e;
        }
      }
    }

    // Attempts later — multi-client chain. Each attempt uses
    // whichever cookies-from-browser produced the most coverage
    // above (prefer Settings explicit; otherwise the chain candidate
    // that already advanced lastError furthest). We do NOT swap
    // cookies again here — the failing dimension is the client
    // fingerprint, not the authentication.
    for (var i = 0; i < _clientChain.length; i++) {
      if (info != null) break;
      if (!_isRecoverableViaClientSwap(lastError)) break;
      final client = _clientChain[i];
      final timeout =
          _clientTimeouts[i + 1 < _clientTimeouts.length
              ? i + 1
              : _clientTimeouts.length - 1];
      lastAttemptLabel = client;
      debugPrint(
        '🔄 [YouTubeExplore] Switching to player_client=$client '
        '(attempt ${i + 2}/${_clientChain.length + 1}) after '
        '${lastError.runtimeType}',
      );
      try {
        info = await datasource.extractInfo(
          url,
          cookiesFromBrowser: cookiesForChain,
          extractorClient: client,
          timeoutSecs: timeout,
        );
        lastError = null;
      } catch (e) {
        lastError = e;
      }
    }

    // Late-arriving response — user may have clicked another video
    // while we were extracting; only commit state if we are still
    // the active selection.
    if (state.selectedVideo?.url != url) return;

    if (info != null) {
      debugPrint('✅ [YouTubeExplore] Detail loaded via $lastAttemptLabel');
      state = state.copyWith(
        videoDetail: info,
        isLoadingDetail: false,
        clearError: true,
      );
      return;
    }

    debugPrint(
      '❌ [YouTubeExplore] Detail load exhausted '
      'cookies + client chain after $lastAttemptLabel: $lastError',
    );
    state = state.copyWith(
      isLoadingDetail: false,
      detailError: lastError?.toString() ?? 'Unknown error',
    );
  }

  /// True when a cookies-from-browser swap has any chance of
  /// recovering the failure. `loginRequired` and
  /// `formatNotAvailable` are the two user-induced error classes
  /// a fresh browser session can fix (SABR / PO-token / age gate /
  /// region gate via cookies). Network / timeout / runtime
  /// errors are NOT helped by a cookie swap and must surface to
  /// the user as-is.
  @visibleForTesting
  static bool isRecoverableViaBrowserCookies(Object? error) =>
      _isRecoverableViaBrowserCookies(error);

  static bool _isRecoverableViaBrowserCookies(Object? error) {
    if (error is! YtDlpException) return false;
    return error.type == YtDlpErrorType.loginRequired ||
        error.type == YtDlpErrorType.formatNotAvailable;
  }

  /// True when a YouTube player-client swap has any chance of
  /// recovering the failure. Same recoverable set as the cookies
  /// retry (loginRequired / formatNotAvailable) — a different
  /// client surface gives YouTube a different fingerprint to
  /// evaluate, often passing where the web client fails. Network
  /// / timeout / circuit-breaker errors are NOT helped by a
  /// client swap.
  @visibleForTesting
  static bool isRecoverableViaClientSwap(Object? error) =>
      _isRecoverableViaClientSwap(error);

  static bool _isRecoverableViaClientSwap(Object? error) {
    if (error is! YtDlpException) return false;
    return error.type == YtDlpErrorType.loginRequired ||
        error.type == YtDlpErrorType.formatNotAvailable;
  }
}

/// Provider for YouTube Explore state
final youtubeExploreProvider =
    StateNotifierProvider<YouTubeExploreNotifier, YouTubeExploreState>((ref) {
      return YouTubeExploreNotifier(ref);
    });
