import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../premium/presentation/providers/premium_providers.dart';
import '../../domain/entities/conversion_preset.dart';
import '../providers/converter_providers.dart';

/// Minimum card width target — used to compute responsive grid column count.
const double _presetCardMinWidth = 180.0;

/// Grid of conversion presets organized by category tabs.
///
/// Displays preset cards with icons, names, and premium badges.
/// Selecting a preset updates the conversion config accordingly.
/// Only shows format/device/social/audio/advanced categories
/// (enhance/edit/creative are in EnhancementPanel).
class PresetSelector extends ConsumerStatefulWidget {
  final void Function(ConversionPreset preset) onPresetSelected;

  const PresetSelector({super.key, required this.onPresetSelected});

  @override
  ConsumerState<PresetSelector> createState() => _PresetSelectorState();
}

class _PresetSelectorState extends ConsumerState<PresetSelector> {
  PresetCategory _selectedCategory = PresetCategory.format;

  /// Built-in conversion categories (enhance/edit/creative live in EnhancementPanel).
  static const _builtInCategories = [
    PresetCategory.format,
    PresetCategory.device,
    PresetCategory.social,
    PresetCategory.audio,
    PresetCategory.advanced,
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
      case PresetCategory.custom:
        return 'converter.presetCategories.custom'.tr();
      // Other categories are not surfaced in this widget but still need a label
      // for safety if somebody routes them here later.
      case PresetCategory.enhance:
      case PresetCategory.edit:
      case PresetCategory.creative:
      case PresetCategory.tools:
        return cat.displayName;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final presetService = ref.watch(presetServiceProvider);
    final selectedPreset = ref.watch(selectedPresetProvider);
    final isPremium = ref.watch(isPremiumProvider);
    final customPresets = ref.watch(customPresetsProvider);

    // Custom tab only appears once the user has actually saved a preset, so
    // first-time users aren't confused by an empty section.
    final categories = <PresetCategory>[
      ..._builtInCategories,
      if (customPresets.isNotEmpty) PresetCategory.custom,
    ];

    // Defensive: if the active tab is "custom" but the user just deleted the
    // last one, fall back to Format so the grid isn't empty.
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
        // Text-only category tabs — Nocturne "terminal menu" style
        SizedBox(
          height: 28,
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
                      color: cs.outlineVariant.withValues(alpha: 0.35),
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

        // Responsive preset grid — 2-4 columns based on width
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final cols = (width / _presetCardMinWidth).floor().clamp(2, 4);
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

/// Text-only terminal-style category tab — underline + color shift on selection.
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
      borderRadius: BorderRadius.circular(2),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                letterSpacing: 1.2,
                color:
                    isSelected
                        ? AppColors.accentHighlight
                        : cs.onSurfaceVariant.withValues(alpha: 0.75),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Container(
              height: 2,
              width: isSelected ? 24 : 0,
              decoration: BoxDecoration(
                color: AppColors.accentHighlight,
                borderRadius: BorderRadius.circular(1),
                boxShadow:
                    isSelected
                        ? [
                          BoxShadow(
                            color: AppColors.accentHighlight.withValues(
                              alpha: 0.6,
                            ),
                            blurRadius: 4,
                          ),
                        ]
                        : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
      borderColor = AppColors.accentHighlight.withValues(alpha: 0.5);
      bgColor = cs.surfaceContainerHighest.withValues(alpha: 0.65);
    } else {
      borderColor = cs.outlineVariant.withValues(alpha: 0.35);
      bgColor = cs.surfaceContainerHighest.withValues(alpha: 0.45);
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
                      color: AppColors.accentHighlight.withValues(alpha: 0.22),
                      blurRadius: 10,
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
                            const _PopularBadge(),
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
                          color: isSelected ? cs.onSurface : cs.onSurface,
                          letterSpacing: 0.1,
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
              // Hover-revealed delete X for custom presets only.
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

  IconData _getIcon(String iconName) {
    switch (iconName) {
      case 'video_file':
        return Icons.video_file_rounded;
      case 'music_note':
        return Icons.music_note_rounded;
      case 'swap_horiz':
        return Icons.swap_horiz_rounded;
      case 'compress':
        return Icons.compress_rounded;
      case 'audiotrack':
        return Icons.audiotrack_rounded;
      case 'phone_iphone':
        return Icons.phone_iphone_rounded;
      case 'phone_android':
        return Icons.phone_android_rounded;
      case 'chat':
        return Icons.chat_rounded;
      case 'camera_alt':
        return Icons.camera_alt_rounded;
      case 'play_circle':
        return Icons.play_circle_rounded;
      case 'forum':
        return Icons.forum_rounded;
      case 'gif':
        return Icons.gif_rounded;
      case 'image':
        return Icons.image_rounded;
      case 'high_quality':
        return Icons.high_quality_rounded;
      case 'graphic_eq':
        return Icons.graphic_eq_rounded;
      case 'hd':
        return Icons.hd_rounded;
      case 'speed':
        return Icons.speed_rounded;
      case 'equalizer':
        return Icons.equalizer_rounded;
      case 'tune':
        return Icons.tune_rounded;
      default:
        return Icons.settings_rounded;
    }
  }
}

/// Tiny "POPULAR" star+text pill marking curated recommended presets so first-
/// time users have an obvious starting point without paging through 70 cards.
class _PopularBadge extends StatelessWidget {
  const _PopularBadge();

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
              letterSpacing: 0.6,
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

/// FREE / PRO / LOCKED / CUSTOM text badge — angular 2px corners, tabular figures.
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
              letterSpacing: 0.8,
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
