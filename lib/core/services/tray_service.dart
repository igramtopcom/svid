import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import '../constants/app_assets.dart';
import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../logging/app_logger.dart';
import 'window_service.dart';

/// Returns the system tray tooltip string for a given active download count.
/// 0 active → app name only; N active → '{AppName} — N active download(s)'.
String trayTooltipForDownloads(int activeCount) {
  if (activeCount == 0) return AppConstants.appName;
  final s = activeCount == 1 ? '' : 's';
  return '${AppConstants.appName} — $activeCount active download$s';
}

/// System Tray Service
/// Handles system tray icon and menu for desktop platforms
class TrayService with TrayListener {
  // Singleton pattern
  static final TrayService _instance = TrayService._internal();
  factory TrayService() => _instance;
  TrayService._internal();

  /// Callback invoked when user clicks "New Download" in tray menu
  /// Set this callback to handle opening the download dialog or focusing the URL input
  Function()? onNewDownload;

  /// Callback invoked when user clicks "Show Downloads" in tray menu
  /// Set this callback to handle navigating to the downloads tab
  Function()? onShowDownloads;

  /// Callback invoked when user clicks "Settings" in tray menu
  /// Set this callback to handle navigating to the settings screen
  Function()? onSettings;

  @visibleForTesting
  static Future<void> Function()? showWindowOverride;

  @visibleForTesting
  static Future<void> Function()? closeWindowOverride;

  /// Initialize system tray
  Future<void> initialize() async {
    try {
      // Only enable on desktop platforms
      if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
        return;
      }

      trayManager.addListener(this);

      // Set tray icon
      await _setTrayIcon();

      // Set context menu
      await _setContextMenu();

      appLogger.info('System tray initialized');
    } catch (e, stackTrace) {
      appLogger.error('Failed to initialize system tray', e, stackTrace);
    }
  }

  /// Set platform-specific tray icon (brand-aware)
  Future<void> _setTrayIcon() async {
    String iconPath;

    if (Platform.isMacOS) {
      iconPath = AppAssets.trayIconMacOS;
    } else if (Platform.isWindows) {
      iconPath = AppAssets.trayIconWindows;
    } else {
      iconPath = AppAssets.trayIconLinux;
    }

    try {
      await trayManager.setIcon(
        iconPath,
        // macOS menu bar icons should be template images so the OS can tint
        // them for light/dark menu bars. Brand color belongs in Dock/app
        // icons; tray icons need to remain legible on both menu bar themes.
        isTemplate: Platform.isMacOS,
      );
    } catch (e) {
      appLogger.warning('Failed to set tray icon, using default', e);
    }

    // Set tooltip
    await trayManager.setToolTip('${AppConstants.appName} - Video Downloader');
  }

  /// Set tray context menu
  Future<void> _setContextMenu() async {
    final menu = Menu(
      items: [
        MenuItem(key: 'show', label: AppLocalizations.trayShowApp),
        MenuItem.separator(),
        MenuItem(key: 'new_download', label: AppLocalizations.trayNewDownload),
        MenuItem(key: 'downloads', label: AppLocalizations.trayShowDownloads),
        MenuItem.separator(),
        MenuItem(key: 'settings', label: AppLocalizations.traySettings),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: AppLocalizations.trayQuit),
      ],
    );

    await trayManager.setContextMenu(menu);
  }

  /// Update tray icon based on download status.
  /// Tooltip reflects active download count via [trayTooltipForDownloads].
  Future<void> updateDownloadStatus({
    required int activeDownloads,
    required int totalDownloads,
  }) async {
    await trayManager.setToolTip(trayTooltipForDownloads(activeDownloads));
  }

  // TrayListener implementations
  @override
  void onTrayIconMouseDown() {
    appLogger.debug('Tray icon clicked');
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    appLogger.debug('Tray menu clicked: ${menuItem.key}');

    switch (menuItem.key) {
      case 'show':
        _handleShow();
        break;
      case 'new_download':
        _handleNewDownload();
        break;
      case 'downloads':
        _handleShowDownloads();
        break;
      case 'settings':
        _handleSettings();
        break;
      case 'quit':
        _handleQuit();
        break;
    }
  }

  @override
  void onTrayIconMouseUp() {}

  @override
  void onTrayIconRightMouseUp() {}

  /// Handle "show" menu item - shows window and brings to front
  Future<void> _handleShow() async {
    await (showWindowOverride ?? WindowService.show)();
  }

  /// Handle new download
  Future<void> _handleNewDownload() async {
    await (showWindowOverride ?? WindowService.show)();
    onNewDownload?.call();
  }

  /// Handle show downloads
  Future<void> _handleShowDownloads() async {
    await (showWindowOverride ?? WindowService.show)();
    onShowDownloads?.call();
  }

  /// Handle settings
  Future<void> _handleSettings() async {
    await (showWindowOverride ?? WindowService.show)();
    onSettings?.call();
  }

  /// Handle quit
  Future<void> _handleQuit() async {
    appLogger.info('Quitting app from tray menu');
    await (closeWindowOverride ?? WindowService.close)();
  }

  /// Dispose tray
  Future<void> dispose() async {
    try {
      trayManager.removeListener(this);
      await trayManager.destroy();
      appLogger.info('System tray destroyed');
    } catch (e) {
      appLogger.error('Failed to destroy system tray', e);
    }
  }
}
