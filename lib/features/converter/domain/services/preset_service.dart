import '../entities/conversion_config.dart';
import '../entities/conversion_preset.dart';
import '../entities/output_format.dart';

/// Registry of all built-in conversion presets.
///
/// Provides categorized preset lists for the UI and lookup by ID.
/// Free presets cover common use cases; premium presets unlock
/// device-specific, social media, advanced configurations,
/// enhancement, editing, and creative effects.
class PresetService {
  /// All built-in presets, ordered by category and popularity.
  List<ConversionPreset> get allPresets => [
        ..._freePresets,
        ..._premiumPresets,
      ];

  /// Free-tier presets available to all users.
  List<ConversionPreset> get freePresets => _freePresets;

  /// Premium-only presets requiring subscription.
  List<ConversionPreset> get premiumPresets => _premiumPresets;

  /// Get presets filtered by category.
  List<ConversionPreset> getByCategory(PresetCategory category) =>
      allPresets.where((p) => p.category == category).toList();

  /// Look up a preset by its unique ID. Returns null if not found.
  ConversionPreset? getById(String id) {
    for (final preset in allPresets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  // ────────────────────────────────────────────────────────────────
  // FREE PRESETS
  // ────────────────────────────────────────────────────────────────

  static final List<ConversionPreset> _freePresets = [
    // 1. MP4 Universal
    ConversionPreset(
      id: 'mp4_universal',
      name: 'MP4 Universal',
      icon: 'video_file',
      description: 'H.264 + AAC, works everywhere',
      category: PresetCategory.format,
      isPopular: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.aac,
        crf: 23,
        encoderPreset: 'medium',
        audioBitrate: 192,
      ),
    ),

    // 2. MP3 Audio
    ConversionPreset(
      id: 'mp3_audio',
      name: 'MP3 Audio',
      icon: 'music_note',
      description: 'Extract audio as MP3 320kbps',
      category: PresetCategory.audio,
      isPopular: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp3,
        videoCodec: VideoCodecOption.none,
        audioCodec: AudioCodecOption.mp3,
        audioBitrate: 320,
      ),
    ),

    // 3. MKV Remux
    ConversionPreset(
      id: 'mkv_remux',
      name: 'MKV Remux',
      icon: 'swap_horiz',
      description: 'Copy streams to MKV (instant, no quality loss)',
      category: PresetCategory.format,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mkv,
        videoCodec: VideoCodecOption.copy,
        audioCodec: AudioCodecOption.copy,
      ),
    ),

    // 4. 720p Compact
    ConversionPreset(
      id: '720p_compact',
      name: '720p Compact',
      icon: 'compress',
      description: 'H.264 720p for smaller file sizes',
      category: PresetCategory.format,
      isPopular: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.aac,
        crf: 23,
        encoderPreset: 'medium',
        resolution: ResolutionOption.p720,
        audioBitrate: 128,
      ),
    ),

    // 5. AAC Audio
    ConversionPreset(
      id: 'aac_audio',
      name: 'AAC Audio',
      icon: 'audiotrack',
      description: 'Extract audio as AAC 256kbps',
      category: PresetCategory.audio,
      config: const ConversionConfig(
        outputFormat: OutputFormat.m4a,
        videoCodec: VideoCodecOption.none,
        audioCodec: AudioCodecOption.aac,
        audioBitrate: 256,
      ),
    ),

    // 6. AVI Legacy
    //
    // Covers paid users (e.g. VidCombo Premium "Jordana" 2026-05-19 feedback)
    // who need AVI containers for legacy video editors, NLE timelines, or
    // older playback hardware that does not handle modern containers.
    // Safe defaults: H.264 video + MP3 audio (broadest legacy support);
    // CRF 23 preserves quality without runaway file size.
    ConversionPreset(
      id: 'avi_legacy',
      name: 'AVI Legacy',
      icon: 'video_file',
      description: 'H.264 + MP3 in AVI for legacy editors',
      category: PresetCategory.format,
      isPopular: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.avi,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.mp3,
        crf: 23,
        encoderPreset: 'medium',
        audioBitrate: 192,
      ),
    ),

    // 7. MP4 Mobile
    //
    // Smartphone-friendly: 480p H.264 + AAC 96 kbps, biased for size
    // (CRF 26) so the file fits cellular share constraints. Quick-row
    // companion to MP4 Universal / AVI Legacy.
    ConversionPreset(
      id: 'mp4_mobile',
      name: 'MP4 Mobile',
      icon: 'phone_iphone',
      description: 'H.264 480p compact for sharing',
      category: PresetCategory.format,
      isPopular: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.aac,
        resolution: ResolutionOption.p480,
        crf: 26,
        encoderPreset: 'medium',
        audioBitrate: 96,
      ),
    ),
  ];

  // ────────────────────────────────────────────────────────────────
  // PREMIUM PRESETS
  // ────────────────────────────────────────────────────────────────

  static final List<ConversionPreset> _premiumPresets = [
    // ── Device category ──

    // 6. iPhone/iPad
    ConversionPreset(
      id: 'iphone_ipad',
      name: 'iPhone / iPad',
      icon: 'phone_iphone',
      description: 'H.265 optimized for Apple devices',
      category: PresetCategory.device,
      isPremium: true,
      isPopular: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h265,
        audioCodec: AudioCodecOption.aac,
        crf: 22,
        audioBitrate: 192,
      ),
    ),

    // 7. Android
    ConversionPreset(
      id: 'android',
      name: 'Android',
      icon: 'phone_android',
      description: 'H.264 High Profile for Android devices',
      category: PresetCategory.device,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.aac,
        crf: 22,
        encoderPreset: 'medium',
        audioBitrate: 192,
      ),
    ),

    // ── Social category ──

    // 8. WhatsApp
    ConversionPreset(
      id: 'whatsapp',
      name: 'WhatsApp',
      icon: 'chat',
      description: 'H.264 720p optimized for 16MB limit',
      category: PresetCategory.social,
      isPremium: true,
      isPopular: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.aac,
        resolution: ResolutionOption.p720,
        videoBitrate: 1500,
        audioBitrate: 128,
        encoderPreset: 'medium',
      ),
    ),

    // 9. Instagram Story
    ConversionPreset(
      id: 'instagram_story',
      name: 'Instagram Story',
      icon: 'camera_alt',
      description: 'H.264 1080x1920 vertical for Stories',
      category: PresetCategory.social,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.aac,
        resolution: ResolutionOption.custom,
        customWidth: 1080,
        customHeight: 1920,
        crf: 22,
        encoderPreset: 'medium',
        audioBitrate: 128,
      ),
    ),

    // 10. YouTube Upload
    ConversionPreset(
      id: 'youtube_upload',
      name: 'YouTube Upload',
      icon: 'play_circle',
      description: 'H.264 High Profile, maximum quality',
      category: PresetCategory.social,
      isPremium: true,
      isPopular: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.aac,
        crf: 18,
        encoderPreset: 'slow',
        audioBitrate: 320,
      ),
    ),

    // 11. Discord (8MB)
    ConversionPreset(
      id: 'discord_8mb',
      name: 'Discord (8MB)',
      icon: 'forum',
      description: 'H.264 targeting 8MB file size limit',
      category: PresetCategory.social,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.aac,
        resolution: ResolutionOption.p480,
        videoBitrate: 800,
        audioBitrate: 96,
        encoderPreset: 'medium',
      ),
    ),

    // 12. Discord Nitro (50MB)
    ConversionPreset(
      id: 'discord_nitro',
      name: 'Discord Nitro (50MB)',
      icon: 'forum',
      description: 'H.264 targeting 50MB Nitro limit',
      category: PresetCategory.social,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.aac,
        resolution: ResolutionOption.p720,
        videoBitrate: 3000,
        audioBitrate: 192,
        encoderPreset: 'medium',
      ),
    ),

    // ── Format category (premium) ──

    // 13. Animated GIF
    ConversionPreset(
      id: 'animated_gif',
      name: 'Animated GIF',
      icon: 'gif',
      description: 'GIF with palette optimization, 15fps',
      category: PresetCategory.format,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.gif,
        fps: 15,
        resolution: ResolutionOption.p480,
      ),
    ),

    // 14. Animated WebP
    ConversionPreset(
      id: 'animated_webp',
      name: 'Animated WebP',
      icon: 'image',
      description: 'WebP animation, better quality than GIF',
      category: PresetCategory.format,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.webp,
        fps: 15,
        resolution: ResolutionOption.p480,
      ),
    ),

    // ── Audio category (premium) ──

    // 15. FLAC Lossless
    ConversionPreset(
      id: 'flac_lossless',
      name: 'FLAC Lossless',
      icon: 'high_quality',
      description: 'Lossless audio extraction',
      category: PresetCategory.audio,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.flac,
        videoCodec: VideoCodecOption.none,
        audioCodec: AudioCodecOption.flac,
      ),
    ),

    // 16. WAV Uncompressed
    ConversionPreset(
      id: 'wav_uncompressed',
      name: 'WAV Uncompressed',
      icon: 'graphic_eq',
      description: 'PCM audio, studio quality',
      category: PresetCategory.audio,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.wav,
        videoCodec: VideoCodecOption.none,
        audioCodec: AudioCodecOption.pcm,
      ),
    ),

    // ── Advanced category ──

    // 17. 4K HEVC
    ConversionPreset(
      id: '4k_hevc',
      name: '4K HEVC',
      icon: 'hd',
      description: 'H.265 2160p, premium quality',
      category: PresetCategory.advanced,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h265,
        audioCodec: AudioCodecOption.aac,
        resolution: ResolutionOption.p2160,
        crf: 20,
        encoderPreset: 'slow',
        audioBitrate: 256,
      ),
    ),

    // 18. AV1 Efficient
    ConversionPreset(
      id: 'av1_efficient',
      name: 'AV1 Efficient',
      icon: 'speed',
      description: 'AV1 codec, best compression ratio',
      category: PresetCategory.advanced,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mkv,
        videoCodec: VideoCodecOption.av1,
        audioCodec: AudioCodecOption.opus,
        crf: 30,
        encoderPreset: 'medium',
        audioBitrate: 128,
      ),
    ),

    // 19. Custom (placeholder — UI lets user configure everything)
    ConversionPreset(
      id: 'custom',
      name: 'Custom',
      icon: 'tune',
      description: 'Full manual control over all settings',
      category: PresetCategory.advanced,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
      ),
    ),

    // ════════════════════════════════════════════════════════════════
    // ENHANCE CATEGORY — Quick one-click enhancements
    // ════════════════════════════════════════════════════════════════

    ConversionPreset(
      id: 'denoise_light',
      name: '1-Click Denoise (Light)',
      icon: 'blur_off',
      description: 'Subtle noise reduction, preserves detail',
      category: PresetCategory.enhance,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.copy,
        crf: 18,
        denoise: true,
        denoiseStrength: 'light',
      ),
    ),

    ConversionPreset(
      id: 'denoise_strong',
      name: '1-Click Denoise (Strong)',
      icon: 'blur_off',
      description: 'Aggressive noise removal for low-light footage',
      category: PresetCategory.enhance,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.copy,
        crf: 18,
        denoise: true,
        denoiseStrength: 'strong',
      ),
    ),

    ConversionPreset(
      id: 'stabilize',
      name: '1-Click Stabilize',
      icon: 'stay_current_portrait',
      description: 'Smooth out shaky handheld footage',
      category: PresetCategory.enhance,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.copy,
        crf: 18,
        stabilize: true,
      ),
    ),

    ConversionPreset(
      id: 'audio_normalize',
      name: 'Audio Normalize',
      icon: 'equalizer',
      description: 'Copy video, normalize audio loudness',
      category: PresetCategory.enhance,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.copy,
        audioCodec: AudioCodecOption.aac,
        audioBitrate: 192,
        normalize: true,
      ),
    ),

    ConversionPreset(
      id: 'remove_audio',
      name: 'Remove Audio',
      icon: 'volume_off',
      description: 'Strip audio track, keep video only',
      category: PresetCategory.enhance,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.copy,
        removeAudio: true,
      ),
    ),

    // ════════════════════════════════════════════════════════════════
    // EDIT CATEGORY — Transform operations
    // ════════════════════════════════════════════════════════════════

    ConversionPreset(
      id: 'rotate_cw90',
      name: 'Rotate 90\u00B0 CW',
      icon: 'rotate_right',
      description: 'Rotate clockwise by 90 degrees',
      category: PresetCategory.edit,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.copy,
        crf: 18,
        rotate: RotateOption.cw90,
      ),
    ),

    ConversionPreset(
      id: 'rotate_ccw90',
      name: 'Rotate 90\u00B0 CCW',
      icon: 'rotate_left',
      description: 'Rotate counter-clockwise by 90 degrees',
      category: PresetCategory.edit,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.copy,
        crf: 18,
        rotate: RotateOption.ccw90,
      ),
    ),

    ConversionPreset(
      id: 'rotate_180',
      name: 'Rotate 180\u00B0',
      icon: 'screen_rotation',
      description: 'Flip video upside down',
      category: PresetCategory.edit,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.copy,
        crf: 18,
        rotate: RotateOption.rotate180,
      ),
    ),

    ConversionPreset(
      id: 'flip_horizontal',
      name: 'Flip Horizontal',
      icon: 'flip',
      description: 'Mirror the video horizontally',
      category: PresetCategory.edit,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.copy,
        crf: 18,
        rotate: RotateOption.flipH,
      ),
    ),

    ConversionPreset(
      id: 'flip_vertical',
      name: 'Flip Vertical',
      icon: 'flip',
      description: 'Mirror the video vertically',
      category: PresetCategory.edit,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.copy,
        crf: 18,
        rotate: RotateOption.flipV,
      ),
    ),

    ConversionPreset(
      id: 'merge_join',
      name: 'Merge / Join',
      icon: 'merge_type',
      description: 'Concatenate multiple files into one',
      category: PresetCategory.edit,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.copy,
        audioCodec: AudioCodecOption.copy,
      ),
    ),

    ConversionPreset(
      id: 'crop_custom',
      name: 'Crop',
      icon: 'crop',
      description: 'Crop video to custom region',
      category: PresetCategory.edit,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.copy,
        crf: 18,
      ),
    ),

    // ════════════════════════════════════════════════════════════════
    // CREATIVE CATEGORY — Visual effects
    // ════════════════════════════════════════════════════════════════

    ConversionPreset(
      id: 'cinematic_fade',
      name: 'Cinematic Fade',
      icon: 'gradient',
      description: 'Fade in 1s + fade out 1s',
      category: PresetCategory.creative,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.aac,
        crf: 18,
        audioBitrate: 192,
        fadeIn: true,
        fadeOut: true,
        fadeDuration: 1.0,
      ),
    ),

    ConversionPreset(
      id: 'vignette',
      name: 'Vignette',
      icon: 'vignette',
      description: 'Dark edges, cinematic look',
      category: PresetCategory.creative,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.copy,
        crf: 18,
        vignette: true,
      ),
    ),

    ConversionPreset(
      id: 'film_grain',
      name: 'Film Grain',
      icon: 'grain',
      description: 'Vintage analog film texture',
      category: PresetCategory.creative,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.copy,
        crf: 18,
        filmGrain: true,
        grainIntensity: 30,
      ),
    ),

    ConversionPreset(
      id: 'slow_motion_05x',
      name: 'Slow Motion 0.5x',
      icon: 'slow_motion_video',
      description: 'Half speed slow motion',
      category: PresetCategory.creative,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.aac,
        crf: 18,
        audioBitrate: 192,
        speed: 0.5,
      ),
    ),

    ConversionPreset(
      id: 'fast_forward_2x',
      name: 'Fast Forward 2x',
      icon: 'fast_forward',
      description: 'Double speed timelapse',
      category: PresetCategory.creative,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.aac,
        crf: 18,
        audioBitrate: 192,
        speed: 2.0,
      ),
    ),

    ConversionPreset(
      id: 'smooth_60fps',
      name: 'Smooth 60fps',
      icon: 'animation',
      description: 'Frame interpolation to 60fps (slow)',
      category: PresetCategory.creative,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.copy,
        crf: 18,
        interpolate: true,
        targetFps: 60,
      ),
    ),

    // ── Color grading presets (using ffmpeg filter chains instead of .cube LUTs) ──

    ConversionPreset(
      id: 'lut_warm_sunset',
      name: 'LUT: Warm Sunset',
      icon: 'wb_sunny',
      description: 'Warm golden tones',
      category: PresetCategory.creative,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.copy,
        crf: 18,
        colorEffect: 'colorbalance=rs=.1:gs=-.05:bs=-.1:rh=.1:gh=.05:bh=-.05',
      ),
    ),

    ConversionPreset(
      id: 'lut_cool_blue',
      name: 'LUT: Cool Blue',
      icon: 'ac_unit',
      description: 'Cool blue cinematic tones',
      category: PresetCategory.creative,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.copy,
        crf: 18,
        colorEffect: 'colorbalance=rs=-.1:gs=0:bs=.15:rh=-.05:gh=.05:bh=.1',
      ),
    ),

    ConversionPreset(
      id: 'lut_vintage_film',
      name: 'LUT: Vintage Film',
      icon: 'filter_vintage',
      description: 'Desaturated retro film look',
      category: PresetCategory.creative,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.copy,
        crf: 18,
        colorEffect: 'curves=vintage',
      ),
    ),

    ConversionPreset(
      id: 'lut_high_contrast',
      name: 'LUT: High Contrast',
      icon: 'contrast',
      description: 'Punchy, vibrant colors',
      category: PresetCategory.creative,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.copy,
        crf: 18,
        colorEffect: 'eq=contrast=1.3:brightness=0.05:saturation=1.2',
      ),
    ),

    // ────────────────────────────────────────────────────────────────
    // ADVANCED PROCESSING — ENHANCE
    // ────────────────────────────────────────────────────────────────

    // HDR → SDR
    ConversionPreset(
      id: 'hdr_to_sdr',
      name: 'HDR → SDR',
      icon: 'hdr_off',
      description: 'Tone map HDR to standard displays',
      category: PresetCategory.enhance,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.copy,
        crf: 18,
        hdrToSdr: true,
      ),
    ),

    // Deinterlace
    ConversionPreset(
      id: 'deinterlace',
      name: 'Deinterlace',
      icon: 'deblur',
      description: 'Fix interlacing artifacts (old TV content)',
      category: PresetCategory.enhance,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.copy,
        crf: 18,
        deinterlace: true,
      ),
    ),

    // Sharpen Light
    ConversionPreset(
      id: 'sharpen_light',
      name: 'Sharpen Light',
      icon: 'blur_off',
      description: 'Subtle clarity improvement',
      category: PresetCategory.enhance,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.copy,
        crf: 18,
        sharpen: true,
        sharpenStrength: 0.8,
      ),
    ),

    // Sharpen Strong
    ConversionPreset(
      id: 'sharpen_strong',
      name: 'Sharpen Strong',
      icon: 'blur_off',
      description: 'Aggressive edge sharpening',
      category: PresetCategory.enhance,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.copy,
        crf: 18,
        sharpen: true,
        sharpenStrength: 1.8,
      ),
    ),

    // Auto Brightness
    ConversionPreset(
      id: 'auto_brightness',
      name: 'Auto Brightness',
      icon: 'brightness_auto',
      description: 'Optimize brightness & contrast',
      category: PresetCategory.enhance,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.copy,
        crf: 18,
        brightness: 0.06,
        contrast: 1.15,
        saturation: 1.1,
      ),
    ),

    // Night Mode (brighten dark videos)
    ConversionPreset(
      id: 'night_mode',
      name: 'Night Mode',
      icon: 'nightlight',
      description: 'Brighten dark/underexposed videos',
      category: PresetCategory.enhance,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.copy,
        crf: 18,
        brightness: 0.15,
        gamma: 1.8,
        contrast: 1.1,
      ),
    ),

    // ────────────────────────────────────────────────────────────────
    // ADVANCED PROCESSING — AUDIO
    // ────────────────────────────────────────────────────────────────

    // Volume Boost +3dB
    ConversionPreset(
      id: 'volume_boost_3',
      name: 'Volume +3 dB',
      icon: 'volume_up',
      description: 'Moderately louder audio',
      category: PresetCategory.audio,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.copy,
        audioCodec: AudioCodecOption.aac,
        audioBitrate: 192,
        volumeDb: 3.0,
      ),
    ),

    // Volume Boost +6dB
    ConversionPreset(
      id: 'volume_boost_6',
      name: 'Volume +6 dB',
      icon: 'volume_up',
      description: 'Significantly louder audio',
      category: PresetCategory.audio,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.copy,
        audioCodec: AudioCodecOption.aac,
        audioBitrate: 192,
        volumeDb: 6.0,
      ),
    ),

    // Volume Reduce -3dB
    ConversionPreset(
      id: 'volume_reduce_3',
      name: 'Volume -3 dB',
      icon: 'volume_down',
      description: 'Moderately quieter audio',
      category: PresetCategory.audio,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.copy,
        audioCodec: AudioCodecOption.aac,
        audioBitrate: 192,
        volumeDb: -3.0,
      ),
    ),

    // Bass Boost
    ConversionPreset(
      id: 'bass_boost',
      name: 'Bass Boost',
      icon: 'speaker',
      description: 'Enhanced low-frequency audio',
      category: PresetCategory.audio,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.copy,
        audioCodec: AudioCodecOption.aac,
        audioBitrate: 192,
        audioEqPreset: 'bass_boost',
      ),
    ),

    // Treble Boost
    ConversionPreset(
      id: 'treble_boost',
      name: 'Treble Boost',
      icon: 'speaker',
      description: 'Enhanced high-frequency clarity',
      category: PresetCategory.audio,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.copy,
        audioCodec: AudioCodecOption.aac,
        audioBitrate: 192,
        audioEqPreset: 'treble_boost',
      ),
    ),

    // Voice Enhance
    ConversionPreset(
      id: 'voice_enhance',
      name: 'Voice Enhance',
      icon: 'record_voice_over',
      description: 'Optimize speech clarity',
      category: PresetCategory.audio,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.copy,
        audioCodec: AudioCodecOption.aac,
        audioBitrate: 192,
        audioEqPreset: 'voice_enhance',
      ),
    ),

    // Cinema Audio
    ConversionPreset(
      id: 'cinema_audio',
      name: 'Cinema Audio',
      icon: 'movie',
      description: 'Warm cinematic sound profile',
      category: PresetCategory.audio,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.copy,
        audioCodec: AudioCodecOption.aac,
        audioBitrate: 192,
        audioEqPreset: 'cinema',
      ),
    ),

    // Podcast Optimize
    ConversionPreset(
      id: 'podcast_optimize',
      name: 'Podcast Optimize',
      icon: 'podcasts',
      description: 'Optimize for voice/podcast content',
      category: PresetCategory.audio,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp3,
        audioCodec: AudioCodecOption.mp3,
        audioBitrate: 128,
        audioEqPreset: 'podcast',
      ),
    ),

    // Audio Compressor
    ConversionPreset(
      id: 'audio_compressor',
      name: 'Audio Compressor',
      icon: 'compress',
      description: 'Reduce dynamic range (even volume)',
      category: PresetCategory.audio,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.copy,
        audioCodec: AudioCodecOption.aac,
        audioBitrate: 192,
        audioCompressor: true,
      ),
    ),

    // ────────────────────────────────────────────────────────────────
    // ADVANCED PROCESSING — EDIT
    // ────────────────────────────────────────────────────────────────

    // 5.1 → Stereo
    ConversionPreset(
      id: 'surround_to_stereo',
      name: '5.1 → Stereo',
      icon: 'surround_sound',
      description: 'Downmix surround to stereo',
      category: PresetCategory.edit,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.copy,
        audioCodec: AudioCodecOption.aac,
        audioBitrate: 192,
        channelLayout: '5.1_to_stereo',
      ),
    ),

    // Stereo → Mono
    ConversionPreset(
      id: 'stereo_to_mono',
      name: 'Stereo → Mono',
      icon: 'speaker',
      description: 'Merge stereo to single channel',
      category: PresetCategory.edit,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.copy,
        audioCodec: AudioCodecOption.aac,
        audioBitrate: 128,
        channelLayout: 'mono',
      ),
    ),

    // Letterbox 16:9
    ConversionPreset(
      id: 'letterbox_16_9',
      name: 'Letterbox 16:9',
      icon: 'fit_screen',
      description: 'Add black bars for 16:9 display',
      category: PresetCategory.edit,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.copy,
        crf: 18,
        letterbox: '16:9',
      ),
    ),

    // Letterbox 21:9 (Cinematic)
    ConversionPreset(
      id: 'letterbox_21_9',
      name: 'Letterbox 21:9',
      icon: 'fit_screen',
      description: 'Cinematic ultra-wide letterbox',
      category: PresetCategory.edit,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.copy,
        crf: 18,
        letterbox: '21:9',
      ),
    ),

    // Trim / Cut
    ConversionPreset(
      id: 'trim_cut',
      name: 'Trim / Cut',
      icon: 'content_cut',
      description: 'Extract a segment from the video',
      category: PresetCategory.edit,
      isPremium: false,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.copy,
        audioCodec: AudioCodecOption.copy,
      ),
    ),

    // Watermark / Image Overlay
    ConversionPreset(
      id: 'watermark',
      name: 'Watermark',
      icon: 'branding_watermark',
      description: 'Overlay image on video',
      category: PresetCategory.edit,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.copy,
        crf: 18,
      ),
    ),

    // Burn-in Subtitles
    ConversionPreset(
      id: 'burn_subtitles',
      name: 'Burn Subtitles',
      icon: 'subtitles',
      description: 'Hardcode subtitles into video',
      category: PresetCategory.edit,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.copy,
        crf: 18,
      ),
    ),

    // ────────────────────────────────────────────────────────────────
    // ADVANCED PROCESSING — CREATIVE
    // ────────────────────────────────────────────────────────────────

    // Reverse Video
    ConversionPreset(
      id: 'reverse_video',
      name: 'Reverse Video',
      icon: 'replay',
      description: 'Play video backwards (loads into memory)',
      category: PresetCategory.creative,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.aac,
        crf: 18,
        audioBitrate: 192,
        reverse: true,
      ),
    ),

    // Negate / Invert Colors
    ConversionPreset(
      id: 'negate_colors',
      name: 'Invert Colors',
      icon: 'invert_colors',
      description: 'Negative/inverted color effect',
      category: PresetCategory.creative,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.copy,
        crf: 18,
        negate: true,
      ),
    ),

    // Loop 2x
    ConversionPreset(
      id: 'loop_2x',
      name: 'Loop 2x',
      icon: 'loop',
      description: 'Repeat video 2 times',
      category: PresetCategory.creative,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.aac,
        crf: 18,
        audioBitrate: 192,
        loopCount: 2,
      ),
    ),

    // Loop 3x
    ConversionPreset(
      id: 'loop_3x',
      name: 'Loop 3x',
      icon: 'loop',
      description: 'Repeat video 3 times',
      category: PresetCategory.creative,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4,
        videoCodec: VideoCodecOption.h264,
        audioCodec: AudioCodecOption.aac,
        crf: 18,
        audioBitrate: 192,
        loopCount: 3,
      ),
    ),

    // ────────────────────────────────────────────────────────────────
    // TOOLS — Special Operations
    // ────────────────────────────────────────────────────────────────

    // Extract Thumbnail
    ConversionPreset(
      id: 'extract_thumbnail',
      name: 'Extract Thumbnail',
      icon: 'photo_camera',
      description: 'Save a single frame as image',
      category: PresetCategory.tools,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4, // overridden by special operation
        extractThumbnail: true,
        thumbnailTimestamp: 0.0,
      ),
    ),

    // Extract Subtitles
    ConversionPreset(
      id: 'extract_subtitles',
      name: 'Extract Subtitles',
      icon: 'subtitles',
      description: 'Save embedded subtitles as .srt',
      category: PresetCategory.tools,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4, // overridden by special operation
        extractSubtitles: true,
        subtitleTrackIndex: 0,
      ),
    ),

    // Split Video
    ConversionPreset(
      id: 'split_video',
      name: 'Split Video',
      icon: 'content_cut',
      description: 'Split into segments by interval',
      category: PresetCategory.tools,
      isPremium: true,
      config: const ConversionConfig(
        outputFormat: OutputFormat.mp4, // overridden
        splitInterval: 60, // 60 second segments default
      ),
    ),
  ];
}
