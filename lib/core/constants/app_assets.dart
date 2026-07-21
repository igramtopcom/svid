import '../config/brand_config.dart';

/// App-wide asset path constants
/// Brand-specific assets are stored in assets/brands/{brand}/
class AppAssets {
  AppAssets._();

  // ==================== BRAND ASSETS ====================
  static String get _brandPath => 'assets/brands/${BrandConfig.current.brand.name}';

  /// App logo (brand-colored play button icon)
  static String get logo => '$_brandPath/logo.png';

  /// App icon (used in About dialogs, etc.)
  static String get appIcon => '$_brandPath/app_icon.png';

  // ==================== TRAY ICONS ====================

  /// macOS tray icon (template image — black with transparency)
  static String get trayIconMacOS => '$_brandPath/tray_icon_macos.png';

  /// Windows tray icon (.ico)
  static String get trayIconWindows => '$_brandPath/tray_icon_windows.ico';

  /// Linux tray icon (.png)
  static String get trayIconLinux => '$_brandPath/tray_icon_linux.png';

  // ==================== PLATFORM ICONS ====================
  // Social media platform icons (shared across brands)
  // static const String _iconsPath = 'assets/icons';
  // static const String youtubeIcon = '$_iconsPath/youtube.png';
}
