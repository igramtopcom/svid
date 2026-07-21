import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Denoise strength selector — light / medium / strong.
///
/// Maps to [ConversionConfig.denoiseStrength] values used by FFmpegCommandBuilder
/// to set hqdn3d filter intensity.
class DenoiseStrengthPanel extends StatefulWidget {
  final String? initialStrength;
  final ValueChanged<String?> onStrengthChanged;

  const DenoiseStrengthPanel({
    super.key,
    this.initialStrength,
    required this.onStrengthChanged,
  });

  @override
  State<DenoiseStrengthPanel> createState() => _DenoiseStrengthPanelState();
}

class _DenoiseStrengthPanelState extends State<DenoiseStrengthPanel> {
  late String _strength;

  static const _options = ['light', 'medium', 'strong'];

  @override
  void initState() {
    super.initState();
    _strength = widget.initialStrength ?? 'medium';
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
            'converter.enhance.denoiseStrength'.tr(),
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),

          // Segmented selector
          Row(
            children: _options.map((opt) {
              final isSelected = opt == _strength;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: opt != _options.last ? 6 : 0,
                  ),
                  child: Material(
                    color: isSelected
                        ? cs.primary.withValues(alpha: 0.15)
                        : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                    child: InkWell(
                      onTap: () {
                        setState(() => _strength = opt);
                        widget.onStrengthChanged(opt);
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
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
                          children: [
                            Icon(
                              _iconForStrength(opt),
                              size: 20,
                              color: isSelected
                                  ? cs.primary
                                  : cs.onSurfaceVariant,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _labelForStrength(opt),
                              style: tt.labelSmall?.copyWith(
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? cs.primary
                                    : cs.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 8),
          Text(
            _descForStrength(_strength),
            style: tt.bodySmall?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForStrength(String s) {
    switch (s) {
      case 'light':
        return Icons.blur_on_rounded;
      case 'medium':
        return Icons.blur_circular_rounded;
      case 'strong':
        return Icons.blur_off_rounded;
      default:
        return Icons.blur_circular_rounded;
    }
  }

  String _labelForStrength(String s) {
    switch (s) {
      case 'light':
        return 'converter.enhance.denoiseLight'.tr();
      case 'medium':
        return 'converter.enhance.denoiseMedium'.tr();
      case 'strong':
        return 'converter.enhance.denoiseStrong'.tr();
      default:
        return s;
    }
  }

  String _descForStrength(String s) {
    switch (s) {
      case 'light':
        return 'converter.enhance.denoiseLightDesc'.tr();
      case 'medium':
        return 'converter.enhance.denoiseMediumDesc'.tr();
      case 'strong':
        return 'converter.enhance.denoiseStrongDesc'.tr();
      default:
        return '';
    }
  }
}
