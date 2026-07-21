import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/conversion_config.dart';
import '../../domain/entities/output_format.dart';
import '../providers/converter_providers.dart';

/// Expandable panel for configuring output format, codecs, quality,
/// resolution, and advanced options.
class OutputConfigPanel extends ConsumerStatefulWidget {
  const OutputConfigPanel({super.key});

  @override
  ConsumerState<OutputConfigPanel> createState() => _OutputConfigPanelState();
}

class _OutputConfigPanelState extends ConsumerState<OutputConfigPanel> {
  bool _showAdvanced = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final config = ref.watch(conversionConfigProvider);
    final configNotifier = ref.read(conversionConfigProvider.notifier);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: AppColors.border(context).withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'converter.outputConfig'.tr(),
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Tooltip(
                message: 'converter.customPreset.saveTooltip'.tr(),
                preferBelow: false,
                child: InkWell(
                  onTap: () => _openSavePresetDialog(context, config),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bookmark_add_outlined,
                          size: 14,
                          color: AppColors.accentHighlight,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'converter.customPreset.saveButton'.tr(),
                          style: tt.labelSmall?.copyWith(
                            color: AppColors.accentHighlight,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Row 1: Format + Video Codec
          Row(
            children: [
              Expanded(
                child: _DropdownField<OutputFormat>(
                  label: 'converter.format'.tr(),
                  tooltip: 'converter.tooltips.format'.tr(),
                  value: config.outputFormat,
                  items: OutputFormat.values,
                  itemLabel: (f) => f.displayName,
                  onChanged: (f) {
                    if (f != null) configNotifier.setOutputFormat(f);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DropdownField<VideoCodecOption>(
                  label: 'converter.videoCodec'.tr(),
                  tooltip: 'converter.tooltips.videoCodec'.tr(),
                  value: config.videoCodec,
                  items: VideoCodecOption.values,
                  itemLabel: (c) => c.displayName,
                  onChanged: (c) => configNotifier.setVideoCodec(c),
                  enabled: !config.outputFormat.isAudioOnly,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DropdownField<AudioCodecOption>(
                  label: 'converter.audioCodec'.tr(),
                  tooltip: 'converter.tooltips.audioCodec'.tr(),
                  value: config.audioCodec,
                  items: AudioCodecOption.values,
                  itemLabel: (c) => c.displayName,
                  onChanged: (c) => configNotifier.setAudioCodec(c),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Row 2: Quality + Resolution
          Row(
            children: [
              Expanded(
                child: _SliderField(
                  label: 'converter.quality'.tr(),
                  tooltip: 'converter.tooltips.crf'.tr(),
                  value: (config.crf ?? 23).toDouble(),
                  min: 0,
                  max: 51,
                  divisions: 51,
                  valueLabel: '${config.crf ?? 23}',
                  enabled:
                      config.videoCodec != VideoCodecOption.copy &&
                      config.videoCodec != VideoCodecOption.none &&
                      !config.outputFormat.isAudioOnly &&
                      config.videoBitrate == null,
                  onChanged: (v) => configNotifier.setCrf(v.round()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DropdownField<ResolutionOption>(
                  label: 'converter.resolution'.tr(),
                  tooltip: 'converter.tooltips.resolution'.tr(),
                  value: config.resolution,
                  items: ResolutionOption.values,
                  itemLabel: (r) => r.displayName,
                  onChanged: (r) => configNotifier.setResolution(r),
                  enabled:
                      config.videoCodec != VideoCodecOption.copy &&
                      config.videoCodec != VideoCodecOption.none &&
                      !config.outputFormat.isAudioOnly,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DropdownField<int>(
                  label: 'converter.audioBitrate'.tr(),
                  tooltip: 'converter.tooltips.audioBitrate'.tr(),
                  value: config.audioBitrate,
                  items: const [64, 96, 128, 160, 192, 256, 320],
                  itemLabel: (b) => '$b kbps',
                  onChanged: (b) => configNotifier.setAudioBitrate(b),
                  enabled:
                      config.audioCodec != AudioCodecOption.copy &&
                      config.audioCodec != AudioCodecOption.none,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Advanced toggle
          InkWell(
            onTap: () => setState(() => _showAdvanced = !_showAdvanced),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _showAdvanced
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'converter.advancedOptions'.tr(),
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),

          // Advanced options
          if (_showAdvanced) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _DropdownField<String>(
                    label: 'converter.encoderPreset'.tr(),
                    tooltip: 'converter.tooltips.encoderPreset'.tr(),
                    value: config.encoderPreset,
                    items: const [
                      'ultrafast',
                      'superfast',
                      'veryfast',
                      'faster',
                      'fast',
                      'medium',
                      'slow',
                      'slower',
                      'veryslow',
                    ],
                    itemLabel: (p) => p[0].toUpperCase() + p.substring(1),
                    onChanged: (p) => configNotifier.setEncoderPreset(p),
                    enabled:
                        config.videoCodec == VideoCodecOption.h264 ||
                        config.videoCodec == VideoCodecOption.h265,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DropdownField<int>(
                    label: 'converter.fps'.tr(),
                    tooltip: 'converter.tooltips.fps'.tr(),
                    value: config.fps,
                    items: const [15, 24, 25, 30, 48, 50, 60],
                    itemLabel: (f) => '$f fps',
                    onChanged: (f) => configNotifier.setFps(f),
                    enabled:
                        config.videoCodec != VideoCodecOption.copy &&
                        !config.outputFormat.isAudioOnly,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DropdownField<int>(
                    label: 'converter.sampleRate'.tr(),
                    tooltip: 'converter.tooltips.sampleRate'.tr(),
                    value: config.audioSampleRate,
                    items: const [22050, 44100, 48000, 96000],
                    itemLabel: (r) => '${(r / 1000).toStringAsFixed(1)} kHz',
                    onChanged: (r) => configNotifier.setAudioSampleRate(r),
                    enabled:
                        config.audioCodec != AudioCodecOption.copy &&
                        config.audioCodec != AudioCodecOption.none,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Toggle options
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _ToggleOption(
                  label: 'converter.hwAccel'.tr(),
                  tooltip: 'converter.tooltips.hwAccel'.tr(),
                  value: config.hwAccel,
                  onChanged: (v) => configNotifier.setHwAccel(v),
                ),
                _ToggleOption(
                  label: 'converter.twoPass'.tr(),
                  tooltip: 'converter.tooltips.twoPass'.tr(),
                  value: config.twoPass,
                  onChanged:
                      config.isAudioOnly || config.isStreamCopy
                          ? null
                          : (v) => configNotifier.setTwoPass(v),
                ),
                _ToggleOption(
                  label: 'converter.normalizeAudio'.tr(),
                  tooltip: 'converter.tooltips.normalizeAudio'.tr(),
                  value: config.normalize,
                  onChanged:
                      config.audioCodec == AudioCodecOption.copy
                          ? null
                          : (v) => configNotifier.setNormalize(v),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openSavePresetDialog(
    BuildContext context,
    ConversionConfig config,
  ) async {
    final cs = Theme.of(context).colorScheme;
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String selectedIcon = 'tune';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text('converter.customPreset.saveTitle'.tr()),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 400,
                  maxHeight: MediaQuery.sizeOf(ctx).height * 0.68,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        autofocus: true,
                        maxLength: 40,
                        decoration: InputDecoration(
                          labelText: 'converter.customPreset.nameLabel'.tr(),
                          hintText: 'converter.customPreset.nameHint'.tr(),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descCtrl,
                        maxLength: 80,
                        decoration: InputDecoration(
                          labelText:
                              'converter.customPreset.descriptionLabel'.tr(),
                          hintText:
                              'converter.customPreset.descriptionHint'.tr(),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'converter.customPreset.iconLabel'.tr(),
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children:
                            _customPresetIcons.map((entry) {
                              final isSel = entry.$1 == selectedIcon;
                              return InkWell(
                                onTap:
                                    () =>
                                        setLocal(() => selectedIcon = entry.$1),
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color:
                                        isSel
                                            ? AppColors.accentHighlight
                                                .withValues(alpha: 0.18)
                                            : AppColors.surface2(ctx),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color:
                                          isSel
                                              ? AppColors.accentHighlight
                                              : AppColors.border(
                                                ctx,
                                              ).withValues(alpha: 0.55),
                                      width: isSel ? 1.4 : 0.8,
                                    ),
                                  ),
                                  child: Icon(
                                    entry.$2,
                                    size: 18,
                                    color:
                                        isSel
                                            ? AppColors.accentHighlight
                                            : cs.onSurfaceVariant,
                                  ),
                                ),
                              );
                            }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text('converter.customPreset.cancel'.tr()),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accentHighlight,
                  ),
                  onPressed: () {
                    if (nameCtrl.text.trim().isEmpty) return;
                    Navigator.of(ctx).pop(true);
                  },
                  child: Text('converter.customPreset.save'.tr()),
                ),
              ],
            );
          },
        );
      },
    );
    if (!mounted) return;

    if (saved == true) {
      final name = nameCtrl.text.trim();
      final desc =
          descCtrl.text.trim().isEmpty
              ? 'converter.customPreset.defaultDescription'.tr()
              : descCtrl.text.trim();
      await ref
          .read(customPresetsProvider.notifier)
          .add(
            name: name,
            icon: selectedIcon,
            description: desc,
            config: config,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'converter.customPreset.saved'.tr(namedArgs: {'name': name}),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }

    nameCtrl.dispose();
    descCtrl.dispose();
  }
}

/// Curated icon palette for the custom preset save dialog. Names match the
/// switch in `_PresetCardState._getIcon` so the saved icon renders correctly.
const List<(String, IconData)> _customPresetIcons = [
  ('tune', Icons.tune_rounded),
  ('video_file', Icons.video_file_rounded),
  ('music_note', Icons.music_note_rounded),
  ('hd', Icons.hd_rounded),
  ('high_quality', Icons.high_quality_rounded),
  ('compress', Icons.compress_rounded),
  ('speed', Icons.speed_rounded),
  ('phone_iphone', Icons.phone_iphone_rounded),
  ('phone_android', Icons.phone_android_rounded),
  ('chat', Icons.chat_rounded),
];

/// Reusable dropdown field widget.
class _DropdownField<T> extends StatelessWidget {
  final String label;
  final String? tooltip;
  final T? value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;
  final bool enabled;

  const _DropdownField({
    required this.label,
    this.tooltip,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LabelWithHelp(label: label, tooltip: tooltip, enabled: enabled),
        const SizedBox(height: 4),
        SizedBox(
          height: 34,
          child: DropdownButtonFormField<T>(
            value: items.contains(value) ? value : null,
            isExpanded: true,
            isDense: true,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 0,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                  color: AppColors.border(context).withValues(alpha: 0.55),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                  color: AppColors.border(context).withValues(alpha: 0.55),
                ),
              ),
              filled: true,
              fillColor:
                  enabled
                      ? AppColors.surface1(context)
                      : AppColors.surface1(context).withValues(alpha: 0.55),
            ),
            style: tt.bodySmall?.copyWith(
              color:
                  enabled
                      ? cs.onSurface
                      : cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            items:
                items
                    .map(
                      (item) => DropdownMenuItem<T>(
                        value: item,
                        child: Text(
                          itemLabel(item),
                          style: tt.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
            onChanged: enabled ? onChanged : null,
          ),
        ),
      ],
    );
  }
}

/// Reusable slider field widget.
class _SliderField extends StatelessWidget {
  final String label;
  final String? tooltip;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final bool enabled;
  final ValueChanged<double> onChanged;

  const _SliderField({
    required this.label,
    this.tooltip,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: _LabelWithHelp(
                label: label,
                tooltip: tooltip,
                enabled: enabled,
              ),
            ),
            Text(
              valueLabel,
              style: tt.labelSmall?.copyWith(
                color:
                    enabled
                        ? cs.primary
                        : cs.onSurfaceVariant.withValues(alpha: 0.4),
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ],
        ),
        SizedBox(
          height: 24,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ),
      ],
    );
  }
}

/// Reusable toggle option widget.
class _ToggleOption extends StatelessWidget {
  final String label;
  final String? tooltip;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _ToggleOption({
    required this.label,
    this.tooltip,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final enabled = onChanged != null;

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: Checkbox(
            value: value,
            onChanged: enabled ? (v) => onChanged!(v ?? false) : null,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: tt.bodySmall?.copyWith(
            color:
                enabled
                    ? cs.onSurface
                    : cs.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
        if (tooltip != null) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: tooltip!,
            preferBelow: false,
            triggerMode: TooltipTriggerMode.tap,
            child: Icon(
              Icons.help_outline_rounded,
              size: 13,
              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ],
    );

    return InkWell(
      onTap: enabled ? () => onChanged!(!value) : null,
      borderRadius: BorderRadius.circular(6),
      child: row,
    );
  }
}

/// Compact label + optional inline help icon. Tapping the icon shows a tooltip.
class _LabelWithHelp extends StatelessWidget {
  final String label;
  final String? tooltip;
  final bool enabled;

  const _LabelWithHelp({
    required this.label,
    required this.tooltip,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color =
        enabled
            ? cs.onSurfaceVariant
            : cs.onSurfaceVariant.withValues(alpha: 0.4);

    final text = Text(
      label,
      style: tt.labelSmall?.copyWith(color: color, fontSize: 11),
    );

    if (tooltip == null) return text;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: text),
        const SizedBox(width: 4),
        Tooltip(
          message: tooltip!,
          preferBelow: false,
          triggerMode: TooltipTriggerMode.tap,
          waitDuration: const Duration(milliseconds: 250),
          showDuration: const Duration(seconds: 6),
          child: Icon(
            Icons.help_outline_rounded,
            size: 12,
            color: cs.onSurfaceVariant.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}
