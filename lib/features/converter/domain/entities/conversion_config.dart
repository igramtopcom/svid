import 'dart:convert';

import 'output_format.dart';

/// Trim range in milliseconds.
class TrimRange {
  final int startMs;
  final int endMs;

  const TrimRange({required this.startMs, required this.endMs});

  Duration get startDuration => Duration(milliseconds: startMs);
  Duration get endDuration => Duration(milliseconds: endMs);
  Duration get duration => Duration(milliseconds: endMs - startMs);

  Map<String, dynamic> toJson() => {'startMs': startMs, 'endMs': endMs};

  factory TrimRange.fromJson(Map<String, dynamic> json) => TrimRange(
        startMs: json['startMs'] as int,
        endMs: json['endMs'] as int,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrimRange && startMs == other.startMs && endMs == other.endMs;

  @override
  int get hashCode => startMs.hashCode ^ endMs.hashCode;
}

/// Crop region configuration.
class CropConfig {
  final int x;
  final int y;
  final int width;
  final int height;

  const CropConfig({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };

  factory CropConfig.fromJson(Map<String, dynamic> json) => CropConfig(
        x: json['x'] as int,
        y: json['y'] as int,
        width: json['width'] as int,
        height: json['height'] as int,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CropConfig &&
          x == other.x &&
          y == other.y &&
          width == other.width &&
          height == other.height;

  @override
  int get hashCode => Object.hash(x, y, width, height);
}

/// Rotation / flip options.
enum RotateOption {
  cw90('90\u00B0 CW'),
  ccw90('90\u00B0 CCW'),
  rotate180('180\u00B0'),
  flipH('Flip Horizontal'),
  flipV('Flip Vertical');

  final String displayName;
  const RotateOption(this.displayName);
}

/// Text overlay configuration (position, font, color).
class TextOverlayConfig {
  final String position; // "top", "center", "bottom"
  final int fontSize;
  final String fontColor;
  final String? borderColor;
  final int borderWidth;

  const TextOverlayConfig({
    this.position = 'bottom',
    this.fontSize = 24,
    this.fontColor = 'white',
    this.borderColor = 'black',
    this.borderWidth = 2,
  });

  Map<String, dynamic> toJson() => {
        'position': position,
        'fontSize': fontSize,
        'fontColor': fontColor,
        if (borderColor != null) 'borderColor': borderColor,
        'borderWidth': borderWidth,
      };

  factory TextOverlayConfig.fromJson(Map<String, dynamic> json) =>
      TextOverlayConfig(
        position: json['position'] as String? ?? 'bottom',
        fontSize: json['fontSize'] as int? ?? 24,
        fontColor: json['fontColor'] as String? ?? 'white',
        borderColor: json['borderColor'] as String?,
        borderWidth: json['borderWidth'] as int? ?? 2,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextOverlayConfig &&
          position == other.position &&
          fontSize == other.fontSize &&
          fontColor == other.fontColor &&
          borderColor == other.borderColor &&
          borderWidth == other.borderWidth;

  @override
  int get hashCode =>
      Object.hash(position, fontSize, fontColor, borderColor, borderWidth);
}

/// Region to blur or pixelate in the video.
class BlurRegion {
  final int x;
  final int y;
  final int width;
  final int height;
  final String type; // "blur" or "pixelate"
  final int strength; // 1-20

  const BlurRegion({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.type = 'blur',
    this.strength = 10,
  });

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'type': type,
        'strength': strength,
      };

  factory BlurRegion.fromJson(Map<String, dynamic> json) => BlurRegion(
        x: json['x'] as int,
        y: json['y'] as int,
        width: json['width'] as int,
        height: json['height'] as int,
        type: json['type'] as String? ?? 'blur',
        strength: json['strength'] as int? ?? 10,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlurRegion &&
          x == other.x &&
          y == other.y &&
          width == other.width &&
          height == other.height &&
          type == other.type &&
          strength == other.strength;

  @override
  int get hashCode => Object.hash(x, y, width, height, type, strength);
}

/// Picture-in-picture overlay configuration.
class PipConfig {
  final String overlayPath;
  final String position; // "topLeft", "topRight", "bottomLeft", "bottomRight"
  final double scale; // 0.1 to 0.5

  const PipConfig({
    required this.overlayPath,
    this.position = 'bottomRight',
    this.scale = 0.25,
  });

  Map<String, dynamic> toJson() => {
        'overlayPath': overlayPath,
        'position': position,
        'scale': scale,
      };

  factory PipConfig.fromJson(Map<String, dynamic> json) => PipConfig(
        overlayPath: json['overlayPath'] as String,
        position: json['position'] as String? ?? 'bottomRight',
        scale: (json['scale'] as num?)?.toDouble() ?? 0.25,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PipConfig &&
          overlayPath == other.overlayPath &&
          position == other.position &&
          scale == other.scale;

  @override
  int get hashCode => Object.hash(overlayPath, position, scale);
}

/// Split screen layout configuration.
class SplitScreenConfig {
  final List<String> filePaths; // 2-4 video paths
  final String layout; // "horizontal", "vertical", "grid"

  const SplitScreenConfig({
    required this.filePaths,
    this.layout = 'horizontal',
  });

  Map<String, dynamic> toJson() => {
        'filePaths': filePaths,
        'layout': layout,
      };

  factory SplitScreenConfig.fromJson(Map<String, dynamic> json) =>
      SplitScreenConfig(
        filePaths: List<String>.from(json['filePaths'] as List),
        layout: json['layout'] as String? ?? 'horizontal',
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SplitScreenConfig &&
          layout == other.layout &&
          _listEquals(filePaths, other.filePaths);

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(layout, Object.hashAll(filePaths));
}

/// Complete conversion configuration — every parameter ffmpeg needs.
///
/// This is the single source of truth for building ffmpeg command args.
/// Serializable to JSON for persistence in the database.
class ConversionConfig {
  final OutputFormat outputFormat;
  final VideoCodecOption? videoCodec;
  final int? videoBitrate; // kbps, null = CRF mode
  final int? crf; // Quality factor, lower = better
  final String? encoderPreset; // ultrafast/fast/medium/slow/veryslow
  final ResolutionOption? resolution;
  final int? customWidth;
  final int? customHeight;
  final int? fps; // null = original
  final AudioCodecOption? audioCodec;
  final int? audioBitrate; // kbps
  final int? audioSampleRate; // 44100, 48000, etc.
  final int? audioChannels; // 1=mono, 2=stereo
  final bool hwAccel;
  final bool twoPass;
  final bool normalize; // loudnorm audio normalization
  final TrimRange? trim;
  final double? speed; // 0.25 to 4.0
  final String? subtitlePath; // burn-in subtitle file
  final String? watermarkPath;
  final WatermarkPosition? watermarkPosition;
  final Map<String, String>? metadata;
  final List<String>? extraArgs; // Power users

  // ── Enhancement / Edit fields ──
  final CropConfig? crop;
  final RotateOption? rotate;
  final bool removeAudio;
  final bool removeVideo;
  final String? textOverlay;
  final TextOverlayConfig? textOverlayConfig;
  final String? lutPath;
  final String? colorEffect; // ffmpeg filter chain for built-in color grading
  final bool denoise;
  final String? denoiseStrength; // "light", "medium", "strong"
  final bool stabilize;
  final bool fadeIn;
  final bool fadeOut;
  final double? fadeDuration; // seconds (default 1.0)
  final bool vignette;
  final double? vignetteAngle; // PI/5 default
  final bool filmGrain;
  final double? grainIntensity; // 0-100
  final bool interpolate;
  final int? targetFps;
  final List<String>? concatFiles; // Files to concatenate (in order)
  final BlurRegion? blurRegion;
  final PipConfig? pipConfig;
  final SplitScreenConfig? splitScreen;

  // ── Advanced Processing fields ──
  final bool hdrToSdr; // HDR→SDR tone mapping (zscale+tonemap)
  final bool deinterlace; // yadif deinterlacing
  final bool reverse; // reverse video+audio
  final double? volumeDb; // volume adjustment in dB (-20 to +20)
  final String? audioEqPreset; // named EQ: "bass_boost", "treble_boost", "voice_enhance", "cinema"
  final String? channelLayout; // "mono", "stereo", "5.1_to_stereo"
  final String? letterbox; // target aspect ratio for letterbox/pillarbox: "16:9", "4:3", "21:9"
  final int? loopCount; // loop video N times (0=infinite)
  final bool sharpen; // unsharp mask sharpening
  final double? sharpenStrength; // 0.5 to 2.0 (default 1.0)
  final double? brightness; // -1.0 to 1.0
  final double? contrast; // 0.0 to 3.0
  final double? saturation; // 0.0 to 3.0
  final double? gamma; // 0.1 to 10.0
  final bool negate; // invert colors
  final bool audioCompressor; // dynamic range compression (compand)

  // ── Special Operations fields ──
  final bool extractThumbnail; // extract single frame as image
  final double? thumbnailTimestamp; // timestamp in seconds for thumbnail
  final bool extractSubtitles; // extract embedded subtitles to .srt
  final int? subtitleTrackIndex; // which subtitle track (0-based)
  final int? splitInterval; // segment split interval in seconds
  final bool concatWithTransition; // fade transitions between concat clips
  final double? transitionDuration; // transition fade duration in seconds

  const ConversionConfig({
    required this.outputFormat,
    this.videoCodec,
    this.videoBitrate,
    this.crf,
    this.encoderPreset,
    this.resolution,
    this.customWidth,
    this.customHeight,
    this.fps,
    this.audioCodec,
    this.audioBitrate,
    this.audioSampleRate,
    this.audioChannels,
    this.hwAccel = false,
    this.twoPass = false,
    this.normalize = false,
    this.trim,
    this.speed,
    this.subtitlePath,
    this.watermarkPath,
    this.watermarkPosition,
    this.metadata,
    this.extraArgs,
    // Enhancement fields
    this.crop,
    this.rotate,
    this.removeAudio = false,
    this.removeVideo = false,
    this.textOverlay,
    this.textOverlayConfig,
    this.lutPath,
    this.colorEffect,
    this.denoise = false,
    this.denoiseStrength,
    this.stabilize = false,
    this.fadeIn = false,
    this.fadeOut = false,
    this.fadeDuration,
    this.vignette = false,
    this.vignetteAngle,
    this.filmGrain = false,
    this.grainIntensity,
    this.interpolate = false,
    this.targetFps,
    this.concatFiles,
    this.blurRegion,
    this.pipConfig,
    this.splitScreen,
    // Advanced processing
    this.hdrToSdr = false,
    this.deinterlace = false,
    this.reverse = false,
    this.volumeDb,
    this.audioEqPreset,
    this.channelLayout,
    this.letterbox,
    this.loopCount,
    this.sharpen = false,
    this.sharpenStrength,
    this.brightness,
    this.contrast,
    this.saturation,
    this.gamma,
    this.negate = false,
    this.audioCompressor = false,
    // Special operations
    this.extractThumbnail = false,
    this.thumbnailTimestamp,
    this.extractSubtitles = false,
    this.subtitleTrackIndex,
    this.splitInterval,
    this.concatWithTransition = false,
    this.transitionDuration,
  });

  /// Whether this config will produce audio-only output
  bool get isAudioOnly =>
      outputFormat.isAudioOnly ||
      videoCodec == VideoCodecOption.none ||
      removeVideo;

  /// Whether this config uses stream copy (no re-encoding)
  bool get isStreamCopy =>
      videoCodec == VideoCodecOption.copy &&
      (audioCodec == AudioCodecOption.copy || audioCodec == null);

  /// Whether this config produces an animated image (GIF/WebP)
  bool get isAnimatedImage => outputFormat.isAnimatedImage;

  /// Whether this config is a concatenation job (multiple input files)
  bool get isConcat => concatFiles != null && concatFiles!.isNotEmpty;

  /// Whether this config requires filter_complex (multi-input filters)
  bool get needsFilterComplex =>
      blurRegion != null ||
      pipConfig != null ||
      splitScreen != null ||
      (watermarkPath != null && watermarkPosition != null);

  /// Whether this is a special operation (not a regular conversion)
  bool get isSpecialOperation =>
      extractThumbnail || extractSubtitles || splitInterval != null;

  /// Whether this config has any enhancement filters
  bool get hasEnhancementFilters =>
      crop != null ||
      rotate != null ||
      textOverlay != null ||
      lutPath != null ||
      colorEffect != null ||
      denoise ||
      fadeIn ||
      fadeOut ||
      vignette ||
      filmGrain ||
      interpolate ||
      blurRegion != null ||
      hdrToSdr ||
      deinterlace ||
      reverse ||
      sharpen ||
      negate ||
      brightness != null ||
      contrast != null ||
      saturation != null ||
      gamma != null;

  ConversionConfig copyWith({
    OutputFormat? outputFormat,
    VideoCodecOption? videoCodec,
    int? videoBitrate,
    int? crf,
    String? encoderPreset,
    ResolutionOption? resolution,
    int? customWidth,
    int? customHeight,
    int? fps,
    AudioCodecOption? audioCodec,
    int? audioBitrate,
    int? audioSampleRate,
    int? audioChannels,
    bool? hwAccel,
    bool? twoPass,
    bool? normalize,
    TrimRange? trim,
    double? speed,
    String? subtitlePath,
    String? watermarkPath,
    WatermarkPosition? watermarkPosition,
    Map<String, String>? metadata,
    List<String>? extraArgs,
    // Enhancement fields
    CropConfig? crop,
    RotateOption? rotate,
    bool? removeAudio,
    bool? removeVideo,
    String? textOverlay,
    TextOverlayConfig? textOverlayConfig,
    String? lutPath,
    String? colorEffect,
    bool? denoise,
    String? denoiseStrength,
    bool? stabilize,
    bool? fadeIn,
    bool? fadeOut,
    double? fadeDuration,
    bool? vignette,
    double? vignetteAngle,
    bool? filmGrain,
    double? grainIntensity,
    bool? interpolate,
    int? targetFps,
    List<String>? concatFiles,
    BlurRegion? blurRegion,
    PipConfig? pipConfig,
    SplitScreenConfig? splitScreen,
    // Advanced processing
    bool? hdrToSdr,
    bool? deinterlace,
    bool? reverse,
    double? volumeDb,
    String? audioEqPreset,
    String? channelLayout,
    String? letterbox,
    int? loopCount,
    bool? sharpen,
    double? sharpenStrength,
    double? brightness,
    double? contrast,
    double? saturation,
    double? gamma,
    bool? negate,
    bool? audioCompressor,
    // Special operations
    bool? extractThumbnail,
    double? thumbnailTimestamp,
    bool? extractSubtitles,
    int? subtitleTrackIndex,
    int? splitInterval,
    bool? concatWithTransition,
    double? transitionDuration,
    // Special sentinel params to clear nullable fields
    bool clearVideoCodec = false,
    bool clearVideoBitrate = false,
    bool clearCrf = false,
    bool clearEncoderPreset = false,
    bool clearResolution = false,
    bool clearCustomWidth = false,
    bool clearCustomHeight = false,
    bool clearFps = false,
    bool clearAudioCodec = false,
    bool clearAudioBitrate = false,
    bool clearAudioSampleRate = false,
    bool clearAudioChannels = false,
    bool clearTrim = false,
    bool clearSpeed = false,
    bool clearSubtitlePath = false,
    bool clearWatermarkPath = false,
    bool clearWatermarkPosition = false,
    bool clearMetadata = false,
    bool clearExtraArgs = false,
    bool clearCrop = false,
    bool clearRotate = false,
    bool clearTextOverlay = false,
    bool clearTextOverlayConfig = false,
    bool clearLutPath = false,
    bool clearColorEffect = false,
    bool clearDenoiseStrength = false,
    bool clearFadeDuration = false,
    bool clearVignetteAngle = false,
    bool clearGrainIntensity = false,
    bool clearTargetFps = false,
    bool clearConcatFiles = false,
    bool clearBlurRegion = false,
    bool clearPipConfig = false,
    bool clearSplitScreen = false,
    bool clearVolumeDb = false,
    bool clearAudioEqPreset = false,
    bool clearChannelLayout = false,
    bool clearLetterbox = false,
    bool clearLoopCount = false,
    bool clearSharpenStrength = false,
    bool clearBrightness = false,
    bool clearContrast = false,
    bool clearSaturation = false,
    bool clearGamma = false,
    bool clearThumbnailTimestamp = false,
    bool clearSubtitleTrackIndex = false,
    bool clearSplitInterval = false,
    bool clearTransitionDuration = false,
  }) {
    return ConversionConfig(
      outputFormat: outputFormat ?? this.outputFormat,
      videoCodec: clearVideoCodec ? null : (videoCodec ?? this.videoCodec),
      videoBitrate: clearVideoBitrate ? null : (videoBitrate ?? this.videoBitrate),
      crf: clearCrf ? null : (crf ?? this.crf),
      encoderPreset: clearEncoderPreset ? null : (encoderPreset ?? this.encoderPreset),
      resolution: clearResolution ? null : (resolution ?? this.resolution),
      customWidth: clearCustomWidth ? null : (customWidth ?? this.customWidth),
      customHeight: clearCustomHeight ? null : (customHeight ?? this.customHeight),
      fps: clearFps ? null : (fps ?? this.fps),
      audioCodec: clearAudioCodec ? null : (audioCodec ?? this.audioCodec),
      audioBitrate: clearAudioBitrate ? null : (audioBitrate ?? this.audioBitrate),
      audioSampleRate: clearAudioSampleRate ? null : (audioSampleRate ?? this.audioSampleRate),
      audioChannels: clearAudioChannels ? null : (audioChannels ?? this.audioChannels),
      hwAccel: hwAccel ?? this.hwAccel,
      twoPass: twoPass ?? this.twoPass,
      normalize: normalize ?? this.normalize,
      trim: clearTrim ? null : (trim ?? this.trim),
      speed: clearSpeed ? null : (speed ?? this.speed),
      subtitlePath: clearSubtitlePath ? null : (subtitlePath ?? this.subtitlePath),
      watermarkPath: clearWatermarkPath ? null : (watermarkPath ?? this.watermarkPath),
      watermarkPosition: clearWatermarkPosition ? null : (watermarkPosition ?? this.watermarkPosition),
      metadata: clearMetadata ? null : (metadata ?? this.metadata),
      extraArgs: clearExtraArgs ? null : (extraArgs ?? this.extraArgs),
      // Enhancement fields
      crop: clearCrop ? null : (crop ?? this.crop),
      rotate: clearRotate ? null : (rotate ?? this.rotate),
      removeAudio: removeAudio ?? this.removeAudio,
      removeVideo: removeVideo ?? this.removeVideo,
      textOverlay: clearTextOverlay ? null : (textOverlay ?? this.textOverlay),
      textOverlayConfig: clearTextOverlayConfig ? null : (textOverlayConfig ?? this.textOverlayConfig),
      lutPath: clearLutPath ? null : (lutPath ?? this.lutPath),
      colorEffect: clearColorEffect ? null : (colorEffect ?? this.colorEffect),
      denoise: denoise ?? this.denoise,
      denoiseStrength: clearDenoiseStrength ? null : (denoiseStrength ?? this.denoiseStrength),
      stabilize: stabilize ?? this.stabilize,
      fadeIn: fadeIn ?? this.fadeIn,
      fadeOut: fadeOut ?? this.fadeOut,
      fadeDuration: clearFadeDuration ? null : (fadeDuration ?? this.fadeDuration),
      vignette: vignette ?? this.vignette,
      vignetteAngle: clearVignetteAngle ? null : (vignetteAngle ?? this.vignetteAngle),
      filmGrain: filmGrain ?? this.filmGrain,
      grainIntensity: clearGrainIntensity ? null : (grainIntensity ?? this.grainIntensity),
      interpolate: interpolate ?? this.interpolate,
      targetFps: clearTargetFps ? null : (targetFps ?? this.targetFps),
      concatFiles: clearConcatFiles ? null : (concatFiles ?? this.concatFiles),
      blurRegion: clearBlurRegion ? null : (blurRegion ?? this.blurRegion),
      pipConfig: clearPipConfig ? null : (pipConfig ?? this.pipConfig),
      splitScreen: clearSplitScreen ? null : (splitScreen ?? this.splitScreen),
      // Advanced processing
      hdrToSdr: hdrToSdr ?? this.hdrToSdr,
      deinterlace: deinterlace ?? this.deinterlace,
      reverse: reverse ?? this.reverse,
      volumeDb: clearVolumeDb ? null : (volumeDb ?? this.volumeDb),
      audioEqPreset: clearAudioEqPreset ? null : (audioEqPreset ?? this.audioEqPreset),
      channelLayout: clearChannelLayout ? null : (channelLayout ?? this.channelLayout),
      letterbox: clearLetterbox ? null : (letterbox ?? this.letterbox),
      loopCount: clearLoopCount ? null : (loopCount ?? this.loopCount),
      sharpen: sharpen ?? this.sharpen,
      sharpenStrength: clearSharpenStrength ? null : (sharpenStrength ?? this.sharpenStrength),
      brightness: clearBrightness ? null : (brightness ?? this.brightness),
      contrast: clearContrast ? null : (contrast ?? this.contrast),
      saturation: clearSaturation ? null : (saturation ?? this.saturation),
      gamma: clearGamma ? null : (gamma ?? this.gamma),
      negate: negate ?? this.negate,
      audioCompressor: audioCompressor ?? this.audioCompressor,
      // Special operations
      extractThumbnail: extractThumbnail ?? this.extractThumbnail,
      thumbnailTimestamp: clearThumbnailTimestamp ? null : (thumbnailTimestamp ?? this.thumbnailTimestamp),
      extractSubtitles: extractSubtitles ?? this.extractSubtitles,
      subtitleTrackIndex: clearSubtitleTrackIndex ? null : (subtitleTrackIndex ?? this.subtitleTrackIndex),
      splitInterval: clearSplitInterval ? null : (splitInterval ?? this.splitInterval),
      concatWithTransition: concatWithTransition ?? this.concatWithTransition,
      transitionDuration: clearTransitionDuration ? null : (transitionDuration ?? this.transitionDuration),
    );
  }

  /// Serialize to JSON string for database persistence.
  String toJsonString() => jsonEncode(toJson());

  Map<String, dynamic> toJson() {
    return {
      'outputFormat': outputFormat.name,
      if (videoCodec != null) 'videoCodec': videoCodec!.name,
      if (videoBitrate != null) 'videoBitrate': videoBitrate,
      if (crf != null) 'crf': crf,
      if (encoderPreset != null) 'encoderPreset': encoderPreset,
      if (resolution != null) 'resolution': resolution!.name,
      if (customWidth != null) 'customWidth': customWidth,
      if (customHeight != null) 'customHeight': customHeight,
      if (fps != null) 'fps': fps,
      if (audioCodec != null) 'audioCodec': audioCodec!.name,
      if (audioBitrate != null) 'audioBitrate': audioBitrate,
      if (audioSampleRate != null) 'audioSampleRate': audioSampleRate,
      if (audioChannels != null) 'audioChannels': audioChannels,
      'hwAccel': hwAccel,
      'twoPass': twoPass,
      'normalize': normalize,
      if (trim != null) 'trim': trim!.toJson(),
      if (speed != null) 'speed': speed,
      if (subtitlePath != null) 'subtitlePath': subtitlePath,
      if (watermarkPath != null) 'watermarkPath': watermarkPath,
      if (watermarkPosition != null) 'watermarkPosition': watermarkPosition!.name,
      if (metadata != null) 'metadata': metadata,
      if (extraArgs != null) 'extraArgs': extraArgs,
      // Enhancement fields
      if (crop != null) 'crop': crop!.toJson(),
      if (rotate != null) 'rotate': rotate!.name,
      'removeAudio': removeAudio,
      'removeVideo': removeVideo,
      if (textOverlay != null) 'textOverlay': textOverlay,
      if (textOverlayConfig != null) 'textOverlayConfig': textOverlayConfig!.toJson(),
      if (lutPath != null) 'lutPath': lutPath,
      if (colorEffect != null) 'colorEffect': colorEffect,
      'denoise': denoise,
      if (denoiseStrength != null) 'denoiseStrength': denoiseStrength,
      'stabilize': stabilize,
      'fadeIn': fadeIn,
      'fadeOut': fadeOut,
      if (fadeDuration != null) 'fadeDuration': fadeDuration,
      'vignette': vignette,
      if (vignetteAngle != null) 'vignetteAngle': vignetteAngle,
      'filmGrain': filmGrain,
      if (grainIntensity != null) 'grainIntensity': grainIntensity,
      'interpolate': interpolate,
      if (targetFps != null) 'targetFps': targetFps,
      if (concatFiles != null) 'concatFiles': concatFiles,
      if (blurRegion != null) 'blurRegion': blurRegion!.toJson(),
      if (pipConfig != null) 'pipConfig': pipConfig!.toJson(),
      if (splitScreen != null) 'splitScreen': splitScreen!.toJson(),
      // Advanced processing
      'hdrToSdr': hdrToSdr,
      'deinterlace': deinterlace,
      'reverse': reverse,
      if (volumeDb != null) 'volumeDb': volumeDb,
      if (audioEqPreset != null) 'audioEqPreset': audioEqPreset,
      if (channelLayout != null) 'channelLayout': channelLayout,
      if (letterbox != null) 'letterbox': letterbox,
      if (loopCount != null) 'loopCount': loopCount,
      'sharpen': sharpen,
      if (sharpenStrength != null) 'sharpenStrength': sharpenStrength,
      if (brightness != null) 'brightness': brightness,
      if (contrast != null) 'contrast': contrast,
      if (saturation != null) 'saturation': saturation,
      if (gamma != null) 'gamma': gamma,
      'negate': negate,
      'audioCompressor': audioCompressor,
      // Special operations
      'extractThumbnail': extractThumbnail,
      if (thumbnailTimestamp != null) 'thumbnailTimestamp': thumbnailTimestamp,
      'extractSubtitles': extractSubtitles,
      if (subtitleTrackIndex != null) 'subtitleTrackIndex': subtitleTrackIndex,
      if (splitInterval != null) 'splitInterval': splitInterval,
      'concatWithTransition': concatWithTransition,
      if (transitionDuration != null) 'transitionDuration': transitionDuration,
    };
  }

  /// Deserialize from JSON string.
  factory ConversionConfig.fromJsonString(String jsonStr) {
    return ConversionConfig.fromJson(
        jsonDecode(jsonStr) as Map<String, dynamic>);
  }

  factory ConversionConfig.fromJson(Map<String, dynamic> json) {
    return ConversionConfig(
      outputFormat: OutputFormat.values.firstWhere(
        (f) => f.name == json['outputFormat'],
        orElse: () => OutputFormat.mp4,
      ),
      videoCodec: json['videoCodec'] != null
          ? VideoCodecOption.values.firstWhere(
              (c) => c.name == json['videoCodec'],
              orElse: () => VideoCodecOption.h264,
            )
          : null,
      videoBitrate: json['videoBitrate'] as int?,
      crf: json['crf'] as int?,
      encoderPreset: json['encoderPreset'] as String?,
      resolution: json['resolution'] != null
          ? ResolutionOption.values.firstWhere(
              (r) => r.name == json['resolution'],
              orElse: () => ResolutionOption.original,
            )
          : null,
      customWidth: json['customWidth'] as int?,
      customHeight: json['customHeight'] as int?,
      fps: json['fps'] as int?,
      audioCodec: json['audioCodec'] != null
          ? AudioCodecOption.values.firstWhere(
              (c) => c.name == json['audioCodec'],
              orElse: () => AudioCodecOption.aac,
            )
          : null,
      audioBitrate: json['audioBitrate'] as int?,
      audioSampleRate: json['audioSampleRate'] as int?,
      audioChannels: json['audioChannels'] as int?,
      hwAccel: json['hwAccel'] as bool? ?? false,
      twoPass: json['twoPass'] as bool? ?? false,
      normalize: json['normalize'] as bool? ?? false,
      trim: json['trim'] != null
          ? TrimRange.fromJson(json['trim'] as Map<String, dynamic>)
          : null,
      speed: (json['speed'] as num?)?.toDouble(),
      subtitlePath: json['subtitlePath'] as String?,
      watermarkPath: json['watermarkPath'] as String?,
      watermarkPosition: json['watermarkPosition'] != null
          ? WatermarkPosition.values.firstWhere(
              (w) => w.name == json['watermarkPosition'],
              orElse: () => WatermarkPosition.bottomRight,
            )
          : null,
      metadata: json['metadata'] != null
          ? Map<String, String>.from(json['metadata'] as Map)
          : null,
      extraArgs: json['extraArgs'] != null
          ? List<String>.from(json['extraArgs'] as List)
          : null,
      // Enhancement fields
      crop: json['crop'] != null
          ? CropConfig.fromJson(json['crop'] as Map<String, dynamic>)
          : null,
      rotate: json['rotate'] != null
          ? RotateOption.values.firstWhere(
              (r) => r.name == json['rotate'],
              orElse: () => RotateOption.cw90,
            )
          : null,
      removeAudio: json['removeAudio'] as bool? ?? false,
      removeVideo: json['removeVideo'] as bool? ?? false,
      textOverlay: json['textOverlay'] as String?,
      textOverlayConfig: json['textOverlayConfig'] != null
          ? TextOverlayConfig.fromJson(
              json['textOverlayConfig'] as Map<String, dynamic>)
          : null,
      lutPath: json['lutPath'] as String?,
      colorEffect: json['colorEffect'] as String?,
      denoise: json['denoise'] as bool? ?? false,
      denoiseStrength: json['denoiseStrength'] as String?,
      stabilize: json['stabilize'] as bool? ?? false,
      fadeIn: json['fadeIn'] as bool? ?? false,
      fadeOut: json['fadeOut'] as bool? ?? false,
      fadeDuration: (json['fadeDuration'] as num?)?.toDouble(),
      vignette: json['vignette'] as bool? ?? false,
      vignetteAngle: (json['vignetteAngle'] as num?)?.toDouble(),
      filmGrain: json['filmGrain'] as bool? ?? false,
      grainIntensity: (json['grainIntensity'] as num?)?.toDouble(),
      interpolate: json['interpolate'] as bool? ?? false,
      targetFps: json['targetFps'] as int?,
      concatFiles: json['concatFiles'] != null
          ? List<String>.from(json['concatFiles'] as List)
          : null,
      blurRegion: json['blurRegion'] != null
          ? BlurRegion.fromJson(json['blurRegion'] as Map<String, dynamic>)
          : null,
      pipConfig: json['pipConfig'] != null
          ? PipConfig.fromJson(json['pipConfig'] as Map<String, dynamic>)
          : null,
      splitScreen: json['splitScreen'] != null
          ? SplitScreenConfig.fromJson(
              json['splitScreen'] as Map<String, dynamic>)
          : null,
      // Advanced processing
      hdrToSdr: json['hdrToSdr'] as bool? ?? false,
      deinterlace: json['deinterlace'] as bool? ?? false,
      reverse: json['reverse'] as bool? ?? false,
      volumeDb: (json['volumeDb'] as num?)?.toDouble(),
      audioEqPreset: json['audioEqPreset'] as String?,
      channelLayout: json['channelLayout'] as String?,
      letterbox: json['letterbox'] as String?,
      loopCount: json['loopCount'] as int?,
      sharpen: json['sharpen'] as bool? ?? false,
      sharpenStrength: (json['sharpenStrength'] as num?)?.toDouble(),
      brightness: (json['brightness'] as num?)?.toDouble(),
      contrast: (json['contrast'] as num?)?.toDouble(),
      saturation: (json['saturation'] as num?)?.toDouble(),
      gamma: (json['gamma'] as num?)?.toDouble(),
      negate: json['negate'] as bool? ?? false,
      audioCompressor: json['audioCompressor'] as bool? ?? false,
      // Special operations
      extractThumbnail: json['extractThumbnail'] as bool? ?? false,
      thumbnailTimestamp: (json['thumbnailTimestamp'] as num?)?.toDouble(),
      extractSubtitles: json['extractSubtitles'] as bool? ?? false,
      subtitleTrackIndex: json['subtitleTrackIndex'] as int?,
      splitInterval: json['splitInterval'] as int?,
      concatWithTransition: json['concatWithTransition'] as bool? ?? false,
      transitionDuration: (json['transitionDuration'] as num?)?.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversionConfig &&
          runtimeType == other.runtimeType &&
          toJsonString() == other.toJsonString();

  @override
  int get hashCode => toJsonString().hashCode;
}
