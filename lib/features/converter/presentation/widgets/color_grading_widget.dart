import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// A color grading preset with an ffmpeg filter chain.
class ColorGradingPreset {
  final String id;
  final String name;
  final String filterChain;
  final List<Color> gradientColors;

  const ColorGradingPreset({
    required this.id,
    required this.name,
    required this.filterChain,
    required this.gradientColors,
  });
}

/// Color grading / LUT selector.
///
/// Grid of color presets with preview swatches showing the color cast.
/// Each preset maps to an ffmpeg filter chain (no .cube file needed).
class ColorGradingWidget extends StatelessWidget {
  final String? selectedEffectId;
  final ValueChanged<ColorGradingPreset?> onPresetSelected;

  const ColorGradingWidget({
    super.key,
    this.selectedEffectId,
    required this.onPresetSelected,
  });

  static const _presets = [
    ColorGradingPreset(
      id: 'warm_sunset',
      name: 'Warm Sunset',
      filterChain: 'colorbalance=rs=.1:gs=-.05:bs=-.1:rh=.1:gh=.05:bh=-.05',
      gradientColors: [Color(0xFFFF8C00), Color(0xFFFFD700)],
    ),
    ColorGradingPreset(
      id: 'cool_blue',
      name: 'Cool Blue',
      filterChain: 'colorbalance=rs=-.1:gs=0:bs=.15:rh=-.05:gh=.05:bh=.1',
      gradientColors: [Color(0xFF1E90FF), Color(0xFF00CED1)],
    ),
    ColorGradingPreset(
      id: 'vintage_film',
      name: 'Vintage Film',
      filterChain: 'curves=vintage',
      gradientColors: [Color(0xFF8B7765), Color(0xFFD2B48C)],
    ),
    ColorGradingPreset(
      id: 'high_contrast',
      name: 'High Contrast',
      filterChain: 'eq=contrast=1.3:brightness=0.05:saturation=1.2',
      gradientColors: [Color(0xFF2C2C2C), Color(0xFFFFFFFF)],
    ),
    ColorGradingPreset(
      id: 'noir',
      name: 'Noir',
      filterChain: 'eq=saturation=0:contrast=1.2:brightness=-0.05',
      gradientColors: [Color(0xFF1A1A1A), Color(0xFF808080)],
    ),
    ColorGradingPreset(
      id: 'sepia',
      name: 'Sepia',
      filterChain: 'colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131',
      gradientColors: [Color(0xFF704214), Color(0xFFC4A882)],
    ),
    ColorGradingPreset(
      id: 'teal_orange',
      name: 'Teal & Orange',
      filterChain: 'colorbalance=rs=.08:gs=-.06:bs=-.08:rm=.05:gm=-.02:bm=-.04:rh=-.03:gh=.04:bh=.08',
      gradientColors: [Color(0xFF008080), Color(0xFFFF8C00)],
    ),
    ColorGradingPreset(
      id: 'cyberpunk',
      name: 'Cyberpunk',
      filterChain: 'colorbalance=rs=.1:gs=-.05:bs=.15:rh=.15:gh=-.05:bh=.1,eq=saturation=1.4:contrast=1.1',
      gradientColors: [Color(0xFFFF00FF), Color(0xFF00FFFF)],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha:0.3),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'converter.enhance.colorGrading'.tr(),
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (selectedEffectId != null)
                TextButton(
                  onPressed: () => onPresetSelected(null),
                  style: TextButton.styleFrom(
                    foregroundColor: cs.onSurfaceVariant,
                    textStyle: tt.bodySmall,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 28),
                  ),
                  child: Text('converter.enhance.clearEffect'.tr()),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Preset grid
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presets.map((preset) {
              final isSelected = selectedEffectId == preset.id;
              return _ColorPresetCard(
                preset: preset,
                isSelected: isSelected,
                onTap: () => onPresetSelected(preset),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ColorPresetCard extends StatelessWidget {
  final ColorGradingPreset preset;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColorPresetCard({
    required this.preset,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 90,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.15),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Color swatch
            Container(
              height: 40,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: preset.gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              preset.name,
              style: tt.labelSmall?.copyWith(
                color: isSelected ? cs.primary : cs.onSurface,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
