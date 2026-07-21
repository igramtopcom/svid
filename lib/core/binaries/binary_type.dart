import 'dart:io' show Platform;

/// Types of external binaries used by the app
enum BinaryType {
  ytDlp('yt-dlp', 'Video/audio downloader'),
  ffmpeg('ffmpeg', 'Media converter'),
  galleryDl('gallery-dl', 'Image downloader'),
  /// Deno JavaScript runtime — REQUIRED by yt-dlp 2025.11.12+ for full
  /// YouTube support (n-challenge / nsig / signature solving). Without
  /// it, YouTube logged-in extraction returns only storyboard formats
  /// (no real video/audio streams). Pinned to v2.7.14 for production
  /// determinism. App bundles per-platform binary; never relies on
  /// system-installed Deno (PATH inheritance creates non-deterministic
  /// behaviour across user environments).
  ///
  /// Architecturally Deno is a "runtime" not an "extractor", but lives
  /// here for unified BinaryManager lifecycle (download / verify / cache
  /// / pin version). yt-dlp invocations pass it explicitly via
  /// `--js-runtimes deno:<absolute-app-managed-path>` — no PATH leakage.
  deno('deno', 'JavaScript runtime for YouTube engine');

  final String name;
  final String description;

  const BinaryType(this.name, this.description);

  /// Get the binary filename for current platform
  String get filename {
    final isWindows = Platform.isWindows;
    switch (this) {
      case BinaryType.ytDlp:
        return isWindows ? 'yt-dlp.exe' : 'yt-dlp';
      case BinaryType.ffmpeg:
        return isWindows ? 'ffmpeg.exe' : 'ffmpeg';
      case BinaryType.galleryDl:
        return isWindows ? 'gallery-dl.exe' : 'gallery-dl';
      case BinaryType.deno:
        return isWindows ? 'deno.exe' : 'deno';
    }
  }

  /// Get display name for UI
  String get displayName {
    switch (this) {
      case BinaryType.ytDlp:
        return 'yt-dlp';
      case BinaryType.ffmpeg:
        return 'FFmpeg';
      case BinaryType.galleryDl:
        return 'gallery-dl';
      case BinaryType.deno:
        return 'Deno';
    }
  }

  /// Conservative minimum size in bytes for a healthy binary on disk.
  /// Used to detect truncated/partial downloads that pass the generic
  /// "not zero bytes" check but are obviously incomplete.
  /// Real production sizes are much larger (ffmpeg ~27MB, yt-dlp zipapp
  /// ~3MB, gallery-dl ~20MB, Deno ~120MB unpacked) — these floors are
  /// 50-70% of expected.
  int get minHealthyBytes {
    switch (this) {
      case BinaryType.ytDlp:
        return 1500000; // 1.5MB — yt-dlp zipapp ~3MB
      case BinaryType.ffmpeg:
        return 10000000; // 10MB — ffmpeg ~27MB
      case BinaryType.galleryDl:
        return 5000000; // 5MB — gallery-dl ~20MB
      case BinaryType.deno:
        return 80000000; // 80MB — Deno unpacked ~120MB on mac arm64
    }
  }
}
