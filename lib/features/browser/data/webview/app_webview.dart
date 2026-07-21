import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as iaw;
import 'package:webview_flutter/webview_flutter.dart' as wf;

import '../../../../core/logging/app_logger.dart';
import '../../../../core/services/webview_environment_service.dart';

/// Sentry-bound breadcrumb sink. Wired from main.dart through DI so this
/// module stays free of Sentry imports (and easy to fake in tests).
typedef WebViewBreadcrumbSink =
    void Function(String message, Map<String, dynamic> data);

WebViewBreadcrumbSink _breadcrumbSink = (_, __) {};

/// Register the global sink that receives WebView lifecycle events as
/// breadcrumbs. Idempotent — last write wins.
void setWebViewBreadcrumbSink(WebViewBreadcrumbSink sink) {
  _breadcrumbSink = sink;
}

/// 30 seconds without `onLoadStop` after `onLoadStart` is treated as a hang.
/// Picked to outlast slow real-world loads (TikTok cold start ≈ 12s) but
/// still catch the Facebook "tiny Meta logo, then nothing" failure mode.
const Duration _hangThreshold = Duration(seconds: 30);

void _emit(String event, Map<String, dynamic> data) {
  appLogger.info('webview.$event ${data.isEmpty ? '' : data}');
  _breadcrumbSink('webview.$event', data);
}

/// Trim long URLs to keep breadcrumbs readable in Sentry.
String _shortUrl(String url) =>
    url.length <= 200 ? url : '${url.substring(0, 200)}…';

/// Platform-agnostic navigation callbacks for WebView events.
class WebViewNavigationCallbacks {
  final void Function(String url)? onPageStarted;
  final void Function(int progress)? onProgress;
  final void Function(String url)? onPageFinished;
  final void Function(String description, {bool isUnknown})? onError;

  /// Return true to allow navigation, false to block.
  final bool Function(String url, bool isMainFrame)? onNavigationRequest;

  const WebViewNavigationCallbacks({
    this.onPageStarted,
    this.onProgress,
    this.onPageFinished,
    this.onError,
    this.onNavigationRequest,
  });
}

/// Platform-agnostic WebView controller.
///
/// macOS/Linux: wraps `webview_flutter` [WebViewController].
/// Windows: wraps `flutter_inappwebview` [InAppWebViewController] (WebView2).
abstract class AppWebViewController {
  /// Create a platform-appropriate WebView controller.
  factory AppWebViewController({
    required String initialUrl,
    required String userAgent,
    WebViewNavigationCallbacks callbacks = const WebViewNavigationCallbacks(),
  }) {
    if (Platform.isWindows) {
      return _WindowsWebViewController(
        initialUrl: initialUrl,
        userAgent: userAgent,
        callbacks: callbacks,
      );
    }
    return _MacOSWebViewController(
      initialUrl: initialUrl,
      userAgent: userAgent,
      callbacks: callbacks,
    );
  }

  Future<void> loadUrl(String url);
  Future<void> reload();
  Future<void> goBack();
  Future<void> goForward();
  Future<bool> canGoBack();
  Future<bool> canGoForward();
  Future<String?> getTitle();
  Future<String?> currentUrl();
  Future<void> runJavaScript(String script);
  Future<Object> runJavaScriptReturningResult(String script);
  Future<void> clearLocalStorage();

  /// Register a JS→Dart message channel.
  /// JS sends via `window.webkit.messageHandlers.<name>.postMessage(...)` (macOS)
  /// or `window.flutter_inappwebview.callHandler("<name>", ...)` (Windows).
  void addJavaScriptChannel(
    String name,
    void Function(dynamic message) handler,
  );

  /// Remove a previously registered JS message channel.
  void removeJavaScriptChannel(String name);

  /// Extract cookies for a given URL from the WebView's cookie store.
  Future<String> getCookies(String url);

  /// Build the platform-appropriate WebView widget.
  Widget buildWidget({Key? key});
}

// ── macOS / Linux implementation (webview_flutter) ──────────────────────────

class _MacOSWebViewController implements AppWebViewController {
  late final wf.WebViewController _controller;
  final Set<String> _registeredChannels = {};

  _MacOSWebViewController({
    required String initialUrl,
    required String userAgent,
    WebViewNavigationCallbacks callbacks = const WebViewNavigationCallbacks(),
  }) {
    _controller = wf.WebViewController();
    // setJavaScriptMode requires macOS 11.0+. On older macOS the
    // webview_flutter_wkwebview plugin throws
    // `PlatformException(FWFUnsupportedVersionError, WKWebpagePreferences
    // .allowsContentJavaScript requires iOS 14.0, macOS 11.0., null, null)`
    // — 22 production crashes in audit. Older WKWebView allows JS by
    // default via the deprecated `WKPreferences.javaScriptEnabled`
    // property, so silently swallowing this call still gives the user
    // a working browser tab.
    unawaited(
      _controller.setJavaScriptMode(wf.JavaScriptMode.unrestricted).catchError((
        Object e,
        StackTrace _,
      ) {
        appLogger.debug(
          'webview setJavaScriptMode unsupported (macOS < 11.0?): $e',
        );
      }),
    );
    _controller
      ..setUserAgent(userAgent)
      ..setNavigationDelegate(
        wf.NavigationDelegate(
          onPageStarted: (url) {
            _onLoadStart(url);
            callbacks.onPageStarted?.call(url);
          },
          onProgress: (progress) => callbacks.onProgress?.call(progress),
          onPageFinished: (url) {
            _onLoadStop(url);
            callbacks.onPageFinished?.call(url);
          },
          onWebResourceError: (error) {
            _onLoadError(
              error.description,
              isMainFrame: error.isForMainFrame ?? false,
            );
            callbacks.onError?.call(
              error.description,
              isUnknown: error.errorType == wf.WebResourceErrorType.unknown,
            );
          },
          onNavigationRequest: (request) {
            final allow =
                callbacks.onNavigationRequest?.call(
                  request.url,
                  request.isMainFrame,
                ) ??
                true;
            return allow
                ? wf.NavigationDecision.navigate
                : wf.NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(initialUrl));
  }

  Timer? _hangTimer;
  String? _pendingUrl;

  void _onLoadStart(String url) {
    _hangTimer?.cancel();
    _pendingUrl = url;
    _emit('load_started', {'url': _shortUrl(url)});
    _hangTimer = Timer(_hangThreshold, () {
      final stuck = _pendingUrl;
      if (stuck == null) return;
      _emit('load_hang', {
        'url': _shortUrl(stuck),
        'threshold_s': _hangThreshold.inSeconds,
      });
      appLogger.warning(
        'WebView hang detected on $stuck (no load_stop after ${_hangThreshold.inSeconds}s)',
      );
    });
  }

  void _onLoadStop(String url) {
    _hangTimer?.cancel();
    _pendingUrl = null;
    _emit('load_finished', {'url': _shortUrl(url)});
  }

  void _onLoadError(String description, {required bool isMainFrame}) {
    _hangTimer?.cancel();
    _pendingUrl = null;
    _emit('load_failed', {
      'description': description,
      'main_frame': isMainFrame,
    });
  }

  @override
  Future<void> loadUrl(String url) => _controller.loadRequest(Uri.parse(url));

  @override
  Future<void> reload() => _controller.reload();

  @override
  Future<void> goBack() => _controller.goBack();

  @override
  Future<void> goForward() => _controller.goForward();

  @override
  Future<bool> canGoBack() => _controller.canGoBack();

  @override
  Future<bool> canGoForward() => _controller.canGoForward();

  @override
  Future<String?> getTitle() => _controller.getTitle();

  @override
  Future<String?> currentUrl() => _controller.currentUrl();

  @override
  Future<void> runJavaScript(String script) =>
      _controller.runJavaScript(script);

  @override
  Future<Object> runJavaScriptReturningResult(String script) =>
      _controller.runJavaScriptReturningResult(script);

  @override
  Future<void> clearLocalStorage() => _controller.clearLocalStorage();

  @override
  void addJavaScriptChannel(
    String name,
    void Function(dynamic message) handler,
  ) {
    if (_registeredChannels.contains(name)) return;
    _registeredChannels.add(name);
    _controller.addJavaScriptChannel(
      name,
      onMessageReceived: (wf.JavaScriptMessage msg) {
        handler(msg.message);
      },
    );
  }

  @override
  void removeJavaScriptChannel(String name) {
    if (!_registeredChannels.contains(name)) return;
    _registeredChannels.remove(name);
    _controller.removeJavaScriptChannel(name);
  }

  @override
  Future<String> getCookies(String url) async {
    // webview_flutter doesn't expose getCookies — extract via JS document.cookie
    try {
      final result = await _controller.runJavaScriptReturningResult(
        'document.cookie',
      );
      // Result may be quoted string — strip quotes
      var cookies = result.toString();
      if (cookies.startsWith('"') && cookies.endsWith('"')) {
        cookies = cookies.substring(1, cookies.length - 1);
      }
      return cookies;
    } catch (_) {
      return '';
    }
  }

  @override
  Widget buildWidget({Key? key}) =>
      wf.WebViewWidget(key: key, controller: _controller);
}

// ── Windows implementation (flutter_inappwebview / WebView2) ────────────────

class _WindowsWebViewController implements AppWebViewController {
  String _lastUrl;
  final String _userAgent;
  final WebViewNavigationCallbacks _callbacks;
  iaw.InAppWebViewController? _controller;
  final Map<String, void Function(dynamic)> _pendingHandlers = {};

  _WindowsWebViewController({
    required String initialUrl,
    required String userAgent,
    WebViewNavigationCallbacks callbacks = const WebViewNavigationCallbacks(),
  }) : _lastUrl = initialUrl,
       _userAgent = userAgent,
       _callbacks = callbacks;

  @override
  Future<void> loadUrl(String url) async {
    _lastUrl = url;
    await _controller?.loadUrl(
      urlRequest: iaw.URLRequest(url: iaw.WebUri(url)),
    );
  }

  @override
  Future<void> reload() async => _controller?.reload();

  @override
  Future<void> goBack() async => _controller?.goBack();

  @override
  Future<void> goForward() async => _controller?.goForward();

  @override
  Future<bool> canGoBack() async => await _controller?.canGoBack() ?? false;

  @override
  Future<bool> canGoForward() async =>
      await _controller?.canGoForward() ?? false;

  @override
  Future<String?> getTitle() async => _controller?.getTitle();

  @override
  Future<String?> currentUrl() async {
    final url = await _controller?.getUrl();
    return url?.toString();
  }

  @override
  Future<void> runJavaScript(String script) async {
    await _controller?.evaluateJavascript(source: script);
  }

  @override
  Future<Object> runJavaScriptReturningResult(String script) async {
    final result = await _controller?.evaluateJavascript(source: script);
    return result ?? '';
  }

  @override
  Future<void> clearLocalStorage() async {
    try {
      await _controller?.evaluateJavascript(
        source: 'window.localStorage.clear();',
      );
    } catch (_) {}
  }

  @override
  void addJavaScriptChannel(
    String name,
    void Function(dynamic message) handler,
  ) {
    // If controller is already available, register immediately
    final ctrl = _controller;
    if (ctrl != null) {
      ctrl.addJavaScriptHandler(
        handlerName: name,
        callback: (args) {
          handler(args.isNotEmpty ? args.first : null);
          return null;
        },
      );
    } else {
      // Queue for registration when controller becomes available
      _pendingHandlers[name] = handler;
    }
  }

  @override
  void removeJavaScriptChannel(String name) {
    _pendingHandlers.remove(name);
    _controller?.removeJavaScriptHandler(handlerName: name);
  }

  @override
  Future<String> getCookies(String url) async {
    try {
      final cookieManager = iaw.CookieManager.instance(
        webViewEnvironment: WebViewEnvironmentService.instance,
      );
      final cookies = await cookieManager.getCookies(url: iaw.WebUri(url));
      return cookies.map((c) => '${c.name}=${c.value}').join('; ');
    } catch (_) {
      return '';
    }
  }

  void _registerPendingHandlers() {
    final ctrl = _controller;
    if (ctrl == null) return;
    for (final entry in _pendingHandlers.entries) {
      ctrl.addJavaScriptHandler(
        handlerName: entry.key,
        callback: (args) {
          entry.value(args.isNotEmpty ? args.first : null);
          return null;
        },
      );
    }
    _pendingHandlers.clear();
  }

  Timer? _hangTimer;
  String? _pendingUrl;

  void _onLoadStart(String url) {
    _hangTimer?.cancel();
    _pendingUrl = url;
    _emit('load_started', {'url': _shortUrl(url)});
    _hangTimer = Timer(_hangThreshold, () {
      final stuck = _pendingUrl;
      if (stuck == null) return;
      _emit('load_hang', {
        'url': _shortUrl(stuck),
        'threshold_s': _hangThreshold.inSeconds,
      });
      appLogger.warning(
        'WebView hang detected on $stuck (no load_stop after ${_hangThreshold.inSeconds}s)',
      );
    });
  }

  void _onLoadStop(String url) {
    _hangTimer?.cancel();
    _pendingUrl = null;
    _emit('load_finished', {'url': _shortUrl(url)});
  }

  void _onLoadError(String description, {required bool isMainFrame}) {
    _hangTimer?.cancel();
    _pendingUrl = null;
    _emit('load_failed', {
      'description': description,
      'main_frame': isMainFrame,
    });
  }

  @override
  Widget buildWidget({Key? key}) {
    // Wrap in a watchdog layer for slow WebView2 creation. The wrapper keeps
    // the native view mounted while pending: disposing flutter_inappwebview's
    // Windows CustomPlatformView before createInAppWebView completes lets the
    // plugin call setState/localToGlobal on a dead render tree.
    return _RobustInAppWebViewBuilder(key: key, controller: this);
  }

  /// Build the raw `InAppWebView` instance. Called by
  /// [_RobustInAppWebViewBuilder]; do NOT call directly from outside the
  /// wrapper or you bypass the watchdog/retry path.
  ///
  /// [onCreatedOverride] gates whether the controller install proceeds.
  /// It normally returns true even after the watchdog fired because the raw
  /// WebView remains mounted behind the recovery overlay.
  Widget _buildRawInAppWebView({
    required Key viewKey,
    required bool Function() onCreatedOverride,
  }) {
    return iaw.InAppWebView(
      key: viewKey,
      // Persistent per-brand WebView2 user-data folder. Without this WebView2
      // falls back to a folder next to the .exe (or temp), wiping cookies +
      // service workers on every install/update — which is what causes the
      // Facebook tab to hang on the Meta logo (service worker can't register).
      webViewEnvironment: WebViewEnvironmentService.instance,
      initialUrlRequest: iaw.URLRequest(url: iaw.WebUri(_lastUrl)),
      initialSettings: iaw.InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: _userAgent,
        useShouldOverrideUrlLoading: _callbacks.onNavigationRequest != null,
        supportMultipleWindows: true,
        javaScriptCanOpenWindowsAutomatically: true,
      ),
      onWebViewCreated: (controller) {
        if (!onCreatedOverride()) {
          // The wrapper was disposed before creation completed. Refuse to
          // install the controller into a dead owner.
          return;
        }
        _controller = controller;
        _registerPendingHandlers();
      },
      onLoadStart: (controller, url) {
        final urlStr = url?.toString() ?? '';
        _onLoadStart(urlStr);
        _callbacks.onPageStarted?.call(urlStr);
      },
      onProgressChanged: (controller, progress) {
        _callbacks.onProgress?.call(progress);
      },
      onLoadStop: (controller, url) {
        final urlStr = url?.toString() ?? '';
        // Track last URL so remounting (tab switch) navigates to the same page
        if (urlStr.isNotEmpty && urlStr != 'about:blank') {
          _lastUrl = urlStr;
        }
        _onLoadStop(urlStr);
        _callbacks.onPageFinished?.call(urlStr);
      },
      onReceivedError: (controller, request, error) {
        _onLoadError(
          error.description,
          isMainFrame: request.isForMainFrame ?? false,
        );
        _callbacks.onError?.call(error.description, isUnknown: false);
      },
      shouldOverrideUrlLoading:
          _callbacks.onNavigationRequest != null
              ? (controller, action) async {
                final url = action.request.url?.toString() ?? '';
                final isMainFrame = action.isForMainFrame;
                final allow = _callbacks.onNavigationRequest!(url, isMainFrame);
                return allow
                    ? iaw.NavigationActionPolicy.ALLOW
                    : iaw.NavigationActionPolicy.CANCEL;
              }
              : null,
      // Handle window.open() — prevents WebView2 crash when sites like
      // Facebook/TikTok open new windows for login, OAuth, or popups.
      // Loads the target URL in the current webview instead of crashing.
      onCreateWindow: (controller, createWindowAction) async {
        final url = createWindowAction.request.url;
        if (url != null && url.toString().isNotEmpty) {
          _emit('window_open_redirect', {'url': _shortUrl(url.toString())});
        }
        // Returning false lets flutter_inappwebview_windows run its default
        // behavior: load the requested URL in this WebView and complete the
        // WebView2 new-window deferral. Calling loadUrl here would navigate
        // twice on Windows.
        return false;
      },
    );
  }
}

/// Watchdog timeout for the WebView2 native view to call back into Flutter
/// via `onWebViewCreated`. Picked to outlast slow cold-start install paths
/// (clean Windows install + Edge first-run can take 6–7s) without leaving
/// the user staring at a blank page indefinitely.
const Duration _kWebViewCreationWatchdog = Duration(seconds: 10);

/// Stateful wrapper around [iaw.InAppWebView] that surfaces a recovery overlay
/// when native view creation appears slow. Provides observability via
/// the [_breadcrumbSink] for backend ops to correlate webview creation
/// success / failure rates with production crash telemetry.
///
/// Important: do not replace the raw WebView while creation is pending. The
/// Windows plugin completes creation asynchronously and is not dispose-safe
/// during that window; unmounting it before completion caused late plugin
/// callbacks to crash inside CustomPlatformView.
class _RobustInAppWebViewBuilder extends StatefulWidget {
  final _WindowsWebViewController controller;

  const _RobustInAppWebViewBuilder({super.key, required this.controller});

  @override
  State<_RobustInAppWebViewBuilder> createState() =>
      _RobustInAppWebViewBuilderState();
}

class _RobustInAppWebViewBuilderState
    extends State<_RobustInAppWebViewBuilder> {
  Timer? _watchdog;
  bool _created = false;
  bool _watchdogFired = false;

  @override
  void initState() {
    super.initState();
    _armWatchdog();
    _emit('creation_attempt', const {'attempt': 0});
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(_kWebViewCreationWatchdog, () {
      if (!_created && mounted) {
        _emit('creation_watchdog_fired', {
          'attempt': 0,
          'timeout_seconds': _kWebViewCreationWatchdog.inSeconds,
        });
        setState(() {
          _watchdogFired = true;
        });
      }
    });
  }

  /// Returns `true` when the caller may proceed to install the
  /// `InAppWebViewController` and register pending handlers.
  bool _handleCreated() {
    if (!mounted) return false;
    _created = true;
    _watchdog?.cancel();
    if (_watchdogFired) {
      _emit('creation_succeeded_after_watchdog', const {'attempt': 0});
      setState(() {
        _watchdogFired = false;
      });
    } else {
      _emit('creation_succeeded', const {'attempt': 0});
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final webView = widget.controller._buildRawInAppWebView(
      viewKey: const ValueKey('iaw'),
      onCreatedOverride: _handleCreated,
    );
    // Keep the raw InAppWebView mounted at a STABLE tree position (always child
    // 0 of this Stack) so toggling _watchdogFired never changes its parent
    // widget type. The previous form (`return webView` when !fired, else
    // `Stack([webView, ui])`) changed this State's root child type
    // InAppWebView -> Stack, which makes Flutter unmount + recreate the native
    // CustomPlatformView — the exact disposed view that the late WebView2
    // onCreated callback then crashes on. A ValueKey cannot reparent across a
    // type change; only a stable parent preserves element identity. The
    // recovery overlay is layered on top as a sibling, never by swapping root.
    return Stack(
      fit: StackFit.expand,
      children: [
        webView,
        if (_watchdogFired) const _WebViewRecoveryUi(),
      ],
    );
  }
}

/// Recovery surface shown when the WebView native view is slow to register
/// within [_kWebViewCreationWatchdog]. Intentionally minimal so the same
/// widget is usable inside a constrained slot (login dialog, browser tab,
/// floating capture) without layout breakage.
class _WebViewRecoveryUi extends StatelessWidget {
  const _WebViewRecoveryUi();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.web_asset_off, size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              'Browser engine could not start',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'The embedded WebView is still starting. If this persists, '
              'restart the app.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}
