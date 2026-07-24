import '../../../../core/config/brand_config.dart';

/// Generates JavaScript interception scripts for capturing media network
/// requests inside the in-app browser (IDM mode).
///
/// Six complementary interception layers run simultaneously:
/// 1. PerformanceObserver — non-invasive, catches all loaded resources
/// 2. fetch() monkey-patch — sees URLs before completion
/// 3. XMLHttpRequest monkey-patch — same for legacy XHR
/// 4. MutationObserver — detects <video>/<audio>/<source> DOM elements
/// 5. MediaSource monitoring — detects MSE-based streaming (YouTube-style)
/// 6. SPA navigation monitor — detects URL changes via pushState/replaceState
///
/// Detected media is reported to the Dart layer via a platform-specific
/// message channel (postMessage for macOS, callHandler for Windows).
class MediaInterceptorService {
  /// Channel name used for JS→Dart communication (media detection).
  static const channelName = 'mediaInterceptor';

  /// Channel name for SPA URL change notifications.
  static const spaChannelName = 'spaUrlChange';

  /// Generate the full interception script to inject after page load.
  ///
  /// [useCallHandler] — true for flutter_inappwebview (Windows),
  /// false for webview_flutter (macOS) which uses messageHandlers.
  static String generateScript({bool useCallHandler = false}) {
    final reportFn = useCallHandler
        ? 'window.flutter_inappwebview.callHandler("$channelName", data)'
        : 'window.webkit.messageHandlers.$channelName.postMessage(JSON.stringify(data))';

    return '''
(function() {
  'use strict';

  // Guard: don't inject twice
  if (window.__${BrandConfig.current.brand.name}_media_interceptor) return;
  window.__${BrandConfig.current.brand.name}_media_interceptor = true;

  // ── Shared helpers ──────────────────────────────────────────────

  var _reported = {};
  var _pending = [];
  var _flushTimer = null;
  var _sentCount = 0;
  var MAX_REPORTS = 120;

  // Batch reports into ONE bridge call per 400ms window (data = array).
  // Per-event callHandler calls hammered the native message channel on heavy
  // SPA pages (vnexpress Shorts) and correlated with an access-violation
  // crash inside flutter_inappwebview_windows_plugin.dll — batching plus the
  // MAX_REPORTS cap keeps bridge pressure low and bounded.
  function _flush() {
    _flushTimer = null;
    if (!_pending.length) return;
    // Cap the payload size per bridge call. A large JSON array handed to the
    // Windows plugin's message channel in one shot correlates with a native
    // access-violation crash (flutter_inappwebview_windows_plugin.dll @0x7ae65,
    // reproducible on resource-heavy news pages). Send in small chunks and
    // re-schedule the remainder.
    var data = _pending.splice(0, 15);
    try { $reportFn; } catch(e) {}
    if (_pending.length && !_flushTimer) {
      _flushTimer = setTimeout(_flush, 60);
    }
  }

  function _ogImage() {
    try {
      var e = document.querySelector('meta[property="og:image"]') ||
              document.querySelector('meta[name="twitter:image"]') ||
              document.querySelector('meta[property="twitter:image"]');
      return (e && e.content) ? e.content : '';
    } catch(_) { return ''; }
  }

  function report(item) {
    var key = item.url || item.mimeType || '';
    if (_reported[key]) return;
    _reported[key] = true;
    if (_sentCount >= MAX_REPORTS) return;
    _sentCount++;
    // Enrich with page context captured AT DETECTION TIME so title + thumbnail
    // stay in sync with this exact stream (a Shorts feed swaps document.title /
    // og:image as it auto-advances — reading them later would mismatch).
    item.pageTitle = document.title || '';
    item.pageUrl = location.href;
    item.pageThumb = _ogImage();
    _pending.push(item);
    // DRM signals flush immediately (the policy notice should not lag);
    // everything else waits for the batch window.
    if (item.type === 'drm') { _flush(); return; }
    if (!_flushTimer) _flushTimer = setTimeout(_flush, 400);
  }

  // ── DRM (EME) detection ─────────────────────────────────────────
  // A page that uses Encrypted Media Extensions is DRM-protected. We decline
  // downloads for such sources by policy, so surface a single 'drm' signal.
  try {
    var _rmksa = navigator.requestMediaKeySystemAccess;
    if (typeof _rmksa === 'function') {
      navigator.requestMediaKeySystemAccess = function() {
        try { report({ source: 'drm', type: 'drm' }); } catch(e) {}
        return _rmksa.apply(this, arguments);
      };
    }
  } catch(e) {}
  try {
    document.addEventListener('encrypted', function() {
      try { report({ source: 'drm', type: 'drm' }); } catch(e) {}
    }, true);
  } catch(e) {}

  // Media extension patterns
  var _videoExts = /\\.(mp4|webm|mkv|avi|mov|wmv|flv|f4v|m4v|3gp|3g2|ts|mts|m2ts|ogv|vob|divx)\$/i;
  var _audioExts = /\\.(mp3|m4a|aac|ogg|opus|flac|wav|wma|weba|aiff|aif)\$/i;
  var _streamExts = /\\.(m3u8|mpd)\$/i;
  var _segmentExts = /\\.(ts|m4s)\$/i;

  // Known video CDN domains (exclude googlevideo.com — YouTube uses SABR
  // protocol with session-signed URLs that cannot be downloaded directly;
  // users should use the dedicated YouTube download path via yt-dlp instead)
  var _cdnDomains = /fbcdn\\.net|cdninstagram\\.com|video\\.twimg\\.com|tiktokcdn\\.com|tiktokv\\.com|akamaized\\.net|cloudfront\\.net|fastly\\.net/i;

  // Ad/tracker domains to ignore
  var _adDomains = /doubleclick\\.net|googlesyndication\\.com|googleadservices\\.com|google-analytics\\.com|googletagmanager\\.com|facebook\\.net\\/signals|amazon-adsystem\\.com|scorecardresearch\\.com|quantserve\\.com|hotjar\\.com|mouseflow\\.com|fullstory\\.com|newrelic\\.com|nr-data\\.net|segment\\.io|mixpanel\\.com|amplitude\\.com/i;
  var _adPaths = /\\/pixel|\\/beacon|\\/track|\\/analytics|\\/telemetry/i;

  // Non-media file extensions to ALWAYS reject (even from CDN domains)
  var _nonMediaExts = /\\.(js|css|json|html|htm|xml|svg|woff|woff2|ttf|eot|otf|png|jpg|jpeg|gif|ico|webp|avif|bmp|cur|map|txt|md|pdf|zip|gz|br|wasm)\$/i;

  function isMediaUrl(url) {
    if (!url || typeof url !== 'string') return false;
    if (url.startsWith('data:') || url.startsWith('blob:') || url.startsWith('chrome:')) return false;
    try {
      var u = new URL(url, location.href);
      var host = u.hostname;
      var path = u.pathname;
      // Block ads/trackers
      if (_adDomains.test(host) || _adPaths.test(path)) return false;
      // Block known non-media extensions (JS, CSS, images, fonts, etc.)
      if (_nonMediaExts.test(path)) return false;
      // Check extensions (strip query from path check)
      if (_videoExts.test(path) || _audioExts.test(path) || _streamExts.test(path)) return true;
      if (_segmentExts.test(path) && path.length > 5) return true;
      // Check CDN domains — but ONLY if path has no extension (could be media redirect)
      // or path has a media-like extension already matched above
      if (_cdnDomains.test(host)) {
        // No file extension → likely a CDN media endpoint (e.g. googlevideo.com/videoplayback)
        var lastSegment = path.split('/').pop() || '';
        if (lastSegment.indexOf('.') === -1) return true;
        // Has extension but not in non-media list → cautiously accept
        return true;
      }
      // Check query params for media hints
      var search = u.search;
      if (search && (/mime=video|mime=audio|itag=/.test(search))) return true;
      return false;
    } catch(e) {
      return false;
    }
  }

  function classifyUrl(url) {
    try {
      var u = new URL(url, location.href);
      var path = u.pathname;
      if (_streamExts.test(path)) return 'stream';
      // Segments MUST be checked before video: '.ts' is also in _videoExts, but
      // an HLS/DASH segment (.ts/.m4s, or seg-/chunk-/frag-named) is NOT an
      // independently downloadable file — the .m3u8 manifest is the real item.
      if (_segmentExts.test(path)) return 'segment';
      if (/[\\/_-](seg|segment|chunk|frag)[-_]?\\d/i.test(path)) return 'segment';
      if (_audioExts.test(path)) return 'audio';
      if (_videoExts.test(path)) return 'video';
      // CDN domain without media extension → likely video
      if (_cdnDomains.test(u.hostname)) return 'video';
      return 'unknown';
    } catch(e) {
      return 'unknown';
    }
  }

  // ── Layer 1: PerformanceObserver ────────────────────────────────

  try {
    var perfObserver = new PerformanceObserver(function(list) {
      var entries = list.getEntries();
      for (var i = 0; i < entries.length; i++) {
        var entry = entries[i];
        var url = entry.name;
        if (!isMediaUrl(url)) continue;
        // Filter tiny resources (< 50KB) unless it's a manifest/stream.
        // Note: DASH init segments (~3KB) on CDN domains may still pass —
        // the unified media provider handles final classification.
        var isManifest = _streamExts.test(url);
        if (!isManifest && entry.transferSize > 0 && entry.transferSize < 51200) continue;
        report({
          url: url,
          source: 'performance',
          type: classifyUrl(url),
          size: entry.transferSize || null,
          initiator: entry.initiatorType || null
        });
      }
    });
    perfObserver.observe({ type: 'resource', buffered: true });
  } catch(e) {}

  // ── Layer 2: fetch() monkey-patch ───────────────────────────────

  try {
    var origFetch = window.fetch;
    if (origFetch) {
      window.fetch = function() {
        var input = arguments[0];
        var url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
        if (isMediaUrl(url)) {
          report({
            url: url,
            source: 'fetch',
            type: classifyUrl(url),
            size: null,
            initiator: null
          });
        }
        return origFetch.apply(this, arguments);
      };
    }
  } catch(e) {}

  // ── Layer 3: XMLHttpRequest monkey-patch ────────────────────────

  try {
    var origOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url) {
      this.__${BrandConfig.current.brand.name}_url = url;
      if (isMediaUrl(url)) {
        report({
          url: url,
          source: 'xhr',
          type: classifyUrl(url),
          size: null,
          initiator: null
        });
      }
      return origOpen.apply(this, arguments);
    };
  } catch(e) {}

  // ── Layer 4: MutationObserver for <video>/<audio> ───────────────

  function scanMediaElement(el) {
    if (!el || !el.tagName) return;
    var tag = el.tagName.toUpperCase();
    if (tag === 'VIDEO' || tag === 'AUDIO' || tag === 'SOURCE') {
      var src = el.src || el.currentSrc || el.getAttribute('src') || '';
      if (src && !src.startsWith('blob:') && !src.startsWith('data:')) {
        if (isMediaUrl(src)) {
          report({
            url: src,
            source: 'dom',
            type: tag === 'AUDIO' ? 'audio' : 'video',
            size: null,
            initiator: tag.toLowerCase()
          });
        }
      }
    }
  }

  function scanTree(node) {
    if (!node) return;
    scanMediaElement(node);
    if (node.querySelectorAll) {
      var els = node.querySelectorAll('video, audio, source');
      for (var i = 0; i < els.length; i++) scanMediaElement(els[i]);
    }
  }

  try {
    var mutObserver = new MutationObserver(function(mutations) {
      for (var i = 0; i < mutations.length; i++) {
        var added = mutations[i].addedNodes;
        for (var j = 0; j < added.length; j++) {
          scanTree(added[j]);
        }
      }
    });
    if (document.body) {
      mutObserver.observe(document.body, { childList: true, subtree: true });
    }
    // Also scan existing elements
    scanTree(document.body);
  } catch(e) {}

  // ── Layer 5: MediaSource monitoring ─────────────────────────────

  try {
    if (window.MediaSource && MediaSource.prototype.addSourceBuffer) {
      var origAddSB = MediaSource.prototype.addSourceBuffer;
      MediaSource.prototype.addSourceBuffer = function(mimeType) {
        report({
          url: null,
          source: 'mediasource',
          type: /^video/i.test(mimeType) ? 'video' : (/^audio/i.test(mimeType) ? 'audio' : 'unknown'),
          size: null,
          mimeType: mimeType,
          initiator: null
        });
        return origAddSB.apply(this, arguments);
      };
    }
  } catch(e) {}

})();
''';
  }

  /// Generate the SPA navigation monitor script (Layer 6).
  ///
  /// Overrides `history.pushState`/`replaceState` and listens for `popstate`
  /// to detect URL changes in single-page apps (Instagram, TikTok, etc.).
  /// Reports URL changes on the [spaChannelName] channel.
  static String generateSpaMonitorScript({bool useCallHandler = false}) {
    final reportFn = useCallHandler
        ? 'window.flutter_inappwebview.callHandler("$spaChannelName", data)'
        : 'window.webkit.messageHandlers.$spaChannelName.postMessage(JSON.stringify(data))';

    return '''
(function() {
  'use strict';
  if (window.__${BrandConfig.current.brand.name}_spa_monitor) return;
  window.__${BrandConfig.current.brand.name}_spa_monitor = true;

  var _lastUrl = location.href;
  var _debounceTimer = null;

  function reportUrlChange() {
    var newUrl = location.href;
    if (newUrl === _lastUrl) return;
    _lastUrl = newUrl;
    if (_debounceTimer) clearTimeout(_debounceTimer);
    _debounceTimer = setTimeout(function() {
      try {
        var data = { type: 'spa_navigation', url: newUrl, title: document.title || '' };
        $reportFn;
      } catch(e) {}
    }, 300);
  }

  // Override history.pushState
  try {
    var origPushState = history.pushState;
    history.pushState = function() {
      var result = origPushState.apply(this, arguments);
      reportUrlChange();
      return result;
    };
  } catch(e) {}

  // Override history.replaceState
  try {
    var origReplaceState = history.replaceState;
    history.replaceState = function() {
      var result = origReplaceState.apply(this, arguments);
      reportUrlChange();
      return result;
    };
  } catch(e) {}

  // Listen for popstate (back/forward navigation)
  window.addEventListener('popstate', function() {
    setTimeout(reportUrlChange, 50);
  });

  // Listen for hashchange
  window.addEventListener('hashchange', function() {
    reportUrlChange();
  });

  // ── Scroll-triggered DOM re-scan ──
  // When user scrolls, SPA apps (Instagram/TikTok) load new content.
  // Notify Dart to re-scan DOM for video links after scrolling settles.
  var _scrollTimer = null;
  window.addEventListener('scroll', function() {
    if (_scrollTimer) clearTimeout(_scrollTimer);
    _scrollTimer = setTimeout(function() {
      try {
        var data = { type: 'scroll_update', url: location.href };
        $reportFn;
      } catch(e) {}
    }, 2500);
  }, { passive: true });
})();
''';
  }

}
