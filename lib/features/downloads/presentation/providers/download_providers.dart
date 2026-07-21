import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/services/smart_preload_service.dart';
import '../../../../core/auth/presentation/providers/auth_providers.dart';
import '../../../../core/binaries/binary_providers.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/providers/backend_providers.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/services/circuit_breaker_service.dart';
import '../../../../core/services/user_agent_service.dart';
import '../../../../core/utils/platform_detector.dart';
import '../../../settings/domain/services/browser_cookie_import_service.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../premium/presentation/providers/premium_providers.dart';
import '../../data/datasources/download_local_datasource.dart';
import '../../data/datasources/download_native_datasource.dart';
import '../../data/datasources/gallerydl_datasource.dart';
import '../../data/datasources/ytdlp_datasource.dart';
import '../../data/remote/api/ssvid_api_service.dart';
import '../../data/remote/ytdlp/cookie_exporter.dart';
import '../../data/repositories/download_repository_impl.dart';
import '../../domain/repositories/download_repository.dart';
import '../../domain/services/download_archive_service.dart';
import '../../domain/services/extraction_cache_service.dart';
import '../../domain/services/file_integrity_service.dart';
import '../../domain/services/orphaned_file_cleanup_service.dart';
import '../../domain/services/playlist_context_holder.dart';
import '../../domain/services/quality_fallback_service.dart';
import '../../domain/usecases/extract_video_info_usecase.dart';
import '../../domain/usecases/start_download_usecase.dart';
import '../../domain/usecases/pause_download_usecase.dart';
import '../../domain/usecases/resume_download_usecase.dart';
import '../../domain/usecases/cancel_download_usecase.dart';
import '../../domain/usecases/delete_download_usecase.dart';
import '../../domain/usecases/get_downloads_usecase.dart';

// ==================== API SERVICE ====================

/// Provider for SSvid API service
final ssvidApiServiceProvider = Provider<SSvidApiService>((ref) {
  return SSvidApiService();
});

// ==================== DATA SOURCES ====================

/// Provider for local data source
final downloadLocalDataSourceProvider = Provider<DownloadLocalDataSource>((
  ref,
) {
  final database = ref.watch(databaseProvider);
  return DownloadLocalDataSource(database);
});

// ==================== NATIVE DATASOURCE ====================

/// Provider for Rust native download engine datasource
final downloadNativeDataSourceProvider = Provider<DownloadNativeDataSource>((
  ref,
) {
  return DownloadNativeDataSource();
});

// ==================== REPOSITORY ====================

/// Provider for download repository
final downloadRepositoryProvider = Provider<DownloadRepository>((ref) {
  final localDataSource = ref.watch(downloadLocalDataSourceProvider);
  final ytdlpDataSource = ref.watch(ytdlpDataSourceProvider);
  final nativeDataSource = ref.watch(downloadNativeDataSourceProvider);
  final galleryDlDataSource = ref.watch(galleryDlDataSourceProvider);
  final userAgentService = ref.watch(userAgentServiceProvider);
  final playlistHolder = ref.watch(playlistContextHolderProvider);
  // RC10 round-5 — inject FileIntegrityService so the repository's
  // yt-dlp retry path can validate output files at completion (parity
  // with the fresh-download path).
  final fileIntegrityService = ref.watch(fileIntegrityServiceProvider);

  return DownloadRepositoryImpl(
    localDataSource,
    ytdlpDataSource,
    nativeDataSource,
    galleryDlDataSource,
    userAgentService,
    playlistHolder,
    fileIntegrityService,
  );
});

// ==================== USE CASES ====================

/// Provider for extract video info use case
final extractVideoInfoUseCaseProvider = Provider<ExtractVideoInfoUseCase>((
  ref,
) {
  final apiService = ref.watch(ssvidApiServiceProvider);
  final ytdlpDataSource = ref.watch(ytdlpDataSourceProvider);
  final galleryDlDataSource = ref.watch(galleryDlDataSourceProvider);
  final circuitBreaker = ref.watch(circuitBreakerProvider);
  final backendService = ref.watch(backendServiceProvider);
  return ExtractVideoInfoUseCase(
    apiService,
    ytdlpDataSource,
    galleryDlDataSource,
    circuitBreaker: circuitBreaker,
    extractionFailureTelemetrySink: ({
      required url,
      required platform,
      required errorCode,
      required errorPhase,
      required errorMessage,
      required metadata,
    }) {
      unawaited(() async {
        await backendService.submitDownloadError(
          url: url,
          platform: platform,
          errorCode: errorCode.name,
          errorPhase: errorPhase,
          errorMessage: errorMessage,
          metadata: jsonEncode(metadata),
        );
      }());
    },
  );
});

/// Provider for orphaned file cleanup service
final orphanedFileCleanupServiceProvider = Provider<OrphanedFileCleanupService>(
  (ref) {
    final repository = ref.watch(downloadRepositoryProvider);
    return OrphanedFileCleanupService(repository);
  },
);

/// Provider for file integrity service
final fileIntegrityServiceProvider = Provider<FileIntegrityService>((ref) {
  final binaryManager = ref.watch(binaryManagerProvider);
  return FileIntegrityService(binaryManager);
});

/// Provider for start download use case
final startDownloadUseCaseProvider = Provider<StartDownloadUseCase>((ref) {
  final repository = ref.watch(downloadRepositoryProvider);
  final ytdlpDataSource = ref.watch(ytdlpDataSourceProvider);
  final galleryDlDataSource = ref.watch(galleryDlDataSourceProvider);
  final fileIntegrityService = ref.watch(fileIntegrityServiceProvider);
  final quotaReserver = ref.watch(downloadQuotaNotifierProvider.notifier);
  final backendService = ref.watch(backendServiceProvider);
  return StartDownloadUseCase(
    repository,
    ytdlpDataSource,
    galleryDlDataSource,
    fileIntegrityService,
    quotaReserver,
    ({
      required download,
      required errorCode,
      required errorPhase,
      required errorMessage,
      required metadata,
    }) {
      unawaited(() async {
        await backendService.submitDownloadError(
          url: download.url,
          platform: download.platform,
          errorCode: errorCode.name,
          errorPhase: errorPhase,
          errorMessage: errorMessage,
          metadata: jsonEncode(metadata),
        );
      }());
    },
  );
});

/// Provider for pause download use case
final pauseDownloadUseCaseProvider = Provider<PauseDownloadUseCase>((ref) {
  final repository = ref.watch(downloadRepositoryProvider);
  return PauseDownloadUseCase(repository);
});

/// Provider for resume download use case
final resumeDownloadUseCaseProvider = Provider<ResumeDownloadUseCase>((ref) {
  final repository = ref.watch(downloadRepositoryProvider);
  return ResumeDownloadUseCase(repository);
});

/// Provider for cancel download use case
final cancelDownloadUseCaseProvider = Provider<CancelDownloadUseCase>((ref) {
  final repository = ref.watch(downloadRepositoryProvider);
  return CancelDownloadUseCase(repository);
});

/// Provider for delete download use case
final deleteDownloadUseCaseProvider = Provider<DeleteDownloadUseCase>((ref) {
  final repository = ref.watch(downloadRepositoryProvider);
  return DeleteDownloadUseCase(repository);
});

/// Provider for get downloads use case
final getDownloadsUseCaseProvider = Provider<GetDownloadsUseCase>((ref) {
  final repository = ref.watch(downloadRepositoryProvider);
  return GetDownloadsUseCase(repository);
});

// ==================== GALLERY-DL ====================

/// Provider for gallery-dl data source (image extraction & download)
/// Uses BinaryManager for on-demand binary download
final galleryDlDataSourceProvider = Provider<GalleryDlDataSource>((ref) {
  final binaryManager = ref.watch(binaryManagerProvider);
  return GalleryDlDataSource(binaryManager);
});

// ==================== CIRCUIT BREAKER ====================

/// Singleton circuit breaker for yt-dlp extraction calls.
/// Protects against repeated failures per platform (rate limiting, etc.).
final circuitBreakerProvider = Provider<CircuitBreakerService>((ref) {
  return CircuitBreakerService();
});

/// Singleton User-Agent rotation service.
/// Provides randomized browser UAs to avoid anti-bot fingerprinting.
final userAgentServiceProvider = Provider<UserAgentService>((ref) {
  return UserAgentService();
});

/// Browser cookie import service for --cookies-from-browser.
/// Detects installed browsers and stores user selection.
final browserCookieImportServiceProvider = Provider<BrowserCookieImportService>(
  (ref) {
    final prefs = ref.watch(sharedPreferencesProvider);
    return BrowserCookieImportService(prefs);
  },
);

/// Current browser cookie import arg (e.g., "chrome", "firefox").
/// Returns null if browser cookie import is disabled.
final cookiesFromBrowserProvider = Provider<String?>((ref) {
  final service = ref.watch(browserCookieImportServiceProvider);
  return service.cookiesFromBrowserArg;
});

/// Auto-detected fallback browser for `--cookies-from-browser` —
/// activates ONLY when the primary cookies path fails with a
/// session-likely error (loginRequired / formatNotAvailable).
///
/// Distinct from [cookiesFromBrowserProvider]:
///   - That one reflects the user's explicit Settings choice. Null
///     when user hasn't configured.
///   - This one is silent best-guess when the user hasn't configured.
///     Used only on retry, never on the first extraction attempt.
///
/// Returns null when no supported browser is detected on the host —
/// the extraction path then falls through to retry-without-cookies
/// as before.
final cookiesFromBrowserFallbackProvider = Provider<String?>((ref) {
  final service = ref.watch(browserCookieImportServiceProvider);
  return service.suggestFallbackBrowser()?.ytdlpName;
});

/// Ordered fallback browser chain — yt-dlp names of every installed
/// browser the cookies-from-browser retry path should try in turn.
///
/// Why a list, not a single value: yt-dlp `--cookies-from-browser
/// [name]` fails with "Could not copy [browser] cookie database"
/// when the named browser holds its SQLite store open (yt-dlp
/// issue 7271). Windows production log §138 caught Chrome doing
/// exactly this on every retry. The chain lets the extract /
/// download path try the next safe candidate (Edge, Firefox, …)
/// instead of surfacing a misleading `loginRequired` to the user.
///
/// Empty list when no supported browser is detected on the host.
/// Order is platform-aware (see [BrowserCookieImportService.
/// suggestFallbackBrowserChain]). On Windows the order pushes
/// Chrome LAST because it is the most-likely-locked candidate.
final cookiesFromBrowserFallbackChainProvider = Provider<List<String>>((ref) {
  final service = ref.watch(browserCookieImportServiceProvider);
  return [for (final b in service.suggestFallbackBrowserChain()) b.ytdlpName];
});

// ==================== QUALITY FALLBACK ====================

/// Provider for quality fallback service (pure Dart, no dependencies).
final qualityFallbackServiceProvider = Provider<QualityFallbackService>((ref) {
  return const QualityFallbackService();
});

/// Whether quality fallback is enabled.
/// Default: true. Stored in SharedPreferences key 'quality_fallback_enabled'.
final qualityFallbackEnabledProvider = Provider<bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getBool('quality_fallback_enabled') ?? true;
});

// ==================== EXTRACTION METADATA CACHE ====================

/// File-based extraction metadata cache (24h TTL, 100MB max).
/// Complements the in-memory ExtractionCache (SharedPrefs, 1h TTL).
final extractionCacheServiceProvider = FutureProvider<ExtractionCacheService>((
  ref,
) async {
  final appSupport = await getApplicationSupportDirectory();
  final cacheDir = '${appSupport.path}/extraction_metadata';
  return ExtractionCacheService(cacheDir);
});

// ==================== DOWNLOAD ARCHIVE ====================

/// Provider for download archive service (duplicate prevention).
final downloadArchiveServiceProvider = Provider<DownloadArchiveService>((ref) {
  return DownloadArchiveService();
});

// ==================== YT-DLP ====================

/// Provider for yt-dlp data source
/// Uses BinaryManager for on-demand binary download
/// Injects CircuitBreakerService for per-platform failure protection
/// Injects UserAgentService for rotating User-Agent strings
final ytdlpDataSourceProvider = Provider<YtDlpDataSource>((ref) {
  final binaryManager = ref.watch(binaryManagerProvider);
  final circuitBreaker = ref.watch(circuitBreakerProvider);
  final userAgentService = ref.watch(userAgentServiceProvider);
  return YtDlpDataSource(
    binaryManager,
    circuitBreaker: circuitBreaker,
    userAgentService: userAgentService,
  );
});

/// Provider for cookie exporter (converts app cookies to yt-dlp format)
final cookieExporterProvider = Provider<CookieExporter>((ref) {
  return CookieExporter();
});

/// Provider to check if yt-dlp is available
final ytdlpAvailableProvider = FutureProvider<bool>((ref) async {
  final datasource = ref.watch(ytdlpDataSourceProvider);
  return datasource.isAvailable();
});

/// Provider for yt-dlp version info
final ytdlpVersionProvider = FutureProvider<String?>((ref) async {
  final datasource = ref.watch(ytdlpDataSourceProvider);
  await datasource.initialize();
  return datasource.version;
});

/// Provider to get cookies file for a URL (auto-detects platform and exports cookies)
/// Returns null if no cookies available for the platform
/// NOTE: Uses autoDispose to always fetch fresh cookies (no stale cache)
final cookiesFileForUrlProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, url) async {
      try {
        // Detect platform from URL
        final platform = PlatformDetector.detectPlatform(url);
        final platformString = platform.toDbString();

        // Skip for unknown platforms
        if (platformString == 'unknown' || platformString == 'other') {
          return null;
        }

        // Get cookies for this platform
        final getCookiesUseCase = ref.read(getPlatformCookiesUseCaseProvider);
        final result = await getCookiesUseCase(platformString);

        if (!result.isSuccess || result.dataOrNull == null) {
          return null;
        }

        final cookie = result.dataOrNull!;

        if (platformString == 'youtube') {
          final cookieNames = _extractCookieNames(cookie.cookieString);
          final authNames =
              cookieNames.where(_isYouTubeAuthCookieName).toList();
          appLogger.info(
            '[Cookies] Loaded YouTube cookie record: '
            'length=${cookie.cookieString.length}, '
            'cookieCount=${cookieNames.length}, '
            'authCount=${authNames.length}',
          );

          if (authNames.isEmpty) {
            appLogger.warning(
              '[Cookies] Stored YouTube cookies are missing HttpOnly session '
              'markers; clearing stale cookie record and requiring re-login.',
            );
            final removeCookiesUseCase = ref.read(
              removePlatformCookiesUseCaseProvider,
            );
            await removeCookiesUseCase(platformString);
            return null;
          }
        }

        // Export to temp file
        final exporter = ref.read(cookieExporterProvider);
        final cookiesFile = await exporter.exportPlatformCookies(cookie);

        return cookiesFile;
      } catch (_) {
        return null;
      }
    });

List<String> _extractCookieNames(String cookieString) {
  final names = <String>[];
  final lines = cookieString.split('\n');

  if (lines.any((line) => line.split('\t').length >= 7)) {
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final fields = trimmed.split('\t');
      if (fields.length >= 7) {
        names.add(fields[5]);
      }
    }
    return names;
  }

  for (final part in cookieString.split(';')) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final equalsIndex = trimmed.indexOf('=');
    if (equalsIndex <= 0) continue;
    names.add(trimmed.substring(0, equalsIndex).trim());
  }

  return names;
}

bool _isYouTubeAuthCookieName(String name) {
  return name == 'SID' ||
      name == 'HSID' ||
      name == 'SSID' ||
      name == 'APISID' ||
      name == 'SAPISID' ||
      name == 'LOGIN_INFO' ||
      name == '__Secure-1PSID' ||
      name == '__Secure-3PSID' ||
      name == '__Secure-1PSIDTS' ||
      name == '__Secure-3PSIDTS';
}

// ==================== SMART PRELOAD ====================

/// Singleton SmartPreloadService — manages the 5 MB preload cache.
/// Uses the OS application-cache directory (subject to OS eviction).
final smartPreloadServiceProvider = Provider<SmartPreloadService>((ref) {
  return SmartPreloadService();
});

// ==================== RATING TRIGGER ====================

/// Signals when the user should be prompted to rate the app.
/// Set to `true` by DownloadsNotifier after N successful downloads.
/// Reset to `false` after the dialog is shown (or dismissed).
final ratingTriggerProvider = StateProvider<bool>((ref) => false);
