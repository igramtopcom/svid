import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../premium/presentation/providers/premium_providers.dart';
import '../../domain/entities/conversion_preset.dart';
import '../providers/converter_providers.dart';

/// Grid of enhancement/edit/creative presets organized by sub-category tabs.
///
/// Similar to PresetSelector but focused on the enhance, edit, and creative
/// categories. Selecting a preset updates the conversion config.
class EnhancementPanel extends ConsumerStatefulWidget {
  final void Function(ConversionPreset preset) onPresetSelected;

  const EnhancementPanel({
    super.key,
    required this.onPresetSelected,
  });

  @override
  ConsumerState<EnhancementPanel> createState() => _EnhancementPanelState();
}

class _EnhancementPanelState extends ConsumerState<EnhancementPanel> {
  PresetCategory _selectedCategory = PresetCategory.enhance;

  static const _enhancementCategories = [
    PresetCategory.enhance,
    PresetCategory.edit,
    PresetCategory.creative,
    PresetCategory.tools,
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final presetService = ref.watch(presetServiceProvider);
    final selectedPreset = ref.watch(selectedPresetProvider);
    final isPremium = ref.watch(isPremiumProvider);

    final presets = presetService.getByCategory(_selectedCategory);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category tabs
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: _enhancementCategories.map((cat) {
              final isSelected = cat == _selectedCategory;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(
                    _categoryLabel(cat),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: cs.primary,
                  backgroundColor: cs.surfaceContainerHighest,
                  side: BorderSide.none,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) {
                    setState(() => _selectedCategory = cat);
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 10),

        // Warning for slow presets
        if (_selectedCategory == PresetCategory.creative &&
            selectedPreset?.id == 'smooth_60fps')
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.warningAmber.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: AppColors.warningAmber.withValues(alpha:0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 16, color: AppColors.warningAmber),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'converter.enhance.interpolateWarning'.tr(),
                    style: tt.bodySmall?.copyWith(
                      color: AppColors.warningAmber,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Preset grid
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: presets.map((preset) {
            final isSelected = selectedPreset?.id == preset.id;
            final isLocked = preset.isPremium && !isPremium;

            return _EnhancementCard(
              preset: preset,
              isSelected: isSelected,
              isLocked: isLocked,
              onTap: () => widget.onPresetSelected(preset),
            );
          }).toList(),
        ),
      ],
    );
  }

  String _categoryLabel(PresetCategory cat) {
    switch (cat) {
      case PresetCategory.enhance:
        return 'converter.categories.enhance'.tr();
      case PresetCategory.edit:
        return 'converter.categories.edit'.tr();
      case PresetCategory.creative:
        return 'converter.categories.creative'.tr();
      case PresetCategory.tools:
        return 'converter.categories.tools'.tr();
      default:
        return cat.displayName;
    }
  }
}

class _EnhancementCard extends StatelessWidget {
  final ConversionPreset preset;
  final bool isSelected;
  final bool isLocked;
  final VoidCallback onTap;

  const _EnhancementCard({
    required this.preset,
    required this.isSelected,
    required this.isLocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      color: isSelected
          ? cs.primary.withValues(alpha:0.15)
          : cs.surfaceContainerHighest.withValues(alpha:0.5),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 140,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected
                  ? cs.primary
                  : cs.outlineVariant.withValues(alpha: 0.15),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    _getIcon(preset.icon),
                    size: 18,
                    color: isSelected ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const Spacer(),
                  if (isLocked)
                    Icon(
                      Icons.lock_rounded,
                      size: 14,
                      color: AppColors.warningAmber,
                    )
                  else if (preset.isPremium)
                    Icon(
                      Icons.star_rounded,
                      size: 14,
                      color: AppColors.warningAmber,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                preset.name,
                style: tt.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isSelected ? cs.primary : cs.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                preset.description,
                style: tt.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha:0.7),
                  fontSize: 10,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIcon(String iconName) {
    switch (iconName) {
      case 'blur_off':
        return Icons.blur_off_rounded;
      case 'stay_current_portrait':
        return Icons.stay_current_portrait_rounded;
      case 'equalizer':
        return Icons.equalizer_rounded;
      case 'volume_off':
        return Icons.volume_off_rounded;
      case 'rotate_right':
        return Icons.rotate_right_rounded;
      case 'rotate_left':
        return Icons.rotate_left_rounded;
      case 'screen_rotation':
        return Icons.screen_rotation_rounded;
      case 'flip':
        return Icons.flip_rounded;
      case 'merge_type':
        return Icons.merge_type_rounded;
      case 'crop':
        return Icons.crop_rounded;
      case 'gradient':
        return Icons.gradient_rounded;
      case 'vignette':
        return Icons.vignette_rounded;
      case 'grain':
        return Icons.grain_rounded;
      case 'slow_motion_video':
        return Icons.slow_motion_video_rounded;
      case 'fast_forward':
        return Icons.fast_forward_rounded;
      case 'animation':
        return Icons.animation_rounded;
      case 'wb_sunny':
        return Icons.wb_sunny_rounded;
      case 'ac_unit':
        return Icons.ac_unit_rounded;
      case 'filter_vintage':
        return Icons.filter_vintage_rounded;
      case 'contrast':
        return Icons.contrast_rounded;
      case 'hdr_off':
        return Icons.hdr_off_rounded;
      case 'deblur':
        return Icons.deblur_rounded;
      case 'brightness_auto':
        return Icons.brightness_auto_rounded;
      case 'nightlight':
        return Icons.nightlight_rounded;
      case 'volume_up':
        return Icons.volume_up_rounded;
      case 'volume_down':
        return Icons.volume_down_rounded;
      case 'speaker':
        return Icons.speaker_rounded;
      case 'record_voice_over':
        return Icons.record_voice_over_rounded;
      case 'movie':
        return Icons.movie_rounded;
      case 'podcasts':
        return Icons.podcasts_rounded;
      case 'surround_sound':
        return Icons.surround_sound_rounded;
      case 'fit_screen':
        return Icons.fit_screen_rounded;
      case 'replay':
        return Icons.replay_rounded;
      case 'invert_colors':
        return Icons.invert_colors_rounded;
      case 'loop':
        return Icons.loop_rounded;
      case 'photo_camera':
        return Icons.photo_camera_rounded;
      case 'subtitles':
        return Icons.subtitles_rounded;
      case 'content_cut':
        return Icons.content_cut_rounded;
      case 'compress':
        return Icons.compress_rounded;
      case 'branding_watermark':
        return Icons.branding_watermark_rounded;
      default:
        return Icons.auto_fix_high_rounded;
    }
  }
}
