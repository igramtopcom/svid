import 'dart:async';

import '../../../../core/logging/app_logger.dart';
import 'clipboard_source.dart';
import 'url_pattern_service.dart';

/// Watches the system clipboard for new URL content and emits events when a
/// recognized video URL is copied.
///
/// Per spec v2.1 §3.1 + §5.3 (app launch behavior):
/// - On start, captures initial clipboard state as **baseline** — pre-existing
///   clipboard content does NOT trigger emission. Only changes AFTER start
///   are emitted.
/// - Dedup window of 60s: if same URL is copied twice within 60s, second
///   copy is ignored (per spec §11 E1).
/// - Filter via [UrlPatternService]: only emit URLs that classify as known
///   types (video/playlist/channel/live). Plain text + non-URL clipboard is
///   silently dropped (per E16).
///
/// This service is platform-agnostic — wraps a [ClipboardSource] which
/// supplies the raw text events. Native polling implementation lives in
/// `NativeClipboardSource` (Phase 1A.2 native bindings, not built yet).
class ClipboardMonitorService {
  final ClipboardSource _source;
  final UrlPatternService _urlPattern;
  final Duration _dedupWindow;

  StreamSubscription<String>? _subscription;
  final _emitter = StreamController<String>.broadcast();

  /// URL → last seen timestamp. Used to dedup within [_dedupWindow].
  /// Auto-pruned when looking up; max ~10 entries during normal use.
  final Map<String, DateTime> _recentUrls = {};

  /// Initial clipboard content at start time. Subsequent reads matching this
  /// hash are NOT emitted (per spec §5.3 passive launch).
  String? _baselineContent;

  bool _started = false;

  ClipboardMonitorService({
    required ClipboardSource source,
    UrlPatternService? urlPattern,
    Duration dedupWindow = const Duration(seconds: 60),
  })  : _source = source,
        _urlPattern = urlPattern ?? const UrlPatternService(),
        _dedupWindow = dedupWindow;

  /// Stream of clipboard URLs that pass classification + dedup filters.
  /// Each emitted string is a raw URL ready for [UrlPatternService.classify].
  Stream<String> get onUrl => _emitter.stream;

  /// Start monitoring. Idempotent.
  ///
  /// Initial clipboard state captured as baseline — won't emit pre-existing
  /// content (per spec §5.3).
  Future<void> start({Duration pollInterval = const Duration(milliseconds: 500)}) async {
    if (_started) return;
    _started = true;

    // Capture baseline before subscribing — anything matching this is
    // considered "pre-existing" and ignored even if source emits it.
    _baselineContent = await _source.readText();

    // Codex audit P2 fix: subscribe BEFORE starting the source. Some
    // platform implementations may emit immediately during start() (or
    // synchronously upon first event-channel listen on the native side)
    // and a late `.listen()` would miss those first events. Order is
    // now: baseline → subscribe → start.
    _subscription = _source.onChange.listen(
      _handleClipboardChange,
      onError: (Object e, StackTrace stack) {
        appLogger.error('[ClipboardMonitor] source error', e, stack);
      },
    );

    await _source.start(pollInterval: pollInterval);

    appLogger.info(
      '[ClipboardMonitor] started, baseline=${_baselineContent != null ? "<existing>" : "<empty>"}',
    );
  }

  /// Stop monitoring. Service can be restarted via [start].
  Future<void> stop() async {
    if (!_started) return;
    _started = false;

    await _subscription?.cancel();
    _subscription = null;
    await _source.stop();
    _baselineContent = null;
    _recentUrls.clear();

    appLogger.info('[ClipboardMonitor] stopped');
  }

  /// Permanent disposal. Closes the broadcast stream.
  Future<void> dispose() async {
    await stop();
    await _emitter.close();
  }

  void _handleClipboardChange(String content) {
    // Defensive: catch any unexpected error in handler so it doesn't crash
    // the subscription or propagate to subscribers.
    try {
      _processClipboardChange(content);
    } catch (e, stack) {
      appLogger.error('[ClipboardMonitor] handler error', e, stack);
    }
  }

  void _processClipboardChange(String content) {
    // Guard against post-dispose race — handler may still fire after stop()
    // due to async cancellation.
    if (!_started || _emitter.isClosed) return;

    // Skip if matches initial baseline — user didn't actually change clipboard
    // since app start, source just notified about pre-existing content.
    if (_baselineContent != null && content == _baselineContent) {
      return;
    }
    // First real change — clear baseline so subsequent identical content
    // can still be detected (e.g., user clears + re-copies same URL).
    _baselineContent = null;

    final trimmed = content.trim();
    if (trimmed.isEmpty) return;

    // Classify — drop non-URL inputs (E16)
    final classification = _urlPattern.classify(trimmed);
    if (!classification.isKnownUrlType) {
      // Includes notUrl, unknown — silent skip
      return;
    }

    // Dedup within window (E1)
    if (_isDuplicate(trimmed)) {
      appLogger.debug('[ClipboardMonitor] dedup skip: $trimmed');
      return;
    }
    _markSeen(trimmed);

    appLogger.info(
      '[ClipboardMonitor] URL detected: ${classification.platform.name}/${classification.urlType.name}',
    );
    _emitter.add(trimmed);
  }

  bool _isDuplicate(String url) {
    _pruneExpired();
    return _recentUrls.containsKey(url);
  }

  void _markSeen(String url) {
    _recentUrls[url] = DateTime.now();
  }

  /// Remove URLs older than dedup window. Bounded cleanup — only iterates
  /// when needed.
  void _pruneExpired() {
    if (_recentUrls.isEmpty) return;
    final now = DateTime.now();
    _recentUrls.removeWhere((_, ts) => now.difference(ts) > _dedupWindow);
  }
}
