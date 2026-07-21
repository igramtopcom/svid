import 'package:package_info_plus/package_info_plus.dart';
import '../config/brand_config.dart';

/// Application-wide constants
class AppConstants {
  AppConstants._();

  // App Information (delegated to BrandConfig)
  static String get appName => BrandConfig.current.appName;
  static String get appDescription => BrandConfig.current.appDescription;

  /// App version — resolved from native platform at startup (always matches pubspec.yaml).
  /// Call [init] before accessing.
  static String _appVersion = '0.0.0';
  static String get appVersion => _appVersion;

  /// Initialize runtime constants. Call once in main() after WidgetsFlutterBinding.
  ///
  /// Local dev runs can pass `--dart-define=APP_VERSION=x.y.z` so the app
  /// talks to update backends as the intended brand version without mutating
  /// `pubspec.yaml`. Release builds normally omit this because CI rewrites
  /// pubspec before packaging.
  ///
  /// Failure-tolerant: this runs BEFORE the error reporter is wired in main().
  /// If `PackageInfo.fromPlatform()` throws (corrupted bundle metadata, broken
  /// MSI install, missing CFBundleVersion plist key on macOS), main() would
  /// die silently with no error handler attached and the user would see a
  /// black window. We swallow the error and keep the '0.0.0' default — the
  /// version string is non-critical (used in Sentry release tag, update check,
  /// /about screen) and any caller that needs the real version will see the
  /// fallback.
  static Future<void> init() async {
    const versionOverride = String.fromEnvironment('APP_VERSION');
    if (versionOverride.isNotEmpty) {
      _appVersion = versionOverride;
      return;
    }

    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = info.version;
    } catch (_) {
      // Keep _appVersion = '0.0.0' default. Logging is unavailable here
      // (appLogger may not be initialized yet on first call).
    }
  }

  // Download Settings
  static const int defaultConcurrentDownloads = 3;
  static const int maxConcurrentDownloads = 10;
  static const int minConcurrentDownloads = 1;
  static const int defaultChunkSize = 1024 * 1024; // 1MB
  static const int maxRetryAttempts = 3;
  static const Duration retryDelay = Duration(seconds: 5);

  // Network Settings
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(minutes: 5);
  static const Duration sendTimeout = Duration(minutes: 1);

  // Storage Settings
  static const String defaultDownloadFolder = 'Downloads';
  static const int maxFileNameLength = 255;

  // UI Settings
  static const double defaultWindowWidth = 1200;
  static const double defaultWindowHeight = 800;
  static const double minWindowWidth = 800;
  static const double minWindowHeight = 600;

  // Drawer Settings
  static const double historyDrawerWidth = 380.0;

  // Sheet Settings
  static const double searchSheetHeightRatio = 0.9;

  // Video Settings
  static const double videoThumbnailWidth = 160.0;
  static const double videoThumbnailHeight = 90.0;
  static const double platformLogoSize = 36.0;
  static const double platformCardAspectRatio = 1.5;

  // Scroll Settings
  static const double infiniteScrollThreshold = 0.8;

  // Responsive Breakpoints
  static const double tabletBreakpoint = 900.0;
  static const double mobileBreakpoint = 600.0;

  // Database Settings (delegated to BrandConfig)
  static String get databaseName => BrandConfig.current.databaseName;
  static const int databaseVersion = 1;

  // File Size Units
  static const int bytesPerKB = 1024;
  static const int bytesPerMB = 1024 * 1024;
  static const int bytesPerGB = 1024 * 1024 * 1024;

  // Animation Durations
  static const Duration shortAnimationDuration = Duration(milliseconds: 200);
  static const Duration mediumAnimationDuration = Duration(milliseconds: 300);
  static const Duration longAnimationDuration = Duration(milliseconds: 500);

  // Supported File Extensions for Media Player
  static const List<String> supportedVideoExtensions = [
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.wmv',
    '.flv',
    '.webm',
    '.m4v',
  ];

  static const List<String> supportedAudioExtensions = [
    '.mp3',
    '.wav',
    '.flac',
    '.aac',
    '.ogg',
    '.m4a',
    '.wma',
  ];

  static const List<String> supportedImageExtensions = [
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.bmp',
    '.webp',
    '.svg',
  ];

  // Logging
  static const bool enableLogging = true;
  static const int maxLogFileSize = 10 * 1024 * 1024; // 10MB
  static const int maxLogFiles = 5;
}

/// API endpoints and URLs
class ApiConstants {
  ApiConstants._();

  // Go backend API — shared across all brands for operational services
  // (identity, analytics, payment, support, crash reports)
  static String get backendBaseUrl => BrandConfig.current.goBackendBaseUrl;
}

/// Preference keys for storing app settings
class PrefKeys {
  PrefKeys._();

  static const String downloadPath = 'download_path';
  static const String concurrentDownloads = 'concurrent_downloads';
  static const String themeMode = 'theme_mode';
  static const String language = 'language';
  static const String enableNotifications = 'enable_notifications';
  static const String autoStart = 'auto_start';
  static const String minimizeToTray = 'minimize_to_tray';
  static const String windowWidth = 'window_width';
  static const String windowHeight = 'window_height';
  static const String windowX = 'window_x';
  static const String windowY = 'window_y';

  // Backend integration
  static const String backendApiKey = 'backend_api_key';
  static const String deviceId = 'device_id';
  static const String bootstrapInstallId = 'bootstrap_install_id';
}
