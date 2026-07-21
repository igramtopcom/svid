import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/converter/domain/entities/conversion_config.dart';
import 'package:svid/features/converter/domain/entities/conversion_status.dart';
import 'package:svid/features/converter/domain/entities/output_format.dart';

void main() {
  group('ConversionConfig', () {
    const base = ConversionConfig(outputFormat: OutputFormat.mp4);

    group('computed properties', () {
      test('isAudioOnly returns true for audio format', () {
        const config = ConversionConfig(outputFormat: OutputFormat.mp3);
        expect(config.isAudioOnly, isTrue);
      });

      test('isAudioOnly returns true when videoCodec is none', () {
        const config = ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.none,
        );
        expect(config.isAudioOnly, isTrue);
      });

      test('isAudioOnly returns true when removeVideo is set', () {
        const config = ConversionConfig(
          outputFormat: OutputFormat.mp4,
          removeVideo: true,
        );
        expect(config.isAudioOnly, isTrue);
      });

      test('isAudioOnly returns false for video format', () {
        expect(base.isAudioOnly, isFalse);
      });

      test('isStreamCopy when both codecs are copy', () {
        const config = ConversionConfig(
          outputFormat: OutputFormat.mkv,
          videoCodec: VideoCodecOption.copy,
          audioCodec: AudioCodecOption.copy,
        );
        expect(config.isStreamCopy, isTrue);
      });

      test('isStreamCopy when video copy and no audio codec specified', () {
        const config = ConversionConfig(
          outputFormat: OutputFormat.mkv,
          videoCodec: VideoCodecOption.copy,
        );
        expect(config.isStreamCopy, isTrue);
      });

      test('isStreamCopy is false when video codec is h264', () {
        const config = ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          audioCodec: AudioCodecOption.copy,
        );
        expect(config.isStreamCopy, isFalse);
      });

      test('isAnimatedImage for GIF', () {
        const config = ConversionConfig(outputFormat: OutputFormat.gif);
        expect(config.isAnimatedImage, isTrue);
      });

      test('isAnimatedImage for WebP', () {
        const config = ConversionConfig(outputFormat: OutputFormat.webp);
        expect(config.isAnimatedImage, isTrue);
      });

      test('isAnimatedImage false for MP4', () {
        expect(base.isAnimatedImage, isFalse);
      });

      test('isConcat returns true with files', () {
        final config = base.copyWith(concatFiles: ['/a.mp4', '/b.mp4']);
        expect(config.isConcat, isTrue);
      });

      test('isConcat returns false without files', () {
        expect(base.isConcat, isFalse);
      });

      test('needsFilterComplex for watermark', () {
        final config = base.copyWith(
          watermarkPath: '/wm.png',
          watermarkPosition: WatermarkPosition.topLeft,
        );
        expect(config.needsFilterComplex, isTrue);
      });

      test('needsFilterComplex for blur region', () {
        final config = base.copyWith(
          blurRegion: const BlurRegion(x: 0, y: 0, width: 100, height: 100),
        );
        expect(config.needsFilterComplex, isTrue);
      });

      test('needsFilterComplex false by default', () {
        expect(base.needsFilterComplex, isFalse);
      });

      test('isSpecialOperation for thumbnail extraction', () {
        final config = base.copyWith(extractThumbnail: true);
        expect(config.isSpecialOperation, isTrue);
      });

      test('isSpecialOperation for subtitle extraction', () {
        final config = base.copyWith(extractSubtitles: true);
        expect(config.isSpecialOperation, isTrue);
      });

      test('isSpecialOperation for split', () {
        final config = base.copyWith(splitInterval: 60);
        expect(config.isSpecialOperation, isTrue);
      });

      test('hasEnhancementFilters for crop', () {
        final config = base.copyWith(
          crop: const CropConfig(x: 0, y: 0, width: 1920, height: 1080),
        );
        expect(config.hasEnhancementFilters, isTrue);
      });

      test('hasEnhancementFilters for denoise', () {
        final config = base.copyWith(denoise: true);
        expect(config.hasEnhancementFilters, isTrue);
      });

      test('hasEnhancementFilters false by default', () {
        expect(base.hasEnhancementFilters, isFalse);
      });
    });

    group('copyWith', () {
      test('preserves existing values when not overridden', () {
        const original = ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          crf: 23,
          audioBitrate: 192,
        );
        final copy = original.copyWith(crf: 18);
        expect(copy.outputFormat, OutputFormat.mp4);
        expect(copy.videoCodec, VideoCodecOption.h264);
        expect(copy.crf, 18);
        expect(copy.audioBitrate, 192);
      });

      test('clear sentinels set nullable fields to null', () {
        const original = ConversionConfig(
          outputFormat: OutputFormat.mp4,
          videoCodec: VideoCodecOption.h264,
          crf: 23,
          brightness: 0.5,
          volumeDb: 3.0,
        );

        final cleared = original.copyWith(
          clearCrf: true,
          clearBrightness: true,
          clearVolumeDb: true,
        );

        expect(cleared.crf, isNull);
        expect(cleared.brightness, isNull);
        expect(cleared.volumeDb, isNull);
        // Non-cleared fields preserved
        expect(cleared.videoCodec, VideoCodecOption.h264);
      });

      test('clear sentinel takes priority over new value', () {
        const original = ConversionConfig(
          outputFormat: OutputFormat.mp4,
          crf: 23,
        );
        final result = original.copyWith(crf: 18, clearCrf: true);
        expect(result.crf, isNull);
      });

      test('copyWith with crop', () {
        const crop = CropConfig(x: 10, y: 20, width: 640, height: 480);
        final config = base.copyWith(crop: crop);
        expect(config.crop, crop);
        expect(config.crop!.x, 10);
        expect(config.crop!.width, 640);
      });

      test('clearCrop removes crop', () {
        final config = base
            .copyWith(crop: const CropConfig(x: 0, y: 0, width: 100, height: 100))
            .copyWith(clearCrop: true);
        expect(config.crop, isNull);
      });

      test('copyWith preserves trim', () {
        final config = base.copyWith(
          trim: const TrimRange(startMs: 1000, endMs: 5000),
        );
        expect(config.trim!.startMs, 1000);
        expect(config.trim!.endMs, 5000);
      });
    });
  });

  group('TrimRange', () {
    test('duration calculates correctly', () {
      const trim = TrimRange(startMs: 2000, endMs: 7000);
      expect(trim.duration, const Duration(milliseconds: 5000));
    });

    test('startDuration and endDuration', () {
      const trim = TrimRange(startMs: 1500, endMs: 3000);
      expect(trim.startDuration, const Duration(milliseconds: 1500));
      expect(trim.endDuration, const Duration(milliseconds: 3000));
    });

    test('toJson and fromJson roundtrip', () {
      const trim = TrimRange(startMs: 500, endMs: 10000);
      final json = trim.toJson();
      final restored = TrimRange.fromJson(json);
      expect(restored, trim);
    });

    test('equality', () {
      const a = TrimRange(startMs: 100, endMs: 200);
      const b = TrimRange(startMs: 100, endMs: 200);
      const c = TrimRange(startMs: 100, endMs: 300);
      expect(a, b);
      expect(a, isNot(c));
    });
  });

  group('CropConfig', () {
    test('toJson and fromJson roundtrip', () {
      const crop = CropConfig(x: 10, y: 20, width: 640, height: 480);
      final json = crop.toJson();
      final restored = CropConfig.fromJson(json);
      expect(restored, crop);
    });

    test('equality', () {
      const a = CropConfig(x: 0, y: 0, width: 1920, height: 1080);
      const b = CropConfig(x: 0, y: 0, width: 1920, height: 1080);
      const c = CropConfig(x: 100, y: 0, width: 1920, height: 1080);
      expect(a, b);
      expect(a, isNot(c));
    });
  });

  group('TextOverlayConfig', () {
    test('defaults', () {
      const cfg = TextOverlayConfig();
      expect(cfg.position, 'bottom');
      expect(cfg.fontSize, 24);
      expect(cfg.fontColor, 'white');
      expect(cfg.borderColor, 'black');
      expect(cfg.borderWidth, 2);
    });

    test('toJson and fromJson roundtrip', () {
      const cfg = TextOverlayConfig(
        position: 'top',
        fontSize: 36,
        fontColor: 'red',
        borderColor: null,
        borderWidth: 3,
      );
      final json = cfg.toJson();
      final restored = TextOverlayConfig.fromJson(json);
      expect(restored.position, 'top');
      expect(restored.fontSize, 36);
      expect(restored.fontColor, 'red');
      expect(restored.borderColor, isNull);
    });

    test('equality', () {
      const a = TextOverlayConfig(position: 'top', fontSize: 24);
      const b = TextOverlayConfig(position: 'top', fontSize: 24);
      const c = TextOverlayConfig(position: 'bottom', fontSize: 24);
      expect(a, b);
      expect(a, isNot(c));
    });
  });

  group('BlurRegion', () {
    test('toJson and fromJson roundtrip', () {
      const region = BlurRegion(
        x: 50,
        y: 100,
        width: 200,
        height: 150,
        type: 'pixelate',
        strength: 15,
      );
      final json = region.toJson();
      final restored = BlurRegion.fromJson(json);
      expect(restored, region);
    });

    test('defaults', () {
      const region = BlurRegion(x: 0, y: 0, width: 100, height: 100);
      expect(region.type, 'blur');
      expect(region.strength, 10);
    });
  });

  group('PipConfig', () {
    test('toJson and fromJson roundtrip', () {
      const pip = PipConfig(
        overlayPath: '/overlay.mp4',
        position: 'topLeft',
        scale: 0.3,
      );
      final json = pip.toJson();
      final restored = PipConfig.fromJson(json);
      expect(restored, pip);
    });

    test('defaults', () {
      const pip = PipConfig(overlayPath: '/a.mp4');
      expect(pip.position, 'bottomRight');
      expect(pip.scale, 0.25);
    });
  });

  group('SplitScreenConfig', () {
    test('toJson and fromJson roundtrip', () {
      const ss = SplitScreenConfig(
        filePaths: ['/a.mp4', '/b.mp4'],
        layout: 'vertical',
      );
      final json = ss.toJson();
      final restored = SplitScreenConfig.fromJson(json);
      expect(restored, ss);
    });

    test('equality checks file list order', () {
      const a = SplitScreenConfig(filePaths: ['/a.mp4', '/b.mp4']);
      const b = SplitScreenConfig(filePaths: ['/b.mp4', '/a.mp4']);
      expect(a, isNot(b));
    });
  });

  group('OutputFormat', () {
    test('extension returns correct value for each format', () {
      expect(OutputFormat.mp4.extension, 'mp4');
      expect(OutputFormat.mkv.extension, 'mkv');
      expect(OutputFormat.mp3.extension, 'mp3');
      expect(OutputFormat.gif.extension, 'gif');
      expect(OutputFormat.m4a.extension, 'm4a');
    });

    test('isAudioOnly for audio formats', () {
      expect(OutputFormat.mp3.isAudioOnly, isTrue);
      expect(OutputFormat.aac.isAudioOnly, isTrue);
      expect(OutputFormat.flac.isAudioOnly, isTrue);
      expect(OutputFormat.wav.isAudioOnly, isTrue);
      expect(OutputFormat.ogg.isAudioOnly, isTrue);
      expect(OutputFormat.opus.isAudioOnly, isTrue);
      expect(OutputFormat.m4a.isAudioOnly, isTrue);
      expect(OutputFormat.wma.isAudioOnly, isTrue);
    });

    test('isAudioOnly false for video formats', () {
      expect(OutputFormat.mp4.isAudioOnly, isFalse);
      expect(OutputFormat.mkv.isAudioOnly, isFalse);
      expect(OutputFormat.webm.isAudioOnly, isFalse);
    });

    test('isAnimatedImage for gif and webp', () {
      expect(OutputFormat.gif.isAnimatedImage, isTrue);
      expect(OutputFormat.webp.isAnimatedImage, isTrue);
      expect(OutputFormat.mp4.isAnimatedImage, isFalse);
    });

    test('fromExtension finds correct format', () {
      expect(OutputFormat.fromExtension('mp4'), OutputFormat.mp4);
      expect(OutputFormat.fromExtension('MP4'), OutputFormat.mp4);
      expect(OutputFormat.fromExtension('.mkv'), OutputFormat.mkv);
      expect(OutputFormat.fromExtension('mp3'), OutputFormat.mp3);
    });

    test('fromExtension returns null for unknown', () {
      expect(OutputFormat.fromExtension('xyz'), isNull);
      expect(OutputFormat.fromExtension(''), isNull);
    });

    test('ffmpegFormat is set correctly', () {
      expect(OutputFormat.mp4.ffmpegFormat, 'mp4');
      expect(OutputFormat.ts.ffmpegFormat, 'mpegts');
      expect(OutputFormat.aac.ffmpegFormat, 'adts');
      expect(OutputFormat.m4a.ffmpegFormat, 'ipod');
    });
  });

  group('VideoCodecOption', () {
    test('ffmpegName for each codec', () {
      expect(VideoCodecOption.h264.ffmpegName, 'libx264');
      expect(VideoCodecOption.h265.ffmpegName, 'libx265');
      expect(VideoCodecOption.vp9.ffmpegName, 'libvpx-vp9');
      expect(VideoCodecOption.av1.ffmpegName, 'libaom-av1');
      expect(VideoCodecOption.copy.ffmpegName, 'copy');
      expect(VideoCodecOption.none.ffmpegName, 'none');
    });
  });

  group('AudioCodecOption', () {
    test('ffmpegName for each codec', () {
      expect(AudioCodecOption.aac.ffmpegName, 'aac');
      expect(AudioCodecOption.mp3.ffmpegName, 'libmp3lame');
      expect(AudioCodecOption.opus.ffmpegName, 'libopus');
      expect(AudioCodecOption.flac.ffmpegName, 'flac');
      expect(AudioCodecOption.copy.ffmpegName, 'copy');
      expect(AudioCodecOption.none.ffmpegName, 'none');
    });
  });

  group('ResolutionOption', () {
    test('height values', () {
      expect(ResolutionOption.original.height, 0);
      expect(ResolutionOption.p1080.height, 1080);
      expect(ResolutionOption.p720.height, 720);
      expect(ResolutionOption.p480.height, 480);
      expect(ResolutionOption.p2160.height, 2160);
      expect(ResolutionOption.custom.height, -1);
    });
  });

  group('WatermarkPosition', () {
    test('overlayExpression for each position', () {
      expect(WatermarkPosition.topLeft.overlayExpression, 'overlay=10:10');
      expect(WatermarkPosition.topRight.overlayExpression, 'overlay=W-w-10:10');
      expect(
        WatermarkPosition.bottomLeft.overlayExpression,
        'overlay=10:H-h-10',
      );
      expect(
        WatermarkPosition.bottomRight.overlayExpression,
        'overlay=W-w-10:H-h-10',
      );
      expect(
        WatermarkPosition.center.overlayExpression,
        'overlay=(W-w)/2:(H-h)/2',
      );
    });
  });

  group('ConversionStatus', () {
    test('isTerminal for completed, failed, cancelled', () {
      expect(ConversionStatus.completed.isTerminal, isTrue);
      expect(ConversionStatus.failed.isTerminal, isTrue);
      expect(ConversionStatus.cancelled.isTerminal, isTrue);
    });

    test('isTerminal false for active states', () {
      expect(ConversionStatus.queued.isTerminal, isFalse);
      expect(ConversionStatus.probing.isTerminal, isFalse);
      expect(ConversionStatus.converting.isTerminal, isFalse);
      expect(ConversionStatus.paused.isTerminal, isFalse);
    });

    test('isActive for probing and converting', () {
      expect(ConversionStatus.probing.isActive, isTrue);
      expect(ConversionStatus.converting.isActive, isTrue);
    });

    test('isActive false for other states', () {
      expect(ConversionStatus.queued.isActive, isFalse);
      expect(ConversionStatus.paused.isActive, isFalse);
      expect(ConversionStatus.completed.isActive, isFalse);
      expect(ConversionStatus.failed.isActive, isFalse);
    });

    test('fromString parses known values', () {
      expect(ConversionStatus.fromString('queued'), ConversionStatus.queued);
      expect(
        ConversionStatus.fromString('converting'),
        ConversionStatus.converting,
      );
      expect(
        ConversionStatus.fromString('completed'),
        ConversionStatus.completed,
      );
      expect(ConversionStatus.fromString('failed'), ConversionStatus.failed);
    });

    test('fromString defaults to queued for unknown', () {
      expect(ConversionStatus.fromString('unknown'), ConversionStatus.queued);
      expect(ConversionStatus.fromString(''), ConversionStatus.queued);
    });

    test('displayName returns non-empty string', () {
      for (final status in ConversionStatus.values) {
        expect(status.displayName, isNotEmpty);
      }
    });
  });
}
