import '../entities/download_error_code.dart';

/// Classifies raw exceptions/error strings into structured [DownloadErrorCode].
/// Pure Dart — no dependencies on Flutter or external packages.
class DownloadErrorClassifier {
  /// Classify an error object into a [DownloadErrorCode].
  static DownloadErrorCode classify(Object error) {
    return classifyMessage(error.toString());
  }

  /// Classify an error message string into a [DownloadErrorCode].
  static DownloadErrorCode classifyMessage(String errorMessage) {
    // Structured HTTP status prefixes from Rust engine — check first (exact, no lower-case needed)
    if (errorMessage.startsWith('HTTP_403_FORBIDDEN:')) {
      return DownloadErrorCode.accessDenied;
    }
    if (errorMessage.startsWith('HTTP_410_GONE:')) {
      return DownloadErrorCode.videoNotFound;
    }
    if (errorMessage.startsWith('HTTP_429_TOO_MANY_REQUESTS:')) {
      return DownloadErrorCode.rateLimited;
    }
    if (errorMessage.startsWith('HTTP_404_NOT_FOUND:')) {
      return DownloadErrorCode.videoNotFound;
    }

    final lower = errorMessage.toLowerCase();

    // JS runtime issues — check BEFORE format-unavailable / login-required
    // because yt-dlp's "n challenge solving failed" / "Signature solving
    // failed" stderr lines also contain words like "format" and "sign"
    // that would otherwise misroute. yt-dlp 2025.11.12+ surfaces these
    // signals when the external JS runtime (Deno/Node) is missing.
    if (_matchesAny(lower, _jsRuntimePatterns)) {
      return DownloadErrorCode.jsRuntimeUnavailable;
    }

    // Cookie database locked — yt-dlp issue 7271 surface. MUST be
    // checked BEFORE login-required because the stderr text often
    // co-occurs with a login-required tail (yt-dlp falls through
    // when the cookie store is inaccessible). Classifying as
    // `loginRequired` would push the user into the auto-login flow,
    // which cannot help when the real fix is "try a different
    // browser in the fallback chain".
    if (_matchesAny(lower, _cookieDbLockedPatterns)) {
      return DownloadErrorCode.cookieDbLocked;
    }

    // SSL/TLS errors — check BEFORE network-offline (SSL failures also look like network errors)
    if (_matchesAny(lower, _sslErrorPatterns)) {
      return DownloadErrorCode.sslError;
    }

    // DL-017 — yt-dlp spawn failure MUST beat the network buckets below.
    // Dart's ProcessException.toString() embeds the full command line
    // ("Command: ...yt-dlp.exe --newline ... --socket-timeout 30 ..."),
    // whose literal `--socket-timeout` flag text satisfied the bare
    // 'timeout' pattern → networkTimeout (RETRYABLE) → an infinite
    // futile auto-retry loop while the engine binary was absent
    // (06-11 production wave: 40 rows/day, 94/95 Windows). Match on
    // exception type + binary evidence — locale-independent, because the
    // OS message itself is localized ("The system cannot find the file
    // specified" / 指定されたファイルが見つかりません / 지정된 파일을 찾을 수
    // 없습니다) and can never be safely string-matched.
    if (lower.contains('processexception') &&
        (lower.contains('yt-dlp') || lower.contains('yt_dlp'))) {
      return DownloadErrorCode.ytdlpBinaryMissing;
    }

    // Network errors — order matters: specific WSA / numeric / Chinese
    // markers in timeout + refused buckets must beat the generic
    // `socketexception` substring in _networkOfflinePatterns, otherwise a
    // literal `SocketException: errno = 10060` (WSAETIMEDOUT) gets
    // classified offline and the user sees the wrong recovery copy.
    // _networkOfflinePatterns remains the fallback for plain
    // SocketException + DNS / failed-host-lookup cases.
    if (_matchesAny(lower, _timeoutPatterns)) {
      return DownloadErrorCode.networkTimeout;
    }
    if (_matchesAny(lower, _connectionRefusedPatterns)) {
      return DownloadErrorCode.connectionRefused;
    }
    if (_matchesAny(lower, _networkOfflinePatterns)) {
      return DownloadErrorCode.networkOffline;
    }
    if (_matchesTikTokTransientExtractorError(lower)) {
      return DownloadErrorCode.serverError;
    }
    if (_matchesServerError(lower)) {
      return DownloadErrorCode.serverError;
    }

    // yt-dlp errors (order matters — more specific first)
    if (_matchesAny(lower, _rateLimitedPatterns)) {
      return DownloadErrorCode.rateLimited;
    }
    if (_matchesExplicitLoginRequiredWrapper(lower)) {
      return DownloadErrorCode.loginRequired;
    }
    if (_matchesAccessDenied(lower)) {
      return DownloadErrorCode.accessDenied;
    }
    if (_matchesFacebookCookieRequired(lower)) {
      return DownloadErrorCode.loginRequired;
    }
    if (_matchesAny(lower, _loginRequiredPatterns)) {
      return DownloadErrorCode.loginRequired;
    }
    if (_matchesAny(lower, _geoRestrictedPatterns)) {
      return DownloadErrorCode.geoRestricted;
    }
    if (_matchesAny(lower, _contentUnavailablePatterns)) {
      return DownloadErrorCode.contentUnavailable;
    }
    if (_matchesAny(lower, _ageRestrictedPatterns)) {
      return DownloadErrorCode.ageRestricted;
    }
    if (_matchesAny(lower, _formatUnavailablePatterns)) {
      return DownloadErrorCode.formatUnavailable;
    }
    if (_matchesAny(lower, _videoNotFoundPatterns)) {
      return DownloadErrorCode.videoNotFound;
    }
    if (_matchesAny(lower, _ytdlpBinaryMissingPatterns) ||
        _isPyInstallerSelfExtractFailure(lower)) {
      return DownloadErrorCode.ytdlpBinaryMissing;
    }
    if (_matchesAny(lower, _binaryNotAvailablePatterns)) {
      return DownloadErrorCode.binaryNotAvailable;
    }
    if (_matchesAny(lower, _ffmpegErrorPatterns)) {
      return DownloadErrorCode.ffmpegError;
    }

    // Storage errors
    if (_matchesAny(lower, _diskFullPatterns)) {
      return DownloadErrorCode.diskFull;
    }
    if (_matchesAny(lower, _permissionDeniedPatterns)) {
      return DownloadErrorCode.permissionDenied;
    }
    if (_matchesAny(lower, _pathNotFoundPatterns)) {
      return DownloadErrorCode.pathNotFound;
    }

    return DownloadErrorCode.unknown;
  }

  static bool _matchesAny(String lower, List<String> patterns) {
    return patterns.any((p) => lower.contains(p));
  }

  /// FE-2 review hardening: the bare "decompression resulted in return code"
  /// line is slightly broad on its own, so it is AND-gated with "failed to
  /// extract" — together they are unique to the PyInstaller bootloader's
  /// onefile self-extract failure. The `[pyi-` tag already classifies the
  /// common case; this only adds a tag-stripped variant, without risking a
  /// false positive on any standalone "decompression"/"return code" text.
  static bool _isPyInstallerSelfExtractFailure(String lower) =>
      lower.contains('decompression resulted in return code') &&
      lower.contains('failed to extract');

  static bool _matchesServerError(String lower) {
    // HTTP 500 — require context to avoid false positives on arbitrary "500"
    if (lower.contains('http error 500') ||
        lower.contains('status 500') ||
        lower.contains('error 500')) {
      return true;
    }
    // HTTP 502/503/504 — still use AND gate with context keywords
    if (lower.contains('502') ||
        lower.contains('503') ||
        lower.contains('504')) {
      if (lower.contains('http') ||
          lower.contains('server') ||
          lower.contains('status') ||
          lower.contains('error')) {
        return true;
      }
    }
    if (lower.contains('internal server error') ||
        lower.contains('bad gateway') ||
        lower.contains('service unavailable')) {
      return true;
    }
    // CDN errors (Reddit DASH segments, broken range headers) — retryable
    if (lower.contains('conflicting range') ||
        lower.contains('downloaded file is empty') ||
        lower.contains('requested range not satisfiable')) {
      return true;
    }
    return false;
  }

  static bool _matchesTikTokTransientExtractorError(String lower) {
    if (!lower.contains('tiktok')) return false;
    return _tiktokTransientExtractorPatterns.any(lower.contains);
  }

  static bool _matchesAccessDenied(String lower) {
    // HTTP 403 Forbidden (distinct from filesystem permission denied)
    if (lower.contains('403')) {
      if (lower.contains('http') ||
          lower.contains('forbidden') ||
          lower.contains('status') ||
          lower.contains('error')) {
        return true;
      }
    }
    if (lower.contains('http') && lower.contains('forbidden')) {
      return true;
    }
    return false;
  }

  static bool _matchesExplicitLoginRequiredWrapper(String lower) {
    // The yt-dlp download path intentionally wraps no-cookie YouTube 403s as
    // "Login required: ... Raw yt-dlp error: HTTP Error 403". Keep that
    // explicit decision from being overwritten by the generic 403 matcher,
    // otherwise production telemetry reports these as accessDenied instead of
    // loginRequired.
    return lower.contains('login required:');
  }

  static bool _matchesFacebookCookieRequired(String lower) {
    // P1 (2026-05-25): pre-fix this rule blanket-promoted every
    // `[facebook] ... Cannot parse data` to `loginRequired`. yt-dlp
    // emits "Cannot parse data" for at least two distinct root
    // causes:
    //   (a) Missing / expired Facebook cookies — re-login resolves.
    //   (b) Facebook changed payload shape OR yt-dlp extractor is
    //       stale OR the post is genuinely unparseable — re-login
    //       does NOT help; user is stuck repeatedly logging in.
    //
    // Keep the auto-promotion ONLY when an explicit auth marker
    // co-occurs in the same message. Without such a marker the
    // generic Cannot-parse-data falls through to the standard
    // `_loginRequiredPatterns` check below (which still catches
    // `cookies are needed`, `login required`, `sign in`, etc.)
    // and ultimately to `unknown` so the UX doesn't push a
    // login-spam loop.
    if (!(lower.contains('facebook') &&
        lower.contains('cannot parse data'))) {
      return false;
    }
    // Treat as cookie-required only if there is concrete auth signal
    // in the same message — yt-dlp Facebook extractor sometimes
    // appends `Use --cookies` / `Login required` / `Please log in`
    // when it identifies the session as the bottleneck.
    return _facebookAuthMarkers.any(lower.contains);
  }

  static const _facebookAuthMarkers = [
    'login required',
    'please log in',
    'use --cookies',
    'cookies are needed',
    'sign in',
    'login_required',
    'checkpoint',
    'access denied',
    'session has expired',
    'session expired',
  ];

  // --- Pattern lists ---

  /// JS runtime missing — yt-dlp 2025.11.12+ requires external JS
  /// (Deno/Node/QuickJS) to solve YouTube nsig + n-challenge. Without
  /// it, `format_unavailable` / `formatNotAvailable` is the symptom
  /// for video extraction, but stderr also surfaces these specific
  /// strings indicating the runtime is the actual blocker.
  static const _jsRuntimePatterns = [
    'n challenge solving failed',
    'signature solving failed',
    'external javascript runtime',
    'no usable javascript runtime',
    'could not find any usable javascript',
    'jsruntimeunavailable',
  ];

  /// yt-dlp `--cookies-from-browser <name>` failure modes when the
  /// browser cookie store cannot be read: DB locked by the browser,
  /// unsupported browser/profile, or Windows DPAPI decrypt failure.
  /// Patterns are LOWERCASED — caller `.toLowerCase()`s the message
  /// before matching.
  ///
  /// Source: yt-dlp `youtube_dl/cookies.py` error sites. The
  /// "could not copy" wording is what Windows production log
  /// 2026-05-12 §138 surfaced when Chrome was running.
  static const _cookieDbLockedPatterns = [
    'could not copy chrome cookie database',
    'could not copy edge cookie database',
    'could not copy brave cookie database',
    'could not copy vivaldi cookie database',
    'could not copy opera cookie database',
    'could not copy chromium cookie database',
    'could not copy firefox cookie database',
    'could not copy safari cookie database',
    // Generic forms — also surfaced by yt-dlp on some platforms
    'could not copy cookie database',
    'unsupported browser',
    'unable to load cookies from',
    // Windows Chrome/Edge cookie decrypt failures (yt-dlp issue 10927).
    // Same user-action class as a locked browser DB: the external
    // browser cookie source is unusable.
    'failed to decrypt with dpapi',
    'failed to decrypt cookie',
    'failed to decrypt cookies',
    'cryptunprotectdata',
  ];

  static const _sslErrorPatterns = [
    'certificate_verify_failed',
    'handshakeexception',
    'bad certificate',
    'tlsexception',
    'ssl error',
    'certificate has expired',
    'unable to get local issuer certificate',
  ];

  static const _networkOfflinePatterns = [
    'socketexception',
    'networkexception',
    'no internet',
    'network is unreachable',
    'no address associated',
    'failed host lookup',
    'network error',
  ];

  static const _timeoutPatterns = [
    'timeoutexception',
    'timed out',
    'timeout',
    'connection timed out',
    // Windows Sockets timeout (WSAETIMEDOUT). Surfaces from Dart's
    // SocketException as a numeric code (10060) without the English
    // 'timed out' marker; before this entry it routed to `unknown`.
    'wsaetimedout',
    '10060',
    'errno = 10060',
    // Chinese (Simplified) Windows locale uses '信号灯超时' (semaphore
    // timed out) for the same WSAETIMEDOUT code. Real users in CN
    // production telemetry surface this exact phrase, which previously
    // bypassed every English-only pattern and routed to `unknown`.
    '信号灯超时',
    // Traditional Chinese equivalent surfaced by Windows zh-TW locale.
    '信號燈逾時',
    // Japanese Windows locale (ja-JP) surfaces WSAETIMEDOUT as
    // 'セマフォがタイムアウトしました' (literally "the semaphore timed out").
    // Real production capture in log2.md 2026-05-23 — v1.6.2 macOS user
    // with JP locale hit this and routed to `unknown` until now.
    'セマフォがタイムアウトしました',
    // Korean Windows locale (ko-KR) surfaces the same WSAETIMEDOUT as
    // '세마포 시간이 초과되었습니다'. Adding alongside the JP/CN siblings
    // so all CJK Windows locales classify consistently.
    '세마포 시간이 초과되었습니다',
  ];

  static const _connectionRefusedPatterns = [
    'connection refused',
    'connection reset',
    'connection closed',
    'dns resolution',
    'dns lookup',
    'getaddrinfo',
    'econnrefused',
    'econnreset',
    // WSAECONNREFUSED (10061) — Windows numeric counterpart that
    // surfaces without the English marker on non-English Windows.
    '10061',
    'wsaeconnrefused',
  ];

  static const _rateLimitedPatterns = [
    'too many requests',
    'http error 429',
    'http_429',
    'status 429',
    'rate limit',
    'rate-limit',
    'throttl',
    'please wait a few minutes',
  ];

  static const _tiktokTransientExtractorPatterns = [
    'unexpected response from webpage request',
    'unable to extract universal data for rehydration',
  ];

  static const _loginRequiredPatterns = [
    'login required',
    'sign in',
    'authentication',
    'private video',
    'members-only',
    'cookies are needed',
    'use cookies',
    'pass cookies',
    'premium',
    'requires payment',
    'requires a subscription',
    'subscriber only',
    'checkpoint required',
  ];

  static const _geoRestrictedPatterns = [
    'geo restrict',
    'geo-restrict',
    'not available in your country',
    'geographically restricted',
    'blocked in your',
  ];

  static const _ageRestrictedPatterns = [
    'age restrict',
    'age-restrict',
    'age gate',
    'age verification',
    'confirm your age',
  ];

  static const _formatUnavailablePatterns = [
    'requested format',
    'format not available',
    'format is not available',
    'no video formats found',
    // DL-004 (06-09 telemetry): "youtube returned only restricted
    // low-quality" — a format-availability restriction (B7/DL-006 family),
    // previously unknown. Checked AFTER the jsRuntime patterns, so the
    // "only restricted low-quality" Deno-missing symptom is already routed
    // to jsRuntimeUnavailable upstream.
    //
    // NOTE — NOT behavior-neutral (unlike the other DL-004 mappings):
    // formatUnavailable intentionally enters StartDownloadUseCase's existing
    // download-stage recovery — `_shouldRetryWithoutCookiesAfterDownloadError`
    // (:1118 → one no-cookie retry) and `isCookieRecoverable` (:1967 →
    // advance the cookie/browser chain). That recovery is the correct toolkit
    // for a cookie/client-tier format restriction, so the routing is BY
    // DESIGN. Coupling is locked by start_download_usecase_test.dart
    // ("keeps existing formatUnavailable cookie retry on all platforms").
    'restricted low-quality',
  ];

  static const _contentUnavailablePatterns = [
    'copyright',
    'dmca',
    'terms of service',
    'community guidelines',
    'content is not available',
    'removed by the uploader',
    'taken down',
    'is unavailable',
    'has been removed',
    'drm protected',
    'drm',
    'terminated',
    // DL-004 (06-09 telemetry): extraction produced no output — "no
    // downloadable content found at this url" / "no files were downloaded".
    // Checked BEFORE videoNotFound so these land in contentUnavailable.
    'no downloadable content',
    'no files were downloaded',
  ];

  static const _videoNotFoundPatterns = [
    'video unavailable',
    'not a valid url',
    'is not a valid url',
    'video not found',
    'page not found',
    'this video has been removed',
    'this video is no longer available',
    'unable to extract',
    'unsupported url',
    'content not found',
  ];

  static const _ytdlpBinaryMissingPatterns = [
    'yt-dlp not found',
    'yt-dlp binary',
    'no such file or directory: yt-dlp',
    'cannot find yt-dlp',
    // DL-004 (06-09 telemetry): Rust FFI could not spawn the binary
    // ("failed to execute yt-dlp caused by ..."). Behavior-safe: this code
    // is non-retryable and the client classifier does not trigger binary
    // repair (Deno/ffmpeg repair runs off the Rust YtDlpErrorType, not this
    // enum). Interpretation: execution failure ⇒ binary unavailable/blocked.
    'failed to execute yt-dlp',
    // FE-2 (2026-06-25 live probe): on Windows the bundled yt-dlp.exe is a
    // PyInstaller onefile; its bootloader can fail to self-extract the packed
    // .pyd/.dll into %TEMP%\_MEIxxxx — "[PYI-NNNNN:ERROR] Failed to extract
    // <name>.pyd: decompression resulted in return code -1". The engine then
    // can't run, so this is the binary-unavailable family — not a generic
    // `unknown`. 36 distinct current-build (1.7.5/1.4.4) devices were hidden
    // in the `unknown` bucket. Markers are PyInstaller-bootloader-internal
    // (the `[pyi-` tag / decompression return code / runtime-hook frame), so
    // they cannot collide with yt-dlp's own video-"extraction" errors. The
    // bare "decompression resulted in return code" form is handled separately
    // via [_isPyInstallerSelfExtractFailure] (AND-gated with "failed to
    // extract") so it cannot false-positive on its own.
    '[pyi-',
    'pyi_rth_',
  ];

  static const _binaryNotAvailablePatterns = [
    'exec format error',
    'bad cpu type',
    'cannot execute binary file',
  ];

  static const _ffmpegErrorPatterns = [
    'postprocessor',
    'postprocessing',
    // DL-004 (06-09 telemetry): real stderr says "post-processing"
    // (hyphenated) — the un-hyphenated 'postprocessing' above missed every
    // "ffmpeg post-processing exceeded Nm" timeout row (→ unknown bucket).
    'post-processing',
    // Literal classifier/diagnostic prefix "ffmpegerror:" — the spaced
    // 'ffmpeg error' below never matched it, so "ffmpegerror:ffmpeg merge
    // exceeded" landed in unknown.
    'ffmpegerror',
    'ffmpeg not found',
    'ffmpeg error',
    'ffmpeg: error',
    'ffmpeg or avconv',
    'merging formats',
    // FFmpeg merge-phase timeout ("ffmpeg merge exceeded Nm") — distinct
    // wording from 'merging formats'.
    'merge exceeded',
    'ffmpeg merge',
    'conversion failed',
    // Recode post-process failure ("recode to .mp4 failed. try mp4 or mkv").
    'recode to ',
    // ffprobe verification gate ("ffprobe is required to verify the 1080p
    // resolution cap") — ffmpeg-family, also the DL-005 signal.
    'ffprobe is required',
    // App/process interrupted during the conversion (recode) phase.
    'interrupted during conversion',
  ];

  static const _diskFullPatterns = [
    'no space left',
    'disk full',
    'enospc',
    'not enough disk space',
    'not enough space',
  ];

  static const _permissionDeniedPatterns = [
    'permission denied',
    'eacces',
    'access denied',
    'operation not permitted',
  ];

  static const _pathNotFoundPatterns = [
    'no such file or directory',
    'path not found',
    'directory does not exist',
    'directory not found',
    // WIN-1/DL-007: a path that exceeds the OS limit is a folder/path problem,
    // not a missing file. Covers the app's upfront preflight message AND a real
    // runtime ENAMETOOLONG / Windows "path too long" so neither falls to the
    // generic `unknown` bucket.
    'path is too long',
    'path too long',
    'filename too long',
    'file name too long',
    'filename or extension is too long',
    'enametoolong',
  ];
}
