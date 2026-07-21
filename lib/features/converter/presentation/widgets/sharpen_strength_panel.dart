import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Sharpen strength slider (0.5 to 2.0).
///
/// Maps to [ConversionConfig.sharpenStrength] used by FFmpegCommandBuilder
/// for unsharp mask filter intensity.
class SharpenStrengthPanel extends StatefulWidget {
  final double? initialStrength;
  final ValueChanged<double?> onStrengthChanged;

  const SharpenStrengthPanel({
    super.key,
    this.initialStrength,
    required this.onStrengthChanged,
  });

  @override
  State<SharpenStrengthPanel> createState() => _SharpenStrengthPanelState();
}

class _SharpenStrengthPanelState extends State<SharpenStrengthPanel> {
  late double _strength;

  @override
  void initState() {
    super.initState();
    _strength = widget.initialStrength ?? 1.0;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final strengthText = _strength.toStringAsFixed(1);
    final isStrong = _strength > 1.4;

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
          Row(
            children: [
              Text(
                'converter.enhance.sharpenStrength'.tr(),
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isStrong
                      ? Colors.orange.withValues(alpha: 0.15)
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  strengthText,
                  style: tt.labelSmall?.copyWith(
                    color: isStrong ? Colors.orange : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Text(
                'converter.enhance.sharpenSubtle'.tr(),
                style: tt.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                  fontSize: 10,
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: 28,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor:
                          isStrong ? Colors.orange : cs.primary,
                      thumbColor: isStrong ? Colors.orange : cs.primary,
                    ),
                    child: Slider(
                      value: _strength,
                      min: 0.5,
                      max: 2.0,
                      divisions: 30, // 0.05 steps
                      onChanged: (v) {
                        final rounded =
                            (v * 20).round() / 20; // round to 0.05
                        setState(() => _strength = rounded);
                        widget.onStrengthChanged(rounded);
                      },
                    ),
                  ),
                ),
              ),
              Text(
                'converter.enhance.sharpenAggressive'.tr(),
                style: tt.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                  fontSize: 10,
                ),
              ),
            ],
          ),

          // Quick presets
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _QuickButton(label: '0.5', onTap: () => _setStrength(0.5)),
              _QuickButton(label: '0.8', onTap: () => _setStrength(0.8)),
              _QuickButton(label: '1.0', onTap: () => _setStrength(1.0)),
              _QuickButton(label: '1.5', onTap: () => _setStrength(1.5)),
              _QuickButton(label: '2.0', onTap: () => _setStrength(2.0)),
            ],
          ),

          if (isStrong)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 14, color: Colors.orange),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'converter.enhance.sharpenWarning'.tr(),
                      style: tt.bodySmall?.copyWith(
                        color: Colors.orange,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _setStrength(double v) {
    setState(() => _strength = v);
    widget.onStrengthChanged(v);
  }
}

class _QuickButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
