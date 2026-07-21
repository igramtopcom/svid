import 'dart:io';
import 'package:flutter/services.dart';
import 'package:local_notifier/local_notifier.dart';
import '../config/brand_config.dart';
import '../l10n/app_localizations.dart';
import '../logging/app_logger.dart';
import '../utils/process_helper.dart';

/// OS-level notification permission status.
enum NotificationPermissionStatus {
  /// Permission granted — notifications will be displayed.
  granted,

  /// Permission explicitly denied by the user.
  denied,

  /// Permission not yet requested (macOS only).
  notDetermined,
}

/// Desktop notification service.
///
/// Handles local notifications for download events and manages
/// OS-level notification permission on macOS/Windows/Linux.
class NotificationService {
  NotificationService({MethodChannel? permissionChannel})
    : _permissionChannel = permissionChannel;

  static const MethodChannel _stableWindowsIdentityChannel = MethodChannel(
    'snakeloader/windows_identity',
  );

  bool _isInitialized = false;

  /// Platform channel for native notification permission management (macOS).
  MethodChannel? _permissionChannel;

  /// Initialize notification service.
  Future<void> initialize() async {
    _permissionChannel = MethodChannel(
      '${BrandConfig.current.methodChannelPrefix}/notification_permission',
    );

    try {
      final windowsAppUserModelId = await _resolveWindowsAppUserModelId();
      await localNotifier.setup(
        appName: BrandConfig.current.appName,
        appUserModelId: windowsAppUserModelId,
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      await _restoreWindowsAppUserModelId(windowsAppUserModelId);
      _isInitialized = true;
      appLogger.info('Notification service initialized');
    } catch (e, stack) {
      appLogger.error('Failed to initialize notification service', e, stack);
    }
  }

  /// Resolve the Windows AUMID from native first. This makes the compiled exe's
  /// `brand_config.h` the source of truth for WinToast identity, so a bad
  /// Dart/native brand mix cannot make notifications emit under a stale app ID.
  Future<String?> _resolveWindowsAppUserModelId() async {
    if (!Platform.isWindows) return null;

    final dartAppUserModelId = BrandConfig.current.windowsAppUserModelId;
    try {
      final nativeAppUserModelId = await _stableWindowsIdentityChannel
          .invokeMethod<String>('getAppUserModelId');
      if (nativeAppUserModelId != null && nativeAppUserModelId.isNotEmpty) {
        if (nativeAppUserModelId != dartAppUserModelId) {
          appLogger.warning(
            'Windows AppUserModelID mismatch: native=$nativeAppUserModelId, '
            'dart=$dartAppUserModelId. Using native identity for toasts.',
          );
        }
        return nativeAppUserModelId;
      }
    } catch (e) {
      appLogger.warning(
        'Failed to read native Windows AppUserModelID; '
        'falling back to Dart brand config: $e',
      );
    }

    return dartAppUserModelId;
  }

  /// Re-apply the brand AUMID after notification setup so taskbar grouping,
  /// toast identity, and installer shortcuts remain aligned on Windows.
  Future<void> _restoreWindowsAppUserModelId(String? appUserModelId) async {
    if (!Platform.isWindows) return;

    try {
      await _stableWindowsIdentityChannel.invokeMethod<void>(
        'applyAppUserModelId',
      );
      appLogger.debug(
        'Restored Windows AppUserModelID: '
        '${appUserModelId ?? BrandConfig.current.windowsAppUserModelId}',
      );
    } on MissingPluginException catch (e) {
      try {
        await MethodChannel(
          '${BrandConfig.current.methodChannelPrefix}/windows_identity',
        ).invokeMethod<void>('applyAppUserModelId');
      } catch (fallbackError) {
        appLogger.warning(
          'Failed to restore Windows AppUserModelID via stable channel ($e) '
          'or branded fallback: $fallbackError',
        );
      }
    } catch (e) {
      appLogger.warning('Failed to restore Windows AppUserModelID: $e');
    }
  }

  // ── Permission Management ──────────────────────────────────────────

  /// Check OS-level notification permission status.
  ///
  /// - macOS: queries UNUserNotificationCenter authorization status.
  /// - Windows/Linux: always returns [NotificationPermissionStatus.granted]
  ///   (notifications are enabled by default on these platforms).
  Future<NotificationPermissionStatus> checkPermission() async {
    if (!Platform.isMacOS) return NotificationPermissionStatus.granted;
    if (_permissionChannel == null) {
      return NotificationPermissionStatus.granted;
    }
    try {
      final status = await _invokeWithRetry<String>('checkPermission');
      switch (status) {
        case 'granted':
          return NotificationPermissionStatus.granted;
        case 'denied':
          return NotificationPermissionStatus.denied;
        case 'not_determined':
          return NotificationPermissionStatus.notDetermined;
        default:
          return NotificationPermissionStatus.notDetermined;
      }
    } catch (e) {
      appLogger.warning('Failed to check notification permission: $e');
      return NotificationPermissionStatus.granted;
    }
  }

  /// Request notification permission from the OS.
  ///
  /// - macOS: triggers the system permission dialog via UNUserNotificationCenter.
  ///   Returns `true` if granted, `false` if denied. Only shows the dialog once —
  ///   subsequent calls return the cached result.
  /// - Windows/Linux: always returns `true` (no permission required).
  Future<bool> requestPermission() async {
    if (!Platform.isMacOS) return true;
    if (_permissionChannel == null) return true;
    try {
      final granted = await _invokeWithRetry<bool>('requestPermission');
      appLogger.info('Notification permission request result: $granted');
      return granted ?? false;
    } catch (e) {
      appLogger.warning('Failed to request notification permission: $e');
      return false;
    }
  }

  /// Invoke a method on the permission channel, retrying if AppDelegate
  /// hasn't wired the channel yet. Dart can race past
  /// `applicationDidFinishLaunching` during startup (and always does on
  /// hot restart), producing a MissingPluginException that masks a real
  /// race rather than a genuine missing handler. Retry with backoff.
  Future<T?> _invokeWithRetry<T>(String method, {int maxAttempts = 5}) async {
    final permissionChannel = _permissionChannel;
    if (permissionChannel == null) return null;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await permissionChannel.invokeMethod<T>(method);
      } on MissingPluginException {
        if (attempt == maxAttempts) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 150 * attempt));
      }
    }
    return null;
  }

  /// Open system notification settings for this app.
  ///
  /// - macOS: opens System Preferences → Notifications (targeting this app's bundle ID).
  /// - Windows: opens Settings → Notifications.
  /// - Linux: no-op (notification settings vary by desktop environment).
  Future<void> openSystemNotificationSettings() async {
    try {
      if (Platform.isMacOS) {
        await _invokeWithRetry<void>('openSettings');
      } else if (Platform.isWindows) {
        await ProcessHelper.openWindowsSettings('ms-settings:notifications');
      }
      // Linux: no standard notification settings path across DEs
    } catch (e) {
      appLogger.warning('Failed to open notification settings: $e');
    }
  }

  // ── Notification Display ───────────────────────────────────────────

  /// Show download completed notification.
  Future<void> showDownloadCompleted({
    required String filename,
    required String savePath,
  }) async {
    if (!_isInitialized) {
      appLogger.warning('Notification service not initialized');
      return;
    }

    try {
      final notification = LocalNotification(
        title: AppLocalizations.notificationDownloadCompleted,
        body: filename,
        actions: [
          LocalNotificationAction(
            text: AppLocalizations.notificationOpenFolder,
          ),
        ],
      );

      notification.onClickAction = (actionIndex) {
        if (actionIndex == 0) {
          // Open Folder — reveal file in system file manager
          ProcessHelper.openDirectoryInFileManager(savePath).ignore();
        }
      };

      await notification.show();
      _playCompletionSound();
      appLogger.debug('Shown notification: Download completed - $filename');
    } catch (e, stack) {
      appLogger.error(
        'Failed to show download completed notification',
        e,
        stack,
      );
    }
  }

  /// Play system sound on download completion (fire-and-forget).
  void _playCompletionSound() {
    try {
      if (Platform.isMacOS) {
        Process.run('afplay', [
          '/System/Library/Sounds/Glass.aiff',
        ]).timeout(const Duration(seconds: 5)).ignore();
      }
      // Windows/Linux: no built-in sound API without additional packages
    } catch (_) {
      // Sound is non-critical, silently ignore failures
    }
  }

  /// Show download failed notification.
  Future<void> showDownloadFailed({
    required String filename,
    required String error,
  }) async {
    if (!_isInitialized) {
      appLogger.warning('Notification service not initialized');
      return;
    }

    try {
      final notification = LocalNotification(
        title: AppLocalizations.notificationDownloadFailed,
        body: filename,
      );

      await notification.show();
      appLogger.debug('Shown notification: Download failed - $filename');
    } catch (e, stack) {
      appLogger.error('Failed to show download failed notification', e, stack);
    }
  }

  /// Show download started notification.
  Future<void> showDownloadStarted({required String filename}) async {
    if (!_isInitialized) {
      appLogger.warning('Notification service not initialized');
      return;
    }

    try {
      final notification = LocalNotification(
        title: AppLocalizations.notificationDownloadStarted,
        body: filename,
      );

      await notification.show();
      appLogger.debug('Shown notification: Download started - $filename');
    } catch (e, stack) {
      appLogger.error('Failed to show download started notification', e, stack);
    }
  }

  /// Show generic notification.
  Future<void> show({required String title, required String body}) async {
    if (!_isInitialized) {
      appLogger.warning('Notification service not initialized');
      return;
    }

    try {
      final notification = LocalNotification(title: title, body: body);

      await notification.show();
      appLogger.debug('Shown notification: $title');
    } catch (e, stack) {
      appLogger.error('Failed to show notification', e, stack);
    }
  }

  /// Close all notifications.
  Future<void> closeAll() async {
    try {
      // local_notifier doesn't have closeAll, but we can track and close individual ones
      appLogger.debug('Closing all notifications');
    } catch (e, stack) {
      appLogger.error('Failed to close notifications', e, stack);
    }
  }
}

/// Global notification service instance.
final notificationService = NotificationService();
