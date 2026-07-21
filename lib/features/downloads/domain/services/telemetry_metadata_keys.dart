/// Schema constants + extractors for the structured metadata map that
/// every download / extraction failure telemetry event ships back to the
/// Go backend (`/v1/download-errors`).
///
/// Without a documented schema, emit sites historically improvised keys
/// (`http_status`, `httpStatus`, `http_code`…) and lookups on the backend
/// dashboard misaligned. The constants below are the single source of
/// truth — every new emit site MUST use these keys for the documented
/// fields. Free-form metadata (per-platform, per-stage) is still allowed
/// alongside.
///
/// Keep keys snake_case to match the Go backend's column convention.
class TelemetryMetadataKeys {
  TelemetryMetadataKeys._();

  // ── Error classification ─────────────────────────────────────────────

  /// First-pass classification of the raw error string before any
  /// policy override (cookie-retry preservation, login-loop guard,
  /// circuit-breaker rewrite). Populate ALONGSIDE the final
  /// classification ([terminalErrorCode]) when an override flipped the
  /// code — the dashboard can then ask "how often does policy X change
  /// classification Y?" without re-deriving from raw messages.
  static const String originalErrorCode = 'original_error_code';

  /// Final classification after all policy overrides. Equal to the
  /// top-level `errorCode` on the telemetry sink; duplicated in
  /// metadata so the backend can index without joining tables.
  static const String effectiveErrorCode = 'effective_error_code';

  /// Same as [effectiveErrorCode] — preserved for backwards-compat with
  /// pre-schema emit sites that already shipped this key. New code
  /// should write BOTH so the migration is invisible to dashboards.
  static const String terminalErrorCode = 'terminal_error_code';

  // ── Attempt sequencing ───────────────────────────────────────────────

  /// 0-indexed retry attempt that produced this failure. 0 = the
  /// initial attempt, 1 = first retry, etc. Distinct from internal
  /// fallback-chain cursors (cookies-from-browser fallback, format
  /// fallback) which have their own keys.
  static const String attemptIndex = 'attempt_index';

  // ── Transport / protocol context ─────────────────────────────────────

  /// yt-dlp's format protocol when the failure pinned to a single
  /// format: 'http', 'https', 'http_dash_segments', 'm3u8_native',
  /// 'm3u8', 'rtmp', 'rtsp', etc. Lets the dashboard split error rates
  /// by protocol family — DASH segment failures look very different
  /// from plain HTTPS GET failures.
  static const String formatProtocol = 'format_protocol';

  /// Integer HTTP status code when the failure was an HTTP response
  /// error (403/410/429/5xx). Extracted from yt-dlp stderr or the
  /// download stream error envelope. Use [extractHttpStatusCode] to
  /// pull this out of an arbitrary error string at emit time.
  static const String httpStatusCode = 'http_status_code';

  // ── Helpers ──────────────────────────────────────────────────────────

  /// Pull a numeric HTTP status code out of [message] if one is
  /// embedded. Recognises the canonical yt-dlp shapes:
  ///   * `HTTP Error 403: Forbidden`
  ///   * `HTTP error 410`
  ///   * `status 429`
  ///   * `HTTP_403_FORBIDDEN: …` (Rust executor prefix)
  /// Returns null when no status code can be confidently extracted.
  static int? extractHttpStatusCode(String message) {
    final lower = message.toLowerCase();
    // Rust executor `HTTP_<code>_<NAME>:` prefix — most reliable shape.
    final structured = RegExp(r'http_(\d{3})_').firstMatch(lower);
    if (structured != null) {
      return int.tryParse(structured.group(1)!);
    }
    // yt-dlp text: 'HTTP Error 403', 'HTTP error 410', etc.
    final ytDlpText = RegExp(r'http\s*error\s+(\d{3})').firstMatch(lower);
    if (ytDlpText != null) {
      return int.tryParse(ytDlpText.group(1)!);
    }
    // Generic: 'status 502', 'status code 504', etc.
    final genericStatus = RegExp(
      r'status(?:\s*code)?\s+(\d{3})',
    ).firstMatch(lower);
    if (genericStatus != null) {
      return int.tryParse(genericStatus.group(1)!);
    }
    return null;
  }

  /// Pull the yt-dlp format protocol family from [message] if visible.
  /// Recognises stderr fragments yt-dlp emits when a single format
  /// failed mid-download. Returns null when the failure was not
  /// scoped to a particular protocol.
  static String? extractFormatProtocol(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('http_dash_segments') ||
        lower.contains('dash segment') ||
        lower.contains('dash manifest')) {
      return 'http_dash_segments';
    }
    if (lower.contains('m3u8_native')) return 'm3u8_native';
    if (lower.contains('.m3u8') || lower.contains('hls manifest')) {
      return 'm3u8';
    }
    if (lower.contains('rtmp://') || lower.contains('rtmp ')) return 'rtmp';
    if (lower.contains('rtsp://') || lower.contains('rtsp ')) return 'rtsp';
    // Plain HTTP only counts if we also saw an HTTP status — otherwise
    // every TCP failure would claim the bucket.
    if (extractHttpStatusCode(message) != null) {
      return lower.contains('https') ? 'https' : 'http';
    }
    return null;
  }
}
