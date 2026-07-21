import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Speed multiplier slider with quick presets.
///
/// Range: 0.25x to 4.0x. Shows slow-motion vs fast-forward indicator.
class SpeedControlPanel extends StatefulWidget {
  final double? initialSpeed;
  final ValueChanged<double?> onSpeedChanged;

  const SpeedControlPanel({
    super.key,
    this.initialSpeed,
    required this.onSpeedChanged,
  });

  @override
  State<SpeedControlPanel> createState() => _SpeedControlPanelState();
}

class _SpeedControlPanelState extends State<SpeedControlPanel> {
  late double _speed;

  @override
  void initState() {
    super.initState();
    _speed = widget.initialSpeed ?? 1.0;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final isSlow = _speed < 1.0;
    final isFast = _speed > 1.0;
    final speedText = '${_speed.toStringAsFixed(2)}x';

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
                'converter.enhance.speedControl'.tr(),
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isSlow
                      ? Colors.blue.withValues(alpha: 0.15)
                      : isFast
                          ? Colors.orange.withValues(alpha: 0.15)
                          : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  speedText,
                  style: tt.labelSmall?.copyWith(
                    color: isSlow
                        ? Colors.blue
                        : isFast
                            ? Colors.orange
                            : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Speed slider
          Row(
            children: [
              Icon(
                Icons.slow_motion_video_rounded,
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
                      activeTrackColor: isSlow
                          ? Colors.blue
                          : isFast
                              ? Colors.orange
                              : cs.primary,
                      thumbColor: isSlow
                          ? Colors.blue
                          : isFast
                              ? Colors.orange
                              : cs.primary,
                    ),
                    child: Slider(
                      value: _speed,
                      min: 0.25,
                      max: 4.0,
                      divisions: 75, // 0.05 steps
                      onChanged: (v) {
                        // Snap to 1.0 when close
                        final snapped =
                            (v - 1.0).abs() < 0.06 ? 1.0 : _roundTo(v, 0.05);
                        setState(() => _speed = snapped);
                        widget.onSpeedChanged(snapped == 1.0 ? null : snapped);
                      },
                    ),
                  ),
                ),
              ),
              Icon(
                Icons.fast_forward_rounded,
                size: 18,
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
              _QuickButton(label: '0.25x', onTap: () => _setSpeed(0.25)),
              _QuickButton(label: '0.5x', onTap: () => _setSpeed(0.5)),
              _QuickButton(label: '0.75x', onTap: () => _setSpeed(0.75)),
              _QuickButton(label: '1.0x', onTap: () => _setSpeed(1.0)),
              _QuickButton(label: '1.5x', onTap: () => _setSpeed(1.5)),
              _QuickButton(label: '2.0x', onTap: () => _setSpeed(2.0)),
              _QuickButton(label: '3.0x', onTap: () => _setSpeed(3.0)),
              _QuickButton(label: '4.0x', onTap: () => _setSpeed(4.0)),
            ],
          ),

          if (_speed < 0.5)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 14, color: Colors.blue),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'converter.enhance.speedSlowWarning'.tr(),
                      style: tt.bodySmall?.copyWith(
                        color: Colors.blue,
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

  void _setSpeed(double speed) {
    setState(() => _speed = speed);
    widget.onSpeedChanged(speed == 1.0 ? null : speed);
  }

  double _roundTo(double value, double step) {
    return (value / step).round() * step;
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
