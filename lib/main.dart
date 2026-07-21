import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:path/path.dart' as p_lib;
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show Sentry, SentryLevel;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:media_kit/media_kit.dart';
import 'app.dart';
import 'bridge/frb_generated.dart';
import 'bridge/api.dart' as native;
import 'floating_window_main.dart';
import 'core/config/env_config.dart';
import 'core/constants/app_constants.dart';
import 'core/l10n/app_localizations.dart';
import 'core/logging/app_logger.dart';
import 'core/migrations/v2_format_preset_migration.dart';
import 'core/migrations/v2_savedpref_to_preset_importer.dart';
import 'core/services/error_reporter_service.dart';
import 'core/services/instrumentation.dart';
import 'core/services/sentry_error_reporter.dart';
import 'core/services/noop_error_reporter.dart';
import 'core/services/notification_service.dart';
import 'core/services/startup_service.dart';
import 'core/services/startup_profiler.dart';
import 'core/services/webview_environment_service.dart';
import 'features/browser/data/webview/app_webview.dart'
    show setWebViewBreadcrumbSink;
import 'core/services/window_service.dart';
import 'core/services/keyboard_service.dart';
import 'core/services/tray_service.dart';
import 'core/utils/process_helper.dart';
import 'core/navigation/navigation_constants.dart';
import 'core/config/brand_config.dart';
import 'core/network/ssl_overrides.dart';
import 'core/providers/navigation_provider.dart';
import 'core/widgets/custom_error_widget.dart';
import 'features/downloads/presentation/providers/extraction_cache_provider.dart';
import 'features/floating_capture/presentation/providers/capture_preferences_provider.dart';
import 'features/floating_capture/presentation/providers/floating_capture_providers.dart';
import 'features/floating_capture/presentation/providers/pending_capture_download_provider.dart';
import 'features/floating_capture/presentation/providers/pending_capture_open_in_app_provider.dart';
import 'features/floating_capture/presentation/providers/pending_capture_play_saved_file_provider.dart';
import 'features/premium/presentation/providers/license_verification_providers.dart';
import 'features/premium/presentation/providers/premium_providers.dart';
import 'features/settings/presentation/providers/settings_provider.dart';

Future<void> main(List<String> args) async {
  final startupProfiler = StartupProfiler.instance;
  startupProfiler.reset(session: 'cold_start');

  WidgetsFlutterBinding.ensureInitialized();
  startupProfiler.mark('binding_ready');

  // Resolve brand from compile-time dart-define (must be first)
  BrandConfig.init();
  startupProfiler.mark('brand_ready');

  // Resolve app version from native platform (always matches pubspec.yaml)
  await AppConstants.init();
  startupProfiler.mark('app_constants_ready');

  // Phase 1A.3c: Multi-window dispatch — must run BEFORE any heavy main-app
  // init. The floating capture popup (`desktop_multi_window`) spawns a
  // separate Flutter engine; that engine's main() is THIS function with
  // launch arguments set. We must short-circuit to the popup app and skip
  // Rust bridge / Sentry / tray / etc., otherwise the popup feels slow and
  // we waste resources initializing services it doesn't use.
  //
  // For the main window, fromCurrentEngine().arguments is empty → fall
  // through to normal init below.
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    try {
      final wc = await WindowController.fromCurrentEngine();
      final parsed = parseFloatingWindowLaunchArgs(wc.arguments);
      if (parsed != null && parsed['windowType'] == 'floating_capture') {
        await runFloatingWindow(wc, parsed);
        return;
      }
    } catch (_) {
      // Plugin not yet registered (rare) or non-multi-window launch.
      // Fall through to normal main app.
    }
  }

  // SSL: bypass certificate verification for known-safe hosts (GitHub CDN, ffmpeg CDN).
  // Fixes CERTIFICATE_VERIFY_FAILED on Windows fresh installs / corporate environments.
  HttpOverrides.global = SsvidHttpOverrides();

  // Phase A: error reporter first (needed to catch errors in subsequent phases)
  final ErrorReporterService errorReporter =
      EnvConfig.isSentryConfigured
          ? SentryErrorReporter()
          : NoOpErrorReporter();
  await errorReporter.init();
  startupProfiler.mark('error_reporter_ready');

  // Pipe WebView lifecycle events into Sentry breadcrumbs so the trail
  // before a crash/hang (load_started → load_hang or load_failed) is
  // attached to whatever event Sentry captures next.
  setWebViewBreadcrumbSink((message, data) {
    // Use safeBreadcrumb so a broken reporter cannot crash the WebView
    // lifecycle hot path. Same fail-safe contract as everywhere else.
    safeBreadcrumb(errorReporter, message, data: data);
  });

  // Wire Flutter framework error handler → Sentry
  FlutterError.onError = (details) {
    // Suppress Flutter's HardwareKeyboard "key already pressed" assertion.
    // The real fix is the channel wrapper below; this catches any remaining leaks.
    if (kDebugMode &&
        details.exception is AssertionError &&
        details.exception.toString().contains('_pressedKeys.containsKey')) {
      return;
    }

    // Fully suppress Flutter's MouseTracker
    // `_debugDuringDeviceUpdate` assertion in debug builds —
    // NO `presentError`, NO Sentry forward, NO console output.
    //
    // Why a hard silence is the right call:
    // 1. The assertion is `debug`-only (release builds strip it
    //    entirely). It does not break dispatch — Flutter's
    //    try/finally clears the flag and continues.
    // 2. `FlutterError.presentError` writes "Another exception
    //    was thrown" to stderr AND builds a full stack trace.
    //    In a hover/scroll storm, stack trace generation alone
    //    is enough to peg a debug build (each trace is ms-class).
    //    log.md 2026-05-12 §650-1049 captured ~400 of these in
    //    seconds — the visible "đơ đơ" lag the user reported.
    // 3. We already fixed the amplifier (dedupe + this whitelist
    //    keeps it out of the Sentry forward path). What was left
    //    was the stderr write itself.
    //
    // Trade-off: a developer who genuinely wants to *see* one of
    // these assertions during local debugging will need to
    // temporarily remove this gate. That's the same trade-off
    // the `_pressedKeys.containsKey` whitelist above already
    // makes — and that gate has been silent for months without
    // hiding real bugs.
    if (kDebugMode &&
        details.exception is AssertionError &&
        details.exception.toString().contains('_debugDuringDeviceUpdate')) {
      return;
    }

    FlutterError.presentError(details);
    unawaited(
      safeCaptureException(
        errorReporter,
        details.exception,
        stackTrace: details.stack,
        scopeConfig: (scope) => scope.setTag('context', 'FlutterError.onError'),
        backendMetadata: const {'context': 'FlutterError.onError'},
      ),
    );
  };

  // Workaround: Flutter macOS debug keyboard bug.
  // HardwareKeyboard._assertEventIsRegular throws on stale keys (hot restart,
  // lost KeyUp events), aborting handleKeyEvent and blocking ALL key input.
  // Fix: wrap the keyboard channel to catch assertion errors. The key event
  // for that press is lost, but KeyUp will clear the stale state so
  // subsequent presses work normally. Release builds are unaffected.
  if (kDebugMode) {
    // ignore: deprecated_member_use — no non-deprecated API to intercept
    // key events before HardwareKeyboard assertion. This is a framework
    // bug workaround, not normal key handling.
    // ignore: deprecated_member_use
    final keyManager = ServicesBinding.instance.keyEventManager;
    SystemChannels.keyEvent.setMessageHandler((dynamic message) async {
      try {
        // ignore: deprecated_member_use
        return await keyManager.handleRawKeyMessage(
          message as Map<String, dynamic>,
        );
      } on AssertionError {
        return <String, dynamic>{'handled': false};
      }
    });
  }

  // Wire uncaught Dart errors → Sentry.
  // safeCaptureException wraps the call so a broken reporter cannot loop —
  // if Sentry init failed and capture itself rejects, we'd otherwise feed the
  // failure back through PlatformDispatcher.onError. The fail-safe wrapper
  // breaks the cycle (and its outer try/catch matches the original sync behavior).
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(
      safeCaptureException(
        errorReporter,
        error,
        stackTrace: stack,
        scopeConfig:
            (scope) => scope.setTag('context', 'PlatformDispatcher.onError'),
        backendMetadata: const {'context': 'PlatformDispatcher.onError'},
      ),
    );
    return true;
  };

  // Set custom error widget for release builds
  ErrorWidget.builder =
      (details) => CustomErrorWidget(details, errorReporter: errorReporter);

  appLogger.info('${AppConstants.appName} starting...');
  cleanOldLogs();

  // Phase B: parallelize independent inits (i18n + prefs + notification wiring)
  late SharedPreferences sharedPreferences;
  await Future.wait([
    EasyLocalization.ensureInitialized(),
    SharedPreferences.getInstance().then((p) => sharedPreferences = p),
    notificationService.initialize(),
  ]);
  startupProfiler.mark('bootstrap_io_ready');

  // Phase B.1 — One-shot v1.x → v2.0 FormatPreset migration. Idempotent
  // (short-circuits on records that already carry `schemaVersion`),
  // never throws on bad user data (corrupt JSON → recover by reseeding
  // built-ins). Runs synchronously after SharedPreferences is ready so
  // the ActivePresetController constructed in Phase E reads v2-shaped
  // records, not the legacy 7-field `FormatPreset`. See
  // `lib/core/migrations/v2_format_preset_migration.dart` and the 18
  // migration tests in `test/core/migrations/`.
  try {
    await V2FormatPresetMigration(prefs: sharedPreferences).run();
    startupProfiler.mark('v2_format_preset_migration_done');
  } catch (e, st) {
    // Defense in depth — migration's internal error paths already
    // recover from corrupt JSON; this catch only fires on truly
    // unexpected failures (disk full, etc.). Log and continue so the
    // user can still launch (popover falls back to canonical built-ins
    // via `availableExtendedPresetsProvider`).
    appLogger.error('V2FormatPresetMigration unexpectedly threw', e, st);
  }

  // Phase B.2 — Import legacy `settings_platform_preferences` saved-pref
  // entries (TikTok=1080p, YouTube=720p, etc.) as discoverable preset
  // shadows in the chip popover. One-shot, idempotent via
  // `imported_savedprefs_v1` flag. Bridges the pre-V2 "buried in dialog"
  // save-as-preference flow into the new chip popover discovery
  // surface — both stores remain authoritative for their original
  // purposes (Rule 2 still auto-applies savedPref per platform).
  try {
    await V2SavedPrefToPresetImporter(prefs: sharedPreferences).run();
    startupProfiler.mark('v2_savedpref_import_done');
  } catch (e, st) {
    appLogger.error('V2SavedPrefToPresetImporter unexpectedly threw', e, st);
  }

  // Phase C+D: keep only first-frame-critical desktop work on the critical path.
  MediaKit.ensureInitialized();
  await Future.wait([
    // Desktop: window must be ready before the first frame.
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
      WindowService.initialize().then((_) {
        startupProfiler.mark('desktop_shell_ready');
      }),
    // Rust bridge init (independent of window)
    _initRustBridge()
        .then((_) {
          startupProfiler.mark('rust_ready');
        })
        .catchError((e) {
          appLogger.fatal(
            'CRITICAL: Rust bridge init failed — downloads/search will not work: $e',
          );
        }),
    // WebView2 environment with persistent per-brand userDataFolder.
    // Must complete before the first InAppWebView builds; on macOS/Linux
    // this returns immediately (no-op).
    WebViewEnvironmentService.init().then((_) {
      startupProfiler.mark('webview_environment_ready');
    }),
  ]);
  startupProfiler.mark('critical_boot_ready');

  // Phase E: create ProviderContainer and run app immediately
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      errorReporterServiceProvider.overrideWithValue(errorReporter),
      // Phase 1B.1+1B.2: wire floating capture's "Download" + "Open in
      // SSvid" buttons to the host app. Each click pushes its payload
      // into the matching pending-* provider; AppScaffold/HomeScreen consume
      // the providers depending on whether the flow can stay out-of-app.
      //
      // - onDownload fires on a video URL — AppScaffold first tries the
      //   background direct-download path, then falls back to HomeScreen UI.
      // - onOpenInApp fires on a non-video URL (playlist / channel /
      //   search per spec Q18) — HomeScreen brings itself to focus and
      //   pre-fills the URL field WITHOUT auto-starting download. User
      //   then chooses the explicit action.
      //
      // The other in-feature defaults (browser, window focus) come from
      // buildDefaultCaptureSideEffectRouter.
      captureSideEffectRouterProvider.overrideWith(
        (ref) => buildDefaultCaptureSideEffectRouter(
          onDownload: (request) async {
            ref.read(pendingCaptureDownloadProvider.notifier).state = request;
          },
          onOpenInApp: (url) async {
            // Bring the main app forward so the user can act on the URL.
            // Errors are logged inside WindowService.show.
            try {
              await WindowService.show();
            } catch (e, s) {
              appLogger.error('[Capture] OpenInApp focus failed', e, s);
            }
            ref.read(pendingCaptureOpenInAppProvider.notifier).state = url;
          },
          // Phase 1B.3: popup menu "Settings" focuses the main app and
          // jumps to the Settings tab. AppScaffold listens to
          // navigationProvider, so a state change is enough — no
          // pending-payload provider needed (no per-widget hand-off).
          onOpenSettings: () async {
            // v2.2 Phase 2C — idempotent: skip focus-stealing window-show
            // when user is already on the Settings tab. Without this guard
            // the popup→Settings click flickers focus when user is already
            // looking at Settings.
            final currentTab = ref.read(navigationProvider);
            final alreadyOnSettings =
                currentTab == NavigationConstants.settingsIndex;
            if (!alreadyOnSettings) {
              try {
                await WindowService.show();
              } catch (e, s) {
                appLogger.error('[Capture] OpenSettings focus failed', e, s);
              }
              ref
                  .read(navigationProvider.notifier)
                  .navigateToTab(NavigationConstants.settingsIndex);
            }
          },
          // v2.2 Phase 2C: surface "Until I resume" snooze as a system
          // notification breadcrumb so user can find resume control even
          // after the popup auto-hides.
          onShowSnoozeToast: () async {
            if (!ref.read(settingsProvider).notificationsEnabled) return;
            try {
              await notificationService.show(
                title:
                    '${BrandConfig.current.appName} — '
                    '${AppLocalizations.captureNotifySnoozedTitle}',
                body: AppLocalizations.captureNotifySnoozedBody,
              );
            } catch (e, s) {
              appLogger.warning(
                '[Capture] snooze toast notification failed',
                e,
                s,
              );
            }
          },
          // v2.2 Phase 2D.1 (CPO feedback): popup _CompletedRow CTAs
          // route here. Open folder stays OS-native; Play routes back into
          // the app so media opens in the in-app player surface.
          onOpenSavedFolder: (path) async {
            try {
              final file = File(path);
              final fileExists = await file.exists();
              final parentPath = file.parent.path;
              if (fileExists) {
                await ProcessHelper.revealInFileManager(
                  path,
                  fallbackDirectory: parentPath,
                );
              } else if (Platform.isLinux) {
                // xdg-open the parent directory; -R reveal isn't standard.
                await ProcessHelper.openDirectoryInFileManager(parentPath);
              } else {
                await ProcessHelper.openDirectoryInFileManager(parentPath);
              }
            } catch (e, s) {
              appLogger.warning(
                '[Capture] OpenSavedFolder failed for $path',
                e,
                s,
              );
            }
          },
          onPlaySavedFile: (path) async {
            ref.read(pendingCapturePlaySavedFileProvider.notifier).state = path;
          },
          // Phase 2D.2 (anh Quân Windows feedback): URL was dropped by
          // an anti-spam layer (already actioned within cooldown, or
          // post-action blocklist active). Surface a small system
          // notification so the user knows the capture was recognized
          // but deduped — instead of silent feature-broken impression.
          // Throttle is enforced upstream (1 per URL per 60s in service).
          onNotifyDeduplicated: (url) async {
            if (!ref.read(settingsProvider).notificationsEnabled) return;
            try {
              await notificationService.show(
                title:
                    '${BrandConfig.current.appName} — '
                    '${AppLocalizations.captureNotifySnoozedTitle}',
                body: AppLocalizations.captureNotifyDeduplicatedBody,
              );
            } catch (e, s) {
              appLogger.warning(
                '[Capture] NotifyUrlDeduplicated notification failed',
                e,
                s,
              );
            }
          },
        ),
      ),
    ],
    observers: [_AppProviderObserver()],
  );

  // Register the URI channel before backend startup so macOS can flush any
  // cold-launch payment return queued by AppDelegate without a timing delay.
  container.read(licenseActivationHandlerProvider);

  try {
    await container.read(premiumLicenseProvider.notifier).refresh();
    final localLicense = container.read(premiumLicenseProvider);
    final needsVidComboBootstrap =
        BrandConfig.current.backendType == BackendType.php &&
        localLicense.isFree;
    container.read(premiumBootstrapReadyProvider.notifier).state =
        !needsVidComboBootstrap;
    appLogger.info(
      '💎 [Premium] Bootstrap: localTier=${localLicense.tier.name}, '
      'access=${container.read(isPremiumProvider)}, '
      'ready=${!needsVidComboBootstrap}',
    );
    startupProfiler.mark('premium_license_loaded');
  } catch (e) {
    appLogger.warning('Premium license preload failed (non-critical): $e');
    container.read(premiumBootstrapReadyProvider.notifier).state = true;
  }

  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('en'),
        Locale('vi'),
        Locale('es'),
        Locale('pt'),
        Locale('ja'),
        Locale('ar'),
        Locale('de'),
        Locale('fr'),
        Locale('hi'),
        Locale('id'),
        Locale('ko'),
        Locale('ru'),
        Locale('th'),
        Locale('tr'),
        Locale('zh'),
      ],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      assetLoader: const RootBundleAssetLoader(),
      useOnlyLangCode: true,
      child: UncontrolledProviderScope(
        container: container,
        child: const SsvidApp(),
      ),
    ),
  );
  startupProfiler.mark('run_app_dispatched');

  WidgetsBinding.instance.addPostFrameCallback((_) {
    startupProfiler.mark('first_frame_presented');
    startupProfiler.logSummary(label: 'first_frame');
    unawaited(_runPostFrameStartupWork(startupProfiler));
  });

  // Phase F: deferred post-first-frame inits (non-blocking)
  // Eagerly initialize extraction cache so first URL paste has zero cache-load delay
  container.read(extractionHistoryProvider);
  startupProfiler.mark('extraction_cache_kicked');

  // Backend startup (fire-and-forget)
  unawaited(
    StartupService.initialize(container).whenComplete(() {
      startupProfiler.mark('backend_startup_ready');
      startupProfiler.logSummary(label: 'background');
    }),
  );

  // Handle deep-link launch URI from command-line args (Windows/Linux)
  _handleLaunchUri(args, container);
  startupProfiler.mark('launch_uri_checked');

  // Phase G: floating capture auto-start (post-first-frame, non-blocking).
  // The CaptureLifecycleController owns ClipboardMonitorService + the
  // CaptureService.sideEffects subscription. Failures are caught inside
  // the controller and logged — they must NOT crash the host app.
  // Linux gracefully degrades because NativeClipboardSource throws
  // MissingPluginException on start which the controller swallows.
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootFloatingCapture(container));
    });
  }
}

/// Reads the user's floating-capture preference and starts the lifecycle
/// only if enabled. Default (first run) is enabled per spec Q6.
Future<void> _bootFloatingCapture(ProviderContainer container) async {
  try {
    final prefs = await container.read(capturePreferencesStoreProvider).read();
    if (!prefs.enabled) {
      appLogger.info('[Boot] floating capture disabled by user preference');
      return;
    }
    await container.read(captureLifecycleControllerProvider).start();
  } catch (e, s) {
    // Boot must keep going even if capture fails — log and move on.
    appLogger.error('[Boot] floating capture init failed', e, s);
  }
}

/// Initialize Rust Bridge and DownloadManager.
///
/// Handles "already initialized" gracefully on hot restart (Rust persists
/// across Dart resets). Real failures are rethrown so the caller knows
/// Rust features won't work.
Future<void> _initRustBridge() async {
  // Step 1: Initialize Rust bridge
  try {
    appLogger.debug('Initializing Rust bridge...');

    // On macOS/iOS, flutter_rust_bridge's default loader tries:
    //   1. ioDirectory/libnative.dylib (relative to cwd — works in debug, fails in release)
    //   2. rust_builder.framework/rust_builder (for plugin template)
    //   3. native.framework/native (relative dlopen — fails when app not launched from project dir)
    //
    // Fix: In release mode, resolve the framework path from the app bundle so
    // dlopen can find it regardless of working directory.
    ExternalLibrary? externalLibrary;
    if (!kDebugMode && Platform.isMacOS) {
      final execPath = Platform.resolvedExecutable;
      // execPath = .../ssvid.app/Contents/MacOS/ssvid
      final frameworkPath = execPath.replaceFirst(
        RegExp(r'/MacOS/[^/]+$'),
        '/Frameworks/native.framework/native',
      );
      appLogger.debug('Loading Rust lib from: $frameworkPath');
      if (File(frameworkPath).existsSync()) {
        externalLibrary = ExternalLibrary.open(frameworkPath);
      }
    }

    await RustLib.init(externalLibrary: externalLibrary);
    appLogger.info('Rust bridge initialized successfully');
  } catch (e, stackTrace) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('already initialized') ||
        msg.contains('already been initialized')) {
      appLogger.info('Rust bridge already initialized (hot restart)');
    } else {
      appLogger.fatal('Failed to initialize Rust bridge', e, stackTrace);
      rethrow;
    }
  }

  // Step 1.5: Initialize Rust telemetry (non-critical, best-effort).
  //
  // Plan D2 chicken-and-egg: init_telemetry is exposed via FRB so it can
  // only be called AFTER RustLib.init succeeds. The window of un-instrumented
  // Rust code (load → RustLib::init → here) is tiny and rarely fails, so
  // we accept this small blind spot rather than building a non-FRB native
  // init path.
  try {
    final panicDir = await _resolveRustPanicDir();
    await native.initTelemetry(
      dsn: EnvConfig.isSentryConfigured ? EnvConfig.sentryDsn : '',
      release: '${BrandConfig.current.brand.name}@${AppConstants.appVersion}',
      panicDir: panicDir,
    );
    appLogger.info('Rust telemetry initialized (panic dir: $panicDir)');
  } catch (e) {
    appLogger.warning('Rust telemetry init failed (non-critical): $e');
  }

  // Step 2: Initialize DownloadManager
  try {
    await native.downloadManagerInit(maxConcurrent: 10);
    appLogger.info('Rust DownloadManager initialized (max: 10 concurrent)');
  } catch (e, stackTrace) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('already initialized') ||
        msg.contains('already been initialized')) {
      appLogger.info('DownloadManager already initialized (hot restart)');
    } else {
      appLogger.fatal('Failed to initialize DownloadManager', e, stackTrace);
      rethrow;
    }
  }
}

Future<void> _initializeDesktopIntegrations(
  StartupProfiler startupProfiler,
) async {
  if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
    return;
  }

  await Future.wait([KeyboardService.initialize(), TrayService().initialize()]);
  startupProfiler.mark('desktop_integrations_ready');
}

Future<void> _runPostFrameStartupWork(StartupProfiler startupProfiler) async {
  await _preWarmMediaKit();
  startupProfiler.mark('media_kit_prewarm_ready');
  startupProfiler.logSummary(label: 'post_frame');

  unawaited(_initializeDesktopIntegrations(startupProfiler));
  unawaited(_requestNotificationPermission(startupProfiler));
  unawaited(_uploadPendingRustPanics());
}

Future<void> _requestNotificationPermission(
  StartupProfiler startupProfiler,
) async {
  if (!Platform.isMacOS) return;

  try {
    await notificationService.requestPermission();
  } finally {
    startupProfiler.mark('notification_permission_ready');
  }
}

/// Pre-warm MediaKit by creating a dummy player
/// This forces native library loading during startup, reducing first-video delay
/// MUST be awaited to ensure native libs are fully loaded before first video playback
Future<void> _preWarmMediaKit() async {
  try {
    appLogger.debug('Pre-warming MediaKit (blocking)...');
    final dummyPlayer = Player();
    // Small delay to ensure native initialization completes
    await Future.delayed(const Duration(milliseconds: 50));
    await dummyPlayer.dispose();
    appLogger.info('MediaKit pre-warmed successfully');
  } catch (e) {
    // Non-critical error, just log it (app can still work, first video may be slower)
    appLogger.warning('MediaKit pre-warm failed (non-critical): $e');
  }
}

/// Handle deep-link URI passed as command-line argument (Windows/Linux).
/// macOS uses native AppDelegate URL handling instead.
void _handleLaunchUri(List<String> args, ProviderContainer container) {
  if (Platform.isMacOS || args.isEmpty) return;
  final scheme = BrandConfig.current.urlScheme;
  final uri = args.firstWhere(
    (a) => a.startsWith('$scheme://'),
    orElse: () => '',
  );
  if (uri.isEmpty) return;
  appLogger.info('Launch URI detected for $scheme scheme');
  // Delay to ensure LicenseActivationHandler is initialized by StartupService
  unawaited(
    Future<void>.delayed(const Duration(seconds: 1), () async {
      try {
        final handler = container.read(licenseActivationHandlerProvider);
        await handler.handleUri(Uri.tryParse(uri));
      } catch (e) {
        appLogger.warning('Failed to handle launch URI: $e');
      }
    }),
  );
}

/// Provider observer for logging state changes in debug mode
class _AppProviderObserver extends ProviderObserver {
  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    // Only log important providers to reduce verbosity
    if (kDebugMode && _shouldLogProvider(provider)) {
      appLogger.trace(
        'Provider ${provider.name ?? provider.runtimeType} updated: $previousValue -> $newValue',
      );
    }
  }

  /// Check if provider should be logged (filter out noisy providers)
  bool _shouldLogProvider(ProviderBase<Object?> provider) {
    final providerType = provider.runtimeType.toString();

    // Skip noisy providers like filtered lists
    if (providerType.contains('filteredDownloadsProvider')) return false;
    if (providerType.contains('navigationProvider')) return false;

    // Log important state changes
    return providerType.contains('DownloadsNotifier') ||
        providerType.contains('SettingsNotifier') ||
        providerType.contains('FilterNotifier');
  }

  @override
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    appLogger.error(
      'Provider ${provider.name ?? provider.runtimeType} failed',
      error,
      stackTrace,
    );
  }
}

/// Resolve the absolute path where Rust writes panic JSON files.
///
/// Layout: `<applicationSupportDirectory>/<brand>/rust_panics/`. Brand is
/// `BrandConfig.current.brand.name` so SSvid lands at `.../ssvid/rust_panics`
/// and VidCombo at `.../vidcombo/rust_panics`.
///
/// **Windows double-nest guard.** `path_provider_windows` returns a path
/// shaped like `<RoamingAppData>\<CompanyName>\<ProductName>` where
/// ProductName is set from the app's product info (often the brand name).
/// Naïvely appending `<brand>` again would yield `.../ssvid/ssvid/rust_panics`.
/// Detect via case-insensitive basename comparison and skip the second
/// brand segment in that case.
///
/// Centralized here so the StartupService scanner reads the same path.
/// Anything that writes one and reads via the other would be a privacy /
/// data-loss bug.
Future<String> _resolveRustPanicDir() async {
  final support = await getApplicationSupportDirectory();
  final brand = BrandConfig.current.brand.name;
  final basename = p_lib.basename(support.path).toLowerCase();
  final dir =
      (basename == brand.toLowerCase())
          ? p_lib.join(support.path, 'rust_panics')
          : p_lib.join(support.path, brand, 'rust_panics');
  await Directory(dir).create(recursive: true);
  return dir;
}

/// Upload any panic JSON files left over from prior runs.
///
/// Runs in the deferred-startup phase (after first frame, non-critical).
/// For each `*.json` file in the brand-resolved panic directory, parses
/// the structured payload and uploads it as a Sentry message with
/// `runtime: rust` + `recovered_from_disk: true` tags. Deletes the file
/// on successful upload.
///
/// Per plan D4 (degraded mode): we use [Sentry.captureMessage] with the
/// full JSON in the message body rather than reconstructing a proper
/// `SentryEvent` with parsed Rust stack frames. This loses symbolicated
/// grouping but keeps the implementation small and robust against
/// Rust-backtrace format changes across builds. If the resulting Sentry
/// dashboard UX proves unworkable, the upgrade path is to parse the
/// `backtrace` field into `SentryStackFrame[]` here and call
/// [Sentry.captureEvent] instead — the file format already includes the
/// raw backtrace text.
Future<void> _uploadPendingRustPanics() async {
  if (!EnvConfig.isSentryConfigured) return;
  try {
    final dirPath = await _resolveRustPanicDir();
    final dir = Directory(dirPath);
    if (!await dir.exists()) return;

    final entries = await dir.list().toList();
    var uploaded = 0;
    for (final entry in entries) {
      if (entry is! File) continue;
      if (!entry.path.endsWith('.json')) continue;
      try {
        final raw = await entry.readAsString();
        final payload = jsonDecode(raw) as Map<String, dynamic>;
        // Compose a readable message body — Sentry dashboard will show
        // this verbatim. Brief header + full JSON for debug.
        final message = payload['message']?.toString() ?? '<no message>';
        final body = 'Rust panic recovered from disk\n\n$message\n\n$raw';
        await Sentry.captureMessage(
          body,
          level: SentryLevel.fatal,
          withScope: (scope) {
            scope.setTag('runtime', 'rust');
            scope.setTag('recovered_from_disk', 'true');
            final loc = payload['location'];
            if (loc is Map) {
              final file = loc['file']?.toString();
              final line = loc['line']?.toString();
              // ignore: deprecated_member_use
              if (file != null) scope.setExtra('panic.file', file);
              // ignore: deprecated_member_use
              if (line != null) scope.setExtra('panic.line', line);
            }
            final thread = payload['thread']?.toString();
            if (thread != null) scope.setTag('panic.thread', thread);
          },
        );
        await entry.delete();
        uploaded++;
      } catch (e) {
        // One bad file shouldn't stop the rest. Log and move on; the file
        // remains on disk for the next launch to retry.
        appLogger.warning(
          'Failed to upload Rust panic file ${p_lib.basename(entry.path)}: $e',
        );
      }
    }
    if (uploaded > 0) {
      appLogger.info('Uploaded $uploaded pending Rust panic file(s)');
    }
  } catch (e) {
    appLogger.warning('Rust panic scanner failed (non-critical): $e');
  }
}
