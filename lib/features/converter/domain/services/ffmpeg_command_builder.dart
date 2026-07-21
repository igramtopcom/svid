import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../core/logging/app_logger.dart';
import '../entities/conversion_config.dart';
import '../entities/hw_accel_info.dart';
import '../entities/output_format.dart';

/// Builds ffmpeg command-line arguments from a [ConversionConfig].
///
/// This is the core engine of the converter feature. It translates the
/// high-level ConversionConfig into the precise sequence of ffmpeg arguments
/// needed to perform the conversion, handling:
///
/// - Format conversion (container remux and transcoding)
/// - Video/audio codec selection with quality controls
/// - Resolution scaling, FPS change, speed change
/// - Hardware acceleration (VideoToolbox, NVENC, VAAPI, QSV)
/// - Audio normalization, subtitle burn-in, watermarks
/// - Trimming, two-pass encoding, GIF/WebP animation
/// - MP4 faststart, metadata injection
/// - Crop, rotate, denoise, text overlay, color grading
/// - Fade in/out, vignette, film grain, frame interpolation
/// - Blur/pixelate regions, PiP, split screen, concatenation
class FFmpegCommandBuilder {
  /// Cached HW accel capabilities (set by caller before building commands)
  List<HwAccelInfo>? _hwAccelCapabilities;

  void setHwAccelCapabilities(List<HwAccelInfo> capabilities) {
    _hwAccelCapabilities = capabilities;
  }

  /// Build the complete ffmpeg argument list for a single-pass conversion
  /// (or pass 2 of a two-pass conversion).
  ///
  /// Returns a list of argument strings suitable for Process.start().
  /// For two-pass encoding, call [buildTwoPassArgs] instead.
  List<String> buildArgs({
    required String inputPath,
    required String outputPath,
    required ConversionConfig config,
    Duration? inputDuration,
  }) {
    // For two-pass, delegate to the two-pass builder
    if (config.twoPass && !config.isAudioOnly && !config.isStreamCopy) {
      // Return pass 2 args (caller should have run pass 1 first)
      return _buildTwoPassArgs(
        inputPath: inputPath,
        outputPath: outputPath,
        config: config,
        passNumber: 2,
      );
    }

    return _buildSinglePassArgs(
      inputPath: inputPath,
      outputPath: outputPath,
      config: config,
      inputDuration: inputDuration,
    );
  }

  /// Build argument lists for two-pass encoding.
  ///
  /// Returns a list of two argument lists: [pass1Args, pass2Args].
  /// Pass 1 analyzes the video (outputs to /dev/null or NUL).
  /// Pass 2 produces the actual output file.
  List<List<String>> buildTwoPassArgs({
    required String inputPath,
    required String outputPath,
    required ConversionConfig config,
  }) {
    return [
      _buildTwoPassArgs(
        inputPath: inputPath,
        outputPath: outputPath,
        config: config,
        passNumber: 1,
      ),
      _buildTwoPassArgs(
        inputPath: inputPath,
        outputPath: outputPath,
        config: config,
        passNumber: 2,
      ),
    ];
  }

  /// Build stabilization args (2-pass vidstab).
  ///
  /// Returns [pass1Args, pass2Args].
  /// Pass 1: detect motion → write transforms.trf file
  /// Pass 2: apply transforms → produce output
  List<List<String>> buildStabilizationArgs({
    required String inputPath,
    required String outputPath,
    required ConversionConfig config,
    required String transformsPath,
  }) {
    // Pass 1: detect motion
    final pass1 = <String>['-y'];
    if (config.trim != null) {
      pass1.addAll(['-ss', _formatMs(config.trim!.startMs)]);
    }
    pass1.addAll(['-i', inputPath]);
    if (config.trim != null) {
      final durationMs = config.trim!.endMs - config.trim!.startMs;
      pass1.addAll(['-t', _formatMs(durationMs)]);
    }
    pass1.addAll([
      '-vf',
      'vidstabdetect=shakiness=5:accuracy=15:result=$transformsPath',
      '-f',
      'null',
      Platform.isWindows ? 'NUL' : '/dev/null',
    ]);

    // Pass 2: apply transforms with other filters
    final pass2 = <String>['-y'];
    if (config.trim != null) {
      pass2.addAll(['-ss', _formatMs(config.trim!.startMs)]);
    }
    pass2.addAll(['-i', inputPath]);
    if (config.trim != null) {
      final durationMs = config.trim!.endMs - config.trim!.startMs;
      pass2.addAll(['-t', _formatMs(durationMs)]);
    }

    final videoFilters = <String>[];
    videoFilters.add(
      'vidstabtransform=smoothing=10:input=$transformsPath',
    );

    // Add any other enhancement video filters after stabilization
    _addEnhancementVideoFilters(videoFilters, config);
    _addVideoFilters(videoFilters, config);

    if (videoFilters.isNotEmpty) {
      pass2.addAll(['-vf', videoFilters.join(',')]);
    }

    // Stabilization requires re-encoding — force h264 if copy was selected
    final effectiveConfig = config.videoCodec == VideoCodecOption.copy
        ? config.copyWith(videoCodec: VideoCodecOption.h264, crf: 18)
        : config;

    _addVideoCodecArgs(pass2, effectiveConfig);
    pass2.addAll(['-c:a', 'copy']);

    if (config.outputFormat == OutputFormat.mp4 ||
        config.outputFormat == OutputFormat.mov ||
        config.outputFormat == OutputFormat.m4a) {
      pass2.addAll(['-movflags', '+faststart']);
    }

    pass2.add(outputPath);

    return [pass1, pass2];
  }

  /// Build concat args using the concat demuxer (fast, same codec).
  ///
  /// [concatListPath] must be a file containing lines like:
  /// file 'path1'
  /// file 'path2'
  List<String> buildConcatDemuxerArgs({
    required String outputPath,
    required String concatListPath,
  }) {
    return [
      '-y',
      '-f', 'concat',
      '-safe', '0',
      '-i', concatListPath,
      '-c', 'copy',
      outputPath,
    ];
  }

  /// Build concat args using filter_complex (different codecs, re-encode).
  List<String> buildConcatFilterArgs({
    required List<String> inputFiles,
    required String outputPath,
    required ConversionConfig config,
  }) {
    final args = <String>['-y'];
    for (final file in inputFiles) {
      args.addAll(['-i', file]);
    }

    final n = inputFiles.length;
    final filterInputs = List.generate(n, (i) => '[$i:v][$i:a]').join();
    args.addAll([
      '-filter_complex',
      '${filterInputs}concat=n=$n:v=1:a=1[v][a]',
      '-map', '[v]',
      '-map', '[a]',
    ]);

    // Add output codec settings from config
    _addVideoCodecArgs(args, config);
    _addAudioCodecArgs(args, config);

    if (config.outputFormat == OutputFormat.mp4 ||
        config.outputFormat == OutputFormat.mov) {
      args.addAll(['-movflags', '+faststart']);
    }

    args.add(outputPath);
    return args;
  }

  List<String> _buildSinglePassArgs({
    required String inputPath,
    required String outputPath,
    required ConversionConfig config,
    Duration? inputDuration,
  }) {
    final args = <String>['-y']; // Overwrite output

    // ── Trim: pre-input seek (fast seek with -ss before -i) ──
    if (config.trim != null) {
      args.addAll(['-ss', _formatMs(config.trim!.startMs)]);
    }

    // ── Input file ──
    args.addAll(['-i', inputPath]);

    // ── Trim: end point ──
    if (config.trim != null) {
      final durationMs = config.trim!.endMs - config.trim!.startMs;
      args.addAll(['-t', _formatMs(durationMs)]);
    }

    // ── PiP overlay input ──
    if (config.pipConfig != null) {
      args.addAll(['-i', config.pipConfig!.overlayPath]);
    }
    // ── Watermark input ──
    else if (config.watermarkPath != null && config.watermarkPosition != null) {
      args.addAll(['-i', config.watermarkPath!]);
    }

    // ── Handle special formats ──
    if (config.outputFormat == OutputFormat.gif) {
      _addGifArgs(args, config, outputPath);
      return args;
    }
    if (config.outputFormat == OutputFormat.webp && !config.isAudioOnly) {
      _addAnimatedWebpArgs(args, config, outputPath);
      return args;
    }

    // ── Remove audio flag ──
    if (config.removeAudio) {
      args.add('-an');
    }

    // ── Remove video flag (audio-only output) ──
    if (config.removeVideo) {
      args.add('-vn');
    }

    // ── Build filter chains ──
    final videoFilters = <String>[];
    final audioFilters = <String>[];

    // Determine if we need filter_complex
    final useFilterComplex = config.needsFilterComplex;

    // Video filters (order matters: crop → scale → denoise → effects → drawtext → overlay)
    if (!config.isAudioOnly && config.videoCodec != VideoCodecOption.copy &&
        !config.removeVideo) {
      // Crop first (before any scaling)
      if (config.crop != null) {
        videoFilters.add(
          'crop=${config.crop!.width}:${config.crop!.height}:${config.crop!.x}:${config.crop!.y}',
        );
      }

      // Rotation / flip
      if (config.rotate != null) {
        videoFilters.addAll(_buildRotateFilters(config.rotate!));
      }

      // Resolution scaling (after crop)
      _addVideoFilters(videoFilters, config);

      // Deinterlace (before denoise for cleaner input)
      if (config.deinterlace) {
        videoFilters.add('yadif=0:-1:0');
      }

      // Denoise
      if (config.denoise) {
        videoFilters.add(_buildDenoiseFilter(config.denoiseStrength));
      }

      // Sharpen (after denoise to avoid amplifying noise)
      if (config.sharpen) {
        final strength = config.sharpenStrength ?? 1.0;
        // unsharp: luma_msize_x:luma_msize_y:luma_amount
        videoFilters.add('unsharp=5:5:${strength.toStringAsFixed(2)}');
      }

      // HDR → SDR tone mapping
      if (config.hdrToSdr) {
        videoFilters.add(
          'zscale=t=linear:npl=100,format=gbrpf32le,'
          'zscale=p=bt709,tonemap=hable:desat=0,'
          'zscale=t=bt709:m=bt709:r=tv,format=yuv420p',
        );
      }

      // Brightness / Contrast / Saturation / Gamma (eq filter)
      if (config.brightness != null || config.contrast != null ||
          config.saturation != null || config.gamma != null) {
        videoFilters.add(_buildEqFilter(config));
      }

      // Negate (invert colors)
      if (config.negate) {
        videoFilters.add('negate');
      }

      // Frame interpolation
      if (config.interpolate && config.targetFps != null) {
        videoFilters.add(
          'minterpolate=fps=${config.targetFps}:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1',
        );
      }

      // Color grading / LUT
      if (config.lutPath != null) {
        final escapedPath = _escapeFilterPath(config.lutPath!);
        videoFilters.add("lut3d='$escapedPath'");
      } else if (config.colorEffect != null) {
        videoFilters.add(config.colorEffect!);
      }

      // Vignette
      if (config.vignette) {
        final angle = config.vignetteAngle ?? 0.6283; // PI/5
        videoFilters.add('vignette=angle=$angle');
      }

      // Film grain
      if (config.filmGrain) {
        final intensity = (config.grainIntensity ?? 30).clamp(5, 80).round();
        videoFilters.add('noise=c0s=$intensity:c0f=t+u');
      }

      // Letterbox / Pillarbox (pad to target aspect ratio)
      if (config.letterbox != null) {
        videoFilters.add(_buildLetterboxFilter(config.letterbox!));
      }

      // Fade in (video)
      if (config.fadeIn) {
        final duration = config.fadeDuration ?? 1.0;
        videoFilters.add('fade=t=in:st=0:d=$duration');
      }

      // Fade out (video) — needs input duration
      if (config.fadeOut && inputDuration != null) {
        final duration = config.fadeDuration ?? 1.0;
        final startTime = inputDuration.inMilliseconds / 1000.0 - duration;
        if (startTime > 0) {
          videoFilters.add(
            'fade=t=out:st=${startTime.toStringAsFixed(3)}:d=$duration',
          );
        }
      }

      // Text overlay (drawtext) — near the end so it's on top
      if (config.textOverlay != null && config.textOverlay!.isNotEmpty) {
        videoFilters.add(_buildDrawtextFilter(
          config.textOverlay!,
          config.textOverlayConfig ?? const TextOverlayConfig(),
        ));
      }

      // Subtitle burn-in
      if (config.subtitlePath != null) {
        final escapedPath = _escapeFilterPath(config.subtitlePath!);
        videoFilters.add("subtitles='$escapedPath'");
      }
    }

    // Speed change
    if (config.speed != null && config.speed != 1.0) {
      if (!config.isAudioOnly && config.videoCodec != VideoCodecOption.copy &&
          !config.removeVideo) {
        videoFilters.add('setpts=${(1.0 / config.speed!).toStringAsFixed(6)}*PTS');
      }
      if (config.audioCodec != AudioCodecOption.copy &&
          config.audioCodec != AudioCodecOption.none &&
          !config.removeAudio) {
        audioFilters.addAll(_buildAtempoChain(config.speed!));
      }
    }

    // Reverse video + audio
    if (config.reverse) {
      if (!config.isAudioOnly && config.videoCodec != VideoCodecOption.copy &&
          !config.removeVideo) {
        videoFilters.add('reverse');
      }
      if (config.audioCodec != AudioCodecOption.copy &&
          config.audioCodec != AudioCodecOption.none &&
          !config.removeAudio) {
        audioFilters.add('areverse');
      }
    }

    // Audio normalization
    if (config.normalize &&
        config.audioCodec != AudioCodecOption.copy &&
        config.audioCodec != AudioCodecOption.none &&
        !config.removeAudio) {
      audioFilters.add('loudnorm=I=-16:TP=-1.5:LR=11');
    }

    // Volume adjustment
    if (config.volumeDb != null && config.volumeDb != 0.0 &&
        config.audioCodec != AudioCodecOption.copy &&
        config.audioCodec != AudioCodecOption.none &&
        !config.removeAudio) {
      audioFilters.add('volume=${config.volumeDb!.toStringAsFixed(1)}dB');
    }

    // Audio EQ preset
    if (config.audioEqPreset != null &&
        config.audioCodec != AudioCodecOption.copy &&
        config.audioCodec != AudioCodecOption.none &&
        !config.removeAudio) {
      audioFilters.add(_buildAudioEqFilter(config.audioEqPreset!));
    }

    // Audio dynamic range compression
    if (config.audioCompressor &&
        config.audioCodec != AudioCodecOption.copy &&
        config.audioCodec != AudioCodecOption.none &&
        !config.removeAudio) {
      audioFilters.add(
        'compand=attacks=0:points=-80/-900|-45/-15|-27/-9|0/-7|20/-7:gain=5',
      );
    }

    // Audio fade in/out
    if (!config.removeAudio &&
        config.audioCodec != AudioCodecOption.copy &&
        config.audioCodec != AudioCodecOption.none) {
      if (config.fadeIn) {
        final duration = config.fadeDuration ?? 1.0;
        audioFilters.add('afade=t=in:st=0:d=$duration');
      }
      if (config.fadeOut && inputDuration != null) {
        final duration = config.fadeDuration ?? 1.0;
        final startTime = inputDuration.inMilliseconds / 1000.0 - duration;
        if (startTime > 0) {
          audioFilters.add(
            'afade=t=out:st=${startTime.toStringAsFixed(3)}:d=$duration',
          );
        }
      }
    }

    // ── Apply filters ──
    if (useFilterComplex && !config.removeVideo) {
      // Complex filter graph needed
      final filterComplex = _buildFilterComplex(
        config: config,
        videoFilters: videoFilters,
        inputDuration: inputDuration,
      );
      args.addAll(['-filter_complex', filterComplex]);

      // Map the output streams from filter_complex
      args.addAll(['-map', '[vout]']);
      if (!config.removeAudio) {
        if (audioFilters.isNotEmpty) {
          args.addAll(['-af', audioFilters.join(',')]);
          args.addAll(['-map', '0:a?']);
        } else {
          args.addAll(['-map', '0:a?']);
        }
      }
    } else {
      // Simple filter chains
      if (config.watermarkPath != null &&
          config.watermarkPosition != null &&
          !config.removeVideo) {
        // Watermark requires filter_complex even without other multi-input filters
        final overlayExpr = config.watermarkPosition!.overlayExpression;
        final vfChain = videoFilters.isNotEmpty ? ',${videoFilters.join(',')}' : '';
        args.addAll([
          '-filter_complex',
          '[0:v][1:v]$overlayExpr$vfChain',
        ]);
      } else {
        if (videoFilters.isNotEmpty && !config.removeVideo) {
          args.addAll(['-vf', videoFilters.join(',')]);
        }
      }
      if (audioFilters.isNotEmpty && !config.removeAudio) {
        args.addAll(['-af', audioFilters.join(',')]);
      }
    }

    // ── Video codec ──
    if (!config.removeVideo) {
      _addVideoCodecArgs(args, config);
    }

    // ── Audio codec ──
    if (!config.removeAudio) {
      _addAudioCodecArgs(args, config);
    }

    // ── MP4 faststart ──
    if (config.outputFormat == OutputFormat.mp4 ||
        config.outputFormat == OutputFormat.mov ||
        config.outputFormat == OutputFormat.m4a) {
      args.addAll(['-movflags', '+faststart']);
    }

    // ── Metadata ──
    if (config.metadata != null) {
      for (final entry in config.metadata!.entries) {
        args.addAll(['-metadata', '${entry.key}=${entry.value}']);
      }
    }

    // ── Channel layout ──
    if (config.channelLayout != null && !config.removeAudio &&
        config.audioCodec != AudioCodecOption.copy) {
      switch (config.channelLayout) {
        case 'mono':
          args.addAll(['-ac', '1']);
          break;
        case 'stereo':
          args.addAll(['-ac', '2']);
          break;
        case '5.1_to_stereo':
          args.addAll(['-ac', '2']);
          break;
      }
    }

    // ── Loop ──
    if (config.loopCount != null && config.loopCount! > 0) {
      args.addAll(['-stream_loop', '${config.loopCount}']);
    }

    // ── Extra args (power users) ──
    if (config.extraArgs != null && config.extraArgs!.isNotEmpty) {
      args.addAll(config.extraArgs!);
    }

    // ── Output ──
    args.add(outputPath);

    return args;
  }

  List<String> _buildTwoPassArgs({
    required String inputPath,
    required String outputPath,
    required ConversionConfig config,
    required int passNumber,
  }) {
    final args = <String>['-y'];

    // Trim
    if (config.trim != null) {
      args.addAll(['-ss', _formatMs(config.trim!.startMs)]);
    }

    args.addAll(['-i', inputPath]);

    if (config.trim != null) {
      final durationMs = config.trim!.endMs - config.trim!.startMs;
      args.addAll(['-t', _formatMs(durationMs)]);
    }

    // Video filters (same for both passes)
    final videoFilters = <String>[];
    if (config.videoCodec != VideoCodecOption.copy) {
      if (config.crop != null) {
        videoFilters.add(
          'crop=${config.crop!.width}:${config.crop!.height}:${config.crop!.x}:${config.crop!.y}',
        );
      }
      if (config.rotate != null) {
        videoFilters.addAll(_buildRotateFilters(config.rotate!));
      }
      _addVideoFilters(videoFilters, config);
      if (config.deinterlace) videoFilters.add('yadif=0:-1:0');
      if (config.denoise) videoFilters.add(_buildDenoiseFilter(config.denoiseStrength));
      if (config.sharpen) {
        videoFilters.add('unsharp=5:5:${(config.sharpenStrength ?? 1.0).toStringAsFixed(2)}');
      }
      if (config.hdrToSdr) {
        videoFilters.add('zscale=t=linear:npl=100,format=gbrpf32le,'
            'zscale=p=bt709,tonemap=hable:desat=0,'
            'zscale=t=bt709:m=bt709:r=tv,format=yuv420p');
      }
      if (config.brightness != null || config.contrast != null ||
          config.saturation != null || config.gamma != null) {
        videoFilters.add(_buildEqFilter(config));
      }
      if (config.negate) videoFilters.add('negate');
      if (config.colorEffect != null) videoFilters.add(config.colorEffect!);
      if (config.vignette) {
        final angle = config.vignetteAngle ?? 0.6283;
        videoFilters.add('vignette=angle=$angle');
      }
      if (config.filmGrain) {
        final intensity = (config.grainIntensity ?? 30).clamp(5, 80).round();
        videoFilters.add('noise=c0s=$intensity:c0f=t+u');
      }
      if (config.letterbox != null) videoFilters.add(_buildLetterboxFilter(config.letterbox!));
    }
    if (config.speed != null && config.speed != 1.0 &&
        config.videoCodec != VideoCodecOption.copy) {
      videoFilters.add('setpts=${(1.0 / config.speed!).toStringAsFixed(6)}*PTS');
    }
    if (config.subtitlePath != null && config.videoCodec != VideoCodecOption.copy) {
      final escapedPath = _escapeFilterPath(config.subtitlePath!);
      videoFilters.add("subtitles='$escapedPath'");
    }

    if (videoFilters.isNotEmpty) {
      args.addAll(['-vf', videoFilters.join(',')]);
    }

    // Video codec
    _addVideoCodecArgs(args, config);

    // Pass log file (written to output directory for predictable cleanup)
    args.addAll(['-passlogfile', p.join(p.dirname(outputPath), 'ffmpeg2pass')]);

    // Pass flag
    args.addAll(['-pass', '$passNumber']);

    if (passNumber == 1) {
      // Pass 1: no audio, output to null
      args.addAll(['-an']);
      args.addAll(['-f', 'null']);
      args.add(Platform.isWindows ? 'NUL' : '/dev/null');
    } else {
      // Pass 2: include audio
      final audioFilters = <String>[];
      if (config.speed != null && config.speed != 1.0 &&
          config.audioCodec != AudioCodecOption.copy &&
          config.audioCodec != AudioCodecOption.none) {
        audioFilters.addAll(_buildAtempoChain(config.speed!));
      }
      if (config.normalize &&
          config.audioCodec != AudioCodecOption.copy &&
          config.audioCodec != AudioCodecOption.none) {
        audioFilters.add('loudnorm=I=-16:TP=-1.5:LR=11');
      }
      if (audioFilters.isNotEmpty) {
        args.addAll(['-af', audioFilters.join(',')]);
      }

      _addAudioCodecArgs(args, config);

      if (config.outputFormat == OutputFormat.mp4 ||
          config.outputFormat == OutputFormat.mov) {
        args.addAll(['-movflags', '+faststart']);
      }

      if (config.metadata != null) {
        for (final entry in config.metadata!.entries) {
          args.addAll(['-metadata', '${entry.key}=${entry.value}']);
        }
      }

      if (config.extraArgs != null && config.extraArgs!.isNotEmpty) {
        args.addAll(config.extraArgs!);
      }

      args.add(outputPath);
    }

    return args;
  }

  /// Build filter_complex string for multi-input filter graphs.
  String _buildFilterComplex({
    required ConversionConfig config,
    required List<String> videoFilters,
    Duration? inputDuration,
  }) {
    // Blur region
    if (config.blurRegion != null) {
      return _buildBlurRegionFilterComplex(config, videoFilters);
    }

    // PiP
    if (config.pipConfig != null) {
      return _buildPipFilterComplex(config, videoFilters);
    }

    // Split screen
    if (config.splitScreen != null) {
      return _buildSplitScreenFilterComplex(config);
    }

    // Fallback: watermark with video filters
    if (config.watermarkPath != null && config.watermarkPosition != null) {
      final overlayExpr = config.watermarkPosition!.overlayExpression;
      final vfChain = videoFilters.isNotEmpty ? ',${videoFilters.join(',')}' : '';
      return '[0:v][1:v]$overlayExpr$vfChain[vout]';
    }

    // No multi-input filter needed — shouldn't reach here
    final vfChain = videoFilters.join(',');
    return '[0:v]${vfChain.isNotEmpty ? vfChain : 'null'}[vout]';
  }

  /// Build filter_complex for blur/pixelate region.
  ///
  /// Strategy: split → crop region → blur → overlay back.
  String _buildBlurRegionFilterComplex(
    ConversionConfig config,
    List<String> videoFilters,
  ) {
    final br = config.blurRegion!;
    final vfPrefix = videoFilters.isNotEmpty ? '${videoFilters.join(',')},' : '';

    if (br.type == 'pixelate') {
      // Pixelate: scale down then back up with nearest neighbor
      final scaleFactor = (br.strength + 1).clamp(2, 20);
      return '[0:v]${vfPrefix}split[main][blur];'
          '[blur]crop=${br.width}:${br.height}:${br.x}:${br.y},'
          'scale=iw/$scaleFactor:ih/$scaleFactor,'
          'scale=${br.width}:${br.height}:flags=neighbor[blurred];'
          '[main][blurred]overlay=${br.x}:${br.y}[vout]';
    } else {
      // Gaussian blur via boxblur
      final blurStr = br.strength.clamp(1, 20);
      return '[0:v]${vfPrefix}split[main][blur];'
          '[blur]crop=${br.width}:${br.height}:${br.x}:${br.y},'
          'boxblur=$blurStr[blurred];'
          '[main][blurred]overlay=${br.x}:${br.y}[vout]';
    }
  }

  /// Build filter_complex for picture-in-picture.
  String _buildPipFilterComplex(
    ConversionConfig config,
    List<String> videoFilters,
  ) {
    final pip = config.pipConfig!;
    final vfPrefix = videoFilters.isNotEmpty ? '${videoFilters.join(',')},' : '';
    final posExpr = _pipPositionExpression(pip.position);

    return '[0:v]${vfPrefix}null[main];'
        '[1:v]scale=iw*${pip.scale}:-2[pip];'
        '[main][pip]overlay=$posExpr[vout]';
  }

  /// Build filter_complex for split screen.
  String _buildSplitScreenFilterComplex(ConversionConfig config) {
    final ss = config.splitScreen!;
    final n = ss.filePaths.length;

    switch (ss.layout) {
      case 'horizontal':
        // Side by side
        final inputs = List.generate(n, (i) => '[$i:v]').join();
        return '${inputs}hstack=inputs=$n[vout]';
      case 'vertical':
        // Top and bottom
        final inputs = List.generate(n, (i) => '[$i:v]').join();
        return '${inputs}vstack=inputs=$n[vout]';
      case 'grid':
        // 2x2 grid (requires exactly 4 inputs)
        if (n == 4) {
          return '[0:v][1:v][2:v][3:v]xstack=inputs=4:layout=0_0|w0_0|0_h0|w0_h0[vout]';
        }
        // Fallback: horizontal stack for non-4 inputs
        final inputs = List.generate(n, (i) => '[$i:v]').join();
        return '${inputs}hstack=inputs=$n[vout]';
      default:
        final inputs = List.generate(n, (i) => '[$i:v]').join();
        return '${inputs}hstack=inputs=$n[vout]';
    }
  }

  /// Get overlay position expression for PiP.
  String _pipPositionExpression(String position) {
    switch (position) {
      case 'topLeft':
        return '10:10';
      case 'topRight':
        return 'W-w-10:10';
      case 'bottomLeft':
        return '10:H-h-10';
      case 'bottomRight':
        return 'W-w-10:H-h-10';
      default:
        return 'W-w-10:H-h-10';
    }
  }

  /// Build rotation/flip ffmpeg filter strings.
  List<String> _buildRotateFilters(RotateOption rotate) {
    switch (rotate) {
      case RotateOption.cw90:
        return ['transpose=1'];
      case RotateOption.ccw90:
        return ['transpose=2'];
      case RotateOption.rotate180:
        return ['transpose=1', 'transpose=1'];
      case RotateOption.flipH:
        return ['hflip'];
      case RotateOption.flipV:
        return ['vflip'];
    }
  }

  /// Build denoise filter string based on strength.
  String _buildDenoiseFilter(String? strength) {
    switch (strength) {
      case 'strong':
        return 'nlmeans=s=10:p=7:r=15';
      case 'medium':
        return 'nlmeans=s=6:p=7:r=15';
      case 'light':
      default:
        return 'nlmeans=s=3:p=7:r=15';
    }
  }

  /// Build drawtext filter for text overlay.
  String _buildDrawtextFilter(String text, TextOverlayConfig cfg) {
    final escapedText = _escapeDrawtext(text);
    final yExpr = _textPositionY(cfg.position);

    final parts = <String>[
      "text='$escapedText'",
      'fontsize=${cfg.fontSize}',
      'fontcolor=${cfg.fontColor}',
      'x=(w-text_w)/2', // Center horizontally
      'y=$yExpr',
    ];

    if (cfg.borderColor != null && cfg.borderWidth > 0) {
      parts.add('borderw=${cfg.borderWidth}');
      parts.add('bordercolor=${cfg.borderColor}');
    }

    return 'drawtext=${parts.join(':')}';
  }

  /// Get Y position expression for drawtext.
  String _textPositionY(String position) {
    switch (position) {
      case 'top':
        return '20';
      case 'center':
        return '(h-text_h)/2';
      case 'bottom':
      default:
        return 'h-th-20';
    }
  }

  /// Escape text content for the drawtext filter (single-level filter parsing).
  ///
  /// Drawtext needs: colon, backslash, single quote escaping.
  /// Different from [_escapeFilterPath] which handles double-level escaping
  /// for file paths in filter graphs (shell + filter parser).
  String _escapeDrawtext(String text) {
    return text
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "'\\\\\\''")
        .replaceAll(':', '\\:')
        .replaceAll('%', '%%');
  }

  /// Add enhancement video filters (used by stabilization pass 2).
  void _addEnhancementVideoFilters(
    List<String> videoFilters,
    ConversionConfig config,
  ) {
    if (config.crop != null) {
      videoFilters.add(
        'crop=${config.crop!.width}:${config.crop!.height}:${config.crop!.x}:${config.crop!.y}',
      );
    }
    if (config.rotate != null) {
      videoFilters.addAll(_buildRotateFilters(config.rotate!));
    }
    if (config.deinterlace) {
      videoFilters.add('yadif=0:-1:0');
    }
    if (config.denoise) {
      videoFilters.add(_buildDenoiseFilter(config.denoiseStrength));
    }
    if (config.sharpen) {
      final strength = config.sharpenStrength ?? 1.0;
      videoFilters.add('unsharp=5:5:${strength.toStringAsFixed(2)}');
    }
    if (config.hdrToSdr) {
      videoFilters.add(
        'zscale=t=linear:npl=100,format=gbrpf32le,'
        'zscale=p=bt709,tonemap=hable:desat=0,'
        'zscale=t=bt709:m=bt709:r=tv,format=yuv420p',
      );
    }
    if (config.brightness != null || config.contrast != null ||
        config.saturation != null || config.gamma != null) {
      videoFilters.add(_buildEqFilter(config));
    }
    if (config.negate) {
      videoFilters.add('negate');
    }
    if (config.colorEffect != null) {
      videoFilters.add(config.colorEffect!);
    }
    if (config.vignette) {
      final angle = config.vignetteAngle ?? 0.6283;
      videoFilters.add('vignette=angle=$angle');
    }
    if (config.filmGrain) {
      final intensity = (config.grainIntensity ?? 30).clamp(5, 80).round();
      videoFilters.add('noise=c0s=$intensity:c0f=t+u');
    }
    if (config.letterbox != null) {
      videoFilters.add(_buildLetterboxFilter(config.letterbox!));
    }
    if (config.textOverlay != null && config.textOverlay!.isNotEmpty) {
      videoFilters.add(_buildDrawtextFilter(
        config.textOverlay!,
        config.textOverlayConfig ?? const TextOverlayConfig(),
      ));
    }
  }

  /// Add video codec arguments to the args list.
  void _addVideoCodecArgs(List<String> args, ConversionConfig config) {
    if (config.isAudioOnly || config.removeVideo) {
      args.add('-vn');
      return;
    }

    final codec = config.videoCodec;
    if (codec == null) return; // Let ffmpeg decide

    if (codec == VideoCodecOption.copy) {
      args.addAll(['-c:v', 'copy']);
      return;
    }

    if (codec == VideoCodecOption.none) {
      args.add('-vn');
      return;
    }

    // Determine the actual encoder name (may use HW accel variant)
    final encoderName = config.hwAccel
        ? _getHwAccelEncoder(codec)
        : codec.ffmpegName;

    args.addAll(['-c:v', encoderName]);

    // Hardware acceleration input flag
    if (config.hwAccel) {
      _addHwAccelInputArgs(args, config);
    }

    // Quality control: CRF or bitrate
    if (config.videoBitrate != null) {
      args.addAll(['-b:v', '${config.videoBitrate}k']);
    } else if (config.crf != null) {
      // CRF naming varies by codec
      if (codec == VideoCodecOption.vp9 || codec == VideoCodecOption.av1) {
        args.addAll(['-crf', '${config.crf}', '-b:v', '0']);
      } else if (config.hwAccel && _isVideoToolbox()) {
        // VideoToolbox uses -q:v instead of -crf
        args.addAll(['-q:v', '${config.crf}']);
      } else {
        args.addAll(['-crf', '${config.crf}']);
      }
    }

    // Encoder preset
    if (config.encoderPreset != null && !config.hwAccel) {
      if (codec == VideoCodecOption.h264 || codec == VideoCodecOption.h265) {
        args.addAll(['-preset', config.encoderPreset!]);
      } else if (codec == VideoCodecOption.av1) {
        // libaom-av1 uses cpu-used (0=slowest/best, 8=fastest)
        final cpuUsed = _presetToCpuUsed(config.encoderPreset!);
        args.addAll(['-cpu-used', '$cpuUsed']);
      }
    }

    // H.264/H.265 specific: profile
    if (codec == VideoCodecOption.h264 && !config.hwAccel) {
      args.addAll(['-profile:v', 'high']);
      args.addAll(['-pix_fmt', 'yuv420p']);
    }

    // FPS override
    if (config.fps != null) {
      args.addAll(['-r', '${config.fps}']);
    }
  }

  /// Add audio codec arguments to the args list.
  void _addAudioCodecArgs(List<String> args, ConversionConfig config) {
    if (config.removeAudio) {
      args.add('-an');
      return;
    }

    final codec = config.audioCodec;

    if (codec == AudioCodecOption.none) {
      args.add('-an');
      return;
    }

    if (codec == AudioCodecOption.copy) {
      args.addAll(['-c:a', 'copy']);
      return;
    }

    if (codec != null) {
      args.addAll(['-c:a', codec.ffmpegName]);
    }

    // Audio bitrate
    if (config.audioBitrate != null) {
      args.addAll(['-b:a', '${config.audioBitrate}k']);
    }

    // Sample rate
    if (config.audioSampleRate != null) {
      args.addAll(['-ar', '${config.audioSampleRate}']);
    }

    // Channels
    if (config.audioChannels != null) {
      args.addAll(['-ac', '${config.audioChannels}']);
    }
  }

  /// Add resolution/scale video filters.
  void _addVideoFilters(List<String> videoFilters, ConversionConfig config) {
    if (config.resolution == null ||
        config.resolution == ResolutionOption.original) {
      return;
    }

    if (config.resolution == ResolutionOption.custom) {
      if (config.customWidth != null && config.customHeight != null) {
        videoFilters.add('scale=${config.customWidth}:${config.customHeight}');
      } else if (config.customWidth != null) {
        videoFilters.add('scale=${config.customWidth}:-2');
      } else if (config.customHeight != null) {
        videoFilters.add('scale=-2:${config.customHeight}');
      }
    } else {
      // Standard resolution: scale height, auto-calculate width maintaining aspect ratio
      // -2 ensures width is divisible by 2 (required by most codecs)
      videoFilters.add('scale=-2:${config.resolution!.height}');
    }
  }

  /// Build GIF-specific args with palette optimization.
  void _addGifArgs(
      List<String> args, ConversionConfig config, String outputPath) {
    final fps = config.fps ?? 15;
    final width = _getAnimatedImageWidth(config);

    // Two-stage GIF with palette generation for quality
    final filterChain =
        'fps=$fps,scale=$width:-1:flags=lanczos,split[s0][s1];'
        '[s0]palettegen[p];[s1][p]paletteuse';

    args.addAll(['-filter_complex', filterChain]);
    args.addAll(['-loop', '0']);
    args.add(outputPath);
  }

  /// Build animated WebP args.
  void _addAnimatedWebpArgs(
      List<String> args, ConversionConfig config, String outputPath) {
    final fps = config.fps ?? 15;
    final width = _getAnimatedImageWidth(config);

    args.addAll(['-vf', 'fps=$fps,scale=$width:-1']);
    args.addAll(['-c:v', 'libwebp']);
    args.addAll(['-lossless', '0']);
    args.addAll(['-quality', '${config.crf ?? 75}']);
    args.addAll(['-loop', '0']);
    args.add(outputPath);
  }

  /// Get width for animated image output (GIF/WebP).
  ///
  /// For resolution presets (e.g., 720p, 1080p), we use the preset's height
  /// value as a *quality indicator* for the output width. This works because:
  /// - GIF/WebP scale filter is `scale=W:-1` (auto-calculates height)
  /// - A "720p" preset means "720-class quality" → 720px wide is reasonable
  /// - For portrait video, 720px wide still maintains aspect ratio correctly
  ///
  /// Uses `customWidth` when the user explicitly set a custom resolution.
  /// Falls back to 480px when no resolution is specified (keeps GIF file size sane).
  int _getAnimatedImageWidth(ConversionConfig config) {
    if (config.resolution == ResolutionOption.custom &&
        config.customWidth != null) {
      return config.customWidth!;
    }
    if (config.resolution != null &&
        config.resolution != ResolutionOption.original &&
        config.resolution != ResolutionOption.custom) {
      return config.resolution!.height;
    }
    return 480;
  }

  /// Build atempo filter chain for speed changes.
  ///
  /// ffmpeg's atempo filter accepts values between 0.5 and 100.0.
  /// For speeds outside the 0.5-2.0 range, we chain multiple atempo filters.
  /// Example: 4.0x speed = atempo=2.0,atempo=2.0
  List<String> _buildAtempoChain(double speed) {
    final filters = <String>[];
    var remaining = speed;

    if (remaining < 0.5) {
      appLogger.warning(
          '[FFmpeg] Audio speed ${speed}x clamped to 0.5x (atempo filter minimum)');
      remaining = 0.5;
    }
    if (remaining > 100.0) {
      appLogger.warning(
          '[FFmpeg] Audio speed ${speed}x clamped to 100.0x (atempo filter maximum)');
      remaining = 100.0;
    }

    while (remaining > 2.0) {
      filters.add('atempo=2.0');
      remaining /= 2.0;
    }
    while (remaining < 0.5) {
      filters.add('atempo=0.5');
      remaining /= 0.5;
    }

    if ((remaining - 1.0).abs() > 0.001) {
      filters.add('atempo=${remaining.toStringAsFixed(6)}');
    }

    return filters;
  }

  /// Add hardware acceleration input arguments.
  void _addHwAccelInputArgs(List<String> args, ConversionConfig config) {
    // HW accel args are added before -i in the final args,
    // but since we add them after the codec selection, they'll need
    // to be inserted. Instead, we rely on the encoder name alone
    // for output encoding (which is the standard approach).
    // Most HW encoders don't need explicit -hwaccel input flags
    // unless we want HW decoding too.
  }

  /// Get the hardware-accelerated encoder name for a codec.
  /// Falls back to software encoder if the HW encoder isn't available.
  String _getHwAccelEncoder(VideoCodecOption codec) {
    final desired = _getDesiredHwEncoder(codec);
    // Check if available in detected capabilities
    if (_hwAccelCapabilities != null) {
      final available = _hwAccelCapabilities!
          .expand((hw) => hw.encoders)
          .toSet();
      if (!available.contains(desired)) {
        return codec.ffmpegName; // Fallback to software
      }
    }
    return desired;
  }

  /// Get the platform-preferred HW encoder name for a codec (without availability check).
  String _getDesiredHwEncoder(VideoCodecOption codec) {
    if (Platform.isMacOS) {
      switch (codec) {
        case VideoCodecOption.h264:
          return 'h264_videotoolbox';
        case VideoCodecOption.h265:
          return 'hevc_videotoolbox';
        default:
          return codec.ffmpegName; // No HW accel for VP9/AV1 on macOS
      }
    } else if (Platform.isWindows) {
      // Prefer NVENC (most common), fall back to QSV
      switch (codec) {
        case VideoCodecOption.h264:
          return 'h264_nvenc';
        case VideoCodecOption.h265:
          return 'hevc_nvenc';
        default:
          return codec.ffmpegName;
      }
    } else if (Platform.isLinux) {
      switch (codec) {
        case VideoCodecOption.h264:
          return 'h264_vaapi';
        case VideoCodecOption.h265:
          return 'hevc_vaapi';
        default:
          return codec.ffmpegName;
      }
    }
    return codec.ffmpegName;
  }

  /// Check if running on macOS (for VideoToolbox-specific behavior)
  bool _isVideoToolbox() => Platform.isMacOS;

  /// Convert encoder preset name to AV1 cpu-used value.
  int _presetToCpuUsed(String preset) {
    switch (preset) {
      case 'veryslow':
        return 1;
      case 'slow':
        return 2;
      case 'medium':
        return 4;
      case 'fast':
        return 6;
      case 'ultrafast':
        return 8;
      default:
        return 4;
    }
  }

  /// Escape file path for ffmpeg filter expressions (double-level escaping).
  ///
  /// Filter paths go through two parsing levels (shell → filter graph parser),
  /// so backslashes and colons need double-escaping. Different from
  /// [_escapeDrawtext] which only handles single-level text content escaping.
  String _escapeFilterPath(String path) {
    return path
        .replaceAll('\\', '\\\\\\\\')
        .replaceAll(':', '\\\\:')
        .replaceAll("'", "'\\''");
  }

  /// Build the `eq` filter for brightness/contrast/saturation/gamma.
  String _buildEqFilter(ConversionConfig config) {
    final parts = <String>[];
    if (config.brightness != null) {
      parts.add('brightness=${config.brightness!.toStringAsFixed(2)}');
    }
    if (config.contrast != null) {
      parts.add('contrast=${config.contrast!.toStringAsFixed(2)}');
    }
    if (config.saturation != null) {
      parts.add('saturation=${config.saturation!.toStringAsFixed(2)}');
    }
    if (config.gamma != null) {
      parts.add('gamma=${config.gamma!.toStringAsFixed(2)}');
    }
    return 'eq=${parts.join(':')}';
  }

  /// Build letterbox/pillarbox padding filter.
  ///
  /// Adds black bars to fit a target aspect ratio without cropping.
  String _buildLetterboxFilter(String targetAspect) {
    final parts = targetAspect.split(':');
    if (parts.length != 2) return 'null'; // passthrough
    final aspectW = int.tryParse(parts[0]) ?? 16;
    final aspectH = int.tryParse(parts[1]) ?? 9;
    // pad to target aspect ratio: calculate output dimensions
    return "pad=iw:iw*$aspectH/$aspectW:(ow-iw)/2:(oh-ih)/2:color=black";
  }

  /// Build audio EQ filter from preset name.
  String _buildAudioEqFilter(String preset) {
    switch (preset) {
      case 'bass_boost':
        return 'bass=g=8:f=110:w=0.6';
      case 'treble_boost':
        return 'treble=g=6:f=4000:w=0.6';
      case 'voice_enhance':
        // Boost voice frequencies (300Hz-3kHz), cut lows and highs
        return 'highpass=f=200,lowpass=f=3500,equalizer=f=1000:t=h:w=500:g=3';
      case 'cinema':
        // Warm cinema sound: slight bass boost, midrange warmth
        return 'bass=g=4:f=80,equalizer=f=500:t=h:w=200:g=2,treble=g=2:f=8000';
      case 'podcast':
        // Optimize for speech: compression + clarity
        return 'highpass=f=80,equalizer=f=2500:t=h:w=500:g=4,lowpass=f=12000';
      case 'music':
        // Balanced music enhancement
        return 'bass=g=3:f=100,treble=g=2:f=6000';
      default:
        return 'anull'; // passthrough
    }
  }

  /// Build thumbnail extraction args (single frame at timestamp).
  List<String> buildThumbnailArgs({
    required String inputPath,
    required String outputPath,
    required double timestamp,
  }) {
    return [
      '-y',
      '-ss', timestamp.toStringAsFixed(3),
      '-i', inputPath,
      '-frames:v', '1',
      '-q:v', '2', // High quality JPEG
      outputPath,
    ];
  }

  /// Build subtitle extraction args.
  List<String> buildSubtitleExtractArgs({
    required String inputPath,
    required String outputPath,
    int trackIndex = 0,
  }) {
    return [
      '-y',
      '-i', inputPath,
      '-map', '0:s:$trackIndex',
      '-c:s', 'srt',
      outputPath,
    ];
  }

  /// Build video segment splitting args.
  List<String> buildSplitArgs({
    required String inputPath,
    required String outputPattern,
    required int intervalSeconds,
  }) {
    return [
      '-y',
      '-i', inputPath,
      '-c', 'copy',
      '-map', '0',
      '-f', 'segment',
      '-segment_time', '$intervalSeconds',
      '-reset_timestamps', '1',
      outputPattern,
    ];
  }

  /// Build concat with crossfade transitions.
  List<String> buildConcatWithTransitionArgs({
    required List<String> inputFiles,
    required String outputPath,
    required ConversionConfig config,
    required double transitionDuration,
  }) {
    final args = <String>['-y'];
    for (final file in inputFiles) {
      args.addAll(['-i', file]);
    }

    final n = inputFiles.length;
    if (n < 2) {
      // Single file: just copy
      args.addAll(['-c', 'copy', outputPath]);
      return args;
    }

    // Build crossfade filter chain:
    // [0:v][1:v]xfade=transition=fade:duration=D:offset=O[v01];
    // [v01][2:v]xfade=...
    final filterParts = <String>[];
    var prevLabel = '0:v';
    // We need durations of each clip to calculate offsets
    // For simplicity, use a fixed offset calculation
    // (real implementation would probe each file)
    for (int i = 1; i < n; i++) {
      final outLabel = i < n - 1 ? 'v${i - 1}$i' : 'vout';
      // xfade with fade transition
      filterParts.add(
        '[$prevLabel][$i:v]xfade=transition=fade:duration=$transitionDuration'
        '${i < n - 1 ? '[$outLabel]' : '[$outLabel]'}',
      );
      prevLabel = outLabel;
    }

    // Audio crossfade
    var prevAudioLabel = '0:a';
    for (int i = 1; i < n; i++) {
      final outLabel = i < n - 1 ? 'a${i - 1}$i' : 'aout';
      filterParts.add(
        '[$prevAudioLabel][$i:a]acrossfade=d=$transitionDuration'
        '[$outLabel]',
      );
      prevAudioLabel = outLabel;
    }

    args.addAll(['-filter_complex', filterParts.join(';')]);
    args.addAll(['-map', '[vout]', '-map', '[aout]']);

    _addVideoCodecArgs(args, config);
    _addAudioCodecArgs(args, config);

    if (config.outputFormat == OutputFormat.mp4 ||
        config.outputFormat == OutputFormat.mov) {
      args.addAll(['-movflags', '+faststart']);
    }

    args.add(outputPath);
    return args;
  }

  /// Format milliseconds to ffmpeg time string: HH:MM:SS.mmm
  static String _formatMs(int ms) {
    final hours = (ms ~/ 3600000).toString().padLeft(2, '0');
    final minutes = ((ms ~/ 60000) % 60).toString().padLeft(2, '0');
    final seconds = ((ms ~/ 1000) % 60).toString().padLeft(2, '0');
    final millis = (ms % 1000).toString().padLeft(3, '0');
    return '$hours:$minutes:$seconds.$millis';
  }
}
