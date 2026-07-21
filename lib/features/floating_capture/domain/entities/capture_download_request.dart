import '../../../downloads/domain/entities/video_preview.dart';

/// Emitted by [CaptureService] when the user clicks the "Download" button
/// on the floating popup. The main app subscribes to
/// [CaptureService.downloadRequests] and routes the request into the
/// existing download system (yt-dlp + ffmpeg pipeline).
///
/// Decoupled from the download system so floating capture can be unit
/// tested without pulling in Rust FFI / yt-dlp / DownloadManager stubs.
class CaptureDownloadRequest {
  /// The preview the user was looking at when they clicked Download.
  /// Carries platform / urlType / itemId / thumbnail — main app uses this
  /// to choose preset, route to playlist sheet, etc.
  final VideoPreview preview;

  /// Optional preset key the popup may forward (e.g. `"1080p-mp4"`). Null
  /// means the main app should apply its default per-platform preset.
  final String? presetKey;

  /// When the user clicked. The main app may use this to deduplicate if
  /// it receives multiple Download events for the same URL (e.g. user
  /// double-clicks).
  final DateTime requestedAt;

  /// v2.2 Phase 2B Shift 1 — popup is destination, not shortcut.
  ///
  /// `true` (default for the popup primary "Tải ngay" button) → main app
  /// may auto-pick from `activePresetProvider.currentConfig` and enqueue
  /// directly when the active preset allows it. If the user has enabled
  /// manual mode, the normal dialog path still wins.
  ///
  /// `false` (popup secondary "Tuỳ chọn…" button) → force the existing
  /// Download Options Dialog for this URL so the user can customize format /
  /// subs / trim / etc. Preset and saved-preference auto-pick are bypassed.
  final bool directDownload;

  const CaptureDownloadRequest({
    required this.preview,
    required this.requestedAt,
    this.presetKey,
    this.directDownload = true,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CaptureDownloadRequest &&
          other.preview == preview &&
          other.presetKey == presetKey &&
          other.requestedAt == requestedAt &&
          other.directDownload == directDownload);

  @override
  int get hashCode =>
      Object.hash(preview, presetKey, requestedAt, directDownload);
}
