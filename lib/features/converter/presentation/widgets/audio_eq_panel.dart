import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Audio EQ preset selector.
///
/// Shows 5 named EQ profiles: Bass Boost, Treble Boost, Voice Enhance,
/// Cinema, Podcast. Maps to [ConversionConfig.audioEqPreset].
class AudioEqPanel extends StatefulWidget {
  final String? initialPreset;
  final ValueChanged<String?> onPresetChanged;

  const AudioEqPanel({
    super.key,
    this.initialPreset,
    required this.onPresetChanged,
  });

  @override
  State<AudioEqPanel> createState() => _AudioEqPanelState();
}

class _AudioEqPanelState extends State<AudioEqPanel> {
  late String _selected;

  static const _presets = [
    _EqPresetInfo(
      id: 'bass_boost',
      icon: Icons.speaker_rounded,
      labelKey: 'converter.enhance.eqBassBoost',
      descKey: 'converter.enhance.eqBassBoostDesc',
    ),
    _EqPresetInfo(
      id: 'treble_boost',
      icon: Icons.graphic_eq_rounded,
      labelKey: 'converter.enhance.eqTrebleBoost',
      descKey: 'converter.enhance.eqTrebleBoostDesc',
    ),
    _EqPresetInfo(
      id: 'voice_enhance',
      icon: Icons.record_voice_over_rounded,
      labelKey: 'converter.enhance.eqVoiceEnhance',
      descKey: 'converter.enhance.eqVoiceEnhanceDesc',
    ),
    _EqPresetInfo(
      id: 'cinema',
      icon: Icons.movie_rounded,
      labelKey: 'converter.enhance.eqCinema',
      descKey: 'converter.enhance.eqCinemaDesc',
    ),
    _EqPresetInfo(
      id: 'podcast',
      icon: Icons.podcasts_rounded,
      labelKey: 'converter.enhance.eqPodcast',
      descKey: 'converter.enhance.eqPodcastDesc',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _selected = widget.initialPreset ?? 'bass_boost';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'converter.enhance.audioEq'.tr(),
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),

          // EQ preset cards
          ...(_presets.map((preset) {
            final isSelected = preset.id == _selected;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: isSelected
                    ? cs.primary.withValues(alpha: 0.12)
                    : cs.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(4),
                child: InkWell(
                  onTap: () {
                    setState(() => _selected = preset.id);
                    widget.onPresetChanged(preset.id);
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSelected
                            ? cs.primary
                            : cs.outlineVariant.withValues(alpha: 0.15),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          preset.icon,
                          size: 20,
                          color:
                              isSelected ? cs.primary : cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                preset.labelKey.tr(),
                                style: tt.labelMedium?.copyWith(
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? cs.primary
                                      : cs.onSurface,
                                ),
                              ),
                              Text(
                                preset.descKey.tr(),
                                style: tt.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant
                                      .withValues(alpha: 0.7),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: cs.primary,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          })),
        ],
      ),
    );
  }
}

class _EqPresetInfo {
  final String id;
  final IconData icon;
  final String labelKey;
  final String descKey;

  const _EqPresetInfo({
    required this.id,
    required this.icon,
    required this.labelKey,
    required this.descKey,
  });
}
