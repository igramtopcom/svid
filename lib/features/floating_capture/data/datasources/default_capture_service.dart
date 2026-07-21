import 'dart:async';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/lru_cache.dart';
import '../../../downloads/domain/entities/video_preview.dart';
import '../../domain/entities/capture_download_request.dart';
import '../../domain/entities/floating_window_event.dart';
import '../../domain/entities/snooze_duration.dart';
import '../../domain/entities/snooze_state.dart';
import '../../domain/services/capture_quota_policy.dart';
import '../../domain/services/capture_service.dart';
import '../../domain/services/clipboard_monitor_service.dart';
import '../../domain/services/floating_window.dart';
import '../../domain/services/recent_url_tracker.dart';
import '../../domain/services/snooze_store.dart';
import '../../domain/services/url_pattern_service.dart';

/// Function shape for fetching a preview. Production passes
/// `LightweightPreviewService.fetchPreview`; tests pass a closure that
/// returns a hand-crafted [VideoPreview] without touching the network.
typedef PreviewFetcher = Future<VideoPreview> Function(String url);

/// Production [CaptureService]. Wires:
///   - [ClipboardMonitorService] — URL detection + 60s dedup
///   - [UrlPatternService] — classify URL into platform / urlType / itemId
///   - [LightweightPreviewService] — fetch oEmbed preview metadata
///   - [FloatingWindow] — spawn / update / hide the popup
///   - [SnoozeStore] — persist snooze state across restarts
///   - [CaptureQuotaPolicy] — daily-counter / premium gating
///
/// All dependencies are injected so unit tests can substitute mocks. The
/// only non-injected dependency is the system clock — a `now()` callback
/// can be overridden via [_now] for deterministic tests.
class DefaultCaptureService implements CaptureService {
  final ClipboardMonitorService _clipboard;
  final FloatingWindow _floatingWindow;
  final PreviewFetcher _fetchPreview;
  final UrlPatternService _urlPattern;
  final SnoozeStore _snoozeStore;
  final CaptureQuotaPolicy _quota;

  /// v2.2 anti-spam Layer 1: dedupe URLs that user already actioned within
  /// cooldown window (default 2 min). Marks on Download/OpenInApp/Dismiss,
  /// not on popup show — failed retries within cooldown still allowed.
  final RecentUrlTracker _recentUrlTracker;

  /// v2.2 anti-spam Layer 4: post-action respawn cooldown. After user
  /// clicks Download/OpenInApp/Dismiss, the URL is blocked from re-triggering
  /// popup for 60s — even if clipboard re-fires for the same URL.
  /// Distinct from [_recentUrlTracker]: tracker is user-configurable cooldown
  /// for "I already actioned this", blocklist is short fixed window for
  /// "popup just dismissed, don't immediately reappear".
  final Map<String, DateTime> _postActionBlocklist = {};
  static const Duration _postActionWindow = Duration(seconds: 60);

  /// Phase 2D.2 (anh Quân Windows feedback): throttle for
  /// `NotifyUrlDeduplicated` side-effect. Without this the user would
  /// be spammed if clipboard fires the same URL multiple times during
  /// the blocklist window. Emits at most ONE notification per URL per
  /// [_dedupNotifyWindow].
  final Map<String, DateTime> _lastDedupNotifyAt = {};
  static const Duration _dedupNotifyWindow = Duration(seconds: 60);

  /// v2.2 anti-spam Layer 3: clipboard noise debounce. If popup is already
  /// visible, wait [_clipboardDebounce] before pushing a new URL — tolerates
  /// the user toggling between tabs while ClipboardMonitorService fires
  /// rapid intermediate URLs. Test override: pass `Duration.zero` to
  /// disable debounce so `await drain()` patterns work without `fakeAsync`.
  Timer? _debounceTimer;
  String? _pendingUrl;
  final Duration _clipboardDebounce;

  /// Injectable clock — overridden in tests so snooze comparisons are
  /// deterministic. Production passes `DateTime.now`.
  final DateTime Function() _now;

  final StreamController<CaptureSideEffect> _effects =
      StreamController<CaptureSideEffect>.broadcast();

  /// Broadcast on every snooze mutation so reactive consumers (Settings UI)
  /// stay in sync. Emission happens AFTER `_snooze` is updated and (where
  /// applicable) persisted, so listeners see a consistent state.
  final StreamController<SnoozeState> _snoozeChanges =
      StreamController<SnoozeState>.broadcast();

  StreamSubscription<String>? _clipboardSub;
  StreamSubscription<FloatingWindowEvent>? _windowEventSub;

  bool _active = false;
  bool _disposed = false;
  SnoozeState _snooze = SnoozeState.inactive;

  /// Serializes processing of clipboard URLs so the popup state stays
  /// consistent when two URLs arrive while the first is mid-fetch.
  Future<void>? _inFlight;

  /// Monotonic counter bumped on every [start] / [stop] / [dispose] so
  /// in-flight [_processUrl] handlers can detect that they raced past
  /// a lifecycle transition and bail out before touching the popup.
  /// Codex audit P1 #3 fix: previously `_processUrl` only checked
  /// snooze post-fetch — a captured URL could spawn the popup AFTER
  /// `stop()` had cancelled subscriptions, leaving a stranded popup.
  int _generation = 0;

  /// Caches the last successfully-fetched preview per URL so
  /// [_emitDownload] can attach the rich metadata without re-fetching.
  /// v2.2: bounded LRU (32 entries) per Codex P2 audit — long-running
  /// sessions previously leaked unboundedly.
  final LruCache<String, VideoPreview> _previewCache = LruCache(32);

  DefaultCaptureService({
    required ClipboardMonitorService clipboard,
    required FloatingWindow floatingWindow,
    required PreviewFetcher fetchPreview,
    required UrlPatternService urlPattern,
    required SnoozeStore snoozeStore,
    required CaptureQuotaPolicy quotaPolicy,
    RecentUrlTracker? recentUrlTracker,
    Duration clipboardDebounce = const Duration(milliseconds: 1500),
    DateTime Function()? now,
  })  : _clipboard = clipboard,
        _floatingWindow = floatingWindow,
        _fetchPreview = fetchPreview,
        _urlPattern = urlPattern,
        _snoozeStore = snoozeStore,
        _quota = quotaPolicy,
        _recentUrlTracker = recentUrlTracker ??
            RecentUrlTracker(now: now ?? DateTime.now),
        _clipboardDebounce = clipboardDebounce,
        _now = now ?? DateTime.now;

  /// Reset both anti-spam Layer 1 (RecentUrlTracker) AND Layer 4
  /// (post-action blocklist). Wired to Settings "Reset cooldowns" button —
  /// safety valve when user reports popup not appearing for legit URL.
  @override
  void resetCooldowns() {
    _recentUrlTracker.clear();
    _postActionBlocklist.clear();
    appLogger.info('[Capture] cooldowns reset by user');
  }

  @override
  Stream<CaptureSideEffect> get sideEffects => _effects.stream;

  @override
  Stream<SnoozeState> get snoozeChanges => _snoozeChanges.stream;

  @override
  bool get isActive => _active;

  @override
  SnoozeState get currentSnooze => _snooze;

  @override
  Future<void> start() async {
    _ensureNotDisposed('start');
    if (_active) return;
    _active = true;

    _snooze = await _snoozeStore.read();
    _emitSnoozeChange();

    // Subscribe BEFORE starting the monitor so any emission during startup
    // is delivered. (ClipboardMonitorService is broadcast.)
    _clipboardSub = _clipboard.onUrl.listen(
      _enqueueUrl,
      onError: (Object e, StackTrace s) {
        appLogger.error('[Capture] clipboard stream error', e, s);
      },
    );
    _windowEventSub = _floatingWindow.events.listen(
      _onWindowEvent,
      onError: (Object e, StackTrace s) {
        appLogger.error('[Capture] floating window stream error', e, s);
      },
    );

    // CaptureService owns the monitor lifecycle — callers shouldn't have to
    // call both start()s. Stop mirrors this in the reverse order.
    try {
      await _clipboard.start();
    } catch (e, s) {
      appLogger.error('[Capture] clipboard monitor start failed', e, s);
      // Best effort — keep service "active" so caller can retry; the
      // window event subscription is still useful for direct invocations.
    }

    appLogger.info(
      '[Capture] started; snooze=${_snooze.duration?.wireKey ?? "inactive"}',
    );
  }

  @override
  Future<void> stop() async {
    _ensureNotDisposed('stop');
    if (!_active) return;
    _active = false;
    _generation++; // any in-flight _processUrl now has a stale token

    try {
      await _clipboard.stop();
    } catch (e, s) {
      appLogger.error('[Capture] clipboard monitor stop failed', e, s);
    }

    await _clipboardSub?.cancel();
    _clipboardSub = null;
    await _windowEventSub?.cancel();
    _windowEventSub = null;

    if (_floatingWindow.isVisible) {
      try {
        await _floatingWindow.hide();
      } catch (e, s) {
        appLogger.error('[Capture] hide on stop failed', e, s);
      }
    }
    appLogger.info('[Capture] stopped');
  }

  @override
  Future<void> snoozeFor(SnoozeDuration duration) async {
    _ensureNotDisposed('snoozeFor');
    final endsAt = duration.resolveEnd(_now());
    _snooze = SnoozeState(endsAt: endsAt, duration: duration);
    await _snoozeStore.write(_snooze);
    _emitSnoozeChange();

    // Hide any visible popup — user has explicitly asked for quiet.
    if (_floatingWindow.isVisible) {
      try {
        await _floatingWindow.hide();
      } catch (e, s) {
        appLogger.error('[Capture] hide on snooze failed', e, s);
      }
    }

    // v2.2 Phase 2C: "Until I resume" has no auto-expiry — without a
    // breadcrumb the user loses track that capture is paused. Emit a
    // toast effect so the host can show a system notification with
    // explicit resume instructions.
    if (duration == SnoozeDuration.untilManuallyResumed) {
      _safeEmit(const ShowSnoozeToast());
    }

    appLogger.info('[Capture] snoozed for ${duration.wireKey}');
  }

  @override
  Future<void> resumeFromSnooze() async {
    _ensureNotDisposed('resumeFromSnooze');
    _snooze = SnoozeState.inactive;
    await _snoozeStore.write(_snooze);
    _emitSnoozeChange();
    appLogger.info('[Capture] resumed from snooze');
  }

  /// Push the current snooze value to subscribers. Guards against
  /// emitting on a closed controller (post-dispose) so the audit-fix
  /// L1 pattern is consistent across both effect streams.
  void _emitSnoozeChange() {
    if (_snoozeChanges.isClosed) return;
    _snoozeChanges.add(_snooze);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _generation++; // invalidate any in-flight processing
    // Call stop() BEFORE flipping `_disposed=true` so its
    // `_ensureNotDisposed` guard doesn't throw on us. In single-threaded
    // Dart this is safe: nothing runs between the await chain and the
    // line that sets _disposed.
    if (_active) {
      await stop();
    }
    _disposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    try {
      await _floatingWindow.dispose();
    } catch (e, s) {
      appLogger.error('[Capture] floatingWindow.dispose failed', e, s);
    }
    await _effects.close();
    await _snoozeChanges.close();
  }

  // -- Clipboard event handling ---------------------------------------------

  /// Entry point from ClipboardMonitorService. Applies the 5-layer anti-spam
  /// pipeline (spec §2 Shift 2) BEFORE enqueueing for processing:
  ///
  ///   Layer 1 — RecentUrlTracker: skip if user actioned this URL recently.
  ///   Layer 4 — Post-action blocklist: skip if popup just dismissed this URL.
  ///   Layer 3 — Clipboard noise debounce: when popup is visible, wait 1.5s
  ///             confirm the user actually settled on this URL.
  void _enqueueUrl(String url) {
    // Layer 1: user already actioned this URL within cooldown — drop.
    if (_recentUrlTracker.isRecentlyActioned(url)) {
      appLogger.info('[Capture] dropped (recently actioned, in cooldown): $url');
      _maybeNotifyDeduplicated(url);
      return;
    }

    // Layer 4: post-action blocklist (60s after Download/OpenInApp/Dismiss).
    final blockedUntil = _postActionBlocklist[url];
    if (blockedUntil != null && blockedUntil.isAfter(_now())) {
      appLogger.info(
        '[Capture] dropped (post-action blocklist active until $blockedUntil): $url',
      );
      _maybeNotifyDeduplicated(url);
      return;
    }
    // Lazy cleanup of expired blocklist entries on every enqueue.
    _postActionBlocklist.removeWhere((_, t) => t.isBefore(_now()));

    // Layer 3: clipboard noise debounce — only when popup is already visible.
    // First-time spawn fires immediately so the user gets fast feedback on
    // the first URL of a session; subsequent URLs are debounced to tolerate
    // tab-switching that emits stale URLs.
    //
    // Tests pass Duration.zero so `await drain()` patterns work without
    // `fakeAsync` package. Production uses 1500ms.
    if (_floatingWindow.isVisible && _clipboardDebounce > Duration.zero) {
      _debounceTimer?.cancel();
      _pendingUrl = url;
      _debounceTimer = Timer(_clipboardDebounce, () {
        if (_pendingUrl == url && !_disposed) {
          _processSerialized(url);
        }
      });
      return;
    }

    // Track the last URL even when not debouncing — PopupDismissed handler
    // uses _pendingUrl to identify which URL to add to blocklist.
    _pendingUrl = url;
    _processSerialized(url);
  }

  /// Awaits any prior in-flight handler so the popup state machine sees
  /// events in the order they arrived. Stalls only if a single handler
  /// stalls — preview-fetch already has a timeout so the worst case is
  /// bounded.
  void _processSerialized(String url) {
    final pending = _inFlight;
    final completer = Completer<void>();
    _inFlight = completer.future;
    () async {
      try {
        if (pending != null) {
          await pending;
        }
        await _processUrl(url);
      } catch (e, s) {
        appLogger.error('[Capture] processUrl failed for $url', e, s);
      } finally {
        completer.complete();
      }
    }();
  }

  Future<void> _processUrl(String url) async {
    // Codex audit P1 #3: capture the generation at entry; every async
    // resume below re-checks it against the current value so stop() /
    // dispose() between awaits aborts the rest of the work cleanly.
    final myGen = _generation;

    if (!_active || _disposed) return;
    if (_snooze.isActive(_now())) {
      appLogger.info('[Capture] dropped (snoozed): $url');
      return;
    }

    final classification = _urlPattern.classify(url);
    if (classification.urlType == UrlType.notUrl ||
        classification.urlType == UrlType.unknown) {
      // Defensive: ClipboardMonitorService already filters these but we
      // belt-and-suspenders to avoid spawning popups for clipboard noise.
      appLogger.info('[Capture] dropped (not a known URL): $url');
      return;
    }

    final remaining = await _quota.remaining();
    if (_generation != myGen) {
      appLogger.info('[Capture] dropped post-quota (lifecycle changed): $url');
      return;
    }

    VideoPreview preview;
    try {
      preview = await _fetchPreview(url);
    } catch (e, s) {
      appLogger.warning(
        '[Capture] preview fetch failed; using fallback',
        e,
        s,
      );
      preview = _fallbackPreview(url, classification);
    }
    if (_generation != myGen) {
      appLogger.info('[Capture] dropped post-fetch (lifecycle changed): $url');
      return;
    }

    // Re-check snooze AFTER fetch — the user may have snoozed during the
    // (potentially seconds-long) preview round-trip. Without this check the
    // popup pops up despite the user explicitly asking for quiet, violating
    // spec Q14.
    if (_snooze.isActive(_now())) {
      appLogger.info('[Capture] dropped post-fetch (snoozed mid-fetch): $url');
      return;
    }

    // Spawn/update FloatingWindow based on current state.
    try {
      if (!_floatingWindow.isSpawned) {
        await _floatingWindow.spawn(initialPreview: preview);
        await _floatingWindow.show();
      } else if (_floatingWindow.isVisible) {
        await _floatingWindow.pushQueue(preview);
      } else {
        await _floatingWindow.showPreview(preview);
      }
      await _floatingWindow.setQuotaState(remaining: remaining);
      _previewCache[url] = preview;
    } catch (e, s) {
      appLogger.error('[Capture] failed to update popup', e, s);
      return;
    }

    // Decrement quota only AFTER we successfully showed the popup —
    // avoids the user being charged for a capture they never saw.
    if (remaining > 0) {
      await _quota.recordCapture();
    }
  }

  VideoPreview _fallbackPreview(String url, UrlClassification c) {
    return VideoPreview(
      rawUrl: url,
      platform: c.platform,
      urlType: c.urlType,
      itemId: c.itemId,
      title: null,
      uploader: null,
      thumbnailUrl: null,
      startTimestamp: c.startTimestamp,
      playlistId: c.playlistId,
      hasFetchedMetadata: false,
    );
  }

  // -- Floating window event handling ---------------------------------------

  void _onWindowEvent(FloatingWindowEvent event) {
    switch (event) {
      case DownloadClicked(:final url, :final presetKey, :final directDownload):
        _markActioned(url);
        _emitDownload(url, presetKey, directDownload: directDownload);

      case SnoozeSelected(:final duration):
        // Fire-and-forget — caller doesn't await us. Errors are logged
        // inside snoozeFor (write) and via the standard logger here.
        snoozeFor(duration).catchError((Object e, StackTrace s) {
          appLogger.error('[Capture] snoozeFor from event failed', e, s);
        });

      case MenuOpenAppRequested():
        _safeEmit(const OpenMainAppWindow());

      case MenuOpenSettingsRequested():
        _safeEmit(const OpenCaptureSettings());

      case PositionChanged():
        // Position persistence deferred to Phase 1A.6 (polish slice).
        break;

      case PopupDismissed():
        // v2.2 anti-spam Layer 4: dismissed URL goes into post-action
        // blocklist for 60s — clipboard re-fire of the same URL won't
        // immediately respawn popup. The dismissed URL is the most recent
        // _pendingUrl (best signal of which URL the user dismissed).
        if (_pendingUrl != null) {
          _markActioned(_pendingUrl!);
        }

      case ThumbnailClicked(:final url):
        _safeEmit(OpenExternalUrl(url));

      case OpenInAppClicked(:final url):
        _markActioned(url);
        _safeEmit(OpenInAppUrl(url));

      // v2.2 Phase 2D.1 (CPO feedback): Completed-banner CTAs.
      case OpenSavedFolderClicked(:final path):
        _safeEmit(OpenSavedFolder(path));

      case PlayFileClicked(:final path):
        _safeEmit(PlaySavedFile(path));
    }
  }

  /// Mark a URL as user-actioned: arms BOTH anti-spam Layer 1 (cooldown)
  /// AND Layer 4 (post-action blocklist). Called from terminal events.
  void _markActioned(String url) {
    _recentUrlTracker.markActioned(url);
    _postActionBlocklist[url] = _now().add(_postActionWindow);
  }

  /// Phase 2D.2: emit [NotifyUrlDeduplicated] at most once per URL per
  /// [_dedupNotifyWindow]. Called from `_enqueueUrl` on Layer 1 / Layer 4
  /// drops so the user gets a visible breadcrumb instead of "popup never
  /// reappeared, feature broken".
  void _maybeNotifyDeduplicated(String url) {
    final lastAt = _lastDedupNotifyAt[url];
    final now = _now();
    if (lastAt != null && now.difference(lastAt) < _dedupNotifyWindow) return;
    _lastDedupNotifyAt[url] = now;
    // Lazy cleanup so the throttle map doesn't grow unbounded.
    _lastDedupNotifyAt.removeWhere(
      (_, t) => now.difference(t) > _dedupNotifyWindow,
    );
    _safeEmit(NotifyUrlDeduplicated(url));
  }

  /// Add to [_effects] only if the controller is still open. The window
  /// event subscription is cancelled in [stop], but a `_onWindowEvent` call
  /// already in flight when [dispose] runs could race past
  /// `_effects.close()` and throw on a closed controller. This guard makes
  /// late events drop silently instead.
  void _safeEmit(CaptureSideEffect effect) {
    if (_effects.isClosed) return;
    _effects.add(effect);
  }

  void _emitDownload(
    String url,
    String? presetKey, {
    bool directDownload = true,
  }) {
    // Reuse the most recently shown preview when possible — popup carries
    // the URL but not the full preview, and re-fetching just to emit a
    // download request would re-hit the network for no reason.
    final cached = _previewCache[url];
    final preview = cached ?? _fallbackPreview(url, _urlPattern.classify(url));

    _safeEmit(
      StartDownloadRequested(
        CaptureDownloadRequest(
          preview: preview,
          presetKey: presetKey,
          requestedAt: _now(),
          directDownload: directDownload,
        ),
      ),
    );
  }

  void _ensureNotDisposed(String method) {
    if (_disposed) {
      throw StateError(
        'DefaultCaptureService.$method() called after dispose()',
      );
    }
  }
}
