/// RC10 of Ultra Plan v3 — shared URL normalization helper.
///
/// Multiple downloader code paths compare URLs to identify the same
/// resource:
///   - Auth retry path matches failed downloads to retry after login
///   - Duplicate-detection warning compares pasted URL vs existing
///     downloads
///   - Floating-capture coordinator compares popup URL vs notifier
///     state
///
/// Pre-RC10 each site did its own string-equality check, so
/// `youtube.com/watch?v=abc&t=10` and `youtube.com/watch?v=abc`
/// (same video, different timestamps) were treated as different,
/// and `youtu.be/abc` vs `youtube.com/watch?v=abc` (same video,
/// different host shape) were also different. This helper centralizes
/// the comparison so every callsite agrees.
///
/// Design constraints (Codex direction 2026-05-23):
///   - Pure function. No I/O, no logging, no state.
///   - Lossless lower-bound: never throws on bad input; falls through
///     to whatever raw string was passed.
///   - Conservative: only strip noise that is well-known to be
///     non-identity-affecting (tracking params, fragment, trailing
///     slash). DON'T strip path segments (could change resource).
class UrlNormalizer {
  /// Compare two URLs for "same resource" semantics. Returns true
  /// when both URLs normalize to the same canonical form. Use this
  /// instead of `a == b` whenever auth retry / duplicate detection
  /// needs to match user-facing identity.
  static bool same(String? a, String? b) {
    if (a == null || b == null) return false;
    final na = normalize(a);
    final nb = normalize(b);
    if (na.isEmpty || nb.isEmpty) return false;
    return na == nb;
  }

  /// Normalize a URL to a canonical form for comparison. Returns
  /// empty string on null/blank input. The output is NOT meant to
  /// be sent to the network — it's a comparison key only.
  ///
  /// Transformations:
  ///   1. Trim whitespace
  ///   2. Lowercase the host portion (URLs are case-insensitive in
  ///      scheme + host, case-sensitive in path/query per RFC 3986)
  ///   3. Strip fragment (`#...`) — fragments are client-side only
  ///   4. Strip trailing `/` (no-content-change)
  ///   5. Drop common tracking params (utm_*, fbclid, gclid, igshid,
  ///      _ga, _gid, mc_eid, ref, ref_src, ref_url, si). These
  ///      universally don't affect the resource the URL identifies.
  ///   6. Sort remaining query params (stable comparison key —
  ///      `?a=1&b=2` and `?b=2&a=1` both produce `a=1&b=2`)
  static String normalize(String? raw) {
    if (raw == null) return '';
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    Uri? parsed;
    try {
      parsed = Uri.tryParse(trimmed);
    } catch (_) {
      parsed = null;
    }
    // Fallback: input doesn't parse as URI → use raw lowercase host
    // detection so we still normalize as best we can.
    if (parsed == null || parsed.host.isEmpty) {
      return trimmed.toLowerCase().split('#').first;
    }
    // RC10 Codex-catch D — canonicalize platform aliases BEFORE
    // normalization. youtu.be/abc, youtube.com/watch?v=abc, and
    // youtube.com/shorts/abc all reference the same video; auth
    // retry + duplicate detection must treat them as one resource.
    final canonical = _canonicalizePlatformAlias(parsed);
    if (canonical != null) parsed = canonical;
    // Trailing slash strip on path (but keep '/' for root).
    var path = parsed.path;
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    // Filter tracking params + sort remaining.
    final queryEntries = parsed.queryParametersAll.entries
        .where((e) => !_trackingParams.contains(e.key.toLowerCase()))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final canonicalQuery = queryEntries
        .expand((e) => e.value.map((v) => '${e.key}=$v'))
        .join('&');
    final hostLower = parsed.host.toLowerCase();
    final schemeLower = parsed.scheme.toLowerCase();
    final portPart = (parsed.hasPort &&
            ((schemeLower == 'http' && parsed.port != 80) ||
                (schemeLower == 'https' && parsed.port != 443)))
        ? ':${parsed.port}'
        : '';
    final queryPart = canonicalQuery.isEmpty ? '' : '?$canonicalQuery';
    return '$schemeLower://$hostLower$portPart$path$queryPart';
  }

  /// RC10 Codex-catch D — canonicalize known platform URL aliases
  /// to their canonical form so [normalize] produces the same key
  /// regardless of which alias the user pasted.
  ///
  /// Aliases handled:
  ///   - YouTube short: `youtu.be/<id>` → `youtube.com/watch?v=<id>`
  ///   - YouTube Shorts: `youtube.com/shorts/<id>` → `youtube.com/watch?v=<id>`
  ///   - YouTube embed: `youtube.com/embed/<id>` → `youtube.com/watch?v=<id>`
  ///   - Mobile prefix: `m.youtube.com` → `youtube.com`,
  ///     `m.facebook.com` → `facebook.com`
  ///   - Facebook short: `fb.watch/<id>` → preserved (no canonical
  ///     URL exists — fb.watch is the official Facebook resolver).
  ///
  /// Returns null when no canonicalization applies; caller proceeds
  /// with the original parsed URI.
  static Uri? _canonicalizePlatformAlias(Uri parsed) {
    final hostLower = parsed.host.toLowerCase();
    // YouTube short link → watch
    if (hostLower == 'youtu.be' || hostLower == 'www.youtu.be') {
      final id = parsed.pathSegments.isNotEmpty
          ? parsed.pathSegments.first
          : '';
      if (id.isEmpty) return null;
      return Uri(
        scheme: 'https',
        host: 'youtube.com',
        path: '/watch',
        queryParameters: {
          'v': id,
          ...parsed.queryParameters,
        },
      );
    }
    // YouTube Shorts / embed → watch
    if (hostLower == 'youtube.com' ||
        hostLower == 'www.youtube.com' ||
        hostLower == 'm.youtube.com' ||
        hostLower == 'music.youtube.com') {
      final segments = parsed.pathSegments;
      String? videoId;
      if (segments.length >= 2 && segments.first == 'shorts') {
        videoId = segments[1];
      } else if (segments.length >= 2 && segments.first == 'embed') {
        videoId = segments[1];
      }
      // Mobile / music subdomain → canonical youtube.com
      // (mobile and music host the same video catalog).
      final isMobileOrMusic =
          hostLower == 'm.youtube.com' || hostLower == 'music.youtube.com';
      if (videoId != null) {
        return Uri(
          scheme: 'https',
          host: 'youtube.com',
          path: '/watch',
          queryParameters: {
            'v': videoId,
            ...parsed.queryParameters,
          },
        );
      }
      if (isMobileOrMusic) {
        return parsed.replace(host: 'youtube.com');
      }
    }
    // Mobile facebook → canonical facebook.com. Skip the `www.`
    // intermediate so the result composes correctly with the www-
    // strip pass below (catch 7) — returning an intermediate Uri
    // here would short-circuit the strip.
    if (hostLower == 'm.facebook.com') {
      return parsed.replace(host: 'facebook.com');
    }
    // RC10 Codex-round-2 catch 7 — strip `www.` prefix for the
    // major platforms so `www.youtube.com/watch?v=abc` and
    // `youtube.com/watch?v=abc` are treated as the same resource.
    // Two-pass logic: first the platform-specific canonicalization
    // above handles youtu.be / shorts / embed / m.* cases; this
    // catch-all strips www for any remaining host where it's
    // meaningless (which is essentially every video platform).
    if (hostLower.startsWith('www.')) {
      return parsed.replace(host: hostLower.substring(4));
    }
    return null;
  }

  static const Set<String> _trackingParams = {
    // Google Analytics / Ads
    'utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content',
    '_ga', '_gid', '_gac', 'gclid', 'dclid', 'gbraid', 'wbraid',
    // Facebook / Meta
    'fbclid',
    // Instagram
    'igshid', 'igsh',
    // Twitter/X
    's', 't',
    // Reddit
    'utm_name',
    // Pinterest
    'epik',
    // Email marketing
    'mc_eid', 'mc_cid',
    // Generic referral
    'ref', 'ref_src', 'ref_url', 'referrer', 'source',
    // YouTube (watchcontext, feature redirects)
    'si', 'pp', 'feature',
  };
}
