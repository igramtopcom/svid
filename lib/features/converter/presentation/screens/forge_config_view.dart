import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';

import '../../../../core/binaries/binary_providers.dart';
import '../../../../core/binaries/binary_type.dart';
import '../../../../core/core.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/conversion_preset.dart';
import '../../domain/entities/media_info.dart';
import '../providers/converter_providers.dart';
import '../widgets/brightness_contrast_panel.dart';
import '../widgets/color_grading_widget.dart';
import '../widgets/concat_panel.dart';
import '../widgets/audio_eq_panel.dart';
import '../widgets/crop_config_widget.dart';
import '../widgets/denoise_strength_panel.dart';
import '../widgets/fade_config_panel.dart';
import '../widgets/grain_intensity_panel.dart';
import '../widgets/letterbox_panel.dart';
import '../widgets/loop_count_panel.dart';
import '../widgets/output_config_panel.dart';
import '../widgets/rotate_flip_panel.dart';
import '../widgets/sharpen_strength_panel.dart';
import '../widgets/speed_control_panel.dart';
import '../widgets/subtitle_burnin_panel.dart';
import '../widgets/tools_config_panel.dart';
import '../widgets/trim_panel.dart';
import '../widgets/volume_panel.dart';
import '../widgets/watermark_panel.dart';

/// Post-preset configuration panel — shown after a preset is selected.
///
/// Displays:
/// 1. Selected preset info bar with "change" action
/// 2. Per-preset config widgets (crop, trim, color grading, etc.)
/// 3. Output format config (for convert presets) or skipped (for enhance)
/// 4. Output directory selector
/// 5. "FIRE CONVERSION" CTA button
class ForgeConfigView extends ConsumerWidget {
  final ConversionPreset selectedPreset;
  final MediaInfo? selectedFileInfo;
  final List<String> concatFiles;
  final String? selectedColorEffectId;
  final ValueChanged<List<String>> onConcatFilesChanged;
  final ValueChanged<String?> onColorEffectChanged;
  final VoidCallback onStartConversion;

  const ForgeConfigView({
    super.key,
    required this.selectedPreset,
    required this.selectedFileInfo,
    required this.concatFiles,
    required this.selectedColorEffectId,
    required this.onConcatFilesChanged,
    required this.onColorEffectChanged,
    required this.onStartConversion,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Determine which config widgets to show based on preset
    final isConvertPreset = _isConvertCategory(selectedPreset.category);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected preset info bar
        _SelectedPresetBar(preset: selectedPreset),
        const SizedBox(height: 12),

        // Output config panel (for convert-type presets)
        if (isConvertPreset) const OutputConfigPanel(),

        // Per-preset enhancement config widgets
        ..._buildPresetConfigWidgets(context, ref),

        // Output directory
        const SizedBox(height: 12),
        _OutputDirRow(
          outputDir: ref.watch(converterOutputDirProvider),
          onChanged:
              (dir) =>
                  ref.read(converterOutputDirProvider.notifier).state = dir,
        ),
        const SizedBox(height: 14),

        // Convert / Apply button
        _buildConvertButton(context, ref),
      ],
    );
  }

  bool _isConvertCategory(PresetCategory category) {
    return category == PresetCategory.format ||
        category == PresetCategory.device ||
        category == PresetCategory.social ||
        category == PresetCategory.audio ||
        category == PresetCategory.advanced ||
        category == PresetCategory.custom;
  }

  List<Widget> _buildPresetConfigWidgets(BuildContext context, WidgetRef ref) {
    final widgets = <Widget>[];
    final id = selectedPreset.id;

    if (id == 'crop_custom') {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CropConfigWidget(
            mediaInfo: selectedFileInfo,
            initialCrop: ref.read(conversionConfigProvider).crop,
            onCropChanged: (crop) {
              final notifier = ref.read(conversionConfigProvider.notifier);
              if (crop != null) {
                notifier.setConfig(
                  ref.read(conversionConfigProvider).copyWith(crop: crop),
                );
              } else {
                notifier.setConfig(
                  ref.read(conversionConfigProvider).copyWith(clearCrop: true),
                );
              }
            },
          ),
        ),
      );
    }

    if (id == 'merge_join') {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: ConcatPanel(
            initialFiles: concatFiles,
            onFilesChanged: onConcatFilesChanged,
          ),
        ),
      );
    }

    if (id.startsWith('lut_')) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: ColorGradingWidget(
            selectedEffectId: selectedColorEffectId,
            onPresetSelected: (ColorGradingPreset? colorPreset) {
              onColorEffectChanged(colorPreset?.id);
              final notifier = ref.read(conversionConfigProvider.notifier);
              if (colorPreset != null) {
                notifier.setConfig(
                  ref
                      .read(conversionConfigProvider)
                      .copyWith(colorEffect: colorPreset.filterChain),
                );
              } else {
                notifier.setConfig(
                  ref
                      .read(conversionConfigProvider)
                      .copyWith(clearColorEffect: true),
                );
              }
            },
          ),
        ),
      );
    }

    if (id == 'auto_brightness' || id == 'night_mode') {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: BrightnessContrastPanel(
            initialBrightness: ref.read(conversionConfigProvider).brightness,
            initialContrast: ref.read(conversionConfigProvider).contrast,
            initialSaturation: ref.read(conversionConfigProvider).saturation,
            initialGamma: ref.read(conversionConfigProvider).gamma,
            onChanged: ({
              double? brightness,
              double? contrast,
              double? saturation,
              double? gamma,
            }) {
              ref
                  .read(conversionConfigProvider.notifier)
                  .setConfig(
                    ref
                        .read(conversionConfigProvider)
                        .copyWith(
                          brightness: brightness,
                          contrast: contrast,
                          saturation: saturation,
                          gamma: gamma,
                          clearBrightness: brightness == null,
                          clearContrast: contrast == null,
                          clearSaturation: saturation == null,
                          clearGamma: gamma == null,
                        ),
                  );
            },
          ),
        ),
      );
    }

    if (id.startsWith('volume_')) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: VolumePanel(
            initialVolumeDb: ref.read(conversionConfigProvider).volumeDb,
            onVolumeChanged: (db) {
              ref
                  .read(conversionConfigProvider.notifier)
                  .setConfig(
                    ref
                        .read(conversionConfigProvider)
                        .copyWith(volumeDb: db, clearVolumeDb: db == null),
                  );
            },
          ),
        ),
      );
    }

    if (id == 'trim_cut') {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: TrimPanel(
            mediaDuration: selectedFileInfo?.duration,
            initialTrim: ref.read(conversionConfigProvider).trim,
            onTrimChanged: (trim) {
              ref
                  .read(conversionConfigProvider.notifier)
                  .setConfig(
                    ref
                        .read(conversionConfigProvider)
                        .copyWith(trim: trim, clearTrim: trim == null),
                  );
            },
          ),
        ),
      );
    }

    if (id == 'watermark') {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: WatermarkPanel(
            initialPath: ref.read(conversionConfigProvider).watermarkPath,
            initialPosition:
                ref.read(conversionConfigProvider).watermarkPosition,
            onChanged: ({String? path, position}) {
              ref
                  .read(conversionConfigProvider.notifier)
                  .setConfig(
                    ref
                        .read(conversionConfigProvider)
                        .copyWith(
                          watermarkPath: path,
                          watermarkPosition: position,
                          clearWatermarkPath: path == null,
                          clearWatermarkPosition: position == null,
                        ),
                  );
            },
          ),
        ),
      );
    }

    if (id == 'burn_subtitles') {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SubtitleBurninPanel(
            initialPath: ref.read(conversionConfigProvider).subtitlePath,
            onPathChanged: (path) {
              ref
                  .read(conversionConfigProvider.notifier)
                  .setConfig(
                    ref
                        .read(conversionConfigProvider)
                        .copyWith(
                          subtitlePath: path,
                          clearSubtitlePath: path == null,
                        ),
                  );
            },
          ),
        ),
      );
    }

    if (id == 'extract_thumbnail') {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: ThumbnailConfigPanel(
            mediaDuration: selectedFileInfo?.duration,
            initialTimestamp:
                ref.read(conversionConfigProvider).thumbnailTimestamp,
            onTimestampChanged: (t) {
              ref
                  .read(conversionConfigProvider.notifier)
                  .setConfig(
                    ref
                        .read(conversionConfigProvider)
                        .copyWith(thumbnailTimestamp: t),
                  );
            },
          ),
        ),
      );
    }

    if (id == 'extract_subtitles') {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SubtitleTrackPanel(
            mediaInfo: selectedFileInfo,
            initialTrack: ref.read(conversionConfigProvider).subtitleTrackIndex,
            onTrackChanged: (i) {
              ref
                  .read(conversionConfigProvider.notifier)
                  .setConfig(
                    ref
                        .read(conversionConfigProvider)
                        .copyWith(subtitleTrackIndex: i),
                  );
            },
          ),
        ),
      );
    }

    if (id == 'split_video') {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SplitIntervalPanel(
            initialInterval: ref.read(conversionConfigProvider).splitInterval,
            onIntervalChanged: (interval) {
              ref
                  .read(conversionConfigProvider.notifier)
                  .setConfig(
                    ref
                        .read(conversionConfigProvider)
                        .copyWith(splitInterval: interval),
                  );
            },
          ),
        ),
      );
    }

    // Speed control (slow motion / fast forward presets)
    if (id == 'slow_motion_05x' || id == 'fast_forward_2x') {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SpeedControlPanel(
            initialSpeed: ref.read(conversionConfigProvider).speed,
            onSpeedChanged: (speed) {
              ref
                  .read(conversionConfigProvider.notifier)
                  .setConfig(
                    ref
                        .read(conversionConfigProvider)
                        .copyWith(speed: speed, clearSpeed: speed == null),
                  );
            },
          ),
        ),
      );
    }

    // Denoise strength selector
    if (id == 'denoise_light' || id == 'denoise_strong') {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: DenoiseStrengthPanel(
            initialStrength: ref.read(conversionConfigProvider).denoiseStrength,
            onStrengthChanged: (strength) {
              ref
                  .read(conversionConfigProvider.notifier)
                  .setConfig(
                    ref
                        .read(conversionConfigProvider)
                        .copyWith(
                          denoiseStrength: strength,
                          clearDenoiseStrength: strength == null,
                        ),
                  );
            },
          ),
        ),
      );
    }

    // Sharpen strength slider
    if (id == 'sharpen_light' || id == 'sharpen_strong') {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SharpenStrengthPanel(
            initialStrength: ref.read(conversionConfigProvider).sharpenStrength,
            onStrengthChanged: (strength) {
              ref
                  .read(conversionConfigProvider.notifier)
                  .setConfig(
                    ref
                        .read(conversionConfigProvider)
                        .copyWith(
                          sharpenStrength: strength,
                          clearSharpenStrength: strength == null,
                        ),
                  );
            },
          ),
        ),
      );
    }

    // Fade in/out config
    if (id == 'cinematic_fade') {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: FadeConfigPanel(
            initialFadeIn: ref.read(conversionConfigProvider).fadeIn,
            initialFadeOut: ref.read(conversionConfigProvider).fadeOut,
            initialDuration: ref.read(conversionConfigProvider).fadeDuration,
            onChanged: ({
              required bool fadeIn,
              required bool fadeOut,
              required double? duration,
            }) {
              ref
                  .read(conversionConfigProvider.notifier)
                  .setConfig(
                    ref
                        .read(conversionConfigProvider)
                        .copyWith(
                          fadeIn: fadeIn,
                          fadeOut: fadeOut,
                          fadeDuration: duration,
                          clearFadeDuration: duration == null,
                        ),
                  );
            },
          ),
        ),
      );
    }

    // Film grain intensity
    if (id == 'film_grain') {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: GrainIntensityPanel(
            initialIntensity: ref.read(conversionConfigProvider).grainIntensity,
            onIntensityChanged: (intensity) {
              ref
                  .read(conversionConfigProvider.notifier)
                  .setConfig(
                    ref
                        .read(conversionConfigProvider)
                        .copyWith(
                          grainIntensity: intensity,
                          clearGrainIntensity: intensity == null,
                        ),
                  );
            },
          ),
        ),
      );
    }

    // Loop count picker
    if (id == 'loop_2x' || id == 'loop_3x') {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: LoopCountPanel(
            initialCount: ref.read(conversionConfigProvider).loopCount,
            onCountChanged: (count) {
              ref
                  .read(conversionConfigProvider.notifier)
                  .setConfig(
                    ref
                        .read(conversionConfigProvider)
                        .copyWith(
                          loopCount: count,
                          clearLoopCount: count == null,
                        ),
                  );
            },
          ),
        ),
      );
    }

    // Rotate / flip direction selector
    if (id.startsWith('rotate_') || id.startsWith('flip_')) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: RotateFlipPanel(
            initialOption: ref.read(conversionConfigProvider).rotate,
            onChanged: (opt) {
              ref
                  .read(conversionConfigProvider.notifier)
                  .setConfig(
                    ref
                        .read(conversionConfigProvider)
                        .copyWith(rotate: opt, clearRotate: opt == null),
                  );
            },
          ),
        ),
      );
    }

    // Audio EQ preset selector
    if (id == 'bass_boost' ||
        id == 'treble_boost' ||
        id == 'voice_enhance' ||
        id == 'cinema_audio' ||
        id == 'podcast_optimize') {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: AudioEqPanel(
            initialPreset: ref.read(conversionConfigProvider).audioEqPreset,
            onPresetChanged: (preset) {
              ref
                  .read(conversionConfigProvider.notifier)
                  .setConfig(
                    ref
                        .read(conversionConfigProvider)
                        .copyWith(
                          audioEqPreset: preset,
                          clearAudioEqPreset: preset == null,
                        ),
                  );
            },
          ),
        ),
      );
    }

    // Letterbox aspect ratio selector
    if (id.startsWith('letterbox_')) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: LetterboxPanel(
            initialRatio: ref.read(conversionConfigProvider).letterbox,
            onRatioChanged: (ratio) {
              ref
                  .read(conversionConfigProvider.notifier)
                  .setConfig(
                    ref
                        .read(conversionConfigProvider)
                        .copyWith(
                          letterbox: ratio,
                          clearLetterbox: ratio == null,
                        ),
                  );
            },
          ),
        ),
      );
    }

    return widgets;
  }

  Widget _buildConvertButton(BuildContext context, WidgetRef ref) {
    final isEnhance = !_isConvertCategory(selectedPreset.category);
    final ffmpegAvailable = ref.watch(
      binaryAvailableProvider(BinaryType.ffmpeg),
    );
    final isEnabled = ffmpegAvailable.valueOrNull ?? false;

    return Container(
      width: double.infinity,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow:
            isEnabled
                ? [
                  BoxShadow(
                    color: AppColors.accentHighlight.withValues(alpha: 0.45),
                    blurRadius: 16,
                    spreadRadius: -2,
                    offset: const Offset(0, 2),
                  ),
                ]
                : null,
      ),
      child: ElevatedButton.icon(
        onPressed: isEnabled ? onStartConversion : null,
        icon: Icon(
          isEnhance ? Icons.auto_fix_high_rounded : Icons.bolt_rounded,
          size: 18,
        ),
        label: Text(
          isEnhance ? 'converter.enhance.apply'.tr() : 'converter.convert'.tr(),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentHighlight,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
        ),
      ),
    );
  }
}

/// Selected preset info bar — shows which preset is active with a change action.
class _SelectedPresetBar extends StatelessWidget {
  final ConversionPreset preset;

  const _SelectedPresetBar({required this.preset});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accentHighlight.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: AppColors.accentHighlight.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 14,
            color: AppColors.accentHighlight,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'converter.activePreset'.tr(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                    color: AppColors.accentHighlight.withValues(alpha: 0.7),
                  ),
                ),
                Text(
                  preset.name,
                  style: tt.labelMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Output directory row — shows destination path + choose/reveal/reset buttons.
class _OutputDirRow extends ConsumerWidget {
  final String? outputDir;
  final ValueChanged<String?> onChanged;

  const _OutputDirRow({required this.outputDir, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hasCustom = outputDir != null;
    final label = outputDir ?? 'converter.outputSameAsInput'.tr();

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color:
            hasCustom
                ? AppColors.accentHighlight.withValues(alpha: 0.06)
                : AppColors.surface2(context),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color:
              hasCustom
                  ? AppColors.accentHighlight.withValues(alpha: 0.15)
                  : AppColors.border(context).withValues(alpha: 0.50),
          width: hasCustom ? 1.2 : 1.0,
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasCustom ? Icons.folder_rounded : Icons.folder_outlined,
            size: 16,
            color: hasCustom ? AppColors.accentHighlight : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'converter.outputDestination'.tr(),
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  style: tt.labelSmall?.copyWith(
                    color: hasCustom ? cs.onSurface : cs.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: hasCustom ? FontWeight.w600 : FontWeight.w400,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (hasCustom)
            Tooltip(
              message: 'converter.revealOutputDir'.tr(),
              preferBelow: false,
              child: InkWell(
                onTap: () => _openDir(outputDir!),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.open_in_new_rounded,
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          TextButton.icon(
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: AppColors.accentHighlight,
            ),
            onPressed: () async {
              final downloadDir = ref.read(downloadPathProvider);
              final dir = await FilePicker.platform.getDirectoryPath(
                initialDirectory: outputDir ?? downloadDir,
              );
              if (!context.mounted) return;
              if (dir != null) onChanged(dir);
            },
            icon: const Icon(Icons.drive_folder_upload_rounded, size: 14),
            label: Text(
              hasCustom
                  ? 'converter.changeOutput'.tr()
                  : 'converter.chooseOutput'.tr(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          if (hasCustom)
            Tooltip(
              message: 'converter.resetOutput'.tr(),
              preferBelow: false,
              child: InkWell(
                onTap: () => onChanged(null),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openDir(String dir) {
    if (Platform.isMacOS) {
      ProcessHelper.openDirectoryInFileManager(dir).ignore();
    } else if (Platform.isWindows) {
      ProcessHelper.openDirectoryInFileManager(dir).ignore();
    } else if (Platform.isLinux) {
      ProcessHelper.openDirectoryInFileManager(dir).ignore();
    }
  }
}
