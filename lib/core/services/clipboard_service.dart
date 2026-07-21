import 'package:flutter/services.dart';

import '../logging/app_logger.dart';

/// Thin wrapper around Flutter's [Clipboard] that swallows the Windows-only
/// `PlatformException(Clipboard error, Unable to open clipboard, 5)` and
/// other transient platform errors (production telemetry: 37 records / 168h
/// against the raw direct calls).
///
/// On Windows the system clipboard can be locked by another foreground app
/// for several hundred ms after a copy/paste action. A direct
/// `Clipboard.getData` / `Clipboard.setData` call landing inside that window
/// throws an unhandled [PlatformException], which the host app's runZoned
/// path captures as a fatal frame error and reports to Sentry. Centralising
/// the access here converts the same failure into a no-op + warn log so the
/// user-facing surface (paste-and-start, copy URL, copy error details, etc.)
/// degrades gracefully instead of crashing the frame.
///
/// Contract:
///   * [getText]  → returns the clipboard text, or `null` on any failure.
///   * [setText]  → returns `true` on success, `false` on any failure.
///
/// Failures are logged at WARN level so support can correlate with
/// production reports without polluting INFO breadcrumbs.
class ClipboardService {
  ClipboardService._();

  /// Read the system clipboard's plain-text contents. Never throws.
  static Future<String?> getText() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      return data?.text;
    } on PlatformException catch (e) {
      appLogger.warning(
        'ClipboardService.getText platform error '
        '(code=${e.code}, message=${e.message})',
      );
      return null;
    } catch (e) {
      appLogger.warning('ClipboardService.getText unexpected error: $e');
      return null;
    }
  }

  /// Write [text] to the system clipboard. Never throws. Returns `true` on
  /// success so callers can show a "Copied" confirmation only when the
  /// write actually landed.
  static Future<bool> setText(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } on PlatformException catch (e) {
      appLogger.warning(
        'ClipboardService.setText platform error '
        '(code=${e.code}, message=${e.message}, len=${text.length})',
      );
      return false;
    } catch (e) {
      appLogger.warning(
        'ClipboardService.setText unexpected error: $e (len=${text.length})',
      );
      return false;
    }
  }
}
