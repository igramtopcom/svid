import 'dart:io' show Platform;

import 'package:flutter_inappwebview/flutter_inappwebview.dart' as iaw;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/brand_config.dart';
import '../logging/app_logger.dart';

/// Singleton holder for the Windows WebView2 [iaw.WebViewEnvironment].
///
/// Without an explicit `userDataFolder`, WebView2 falls back to a directory
/// next to the executable (or a temp dir) — which means cookies, IndexedDB and
/// service workers are wiped on every install/update. Facebook in particular
/// will load partially then hang because its service worker can't register
/// against ephemeral storage.
///
/// We resolve a per-brand folder under `getApplicationSupportDirectory()` so
/// Svid and VidCombo never share state, and persistence survives app
/// restarts and updates.
///
/// On macOS/Linux this is a no-op — `webview_flutter` (WKWebView) already
/// uses `WKWebsiteDataStore.default()` which is persistent by default.
class WebViewEnvironmentService {
  static iaw.WebViewEnvironment? _instance;
  static String? _resolvedPath;

  /// The shared environment (Windows only). Null on other platforms or before
  /// [init] completes.
  static iaw.WebViewEnvironment? get instance => _instance;

  /// Absolute path of the resolved user-data folder, for diagnostics.
  static String? get resolvedPath => _resolvedPath;

  /// Initialize once, before any [iaw.InAppWebView] is built.
  /// Safe to call from main(); failures are logged and the app continues
  /// (WebView2 falls back to its default — same behaviour as before).
  static Future<void> init() async {
    if (!Platform.isWindows) return;
    if (_instance != null) return;

    try {
      final support = await getApplicationSupportDirectory();
      final folder = p.join(
        support.path,
        'webview_data',
        BrandConfig.current.brand.name,
      );
      _resolvedPath = folder;

      _instance = await iaw.WebViewEnvironment.create(
        settings: iaw.WebViewEnvironmentSettings(userDataFolder: folder),
      );
      appLogger.info('WebView2 environment ready: $folder');
    } catch (e, st) {
      appLogger.error(
        'WebView2 environment init failed — falling back to default storage',
        e,
        st,
      );
    }
  }
}
