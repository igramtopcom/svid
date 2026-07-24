import 'dart:io' show Platform;

import '../../../../core/binaries/binary_info.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/services/circuit_breaker_service.dart';
import '../../../../core/utils/file_utils.dart';
import '../../../../core/utils/platform_detector.dart';
import '../../../settings/domain/enums/download_engine.dart';
import '../../data/datasources/gallerydl_datasource.dart';
import '../../data/datasources/ytdlp_datasource.dart';
// VideoInfoMapper file was removed in commit 5a2aab0f (deep cleanup).
// Inline conversion below preserves V2 API-only fallback path.
import '../../data/remote/api/svid_api_service.dart';
import '../entities/download_error_code.dart';
import '../entities/video_info.dart';
import '../services/download_error_classifier.dart';
import '../services/download_referer_holder.dart';
import '../services/platform_quality_hint.dart';
import '../services/telemetry_metadata_keys.dart';

/// Severity classification for an extraction failure — drives whether
/// the circuit breaker counter increments. See
/// [ExtractVideoInfoUseCase._classifySeverity] for the typed +
/// regex-driven decision flow.
enum _ExtractionFailureSeverity {
  /// Per-URL or per-cookies issue — refreshing cookies / picking a
  /// different URL fixes it. Must NOT trip the platform-wide circuit.
  userInduced,

  /// Platform / extractor genuinely degraded (HTTP 5xx, persistent
  /// timeout, parser broken) — cooldown is appropriate.
  platformBroken,
}

typedef ExtractionFailureTelemetrySink =
    void Function({
      required String url,
      required String platform,
      required DownloadErrorCode errorCode,
      required String errorPhase,
      required String errorMessage,
      required Map<String, dynamic> metadata,
    });

/// Use case to extract video information from URL
///
/// Engine behavior:
/// - ytdlpOnly: ONLY use yt-dlp, fail if not available or fails
/// - apiOnly: ONLY use API, never try yt-dlp
/// - auto + fallback enabled: Try yt-dlp first, fallback to API on failure
/// - auto + fallback disabled: Try yt-dlp first, fail if not available or fails
class ExtractVideoInfoUseCase {
  final SvidApiService _apiService;
  final YtDlpDataSource _ytdlpDataSource;
  final GalleryDlDataSource _galleryDlDataSource;
  final CircuitBreakerService? _circuitBreaker;
  final ExtractionFailureTelemetrySink? _extractionFailureTelemetrySink;
  // Injectable for testing — production default is a real 3-second delay.
  final Future<void> Function(Duration) _delay;

  ExtractVideoInfoUseCase(
    this._apiService,
    this._ytdlpDataSource,
    this._galleryDlDataSource, {
    CircuitBreakerService? circuitBreaker,
    ExtractionFailureTelemetrySink? extractionFailureTelemetrySink,
    Future<void> Function(Duration)? delay,
  }) : _circuitBreaker = circuitBreaker,
       _extractionFailureTelemetrySink = extractionFailureTelemetrySink,
       _delay = delay ?? Future.delayed;

  /// Extract video info with strategy based on settings
  ///
  /// [cookiesFromBrowser] is the user's EXPLICITLY chosen browser for
  /// `--cookies-from-browser` (from Settings). Null when the user hasn't
  /// configured one.
  ///
  /// [cookiesFromBrowserFallback] is the AUTO-DETECTED browser used as a
  /// last-resort retry when the primary path fails with a user-induced
  /// error (loginRequired / formatNotAvailable). Distinct from
  /// [cookiesFromBrowser] because:
  ///   1. It only fires on retry — not the first attempt — so the user's
  ///      privacy-default of "no browser cookie reads" is respected on
  ///      every successful extraction.
  ///   2. It triggers a one-time platform credential prompt
  ///      (Keychain on macOS, etc.) that we want to lazy-trigger only
  ///      when the user is already invested in a failed download, not
  ///      surprise them on the very first paste.
  Future<Result<VideoInfo>> call(
    String url, {
    DownloadEngine engine = DownloadEngine.auto,
    bool enableFallback = true,
    String? cookiesFile,
    String? cookiesFromBrowser,
    String? cookiesFromBrowserFallback,
    List<String>? cookiesFromBrowserFallbackChain,
    String? proxyUrl,
    bool stopOnLoginRequired = false,
  }) async {
    appLogger.debug(
      '🔧 [Extract] Engine: ${engine.name}, Fallback: $enableFallback',
    );

    switch (engine) {
      // ========== YT-DLP ONLY MODE ==========
      // NEVER use API, fail if yt-dlp fails
      case DownloadEngine.ytdlpOnly:
        appLogger.info('🎯 [Extract] Mode: yt-dlp ONLY (no fallback)');

        return _dispatchExtraction(
          url,
          cookiesFile: cookiesFile,
          cookiesFromBrowser: cookiesFromBrowser,
          cookiesFromBrowserFallback: cookiesFromBrowserFallback,
          cookiesFromBrowserFallbackChain: cookiesFromBrowserFallbackChain,
          proxyUrl: proxyUrl,
          stopOnLoginRequired: stopOnLoginRequired,
        );

      // ========== API ONLY MODE ==========
      // NEVER use yt-dlp
      case DownloadEngine.apiOnly:
        appLogger.info('🎯 [Extract] Mode: API ONLY (no yt-dlp)');
        return _extractWithApiRetry(url, retryCount: 0);

      // ========== AUTO MODE ==========
      case DownloadEngine.auto:
        return _extractWithAutoMode(
          url,
          enableFallback: enableFallback,
          cookiesFile: cookiesFile,
          cookiesFromBrowser: cookiesFromBrowser,
          cookiesFromBrowserFallback: cookiesFromBrowserFallback,
          cookiesFromBrowserFallbackChain: cookiesFromBrowserFallbackChain,
          proxyUrl: proxyUrl,
          stopOnLoginRequired: stopOnLoginRequired,
        );
    }
  }

  /// Auto mode extraction logic
  Future<Result<VideoInfo>> _extractWithAutoMode(
    String url, {
    required bool enableFallback,
    String? cookiesFile,
    String? cookiesFromBrowser,
    String? cookiesFromBrowserFallback,
    List<String>? cookiesFromBrowserFallbackChain,
    String? proxyUrl,
    bool stopOnLoginRequired = false,
  }) async {
    if (enableFallback) {
      appLogger.info('🎯 [Extract] Mode: AUTO (yt-dlp first, API fallback)');
    } else {
      appLogger.info('🎯 [Extract] Mode: AUTO (yt-dlp first, NO fallback)');
    }

    // Step 1: Try yt-dlp. Do not preflight `isAvailable()` here:
    // DL-016 repair lives at the datasource spawn gate. A preflight false
    // would bypass the repair path and fall back/fail while the binary is
    // still recoverable.
    final ytdlpResult = await _dispatchExtraction(
      url,
      cookiesFile: cookiesFile,
      cookiesFromBrowser: cookiesFromBrowser,
      cookiesFromBrowserFallback: cookiesFromBrowserFallback,
      cookiesFromBrowserFallbackChain: cookiesFromBrowserFallbackChain,
      proxyUrl: proxyUrl,
      stopOnLoginRequired: stopOnLoginRequired,
    );

    if (ytdlpResult.isSuccess) {
      return ytdlpResult;
    }

    if (stopOnLoginRequired && _isLoginRequiredResult(ytdlpResult)) {
      appLogger.warning(
        '[Extract] yt-dlp reported login required; preserving failure '
        'for the first-login prompt instead of using API fallback.',
      );
      return ytdlpResult;
    }

    if (_isYtdlpBinaryMissingResult(ytdlpResult)) {
      appLogger.warning(
        '[Extract] yt-dlp binary missing after bounded repair; preserving '
        'terminal ytdlpBinaryMissing failure instead of using API fallback.',
      );
      return ytdlpResult;
    }

    // Step 2: yt-dlp failed - check fallback
    if (enableFallback) {
      appLogger.warning('⚠️ [Extract] yt-dlp failed, using API fallback...');
      return _extractWithApiRetry(url, retryCount: 0);
    }

    // No fallback - return the failure
    appLogger.error('❌ [Extract] yt-dlp failed and fallback disabled!');
    return ytdlpResult;
  }

  /// Platforms where posts can be images/carousels (gallery-dl handles these).
  /// For these platforms, run yt-dlp + gallery-dl in parallel to avoid
  /// sequential wait (yt-dlp ~3-5s + gallery-dl PyInstaller ~5-7s).
  static const _imageCapablePlatforms = {
    VideoPlatform.instagram,
    VideoPlatform.pinterest,
    VideoPlatform.twitter,
    VideoPlatform.reddit,
    VideoPlatform.tiktok,
    VideoPlatform.facebook,
  };

  /// Route to [_extractWithClientFallback] for YouTube URLs (uses multi-client chain),
  /// or [_extractWithYtdlp] directly for all other platforms.
  /// For image-capable platforms, runs gallery-dl in parallel to avoid sequential delay.
  ///
  /// **Circuit-breaker single source of truth**: this dispatcher is the
  /// ONE place that records extraction outcomes for the platform-level
  /// circuit breaker. Inner paths (YouTube fallback chain, image-capable
  /// parallel race, plain yt-dlp, retry-without-cookies) MUST NOT call
  /// `recordSuccess` / `recordFailure` themselves — recording at multiple
  /// layers either double-counts (causing the original conflation bug)
  /// or skips entire platforms (causing the regression flagged by
  /// reviewer 2026-05-07: non-YouTube paths had no recording at all).
  /// See `feedback_circuit_breaker_counter_conflation.md`.
  Future<Result<VideoInfo>> _dispatchExtraction(
    String url, {
    String? cookiesFile,
    String? cookiesFromBrowser,
    String? cookiesFromBrowserFallback,
    List<String>? cookiesFromBrowserFallbackChain,
    String? proxyUrl,
    bool stopOnLoginRequired = false,
  }) async {
    final result = await _runDispatch(
      url,
      cookiesFile: cookiesFile,
      cookiesFromBrowser: cookiesFromBrowser,
      cookiesFromBrowserFallback: cookiesFromBrowserFallback,
      cookiesFromBrowserFallbackChain: cookiesFromBrowserFallbackChain,
      proxyUrl: proxyUrl,
      stopOnLoginRequired: stopOnLoginRequired,
    );

    final platform = PlatformDetector.detectPlatform(url).name;
    if (result.isSuccess) {
      _circuitBreaker?.recordSuccess(platform);
    } else {
      final exception = result.exceptionOrNull;
      final severity = _classifySeverity(exception);
      switch (severity) {
        case _ExtractionFailureSeverity.userInduced:
          appLogger.info(
            '⚪ [CircuitBreaker] $platform failure ignored '
            '(user-induced: $exception)',
          );
        case _ExtractionFailureSeverity.platformBroken:
          _circuitBreaker?.recordFailure(platform);
      }
      _emitExtractionFailureTelemetry(
        url: url,
        platform: platform,
        exception: exception,
        cookiesFile: cookiesFile,
        cookiesFromBrowser: cookiesFromBrowser,
        cookiesFromBrowserFallbackChain: cookiesFromBrowserFallbackChain,
        stopOnLoginRequired: stopOnLoginRequired,
      );
    }
    return result;
  }

  void _emitExtractionFailureTelemetry({
    required String url,
    required String platform,
    required Object? exception,
    required String? cookiesFile,
    required String? cookiesFromBrowser,
    required List<String>? cookiesFromBrowserFallbackChain,
    required bool stopOnLoginRequired,
  }) {
    final sink = _extractionFailureTelemetrySink;
    if (sink == null) return;

    try {
      final message = exception?.toString() ?? 'unknown';
      final errorCode = DownloadErrorClassifier.classifyMessage(message);
      final ytdlpMetadata =
          exception is YtDlpException
              ? Map<String, dynamic>.from(exception.metadata)
              : <String, dynamic>{};
      final lower = message.toLowerCase();
      sink(
        url: url,
        platform: platform,
        errorCode: errorCode,
        errorPhase: 'extraction',
        errorMessage: '${errorCode.name}:$message',
        metadata: {
          ...ytdlpMetadata,
          'stage': 'extract',
          'yt_dlp_channel': ytDlpReleaseChannel,
          if (!ytdlpMetadata.containsKey('yt_dlp_version'))
            'yt_dlp_version': _ytdlpDataSource.version ?? 'unknown',
          'platform': platform,
          'os': Platform.operatingSystem,
          'is_youtube': platform == 'youtube',
          'local_cookies_file_present': cookiesFile != null,
          'local_cookies_from_browser': cookiesFromBrowser,
          'fallback_chain_length': cookiesFromBrowserFallbackChain?.length ?? 0,
          'stop_on_login_required': stopOnLoginRequired,
          // C5 telemetry schema (see TelemetryMetadataKeys). Backward-
          // compat key `terminal_error_code` kept alongside.
          TelemetryMetadataKeys.terminalErrorCode: errorCode.name,
          TelemetryMetadataKeys.effectiveErrorCode: errorCode.name,
          if (TelemetryMetadataKeys.extractHttpStatusCode(message) != null)
            TelemetryMetadataKeys.httpStatusCode:
                TelemetryMetadataKeys.extractHttpStatusCode(message),
          if (TelemetryMetadataKeys.extractFormatProtocol(message) != null)
            TelemetryMetadataKeys.formatProtocol:
                TelemetryMetadataKeys.extractFormatProtocol(message),
          'looks_like_http_403': _containsAny(lower, const [
            'http error 403',
            '403: forbidden',
            'http_403_forbidden',
            'status 403',
          ]),
          'looks_like_login_required': _containsAny(lower, const [
            'login required',
            'sign in to confirm',
            'requested authentication',
          ]),
          'looks_like_js_runtime_issue': _containsAny(lower, const [
            'n challenge solving failed',
            'signature solving failed',
            'external javascript runtime',
            'no usable javascript runtime',
            'deno:',
          ]),
          'error_detail_excerpt': _truncateForTelemetry(message, 500),
        },
      );
    } catch (_) {
      // Telemetry must never affect extraction or auto-login flow.
    }
  }

  static bool _containsAny(String value, List<String> needles) {
    return needles.any(value.contains);
  }

  static String _truncateForTelemetry(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}…';
  }

  Future<Result<VideoInfo>> _runDispatch(
    String url, {
    String? cookiesFile,
    String? cookiesFromBrowser,
    String? cookiesFromBrowserFallback,
    List<String>? cookiesFromBrowserFallbackChain,
    String? proxyUrl,
    bool stopOnLoginRequired = false,
  }) {
    final platform = PlatformDetector.detectPlatform(url);
    if (platform == VideoPlatform.youtube) {
      return _extractWithClientFallback(
        url,
        cookiesFile: cookiesFile,
        cookiesFromBrowser: cookiesFromBrowser,
        cookiesFromBrowserFallback: cookiesFromBrowserFallback,
        cookiesFromBrowserFallbackChain: cookiesFromBrowserFallbackChain,
        proxyUrl: proxyUrl,
        stopOnLoginRequired: stopOnLoginRequired,
      );
    }

    // For image-capable platforms, pre-warm gallery-dl in parallel with yt-dlp
    // so fallback is instant instead of waiting for PyInstaller startup.
    //
    // RC10.1 of Ultra Plan v3 — exception: Facebook reel / watch /
    // share/r/ / video/ URLs are confirmed VIDEO and gallery-dl
    // CANNOT handle them (returns "Unsupported URL" with ~500ms
    // wasted startup + log noise + complicates auth recovery).
    // Route confirmed-video Facebook URLs straight to yt-dlp.
    // Image and ambiguous Facebook URLs (e.g., /posts/<id> which
    // can be text/image/video) still go through the parallel path
    // so carousel posts work. Instagram /p/<id> intentionally stays
    // parallel — it's genuinely ambiguous (post can be 1 image, 10
    // carousel, or video, only resolvable at full page load).
    if (_imageCapablePlatforms.contains(platform)) {
      if (platform == VideoPlatform.facebook &&
          PlatformDetector.detectFacebookMediaType(url) ==
              FacebookMediaType.video) {
        return _extractWithYtdlp(
          url,
          cookiesFile: cookiesFile,
          cookiesFromBrowser: cookiesFromBrowser,
          cookiesFromBrowserFallback: cookiesFromBrowserFallback,
          cookiesFromBrowserFallbackChain: cookiesFromBrowserFallbackChain,
          proxyUrl: proxyUrl,
          stopOnLoginRequired: stopOnLoginRequired,
        );
      }
      return _extractWithParallelGalleryDl(
        url,
        cookiesFile: cookiesFile,
        cookiesFromBrowser: cookiesFromBrowser,
        cookiesFromBrowserFallback: cookiesFromBrowserFallback,
        cookiesFromBrowserFallbackChain: cookiesFromBrowserFallbackChain,
        proxyUrl: proxyUrl,
      );
    }

    return _extractWithYtdlp(
      url,
      cookiesFile: cookiesFile,
      cookiesFromBrowser: cookiesFromBrowser,
      cookiesFromBrowserFallback: cookiesFromBrowserFallback,
      cookiesFromBrowserFallbackChain: cookiesFromBrowserFallbackChain,
      proxyUrl: proxyUrl,
      stopOnLoginRequired: stopOnLoginRequired,
    );
  }

  /// Extract with yt-dlp + gallery-dl running in parallel.
  /// yt-dlp is the primary source (better for video). gallery-dl runs alongside
  /// so if yt-dlp returns no formats (image post), gallery-dl result is ready instantly.
  Future<Result<VideoInfo>> _extractWithParallelGalleryDl(
    String url, {
    String? cookiesFile,
    String? cookiesFromBrowser,
    String? cookiesFromBrowserFallback,
    List<String>? cookiesFromBrowserFallbackChain,
    String? proxyUrl,
  }) async {
    // Start both extractions in parallel
    final galleryDlFuture = _extractWithGalleryDl(
      url,
      cookiesFile: cookiesFile,
    );
    final ytdlpFuture = _extractWithYtdlp(
      url,
      cookiesFile: cookiesFile,
      cookiesFromBrowser: cookiesFromBrowser,
      cookiesFromBrowserFallback: cookiesFromBrowserFallback,
      cookiesFromBrowserFallbackChain: cookiesFromBrowserFallbackChain,
      proxyUrl: proxyUrl,
      skipGalleryDlFallback: true, // gallery-dl already running in parallel
    );

    // Wait for yt-dlp first (primary source)
    final ytdlpResult = await ytdlpFuture;
    if (ytdlpResult.isSuccess) return ytdlpResult;

    // yt-dlp failed or had no formats — use gallery-dl result (already running/completed)
    appLogger.info('🖼️ [parallel] yt-dlp had no result, using gallery-dl...');
    final galleryResult = await galleryDlFuture;
    if (galleryResult.isSuccess) {
      // Outcome recording happens at `_dispatchExtraction` outer wrapper
      // — single source of truth across all paths.
      return galleryResult;
    }

    // Both failed — propagate login-required if gallery-dl detected it
    if (_isLoginRequiredResult(galleryResult)) return galleryResult;

    // Return yt-dlp error (more informative for video URLs)
    return ytdlpResult;
  }

  /// YouTube player client fallback chain.
  /// Attempt order: default (ios,web) → android → android_creator → tv_embedded.
  /// Each attempt uses an escalating timeout.
  /// Only used for YouTube URLs when the default client fails.
  static const _clientChain = [
    'mweb,web',
    'android',
    'android_creator',
    'tv_embedded',
  ];
  // Timeouts per attempt: default(30s), mweb/web(45s), android(60s),
  // android_creator(75s), tv_embedded(90s).
  static const _clientTimeouts = [30, 45, 60, 75, 90];

  /// Try extraction with each YouTube player client in the fallback chain.
  /// [attempt] 0 = default client (ios,web), 1+ = _clientChain[attempt-1].
  ///
  /// **Circuit breaker contract**: This orchestrator records exactly
  /// ONE outcome per logical extraction (one user click), regardless
  /// of how many fallback clients run inside. Recording per-client
  /// would count a single user request as 3-4 failures, tripping the
  /// 3-failure threshold mid-chain — the bug that made retries fail
  /// for 60+ seconds even after YouTube cleared. Severity gate skips
  /// recording entirely for user-induced errors (bad cookies, format
  /// unavailable, video private) so those don't block other unrelated
  /// videos on the same platform.
  Future<Result<VideoInfo>> _extractWithClientFallback(
    String url, {
    String? cookiesFile,
    String? cookiesFromBrowser,
    String? cookiesFromBrowserFallback,
    List<String>? cookiesFromBrowserFallbackChain,
    String? proxyUrl,
    int attempt = 0,
    bool stopOnLoginRequired = false,
  }) async {
    // Outcome recording happens at `_dispatchExtraction` outer wrapper —
    // single source of truth across all platforms (YouTube, image-capable,
    // generic). The fallback chain itself is internal to the YouTube
    // path; what the dispatcher sees is the chain's final Result.
    return _runFallbackChain(
      url,
      cookiesFile: cookiesFile,
      cookiesFromBrowser: cookiesFromBrowser,
      cookiesFromBrowserFallback: cookiesFromBrowserFallback,
      cookiesFromBrowserFallbackChain: cookiesFromBrowserFallbackChain,
      proxyUrl: proxyUrl,
      attempt: attempt,
      stopOnLoginRequired: stopOnLoginRequired,
    );
  }

  Future<Result<VideoInfo>> _runFallbackChain(
    String url, {
    String? cookiesFile,
    String? cookiesFromBrowser,
    String? cookiesFromBrowserFallback,
    List<String>? cookiesFromBrowserFallbackChain,
    String? proxyUrl,
    required int attempt,
    bool stopOnLoginRequired = false,
  }) async {
    final client = attempt == 0 ? null : _clientChain[attempt - 1];
    final timeoutSecs =
        _clientTimeouts[attempt.clamp(0, _clientTimeouts.length - 1)];
    final clientLabel = client ?? 'ios,web (default)';

    if (attempt > 0) {
      appLogger.info(
        '🔄 [yt-dlp] Retrying with $clientLabel client (${timeoutSecs}s timeout)...',
      );
    }

    final result = await _extractWithYtdlp(
      url,
      cookiesFile: cookiesFile,
      cookiesFromBrowser: cookiesFromBrowser,
      cookiesFromBrowserFallback: cookiesFromBrowserFallback,
      cookiesFromBrowserFallbackChain: cookiesFromBrowserFallbackChain,
      proxyUrl: proxyUrl,
      extractorClient: client,
      timeoutSecs: timeoutSecs,
      // Browser cookie fallback is useful, but it is independent of
      // player_client. Trying the same locked Edge/Chrome stores once per
      // client makes a failed Windows extraction feel hung. Run that browser
      // chain only on the first/default attempt; later attempts only swap the
      // YouTube client against the same in-app cookie file.
      enableBrowserCookieFallback: attempt == 0,
      stopOnLoginRequired: stopOnLoginRequired && attempt == 0,
    );

    if (result.isSuccess) return result;

    if (stopOnLoginRequired && attempt == 0 && _isLoginRequiredResult(result)) {
      appLogger.info(
        '[yt-dlp] Primary YouTube extraction requires login and no '
        'app/browser cookie source is available; opening login flow early.',
      );
      return result;
    }

    // Smart early-bail — when the first failure is user-induced
    // (cookies expired, video private, format not available, geo
    // restricted, etc.), trying different YouTube player_clients
    // won't help: those errors are intrinsic to the URL/account,
    // not the extractor backend. Bail immediately and let the
    // dispatch wrapper surface the actionable error to the user.
    //
    // Why this matters: with `_clientTimeouts = [30, 45, 60, 90]`
    // the full chain takes 225s worst case. Pre-fix the buggy
    // circuit-breaker counter conflation accidentally short-
    // circuited tv_embedded after 3 fails (~135s); the correct
    // counter fix removed that escape hatch. This early-bail
    // restores fast failure for user-actionable errors WITHOUT
    // resurrecting the counter bug. Platform-broken errors
    // (HTTP 5xx, network blip, parser auth) still walk the full
    // chain because a different player_client genuinely might
    // hit a different YouTube backend that's still working.
    final severity = _classifySeverity(result.exceptionOrNull);
    final canRecoverViaClientSwap = _isRecoverableViaClientSwapResult(result);
    if (severity == _ExtractionFailureSeverity.userInduced &&
        !canRecoverViaClientSwap) {
      appLogger.info(
        '⏭️ [yt-dlp] $clientLabel failed user-induced — bailing chain '
        '(remaining clients won\'t fix this)',
      );
      return result;
    }

    final nextAttempt = attempt + 1;
    if (nextAttempt <= _clientChain.length) {
      appLogger.warning(
        '⚠️ [yt-dlp] $clientLabel failed — trying next client in chain...',
      );
      return _runFallbackChain(
        url,
        cookiesFile: cookiesFile,
        cookiesFromBrowser: cookiesFromBrowser,
        cookiesFromBrowserFallback: cookiesFromBrowserFallback,
        cookiesFromBrowserFallbackChain: cookiesFromBrowserFallbackChain,
        proxyUrl: proxyUrl,
        attempt: nextAttempt,
        stopOnLoginRequired: stopOnLoginRequired,
      );
    }

    // All clients exhausted
    appLogger.error('❌ [yt-dlp] All YouTube player clients failed for: $url');
    return result;
  }

  /// Classify an extraction failure for circuit-breaker purposes.
  ///
  /// User-induced errors (bad cookies for THIS user, video private,
  /// format not available for THIS URL, app's own circuit-breaker
  /// rejection) are extraction-specific — they don't indicate the
  /// platform's extractor is broken, so they MUST NOT trip the
  /// circuit breaker. Otherwise downloading 1 private video would
  /// block all YouTube downloads for 60 seconds.
  ///
  /// Platform-broken errors (HTTP 5xx, timeouts, network errors,
  /// parser auth failures across the board) DO indicate the platform
  /// / yt-dlp combo is degraded and warrant a backoff.
  ///
  /// **Implementation strategy** — preferentially routes off typed
  /// `YtDlpErrorType` to survive yt-dlp version churn (error message
  /// wording changes silently between yt-dlp releases). String matching
  /// is the second-tier classifier for `AppException` envelopes that
  /// have already lost the typed payload, plus a few yt-dlp messages
  /// that the lower-layer parser doesn't classify cleanly.
  _ExtractionFailureSeverity _classifySeverity(Exception? e) {
    if (e == null) return _ExtractionFailureSeverity.platformBroken;

    // ── Tier 1: typed YtDlpException ──
    // Faster + version-resilient. Datasource already mapped raw
    // yt-dlp stderr to typed enum.
    if (e is YtDlpException) {
      switch (e.type) {
        // User-induced: don't trip the circuit.
        case YtDlpErrorType.loginRequired:
        case YtDlpErrorType.formatNotAvailable:
        case YtDlpErrorType.geoRestricted:
        case YtDlpErrorType.ageRestricted:
        case YtDlpErrorType.notFound:
        case YtDlpErrorType.circuitBreakerOpen:
        // App-side runtime missing (Deno not bundled / corrupted /
        // not yet downloaded). NOT platform-broken — platform is
        // fine, our local runtime is not. Tripping the circuit on
        // jsRuntimeUnavailable would misclassify this as "YouTube
        // down" and lock all platform-wide. Treat as userInduced
        // (no circuit impact); BinaryManager re-downloads Deno in
        // the background while UI surfaces an actionable error.
        case YtDlpErrorType.jsRuntimeUnavailable:
          return _ExtractionFailureSeverity.userInduced;
        // Platform-broken: legitimate signal of degradation.
        case YtDlpErrorType.timeout:
        case YtDlpErrorType.networkError:
        case YtDlpErrorType.rateLimited:
        case YtDlpErrorType.binaryNotFound:
          return _ExtractionFailureSeverity.platformBroken;
        case YtDlpErrorType.unknown:
          // Fall through to message inspection below.
          break;
      }
    }

    // ── Tier 2: AppException / unknown — string heuristics ──
    // Guards against typed-info loss when yt-dlp errors are wrapped
    // in `AppException.network(message: 'yt-dlp error: ...')`.
    final msg = e.toString().toLowerCase();

    // User-induced: cookies/auth issues — refresh cookies fixes.
    if (msg.contains('sign in to confirm') ||
        msg.contains('login required') ||
        msg.contains('use --cookies') ||
        msg.contains('cookies-from-browser')) {
      return _ExtractionFailureSeverity.userInduced;
    }

    // User-induced: per-URL / per-video issues.
    if (msg.contains('requested format is not available') ||
        msg.contains('video unavailable') ||
        msg.contains('this video is private') ||
        msg.contains('this video has been removed') ||
        msg.contains('age-restricted') ||
        msg.contains('members-only') ||
        msg.contains('geo-restricted') ||
        msg.contains('not available in your country')) {
      return _ExtractionFailureSeverity.userInduced;
    }

    // App's own circuit-breaker self-rejection. Kept here as belt-and-
    // suspenders even though Tier 1 already catches `circuitBreakerOpen`
    // — string check survives if the exception is re-wrapped on the way
    // up (e.g. `AppException.network(message: 'yt-dlp error: Circuit
    // breaker open for ...')`).
    if (msg.contains('circuit breaker open')) {
      return _ExtractionFailureSeverity.userInduced;
    }

    // Facebook "cannot parse data" — historically treated as a
    // user-actionable parser/cookies issue (re-login fixes it).
    if (msg.contains('cannot parse data')) {
      return _ExtractionFailureSeverity.userInduced;
    }

    // Default: platform-broken — record. Covers timeouts, HTTP 5xx,
    // network errors, parser breakage, generic unknowns.
    return _ExtractionFailureSeverity.platformBroken;
  }

  /// Whether the failure path should round-trip through gallery-dl
  /// before giving up. Two gates:
  ///
  /// 1. [skipFlag] — caller-side opt-out (used when gallery-dl is
  ///    already running in parallel via the image-capable race path,
  ///    so the sequential fallback would be wasted work).
  /// 2. [platform.supportsGalleryDlFallback] — only true for
  ///    platforms whose posts can be image/carousel content
  ///    (Instagram, Facebook, Twitter, Reddit, Pinterest, LinkedIn,
  ///    Threads, plus `unknown` as a defensive default). Pure-video
  ///    platforms (YouTube, Vimeo, SoundCloud, Bilibili, TikTok,
  ///    Douyin, Dailymotion) always return exit 64 "Unsupported URL"
  ///    on gallery-dl — calling it is a guaranteed waste of up to a
  ///    60s timeout, on top of an already-failed yt-dlp attempt.
  ///
  /// This guard existed at commit `2d626617` ("skip gallery-dl on
  /// pure video") and was lost in the V2 reconcile merges; restoring
  /// it closes a regression that made YouTube extract failures on
  /// Windows spend extra time chasing an impossible fallback.
  bool _shouldTryGalleryDlFallback(bool skipFlag, VideoPlatform platform) {
    if (skipFlag) return false;
    return platform.supportsGalleryDlFallback;
  }

  /// Extract using yt-dlp directly.  On 429, waits 3s and retries once.
  /// [retryOnRateLimit] prevents infinite loops on the retry call.
  /// [skipGalleryDlFallback] skips gallery-dl fallback (when caller already runs it in parallel).
  Future<Result<VideoInfo>> _extractWithYtdlp(
    String url, {
    String? cookiesFile,
    String? cookiesFromBrowser,
    String? cookiesFromBrowserFallback,
    List<String>? cookiesFromBrowserFallbackChain,
    String? proxyUrl,
    String? extractorClient,
    int? timeoutSecs,
    bool retryOnRateLimit = true,
    bool skipGalleryDlFallback = false,
    bool enableBrowserCookieFallback = true,
    bool stopOnLoginRequired = false,
  }) async {
    final platform = PlatformDetector.detectPlatform(url);
    try {
      appLogger.info('🔍 [yt-dlp] Extracting: $url');

      final info = await _ytdlpDataSource.extractInfo(
        url,
        cookiesFile: cookiesFile,
        cookiesFromBrowser: cookiesFromBrowser,
        proxyUrl: proxyUrl,
        extractorClient: extractorClient,
        timeoutSecs: timeoutSecs,
      );

      final result = _buildVideoInfoResult(url, info);

      // yt-dlp surfaced metadata but no usable media formats — this
      // is the canonical YouTube "storyboards-only" symptom (e.g.
      // Deno JS runtime absent/unhealthy, the very class of failure
      // Phase B Deno bundling is designed to recover from). On
      // pure-video platforms, gallery-dl still cannot fix this — it
      // returns exit 64 "Unsupported URL". The guard mirrors the
      // catch-branch behavior so a YouTube empty-formats result on
      // Windows does not waste another up-to-60s gallery-dl round
      // trip on top of the already-suspect extract.
      if (result == null) {
        if (_shouldTryGalleryDlFallback(skipGalleryDlFallback, platform)) {
          appLogger.info(
            '🖼️ [gallery-dl] yt-dlp had no formats, trying gallery-dl...',
          );
          final galleryResult = await _extractWithGalleryDl(
            url,
            cookiesFile: cookiesFile,
          );
          if (galleryResult.isSuccess) return galleryResult;
          // gallery-dl also failed, return generic error
        }
        return Result.failure(
          const AppException.download(
            message: 'No downloadable content found at this URL',
          ),
        );
      }

      // Phase 15 instrumentation — emit a warning when extraction
      // succeeded for a platform whose HQ formats are auth-gated
      // (currently only Bilibili) but the user has no cookies on file
      // for that platform, so only the unauthenticated quality tier
      // was returned. UI surfacing (snackbar / format-dialog badge) is
      // deferred to v2.1 once product picks the per-platform messaging
      // strategy and i18n rounds the keys across 15 locales — this hook
      // gives us production telemetry to validate the assumption
      // before paying that l10n cost.
      final videoInfo = result.dataOrNull;
      if (videoInfo != null) {
        final hasCookiesForPlatform =
            cookiesFile != null || cookiesFromBrowser != null;
        if (PlatformQualityHint.shouldHintLoginForHq(
          platform: platform,
          videoInfo: videoInfo,
          hasCookiesForPlatform: hasCookiesForPlatform,
        )) {
          appLogger.warning(
            '🔒 [Quality] ${platform.name} returned only low-quality formats '
            '(no cookies present). User would likely benefit from signing in '
            'for HD/4K formats. UI hint surface deferred to v2.1 — see '
            'PlatformQualityHint and the deferred-l10n note in Phase 15.',
          );
        }
      }

      return result;
    } on YtDlpException catch (e) {
      // Rate-limit: wait 3s then retry once with a fresh random User-Agent.
      // YtDlpDataSource.extractInfo() picks a new random UA on each invocation,
      // so no explicit rotate call is needed.
      if (e.type == YtDlpErrorType.rateLimited && retryOnRateLimit) {
        appLogger.warning(
          '⏳ [yt-dlp] Rate-limited — waiting 3s before retry with fresh UA...',
        );
        await _delay(const Duration(seconds: 3));
        return _extractWithYtdlp(
          url,
          cookiesFile: cookiesFile,
          cookiesFromBrowser: cookiesFromBrowser,
          cookiesFromBrowserFallback: cookiesFromBrowserFallback,
          cookiesFromBrowserFallbackChain: cookiesFromBrowserFallbackChain,
          proxyUrl: proxyUrl,
          extractorClient: extractorClient,
          timeoutSecs: timeoutSecs,
          retryOnRateLimit: false, // prevent infinite retry
          skipGalleryDlFallback: skipGalleryDlFallback,
          enableBrowserCookieFallback: enableBrowserCookieFallback,
          stopOnLoginRequired: stopOnLoginRequired,
        );
      }

      appLogger.warning('⚠️ [yt-dlp] Extraction failed: ${e.message}');

      if (stopOnLoginRequired && e.type == YtDlpErrorType.loginRequired) {
        appLogger.info(
          '[yt-dlp] Login required on primary attempt; skipping browser '
          'cookie and player-client fallback for first-login prompt.',
        );
        return Result.failure(e);
      }

      // V2 reconcile: Facebook "Cannot parse data" → user needs to login
      // (Browser tab) or refresh cookies. Surface clear actionable error
      // instead of generic extraction failure.
      //
      // P1 (2026-05-25): pass `hadCookies` so the gate distinguishes
      // (a) no-cookies-attached (login likely fixes) from (b) cookies-
      // attached-but-still-cannot-parse (extractor / payload broken;
      // login does NOT help and previously caused login-spam loop).
      final hadCookies = cookiesFile != null || cookiesFromBrowser != null;
      if (_isFacebookCookieRequiredFailure(
        url,
        e.message,
        hadCookies: hadCookies,
      )) {
        final authContext =
            hadCookies
                ? 'with cookies but extractor still flagged auth'
                : 'without a usable session';
        appLogger.warning(
          '🍪 [Facebook] Cannot parse data $authContext. '
          'Prompting user to login/import cookies.',
        );
        return Result.failure(
          const AppException.download(
            message:
                'Facebook login required — login in the Browser tab or refresh Facebook cookies, then retry.',
          ),
        );
      }

      if (_shouldTryGalleryDlFallback(skipGalleryDlFallback, platform)) {
        // Try gallery-dl fallback for image content before giving up
        appLogger.info(
          '🖼️ [gallery-dl] yt-dlp failed, trying gallery-dl fallback...',
        );
        final galleryResult = await _extractWithGalleryDl(
          url,
          cookiesFile: cookiesFile,
        );
        if (galleryResult.isSuccess) {
          // Outcome recorded by `_dispatchExtraction` outer wrapper.
          return galleryResult;
        }

        // If gallery-dl detected login requirement, propagate that (triggers auto-login flow)
        if (_isLoginRequiredResult(galleryResult)) return galleryResult;
      }

      // gallery-dl also failed.
      //
      // RETRY ORDER (highest probability of success first):
      //   1. cookies-from-browser fallback — when the user hasn't
      //      explicitly configured one but a browser is installed.
      //      Live browser cookies carry session-binding signals (PO
      //      Token visitor data, BotGuard rotation cookies) that the
      //      WebView-extracted file format silently strips. Gated
      //      independently of (2) because `loginRequired` (Sign in
      //      to confirm bot) is the textbook case browser-cookies
      //      fix, but `_shouldRetryWithoutCookies` excludes it.
      //   2. retry-without-cookies — last-resort for the case where
      //      our cookies are themselves the problem (expired SAPISID,
      //      stale __Secure-*PSIDTS, etc). Narrower gate because
      //      removing cookies on `loginRequired` would just change
      //      the error to "login required" again.
      // P1 (2026-05-07 review): drop the `cookiesFile != null` gate.
      // The original gate locked browser-cookies retry behind "user
      // already extracted file cookies via app webview" — but the most
      // common case where browser-cookies helps is precisely when the
      // user has Chrome logged into YouTube but never logged in via
      // app webview. Privacy is still preserved because the retry
      // only fires AFTER a primary failure, never on first attempt.
      if (cookiesFromBrowser == null &&
          enableBrowserCookieFallback &&
          _shouldRetryWithCookiesFromBrowser(e.type)) {
        // Build the browser candidate chain. Prefer the explicit chain
        // when provided (Phase 1: callers pass the platform-aware
        // ordered list from `cookiesFromBrowserFallbackChainProvider`).
        // Fall back to the single-shot value for legacy callers that
        // haven't migrated yet, so behaviour is at-least-as-good as
        // pre-chain. Empty chain → no retry, drop through.
        //
        // Why iterate: yt-dlp issue 7271. A single browser pick can
        // hard-fail with "Could not copy <browser> cookie database"
        // when that browser is currently running and holding its
        // SQLite store open. Pre-chain, the failure surfaced as a
        // misleading `loginRequired` to the user. The chain now
        // advances on `cookieDbLocked` so Edge / Firefox / etc get a
        // shot. Production Windows log 2026-05-12 §138 caught this
        // exact pattern (Chrome locked → entire retry path died).
        final candidates = <String>[
          if (cookiesFromBrowserFallbackChain != null)
            ...cookiesFromBrowserFallbackChain
          else if (cookiesFromBrowserFallback != null)
            cookiesFromBrowserFallback,
        ];

        for (final candidate in candidates) {
          appLogger.warning(
            '⚠️ [yt-dlp] Primary cookies failed (${e.type.name}). '
            'Retrying with cookies-from-browser=$candidate...',
          );
          final fallbackResult = await _retryWithCookiesFromBrowser(
            url,
            candidate,
            proxyUrl: proxyUrl,
            extractorClient: extractorClient,
            timeoutSecs: timeoutSecs,
          );
          if (fallbackResult.isSuccess) return fallbackResult;

          // Codex review round 2: keep iterating on ANY auth/lock
          // class. Common case: Edge readable but the user hasn't
          // signed in to YouTube there → YouTube returns
          // `loginRequired`, but Chrome / Firefox might actually
          // hold a valid session. Pre-fix we broke out on anything
          // other than `cookieDbLocked` and lost those candidates.
          // We only stop on errors a different browser cannot help
          // with (network / runtime / SSL / circuit-breaker /
          // geo / disk / etc.).
          final inner = fallbackResult.exceptionOrNull;
          final innerMsg = inner?.toString() ?? '';
          final innerCode = DownloadErrorClassifier.classifyMessage(innerMsg);
          final advanceableCodes = <DownloadErrorCode>{
            DownloadErrorCode.cookieDbLocked,
            DownloadErrorCode.loginRequired,
            DownloadErrorCode.formatUnavailable,
            DownloadErrorCode.ageRestricted,
          };
          if (advanceableCodes.contains(innerCode)) {
            appLogger.info(
              '➡️ [yt-dlp] cookies-from-browser=$candidate failed '
              '(${innerCode.name}) — advancing to next browser in '
              'fallback chain.',
            );
            continue;
          }
          // Failure class a different browser cannot fix (network,
          // SSL, JS runtime, geo-restriction, etc.). Stop iterating
          // and fall through to retry-without-cookies + final
          // error surface.
          appLogger.info(
            '🛑 [yt-dlp] cookies-from-browser=$candidate failed '
            '(${innerCode.name}) — non-cookie failure class, '
            'aborting chain.',
          );
          break;
        }
        // Fall through to retry-without-cookies if browser-fallback
        // chain also failed — sometimes both paths fail and we want
        // the final extractor exception surfaced upward.
      }

      if (cookiesFile != null && _shouldRetryWithoutCookies(e.type)) {
        appLogger.warning(
          '⚠️ [yt-dlp] Cookies may be bad/expired (${e.type.name}). '
          'Retrying WITHOUT cookies...',
        );
        final retryResult = await _retryWithoutCookies(url);
        if (retryResult.isSuccess) return retryResult;

        // P0 (login-loop bug, 2026-05-07 runtime test):
        // When retry-without-cookies ALSO fails, NEVER escalate the
        // original error type. Removing cookies from a session-bound
        // request always provokes "Sign in to confirm bot" (=
        // loginRequired) from YouTube — that's an artifact of the
        // retry, NOT the user's actual problem. Returning that
        // loginRequired upward triggers the auto-login flow, which
        // re-extracts with new cookies, which fails the same way
        // (PO Token still missing), which retries-without-cookies
        // again, and so on — login loop ensues.
        //
        // The user's actual signal is the ORIGINAL `e` (most often
        // formatNotAvailable, indicating PO Token requirement). UI
        // surfaces that → user sees "format not available", doesn't
        // get bounced into a useless login cycle.
        appLogger.info(
          '📌 [yt-dlp] Retry without cookies escalated to ${retryResult.exceptionOrNull?.runtimeType}. '
          'Surfacing ORIGINAL ${e.type.name} to caller — retry artifact suppressed '
          'to prevent login-loop on PO-Token-required URLs.',
        );
        return Result.failure(e);
      }

      // Preserve the typed `YtDlpException` (instead of wrapping into
      // `AppException.network`) so `_dispatchExtraction._classifySeverity`
      // can route off `YtDlpErrorType` directly. Wrapping lost the type
      // info and forced the classifier into fragile string matching that
      // breaks silently on yt-dlp version churn.
      return Result.failure(e);
    } catch (e, stack) {
      appLogger.error('❌ [yt-dlp] Unexpected error', e, stack);

      if (_shouldTryGalleryDlFallback(skipGalleryDlFallback, platform)) {
        // Try gallery-dl fallback
        appLogger.info(
          '🖼️ [gallery-dl] yt-dlp errored, trying gallery-dl fallback...',
        );
        final galleryResult = await _extractWithGalleryDl(
          url,
          cookiesFile: cookiesFile,
        );
        if (galleryResult.isSuccess) {
          // Outcome recorded by `_dispatchExtraction` outer wrapper.
          return galleryResult;
        }

        // If gallery-dl detected login requirement, propagate that (triggers auto-login flow)
        if (_isLoginRequiredResult(galleryResult)) return galleryResult;
      }

      // P1 (2026-05-07 review): drop `cookiesFile != null` gate to
      // unlock browser-cookies retry for users without app-webview
      // cookies (matches typed-catch path above).
      if (cookiesFromBrowser == null &&
          enableBrowserCookieFallback &&
          cookiesFromBrowserFallback != null) {
        appLogger.warning(
          '⚠️ [yt-dlp] Unexpected error. '
          'Retrying with cookies-from-browser=$cookiesFromBrowserFallback...',
        );
        final fallbackResult = await _retryWithCookiesFromBrowser(
          url,
          cookiesFromBrowserFallback,
          proxyUrl: proxyUrl,
          extractorClient: extractorClient,
          timeoutSecs: timeoutSecs,
        );
        if (fallbackResult.isSuccess) return fallbackResult;
      }

      if (cookiesFile != null) {
        appLogger.warning(
          '⚠️ [yt-dlp] Unexpected error with cookies. Retrying WITHOUT cookies...',
        );
        final retryResult = await _retryWithoutCookies(url);
        if (retryResult.isSuccess) return retryResult;
        // Same login-loop guard as typed-catch path — surface the
        // ORIGINAL exception, not the retry-without-cookies artifact.
        return Result.failure(
          AppException.network(
            message: 'yt-dlp error: ${AppExceptionX.readableMessage(e)}',
          ),
        );
      }

      return Result.failure(
        AppException.network(
          message: 'yt-dlp error: ${AppExceptionX.readableMessage(e)}',
        ),
      );
    }
  }

  /// Check if a failed Result contains a login-required error from gallery-dl.
  /// When gallery-dl detects login redirect, we propagate that error so the
  /// auto-login flow in home_screen can trigger.
  bool _isLoginRequiredResult(Result<VideoInfo> result) {
    if (result.isSuccess) return false;
    final exception = result.exceptionOrNull;
    if (exception is YtDlpException) {
      return exception.type == YtDlpErrorType.loginRequired;
    }
    final msg =
        (exception is AppException ? exception.message : exception.toString())
            .toLowerCase();
    return msg.contains('login required') || msg.contains('login page');
  }

  bool _isYtdlpBinaryMissingResult(Result<VideoInfo> result) {
    if (result.isSuccess) return false;
    final exception = result.exceptionOrNull;
    final message =
        exception is AppException ? exception.message : exception.toString();
    return DownloadErrorClassifier.classifyMessage(message) ==
        DownloadErrorCode.ytdlpBinaryMissing;
  }

  bool _isRecoverableViaClientSwapResult(Result<VideoInfo> result) {
    if (result.isSuccess) return false;
    final exception = result.exceptionOrNull;
    if (exception is YtDlpException) {
      return exception.type == YtDlpErrorType.loginRequired ||
          exception.type == YtDlpErrorType.formatNotAvailable;
    }

    final msg =
        (exception is AppException ? exception.message : exception.toString())
            .toLowerCase();
    return msg.contains('sign in to confirm') ||
        msg.contains('login required') ||
        msg.contains('use --cookies') ||
        msg.contains('requested format is not available');
  }

  /// Check if error type suggests bad cookies (worth retrying without)
  bool _shouldRetryWithoutCookies(YtDlpErrorType type) {
    return type == YtDlpErrorType.formatNotAvailable ||
        type == YtDlpErrorType.unknown;
  }

  /// Check if error type suggests cookies-from-browser would help.
  /// loginRequired explicitly indicates "we need fresher session
  /// cookies"; formatNotAvailable can also mean session-binding
  /// missing (PO Token visitor data tied to live browser session).
  /// `unknown` is included because Tier-1 typed classification might
  /// have lost detail when the original error was wrapped.
  bool _shouldRetryWithCookiesFromBrowser(YtDlpErrorType type) {
    return type == YtDlpErrorType.loginRequired ||
        type == YtDlpErrorType.formatNotAvailable ||
        type == YtDlpErrorType.unknown;
  }

  /// Retry extraction with `--cookies-from-browser <name>` — yt-dlp
  /// reads the live browser cookie store directly (decrypts via
  /// platform keystore on macOS / DPAPI on Windows). Often succeeds
  /// where file-based cookies fail because the browser session
  /// carries fresher SIDTS/SIDCC rotation cookies + visitor-data
  /// signals YouTube's anti-bot uses to score legitimacy.
  ///
  /// First-time Keychain prompt on macOS is acceptable UX — only
  /// fires after primary path already failed (user is invested).
  ///
  /// [proxyUrl] is forwarded so YouTube's IP/account scoring sees
  /// the same egress as the primary attempt — without this, a user
  /// who specifically configured a proxy to bypass IP-flag would
  /// have their browser-cookies retry hit raw home IP, defeating
  /// the layer that's most likely to be the actual blocker.
  Future<Result<VideoInfo>> _retryWithCookiesFromBrowser(
    String url,
    String browserName, {
    String? proxyUrl,
    String? extractorClient,
    int? timeoutSecs,
  }) async {
    try {
      final info = await _ytdlpDataSource.extractInfo(
        url,
        cookiesFromBrowser: browserName,
        proxyUrl: proxyUrl,
        extractorClient: extractorClient,
        timeoutSecs: timeoutSecs,
      );
      appLogger.info(
        '✅ [yt-dlp] Succeeded with cookies-from-browser=$browserName! '
        'Browser session has stronger binding than file cookies.',
      );
      final result = _buildVideoInfoResult(url, info);
      if (result == null) {
        return Result.failure(
          const AppException.download(
            message: 'No downloadable content found at this URL',
          ),
        );
      }
      return result;
    } on YtDlpException catch (e) {
      appLogger.warning(
        '⚠️ [yt-dlp] cookies-from-browser=$browserName also failed: '
        '${e.message}',
      );
      return Result.failure(e);
    } catch (e, stack) {
      appLogger.warning(
        '⚠️ [yt-dlp] cookies-from-browser=$browserName unexpected error',
        e,
        stack,
      );
      return Result.failure(
        AppException.network(
          message: 'yt-dlp error: ${AppExceptionX.readableMessage(e)}',
        ),
      );
    }
  }

  /// Retry extraction without cookies (fallback for bad/expired cookies)
  Future<Result<VideoInfo>> _retryWithoutCookies(String url) async {
    try {
      final info = await _ytdlpDataSource.extractInfo(url);
      appLogger.warning(
        '✅ [yt-dlp] Succeeded WITHOUT cookies! '
        'Your cookies may be bad/expired - consider refreshing them.',
      );
      final result = _buildVideoInfoResult(url, info);
      if (result == null) {
        return Result.failure(
          const AppException.download(
            message: 'No downloadable content found at this URL',
          ),
        );
      }
      return result;
    } on YtDlpException catch (e) {
      appLogger.error(
        '❌ [yt-dlp] Retry without cookies also failed: ${e.message}',
      );
      // Preserve typed exception — same reasoning as the primary
      // `_extractWithYtdlp` catch path. Wrapping into AppException
      // loses YtDlpErrorType, forcing the upstream severity
      // classifier (in `_runFallbackChain` early-bail decision +
      // `_dispatchExtraction` circuit-breaker recording) into
      // fragile string matching.
      return Result.failure(e);
    } catch (e, stack) {
      appLogger.error('❌ [yt-dlp] Retry unexpected error', e, stack);
      return Result.failure(
        AppException.network(
          message: 'yt-dlp error: ${AppExceptionX.readableMessage(e)}',
        ),
      );
    }
  }

  /// Build VideoInfo Result from YtDlpVideoInfo.
  /// Returns null if no usable qualities found (caller should try gallery-dl).
  Result<VideoInfo>? _buildVideoInfoResult(String url, YtDlpVideoInfo info) {
    // Convert chapters from YtDlpChapterInfo to ChapterInfo
    final chapters =
        info.chapters
            .map(
              (c) => ChapterInfo(
                title: c.title,
                startTime: c.startTime,
                endTime: c.endTime,
              ),
            )
            .toList();

    if (chapters.isNotEmpty) {
      appLogger.debug('[yt-dlp] Found ${chapters.length} chapters');
    }
    if (info.isLive) {
      appLogger.debug('[yt-dlp] Live stream detected: ${info.liveStatus}');
    }

    // Map subtitles with deduplication by lang code
    final subtitleMap = <String, SubtitleTrackInfo>{};
    for (final s in info.subtitles) {
      subtitleMap.putIfAbsent(
        s.lang,
        () => SubtitleTrackInfo(
          lang: s.lang,
          langName: s.langName ?? s.lang,
          isAutoGenerated: false,
        ),
      );
    }
    final autoSubtitleMap = <String, SubtitleTrackInfo>{};
    for (final s in info.automaticCaptions) {
      autoSubtitleMap.putIfAbsent(
        s.lang,
        () => SubtitleTrackInfo(
          lang: s.lang,
          langName: s.langName ?? s.lang,
          isAutoGenerated: true,
        ),
      );
    }

    if (subtitleMap.isNotEmpty || autoSubtitleMap.isNotEmpty) {
      appLogger.debug(
        '[yt-dlp] Subtitles: ${subtitleMap.length} original, '
        '${autoSubtitleMap.length} auto-translated',
      );
    }

    final subtitlesList = subtitleMap.values.toList();
    final autoSubtitlesList = autoSubtitleMap.values.toList();

    final platform = PlatformDetector.detectPlatform(url);
    if (platform == VideoPlatform.youtube &&
        _isYouTubeBotWallLimitedFormatSet(info.formats)) {
      final videoFormats =
          info.formats
              .where((f) => f.height != null && f.height! > 0)
              .where((f) => f.vcodec != null && f.vcodec != 'none')
              .toList();
      final maxHeight = videoFormats
          .map((f) => f.height ?? 0)
          .fold<int>(0, (max, height) => height > max ? height : max);
      appLogger.warning(
        '[yt-dlp] YouTube returned only restricted low-quality formats '
        '(formats=${info.formats.length}, video=${videoFormats.length}, '
        'maxHeight=${maxHeight}p). Treating as recoverable client/PO-token '
        'failure instead of auto-downloading a fake Best ${maxHeight}p file.',
      );
      return Result.failure(
        YtDlpException(
          YtDlpErrorType.formatNotAvailable,
          'YouTube returned only restricted low-quality formats. '
          'A different player client, fresher browser session, or PO token is required.',
        ),
      );
    }

    // Convert formats to qualities (includes video-only + subtitle options)
    final qualities = _convertFormatsToQualities(
      info.formats,
      hasChapters: chapters.isNotEmpty,
      subtitles: subtitlesList,
      autoSubtitles: autoSubtitlesList,
    );
    appLogger.debug('[yt-dlp] Found ${qualities.length} qualities');

    // Browser-sniffed HLS (referer-stamped): znews-style pages embed a bare
    // VARIANT playlist whose single muxed .ts format carries no
    // height/vcodec/acodec metadata. The quality filters above either drop it
    // entirely or misread it as audio-only, so the user loses the Video option.
    // Since a sniffed HLS stream is ALWAYS a playable video, guarantee a
    // synthesized "Best" video entry (prepended) whenever no real video
    // quality survived — independent of any audio entries.
    // Detect a raw HLS manifest handed straight to yt-dlp (browser sniff): the
    // URL is an .m3u8, OR it was referer-stamped by the panel. Independent of
    // the holder so a lookup miss (cleaned/redirected URL) can't strip the
    // Video option.
    final isSniffedHls =
        info.formats.isNotEmpty &&
        (url.toLowerCase().contains('.m3u8') ||
            DownloadRefererHolder.lookup(url) != null);
    if (isSniffedHls) {
      // WARNING level so it survives the log filter (info/debug are dropped).
      appLogger.warning(
        '[hls-diag] formats=${info.formats.length} qBefore=${qualities.length} '
        'v=${qualities.where((q) => q.mediaType == MediaType.video).length} '
        'a=${qualities.where((q) => q.mediaType == MediaType.audio).length} '
        'url=$url',
      );
      // Per-variant HLS format IDs (e.g. index-v1-a1) and height-based
      // selectors are unstable: the manifest is re-fetched at download time
      // with a new token, so those IDs no longer resolve ("Requested format is
      // not available"). Drop every video quality tied to a specific stream and
      // offer ONE Best video that downloads via `-f best`, re-resolved live.
      qualities.removeWhere(
        (q) =>
            q.mediaType == MediaType.video &&
            q.encryptedUrl != 'ytdlp:best:mp4',
      );
      if (!qualities.any((q) => q.encryptedUrl == 'ytdlp:best:mp4')) {
        qualities.insert(
          0,
          const Quality(
            qualityText: 'Best Available',
            size: 'Highest quality available',
            encryptedUrl: 'ytdlp:best:mp4',
            mediaType: MediaType.video,
          ),
        );
      }
      appLogger.warning(
        '[hls-diag] qAfter=${qualities.length} '
        'v=${qualities.where((q) => q.mediaType == MediaType.video).length}',
      );
    }

    // No usable video/audio formats — likely image-only content
    // Return null to signal caller to try gallery-dl fallback
    // Note: subtitle-only results are still valid
    final hasMediaQualities = qualities.any(
      (q) => q.mediaType != MediaType.subtitle,
    );
    if (!hasMediaQualities &&
        subtitlesList.isEmpty &&
        autoSubtitlesList.isEmpty) {
      appLogger.warning('⚠️ [yt-dlp] No usable video/audio formats found');
      return null;
    }

    final videoInfo = VideoInfo(
      url: url,
      title: info.title,
      description: info.description,
      thumbnail: info.thumbnail,
      duration: info.duration,
      platform: info.platform,
      uploader: info.uploader,
      viewCount: info.viewCount,
      uploadDate: info.uploadDate,
      extractor: info.platform,
      availableQualities: qualities,
      downloadMethod: 'ytdlp',
      // P1 features
      chapters: chapters,
      isLive: info.isLive,
      liveStatus: info.liveStatus,
      // Subtitle availability
      availableSubtitles: subtitlesList,
      availableAutoSubtitles: autoSubtitlesList,
    );

    appLogger.info('✅ [yt-dlp] Extracted: ${videoInfo.title}');
    return Result.success(videoInfo);
  }

  bool _isYouTubeBotWallLimitedFormatSet(List<YtDlpFormat> formats) {
    final videoFormats =
        formats
            .where((f) => f.height != null && f.height! > 0)
            .where((f) => f.vcodec != null && f.vcodec != 'none')
            .toList();
    if (videoFormats.isEmpty) return false;

    final maxHeight = videoFormats
        .map((f) => f.height ?? 0)
        .fold<int>(0, (max, height) => height > max ? height : max);
    // YouTube's anti-bot / missing-PO-token path commonly exposes only one
    // low pre-muxed stream (often format 18) and hides the real DASH/HLS
    // catalogue. Treating that as "Best (360p)" is worse than failing.
    return formats.length <= 6 &&
        videoFormats.length <= 1 &&
        maxHeight > 0 &&
        maxHeight <= 360;
  }

  /// Convert yt-dlp formats to Quality objects
  List<Quality> _convertFormatsToQualities(
    List<YtDlpFormat> formats, {
    bool hasChapters = false,
    List<SubtitleTrackInfo> subtitles = const [],
    List<SubtitleTrackInfo> autoSubtitles = const [],
  }) {
    final qualities = <Quality>[];
    final seenHeights = <int>{};

    // Debug: Log all raw formats to understand what yt-dlp returns
    appLogger.debug('[yt-dlp] Raw formats count: ${formats.length}');
    for (final f in formats) {
      if (f.height != null && f.height! >= 1080) {
        appLogger.debug(
          '[yt-dlp] Format: ${f.formatId} | ${f.width}x${f.height} | vcodec=${f.vcodec} | ext=${f.ext}',
        );
      }
    }

    // Get video formats sorted by height (descending)
    final videoFormats =
        formats
            .where((f) => f.height != null && f.height! > 0)
            .where((f) => f.vcodec != null && f.vcodec != 'none')
            .toList()
          ..sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));

    // Debug: Log filtered video formats
    appLogger.debug('[yt-dlp] Filtered video formats: ${videoFormats.length}');
    if (videoFormats.isNotEmpty) {
      final best = videoFormats.first;
      appLogger.debug(
        '[yt-dlp] Best: ${best.width}x${best.height} (${best.formatId})',
      );
    }

    // Determine best available resolution for display
    // Check BOTH width and height to handle ultra-wide videos correctly
    // Ultra-wide 4K: width ~3840 but height ~1744 (not 2160)
    String bestQualityLabel = 'Best Available';
    if (videoFormats.isNotEmpty) {
      final bestHeight = videoFormats.first.height!;
      final bestWidth = videoFormats.first.width ?? 0;
      final bestFps = videoFormats.first.fps;

      if (bestWidth >= 7680 || bestHeight >= 4320) {
        bestQualityLabel = 'Best (8K)';
      } else if (bestWidth >= 3840 || bestHeight >= 2160) {
        bestQualityLabel = 'Best (4K)';
      } else if (bestWidth >= 2560 || bestHeight >= 1440) {
        bestQualityLabel = 'Best (2K)';
      } else if (bestHeight >= 1080) {
        bestQualityLabel = 'Best (1080p)';
      } else {
        bestQualityLabel = 'Best (${bestHeight}p)';
      }
      if (bestFps != null && bestFps > 30) {
        bestQualityLabel += ' ${bestFps.round()}fps';
      }
    }

    // Add "Best Available" option first - downloads highest quality
    // Only add if there are actual video formats (not for image-only posts)
    if (videoFormats.isNotEmpty) {
      final bestFilesizeBytes = videoFormats.first.filesize;
      final bestSizeStr =
          bestFilesizeBytes != null
              ? _formatFileSize(bestFilesizeBytes)
              : 'Highest quality available';
      qualities.add(
        Quality(
          qualityText: bestQualityLabel,
          size: bestSizeStr,
          encryptedUrl: 'ytdlp:best:mp4',
          mediaType: MediaType.video,
          vcodec: videoFormats.first.vcodec,
          fps: videoFormats.first.fps,
          filesizeBytes: bestFilesizeBytes,
        ),
      );
    }

    // Add unique quality levels (muxed — video + audio merged)
    for (final format in videoFormats) {
      final height = format.height!;
      final width = format.width ?? 0;

      // Skip if we already have this quality
      if (seenHeights.contains(height)) continue;
      seenHeights.add(height);

      // Format size string
      final sizeStr =
          format.filesize != null ? _formatFileSize(format.filesize!) : '';

      // Create quality label - map to standard tiers
      String qualityLabel = _getStandardQualityLabel(width, height);

      // Add FPS suffix if > 30 (consistent formatting)
      if (format.fps != null && format.fps! > 30) {
        qualityLabel += ' ${format.fps!.round()}fps';
      }

      qualities.add(
        Quality(
          qualityText: qualityLabel,
          size: sizeStr,
          encryptedUrl: 'ytdlp:${height}p',
          mediaType: MediaType.video,
          vcodec: format.vcodec,
          acodec: format.acodec,
          fps: format.fps,
          tbr: format.tbr,
          filesizeBytes: format.filesize,
        ),
      );
    }

    // Add "Split by Chapters" option if video has chapters
    if (hasChapters && videoFormats.isNotEmpty) {
      qualities.add(
        Quality(
          qualityText: 'Split by Chapters',
          size: 'Downloads each chapter as separate file',
          encryptedUrl: 'ytdlp:best:mp4:split_chapters',
          mediaType: MediaType.video,
        ),
      );
    }

    // === Video-Only section (raw streams without audio) ===
    final videoOnlyFormats = videoFormats.where((f) => f.isVideoOnly).toList();
    final seenVideoOnly = <String>{}; // deduplicate by height+codec
    for (final format in videoOnlyFormats) {
      final height = format.height!;
      final codec = _formatCodecName(format.vcodec);
      final dedupeKey = '${height}_$codec';
      if (seenVideoOnly.contains(dedupeKey)) continue;
      seenVideoOnly.add(dedupeKey);

      final sizeStr =
          format.filesize != null ? _formatFileSize(format.filesize!) : '';

      String qualityLabel = _getStandardQualityLabel(format.width ?? 0, height);
      if (format.fps != null && format.fps! > 30) {
        qualityLabel += ' ${format.fps!.round()}fps';
      }

      qualities.add(
        Quality(
          qualityText: '$qualityLabel Video Only ($codec)',
          size: sizeStr,
          encryptedUrl: 'ytdlp:raw:${format.formatId}',
          mediaType: MediaType.video,
          vcodec: format.vcodec,
          fps: format.fps,
          tbr: format.tbr,
          isVideoOnly: true,
          filesizeBytes: format.filesize,
        ),
      );
    }

    // === Raw audio streams (specific format IDs from the source) ===
    // These allow precise stream selection and custom video+audio combos.
    // Sorted by bitrate descending so the highest-quality stream comes first.
    // DL-003: exclude storyboards from the audio list. A storyboard row
    // has vcodec=='none' AND acodec=='none', so `isAudioOnly` (which keys
    // on vcodec=='none') wrongly admits it; without the acodec!=none
    // guard it becomes a fake `.mp3` choice → `-f sb0 -x --audio-format
    // mp3` → `.mhtml` output → container-mismatch hard-fail. Mirror the
    // video filter's vcodec!=none exclusion.
    final audioOnlyFormats =
        formats
            .where(
              (f) => f.isAudioOnly && f.acodec != null && f.acodec != 'none',
            )
            .toList()
          ..sort((a, b) => (b.tbr ?? 0).compareTo(a.tbr ?? 0));
    final seenAudio = <String>{}; // deduplicate by codec+bitrate bucket
    for (final format in audioOnlyFormats) {
      final codec = format.acodec ?? 'audio';
      final bitrateKbps = format.tbr != null ? format.tbr!.round() : 0;
      final dedupeKey = '${codec}_$bitrateKbps';
      if (seenAudio.contains(dedupeKey)) continue;
      seenAudio.add(dedupeKey);

      final bitrateLabel = bitrateKbps > 0 ? ' ${bitrateKbps}kbps' : '';
      final codecLabel = _formatCodecName(codec);
      final sizeStr =
          format.filesize != null ? _formatFileSize(format.filesize!) : '';

      qualities.add(
        Quality(
          qualityText: 'Audio Stream - $codecLabel$bitrateLabel',
          size: sizeStr,
          encryptedUrl: 'ytdlp:raw:${format.formatId}',
          mediaType: MediaType.audio,
          isAudioOnly: true,
          acodec: format.acodec,
          tbr: format.tbr,
          filesizeBytes: format.filesize,
        ),
      );
    }

    // Add audio format options (requires FFmpeg for conversion)
    final hasAudio = formats.any((f) => f.isAudioOnly);
    if (hasAudio || qualities.length > 1) {
      final audioFormats = [
        ('mp3', 'MP3', AppLocalizations.configDialogAudioDescMp3),
        ('m4a', 'M4A (AAC)', AppLocalizations.configDialogAudioDescM4a),
        ('opus', 'Opus', AppLocalizations.configDialogAudioDescOpus),
        ('wav', 'WAV', AppLocalizations.configDialogAudioDescWav),
      ];

      for (final (formatId, formatName, description) in audioFormats) {
        qualities.add(
          Quality(
            qualityText: AppLocalizations.configDialogAudioQualitySimple(
              formatName,
            ),
            size: description,
            encryptedUrl: 'ytdlp:audio:$formatId',
            mediaType: MediaType.audio,
            isAudioOnly: true,
          ),
        );
      }
    }

    // === Subtitle download options ===
    for (final sub in subtitles) {
      qualities.add(
        Quality(
          qualityText: '${sub.langName} (${sub.lang})',
          size: 'Original subtitle',
          encryptedUrl: 'ytdlp:subtitle:${sub.lang}',
          mediaType: MediaType.subtitle,
        ),
      );
    }
    for (final sub in autoSubtitles) {
      qualities.add(
        Quality(
          qualityText: '${sub.langName} (${sub.lang})',
          size: 'Auto-generated',
          encryptedUrl: 'ytdlp:subtitle:auto:${sub.lang}',
          mediaType: MediaType.subtitle,
        ),
      );
    }

    return qualities;
  }

  /// Format codec name for display (e.g., 'avc1.64001f' → 'H.264', 'opus' → 'Opus')
  String _formatCodecName(String? codec) {
    if (codec == null) return 'Unknown';
    final lower = codec.toLowerCase();
    if (lower.startsWith('avc') ||
        lower.startsWith('h264') ||
        lower == 'h.264') {
      return 'H.264';
    }
    if (lower.startsWith('vp9') || lower.startsWith('vp09')) return 'VP9';
    if (lower.startsWith('av01') || lower.startsWith('av1')) return 'AV1';
    if (lower.startsWith('hevc') ||
        lower.startsWith('hev') ||
        lower.startsWith('h265')) {
      return 'H.265';
    }
    if (lower == 'opus') return 'Opus';
    if (lower.startsWith('mp4a') || lower == 'aac') return 'AAC';
    if (lower == 'vorbis') return 'Vorbis';
    if (lower == 'flac') return 'FLAC';
    return codec.split('.').first.toUpperCase();
  }

  /// Get standard quality label based on resolution
  /// Maps non-standard resolutions to nearest standard tier
  String _getStandardQualityLabel(int width, int height) {
    // 8K tier: width >= 7680 OR height >= 4320
    if (width >= 7680 || height >= 4320) {
      return '8K';
    }
    // 4K tier: width >= 3840 OR height >= 2160
    if (width >= 3840 || height >= 2160) {
      return '4K';
    }
    // 2K/1440p tier: width >= 2560 OR height >= 1440
    if (width >= 2560 || height >= 1440) {
      return '1440p';
    }
    // 1080p tier: height >= 1000 (allows for ultra-wide 1080p)
    if (height >= 1000) {
      return '1080p';
    }
    // 720p tier: height >= 700
    if (height >= 700) {
      return '720p';
    }
    // 480p tier: height >= 400
    if (height >= 400) {
      return '480p';
    }
    // 360p tier: height >= 300
    if (height >= 300) {
      return '360p';
    }
    // Below 360p, show actual height
    return '${height}p';
  }

  /// Format file size to human readable string using FileUtils
  String _formatFileSize(int bytes) {
    return FileUtils.formatBytes(bytes, decimals: 1);
  }

  // ==================== Gallery-dl Fallback ====================

  /// Try extracting image info using gallery-dl.
  /// Used as fallback when yt-dlp fails or returns no video/audio formats.
  Future<Result<VideoInfo>> _extractWithGalleryDl(
    String url, {
    String? cookiesFile,
  }) async {
    try {
      final available = await _galleryDlDataSource.isAvailable();
      if (!available) {
        appLogger.debug('[gallery-dl] Binary not available, skipping fallback');
        return Result.failure(
          const AppException.download(message: 'gallery-dl not available'),
        );
      }

      final info = await _galleryDlDataSource.extractInfo(
        url,
        cookiesFile: cookiesFile,
      );
      return _buildGalleryDlResult(url, info);
    } on GalleryDlException catch (e) {
      appLogger.debug('[gallery-dl] Fallback failed: ${e.message}');
      return Result.failure(
        AppException.download(message: 'gallery-dl: ${e.message}'),
      );
    } catch (e, stack) {
      appLogger.error('[gallery-dl] Unexpected error', e, stack);
      return Result.failure(
        AppException.download(
          message: 'gallery-dl error: ${AppExceptionX.readableMessage(e)}',
        ),
      );
    }
  }

  /// Convert gallery-dl extraction result to VideoInfo with image Quality objects.
  Result<VideoInfo> _buildGalleryDlResult(String url, GalleryDlInfo info) {
    final qualities = <Quality>[];
    final imageItems = info.items.where((i) => i.isImage).toList();
    final videoItems = info.items.where((i) => i.isVideo).toList();

    // Image qualities
    if (imageItems.length == 1) {
      // Single image — one quality option (triggers auto-download rule)
      final item = imageItems.first;
      final resStr =
          (item.width != null && item.height != null)
              ? ' (${item.width}x${item.height})'
              : '';
      final sizeStr =
          item.filesize != null ? _formatFileSize(item.filesize!) : '';

      qualities.add(
        Quality(
          qualityText: 'Image$resStr .${item.extension}',
          size: sizeStr.isNotEmpty ? sizeStr : 'Original quality',
          encryptedUrl: 'gallerydl:${item.index}',
          mediaType: MediaType.image,
        ),
      );
    } else if (imageItems.length > 1) {
      // Carousel — "All images" + individual items
      qualities.add(
        Quality(
          qualityText: 'All ${imageItems.length} images',
          size: 'Download all as individual files',
          encryptedUrl: 'gallerydl:all:${imageItems.length}',
          mediaType: MediaType.image,
        ),
      );

      for (final item in imageItems) {
        final resStr =
            (item.width != null && item.height != null)
                ? ' (${item.width}x${item.height})'
                : '';
        final sizeStr =
            item.filesize != null ? _formatFileSize(item.filesize!) : '';

        qualities.add(
          Quality(
            qualityText: 'Image ${item.index}$resStr .${item.extension}',
            size: sizeStr,
            encryptedUrl: 'gallerydl:${item.index}',
            mediaType: MediaType.image,
          ),
        );
      }
    }

    // "All N videos" option when multiple videos in carousel
    if (videoItems.length > 1) {
      qualities.add(
        Quality(
          qualityText: 'All ${videoItems.length} videos',
          size: 'Download all as individual files',
          encryptedUrl: 'gallerydl:all_videos:${videoItems.length}',
          mediaType: MediaType.video,
        ),
      );
    }

    // Video qualities from gallery-dl (some posts have embedded videos)
    for (final item in videoItems) {
      final resStr =
          (item.width != null && item.height != null)
              ? ' (${item.width}x${item.height})'
              : '';
      qualities.add(
        Quality(
          qualityText: 'Video ${item.index}$resStr .${item.extension}',
          size: item.filesize != null ? _formatFileSize(item.filesize!) : '',
          encryptedUrl: 'gallerydl:${item.index}',
          mediaType: MediaType.video,
        ),
      );
    }

    if (qualities.isEmpty) {
      return Result.failure(
        const AppException.download(message: 'No downloadable content found'),
      );
    }

    final videoInfo = VideoInfo(
      url: url,
      title: info.title ?? 'Image',
      thumbnail: info.thumbnail,
      platform: info.platform,
      uploader: info.uploader,
      extractor: info.platform,
      availableQualities: qualities,
      downloadMethod: 'gallerydl',
    );

    appLogger.info(
      '✅ [gallery-dl] Built VideoInfo: ${videoInfo.title} '
      '(${qualities.length} qualities: ${imageItems.length} images, ${videoItems.length} videos)',
    );
    return Result.success(videoInfo);
  }

  /// Extract video info using API with retry logic
  Future<Result<VideoInfo>> _extractWithApiRetry(
    String url, {
    required int retryCount,
  }) async {
    try {
      appLogger.info(
        '🔍 [API] Extracting: $url${retryCount > 0 ? ' (retry $retryCount)' : ''}',
      );

      final response = await _apiService.search(url);

      // Check for empty response
      if (response.status == null &&
          response.data == null &&
          response.error == null) {
        throw Exception('Empty response from API');
      }

      // Check response status
      if (response.status != 'ok' || response.data == null) {
        final errorMessage = response.error ?? 'Failed to extract video info';
        appLogger.error('❌ [API] Extraction failed: $errorMessage');
        return Result.failure(AppException.network(message: errorMessage));
      }

      // Map DTO to domain model — VideoInfoMapper file removed in
      // commit 5a2aab0f. API-only path stubbed: throw clear error so
      // ytdlp fallback engine takes over instead of silent broken data.
      throw UnimplementedError(
        'VideoInfoMapper removed; API-only DownloadEngine path not '
        'wired in V2/PR #234 reconcile. Use DownloadEngine.auto or '
        '.ytdlpOnly until mapper restored.',
      );
      // ignore: dead_code
      final videoInfo = VideoInfo(
        url: url,
        title: '',
        thumbnail: '',
        availableQualities: const [],
      );

      appLogger.info('✅ [API] Extracted: ${videoInfo.title}');
      appLogger.debug(
        '[API] Found ${videoInfo.availableQualities.length} qualities',
      );

      return Result.success(videoInfo);
    } catch (e, stack) {
      appLogger.error('❌ [API] Extraction error', e, stack);

      // Retry logic: 1 retry after 2 seconds
      if (retryCount == 0) {
        appLogger.info('⏳ [API] Retrying in 2 seconds...');
        await Future.delayed(const Duration(seconds: 2));
        return _extractWithApiRetry(url, retryCount: 1);
      }

      return Result.failure(
        AppException.network(
          message: 'API error: ${AppExceptionX.readableMessage(e)}',
        ),
      );
    }
  }

  /// V2 reconcile: detect Facebook-specific "Cannot parse data" failure
  /// that signals expired session / missing cookies. Used by yt-dlp
  /// catch block to surface actionable login-required error.
  ///
  /// P1 (2026-05-25): pre-fix this returned true for EVERY `[facebook]
  /// ... Cannot parse data` message. yt-dlp's "Cannot parse data" has
  /// at least two root causes: (a) missing/expired cookies (re-login
  /// helps), and (b) FB changed payload / extractor lag (re-login
  /// does NOT help — login-spam loop). The refined gate:
  ///
  ///   - Facebook URL, AND
  ///   - "cannot parse data" in message, AND
  ///   - EITHER no usable cookies were attached to the extraction
  ///     (so cookies are a plausible fix) OR an explicit auth
  ///     marker co-occurs in the message (so we have positive signal
  ///     that auth is the bottleneck).
  ///
  /// When cookies WERE attached and no explicit marker is present,
  /// fall through to the generic extractor-failure path so the user
  /// sees an honest "extractor could not parse data" error instead
  /// of a misleading "login required" loop.
  bool _isFacebookCookieRequiredFailure(
    String url,
    String message, {
    bool hadCookies = false,
  }) {
    final platform = PlatformDetector.detectPlatform(url);
    if (platform != VideoPlatform.facebook) return false;
    final lower = message.toLowerCase();
    if (!lower.contains('cannot parse data')) return false;
    // No cookies attached → cookies are the plausible missing piece.
    if (!hadCookies) return true;
    // Cookies WERE attached → only auto-classify as auth issue when
    // yt-dlp's message itself signals auth (e.g., Facebook returned
    // a login wall response that the extractor surfaces alongside
    // "Cannot parse data"). Otherwise this is extractor / payload
    // breakage and a re-login won't fix it.
    return _facebookExplicitAuthMarkers.any(lower.contains);
  }

  static const _facebookExplicitAuthMarkers = [
    'login required',
    'please log in',
    'use --cookies',
    'cookies are needed',
    'sign in',
    'login_required',
    'checkpoint',
    'session has expired',
    'session expired',
  ];
}
