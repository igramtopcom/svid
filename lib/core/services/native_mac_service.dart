import 'dart:io';

import 'package:flutter/services.dart';

import '../config/brand_config.dart';
import '../logging/app_logger.dart';

/// Bridges Flutter to native macOS APIs via MethodChannel.
/// All methods are no-ops on non-macOS platforms.
class NativeMacService {
  static final _channel = MethodChannel('${BrandConfig.current.methodChannelPrefix}/macos_actions');

  /// Shows the native macOS share sheet (NSSharingServicePicker) for [filePath].
  /// The share sheet allows the user to send the file via AirDrop, Mail,
  /// Messages, or any other registered sharing service.
  ///
  /// Does nothing on non-macOS platforms.
  static Future<void> shareFile(String filePath) async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod<void>('shareFile', filePath);
    } on PlatformException catch (e) {
      appLogger.warning('NativeMacService.shareFile failed: ${e.message}');
    }
  }
}
