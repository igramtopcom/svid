import '../../../../core/l10n/app_localizations.dart';

/// All supported output formats for media conversion.
///
/// Organized by category: video containers, audio formats, animated images.
enum OutputFormat {
  // ── Video containers ────────────────────────────────────────
  mp4('mp4', 'MP4', OutputFormatCategory.video),
  mkv('mkv', 'MKV', OutputFormatCategory.video),
  webm('webm', 'WebM', OutputFormatCategory.video),
  avi('avi', 'AVI', OutputFormatCategory.video),
  mov('mov', 'MOV', OutputFormatCategory.video),
  ts('mpegts', 'TS', OutputFormatCategory.video),
  flv('flv', 'FLV', OutputFormatCategory.video),

  // ── Audio formats ──────────────────────────────────────────
  mp3('mp3', 'MP3', OutputFormatCategory.audio),
  aac('adts', 'AAC', OutputFormatCategory.audio),
  flac('flac', 'FLAC', OutputFormatCategory.audio),
  wav('wav', 'WAV', OutputFormatCategory.audio),
  ogg('ogg', 'OGG', OutputFormatCategory.audio),
  opus('opus', 'Opus', OutputFormatCategory.audio),
  m4a('ipod', 'M4A', OutputFormatCategory.audio),
  wma('asf', 'WMA', OutputFormatCategory.audio),

  // ── Animated images ────────────────────────────────────────
  gif('gif', 'GIF', OutputFormatCategory.animatedImage),
  webp('webp', 'WebP', OutputFormatCategory.animatedImage);

  /// The ffmpeg format name used with `-f`
  final String ffmpegFormat;

  /// Human-readable display name
  final String displayName;

  /// Category for UI grouping
  final OutputFormatCategory category;

  const OutputFormat(this.ffmpegFormat, this.displayName, this.category);

  /// File extension (lowercase, no dot)
  String get extension {
    switch (this) {
      case OutputFormat.mp4:
        return 'mp4';
      case OutputFormat.mkv:
        return 'mkv';
      case OutputFormat.webm:
        return 'webm';
      case OutputFormat.avi:
        return 'avi';
      case OutputFormat.mov:
        return 'mov';
      case OutputFormat.ts:
        return 'ts';
      case OutputFormat.flv:
        return 'flv';
      case OutputFormat.mp3:
        return 'mp3';
      case OutputFormat.aac:
        return 'aac';
      case OutputFormat.flac:
        return 'flac';
      case OutputFormat.wav:
        return 'wav';
      case OutputFormat.ogg:
        return 'ogg';
      case OutputFormat.opus:
        return 'opus';
      case OutputFormat.m4a:
        return 'm4a';
      case OutputFormat.wma:
        return 'wma';
      case OutputFormat.gif:
        return 'gif';
      case OutputFormat.webp:
        return 'webp';
    }
  }

  /// Whether this format is audio-only (no video stream possible)
  bool get isAudioOnly => category == OutputFormatCategory.audio;

  /// Whether this format is a video container
  bool get isVideo => category == OutputFormatCategory.video;

  /// Whether this format is an animated image format
  bool get isAnimatedImage => category == OutputFormatCategory.animatedImage;

  /// Parse from file extension string
  static OutputFormat? fromExtension(String ext) {
    final lower = ext.toLowerCase().replaceAll('.', '');
    for (final format in values) {
      if (format.extension == lower) return format;
    }
    return null;
  }
}

/// Category grouping for output formats. `displayName` is the English
/// baseline kept as a const field (UI MUST prefer [localizedLabel] for
/// runtime locale switch).
enum OutputFormatCategory {
  video('Video'),
  audio('Audio'),
  animatedImage('Animated Image');

  final String displayName;
  const OutputFormatCategory(this.displayName);

  /// Locale-aware label resolved via AppLocalizations at render time.
  String get localizedLabel =>
      AppLocalizations.outputFormatCategoryLabel(name);
}

/// Video codec options for transcoding.
enum VideoCodecOption {
  h264('libx264', 'H.264 (AVC)'),
  h265('libx265', 'H.265 (HEVC)'),
  vp9('libvpx-vp9', 'VP9'),
  av1('libaom-av1', 'AV1'),
  copy('copy', 'Copy (no re-encode)'),
  none('none', 'No video');

  final String ffmpegName;
  final String displayName;
  const VideoCodecOption(this.ffmpegName, this.displayName);
}

/// Audio codec options for transcoding.
enum AudioCodecOption {
  aac('aac', 'AAC'),
  mp3('libmp3lame', 'MP3'),
  opus('libopus', 'Opus'),
  flac('flac', 'FLAC'),
  vorbis('libvorbis', 'Vorbis'),
  pcm('pcm_s16le', 'PCM (WAV)'),
  copy('copy', 'Copy (no re-encode)'),
  none('none', 'No audio');

  final String ffmpegName;
  final String displayName;
  const AudioCodecOption(this.ffmpegName, this.displayName);
}

/// Resolution presets for video scaling. `displayName` is the English
/// baseline (numeric resolutions stay universal across locales); UI
/// SHOULD prefer [localizedLabel] for the two non-numeric values
/// (Original / Custom) so they follow user locale.
enum ResolutionOption {
  original(0, 'Original'),
  p2160(2160, '4K (2160p)'),
  p1440(1440, '2K (1440p)'),
  p1080(1080, '1080p'),
  p720(720, '720p'),
  p480(480, '480p'),
  p360(360, '360p'),
  custom(-1, 'Custom');

  final int height;
  final String displayName;
  const ResolutionOption(this.height, this.displayName);

  /// Locale-aware label. Numeric resolutions ("1080p", "4K (2160p)") are
  /// universal tech terms and pass through unchanged. Only `original` and
  /// `custom` resolve via AppLocalizations.
  String get localizedLabel {
    switch (this) {
      case ResolutionOption.original:
        return AppLocalizations.resolutionOriginal;
      case ResolutionOption.custom:
        return AppLocalizations.resolutionCustom;
      default:
        return displayName;
    }
  }
}

/// Watermark position options. `displayName` is the English baseline;
/// UI MUST prefer [localizedLabel].
enum WatermarkPosition {
  topLeft('Top Left'),
  topRight('Top Right'),
  bottomLeft('Bottom Left'),
  bottomRight('Bottom Right'),
  center('Center');

  final String displayName;
  const WatermarkPosition(this.displayName);

  /// Locale-aware label resolved via AppLocalizations at render time.
  String get localizedLabel => AppLocalizations.watermarkPositionLabel(name);

  /// Get the ffmpeg overlay expression for this position.
  /// Assumes a 10px margin from edges.
  String get overlayExpression {
    switch (this) {
      case WatermarkPosition.topLeft:
        return 'overlay=10:10';
      case WatermarkPosition.topRight:
        return 'overlay=W-w-10:10';
      case WatermarkPosition.bottomLeft:
        return 'overlay=10:H-h-10';
      case WatermarkPosition.bottomRight:
        return 'overlay=W-w-10:H-h-10';
      case WatermarkPosition.center:
        return 'overlay=(W-w)/2:(H-h)/2';
    }
  }
}
