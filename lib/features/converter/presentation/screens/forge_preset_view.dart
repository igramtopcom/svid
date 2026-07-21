import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../premium/presentation/providers/premium_providers.dart';
import '../../domain/entities/conversion_preset.dart';
import '../providers/converter_providers.dart';

/// Unified preset mosaic grid — shows ALL categories (format, device, social,
/// audio, advanced, enhance, edit, creative, tools, custom) in a single
/// filterable view. Replaces the old Convert/Enhance tab split.
class ForgePresetView extends ConsumerStatefulWidget {
  final void Function(ConversionPreset preset) onPresetSelected;

  const ForgePresetView({super.key, required this.onPresetSelected});

  @override
  ConsumerState<ForgePresetView> createState() => _ForgePresetViewState();
}

class _ForgePresetViewState extends ConsumerState<ForgePresetView> {
  PresetCategory _selectedCategory = PresetCategory.format;

  /// All categories in display order — Convert categories first, then
  /// Enhance/Edit/Creative/Tools, finally Custom.
  static const _allCategories = [
    PresetCategory.format,
    PresetCategory.device,
    PresetCategory.social,
    PresetCategory.audio,
    PresetCategory.advanced,
    PresetCategory.enhance,
    PresetCategory.edit,
    PresetCategory.creative,
    PresetCategory.tools,
  ];

  String _localizedCategoryLabel(PresetCategory cat) {
    switch (cat) {
      case PresetCategory.format:
        return 'converter.presetCategories.format'.tr();
      case PresetCategory.device:
        return 'converter.presetCategories.device'.tr();
      case PresetCategory.social:
        return 'converter.presetCategories.social'.tr();
      case PresetCategory.audio:
        return 'converter.presetCategories.audio'.tr();
      case PresetCategory.advanced:
        return 'converter.presetCategories.advanced'.tr();
      case PresetCategory.enhance:
        return 'converter.categories.enhance'.tr();
      case PresetCategory.edit:
        return 'converter.categories.edit'.tr();
      case PresetCategory.creative:
        return 'converter.categories.creative'.tr();
      case PresetCategory.tools:
        return 'converter.categories.tools'.tr();
      case PresetCategory.custom:
        return 'converter.presetCategories.custom'.tr();
    }
  }

  @override
  Widget build(BuildContext context) {
    final presetService = ref.watch(presetServiceProvider);
    final selectedPreset = ref.watch(selectedPresetProvider);
    final isPremium = ref.watch(isPremiumProvider);
    final customPresets = ref.watch(customPresetsProvider);

    // Add custom category if user has saved presets
    final categories = <PresetCategory>[
      ..._allCategories,
      if (customPresets.isNotEmpty) PresetCategory.custom,
    ];

    // Defensive fallback
    if (_selectedCategory == PresetCategory.custom && customPresets.isEmpty) {
      _selectedCategory = PresetCategory.format;
    }

    final presets =
        _selectedCategory == PresetCategory.custom
            ? customPresets
            : presetService.getByCategory(_selectedCategory);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section title
        Text(
          'converter.choosePreset'.tr(),
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),

        // Category tabs — terminal-menu style, horizontal scroll
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder:
                (_, __) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Center(
                    child: Container(
                      width: 1,
                      height: 10,
                      color: AppColors.border(context).withValues(alpha: 0.45),
                    ),
                  ),
                ),
            itemBuilder: (context, i) {
              final cat = categories[i];
              final isSelected = cat == _selectedCategory;
              return _CategoryTab(
                label: _localizedCategoryLabel(cat),
                isSelected: isSelected,
                onTap: () => setState(() => _selectedCategory = cat),
              );
            },
          ),
        ),
        const SizedBox(height: 12),

        // Responsive preset grid
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final cols = (width / 180.0).floor().clamp(2, 4);
            const spacing = 8.0;
            final cardWidth = (width - (spacing * (cols - 1))) / cols;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children:
                  presets.map((preset) {
                    final isSelected = selectedPreset?.id == preset.id;
                    final isLocked = preset.isPremium && !isPremium;
                    final isCustom = preset.category == PresetCategory.custom;
                    return SizedBox(
                      width: cardWidth,
                      child: _PresetCard(
                        preset: preset,
                        isSelected: isSelected,
                        isLocked: isLocked,
                        isCustom: isCustom,
                        onTap: () => widget.onPresetSelected(preset),
                        onDelete:
                            isCustom ? () => _confirmDelete(preset) : null,
                      ),
                    );
                  }).toList(),
            );
          },
        ),
      ],
    );
  }

  Future<void> _confirmDelete(ConversionPreset preset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('converter.customPreset.deleteTitle'.tr()),
          content: Text(
            'converter.customPreset.deleteConfirm'.tr(
              namedArgs: {'name': preset.name},
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('converter.customPreset.cancel'.tr()),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.errorRed),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('converter.customPreset.delete'.tr()),
            ),
          ],
        );
      },
    );
    if (!mounted) return;
    if (confirmed == true) {
      await ref.read(customPresetsProvider.notifier).remove(preset.id);
    }
  }
}

/// Compact category chip with a clear selected state.
class _CategoryTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? AppColors.accentHighlight.withValues(alpha: 0.10)
                  : AppColors.surface2(context),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color:
                isSelected
                    ? AppColors.accentHighlight.withValues(alpha: 0.45)
                    : AppColors.border(context).withValues(alpha: 0.50),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            letterSpacing: 0,
            color:
                isSelected
                    ? AppColors.accentHighlight
                    : cs.onSurfaceVariant.withValues(alpha: 0.85),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// Preset card — shows icon, name, description, tier badge, popular badge.
class _PresetCard extends StatefulWidget {
  final ConversionPreset preset;
  final bool isSelected;
  final bool isLocked;
  final bool isCustom;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _PresetCard({
    required this.preset,
    required this.isSelected,
    required this.isLocked,
    required this.onTap,
    this.isCustom = false,
    this.onDelete,
  });

  @override
  State<_PresetCard> createState() => _PresetCardState();
}

class _PresetCardState extends State<_PresetCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isSelected = widget.isSelected;
    final preset = widget.preset;

    final Color borderColor;
    final Color bgColor;
    if (isSelected) {
      borderColor = AppColors.accentHighlight;
      bgColor = AppColors.accentHighlight.withValues(alpha: 0.10);
    } else if (_hover) {
      borderColor = AppColors.accentHighlight.withValues(alpha: 0.4);
      bgColor = AppColors.surface3(context);
    } else {
      borderColor = AppColors.border(context).withValues(alpha: 0.50);
      bgColor = AppColors.surface2(context);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: borderColor, width: isSelected ? 1.4 : 1.0),
          boxShadow:
              isSelected
                  ? [
                    BoxShadow(
                      color: AppColors.accentHighlight.withValues(alpha: 0.40),
                      blurRadius: 15,
                      spreadRadius: -2,
                    ),
                  ]
                  : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Padding(
                  padding: const EdgeInsets.all(11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _getIcon(preset.icon),
                            size: 18,
                            color:
                                isSelected
                                    ? AppColors.accentHighlight
                                    : cs.onSurfaceVariant,
                          ),
                          if (preset.isPopular) ...[
                            const SizedBox(width: 6),
                            _PopularBadge(),
                          ],
                          const Spacer(),
                          _TierBadge(
                            isPremium: preset.isPremium,
                            isLocked: widget.isLocked,
                            isCustom: widget.isCustom,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        preset.name,
                        style: tt.bodySmall?.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                          letterSpacing: 0,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        preset.description,
                        style: tt.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.68),
                          fontSize: 11,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              // Selected checkmark badge
              if (isSelected && !widget.isCustom)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: AppColors.accentHighlight,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accentHighlight.withValues(
                            alpha: 0.5,
                          ),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              // Delete button for custom presets
              if (widget.isCustom && widget.onDelete != null && _hover)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Material(
                    color: Colors.transparent,
                    child: Tooltip(
                      message: 'converter.customPreset.delete'.tr(),
                      child: InkWell(
                        onTap: widget.onDelete,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: cs.surface.withValues(alpha: 0.85),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.errorRed.withValues(alpha: 0.6),
                              width: 0.8,
                            ),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 12,
                            color: AppColors.errorRed,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Combined icon map from both PresetSelector and EnhancementPanel.
  IconData _getIcon(String iconName) {
    const iconMap = <String, IconData>{
      // Format / Device / Social / Audio / Advanced
      'video_file': Icons.video_file_rounded,
      'music_note': Icons.music_note_rounded,
      'swap_horiz': Icons.swap_horiz_rounded,
      'compress': Icons.compress_rounded,
      'audiotrack': Icons.audiotrack_rounded,
      'phone_iphone': Icons.phone_iphone_rounded,
      'phone_android': Icons.phone_android_rounded,
      'chat': Icons.chat_rounded,
      'camera_alt': Icons.camera_alt_rounded,
      'play_circle': Icons.play_circle_rounded,
      'forum': Icons.forum_rounded,
      'gif': Icons.gif_rounded,
      'image': Icons.image_rounded,
      'high_quality': Icons.high_quality_rounded,
      'graphic_eq': Icons.graphic_eq_rounded,
      'hd': Icons.hd_rounded,
      'speed': Icons.speed_rounded,
      'equalizer': Icons.equalizer_rounded,
      'tune': Icons.tune_rounded,
      // Enhance / Edit / Creative / Tools
      'blur_off': Icons.blur_off_rounded,
      'stay_current_portrait': Icons.stay_current_portrait_rounded,
      'volume_off': Icons.volume_off_rounded,
      'rotate_right': Icons.rotate_right_rounded,
      'rotate_left': Icons.rotate_left_rounded,
      'screen_rotation': Icons.screen_rotation_rounded,
      'flip': Icons.flip_rounded,
      'merge_type': Icons.merge_type_rounded,
      'crop': Icons.crop_rounded,
      'gradient': Icons.gradient_rounded,
      'vignette': Icons.vignette_rounded,
      'grain': Icons.grain_rounded,
      'slow_motion_video': Icons.slow_motion_video_rounded,
      'fast_forward': Icons.fast_forward_rounded,
      'animation': Icons.animation_rounded,
      'wb_sunny': Icons.wb_sunny_rounded,
      'ac_unit': Icons.ac_unit_rounded,
      'filter_vintage': Icons.filter_vintage_rounded,
      'contrast': Icons.contrast_rounded,
      'hdr_off': Icons.hdr_off_rounded,
      'deblur': Icons.deblur_rounded,
      'brightness_auto': Icons.brightness_auto_rounded,
      'nightlight': Icons.nightlight_rounded,
      'volume_up': Icons.volume_up_rounded,
      'volume_down': Icons.volume_down_rounded,
      'speaker': Icons.speaker_rounded,
      'record_voice_over': Icons.record_voice_over_rounded,
      'movie': Icons.movie_rounded,
      'podcasts': Icons.podcasts_rounded,
      'surround_sound': Icons.surround_sound_rounded,
      'fit_screen': Icons.fit_screen_rounded,
      'replay': Icons.replay_rounded,
      'invert_colors': Icons.invert_colors_rounded,
      'loop': Icons.loop_rounded,
      'photo_camera': Icons.photo_camera_rounded,
      'subtitles': Icons.subtitles_rounded,
      'content_cut': Icons.content_cut_rounded,
      'branding_watermark': Icons.branding_watermark_rounded,
    };
    return iconMap[iconName] ?? Icons.settings_rounded;
  }
}

/// Tiny "POPULAR" star+text pill.
class _PopularBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.warningAmber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: AppColors.warningAmber.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 9, color: AppColors.warningAmber),
          const SizedBox(width: 2),
          Text(
            'converter.tier.popular'.tr(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
              color: AppColors.warningAmber,
              height: 1.1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// FREE / PRO / LOCKED / CUSTOM text badge.
class _TierBadge extends StatelessWidget {
  final bool isPremium;
  final bool isLocked;
  final bool isCustom;

  const _TierBadge({
    required this.isPremium,
    required this.isLocked,
    this.isCustom = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final String label;
    final IconData? leadingIcon;

    if (isCustom) {
      bg = AppColors.accentHighlight.withValues(alpha: 0.12);
      fg = AppColors.accentHighlight;
      label = 'converter.tier.custom'.tr();
      leadingIcon = Icons.bookmark_rounded;
    } else if (isLocked) {
      bg = AppColors.warningAmber.withValues(alpha: 0.15);
      fg = AppColors.warningAmber;
      label = 'converter.tier.locked'.tr();
      leadingIcon = Icons.lock_rounded;
    } else if (isPremium) {
      bg = AppColors.accentHighlight.withValues(alpha: 0.15);
      fg = AppColors.accentHighlight;
      label = 'converter.tier.pro'.tr();
      leadingIcon = null;
    } else {
      bg = AppColors.successGreen.withValues(alpha: 0.12);
      fg = AppColors.successGreen;
      label = 'converter.tier.free'.tr();
      leadingIcon = null;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: fg.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leadingIcon != null) ...[
            Icon(leadingIcon, size: 10, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
              color: fg,
              height: 1.1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
