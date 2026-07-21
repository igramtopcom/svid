import 'snooze_duration.dart';

/// Events emitted by the floating capture popup back to the main app.
///
/// Sealed hierarchy — pattern-match in the main app's event handler so
/// adding a new variant is a compile-time error if any consumer forgets
/// to handle it. Mirrors the IPC method names listed in the spike at
/// `floating_window_spike.dart` (lines 147–177) and spec §3.3.
sealed class FloatingWindowEvent {
  const FloatingWindowEvent();
}

/// User clicked one of the download buttons on the popup.
///
/// v2.2 Phase 2B introduced two button variants:
/// - **Primary "Tải ngay"** → [directDownload] = true → main app may
///   auto-pick from active preset when manual mode is off.
/// - **Secondary "Tuỳ chọn…"** → [directDownload] = false → main app
///   pre-fills URL field and forces the Download Options Dialog.
final class DownloadClicked extends FloatingWindowEvent {
  final String url;

  /// Optional preset key — popup may let user choose a quality preset
  /// (e.g. "1080p MP4") which the main app should apply when starting
  /// the download. Null means use the platform's default preset.
  final String? presetKey;

  /// v2.2 Phase 2B: which button was clicked. Default `true` for forward-
  /// compat with old popup engines that don't send the flag — old popups
  /// only had a single "Tải về" button which conceptually maps to "Tải ngay".
  final bool directDownload;

  const DownloadClicked({
    required this.url,
    this.presetKey,
    this.directDownload = true,
  });
}

/// User selected a snooze option.
final class SnoozeSelected extends FloatingWindowEvent {
  final SnoozeDuration duration;
  const SnoozeSelected(this.duration);
}

/// User chose "Open SSvid app" from the popup menu.
final class MenuOpenAppRequested extends FloatingWindowEvent {
  const MenuOpenAppRequested();
}

/// User chose "Settings" from the popup menu.
final class MenuOpenSettingsRequested extends FloatingWindowEvent {
  const MenuOpenSettingsRequested();
}

/// User dragged the popup to a new screen position. Coordinates are in
/// the global screen space; [monitorId] is the platform-specific monitor
/// identifier (used to remember per-monitor preferred positions).
final class PositionChanged extends FloatingWindowEvent {
  final double x;
  final double y;
  final String monitorId;
  const PositionChanged({
    required this.x,
    required this.y,
    required this.monitorId,
  });
}

/// User dismissed the popup (close button, click-outside, or Esc).
final class PopupDismissed extends FloatingWindowEvent {
  const PopupDismissed();
}

/// User clicked the video thumbnail — main app should open the URL in the
/// system browser per spec Q24.
final class ThumbnailClicked extends FloatingWindowEvent {
  final String url;
  const ThumbnailClicked(this.url);
}

/// User clicked "Open in SSvid" for a non-video URL — main app routes to
/// its own browser/sheet per spec Q18.
final class OpenInAppClicked extends FloatingWindowEvent {
  final String url;
  const OpenInAppClicked(this.url);
}

/// v2.2 Phase 2D.1 (CPO feedback): popup _CompletedRow "Mở thư mục" CTA.
/// Carries the absolute saved path so main side can reveal in Finder /
/// Explorer (`open -R <path>` macOS, `explorer.exe /select,<path>` Win).
final class OpenSavedFolderClicked extends FloatingWindowEvent {
  final String path;
  const OpenSavedFolderClicked(this.path);
}

/// v2.2 Phase 2D.1: popup _CompletedRow "Phát" CTA. Opens the matching
/// saved download in the main app's in-app player surface.
final class PlayFileClicked extends FloatingWindowEvent {
  final String path;
  const PlayFileClicked(this.path);
}
