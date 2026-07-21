import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Fade in/out toggle + duration slider.
///
/// Controls [ConversionConfig.fadeIn], [fadeOut], and [fadeDuration].
class FadeConfigPanel extends StatefulWidget {
  final bool initialFadeIn;
  final bool initialFadeOut;
  final double? initialDuration;
  final void Function({
    required bool fadeIn,
    required bool fadeOut,
    required double? duration,
  }) onChanged;

  const FadeConfigPanel({
    super.key,
    this.initialFadeIn = true,
    this.initialFadeOut = true,
    this.initialDuration,
    required this.onChanged,
  });

  @override
  State<FadeConfigPanel> createState() => _FadeConfigPanelState();
}

class _FadeConfigPanelState extends State<FadeConfigPanel> {
  late bool _fadeIn;
  late bool _fadeOut;
  late double _duration;

  @override
  void initState() {
    super.initState();
    _fadeIn = widget.initialFadeIn;
    _fadeOut = widget.initialFadeOut;
    _duration = widget.initialDuration ?? 1.0;
  }

  void _emit() {
    widget.onChanged(
      fadeIn: _fadeIn,
      fadeOut: _fadeOut,
      duration: (_fadeIn || _fadeOut) ? _duration : null,
    );
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
            'converter.enhance.fadeConfig'.tr(),
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),

          // Fade In / Fade Out toggles
          Row(
            children: [
              Expanded(
                child: _ToggleChip(
                  label: 'converter.enhance.fadeIn'.tr(),
                  icon: Icons.arrow_forward_rounded,
                  isSelected: _fadeIn,
                  onTap: () {
                    setState(() => _fadeIn = !_fadeIn);
                    _emit();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ToggleChip(
                  label: 'converter.enhance.fadeOut'.tr(),
                  icon: Icons.arrow_back_rounded,
                  isSelected: _fadeOut,
                  onTap: () {
                    setState(() => _fadeOut = !_fadeOut);
                    _emit();
                  },
                ),
              ),
            ],
          ),

          if (_fadeIn || _fadeOut) ...[
            const SizedBox(height: 12),

            // Duration slider
            Row(
              children: [
                Text(
                  'converter.enhance.fadeDuration'.tr(),
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${_duration.toStringAsFixed(1)}s',
                    style: tt.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 28,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14),
                ),
                child: Slider(
                  value: _duration,
                  min: 0.5,
                  max: 5.0,
                  divisions: 18, // 0.25s steps
                  onChanged: (v) {
                    final rounded = (v * 4).round() / 4; // 0.25 steps
                    setState(() => _duration = rounded);
                    _emit();
                  },
                ),
              ),
            ),

            // Quick presets
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _DurationButton(
                    label: '0.5s', onTap: () => _setDuration(0.5)),
                _DurationButton(label: '1s', onTap: () => _setDuration(1.0)),
                _DurationButton(label: '2s', onTap: () => _setDuration(2.0)),
                _DurationButton(label: '3s', onTap: () => _setDuration(3.0)),
                _DurationButton(label: '5s', onTap: () => _setDuration(5.0)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _setDuration(double d) {
    setState(() => _duration = d);
    _emit();
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: isSelected
          ? cs.primary.withValues(alpha: 0.15)
          : cs.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DurationButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DurationButton({required this.label, required this.onTap});

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
