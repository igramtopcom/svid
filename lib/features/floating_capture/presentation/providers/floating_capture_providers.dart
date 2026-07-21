import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/services/window_service.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../player/domain/services/system_pip_service.dart';
import '../../data/datasources/desktop_multi_window_floating_window.dart';
import '../../data/datasources/default_capture_service.dart';
import '../../data/datasources/lightweight_preview_service.dart';
import '../../data/datasources/native_clipboard_source.dart';
import '../../data/datasources/shared_preferences_snooze_store.dart';
import '../../data/services/capture_lifecycle_controller.dart';
import '../../data/services/capture_side_effect_router.dart';
import '../../domain/entities/capture_download_request.dart';
import '../../domain/entities/snooze_state.dart';
import '../../domain/services/capture_quota_policy.dart';
import '../../domain/services/capture_service.dart';
import '../../domain/services/clipboard_monitor_service.dart';
import '../../domain/services/clipboard_source.dart';
import '../../domain/services/floating_window.dart';
import '../../domain/services/snooze_store.dart';
import '../../domain/services/url_pattern_service.dart';

// =============================================================================
// Floating Capture — Provider chain (Phase 1A.6 wiring)
//
// Builds the dependency graph end-to-end so the host app can:
//   ref.read(captureServiceProvider).start();
//   ref.read(captureServiceProvider).sideEffects.listen(
//       ref.read(captureSideEffectRouterProvider).handle);
//
// Heavy classes (CaptureService, FloatingWindow) own native resources, so
// each provider registers a `ref.onDispose` for cleanup. The chain is
// constructed lazily — nothing spawns until something downstream is read.
//
// Auto-start at app boot is intentionally NOT wired here (a separate slice
// will hook into main.dart). This file contains pure dependency wiring so
// the chain can be exercised in isolation by tests / dev tools.
// =============================================================================

/// Pure URL classification — no I/O, safe to keep around indefinitely.
final urlPatternServiceProvider = Provider<UrlPatternService>((ref) {
  return const UrlPatternService();
});

/// Production [ClipboardSource] — uses native platform plugins.
/// Linux is deferred (spec §Q12); falls back to a never-emitting source so
/// downstream code doesn't have to special-case nullability.
final clipboardSourceProvider = Provider<ClipboardSource>((ref) {
  final source = NativeClipboardSource();
  ref.onDispose(() => source.dispose());
  return source;
});

final clipboardMonitorServiceProvider = Provider<ClipboardMonitorService>((
  ref,
) {
  final source = ref.watch(clipboardSourceProvider);
  final urlPattern = ref.watch(urlPatternServiceProvider);
  final monitor = ClipboardMonitorService(
    source: source,
    urlPattern: urlPattern,
  );
  ref.onDispose(() => monitor.dispose());
  return monitor;
});

/// Locale code passed to the popup engine on spawn (Phase 1D).
///
/// Default reads `Platform.localeName` (system-level) and clamps to the
/// supported set. Main app may override this provider with the user's
/// in-app EasyLocalization choice if it diverges from the system locale —
/// floating capture popup will follow the override on subsequent spawns.
///
/// Unsupported / future locale codes fall back to English.
final captureLocaleCodeProvider = Provider<String>((ref) {
  if (kIsWeb) return 'en';
  const supported = {
    'en', 'vi', 'es', 'pt', 'ja', 'ko', 'zh', 'de', 'fr', 'ru',
    'ar', 'hi', 'id', 'th', 'tr',
  };
  final raw = Platform.localeName.split(RegExp(r'[_-]')).first.toLowerCase();
  return supported.contains(raw) ? raw : 'en';
});

final floatingWindowProvider = Provider<FloatingWindow>((ref) {
  final window = DesktopMultiWindowFloatingWindow(
    avoidBoundsProvider: () => SystemPipService.activeBounds,
  )..localeCode = ref.read(captureLocaleCodeProvider);
  ref.onDispose(() => window.dispose());
  return window;
});

final lightweightPreviewServiceProvider = Provider<LightweightPreviewService>((
  ref,
) {
  final urlPattern = ref.watch(urlPatternServiceProvider);
  final service = LightweightPreviewService(urlPattern: urlPattern);
  // Closes the wrapped http.Client when the container disposes — without
  // this, the client + its connection pool stay alive for the app lifetime.
  ref.onDispose(() => service.dispose());
  return service;
});

/// Persistence for snooze state — uses the existing app-wide
/// SharedPreferences instance (NOT a separate file).
final snoozeStoreProvider = Provider<SnoozeStore>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SharedPreferencesSnoozeStore(prefs);
});

/// Quota gating. Defaults to unlimited (premium-equivalent) until the
/// premium feature integrates a real per-day counter. Override this
/// provider in main.dart when wiring billing.
final captureQuotaPolicyProvider = Provider<CaptureQuotaPolicy>((ref) {
  return const UnlimitedCaptureQuotaPolicy();
});

/// Glues all the building blocks together. Lifecycle (start/stop) is the
/// caller's responsibility — auto-start happens in main.dart in a
/// separate slice.
final captureServiceProvider = Provider<CaptureService>((ref) {
  final service = DefaultCaptureService(
    clipboard: ref.watch(clipboardMonitorServiceProvider),
    floatingWindow: ref.watch(floatingWindowProvider),
    fetchPreview: ref.watch(lightweightPreviewServiceProvider).fetchPreview,
    urlPattern: ref.watch(urlPatternServiceProvider),
    snoozeStore: ref.watch(snoozeStoreProvider),
    quotaPolicy: ref.watch(captureQuotaPolicyProvider),
  );
  ref.onDispose(() => service.dispose());
  return service;
});

/// Constructs the default [CaptureSideEffectRouter]. In-feature side
/// effects (browser, window focus) get sensible defaults baked in;
/// cross-feature ones (download / in-app / settings) accept caller
/// overrides so main.dart can wire them to existing systems without
/// re-deriving the in-feature logic.
///
/// Exported as a free function so the host app can call it in a Provider
/// override and add a `onDownload` callback while keeping the in-feature
/// defaults intact:
///
/// ```dart
/// captureSideEffectRouterProvider.overrideWith((ref) =>
///   buildDefaultCaptureSideEffectRouter(
///     onDownload: (req) async => downloadManager.start(req.preview),
///   ),
/// )
/// ```
CaptureSideEffectRouter buildDefaultCaptureSideEffectRouter({
  Future<void> Function(CaptureDownloadRequest request)? onDownload,
  Future<void> Function(String url)? onOpenInApp,
  Future<void> Function()? onOpenSettings,
  Future<void> Function()? onShowSnoozeToast,
  Future<void> Function(String path)? onOpenSavedFolder,
  Future<void> Function(String path)? onPlaySavedFile,
  Future<void> Function(String url)? onNotifyDeduplicated,
}) {
  return CaptureSideEffectRouter(
    onDownload: onDownload,
    onOpenInApp: onOpenInApp,
    onOpenSettings: onOpenSettings,
    onShowSnoozeToast: onShowSnoozeToast,
    onOpenSavedFolder: onOpenSavedFolder,
    onPlaySavedFile: onPlaySavedFile,
    onNotifyDeduplicated: onNotifyDeduplicated,
    onOpenExternal: (url) async {
      final uri = Uri.tryParse(url);
      if (uri == null) {
        appLogger.warning('[Capture] OpenExternalUrl unparseable: $url');
        return;
      }
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          appLogger.warning('[Capture] system cannot launch URL: $url');
        }
      } catch (e, s) {
        appLogger.error('[Capture] launchUrl failed', e, s);
      }
    },
    onOpenMainApp: () async {
      if (kIsWeb) return;
      try {
        await WindowService.show();
      } catch (e, s) {
        appLogger.error('[Capture] WindowService.show failed', e, s);
      }
    },
  );
}

/// Default router. main.dart overrides this with cross-feature callbacks
/// (download, in-app URL, settings nav). Until overridden, those callbacks
/// log a "no handler wired" breadcrumb and the in-feature defaults work.
final captureSideEffectRouterProvider = Provider<CaptureSideEffectRouter>((
  ref,
) {
  return buildDefaultCaptureSideEffectRouter();
});

/// Reactive view of [CaptureService.currentSnooze]. Yields the initial
/// (sync) value followed by every [CaptureService.snoozeChanges]
/// emission. Settings UI watches this so the snooze-status row stays in
/// sync without manual refresh.
final captureSnoozeStreamProvider = StreamProvider<SnoozeState>((ref) async* {
  final service = ref.watch(captureServiceProvider);
  // Seed with current value so the very first build shows the right
  // state instead of a loading indicator until the next snooze event.
  yield service.currentSnooze;
  yield* service.snoozeChanges;
});

/// Owns the runtime [CaptureService] subscription + dispatch loop.
/// Construct lazily; call `.start()` after the host app has booted (e.g.,
/// in `main.dart` Phase E or post-first-frame). `ref.onDispose` ensures
/// the subscription is cancelled before the service tears down on app
/// shutdown.
final captureLifecycleControllerProvider = Provider<CaptureLifecycleController>(
  (ref) {
    final controller = CaptureLifecycleController(
      service: ref.watch(captureServiceProvider),
      router: ref.watch(captureSideEffectRouterProvider),
    );
    ref.onDispose(() => controller.dispose());
    return controller;
  },
);
