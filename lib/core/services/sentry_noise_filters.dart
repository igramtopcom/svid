import 'package:sentry_flutter/sentry_flutter.dart';

/// Narrow Sentry beforeSend filters for known no-action-needed noise.
///
/// **Policy (Codex-calibrated 2026-05-20):** filter ONLY events that match a
/// concrete pattern AND have no user-actionable signal. Never filter network/
/// download errors broadly — those are diagnostic gold. Each filter must:
///   1. Match a specific URL/message pattern
///   2. Have no failure that the user can do anything about
///   3. Be locked by unit tests so it cannot drift wider over time
///
/// Add a new filter only after evidence the noise is recurring and ALWAYS
/// user-invisible.
class SentryNoiseFilters {
  /// Returns `true` when [event] is a YouTube thumbnail 404 that should be
  /// dropped. The pattern is narrow on purpose:
  ///
  ///   - URL contains `img.youtube.com/vi/` AND a `*default.jpg` variant
  ///   - Exception text contains the literal `404` status indicator
  ///
  /// YouTube returns 404 for thumbnails of deleted / unlisted / age-gated
  /// videos. The image widget already renders a placeholder via
  /// `AppCachedImage.errorBuilder`, so the user sees nothing different —
  /// the Sentry event is pure noise.
  static bool isYouTubeThumbnail404(SentryEvent event) {
    final haystack = _extractHaystack(event);
    if (haystack.isEmpty) return false;

    final hasStatus = haystack.contains('404') ||
        haystack.contains('statusCode: 404') ||
        haystack.contains('HTTP/1.1 404');

    // Be tolerant of the path shape: `/vi/<id>/hqdefault.jpg` is the most
    // common; YouTube also serves `mqdefault.jpg`, `sddefault.jpg`,
    // `maxresdefault.jpg`, `default.jpg`. Lock the host to avoid
    // accidentally hiding errors from a different `/vi/` path on an
    // unrelated CDN.
    final isYouTubeHost =
        haystack.contains('img.youtube.com/vi/') ||
            haystack.contains('i.ytimg.com/vi/');
    final isThumbnailPath =
        haystack.contains('hqdefault.jpg') ||
            haystack.contains('mqdefault.jpg') ||
            haystack.contains('sddefault.jpg') ||
            haystack.contains('maxresdefault.jpg') ||
            // `/default.jpg` only, not the prefixed siblings above.
            RegExp(r'/vi/[^/]+/default\.jpg').hasMatch(haystack);

    return hasStatus && isYouTubeHost && isThumbnailPath;
  }

  /// Returns `true` when [event] is a transient health-probe timeout that
  /// has no user-visible effect. Specifically:
  ///
  ///   - host is `api.vidcombo.net` (PHP backend version probe)
  ///   - error is `TimeoutException` against the 10 s startup probe
  ///
  /// The probe failure is already caught silently and does not block the
  /// app from starting (see `startup_service.dart` post-2089d5ae). Sending
  /// it to Sentry costs quota without surfacing anything actionable.
  static bool isVidComboHealthProbeTimeout(SentryEvent event) {
    final haystack = _extractHaystack(event);
    if (haystack.isEmpty) return false;
    final hasTimeout = haystack.contains('TimeoutException');
    final hasHost = haystack.contains('api.vidcombo.net') ||
        haystack.contains('vidcombo.com/api');
    final hasProbe = haystack.contains('version.php') ||
        haystack.contains('checkkey.php');
    return hasTimeout && hasHost && hasProbe;
  }

  /// Returns `true` when ANY noise filter matches. This is the public
  /// surface used by `_beforeSend` — a single short-circuit drop.
  static bool shouldDrop(SentryEvent event) {
    return isYouTubeThumbnail404(event) ||
        isVidComboHealthProbeTimeout(event);
  }

  /// Builds a single lowercase string with the event's message, exception
  /// values, and stack-relevant URLs. Filters match against this haystack
  /// so the pattern is consistent across `SentryEvent` shapes (message
  /// event vs exception event vs breadcrumb-rich event).
  ///
  /// Visible for testing — exposed indirectly via [shouldDrop] which is
  /// the unit-of-behavior the unit tests lock.
  static String _extractHaystack(SentryEvent event) {
    final buf = StringBuffer();
    final message = event.message?.formatted;
    if (message != null) {
      buf.write(message);
      buf.write('\n');
    }
    for (final exc in event.exceptions ?? const <SentryException>[]) {
      buf.write(exc.type ?? '');
      buf.write('\n');
      buf.write(exc.value ?? '');
      buf.write('\n');
    }
    // Some image errors land in the request URL or extra map rather than
    // the exception value. Include `extra` strings opportunistically.
    // `extra` is deprecated upstream in favor of structured Contexts, but
    // existing capture sites in this codebase still attach data there; we
    // read it best-effort so the filter does not miss those events.
    // ignore: deprecated_member_use
    final extra = event.extra;
    if (extra != null) {
      for (final v in extra.values) {
        if (v is String) {
          buf.write(v);
          buf.write('\n');
        }
      }
    }
    return buf.toString();
  }
}
