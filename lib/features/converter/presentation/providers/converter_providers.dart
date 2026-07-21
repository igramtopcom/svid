import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/binaries/binary_providers.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../data/datasources/conversion_datasource.dart';
import '../../data/repositories/conversion_repository_impl.dart';
import '../../domain/entities/conversion_config.dart';
import '../../domain/entities/conversion_preset.dart';
import '../../domain/entities/hw_accel_info.dart';
import '../../domain/entities/media_info.dart';
import '../../domain/entities/output_format.dart';
import '../../domain/repositories/conversion_repository.dart';
import '../../domain/services/custom_preset_store.dart';
import '../../domain/services/ffmpeg_command_builder.dart';
import '../../domain/services/hw_accel_detector.dart';
import '../../domain/services/preset_service.dart';
import '../../domain/usecases/convert_file_usecase.dart';
import '../../domain/usecases/probe_media_usecase.dart';

// ==================== SERVICES ====================

/// FFmpeg command builder service
final ffmpegCommandBuilderProvider = Provider<FFmpegCommandBuilder>((ref) {
  return FFmpegCommandBuilder();
});

/// Preset service with all built-in conversion presets
final presetServiceProvider = Provider<PresetService>((ref) {
  return PresetService();
});

/// Persistence layer for user-saved custom presets (SharedPreferences-backed).
final customPresetStoreProvider = Provider<CustomPresetStore>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return CustomPresetStore(prefs);
});

/// Reactive list of user-saved custom presets. UI watches this provider to
/// rebuild the "Custom" tab in [PresetSelector] whenever the user adds or
/// removes a preset.
final customPresetsProvider =
    StateNotifierProvider<CustomPresetsNotifier, List<ConversionPreset>>((ref) {
      final store = ref.watch(customPresetStoreProvider);
      return CustomPresetsNotifier(store);
    });

/// Hardware acceleration detector
final hwAccelDetectorProvider = Provider<HwAccelDetector>((ref) {
  final binaryManager = ref.watch(binaryManagerProvider);
  return HwAccelDetector(binaryManager);
});

// ==================== DATA SOURCES ====================

/// Conversion datasource (ffmpeg/ffprobe process management)
final conversionDatasourceProvider = Provider<ConversionDatasource>((ref) {
  final binaryManager = ref.watch(binaryManagerProvider);
  final commandBuilder = ref.watch(ffmpegCommandBuilderProvider);
  final hwAccelDetector = ref.watch(hwAccelDetectorProvider);
  return ConversionDatasource(binaryManager, commandBuilder, hwAccelDetector);
});

// ==================== REPOSITORY ====================

/// Conversion repository
final conversionRepositoryProvider = Provider<ConversionRepository>((ref) {
  final datasource = ref.watch(conversionDatasourceProvider);
  return ConversionRepositoryImpl(datasource);
});

// ==================== USE CASES ====================

/// Probe media file info use case
final probeMediaUseCaseProvider = Provider<ProbeMediaUseCase>((ref) {
  final repository = ref.watch(conversionRepositoryProvider);
  return ProbeMediaUseCase(repository);
});

/// Convert file use case
final convertFileUseCaseProvider = Provider<ConvertFileUseCase>((ref) {
  final repository = ref.watch(conversionRepositoryProvider);
  return ConvertFileUseCase(repository);
});

// ==================== STATE ====================

/// Currently selected preset (null = custom configuration)
final selectedPresetProvider = StateProvider<ConversionPreset?>((ref) => null);

/// Current conversion configuration being edited
final conversionConfigProvider =
    StateNotifierProvider<ConversionConfigNotifier, ConversionConfig>((ref) {
      return ConversionConfigNotifier();
    });

/// Detect available hardware acceleration (cached)
final hwAccelInfoProvider = FutureProvider<List<HwAccelInfo>>((ref) async {
  final repository = ref.watch(conversionRepositoryProvider);
  return repository.detectHardwareAccel();
});

/// Probe result for the currently selected input file
final probeResultProvider = StateProvider<AsyncValue<MediaInfo?>>(
  (ref) => const AsyncValue.data(null),
);

/// Input file path set from external navigation (e.g., download context menu "Convert" action).
/// Converter screen watches this on init and auto-probes if set.
final converterInputFileProvider = StateProvider<String?>((ref) => null);

/// Custom output directory for converter. Null means same directory as input file.
final converterOutputDirProvider = StateProvider<String?>((ref) => null);

// ==================== CONFIG NOTIFIER ====================

/// Manages the current conversion configuration state.
class ConversionConfigNotifier extends StateNotifier<ConversionConfig> {
  ConversionConfigNotifier()
    : super(const ConversionConfig(outputFormat: OutputFormat.mp4));

  /// Replace entire config (e.g., when selecting a preset)
  void setConfig(ConversionConfig config) {
    state = config;
  }

  /// Update output format
  void setOutputFormat(OutputFormat format) {
    final audioCodec = _preferredAudioCodecForFormat(format);
    state = state.copyWith(
      outputFormat: format,
      audioCodec: audioCodec,
      videoCodec: format.isAudioOnly ? VideoCodecOption.none : null,
      clearVideoCodec:
          !format.isAudioOnly && state.videoCodec == VideoCodecOption.none,
    );
  }

  /// Update video codec
  void setVideoCodec(VideoCodecOption? codec) {
    if (codec == null) {
      state = state.copyWith(clearVideoCodec: true);
    } else {
      state = state.copyWith(videoCodec: codec);
    }
  }

  /// Update audio codec
  void setAudioCodec(AudioCodecOption? codec) {
    if (codec == null) {
      state = state.copyWith(clearAudioCodec: true);
    } else {
      final outputFormat =
          state.outputFormat.isAudioOnly
              ? _preferredAudioFormatForCodec(codec) ?? state.outputFormat
              : state.outputFormat;
      state = state.copyWith(
        outputFormat: outputFormat,
        audioCodec: codec,
        videoCodec: outputFormat.isAudioOnly ? VideoCodecOption.none : null,
      );
    }
  }

  AudioCodecOption? _preferredAudioCodecForFormat(OutputFormat format) {
    switch (format) {
      case OutputFormat.mp3:
        return AudioCodecOption.mp3;
      case OutputFormat.aac:
      case OutputFormat.m4a:
        return AudioCodecOption.aac;
      case OutputFormat.flac:
        return AudioCodecOption.flac;
      case OutputFormat.wav:
        return AudioCodecOption.pcm;
      case OutputFormat.ogg:
        return AudioCodecOption.vorbis;
      case OutputFormat.opus:
        return AudioCodecOption.opus;
      default:
        return null;
    }
  }

  OutputFormat? _preferredAudioFormatForCodec(AudioCodecOption codec) {
    switch (codec) {
      case AudioCodecOption.mp3:
        return OutputFormat.mp3;
      case AudioCodecOption.aac:
        return OutputFormat.m4a;
      case AudioCodecOption.flac:
        return OutputFormat.flac;
      case AudioCodecOption.pcm:
        return OutputFormat.wav;
      case AudioCodecOption.vorbis:
        return OutputFormat.ogg;
      case AudioCodecOption.opus:
        return OutputFormat.opus;
      case AudioCodecOption.copy:
      case AudioCodecOption.none:
        return null;
    }
  }

  /// Update CRF value
  void setCrf(int? crf) {
    if (crf == null) {
      state = state.copyWith(clearCrf: true);
    } else {
      state = state.copyWith(crf: crf);
    }
  }

  /// Update video bitrate (kbps)
  void setVideoBitrate(int? bitrate) {
    if (bitrate == null) {
      state = state.copyWith(clearVideoBitrate: true);
    } else {
      state = state.copyWith(videoBitrate: bitrate);
    }
  }

  /// Update encoder preset
  void setEncoderPreset(String? preset) {
    if (preset == null) {
      state = state.copyWith(clearEncoderPreset: true);
    } else {
      state = state.copyWith(encoderPreset: preset);
    }
  }

  /// Update resolution
  void setResolution(ResolutionOption? resolution) {
    if (resolution == null) {
      state = state.copyWith(clearResolution: true);
    } else {
      state = state.copyWith(resolution: resolution);
    }
  }

  /// Update custom dimensions
  void setCustomDimensions({int? width, int? height}) {
    state = state.copyWith(
      customWidth: width,
      customHeight: height,
      resolution: ResolutionOption.custom,
    );
  }

  /// Update FPS
  void setFps(int? fps) {
    if (fps == null) {
      state = state.copyWith(clearFps: true);
    } else {
      state = state.copyWith(fps: fps);
    }
  }

  /// Update audio bitrate
  void setAudioBitrate(int? bitrate) {
    if (bitrate == null) {
      state = state.copyWith(clearAudioBitrate: true);
    } else {
      state = state.copyWith(audioBitrate: bitrate);
    }
  }

  /// Update audio sample rate
  void setAudioSampleRate(int? rate) {
    if (rate == null) {
      state = state.copyWith(clearAudioSampleRate: true);
    } else {
      state = state.copyWith(audioSampleRate: rate);
    }
  }

  /// Update audio channels
  void setAudioChannels(int? channels) {
    if (channels == null) {
      state = state.copyWith(clearAudioChannels: true);
    } else {
      state = state.copyWith(audioChannels: channels);
    }
  }

  /// Toggle hardware acceleration
  void setHwAccel(bool enabled) {
    state = state.copyWith(hwAccel: enabled);
  }

  /// Toggle two-pass encoding
  void setTwoPass(bool enabled) {
    state = state.copyWith(twoPass: enabled);
  }

  /// Toggle audio normalization
  void setNormalize(bool enabled) {
    state = state.copyWith(normalize: enabled);
  }

  /// Update speed multiplier
  void setSpeed(double? speed) {
    if (speed == null) {
      state = state.copyWith(clearSpeed: true);
    } else {
      state = state.copyWith(speed: speed);
    }
  }

  /// Reset to default config
  void reset() {
    state = const ConversionConfig(outputFormat: OutputFormat.mp4);
  }
}

// ==================== CUSTOM PRESETS NOTIFIER ====================

/// Manages the user's custom-preset list, persisted via [CustomPresetStore].
///
/// Loads existing presets eagerly on construction so the UI shows them on
/// first paint without an extra async hop. Mutations write through to disk
/// and update [state] so all watchers rebuild.
class CustomPresetsNotifier extends StateNotifier<List<ConversionPreset>> {
  final CustomPresetStore _store;

  CustomPresetsNotifier(this._store) : super(const []) {
    state = _store.loadAll();
  }

  /// Persist a new preset built from the current config + user-supplied
  /// metadata. Generates a stable id from a timestamp prefix so two presets
  /// with the same name don't collide.
  Future<void> add({
    required String name,
    required String icon,
    required String description,
    required ConversionConfig config,
  }) async {
    final preset = ConversionPreset(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      icon: icon,
      description: description,
      config: config,
      category: PresetCategory.custom,
    );
    state = await _store.add(preset);
  }

  /// Delete a custom preset by id.
  Future<void> remove(String id) async {
    state = await _store.remove(id);
  }
}
