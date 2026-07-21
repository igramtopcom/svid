import 'dart:async';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/platform_detector.dart';
import '../../domain/entities/capture_download_request.dart';
import '../../domain/services/capture_service.dart';
import '../../domain/services/url_pattern_service.dart';

/// Routes [CaptureSideEffect]s emitted by [CaptureService] to host-app
/// callbacks. Each callback is optional — when null, the router logs at
/// info level so production sees a clear "wiring not yet provided"
/// breadcrumb instead of silent loss.
///
/// Usage at the host (Riverpod Provider):
/// ```dart
/// final router = CaptureSideEffectRouter(
///   onDownload: (req) async => downloadManager.start(req.preview),
///   onOpenExternal: (url) async => launchUrl(Uri.parse(url)),
///   onOpenMainApp: () async => windowManager.show(),
///   onOpenSettings: () async => router.go('/settings/capture'),
/// );
/// captureService.sideEffects.listen(router.handle);
/// ```
///
/// All callbacks are async + return Future&lt;void&gt; so they can chain
/// I/O (open URL, focus window, etc.) without callers needing to await
/// the dispatch itself. Callback errors are logged but never propagate
/// — one failing handler doesn't poison the stream.
class CaptureSideEffectRouter {
  final Future<void> Function(CaptureDownloadRequest request)? onDownload;
  final Future<void> Function(String url)? onOpenExternal;
  final Future<void> Function(String url)? onOpenInApp;
  final Future<void> Function()? onOpenMainApp;
  final Future<void> Function()? onOpenSettings;

  /// v2.2 Phase 2C — Show "snooze active" toast/system notification when
  /// user picks "Until I resume" so they don't lose track of capture being
  /// paused.
  final Future<void> Function()? onShowSnoozeToast;

  /// v2.2 Phase 2D.1 (CPO feedback): popup Completed-banner CTAs.
  /// `onOpenSavedFolder` reveals the file in Finder/Explorer;
  /// `onPlaySavedFile` opens it in the main app's in-app player.
  final Future<void> Function(String path)? onOpenSavedFolder;
  final Future<void> Function(String path)? onPlaySavedFile;

  /// Phase 2D.2 (anh Quân Windows feedback): main-side breadcrumb when
  /// a clipboard URL was dropped by Layer 1 (RecentUrlTracker) or
  /// Layer 4 (postActionBlocklist) — popup did NOT spawn. Host wires
  /// this to a system notification or in-app toast so the user knows
  /// the URL was recognized but skipped. Throttled at the service.
  final Future<void> Function(String url)? onNotifyDeduplicated;

  /// v2.2 IPC URL allowlist (Codex P2 audit fix). Re-classifies URLs from
  /// the popup process before routing to `url_launcher` — prevents popup
  /// bypassing main-side validation. Defaults to `const UrlPatternService()`.
  final UrlPatternService _urlPattern;

  const CaptureSideEffectRouter({
    this.onDownload,
    this.onOpenExternal,
    this.onOpenInApp,
    this.onOpenMainApp,
    this.onOpenSettings,
    this.onShowSnoozeToast,
    this.onOpenSavedFolder,
    this.onPlaySavedFile,
    this.onNotifyDeduplicated,
    UrlPatternService urlPattern = const UrlPatternService(),
  }) : _urlPattern = urlPattern;

  /// Dispatch a single side effect. Safe to use as a Stream listener
  /// directly: `captureService.sideEffects.listen(router.handle)`.
  Future<void> handle(CaptureSideEffect effect) async {
    try {
      switch (effect) {
        case StartDownloadRequested(:final request):
          await _invoke(
            'StartDownloadRequested',
            onDownload,
            (cb) => cb(request),
            details: request.preview.rawUrl,
          );

        case OpenExternalUrl(:final url):
          if (!_isSafeUrl(url)) {
            appLogger.warning(
              '[CaptureRouter] OpenExternalUrl blocked (not http/https or '
              'unknown platform): $url',
            );
            return;
          }
          await _invoke(
            'OpenExternalUrl',
            onOpenExternal,
            (cb) => cb(url),
            details: url,
          );

        case OpenInAppUrl(:final url):
          if (!_isSafeUrl(url)) {
            appLogger.warning('[CaptureRouter] OpenInAppUrl blocked: $url');
            return;
          }
          await _invoke(
            'OpenInAppUrl',
            onOpenInApp,
            (cb) => cb(url),
            details: url,
          );

        case OpenMainAppWindow():
          await _invoke('OpenMainAppWindow', onOpenMainApp, (cb) => cb());

        case OpenCaptureSettings():
          await _invoke('OpenCaptureSettings', onOpenSettings, (cb) => cb());

        case ShowSnoozeToast():
          await _invoke('ShowSnoozeToast', onShowSnoozeToast, (cb) => cb());

        case OpenSavedFolder(:final path):
          // Path comes from main-side DownloadEntity.savePath/filename so
          // it's trusted, but defensive belt-and-suspenders rejects empty
          // — same posture as IPC URL allowlist (reviewer-2 P2).
          if (path.isEmpty) {
            appLogger.warning('[CaptureRouter] OpenSavedFolder empty path');
            return;
          }
          await _invoke(
            'OpenSavedFolder',
            onOpenSavedFolder,
            (cb) => cb(path),
            details: path,
          );

        case PlaySavedFile(:final path):
          if (path.isEmpty) {
            appLogger.warning('[CaptureRouter] PlaySavedFile empty path');
            return;
          }
          await _invoke(
            'PlaySavedFile',
            onPlaySavedFile,
            (cb) => cb(path),
            details: path,
          );

        case NotifyUrlDeduplicated(:final url):
          // Defensive: ignore empty (shouldn't reach here from service).
          if (url.isEmpty) return;
          await _invoke(
            'NotifyUrlDeduplicated',
            onNotifyDeduplicated,
            (cb) => cb(url),
            details: url,
          );
      }
    } catch (e, s) {
      // Defense-in-depth — _invoke already catches per-callback errors,
      // so reaching this branch means something pathological (e.g. an
      // assertion in pattern matching). Log and swallow so the stream
      // listener stays subscribed.
      appLogger.error('[CaptureRouter] dispatch failed', e, s);
    }
  }

  /// Re-validates a URL string from popup IPC before launching it.
  ///
  /// Allows only http/https schemes and rejects URLs whose platform
  /// classification is `unknown` (defense-in-depth: popup might be
  /// compromised or send malformed data — main side never trusts a
  /// raw string blindly).
  bool _isSafeUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'http' && uri.scheme != 'https') return false;
      if (uri.host.isEmpty) return false;
      final classification = _urlPattern.classify(url);
      // Reject unclassifiable URLs — every supported platform is in the
      // VideoPlatform enum.
      if (classification.platform == VideoPlatform.unknown) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _invoke<C>(
    String name,
    C? callback,
    Future<void> Function(C) call, {
    String? details,
  }) async {
    if (callback == null) {
      appLogger.info(
        '[CaptureRouter] $name → no handler wired'
        '${details != null ? " ($details)" : ""}',
      );
      return;
    }
    try {
      await call(callback);
    } catch (e, s) {
      appLogger.error('[CaptureRouter] $name handler threw', e, s);
    }
  }
}
