import 'package:sentry_flutter/sentry_flutter.dart';

/// Scrubs personally identifiable information (PII) from Sentry events
/// before they are sent to the server.
///
/// Walks every event surface that Item A/B instrumentation populates:
/// `message`, `exceptions`, `breadcrumbs`, `tags`, `extras`, `request`,
/// `user`, `contexts`, `fingerprints`. Anything else added later should be
/// added to this walker too — silently letting an event surface escape
/// scrubbing is the failure mode we're guarding against.
///
/// Redacts:
/// - URLs (http/https)
/// - User-specific file paths (macOS, Linux, Windows)
/// - Media filenames (.mp4, .mp3, .mkv, etc.)
/// - 32-char hex license keys (VidCombo / SSvid format)
/// - UUIDs (any case, with or without hyphens)
/// - JWT tokens (3 base64url segments separated by `.`)
/// - Stripe-style ids (`sk_*`, `pk_*` keys/secrets)
/// - SSvid API keys (`snk_*` prefix)
/// - Email addresses
SentryEvent piiScrubber(SentryEvent event) {
  return event.copyWith(
    message:
        event.message != null
            ? SentryMessage(
              scrubString(event.message!.formatted),
              template:
                  event.message!.template != null
                      ? scrubString(event.message!.template!)
                      : null,
            )
            : null,
    exceptions:
        event.exceptions
            ?.map(
              (e) => SentryException(
                type: e.type,
                value: e.value != null ? scrubString(e.value!) : null,
                module: e.module,
                stackTrace: e.stackTrace,
                mechanism: e.mechanism,
                threadId: e.threadId,
              ),
            )
            .toList(),
    breadcrumbs:
        event.breadcrumbs
            ?.map(
              (b) => Breadcrumb(
                message: b.message != null ? scrubString(b.message!) : null,
                category: b.category,
                type: b.type,
                level: b.level,
                timestamp: b.timestamp,
                data: _scrubMap(b.data),
              ),
            )
            .toList(),
    tags: _scrubTags(event.tags),
    // ignore: deprecated_member_use
    extra: _scrubMap(event.extra),
    user: _scrubUser(event.user),
    contexts: _scrubContexts(event.contexts),
    request: _scrubRequest(event.request),
    fingerprint: event.fingerprint?.map(scrubString).toList(),
  );
}

/// Standalone scrubber for individual strings — used by instrumentation
/// helpers to scrub attributes at attach time, before they reach Sentry.
String scrubString(String input) {
  var result = input;
  for (final pattern in _patterns) {
    result = result.replaceAll(pattern.regex, pattern.replacement);
  }
  return result;
}

/// Scrub a URL for HTTP breadcrumbs to a route template.
///
/// Example: `https://api.ssvid.app/v1/tickets/abc-uuid?key=secret` →
/// `https://api.ssvid.app/v1/tickets/{id}`.
///
/// Steps:
/// 1. Strip query string entirely.
/// 2. Replace path segments matching UUIDs / license keys / emails / opaque
///    tokens with placeholders. Static segments (`v1`, `tickets`) preserved.
String scrubHttpUrl(Uri uri) {
  final scrubbedSegments = uri.pathSegments.map(_scrubPathSegment).toList();
  final cleanPath =
      scrubbedSegments.isEmpty ? '' : '/${scrubbedSegments.join('/')}';
  // Drop query and fragment entirely; they often carry tokens/license keys.
  // Build the URL string manually instead of via `Uri(...).toString()`, which
  // percent-encodes the curly braces in placeholder segments (`{id}` →
  // `%7Bid%7D`) per RFC 3986. The route-template format must remain literal
  // so observability dashboards can group by template.
  final buf = StringBuffer();
  if (uri.scheme.isNotEmpty) {
    buf.write('${uri.scheme}://');
  }
  if (uri.host.isNotEmpty) {
    buf.write(uri.host);
  }
  if (uri.hasPort) {
    buf.write(':${uri.port}');
  }
  buf.write(cleanPath);
  return buf.toString();
}

String _scrubPathSegment(String segment) {
  if (_uuidRegex.hasMatch(segment)) return '{id}';
  if (_licenseKeyRegex.hasMatch(segment)) return '{license}';
  if (_emailRegex.hasMatch(segment)) return '{email}';
  if (_stripeIdRegex.hasMatch(segment)) return '{stripe_id}';
  if (_apiKeyRegex.hasMatch(segment)) return '{api_key}';
  // Long opaque tokens (>20 chars, base64url-ish) — likely auth tokens.
  if (segment.length > 20 && _opaqueTokenRegex.hasMatch(segment)) {
    return '{token}';
  }
  return segment;
}

// --- Pattern set ---

class _ScrubPattern {
  const _ScrubPattern(this.regex, this.replacement);
  final RegExp regex;
  final String replacement;
}

/// Order matters: more specific patterns first.
final List<_ScrubPattern> _patterns = [
  _ScrubPattern(_jwtRegex, '[JWT_REDACTED]'),
  _ScrubPattern(_apiKeyRegex, '[API_KEY_REDACTED]'),
  _ScrubPattern(_stripeIdRegex, '[STRIPE_ID_REDACTED]'),
  _ScrubPattern(_emailRegex, '[EMAIL_REDACTED]'),
  _ScrubPattern(_urlPattern, '[URL_REDACTED]'),
  _ScrubPattern(_userPathPattern, '[PATH_REDACTED]'),
  _ScrubPattern(_uuidRegex, '[UUID_REDACTED]'),
  _ScrubPattern(_licenseKeyRegex, '[LICENSE_REDACTED]'),
  _ScrubPattern(_mediaFilePattern, '[MEDIA_REDACTED]'),
];

/// URL pattern: http(s)://...
final _urlPattern = RegExp(r'https?://[^\s\])"]+');

/// User path patterns: consume entire path up to whitespace / quote / paren.
/// Earlier draft only matched the `/Users/<name>` segment, leaving the rest
/// of the path (including potentially-sensitive folder names like
/// `/Users/x/secret-project/`) visible. Fix: greedy until a delimiter.
/// - macOS: /Users/username/...
/// - Linux: /home/username/...
/// - Windows: C:\Users\username\...
final _userPathPattern = RegExp(
  r'(/Users/[^\s"\)\]]+|/home/[^\s"\)\]]+|[A-Z]:\\Users\\[^\s"\)\]]+)',
);

/// Media filename pattern: word.ext (common media extensions)
final _mediaFilePattern = RegExp(
  r'\b[\w\-\.]+\.(mp4|mp3|mkv|avi|mov|webm|m4a|flac|wav|ogg|aac|jpg|jpeg|png|gif|webp)\b',
  caseSensitive: false,
);

/// 32-char hex string with word boundaries — VidCombo / SSvid license keys.
/// Note: this also matches some MD5 hashes; that's an acceptable false-positive
/// because we never want hex-encoded secrets in event payloads anyway.
final _licenseKeyRegex = RegExp(r'\b[0-9a-fA-F]{32}\b');

/// UUID v1-v5: 8-4-4-4-12 hex with hyphens, case-insensitive.
final _uuidRegex = RegExp(
  r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b',
);

/// JWT: three base64url segments separated by dots (rough but effective).
/// First two segments must contain a JSON-y prefix; third can be empty (signature
/// stripping). Min length per segment guards against false positives like `a.b.c`.
final _jwtRegex = RegExp(
  r'\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]*\b',
);

/// Stripe-style IDs: prefix `sk_` or `pk_` followed by `live_`/`test_` and 24+ chars.
/// Also matches the bare `sk_xxx`/`pk_xxx` form some test fixtures use.
final _stripeIdRegex = RegExp(
  r'\b(?:sk|pk|rk)_(?:live_|test_)?[A-Za-z0-9]{16,}\b',
);

/// SSvid API key prefix `snk_` followed by base64url payload.
final _apiKeyRegex = RegExp(r'\bsnk_[A-Za-z0-9_-]{16,}\b');

/// Email addresses — RFC-ish, intentionally broad to catch user input.
final _emailRegex = RegExp(
  r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b',
);

/// Loose check for opaque base64url tokens — only used for path-segment
/// scrubbing where context confirms it's an identifier.
final _opaqueTokenRegex = RegExp(r'^[A-Za-z0-9_-]+$');

// --- Map / collection scrubbers ---

Map<String, dynamic>? _scrubMap(Map<String, dynamic>? input) {
  if (input == null) return null;
  return input.map((k, v) {
    if (v is String) return MapEntry(k, scrubString(v));
    if (v is Map<String, dynamic>) return MapEntry(k, _scrubMap(v));
    if (v is List) return MapEntry(k, _scrubList(v));
    return MapEntry(k, v);
  });
}

List<dynamic> _scrubList(List<dynamic> input) {
  return input.map((v) {
    if (v is String) return scrubString(v);
    if (v is Map<String, dynamic>) return _scrubMap(v);
    if (v is List) return _scrubList(v);
    return v;
  }).toList();
}

Map<String, String>? _scrubTags(Map<String, String>? tags) {
  if (tags == null) return null;
  return tags.map((k, v) => MapEntry(k, scrubString(v)));
}

SentryUser? _scrubUser(SentryUser? user) {
  if (user == null) return null;

  // CRITICAL: do NOT use SentryUser.copyWith here. Its copyWith uses
  // `field ?? this.field` semantics, so passing `ipAddress: null` would
  // PRESERVE the original IP, not clear it. Construct a fresh SentryUser
  // explicitly and only carry forward scrubbed fields.
  final scrubbedId = user.id != null ? scrubString(user.id!) : null;
  final scrubbedUsername =
      user.username != null ? scrubString(user.username!) : null;
  final scrubbedEmail = user.email != null ? scrubString(user.email!) : null;
  final scrubbedName = user.name != null ? scrubString(user.name!) : null;
  final scrubbedData = _scrubMap(user.data);

  // SentryUser asserts at construction time that at least one of
  // `id`/`username`/`email`/`ipAddress`/`segment` is non-null (Sentry 8.x
  // protocol invariant). `data` and `name` do NOT count toward this.
  //
  // CANNOT return null here: SentryEvent.copyWith uses `user ?? this.user`
  // semantics, so a null return would PRESERVE the original (un-scrubbed)
  // user on the outgoing event — defeating the redaction. Instead, return
  // a sentinel SentryUser with a placeholder id so copyWith(user: sentinel)
  // overwrites the original.
  final hasIdentifierForAssert =
      scrubbedId != null || scrubbedUsername != null || scrubbedEmail != null;
  if (!hasIdentifierForAssert) {
    return SentryUser(
      id: '[REDACTED]',
      // Carry forward non-PII fields so post-redaction triage isn't
      // completely blind. ipAddress remains null.
      data: scrubbedData,
      geo: user.geo,
    );
  }

  return SentryUser(
    id: scrubbedId,
    username: scrubbedUsername,
    email: scrubbedEmail,
    name: scrubbedName,
    // Intentionally drop ipAddress entirely. Sentry server can derive a
    // coarse geo from request headers if needed; we never send the raw IP.
    ipAddress: null,
    geo: user.geo,
    data: scrubbedData,
  );
}

Contexts? _scrubContexts(Contexts? contexts) {
  if (contexts == null) return null;
  // Contexts has typed fields (device, OS, runtime, app, browser, gpu,
  // response, culture) PLUS a free-form `Map<String, dynamic>` surface for
  // custom entries set via `Sentry.configureScope((s) => s.setContexts(...))`.
  // We don't currently call `setContexts` ourselves, but a future caller
  // might — and the typed fields themselves are SDK-auto-populated diagnostic
  // data (no user PII).
  //
  // To stay conservative and forward-compatible: copy the typed fields
  // unchanged, then walk the custom map surface and scrub string values.
  // Contexts in sentry-dart 8.x extends `MapView<String, dynamic>`, so it
  // supports `keys` iteration and `[key]` access. Any future SDK shape
  // change that breaks this is caught by analyze.
  final scrubbed = Contexts(
    device: contexts.device,
    operatingSystem: contexts.operatingSystem,
    runtimes:
        contexts.runtimes, // plural in Sentry 8.x — `List<SentryRuntime>?`
    app: contexts.app,
    browser: contexts.browser,
    gpu: contexts.gpu,
    response: contexts.response,
    culture: contexts.culture,
  );
  // Walk custom entries via the MapView interface.
  for (final key in contexts.keys) {
    final value = contexts[key];
    if (value is String) {
      scrubbed[key] = scrubString(value);
    } else if (value is Map<String, dynamic>) {
      scrubbed[key] = _scrubMap(value);
    } else if (value is List) {
      scrubbed[key] = _scrubList(value);
    } else {
      scrubbed[key] = value;
    }
  }
  return scrubbed;
}

SentryRequest? _scrubRequest(SentryRequest? request) {
  if (request == null) return null;
  // Construct a fresh SentryRequest rather than using copyWith — same
  // `?? this.field` footgun as SentryUser; passing null to copyWith would
  // preserve the original value, defeating the redaction.
  return SentryRequest(
    url: request.url != null ? scrubString(request.url!) : null,
    method: request.method,
    // queryString and cookies are never carried — they always carry secrets.
    // We do not pass them through; absence at the call site == cleared.
    data: _scrubRequestData(request.data),
    headers: _scrubHeaders(request.headers),
    // SentryRequest.env is `Map<String, String>?` — _scrubMap returns
    // `Map<String, dynamic>?` which does NOT satisfy that type. Use the
    // string-only scrubber to keep types correct.
    env: _scrubStringMap(request.env),
    fragment: request.fragment != null ? scrubString(request.fragment!) : null,
  );
}

Map<String, String>? _scrubStringMap(Map<String, String>? input) {
  if (input == null) return null;
  return input.map((k, v) => MapEntry(k, scrubString(v)));
}

dynamic _scrubRequestData(dynamic data) {
  if (data == null) return null;
  if (data is String) return scrubString(data);
  if (data is Map<String, dynamic>) return _scrubMap(data);
  if (data is List) return _scrubList(data);
  return data;
}

Map<String, String>? _scrubHeaders(Map<String, String>? headers) {
  if (headers == null) return null;
  final result = <String, String>{};
  for (final entry in headers.entries) {
    final lowerKey = entry.key.toLowerCase();
    // Drop auth-related headers entirely — they always carry secrets.
    if (lowerKey == 'authorization' ||
        lowerKey == 'cookie' ||
        lowerKey == 'x-api-key' ||
        lowerKey == 'x-auth-token' ||
        lowerKey == 'proxy-authorization') {
      result[entry.key] = '[REDACTED]';
      continue;
    }
    result[entry.key] = scrubString(entry.value);
  }
  return result;
}
