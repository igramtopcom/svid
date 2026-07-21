import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Volume adjustment slider with dB readout.
///
/// Range: -20 dB to +20 dB. Shows visual indicator of boost/reduction.
class VolumePanel extends StatefulWidget {
  final double? initialVolumeDb;
  final ValueChanged<double?> onVolumeChanged;

  const VolumePanel({
    super.key,
    this.initialVolumeDb,
    required this.onVolumeChanged,
  });

  @override
  State<VolumePanel> createState() => _VolumePanelState();
}

class _VolumePanelState extends State<VolumePanel> {
  late double _volumeDb;

  @override
  void initState() {
    super.initState();
    _volumeDb = widget.initialVolumeDb ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final isBoost = _volumeDb > 0;
    final isReduce = _volumeDb < 0;
    final dbText = _volumeDb == 0
        ? '0 dB'
        : '${_volumeDb > 0 ? '+' : ''}${_volumeDb.toStringAsFixed(1)} dB';

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
                'converter.enhance.volumeAdjust'.tr(),
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isBoost
                      ? Colors.green.withValues(alpha:0.15)
                      : isReduce
                          ? Colors.orange.withValues(alpha:0.15)
                          : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  dbText,
                  style: tt.labelSmall?.copyWith(
                    color: isBoost
                        ? Colors.green
                        : isReduce
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

          // dB Slider
          Row(
            children: [
              Icon(
                Icons.volume_down_rounded,
                size: 18,
                color: cs.onSurfaceVariant.withValues(alpha:0.5),
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
                          isBoost ? Colors.green : cs.primary,
                      thumbColor:
                          isBoost ? Colors.green : cs.primary,
                    ),
                    child: Slider(
                      value: _volumeDb,
                      min: -20.0,
                      max: 20.0,
                      divisions: 80, // 0.5 dB steps
                      onChanged: (v) {
                        // Snap to 0 when close
                        final snapped = v.abs() < 0.3 ? 0.0 : v;
                        setState(() => _volumeDb = snapped);
                        widget.onVolumeChanged(
                          snapped == 0.0 ? null : snapped,
                        );
                      },
                    ),
                  ),
                ),
              ),
              Icon(
                Icons.volume_up_rounded,
                size: 18,
                color: cs.onSurfaceVariant.withValues(alpha:0.5),
              ),
            ],
          ),

          // Quick presets
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _QuickButton(label: '-6 dB', onTap: () => _setVolume(-6.0)),
              _QuickButton(label: '-3 dB', onTap: () => _setVolume(-3.0)),
              _QuickButton(label: '0 dB', onTap: () => _setVolume(0.0)),
              _QuickButton(label: '+3 dB', onTap: () => _setVolume(3.0)),
              _QuickButton(label: '+6 dB', onTap: () => _setVolume(6.0)),
              _QuickButton(label: '+10 dB', onTap: () => _setVolume(10.0)),
            ],
          ),

          if (_volumeDb > 10)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 14, color: Colors.orange),
                  const SizedBox(width: 4),
                  Text(
                    'converter.enhance.volumeClipWarning'.tr(),
                    style: tt.bodySmall?.copyWith(
                      color: Colors.orange,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _setVolume(double db) {
    setState(() => _volumeDb = db);
    widget.onVolumeChanged(db == 0.0 ? null : db);
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
      color: cs.surfaceContainerHighest.withValues(alpha:0.5),
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
