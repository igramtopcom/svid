// Pure formatting helpers for media info display.
// Extracted for testability — no Flutter/UI dependencies.

/// Format raw codec name to human-readable form.
/// Examples: 'h264' → 'H.264', 'vp9' → 'VP9', 'av1' → 'AV1',
/// 'aac' → 'AAC', 'opus' → 'Opus', null → '—'
String formatCodecName(String? raw) {
  if (raw == null || raw.isEmpty) return '—';
  final lower = raw.toLowerCase();
  const map = {
    'h264': 'H.264',
    'h265': 'H.265',
    'hevc': 'H.265',
    'vp8': 'VP8',
    'vp9': 'VP9',
    'av1': 'AV1',
    'aac': 'AAC',
    'opus': 'Opus',
    'mp3': 'MP3',
    'flac': 'FLAC',
    'vorbis': 'Vorbis',
    'ac3': 'AC3',
    'eac3': 'EAC3',
    'pcm': 'PCM',
  };
  return map[lower] ?? raw.toUpperCase();
}

/// Format bitrate in kbps to human-readable form.
/// Examples: 5200 → '5,200 kbps', null → '—'
String formatBitrate(int? kbps) {
  if (kbps == null || kbps <= 0) return '—';
  // Add thousand separators
  final str = kbps.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(str[i]);
  }
  return '$buffer kbps';
}

/// Format sample rate in Hz to human-readable form.
/// Examples: 48000 → '48,000 Hz', null → '—'
String formatSampleRate(int? hz) {
  if (hz == null || hz <= 0) return '—';
  final str = hz.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(str[i]);
  }
  return '$buffer Hz';
}

/// Format video resolution.
/// Examples: (1920, 1080) → '1920×1080', (null, null) → '—'
String formatResolution(int? w, int? h) {
  if (w == null || h == null || w <= 0 || h <= 0) return '—';
  return '$w×$h';
}

/// Format audio channels to human-readable form.
/// Examples: ('stereo', 2) → 'Stereo (2ch)', ('mono', 1) → 'Mono (1ch)',
/// (null, 2) → '2ch', (null, null) → '—'
String formatChannels(String? layout, int? count) {
  if (layout == null && count == null) return '—';
  if (layout != null && layout.isNotEmpty) {
    final capitalized = layout[0].toUpperCase() + layout.substring(1);
    if (count != null && count > 0) {
      return '$capitalized (${count}ch)';
    }
    return capitalized;
  }
  if (count != null && count > 0) return '${count}ch';
  return '—';
}

/// Format file size in bytes to human-readable form.
/// Examples: 1073741824 → '1.0 GB', 5242880 → '5.0 MB', 0 → '—'
String formatFileSize(int? bytes) {
  if (bytes == null || bytes <= 0) return '—';
  if (bytes >= 1073741824) {
    return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1048576) {
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}
