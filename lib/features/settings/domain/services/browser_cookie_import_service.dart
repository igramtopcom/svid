import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Supported browser types for cookie import via yt-dlp's --cookies-from-browser.
enum BrowserType {
  chrome('chrome', 'Google Chrome'),
  firefox('firefox', 'Firefox'),
  edge('edge', 'Microsoft Edge'),
  safari('safari', 'Safari'),
  brave('brave', 'Brave'),
  opera('opera', 'Opera'),
  chromium('chromium', 'Chromium'),
  vivaldi('vivaldi', 'Vivaldi');

  const BrowserType(this.ytdlpName, this.displayName);

  /// Name passed to yt-dlp's --cookies-from-browser flag.
  final String ytdlpName;

  /// Human-readable display name for the UI.
  final String displayName;

  /// Parse from stored string (ytdlpName).
  static BrowserType? fromString(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final b in values) {
      if (b.ytdlpName == value) return b;
    }
    return null;
  }
}

/// Service for detecting installed browsers and managing browser cookie import
/// selection for yt-dlp's `--cookies-from-browser` feature.
///
/// Does NOT read cookies directly — delegates to yt-dlp which handles
/// browser cookie store decryption natively.
class BrowserCookieImportService {
  static const _prefsKey = 'cookie_import_browser';

  final SharedPreferences _prefs;

  /// Injectable directory checker for testability.
  final bool Function(String path)? _directoryExists;

  BrowserCookieImportService(
    this._prefs, {
    bool Function(String path)? directoryExists,
  }) : _directoryExists = directoryExists;

  bool _dirExists(String path) {
    if (_directoryExists != null) return _directoryExists(path);
    return Directory(path).existsSync();
  }

  /// Detect browsers installed on this machine.
  List<BrowserType> detectInstalledBrowsers() {
    if (Platform.isMacOS) return _detectMacOS();
    if (Platform.isWindows) return _detectWindows();
    if (Platform.isLinux) return _detectLinux();
    return [];
  }

  List<BrowserType> _detectMacOS() {
    final home = Platform.environment['HOME'] ?? '';
    final results = <BrowserType>[];

    final checks = <BrowserType, List<String>>{
      BrowserType.chrome: [
        '$home/Library/Application Support/Google/Chrome',
      ],
      BrowserType.firefox: [
        '$home/Library/Application Support/Firefox',
      ],
      BrowserType.edge: [
        '$home/Library/Application Support/Microsoft Edge',
      ],
      BrowserType.safari: [
        '$home/Library/Safari',
      ],
      BrowserType.brave: [
        '$home/Library/Application Support/BraveSoftware/Brave-Browser',
      ],
      BrowserType.opera: [
        '$home/Library/Application Support/com.operasoftware.Opera',
      ],
      BrowserType.chromium: [
        '$home/Library/Application Support/Chromium',
      ],
      BrowserType.vivaldi: [
        '$home/Library/Application Support/Vivaldi',
      ],
    };

    for (final entry in checks.entries) {
      if (entry.value.any(_dirExists)) {
        results.add(entry.key);
      }
    }

    return results;
  }

  List<BrowserType> _detectWindows() {
    final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
    final appData = Platform.environment['APPDATA'] ?? '';
    final results = <BrowserType>[];

    final checks = <BrowserType, List<String>>{
      BrowserType.chrome: [
        '$localAppData\\Google\\Chrome\\User Data',
      ],
      BrowserType.firefox: [
        '$appData\\Mozilla\\Firefox\\Profiles',
      ],
      BrowserType.edge: [
        '$localAppData\\Microsoft\\Edge\\User Data',
      ],
      BrowserType.brave: [
        '$localAppData\\BraveSoftware\\Brave-Browser\\User Data',
      ],
      BrowserType.opera: [
        '$appData\\Opera Software\\Opera Stable',
      ],
      BrowserType.chromium: [
        '$localAppData\\Chromium\\User Data',
      ],
      BrowserType.vivaldi: [
        '$localAppData\\Vivaldi\\User Data',
      ],
    };

    for (final entry in checks.entries) {
      if (entry.value.any(_dirExists)) {
        results.add(entry.key);
      }
    }

    return results;
  }

  List<BrowserType> _detectLinux() {
    final home = Platform.environment['HOME'] ?? '';
    final results = <BrowserType>[];

    final checks = <BrowserType, List<String>>{
      BrowserType.chrome: [
        '$home/.config/google-chrome',
      ],
      BrowserType.firefox: [
        '$home/.mozilla/firefox',
      ],
      BrowserType.edge: [
        '$home/.config/microsoft-edge',
      ],
      BrowserType.brave: [
        '$home/.config/BraveSoftware/Brave-Browser',
      ],
      BrowserType.opera: [
        '$home/.config/opera',
      ],
      BrowserType.chromium: [
        '$home/.config/chromium',
      ],
      BrowserType.vivaldi: [
        '$home/.config/vivaldi',
      ],
    };

    for (final entry in checks.entries) {
      if (entry.value.any(_dirExists)) {
        results.add(entry.key);
      }
    }

    return results;
  }

  /// Get currently selected browser for cookie import.
  /// Returns null if no browser is selected (disabled).
  BrowserType? get selectedBrowser {
    final stored = _prefs.getString(_prefsKey);
    return BrowserType.fromString(stored);
  }

  /// Set the browser to use for cookie import.
  /// Pass null to disable browser cookie import.
  Future<void> setSelectedBrowser(BrowserType? browser) async {
    if (browser == null) {
      await _prefs.remove(_prefsKey);
    } else {
      await _prefs.setString(_prefsKey, browser.ytdlpName);
    }
  }

  /// Get the yt-dlp argument value for --cookies-from-browser.
  /// Returns null if no browser is selected.
  String? get cookiesFromBrowserArg {
    return selectedBrowser?.ytdlpName;
  }

  /// Whether browser cookie import is currently enabled.
  bool get isEnabled => selectedBrowser != null;

  /// Pick a sensible default browser for an auto-fallback retry when
  /// the primary cookie-file path fails with `loginRequired` /
  /// `formatNotAvailable`.
  ///
  /// Returns the FIRST entry of [suggestFallbackBrowserChain] for
  /// callers that still want a single-shot fallback (legacy paths
  /// kept to minimise blast radius). New code should use
  /// [suggestFallbackBrowserChain] to iterate the full safe-ordered
  /// chain — yt-dlp `--cookies-from-browser` can fail on a single
  /// candidate when the browser holds its cookie database open
  /// (issue 7271 on Windows is the canonical case: Chrome running
  /// → `Could not copy Chrome cookie database` → naive single-pick
  /// dies even though Edge/Firefox would have succeeded).
  ///
  /// Returns null when no supported browser is detected. Caller
  /// should silently skip the fallback in that case rather than
  /// fail the whole extraction.
  BrowserType? suggestFallbackBrowser() {
    final chain = suggestFallbackBrowserChain();
    return chain.isEmpty ? null : chain.first;
  }

  /// Ordered chain of browsers to try as the cookies-from-browser
  /// fallback, safest-first. Callers should iterate this and break
  /// on the first attempt that doesn't fail with a "could not copy
  /// cookie database" / "unsupported browser" / browser-locked
  /// pattern.
  ///
  /// Ordering rationale per platform:
  /// - **Windows** — Chrome's cookie DB is locked by the Chrome
  ///   process whenever it is running (yt-dlp issue 7271). On a
  ///   typical user machine Chrome IS running because that's where
  ///   they're signed in to YouTube. Putting Chrome first is the
  ///   bad default the production log §138 surfaced. We push
  ///   Chrome LAST and prioritise Edge → Firefox → Brave → … so the
  ///   chain has a real chance to land on a non-locked store.
  /// - **macOS** — DB-lock is less common (each browser uses
  ///   per-profile SQLite files with WAL mode and the OS keychain
  ///   for decryption). Chrome first stays optimal here because it
  ///   is the most common YouTube login target.
  /// - **Linux** — Firefox first (often the system default + uses
  ///   profile.ini that yt-dlp parses without keyring quirks).
  ///   Chromium-family after.
  ///
  /// Safari is only emitted on macOS — its cookie store is platform-
  /// locked. Browsers not in `detectInstalledBrowsers()` are
  /// silently dropped.
  List<BrowserType> suggestFallbackBrowserChain() {
    final installed = detectInstalledBrowsers().toSet();
    if (installed.isEmpty) return const <BrowserType>[];
    final priority = _platformPriority();
    return [
      for (final candidate in priority)
        if (installed.contains(candidate)) candidate,
    ];
  }

  List<BrowserType> _platformPriority() {
    if (Platform.isWindows) {
      // Edge ships with the OS, is usually NOT the active browser,
      // and shares Chromium's cookie format → yt-dlp reads it
      // without DPAPI quirks. Firefox second because Mozilla's
      // sqlite store doesn't lock the way Chrome's does.
      return const [
        BrowserType.edge,
        BrowserType.firefox,
        BrowserType.brave,
        BrowserType.vivaldi,
        BrowserType.opera,
        BrowserType.chromium,
        BrowserType.chrome,
      ];
    }
    if (Platform.isMacOS) {
      return const [
        BrowserType.chrome,
        BrowserType.safari,
        BrowserType.edge,
        BrowserType.brave,
        BrowserType.firefox,
        BrowserType.vivaldi,
        BrowserType.opera,
        BrowserType.chromium,
      ];
    }
    // Linux + everything else.
    return const [
      BrowserType.firefox,
      BrowserType.chrome,
      BrowserType.chromium,
      BrowserType.brave,
      BrowserType.vivaldi,
      BrowserType.opera,
      BrowserType.edge,
    ];
  }
}
