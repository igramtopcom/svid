import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Panel with sliders for brightness, contrast, saturation, and gamma.
///
/// Used when an adjustment preset is selected (Auto Brightness, Night Mode)
/// or when the user wants manual control.
class BrightnessContrastPanel extends StatefulWidget {
  final double? initialBrightness;
  final double? initialContrast;
  final double? initialSaturation;
  final double? initialGamma;
  final void Function({
    double? brightness,
    double? contrast,
    double? saturation,
    double? gamma,
  }) onChanged;

  const BrightnessContrastPanel({
    super.key,
    this.initialBrightness,
    this.initialContrast,
    this.initialSaturation,
    this.initialGamma,
    required this.onChanged,
  });

  @override
  State<BrightnessContrastPanel> createState() =>
      _BrightnessContrastPanelState();
}

class _BrightnessContrastPanelState extends State<BrightnessContrastPanel> {
  late double _brightness;
  late double _contrast;
  late double _saturation;
  late double _gamma;

  @override
  void initState() {
    super.initState();
    _brightness = widget.initialBrightness ?? 0.0;
    _contrast = widget.initialContrast ?? 1.0;
    _saturation = widget.initialSaturation ?? 1.0;
    _gamma = widget.initialGamma ?? 1.0;
  }

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
                'converter.enhance.adjustments'.tr(),
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              TextButton(
                onPressed: _reset,
                style: TextButton.styleFrom(
                  foregroundColor: cs.onSurfaceVariant,
                  textStyle: tt.bodySmall,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 28),
                ),
                child: Text('converter.enhance.reset'.tr()),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Brightness: -1.0 to 1.0
          _SliderRow(
            label: 'converter.enhance.brightness'.tr(),
            value: _brightness,
            min: -1.0,
            max: 1.0,
            displayValue: _brightness.toStringAsFixed(2),
            onChanged: (v) {
              setState(() => _brightness = v);
              _emit();
            },
          ),
          const SizedBox(height: 6),

          // Contrast: 0.0 to 3.0
          _SliderRow(
            label: 'converter.enhance.contrast'.tr(),
            value: _contrast,
            min: 0.0,
            max: 3.0,
            displayValue: _contrast.toStringAsFixed(2),
            onChanged: (v) {
              setState(() => _contrast = v);
              _emit();
            },
          ),
          const SizedBox(height: 6),

          // Saturation: 0.0 to 3.0
          _SliderRow(
            label: 'converter.enhance.saturation'.tr(),
            value: _saturation,
            min: 0.0,
            max: 3.0,
            displayValue: _saturation.toStringAsFixed(2),
            onChanged: (v) {
              setState(() => _saturation = v);
              _emit();
            },
          ),
          const SizedBox(height: 6),

          // Gamma: 0.1 to 10.0
          _SliderRow(
            label: 'converter.enhance.gamma'.tr(),
            value: _gamma,
            min: 0.1,
            max: 5.0,
            displayValue: _gamma.toStringAsFixed(2),
            onChanged: (v) {
              setState(() => _gamma = v);
              _emit();
            },
          ),
        ],
      ),
    );
  }

  void _emit() {
    widget.onChanged(
      brightness: _brightness != 0.0 ? _brightness : null,
      contrast: _contrast != 1.0 ? _contrast : null,
      saturation: _saturation != 1.0 ? _saturation : null,
      gamma: _gamma != 1.0 ? _gamma : null,
    );
  }

  void _reset() {
    setState(() {
      _brightness = 0.0;
      _contrast = 1.0;
      _saturation = 1.0;
      _gamma = 1.0;
    });
    widget.onChanged(
      brightness: null,
      contrast: null,
      saturation: null,
      gamma: null,
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String displayValue;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.displayValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 24,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            displayValue,
            textAlign: TextAlign.right,
            style: tt.labelSmall?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}
