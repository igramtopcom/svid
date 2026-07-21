import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/converter/domain/entities/conversion_config.dart';
import 'package:svid/features/converter/domain/entities/output_format.dart';
import 'package:svid/features/converter/domain/services/ffmpeg_command_builder.dart';

void main() {
  late FFmpegCommandBuilder builder;

  setUp(() {
    builder = FFmpegCommandBuilder();
  });

  /// Helper to build args with minimal config.
  List<String> buildArgs({
    String inputPath = '/input.mp4',
    String outputPath = '/output.mp4',
    required ConversionConfig config,
    Duration? inputDuration,
  }) {
    return builder.buildArgs(
      inputPath: inputPath,
      outputPath: outputPath,
      config: config,
      inputDuration: inputDuration,
    );
  }

  group('basic conversion', () {
    test('produces -y, -i, output path', () {
      final args = buildArgs(
        config: const ConversionConfig(outputFormat: OutputFormat.mp4),
      );
      expect(args.first, '-y');
      expect(args.contains('-i'), isTrue);
      expect(args.indexOf('-i') + 1, lessThan(args.length));
      expect(args[args.indexOf('-i') + 1], '/input.mp4');
      expect(args.last, '/output.mp4');
    });

    test('MP4 adds movflags faststart', () {
      final args = buildArgs(
        config: const ConversionConfig(outputFormat: OutputFormat.mp4),
      );
      final idx = args.indexOf('-movflags');
      expect(idx, isNot(-1));
      expect(args[idx + 1], '+faststart');
    });

    test('MKV does not add movflags', () {
      final args = buildArgs(
        outputPath: '/output.mkv',
        config: const ConversionConfig(outputFormat: OutputFormat.mkv),
      );
      expect(args.contains('-movflags'), isFalse);
    });

    test('MOV adds movflags faststart', () {
      final args = buildArgs(
        outputPath: '/output.mov',
        config: const ConversionConfig(outputFormat: OutputFormat.mov),
      );
      expect(args.contains('-movflags'), isTrue);
    });
  });

  group('video codec', () {
    test('h264 codec adds -c:v libx264', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
        ),
      );
      final idx = args.indexOf('-c:v');
      expect(idx, isNot(-1));
      expect(args[idx + 1], 'libx264');
    });

    test('h265 codec adds -c:v libx265', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h265,
        ),
      );
      final idx = args.indexOf('-c:v');
      expect(idx, isNot(-1));
      expect(args[idx + 1], 'libx265');
    });

    test('copy codec adds -c:v copy', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mkv,
          videoCodec: VideoCodecOption.copy,
          audioCodec: AudioCodecOption.copy,
        ),
      );
      final idx = args.indexOf('-c:v');
      expect(idx, isNot(-1));
      expect(args[idx + 1], 'copy');
    });

    test('no video codec adds -vn for audio-only', () {
      final args = buildArgs(
        outputPath: '/output.mp3',
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp3,
          videoCodec: VideoCodecOption.none,
        ),
      );
      expect(args.contains('-vn'), isTrue);
    });

    test('CRF is added when set', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          crf: 18,
        ),
      );
      final idx = args.indexOf('-crf');
      expect(idx, isNot(-1));
      expect(args[idx + 1], '18');
    });

    test('video bitrate is added when set', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          videoBitrate: 5000,
        ),
      );
      final idx = args.indexOf('-b:v');
      expect(idx, isNot(-1));
      expect(args[idx + 1], '5000k');
    });

    test('encoder preset is added for h264', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          encoderPreset: 'fast',
        ),
      );
      final idx = args.indexOf('-preset');
      expect(idx, isNot(-1));
      expect(args[idx + 1], 'fast');
    });

    test('VP9 CRF also includes -b:v 0', () {
      final args = buildArgs(
        outputPath: '/output.webm',
        config: const ConversionConfig(
          outputFormat: OutputFormat.webm,
          videoCodec: VideoCodecOption.vp9,
          crf: 30,
        ),
      );
      final crfIdx = args.indexOf('-crf');
      expect(crfIdx, isNot(-1));
      expect(args[crfIdx + 1], '30');
      // VP9 requires -b:v 0 with CRF
      final bvIdx = args.indexOf('-b:v');
      expect(bvIdx, isNot(-1));
      expect(args[bvIdx + 1], '0');
    });
  });

  group('audio codec', () {
    test('aac codec adds -c:a aac', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          audioCodec: AudioCodecOption.aac,
        ),
      );
      final idx = args.indexOf('-c:a');
      expect(idx, isNot(-1));
      expect(args[idx + 1], 'aac');
    });

    test('audio bitrate is added when set', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          audioCodec: AudioCodecOption.aac,
          audioBitrate: 192,
        ),
      );
      final idx = args.indexOf('-b:a');
      expect(idx, isNot(-1));
      expect(args[idx + 1], '192k');
    });

    test('audio sample rate is added when set', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          audioCodec: AudioCodecOption.aac,
          audioSampleRate: 48000,
        ),
      );
      final idx = args.indexOf('-ar');
      expect(idx, isNot(-1));
      expect(args[idx + 1], '48000');
    });

    test('removeAudio adds -an flag', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          removeAudio: true,
        ),
      );
      expect(args.contains('-an'), isTrue);
    });
  });

  group('trim', () {
    test('trim adds -ss before input and -t after', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.copy,
          audioCodec: AudioCodecOption.copy,
          trim: TrimRange(startMs: 5000, endMs: 15000),
        ),
      );

      // -ss should come before -i (fast seek)
      final ssIdx = args.indexOf('-ss');
      final inputIdx = args.indexOf('-i');
      expect(ssIdx, isNot(-1));
      expect(ssIdx, lessThan(inputIdx));

      // -t should come after -i
      final tIdx = args.indexOf('-t');
      expect(tIdx, isNot(-1));
      expect(tIdx, greaterThan(inputIdx));
    });

    test('trim duration is end - start', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.copy,
          audioCodec: AudioCodecOption.copy,
          trim: TrimRange(startMs: 2000, endMs: 7000),
        ),
      );

      final tIdx = args.indexOf('-t');
      // Duration = 7000 - 2000 = 5000ms = 5.000s
      expect(args[tIdx + 1], contains('5'));
    });
  });

  group('video filters', () {
    test('crop filter is added', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          crop: CropConfig(x: 10, y: 20, width: 640, height: 480),
        ),
      );
      final vfIdx = args.indexOf('-vf');
      expect(vfIdx, isNot(-1));
      expect(args[vfIdx + 1], contains('crop=640:480:10:20'));
    });

    test('denoise filter is added', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          denoise: true,
        ),
      );
      final vfIdx = args.indexOf('-vf');
      expect(vfIdx, isNot(-1));
      expect(args[vfIdx + 1], contains('nlmeans'));
    });

    test('denoise strength variations', () {
      for (final strength in ['light', 'medium', 'strong']) {
        final args = buildArgs(
          config: ConversionConfig(
            outputFormat: OutputFormat.mp4,
            videoCodec: VideoCodecOption.h264,
            denoise: true,
            denoiseStrength: strength,
          ),
        );
        final vfIdx = args.indexOf('-vf');
        expect(vfIdx, isNot(-1));
        final filterStr = args[vfIdx + 1];
        expect(filterStr, contains('nlmeans'));
        if (strength == 'strong') {
          expect(filterStr, contains('s=10'));
        } else if (strength == 'medium') {
          expect(filterStr, contains('s=6'));
        } else {
          expect(filterStr, contains('s=3'));
        }
      }
    });

    test('deinterlace adds yadif filter', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          deinterlace: true,
        ),
      );
      final vfIdx = args.indexOf('-vf');
      expect(vfIdx, isNot(-1));
      expect(args[vfIdx + 1], contains('yadif'));
    });

    test('sharpen adds unsharp filter', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          sharpen: true,
          sharpenStrength: 1.5,
        ),
      );
      final vfIdx = args.indexOf('-vf');
      expect(vfIdx, isNot(-1));
      expect(args[vfIdx + 1], contains('unsharp=5:5:1.50'));
    });

    test('HDR to SDR adds tone mapping filters', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          hdrToSdr: true,
        ),
      );
      final vfIdx = args.indexOf('-vf');
      expect(vfIdx, isNot(-1));
      final filterStr = args[vfIdx + 1];
      expect(filterStr, contains('zscale'));
      expect(filterStr, contains('tonemap'));
    });

    test('brightness/contrast/saturation adds eq filter', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          brightness: 0.1,
          contrast: 1.2,
          saturation: 1.5,
        ),
      );
      final vfIdx = args.indexOf('-vf');
      expect(vfIdx, isNot(-1));
      final filterStr = args[vfIdx + 1];
      expect(filterStr, contains('eq='));
      expect(filterStr, contains('brightness='));
      expect(filterStr, contains('contrast='));
      expect(filterStr, contains('saturation='));
    });

    test('negate adds negate filter', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          negate: true,
        ),
      );
      final vfIdx = args.indexOf('-vf');
      expect(vfIdx, isNot(-1));
      expect(args[vfIdx + 1], contains('negate'));
    });

    test('vignette adds vignette filter', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          vignette: true,
        ),
      );
      final vfIdx = args.indexOf('-vf');
      expect(vfIdx, isNot(-1));
      expect(args[vfIdx + 1], contains('vignette'));
    });

    test('film grain adds noise filter', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          filmGrain: true,
          grainIntensity: 50,
        ),
      );
      final vfIdx = args.indexOf('-vf');
      expect(vfIdx, isNot(-1));
      expect(args[vfIdx + 1], contains('noise=c0s=50'));
    });

    test('color effect filter chain is added', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          colorEffect: 'curves=vintage',
        ),
      );
      final vfIdx = args.indexOf('-vf');
      expect(vfIdx, isNot(-1));
      expect(args[vfIdx + 1], contains('curves=vintage'));
    });

    test('rotation CW90 adds transpose=1', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          rotate: RotateOption.cw90,
        ),
      );
      final vfIdx = args.indexOf('-vf');
      expect(vfIdx, isNot(-1));
      expect(args[vfIdx + 1], contains('transpose=1'));
    });

    test('flipH adds hflip filter', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          rotate: RotateOption.flipH,
        ),
      );
      final vfIdx = args.indexOf('-vf');
      expect(vfIdx, isNot(-1));
      expect(args[vfIdx + 1], contains('hflip'));
    });

    test('subtitle burn-in adds subtitles filter', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          subtitlePath: '/subs.srt',
        ),
      );
      final vfIdx = args.indexOf('-vf');
      expect(vfIdx, isNot(-1));
      expect(args[vfIdx + 1], contains('subtitles='));
    });

    test('no video filters when codec is copy', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mkv,
          videoCodec: VideoCodecOption.copy,
          audioCodec: AudioCodecOption.copy,
          denoise: true,
          sharpen: true,
        ),
      );
      expect(args.contains('-vf'), isFalse);
    });

    test('multiple video filters are comma-joined', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          crop: CropConfig(x: 0, y: 0, width: 1920, height: 1080),
          denoise: true,
          sharpen: true,
        ),
      );
      final vfIdx = args.indexOf('-vf');
      expect(vfIdx, isNot(-1));
      final filterStr = args[vfIdx + 1];
      // Should contain commas joining multiple filters
      expect(filterStr.split(',').length, greaterThanOrEqualTo(3));
    });

    test('fade in adds fade=t=in filter', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          fadeIn: true,
          fadeDuration: 2.0,
        ),
      );
      final vfIdx = args.indexOf('-vf');
      expect(vfIdx, isNot(-1));
      expect(args[vfIdx + 1], contains('fade=t=in:st=0:d=2.0'));
    });

    test('frame interpolation adds minterpolate', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          interpolate: true,
          targetFps: 60,
        ),
      );
      final vfIdx = args.indexOf('-vf');
      expect(vfIdx, isNot(-1));
      expect(args[vfIdx + 1], contains('minterpolate'));
      expect(args[vfIdx + 1], contains('fps=60'));
    });
  });

  group('audio filters', () {
    test('normalize adds loudnorm filter', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          audioCodec: AudioCodecOption.aac,
          normalize: true,
        ),
      );
      final afIdx = args.indexOf('-af');
      expect(afIdx, isNot(-1));
      expect(args[afIdx + 1], contains('loudnorm'));
    });

    test('volume adjustment adds volume filter', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          audioCodec: AudioCodecOption.aac,
          volumeDb: 6.0,
        ),
      );
      final afIdx = args.indexOf('-af');
      expect(afIdx, isNot(-1));
      expect(args[afIdx + 1], contains('volume=6.0dB'));
    });

    test('audio compressor adds compand filter', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          audioCodec: AudioCodecOption.aac,
          audioCompressor: true,
        ),
      );
      final afIdx = args.indexOf('-af');
      expect(afIdx, isNot(-1));
      expect(args[afIdx + 1], contains('compand'));
    });

    test('normalize not added when audio codec is copy', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mkv,
          videoCodec: VideoCodecOption.copy,
          audioCodec: AudioCodecOption.copy,
          normalize: true,
        ),
      );
      expect(args.contains('-af'), isFalse);
    });

    test('reverse adds areverse audio filter', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          audioCodec: AudioCodecOption.aac,
          reverse: true,
        ),
      );
      final afIdx = args.indexOf('-af');
      expect(afIdx, isNot(-1));
      expect(args[afIdx + 1], contains('areverse'));
    });
  });

  group('speed change', () {
    test('speed 2x adds setpts and atempo', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          audioCodec: AudioCodecOption.aac,
          speed: 2.0,
        ),
      );
      // Video: setpts filter
      final vfIdx = args.indexOf('-vf');
      expect(vfIdx, isNot(-1));
      expect(args[vfIdx + 1], contains('setpts='));

      // Audio: atempo filter
      final afIdx = args.indexOf('-af');
      expect(afIdx, isNot(-1));
      expect(args[afIdx + 1], contains('atempo='));
    });

    test('speed 1.0 does not add speed filters', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          audioCodec: AudioCodecOption.aac,
          speed: 1.0,
        ),
      );
      // No video filters should be present for speed=1.0
      if (args.contains('-vf')) {
        expect(args[args.indexOf('-vf') + 1], isNot(contains('setpts=')));
      }
    });
  });

  group('reverse', () {
    test('reverse adds reverse video filter', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          audioCodec: AudioCodecOption.aac,
          reverse: true,
        ),
      );
      final vfIdx = args.indexOf('-vf');
      expect(vfIdx, isNot(-1));
      expect(args[vfIdx + 1], contains('reverse'));
    });
  });

  group('metadata', () {
    test('metadata entries are added', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          metadata: {'title': 'Test Video', 'artist': 'Me'},
        ),
      );
      final metaIndices = <int>[];
      for (int i = 0; i < args.length; i++) {
        if (args[i] == '-metadata') metaIndices.add(i);
      }
      expect(metaIndices.length, 2);
      final metaValues = metaIndices.map((i) => args[i + 1]).toList();
      expect(metaValues, contains('title=Test Video'));
      expect(metaValues, contains('artist=Me'));
    });
  });

  group('channel layout', () {
    test('mono adds -ac 1', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          audioCodec: AudioCodecOption.aac,
          channelLayout: 'mono',
        ),
      );
      final acIdx = args.indexOf('-ac');
      expect(acIdx, isNot(-1));
      expect(args[acIdx + 1], '1');
    });

    test('stereo adds -ac 2', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          audioCodec: AudioCodecOption.aac,
          channelLayout: 'stereo',
        ),
      );
      final acIdx = args.indexOf('-ac');
      expect(acIdx, isNot(-1));
      expect(args[acIdx + 1], '2');
    });

    test('5.1_to_stereo adds -ac 2', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          audioCodec: AudioCodecOption.aac,
          channelLayout: '5.1_to_stereo',
        ),
      );
      final acIdx = args.indexOf('-ac');
      expect(acIdx, isNot(-1));
      expect(args[acIdx + 1], '2');
    });
  });

  group('two-pass encoding', () {
    test('buildTwoPassArgs returns two argument lists', () {
      final passes = builder.buildTwoPassArgs(
        inputPath: '/input.mp4',
        outputPath: '/output.mp4',
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          audioCodec: AudioCodecOption.aac,
          twoPass: true,
          crf: 20,
        ),
      );
      expect(passes.length, 2);
    });

    test('pass 1 outputs to null device', () {
      final passes = builder.buildTwoPassArgs(
        inputPath: '/input.mp4',
        outputPath: '/output.mp4',
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          twoPass: true,
        ),
      );
      final pass1 = passes[0];
      expect(pass1.contains('-pass'), isTrue);
      expect(pass1.contains('-an'), isTrue);
      // Last arg should be /dev/null or NUL
      final nullDevice = Platform.isWindows ? 'NUL' : '/dev/null';
      expect(pass1.last, nullDevice);
    });

    test('pass 2 produces actual output', () {
      final passes = builder.buildTwoPassArgs(
        inputPath: '/input.mp4',
        outputPath: '/output.mp4',
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          audioCodec: AudioCodecOption.aac,
          twoPass: true,
        ),
      );
      final pass2 = passes[1];
      expect(pass2.last, '/output.mp4');
      expect(pass2.contains('-pass'), isTrue);
    });

    test('both passes include passlogfile', () {
      final passes = builder.buildTwoPassArgs(
        inputPath: '/input.mp4',
        outputPath: '/output.mp4',
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          twoPass: true,
        ),
      );
      for (final pass in passes) {
        expect(pass.contains('-passlogfile'), isTrue);
      }
    });
  });

  group('concat demuxer', () {
    test('builds correct concat demuxer args', () {
      final args = builder.buildConcatDemuxerArgs(
        outputPath: '/merged.mp4',
        concatListPath: '/tmp/concat.txt',
      );
      expect(args, contains('-y'));
      expect(args, contains('-f'));
      expect(args[args.indexOf('-f') + 1], 'concat');
      expect(args, contains('-safe'));
      expect(args, contains('-c'));
      expect(args[args.indexOf('-c') + 1], 'copy');
      expect(args.last, '/merged.mp4');
    });
  });

  group('concat filter', () {
    test('builds correct filter_complex for multiple inputs', () {
      final args = builder.buildConcatFilterArgs(
        inputFiles: ['/a.mp4', '/b.mp4', '/c.mp4'],
        outputPath: '/merged.mp4',
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          audioCodec: AudioCodecOption.aac,
        ),
      );
      // Should have -i for each input
      final inputCount = args.where((a) => a == '-i').length;
      expect(inputCount, 3);

      // Should have filter_complex
      expect(args, contains('-filter_complex'));
      final fcIdx = args.indexOf('-filter_complex');
      expect(args[fcIdx + 1], contains('concat=n=3'));
    });
  });

  group('stabilization', () {
    test('buildStabilizationArgs returns two passes', () {
      final passes = builder.buildStabilizationArgs(
        inputPath: '/input.mp4',
        outputPath: '/output.mp4',
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          stabilize: true,
        ),
        transformsPath: '/tmp/transforms.trf',
      );
      expect(passes.length, 2);
    });

    test('pass 1 uses vidstabdetect', () {
      final passes = builder.buildStabilizationArgs(
        inputPath: '/input.mp4',
        outputPath: '/output.mp4',
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          stabilize: true,
        ),
        transformsPath: '/tmp/transforms.trf',
      );
      final pass1 = passes[0];
      final vfIdx = pass1.indexOf('-vf');
      expect(vfIdx, isNot(-1));
      expect(pass1[vfIdx + 1], contains('vidstabdetect'));
    });

    test('pass 2 uses vidstabtransform', () {
      final passes = builder.buildStabilizationArgs(
        inputPath: '/input.mp4',
        outputPath: '/output.mp4',
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          stabilize: true,
        ),
        transformsPath: '/tmp/transforms.trf',
      );
      final pass2 = passes[1];
      final vfIdx = pass2.indexOf('-vf');
      expect(vfIdx, isNot(-1));
      expect(pass2[vfIdx + 1], contains('vidstabtransform'));
      expect(pass2.last, '/output.mp4');
    });
  });

  group('watermark', () {
    test('watermark adds second input and filter_complex', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          watermarkPath: '/wm.png',
          watermarkPosition: WatermarkPosition.bottomRight,
        ),
      );
      // Second -i for watermark
      final inputIndices = <int>[];
      for (int i = 0; i < args.length; i++) {
        if (args[i] == '-i') inputIndices.add(i);
      }
      expect(inputIndices.length, 2);
      expect(args[inputIndices[1] + 1], '/wm.png');

      // filter_complex with overlay
      expect(args, contains('-filter_complex'));
      final fcIdx = args.indexOf('-filter_complex');
      expect(args[fcIdx + 1], contains('overlay'));
    });
  });

  group('extra args', () {
    test('extra args are appended before output', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          extraArgs: ['-threads', '4'],
        ),
      );
      final threadsIdx = args.indexOf('-threads');
      expect(threadsIdx, isNot(-1));
      expect(args[threadsIdx + 1], '4');
      // Extra args should be before the output path (last element)
      expect(threadsIdx, lessThan(args.length - 1));
    });
  });

  group('loop', () {
    test('loop count adds -stream_loop', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          loopCount: 3,
        ),
      );
      final idx = args.indexOf('-stream_loop');
      expect(idx, isNot(-1));
      expect(args[idx + 1], '3');
    });

    test('loop 0 does not add flag', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          loopCount: 0,
        ),
      );
      expect(args.contains('-stream_loop'), isFalse);
    });
  });

  group('removeVideo', () {
    test('removeVideo adds -vn', () {
      final args = buildArgs(
        config: const ConversionConfig(
          outputFormat: OutputFormat.mp4,
          removeVideo: true,
        ),
      );
      expect(args.contains('-vn'), isTrue);
    });
  });
}
