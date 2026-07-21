import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Film grain intensity slider (0 to 100).
///
/// Maps to [ConversionConfig.grainIntensity] used by FFmpegCommandBuilder
/// for the noise filter.
class GrainIntensityPanel extends StatefulWidget {
  final double? initialIntensity;
  final ValueChanged<double?> onIntensityChanged;

  const GrainIntensityPanel({
    super.key,
    this.initialIntensity,
    required this.onIntensityChanged,
  });

  @override
  State<GrainIntensityPanel> createState() => _GrainIntensityPanelState();
}

class _GrainIntensityPanelState extends State<GrainIntensityPanel> {
  late double _intensity;

  @override
  void initState() {
    super.initState();
    _intensity = widget.initialIntensity ?? 30.0;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final isHigh = _intensity > 60;

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
                'converter.enhance.grainIntensity'.tr(),
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isHigh
                      ? Colors.orange.withValues(alpha: 0.15)
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_intensity.round()}%',
                  style: tt.labelSmall?.copyWith(
                    color: isHigh ? Colors.orange : cs.onSurfaceVariant,
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
              Icon(
                Icons.grain_rounded,
                size: 18,
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
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
                          isHigh ? Colors.orange : cs.primary,
                      thumbColor: isHigh ? Colors.orange : cs.primary,
                    ),
                    child: Slider(
                      value: _intensity,
                      min: 5,
                      max: 100,
                      divisions: 19, // 5-unit steps
                      onChanged: (v) {
                        final rounded = (v / 5).round() * 5.0;
                        setState(() => _intensity = rounded);
                        widget.onIntensityChanged(rounded);
                      },
                    ),
                  ),
                ),
              ),
              Icon(
                Icons.grain_rounded,
                size: 24,
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),

          // Quick presets
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _QuickButton(label: '10%', onTap: () => _setIntensity(10)),
              _QuickButton(label: '20%', onTap: () => _setIntensity(20)),
              _QuickButton(label: '30%', onTap: () => _setIntensity(30)),
              _QuickButton(label: '50%', onTap: () => _setIntensity(50)),
              _QuickButton(label: '75%', onTap: () => _setIntensity(75)),
              _QuickButton(label: '100%', onTap: () => _setIntensity(100)),
            ],
          ),

          if (isHigh)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 14, color: Colors.orange),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'converter.enhance.grainHighWarning'.tr(),
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

  void _setIntensity(double v) {
    setState(() => _intensity = v);
    widget.onIntensityChanged(v);
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
